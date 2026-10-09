import Foundation

/// How AI players spend an interlude: which exam to sit, where the skill points go.
/// Rule AI players decide by rule; LLM players are asked (and fall back to the rule).
public enum RunAI {

    /// The skills a player leans toward: certificates held, then ranks, then their temperament.
    static func preference(_ p: RunPlayer, _ library: [CertificateDef]) -> [String] {
        var score: [String: Double] = [:]
        for s in Progression.trainable { score[s] = 0 }
        for r in p.certs { if let c = library.first(where: { $0.id == r.id }) { score[c.skill, default: 0] += 2 } }
        for (k, v) in p.ranks { score[k, default: 0] += Double(v) * 1.5 }
        for (k, v) in p.practice { score[k, default: 0] += Double(v) / 20 }
        switch p.persona.temperament {
        case "warm": score["medical", default: 0] += 1.2
        case "bold": score["survival", default: 0] += 1.2
        case "shrewd": score["technical", default: 0] += 1.2
        case "steady": score["navigation", default: 0] += 1.0
        case "anxious": score["medical", default: 0] += 0.8
        case "wry": score["social", default: 0] += 1.0
        default: break
        }
        // a stable tie-break per player
        var h: UInt64 = 1469598103934665603
        for b in p.id.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        for (i, s) in Progression.trainable.enumerated() { score[s, default: 0] += Double((h >> UInt64(i * 7)) & 15) / 100 }
        return Progression.trainable.sorted { (score[$0] ?? 0) > (score[$1] ?? 0) }
    }

    /// Rule: the eligible certificate that best fits the player (medical/survival first, they keep people alive).
    public static func chooseExam(_ run: EndlessRun, _ playerId: String, _ library: [CertificateDef]) -> String? {
        guard let p = run.player(playerId) else { return nil }
        let options = run.eligible(playerId, library)
        guard !options.isEmpty else { return nil }
        let pref = preference(p, library)
        func value(_ c: CertificateDef) -> Double {
            var v = 0.0
            if let i = pref.firstIndex(of: c.skill) { v += Double(5 - i) }
            if c.skill == "medical" || c.skill == "survival" { v += 1.5 }
            if c.perk != nil { v += 0.8 }
            if p.certBonus(c.skill, library) >= Progression.certCapPerSkill { v -= 3 }   // no more skill to gain
            // failed it before: a little less keen
            v -= Double(p.exams.filter { $0.certId == c.id && !$0.passed }.count) * 0.7
            return v
        }
        return options.max { a, b in value(a) == value(b) ? a.id > b.id : value(a) < value(b) }?.id
    }

    /// Rule: spend all points on the favourite skills, cheapest useful rank first.
    public static func allocate(_ p: inout RunPlayer, _ library: [CertificateDef]) {
        let pref = preference(p, library)
        var guardCount = 0
        while p.points > 0 && guardCount < 30 {
            guardCount += 1
            // favourite skill that can still go up and isn't already capped by certificates + ranks
            guard let s = pref.first(where: { p.canRaise($0) }) else { break }
            p.raise(s)
        }
    }

    // MARK: LLM players

    public static func planSystem(_ lang: Lang) -> String {
        Loc.pick("""
        你是《绝境》无尽模式里的一名玩家（由你这个大模型扮演）。在关与关之间，你可以考一张资格证、分配技能点。
        只输出一个 JSON 对象（json 格式），不要任何其他文字，不要代码块。
        """, """
        You are a player in Brink's endless mode (you, the AI model, are the player). Between chapters you may sit one certificate exam and spend skill points.
        Output a single JSON object (json format) and nothing else — no other text, no code fences.
        """, lang)
    }

    public static func planPrompt(_ run: EndlessRun, _ playerId: String, _ library: [CertificateDef]) -> String {
        let lang = run.lang
        let L = run.L
        guard let p = run.player(playerId) else { return "" }
        var out: [String] = []
        out.append(L("你是玩家「\(p.name)」（\(Personas.temperamentName(p.persona.temperament, lang))）：Lv\(p.level)，心力 \(p.resolve)/\(p.maxResolve)，未用技能点 \(p.points)。",
                     "You are the player \"\(p.name)\" (\(Personas.temperamentName(p.persona.temperament, lang))): Lv \(p.level), resolve \(p.resolve)/\(p.maxResolve), unspent skill points \(p.points)."))
        out.append(L("规则：每关你会扮演场景里的一个人；你的加点和资格证会加到那个人的技能上（实际技能上限 5）。体能属于身体，不能加点。",
                     "Rules: each chapter you play one of the scenario's people; your ranks and certificates are added to that person's skills (capped at 5). Strength belongs to the body and can't be trained."))
        out.append(L("技能加点（每项最多 +3；下一级的花费 = 下一级的级数）：", "Skill ranks (max +3 each; the next rank costs its own number in points):"))
        for s in Progression.trainable {
            let r = p.rank(s)
            out.append("  - \(s) (\(Skill.name(s, lang))): +\(r)\(r < Progression.maxRank ? L("，下一级要 \(r + 1) 点", ", next rank costs \(r + 1)") : L("（已满）", " (maxed)"))")
        }
        let held = p.certs.compactMap { r in library.first { $0.id == r.id }?.name(lang) }
        out.append(L("已有资格证：\(held.isEmpty ? "无" : held.joined(separator: "、"))", "Certificates held: \(held.isEmpty ? "none" : held.joined(separator: ", "))"))
        let elig = run.eligible(playerId, library)
        if run.examUsed(playerId) || elig.isEmpty {
            out.append(L("这次不能再考试了。", "You can't sit an exam this time."))
        } else {
            out.append(L("这次可以考（资格认证：20 题，大多是考官级难题，对 19 题才算通过；通过 +2 技能点和经验，对应技能 +1）：", "You can sit one of these (certification: 20 questions, mostly examiner-level, 19 to pass; a pass gives +2 skill points, XP, and +1 to its skill):"))
            for c in elig {
                let failed = p.exams.filter { $0.certId == c.id && !$0.passed }.count
                out.append("  - \(c.id): \(c.text(lang).full) — \(c.effectText(lang))\(failed > 0 ? L("（之前没考过 \(failed) 次）", " (failed \(failed)×)") : "")")
            }
        }
        let next = run.nextChoices.compactMap { id in id == EndlessRun.finaleId ? L("终章", "the finale") : nil }
        if !next.isEmpty { out.append(L("下一关就是终章：这一次不是推演。", "The next chapter is the finale: this time it is not a drill.")) }
        if let last = p.history.last {
            out.append(L("上一关你演\(last.characterName)（《\(last.scenarioTitle)》）：\(last.survived ? "活了下来" : last.fate)。",
                         "Last chapter you played \(last.characterName) (\(last.scenarioTitle)): \(last.survived ? "survived" : last.fate)."))
        }
        out.append("")
        let hasLast = p.history.last != nil
        out.append(L("""
        决定：考哪张证（或者不考），技能点怎么分（总数不超过你的未用点数，按花费计算），再说一句话（有个性）\(hasLast ? "，并写下上一关学到的一个教训（会记进你以后每一关的记忆里）" : "")。格式：
        {"exam": "证书 id 或 none", "ranks": {"medical": 1, "survival": 0}, "say": "一句话"\(hasLast ? ", \"lesson\": \"一句话的教训\"" : "")}
        ranks 里写每项要升几级。
        """, """
        Decide: which certificate to sit (or none), how to spend your points (total cost within your unspent points), and say one sentence (in character)\(hasLast ? ", and write down one lesson from the last chapter (it goes into your memory for every chapter after this)" : ""). Format:
        {"exam": "certificate id or none", "ranks": {"medical": 1, "survival": 0}, "say": "one sentence"\(hasLast ? ", \"lesson\": \"a one-sentence lesson\"" : "")}
        In ranks, give how many ranks to add to each skill.
        """))
        return out.joined(separator: "\n")
    }

    /// Applies an LLM's plan; whatever it couldn't afford is left as points. Returns (exam id, words).
    public static func applyPlan(_ obj: [String: Any], to p: inout RunPlayer, eligible: [String]) -> (exam: String?, say: String?) {
        if let r = obj["ranks"] as? [String: Any] {
            for s in Progression.trainable {
                let n = (r[s] as? Int) ?? Int((r[s] as? Double) ?? 0) + (Int((r[s] as? String ?? "").trimmingCharacters(in: .whitespaces)) ?? 0)
                for _ in 0..<max(0, min(3, n)) where p.canRaise(s) { p.raise(s) }
            }
        }
        var exam: String?
        if let e = (obj["exam"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), eligible.contains(e) { exam = e }
        if let lesson = (obj["lesson"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !lesson.isEmpty {
            var l = p.lessons ?? []
            l.append(String(lesson.prefix(120)))
            p.lessons = Array(l.suffix(6))
        }
        let say = (obj["say"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (exam, say?.isEmpty == true ? nil : say)
    }

    /// Rule AI players' whole interlude (also used by the CLI and as the LLM fallback).
    public static func ruleInterlude(_ run: inout EndlessRun, _ playerId: String, _ library: [CertificateDef], includeHuman: Bool = false) {
        guard let p = run.player(playerId), !p.out, includeHuman || !p.isHuman else { return }
        if !run.examUsed(playerId), let certId = chooseExam(run, playerId, library), let cert = library.first(where: { $0.id == certId }) {
            let record = ruleExam(run, p, cert)
            run.recordExam(playerId, record, library: library)
        }
        run.update(playerId) { allocate(&$0, library) }
    }

    public static func ruleExam(_ run: EndlessRun, _ p: RunPlayer, _ cert: CertificateDef) -> ExamRecord {
        let paperSeed = paperSeed(run, p, cert)
        let paper = Exams.drawCertification(cert, seed: paperSeed)
        let answers = Exams.ruleAnswers(paper, cert, level: p.level, skillRank: p.rank(cert.skill), seed: paperSeed ^ 0xA11)
        let score = Exams.grade(paper, cert, answers: answers)
        return ExamRecord(certId: cert.id, interlude: run.interlude, score: score, total: paper.total, passed: score >= paper.pass(cert), by: "rule", answers: answers, paper: paper, note: nil)
    }

    /// The paper a player gets for a certificate in this interlude (same seed → same paper).
    /// The certification paper a player gets for a certificate in this interlude (same seed → same paper).
    public static func paper(_ run: EndlessRun, _ p: RunPlayer, _ cert: CertificateDef) -> ExamPaper {
        Exams.drawCertification(cert, seed: paperSeed(run, p, cert))
    }

    /// Same run, interlude, player and certificate → same paper (stable across launches).
    static func paperSeed(_ run: EndlessRun, _ p: RunPlayer, _ cert: CertificateDef) -> UInt64 {
        EndlessRun.mix(run.seed, UInt64(run.interlude) &* 1_000_003 &+ EndlessRun.stableHash(p.id + "/" + cert.id))
    }
}
