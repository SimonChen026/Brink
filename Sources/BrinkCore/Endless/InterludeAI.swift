import Foundation
import Observation

/// Runs the AI players' interlude: LLM players are asked what to sit and how to spend their points,
/// then actually answer the exam; rule AI players decide by rule. Results are applied one player
/// at a time to the live run (the human may be busy with their own exam at the same moment).
@MainActor
@Observable
public final class InterludeAI {
    public private(set) var running = false
    /// player id → what they're doing / how it went (in the run's language)
    public private(set) var status: [String: String] = [:]
    /// player id → the exam just sat (for the hub's result chips)
    public private(set) var results: [String: ExamRecord] = [:]
    public private(set) var calls: [LLMCallRecord] = []

    @ObservationIgnored private let client = LLMClient(timeout: 120)

    public init() {}

    public func reset() {
        status = [:]
        results = [:]
    }

    /// `apply` receives a mutation for the live run.
    public func perform(_ snapshot: EndlessRun, config: AppConfig, library: [CertificateDef], apply: @escaping @MainActor ((inout EndlessRun) -> Void) -> Void) async {
        guard !running else { return }
        running = true
        defer { running = false }
        let L = snapshot.L
        // players who already sat this break's exam (e.g. after "Continue" back into the camp) are done
        let ai = snapshot.active.filter { !$0.isHuman && !snapshot.examUsed($0.id) }
        await withTaskGroup(of: Void.self) { group in
            for p in ai {
                group.addTask { @MainActor in
                    if p.isLLM, let ref = ModelRef(seatId: p.seat), let profile = config.provider(ref.providerId) {
                        await self.llmInterlude(snapshot, p, ref: ref, profile: profile, label: config.label(for: ref), library: library, apply: apply)
                    } else {
                        apply { run in RunAI.ruleInterlude(&run, p.id, library) }
                        if let r = self.lastExam(p.id, snapshot.interlude, apply: apply) { self.results[p.id] = r }
                        self.status[p.id] = self.results[p.id].map { r in self.describe(r, snapshot.lang) } ?? L("没有可考的证", "Nothing to sit")
                    }
                }
            }
        }
    }

    private func lastExam(_ id: String, _ interlude: Int, apply: @MainActor ((inout EndlessRun) -> Void) -> Void) -> ExamRecord? {
        var found: ExamRecord?
        apply { run in found = run.player(id)?.exams.last { $0.interlude == interlude } }
        return found
    }

    public func describe(_ r: ExamRecord, _ lang: Lang) -> String {
        let name = ExamLibrary.cert(r.certId)?.name(lang) ?? r.certId
        if r.by == "absent" { return Loc.pick("缺考：\(name)", "Missed: \(name)", lang) }
        return r.passed ? Loc.pick("通过「\(name)」\(r.score)/\(r.total)", "Passed \(name) \(r.score)/\(r.total)", lang)
                        : Loc.pick("没过「\(name)」\(r.score)/\(r.total)", "Failed \(name) \(r.score)/\(r.total)", lang)
    }

    private func llmInterlude(_ snapshot: EndlessRun, _ p: RunPlayer, ref: ModelRef, profile: ProviderProfile, label: String, library: [CertificateDef],
                              apply: @escaping @MainActor ((inout EndlessRun) -> Void) -> Void) async {
        let lang = snapshot.lang
        let L = snapshot.L
        status[p.id] = L("在想考什么……", "Thinking it over…")
        // 1. plan
        let eligible = snapshot.examUsed(p.id) ? [] : snapshot.eligible(p.id, library).map(\.id)
        var examId: String?
        var words: String?
        if let obj = await ask(p, ref: ref, profile: profile, label: label, lang: lang, system: RunAI.planSystem(lang), user: RunAI.planPrompt(snapshot, p.id, library), phase: L("考证", "Exams")) {
            var copy = p
            let (e, say) = RunAI.applyPlan(obj, to: &copy, eligible: eligible)
            examId = e
            words = say
            let ranks = copy.ranks, points = copy.points, lessons = copy.lessons
            apply { run in run.update(p.id) { $0.ranks = ranks; $0.points = points; $0.lastWords = say; $0.lessons = lessons } }
        } else {
            examId = snapshot.examUsed(p.id) ? nil : RunAI.chooseExam(snapshot, p.id, library)
        }
        // whatever points are left: by rule
        apply { run in run.update(p.id) { RunAI.allocate(&$0, library) } }
        guard let certId = examId, let cert = library.first(where: { $0.id == certId }) else {
            status[p.id] = words.map { "“\($0)”" } ?? L("这次不考", "Not sitting an exam")
            return
        }
        // 2. the exam itself
        status[p.id] = L("正在考「\(cert.name(lang))」……", "Sitting \(cert.name(lang))…")
        let paper = RunAI.paper(snapshot, p, cert)
        var record: ExamRecord
        if let obj = await ask(p, ref: ref, profile: profile, label: label, lang: lang, system: Exams.systemPrompt(lang), user: Exams.userPrompt(paper, cert, playerName: p.name, lang), phase: L("考试", "Exam")) {
            let (answers, comment) = Exams.parseAnswers(obj, count: paper.total)
            let score = Exams.grade(paper, cert, answers: answers)
            record = ExamRecord(certId: cert.id, interlude: snapshot.interlude, score: score, total: paper.total, passed: score >= paper.pass(cert), by: "llm", answers: answers, paper: paper, note: comment)
        } else {
            record = ExamRecord(certId: cert.id, interlude: snapshot.interlude, score: 0, total: paper.total, passed: false, by: "absent", answers: nil, paper: paper, note: L("调用失败，缺考", "The call failed — missed the exam"))
        }
        let rec = record
        apply { run in run.recordExam(p.id, rec, library: library) }
        if rec.passed { apply { run in run.update(p.id) { RunAI.allocate(&$0, library) } } }
        results[p.id] = rec
        status[p.id] = describe(rec, lang)
        if rec.by == "llm" {
            var store = ModelStatsStore.load()
            store.recordExam(key: label, record: rec)
            store.save()
        }
    }

    private func ask(_ p: RunPlayer, ref: ModelRef, profile: ProviderProfile, label: String, lang: Lang, system: String, user: String, phase: String) async -> [String: Any]? {
        let reasoning = ["reasoner", "thinking", "r1", "qwq", "o1", "o3", "o4", "gpt-5", "glm-4.5", "glm-4.6", "glm-z1", "qwen3", "k2-thinking"].contains { ref.model.lowercased().contains($0) }
        var prompt = user
        for attempt in 0..<2 {
            do {
                let r = try await client.complete(profile: profile, model: ref.model, system: system, user: prompt, jsonMode: true, maxTokens: reasoning ? 8000 : 2000, temperature: profile.temperature)
                calls.append(LLMCallRecord(character: p.name, model: label, phase: phase, round: 0, prompt: String(prompt.suffix(1500)), response: r.text, seconds: r.seconds, inputTokens: r.inputTokens, outputTokens: r.outputTokens, error: nil))
                if let obj = JSONExtract.object(from: r.text) { return obj }
                if attempt == 0 {
                    prompt = user + Loc.pick("\n\n（注意：你上一次的回答不是合法的 JSON。这一次只输出一个 JSON 对象。）", "\n\n(Note: your last answer was not valid json. This time output a single JSON object only.)", lang)
                }
            } catch {
                calls.append(LLMCallRecord(character: p.name, model: label, phase: phase, round: 0, prompt: String(prompt.suffix(1500)), response: "", seconds: 0, inputTokens: 0, outputTokens: 0, error: Redact.text("\(error)")))
                if let e = error as? LLMError, let st = e.status, [401, 403, 404].contains(st) { return nil }
            }
        }
        return nil
    }
}
