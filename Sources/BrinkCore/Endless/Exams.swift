import Foundation

// MARK: - Certificates and question banks

/// Display text of a certificate in one language.
public struct CertText: Codable, Sendable {
    public var name: String
    public var full: String
    public var desc: String
    public var realWorld: String
}

/// One question of a bank. Both languages share the option order and the answer index.
public struct ExamQuestion: Codable, Sendable, Identifiable {
    public var id: String
    public var answer: Int
    public var hard: Bool?
    /// Instructor-level questions; certification papers are built mostly from these (D-042).
    public var expert: Bool?
    public var source: String?
    public var zh: QText
    public var en: QText

    public func text(_ lang: Lang) -> QText { lang == .en ? en : zh }
}

public struct QText: Codable, Sendable {
    public var q: String
    public var options: [String]
    public var explain: String
}

/// A certificate: what it gives, who may sit it, and its question bank.
/// Files: `Resources/Exams/<id>.json` (both languages inline, see D-037).
public struct CertificateDef: Codable, Sendable, Identifiable {
    public var id: String
    /// The skill it adds to (+bonus, at most +2 per skill from certificates).
    public var skill: String
    public var bonus: Int
    /// Know-how carried into every role: "warm" | "wet" | "water" | "calm".
    public var perk: String?
    public var requires: [String]
    public var minLevel: Int
    /// Questions per exam, and how many must be right.
    public var count: Int
    public var pass: Int
    public var icon: String
    public var color: String
    public var zh: CertText
    public var en: CertText
    public var questions: [ExamQuestion]

    public func text(_ lang: Lang) -> CertText { lang == .en ? en : zh }
    public func name(_ lang: Lang) -> String { text(lang).name }
    public func question(_ id: String) -> ExamQuestion? { questions.first { $0.id == id } }

    /// What holding it does, in one line ("Medical +1 · keeps warm: clothing +0.3 clo").
    public func effectText(_ lang: Lang) -> String {
        var parts = [Loc.pick("\(Skill.name(skill, lang)) +\(bonus)", "\(Skill.name(skill, lang)) +\(bonus)", lang)]
        if let perk { parts.append(Perks.describe(perk, lang)) }
        return parts.joined(separator: " · ")
    }
}

/// Know-how that a certificate carries into every role (engine hooks: Physiology / morale).
public enum Perks {
    public static let all = ["warm", "wet", "water", "calm"]

    public static func name(_ p: String, _ lang: Lang) -> String {
        switch p {
        case "warm": return Loc.pick("保暖有方", "Dresses for the cold", lang)
        case "wet": return Loc.pick("湿冷不慌", "Steady in cold water", lang)
        case "water": return Loc.pick("惜汗如金", "Rations sweat", lang)
        case "calm": return Loc.pick("临危不乱", "Keeps a cool head", lang)
        default: return p
        }
    }

    public static func describe(_ p: String, _ lang: Lang) -> String {
        switch p {
        case "warm": return Loc.pick("保暖有方：衣物保温 +0.3 clo（会分层、垫地、保持干燥）", "Dresses for the cold: clothing +0.3 clo (layers, insulation underneath, staying dry)", lang)
        case "wet": return Loc.pick("湿冷不慌：衣服湿透时保暖下降少一半（HELP 姿势、少动）", "Steady in cold water: being soaked costs half as much warmth (HELP position, keeping still)", lang)
        case "water": return Loc.pick("惜汗如金：出汗和呼吸失水 −12%（白天躲阴、慢动作）", "Rations sweat: 12% less water lost (shade by day, moving slowly)", lang)
        case "calm": return Loc.pick("临危不乱：士气下降少 25%，心力上限 +1", "Keeps a cool head: morale falls 25% less, +1 maximum resolve", lang)
        default: return p
        }
    }
}

public enum ExamLibrary {
    nonisolated(unsafe) private static var cache: [CertificateDef]?
    private static let lock = NSLock()

    /// Display order of the certificates.
    public static let order = ["firstaid", "wfr", "survival", "cold", "sea", "flood", "desert", "navigation", "radio", "mine", "usar", "psych"]

    public static func directory() -> URL? {
        if let url = Bundle.main.url(forResource: "Exams", withExtension: nil) { return url }
        if let url = Bundle.module.url(forResource: "Exams", withExtension: nil) { return url }
        return nil
    }

    /// All certificates (cached). Files that fail to load are skipped (see `loadReport`).
    public static func all() -> [CertificateDef] {
        lock.lock(); defer { lock.unlock() }
        if let c = cache { return c }
        let loaded = load().certs
        cache = loaded
        return loaded
    }

    public static func cert(_ id: String) -> CertificateDef? { all().first { $0.id == id } }

    /// Loads every bank; returns the certificates and the files that failed.
    public static func load(from dir: URL? = nil) -> (certs: [CertificateDef], errors: [String]) {
        guard let dir = dir ?? directory(),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return ([], [Loc.pick("找不到题库目录", "Exam folder not found", Loc.ui)]) }
        var out: [CertificateDef] = []
        var errors: [String] = []
        for f in files where f.pathExtension == "json" {
            do {
                let c = try JSONDecoder().decode(CertificateDef.self, from: Data(contentsOf: f))
                out.append(c)
            } catch {
                errors.append("\(f.lastPathComponent): \(error)")
            }
        }
        out.sort { (order.firstIndex(of: $0.id) ?? 99, $0.id) < (order.firstIndex(of: $1.id) ?? 99, $1.id) }
        return (out, errors)
    }

    /// Problems with a bank (used by `brink-cli exam-check` and the tests).
    public static func check(_ c: CertificateDef) -> [String] {
        var errs: [String] = []
        if c.questions.count < c.count { errs.append("\(c.id): \(c.questions.count) questions, an exam needs \(c.count)") }
        if !Skill.all.contains(c.skill) { errs.append("\(c.id): unknown skill \(c.skill)") }
        if let p = c.perk, !Perks.all.contains(p) { errs.append("\(c.id): unknown perk \(p)") }
        var ids: Set<String> = []
        for q in c.questions {
            if ids.contains(q.id) { errs.append("\(q.id): duplicate id") }
            ids.insert(q.id)
            if !(0..<4).contains(q.answer) { errs.append("\(q.id): answer out of range") }
            for (lang, t) in [("zh", q.zh), ("en", q.en)] {
                if t.options.count != 4 { errs.append("\(q.id).\(lang): \(t.options.count) options") }
                if t.q.isEmpty || t.explain.isEmpty { errs.append("\(q.id).\(lang): empty text") }
            }
            if Loc.hasCJK(q.en.q + q.en.explain + q.en.options.joined()) { errs.append("\(q.id).en: Chinese in the English text") }
        }
        return errs
    }
}

// MARK: - Sitting an exam

/// A drawn exam: which questions, with the options in which order.
public struct ExamPaper: Codable, Sendable {
    public var certId: String
    public var items: [PaperItem]
    /// Correct answers needed (nil in papers saved before certification exams: the certificate's own pass mark).
    public var passMark: Int?
    /// Seconds per question for a human candidate (nil = no limit).
    public var timeLimit: Int?
    /// A certification paper (vs. practice).
    public var certification: Bool?

    public var total: Int { items.count }
    public func pass(_ cert: CertificateDef) -> Int { passMark ?? cert.pass }
    public var isCertification: Bool { certification ?? false }
}

public struct PaperItem: Codable, Sendable {
    public var questionId: String
    /// order[i] = index (in the bank) of the option shown at position i.
    public var order: [Int]
}

/// The result of one sitting.
public struct ExamRecord: Codable, Sendable {
    public var certId: String
    /// Interlude the exam was taken in (one attempt per interlude).
    public var interlude: Int
    public var score: Int
    public var total: Int
    public var passed: Bool
    /// "human" | "llm" | "rule"
    public var by: String
    /// The answers given (shown positions, nil = no answer).
    public var answers: [Int?]?
    public var paper: ExamPaper?
    /// LLM players: what they said about it / why the call failed.
    public var note: String?

    public var perfect: Bool { passed && score == total }

    public init(certId: String, interlude: Int, score: Int, total: Int, passed: Bool, by: String, answers: [Int?]?, paper: ExamPaper?, note: String?) {
        self.certId = certId
        self.interlude = interlude
        self.score = score
        self.total = total
        self.passed = passed
        self.by = by
        self.answers = answers
        self.paper = paper
        self.note = note
    }
}

public enum Exams {
    public static let letters = ["A", "B", "C", "D"]

    // Certification (D-042): 20 questions, mostly expert and hard, 19 to pass, 40 s per question,
    // and in the exam room a 12-hour wait after a failed attempt at the same certificate.
    public static let certCount = 20
    public static let certPass = 19
    public static let certTimeLimit = 40
    public static let cooldownHours = 12.0

    /// A certification paper: 8 expert + 8 hard + 4 others (topped up from the next pool when a bank runs short).
    public static func drawCertification(_ cert: CertificateDef, seed: UInt64) -> ExamPaper {
        var rng = SeededRNG(seed: seed ^ 0xCE47)
        var expert = rng.shuffled(cert.questions.filter { $0.expert ?? false })
        var hard = rng.shuffled(cert.questions.filter { ($0.hard ?? false) && !($0.expert ?? false) })
        var normal = rng.shuffled(cert.questions.filter { !($0.hard ?? false) })
        let n = min(certCount, cert.questions.count)
        var picked: [ExamQuestion] = []
        func take(_ pool: inout [ExamQuestion], _ k: Int) {
            let m = min(k, pool.count)
            picked += pool.prefix(m)
            pool.removeFirst(m)
        }
        take(&expert, 8)
        take(&hard, 8 + (8 - min(8, picked.count)))
        take(&normal, n - picked.count)
        take(&hard, n - picked.count)
        take(&expert, n - picked.count)
        picked = rng.shuffled(picked)
        let items = picked.map { q in PaperItem(questionId: q.id, order: rng.shuffled(Array(0..<q.zh.options.count))) }
        let pass = max(1, Int((Double(certPass) / Double(certCount) * Double(items.count)).rounded(.up)))
        return ExamPaper(certId: cert.id, items: items, passMark: pass, timeLimit: certTimeLimit, certification: true)
    }

    /// A practice paper: `cert.count` questions (at least 4 hard ones when the bank has them), options shuffled.
    public static func draw(_ cert: CertificateDef, seed: UInt64) -> ExamPaper {
        var rng = SeededRNG(seed: seed)
        let hard = rng.shuffled(cert.questions.filter { $0.hard ?? false })
        let easy = rng.shuffled(cert.questions.filter { !($0.hard ?? false) })
        let n = min(cert.count, cert.questions.count)
        // practice papers got harder too: at least 4 of 10 hard (the expert ones count as hard)
        let wantHard = min(hard.count, max(4, n * 4 / 10))
        var picked = Array(hard.prefix(wantHard))
        picked += easy.prefix(max(0, n - picked.count))
        if picked.count < n { picked += hard.dropFirst(wantHard).prefix(n - picked.count) }
        picked = rng.shuffled(picked)
        let items = picked.map { q in PaperItem(questionId: q.id, order: rng.shuffled(Array(0..<q.zh.options.count))) }
        return ExamPaper(certId: cert.id, items: items, passMark: cert.pass, timeLimit: nil, certification: false)
    }

    /// Position of the right option in a drawn item.
    public static func correctPosition(_ item: PaperItem, _ cert: CertificateDef) -> Int {
        guard let q = cert.question(item.questionId) else { return 0 }
        return item.order.firstIndex(of: q.answer) ?? 0
    }

    public static func grade(_ paper: ExamPaper, _ cert: CertificateDef, answers: [Int?]) -> Int {
        var score = 0
        for (i, item) in paper.items.enumerated() where i < answers.count {
            if let a = answers[i], a == correctPosition(item, cert) { score += 1 }
        }
        return score
    }

    /// The question as shown (options in paper order).
    public static func shown(_ item: PaperItem, _ cert: CertificateDef, _ lang: Lang) -> (q: String, options: [String], explain: String, correct: Int, source: String?) {
        guard let q = cert.question(item.questionId) else { return ("?", [], "", 0, nil) }
        let t = q.text(lang)
        let opts = item.order.map { $0 < t.options.count ? t.options[$0] : "" }
        return (t.q, opts, t.explain, correctPosition(item, cert), q.source)
    }

    /// Rule AI: each question right with a probability that grows with level and the skill behind it.
    public static func ruleAnswers(_ paper: ExamPaper, _ cert: CertificateDef, level: Int, skillRank: Int, seed: UInt64) -> [Int?] {
        var rng = SeededRNG(seed: seed)
        var out: [Int?] = []
        for item in paper.items {
            let q = cert.question(item.questionId)
            let hard = q?.hard ?? false, expert = q?.expert ?? false
            var p = 0.80 + 0.02 * Double(level - 1) + 0.04 * Double(skillRank) - (expert ? 0.16 : (hard ? 0.08 : 0))
            p = min(0.98, max(0.3, p))
            let right = correctPosition(item, cert)
            if rng.chance(p) {
                out.append(right)
            } else {
                let wrong = (0..<item.order.count).filter { $0 != right }
                out.append(rng.pick(wrong) ?? right)
            }
        }
        return out
    }

    // MARK: LLM players

    public static func systemPrompt(_ lang: Lang) -> String {
        Loc.pick("""
        你正在参加一场资格考试（灾害应对训练营）。每道题四个选项，只有一个正确。按你真实的知识作答，不要猜测题目以外的信息。
        只输出一个 JSON 对象（json 格式），不要任何其他文字，不要代码块。
        """, """
        You are sitting a certification exam (disaster response training). Each question has four options and exactly one is correct. Answer from what you actually know.
        Output a single JSON object (json format) and nothing else — no other text, no code fences.
        """, lang)
    }

    public static func userPrompt(_ paper: ExamPaper, _ cert: CertificateDef, playerName: String, _ lang: Lang) -> String {
        var out: [String] = []
        let t = cert.text(lang)
        out.append(Loc.pick("考生：\(playerName)\n科目：\(t.full)（\(t.desc)）\n共 \(paper.total) 题，答对 \(paper.pass(cert)) 题及格\(paper.isCertification ? "（资格认证，题目大多是考官级难题）" : "")。",
                            "Candidate: \(playerName)\nExam: \(t.full) (\(t.desc))\n\(paper.total) questions; \(paper.pass(cert)) correct to pass\(paper.isCertification ? " (certification: most questions are examiner-level)" : "").", lang))
        for (i, item) in paper.items.enumerated() {
            let s = shown(item, cert, lang)
            out.append("")
            out.append("\(i + 1). \(s.q)")
            for (j, o) in s.options.enumerated() { out.append("   \(letters[j]). \(o)") }
        }
        out.append("")
        out.append(Loc.pick("""
        按题号顺序给出答案（字母 A–D），再用一句话说说这场考试对你来说怎么样（可以有个性）。格式：
        {"answers": ["B", "D", ...], "comment": "一句话"}
        """, """
        Give your answers in question order (letters A–D), plus one sentence on how the exam went for you (feel free to have a personality). Format:
        {"answers": ["B", "D", ...], "comment": "one sentence"}
        """, lang))
        return out.joined(separator: "\n")
    }

    /// Parses `{"answers": ["A", …]}` (letters, numbers 1–4 or option text) into shown positions.
    public static func parseAnswers(_ obj: [String: Any], count: Int) -> (answers: [Int?], comment: String?) {
        var raw: [Any] = []
        if let a = obj["answers"] as? [Any] { raw = a } else if let a = obj["answer"] as? [Any] { raw = a }
        var out: [Int?] = []
        for i in 0..<count {
            guard i < raw.count else { out.append(nil); continue }
            out.append(position(raw[i]))
        }
        let comment = (obj["comment"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (out, comment?.isEmpty == true ? nil : comment)
    }

    static func position(_ v: Any) -> Int? {
        if let n = v as? Int { return (1...4).contains(n) ? n - 1 : ((0...3).contains(n) ? n : nil) }
        guard let s = (v as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), let c = s.first else { return nil }
        if let i = letters.firstIndex(of: String(c)) { return i }
        if let n = Int(String(c)), (1...4).contains(n) { return n - 1 }
        return nil
    }
}
