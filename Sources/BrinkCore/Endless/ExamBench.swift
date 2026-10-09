import Foundation
import Observation

/// Has an AI model sit every certificate exam once (the exam room's "let a model take them").
/// Results go to the model leaderboard, like the exams model players sit in endless runs.
@MainActor
@Observable
public final class ExamBench {
    public private(set) var running = false
    public private(set) var model: String?
    /// certificate id → result (nil while it's being sat)
    public private(set) var results: [String: ExamRecord] = [:]
    public private(set) var current: String?
    public private(set) var error: String?

    @ObservationIgnored private let client = LLMClient(timeout: 120)
    @ObservationIgnored private var task: Task<Void, Never>?

    public init() {}

    public var correct: Int { results.values.map(\.score).reduce(0, +) }
    public var questions: Int { results.values.map(\.total).reduce(0, +) }
    public var passed: Int { results.values.filter(\.passed).count }

    public func stop() {
        task?.cancel()
        task = nil
        running = false
        current = nil
    }

    public func start(ref: ModelRef, config: AppConfig, library: [CertificateDef], lang: Lang) {
        guard !running, let profile = config.provider(ref.providerId) else { return }
        let label = config.label(for: ref)
        running = true
        model = label
        results = [:]
        error = nil
        task = Task { [weak self] in
            guard let self else { return }
            let seed = UInt64(Date().timeIntervalSince1970) % 900_000 + 1
            // the bench sits the real thing: certification papers, all at once (the client keeps
            // to each provider's own limit on parallel requests)
            let certs = library.enumerated().filter { $0.element.questions.count >= $0.element.count }.map { ($0.offset, $0.element) }
            self.current = certs.first?.1.id
            let client = self.client
            let reasoning = ["reasoner", "thinking", "r1", "qwq", "o1", "o3", "o4", "gpt-5", "glm-4.5", "glm-4.6", "glm-z1", "qwen3", "k2-thinking"].contains { ref.model.lowercased().contains($0) }
            await withTaskGroup(of: (String, ExamRecord, Bool).self) { group in
                for (i, cert) in certs {
                    group.addTask {
                        let paper = Exams.drawCertification(cert, seed: seed &+ UInt64(i * 31))
                        var rec = ExamRecord(certId: cert.id, interlude: 0, score: 0, total: paper.total, passed: false, by: "absent", answers: nil, paper: paper, note: nil)
                        var fatal = false
                        do {
                            let r = try await client.complete(profile: profile, model: ref.model, system: Exams.systemPrompt(lang),
                                                              user: Exams.userPrompt(paper, cert, playerName: label, lang), jsonMode: true,
                                                              maxTokens: reasoning ? 8000 : 2000, temperature: profile.temperature)
                            if let obj = JSONExtract.object(from: r.text) {
                                let (answers, comment) = Exams.parseAnswers(obj, count: paper.total)
                                let score = Exams.grade(paper, cert, answers: answers)
                                rec = ExamRecord(certId: cert.id, interlude: 0, score: score, total: paper.total, passed: score >= paper.pass(cert), by: "llm", answers: answers, paper: paper, note: comment)
                            } else {
                                rec.note = Loc.pick("回答不是合法的 JSON", "The answer was not valid JSON", lang)
                            }
                        } catch {
                            rec.note = Redact.text("\(error)")
                            if let e = error as? LLMError, let st = e.status, [401, 403, 404].contains(st) { fatal = true }
                        }
                        return (cert.id, rec, fatal)
                    }
                }
                for await (id, rec, fatal) in group {
                    // a stopped (or restarted) bench writes nothing more
                    if Task.isCancelled { group.cancelAll(); break }
                    self.results[id] = rec
                    if rec.by == "llm" {
                        var store = ModelStatsStore.load()
                        store.recordExam(key: label, record: rec)
                        store.save()
                    } else if let note = rec.note {
                        self.error = note
                    }
                    self.current = certs.first { self.results[$0.1.id] == nil }?.1.id
                    // a bad key or a missing model: the other papers would fail the same way
                    if fatal { group.cancelAll(); break }
                }
            }
            if Task.isCancelled { return }
            self.current = nil
            self.running = false
        }
    }
}
