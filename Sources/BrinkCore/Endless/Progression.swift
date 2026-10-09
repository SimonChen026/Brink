import Foundation

// MARK: - Rules of growth (D-036)

public enum Progression {
    /// Skills a player can train. Strength belongs to the body of the role, so it isn't trainable.
    public static let trainable = ["medical", "survival", "technical", "navigation", "social"]
    public static let maxRank = 3
    public static let skillCap = 5
    public static let certCapPerSkill = 2
    public static let baseResolve = 3

    /// XP needed to go from `level` to `level + 1`.
    public static func xpToNext(_ level: Int) -> Int { 100 * level }

    /// Total XP at which `level` begins.
    public static func xpAt(_ level: Int) -> Int { 50 * level * (level - 1) }

    public static func level(forXP xp: Int) -> Int {
        var l = 1
        while xp >= xpAt(l + 1) { l += 1 }
        return l
    }

    /// Skill points for reaching `level`.
    public static func pointsFor(level: Int) -> Int { level % 5 == 0 ? 2 : 1 }

    /// Points for the next rank (1, 2, 3).
    public static func rankCost(_ nextRank: Int) -> Int { nextRank }

    /// Practice needed for a free rank when the skill is at `rank`.
    public static func practiceNeeded(_ rank: Int) -> Int { 20 * (rank + 1) }
}

// MARK: - Players

/// A run player's own identity: used in the finale, where everyone plays themselves.
public struct Persona: Codable, Sendable {
    public var name: String
    public var female: Bool
    public var age: Int
    public var weight: Double
    public var fat: Double
    /// Temperament key (see Personas): colours how they're described and how a rule AI plays them.
    public var temperament: String

    public init(name: String, female: Bool, age: Int, weight: Double, fat: Double, temperament: String) {
        self.name = name
        self.female = female
        self.age = age
        self.weight = weight
        self.fat = fat
        self.temperament = temperament
    }
}

public struct CertRecord: Codable, Sendable {
    public var id: String
    public var interlude: Int
    public var score: Int
    public var total: Int
}

/// One line of the XP breakdown after a chapter.
public struct XPItem: Codable, Sendable {
    public var label: String
    public var xp: Int
}

/// What a chapter meant for one player.
public struct PlayerChapter: Codable, Sendable {
    public var chapter: Int
    public var scenarioId: String
    public var scenarioTitle: String
    public var characterId: String
    public var characterName: String
    public var survived: Bool
    /// CharStatus raw value at the end.
    public var status: String
    public var fate: String
    public var deathCause: String?
    public var goalAchieved: Bool
    public var xp: Int
    public var breakdown: [XPItem]
    public var levelBefore: Int
    public var levelAfter: Int
    public var resolveBefore: Int
    public var resolveAfter: Int
    /// Practice points gained per skill, and the skills that went up for free.
    public var practice: [String: Int]
    public var freeRanks: [String]
    public var cared: Int
    public var thefts: Int
    public var caught: Int
    public var led: Int
    public var finale: Bool
}

public struct PlayerTotals: Codable, Sendable {
    public var chapters = 0
    public var survived = 0
    public var deaths = 0
    public var exiled = 0
    public var goals = 0
    public var cared = 0
    public var thefts = 0
    public var caught = 0
    public var led = 0
    public var examsTaken = 0
    public var examsPassed = 0
    public init() {}
}

/// A seat in an endless run: the human, an LLM player or a rule AI player.
public struct RunPlayer: Codable, Sendable, Identifiable {
    public var id: String
    public var persona: Persona
    /// "human" | "rule" | a ModelRef id
    public var seat: String
    /// Display label of the controller ("Player", "Rule AI", "DeepSeek · deepseek-chat").
    public var controllerLabel: String
    /// The label as shown: saves from before the rename still say "规则AI" / "Rule AI" for the basic bots.
    public var shownController: String {
        switch controllerLabel {
        case "规则AI", "规则 AI": return "基础人机"
        case "Rule AI": return "Basic bot"
        default: return controllerLabel
        }
    }
    public var xp: Int = 0
    public var level: Int = 1
    public var points: Int = 0
    public var ranks: [String: Int] = [:]
    public var practice: [String: Int] = [:]
    public var certs: [CertRecord] = []
    public var resolve: Int
    public var out: Bool = false
    public var outChapter: Int?
    public var joinedChapter: Int
    public var exams: [ExamRecord] = []
    public var history: [PlayerChapter] = []
    public var totals = PlayerTotals()
    /// What an LLM player said in the last interlude (shown in the hub).
    public var lastWords: String?
    /// Ranks bought since the last chapter (only these can be taken back).
    public var refundable: [String: Int]?
    /// LLM players: lessons they wrote down after chapters (fed back into their career memory).
    public var lessons: [String]?

    public var isHuman: Bool { seat == "human" }
    public var isLLM: Bool { seat != "human" && seat != "rule" }
    public var name: String { persona.name }

    public func rank(_ skill: String) -> Int { ranks[skill] ?? 0 }
    public func has(_ cert: String) -> Bool { certs.contains { $0.id == cert } }

    public var maxResolve: Int { Progression.baseResolve + (has("psych") ? 1 : 0) }

    /// Skill bonus from certificates (at most +2 per skill).
    public func certBonus(_ skill: String, _ library: [CertificateDef]) -> Int {
        let n = certs.compactMap { r in library.first { $0.id == r.id } }.filter { $0.skill == skill }.map(\.bonus).reduce(0, +)
        return min(Progression.certCapPerSkill, n)
    }

    /// Everything the player adds to a role's skill.
    public func bonus(_ skill: String, _ library: [CertificateDef]) -> Int {
        guard Progression.trainable.contains(skill) else { return 0 }
        return rank(skill) + certBonus(skill, library)
    }

    public func perks(_ library: [CertificateDef]) -> [String] {
        var out: [String] = []
        for r in certs {
            if let p = library.first(where: { $0.id == r.id })?.perk, !out.contains(p) { out.append(p) }
        }
        return out
    }

    /// XP progress inside the current level (0…1).
    public var levelProgress: Double {
        let start = Progression.xpAt(level), need = Progression.xpToNext(level)
        return min(1, max(0, Double(xp - start) / Double(need)))
    }

    public func canRaise(_ skill: String) -> Bool {
        Progression.trainable.contains(skill) && rank(skill) < Progression.maxRank && points >= Progression.rankCost(rank(skill) + 1)
    }

    public mutating func raise(_ skill: String) {
        guard canRaise(skill) else { return }
        points -= Progression.rankCost(rank(skill) + 1)
        ranks[skill] = rank(skill) + 1
        refundable = (refundable ?? [:]).merging([skill: 1], uniquingKeysWith: +)
    }

    public func canLower(_ skill: String) -> Bool { (refundable?[skill] ?? 0) > 0 && rank(skill) > 0 }

    /// Takes back a rank bought since the last chapter.
    public mutating func lower(_ skill: String) {
        guard canLower(skill) else { return }
        points += Progression.rankCost(rank(skill))
        ranks[skill] = rank(skill) - 1
        refundable?[skill, default: 1] -= 1
    }

    /// Adds XP and returns the levels gained.
    @discardableResult
    public mutating func gain(_ amount: Int) -> Int {
        let before = level
        xp += max(0, amount)
        level = Progression.level(forXP: xp)
        if level > before {
            for l in (before + 1)...level { points += Progression.pointsFor(level: l) }
        }
        return level - before
    }

    /// Adds practice; returns skills that went up for free.
    public mutating func addPractice(_ gained: [String: Int]) -> [String] {
        var up: [String] = []
        for skill in Progression.trainable {
            guard let n = gained[skill], n > 0 else { continue }
            practice[skill, default: 0] += n
            while rank(skill) < Progression.maxRank && practice[skill, default: 0] >= Progression.practiceNeeded(rank(skill)) {
                practice[skill, default: 0] -= Progression.practiceNeeded(rank(skill))
                ranks[skill] = rank(skill) + 1
                up.append(skill)
            }
            if rank(skill) >= Progression.maxRank { practice[skill] = min(practice[skill, default: 0], Progression.practiceNeeded(rank(skill))) }
        }
        return up
    }
}
