import Foundation

/// The human player's own record across the whole app ("我"): certificates held, exam history.
/// Certificates are earned in certification exams (the exam room, or between chapters of a run) and
/// carried into every new endless run (D-042).
public struct PlayerProfile: Codable, Sendable {
    public struct Held: Codable, Sendable, Identifiable {
        public var id: String          // certificate id
        public var date: Date
        public var score: Int
        public var total: Int
        /// "hall" (the exam room) | "run"
        public var source: String
        /// Certificate number shown on the certificate.
        public var serial: String
    }

    public struct Attempt: Codable, Sendable, Identifiable {
        public var id = UUID()
        public var certId: String
        public var date: Date
        public var score: Int
        public var total: Int
        public var passed: Bool
        public var source: String
    }

    public var name: String?
    public var certs: [Held] = []
    public var attempts: [Attempt] = []

    public init() {}

    enum CodingKeys: String, CodingKey { case name, certs, attempts }

    /// Missing fields fall back to their defaults, so older (or newer) profiles still open.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        certs = try c.decodeIfPresent([Held].self, forKey: .certs) ?? []
        attempts = try c.decodeIfPresent([Attempt].self, forKey: .attempts) ?? []
    }

    public static var url: URL { AppPaths.support.appendingPathComponent("profile.json") }

    public static func load() -> PlayerProfile {
        guard let d = try? Data(contentsOf: url) else { return PlayerProfile() }
        guard let p = try? JSONDecoder().decode(PlayerProfile.self, from: d) else {
            // keep the certificate wall even if this version can't read it
            AppPaths.keepUnreadable(url)
            return PlayerProfile()
        }
        return p
    }

    public func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(self) { try? d.write(to: PlayerProfile.url, options: .atomic) }
    }

    public func has(_ cert: String) -> Bool { certs.contains { $0.id == cert } }
    public func held(_ cert: String) -> Held? { certs.first { $0.id == cert } }

    /// When the exam room lets you sit this certificate again (nil = now).
    public func cooldownUntil(_ cert: String, now: Date = Date()) -> Date? {
        guard let last = attempts.last(where: { $0.certId == cert && $0.source == "hall" && !$0.passed }) else { return nil }
        let until = last.date.addingTimeInterval(Exams.cooldownHours * 3600)
        return until > now ? until : nil
    }

    /// Why a certificate can't be sat in the exam room right now (nil = it can).
    public func lockReason(_ c: CertificateDef, lang: Lang, now: Date = Date()) -> String? {
        if has(c.id) { return Loc.pick("已取得", "Held", lang) }
        if let missing = c.requires.first(where: { !has($0) }) {
            let n = ExamLibrary.cert(missing)?.name(lang) ?? missing
            return Loc.pick("需要先取得「\(n)」", "Needs “\(n)” first", lang)
        }
        if let until = cooldownUntil(c.id, now: now) {
            let mins = Int(until.timeIntervalSince(now) / 60) + 1
            let t = mins >= 60 ? Loc.pick("\(mins / 60) 小时 \(mins % 60) 分", "\(mins / 60) h \(mins % 60) min", lang) : Loc.pick("\(mins) 分钟", "\(mins) min", lang)
            return Loc.pick("没通过，\(t)后才能重考", "Failed — retake in \(t)", lang)
        }
        if c.questions.count < Exams.certCount { return Loc.pick("题库还没准备好", "Question bank not ready", lang) }
        return nil
    }

    /// Records a certification sitting; a pass grants the certificate (once).
    @discardableResult
    public mutating func record(_ certId: String, score: Int, total: Int, passed: Bool, source: String, now: Date = Date()) -> Bool {
        attempts.append(Attempt(certId: certId, date: now, score: score, total: total, passed: passed, source: source))
        if attempts.count > 300 { attempts.removeFirst(attempts.count - 300) }
        guard passed, !has(certId) else { return false }
        certs.append(Held(id: certId, date: now, score: score, total: total, source: source, serial: PlayerProfile.serial(certId, now)))
        return true
    }

    static func serial(_ cert: String, _ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyMMdd"
        let h = EndlessRun.stableHash(cert + "\(date.timeIntervalSince1970)") % 100_000
        return "BRK-\(cert.prefix(3).uppercased())-\(f.string(from: date))-\(String(format: "%05d", Int(h)))"
    }
}
