import Foundation

// MARK: - Num: a number or an expression string

/// A numeric field in scenario JSON. Either a literal number (`12.5`) or an
/// expression string (`"var.search / 100 * 0.2"`).
public enum Num: Codable, Sendable, CustomStringConvertible {
    case const(Double)
    case expr(String)

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) {
            self = .const(d)
        } else if let s = try? c.decode(String.self) {
            self = .expr(s)
        } else if let b = try? c.decode(Bool.self) {
            self = .const(b ? 1 : 0)
        } else {
            throw DecodingError.typeMismatch(Num.self, .init(codingPath: decoder.codingPath, debugDescription: "需要数字或表达式字符串"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .const(let d): try c.encode(d)
        case .expr(let s): try c.encode(s)
        }
    }

    public var description: String {
        switch self {
        case .const(let d): return String(d)
        case .expr(let s): return s
        }
    }

    public var expression: String? {
        if case .expr(let s) = self { return s }
        return nil
    }
}

// MARK: - Scenario

public struct Scenario: Codable, Identifiable, Sendable {
    public var id: String
    public var version: Int?
    public var title: String
    public var subtitle: String
    public var tagline: String
    public var inspiration: String
    /// Short notes on how the real-world physics/physiology of this scenario is modeled (shown to players).
    public var modelNotes: [String]?
    public var difficulty: Int
    public var accent: String?
    public var icon: String?
    public var briefing: [String]
    public var setting: SettingDef
    public var clock: ClockDef
    public var climate: ClimateDef
    public var shelter: ShelterDef
    public var rations: RationDef?
    public var physiology: PhysiologyDef?
    public var resources: [ResourceDef]
    public var vars: [VarDef]?
    public var pools: [String: PoolDef]?
    public var projects: [ProjectDef]?
    public var characters: [CharacterDef]
    public var npcs: [CharacterDef]?
    public var tasks: [TaskDef]
    public var builtinTasks: [String]?
    public var onStart: [Effect]?
    public var rules: [Effect]?
    public var events: [EventDef]
    public var endings: [EndingDef]
    public var defaultEnding: String
    public var wipeEnding: String
    /// Display names for personal item ids (e.g. "suitcase": "铝合金箱子").
    public var itemNames: [String: String]?
    /// Optional text when someone is exiled, e.g. "{actor} 被推下了救生筏。"
    public var exileText: String?
    /// Not listed on the home screen (the endless-mode finale, the tutorial).
    public var hidden: Bool?
    /// How often things go wrong on the harder settings, relative to the default (1): see `rollHardship`.
    public var hardship: Double?
    /// Ids of the events that bring help or a way out. On the harder settings none of them can happen before
    /// `rescueAfter` rounds (scaled by the setting) have passed: help takes longer to come (D-055).
    public var rescues: [String]?
    public var rescueAfter: Int?

    /// The beginner tutorial: a short hidden scenario played with an on-screen guide.
    public static let tutorialId = "tutorial"
    public var isTutorial: Bool { id == Scenario.tutorialId }

    public func itemName(_ id: String) -> String { itemNames?[id] ?? id }

    public var allCharacters: [CharacterDef] { characters + (npcs ?? []) }

    public func character(_ id: String) -> CharacterDef? {
        allCharacters.first { $0.id == id }
    }

    public func resource(_ id: String) -> ResourceDef? {
        resources.first { $0.id == id }
    }

    public func variable(_ id: String) -> VarDef? {
        vars?.first { $0.id == id }
    }

    public func task(_ id: String) -> TaskDef? {
        tasks.first { $0.id == id }
    }

    public func event(_ id: String) -> EventDef? {
        events.first { $0.id == id }
    }

    public func project(_ id: String) -> ProjectDef? {
        projects?.first { $0.id == id }
    }

    public var rationDef: RationDef {
        rations ?? RationDef(food: [0, 600, 1200, 1800, 2400], water: [0.5, 1, 2, 3], defaultFood: 3, defaultWater: 2)
    }
}

public struct SettingDef: Codable, Sendable {
    public var location: String
    public var altitude: Double?
    public var date: String?
    public var description: String?
}

public struct ClockDef: Codable, Sendable {
    /// Hours per round (24 = one day per round).
    public var roundHours: Int
    /// Clock hour at which round 1 starts.
    public var startHour: Int
    /// Hard limit; when reached the default ending fires.
    public var maxRounds: Int
    /// Work hours inside a round (task exposure window). Default: roundHours / 3.
    public var workHours: Int?
    /// Optional label template, e.g. "震后第{hours}小时". Default "第{day}天".
    public var roundLabel: String?
    /// Optional clock hour(s) at which work starts (JSON `8` or `[10, 20]`, each 0–23). Each round uses the first
    /// listed hour that falls inside it, so 12-hour day/night rounds can work 10:00–14:00 by day and 20:00–24:00 by
    /// night. Default: one hour after the round starts. Expeditions (`away`) set off at the same hour (default 08:00).
    public var workStart: HourList?
}

/// One or more clock hours. JSON: a single number (`8`) or a list (`[10, 20]`).
public struct HourList: Codable, Sendable, Equatable {
    public var hours: [Int]

    public init(_ hours: [Int]) { self.hours = hours }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let h = try? c.decode(Int.self) {
            hours = [h]
        } else {
            hours = try c.decode([Int].self)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if hours.count == 1 { try c.encode(hours[0]) } else { try c.encode(hours) }
    }
}

public struct ClimateDef: Codable, Sendable {
    public var tempHigh: Double
    public var tempLow: Double
    public var drift: Double?
    public var noise: Double?
    /// Extra effective °C in direct sun at midday (outdoors, clear weather).
    public var solar: Double?
    public var initialWeather: String
    public var weather: [String: WeatherDef]
}

public struct WeatherDef: Codable, Sendable {
    public var name: String
    public var icon: String?
    public var temp: Double?
    public var ampScale: Double?
    public var wind: Double?
    public var visibility: Double?
    public var precip: Double?
    public var sun: Double?
    public var wet: Bool?
    public var outdoorRisk: Double?
    public var desc: String?
    public var next: [String: Double]
}

public struct ShelterDef: Codable, Sendable {
    public var name: String
    /// °C warmer than outside when it's cold (scaled by integrity).
    public var insulation: Double
    /// 0..1 fraction of wind chill blocked.
    public var windProof: Double
    public var integrity: Double
    public var decay: Double?
    public var stormDecay: Double?
    /// Extra clothing insulation (clo) when resting/sleeping inside (blankets, seat covers…).
    public var bedding: Double?
    /// Whether the shelter blocks sun. Default true.
    public var shade: Bool?
    /// People inside are constantly wet (raft, flooded roof).
    public var wet: Bool?
    public var fire: FireDef?
}

public struct FireDef: Codable, Sendable {
    public var resource: String
    public var perRound: Double
    public var heat: Double
    public var label: String?
}

public struct RationDef: Codable, Sendable {
    public var food: [Double]
    public var water: [Double]
    public var defaultFood: Int
    public var defaultWater: Int
}

public struct PhysiologyDef: Codable, Sendable {
    /// Multiplier for wound infection chance (dirty water, tropics → >1).
    public var infectionRisk: Double?
    /// Altitude in meters (overrides setting.altitude for physiology).
    public var altitude: Double?
    /// Constant oxygen/CO2 etc. are modeled by scenario vars + rules.
    public var note: String?
}

public struct ResourceDef: Codable, Sendable {
    public var id: String
    public var name: String
    public var unit: String
    public var initial: Double
    public var kind: String?
    public var decimals: Int?
    public var desc: String?
    public var hidden: Bool?
}

public struct VarDef: Codable, Sendable {
    public var id: String
    public var name: String
    public var initial: Double
    public var min: Double?
    public var max: Double?
    public var unit: String?
    public var show: Bool?
    /// "level" | "percent" | "number"
    public var format: String?
    public var levels: [String]?
    public var desc: String?
}

public struct PoolDef: Codable, Sendable {
    public var name: String
    public var items: [PoolItem]
}

public struct PoolItem: Codable, Sendable {
    public var res: String?
    public var amount: [Double]?
    public var weight: Double
    public var stock: Int?
    public var text: String?
    public var effects: [Effect]?
}

public struct ProjectDef: Codable, Sendable {
    public var id: String
    public var name: String
    public var desc: String
    public var work: Double
    public var when: String?
    public var onComplete: [Effect]
}

public struct CharacterDef: Codable, Sendable {
    public var id: String
    public var name: String
    public var gender: String
    public var age: Int
    public var role: String
    public var bio: String
    public var personality: String
    public var voice: String?
    public var secret: String?
    public var secretReveal: [Effect]?
    public var goal: GoalDef?
    public var weight: Double
    public var fat: Double
    public var clo: Double
    public var skills: [String: Int]
    public var injuries: [InjuryInit]?
    public var items: [String: Double]?
    public var stash: [String: Double]?
    public var traits: TraitsDef?
    public var relations: [String: Double]?
    public var joinsLater: Bool?
    public var tags: [String]?
    /// Per-character epilogues: the first whose `when` holds at the end is shown (actor = this character).
    public var epilogues: [EpilogueDef]?
    /// NPCs only: a task the NPC does by itself every round (when able). Default: rest.
    public var autoTask: String?
    /// NPCs only: things they say now and then (ambient flavor).
    public var lines: [String]?
    /// Know-how a player brings into this role in endless mode ("warm", "wet", "water", "calm"; see Certificates).
    public var perks: [String]?
    /// Starting morale (default 55). Endless mode: lower when the player's resolve is low.
    public var morale: Double?

    public func hasPerk(_ p: String) -> Bool { perks?.contains(p) ?? false }

    public func skill(_ s: String) -> Int { skills[s] ?? 0 }

    /// Works for both "女" and "female" (English overlays translate the gender field).
    public var isFemale: Bool {
        let g = gender.lowercased()
        return gender.contains("女") || gender.contains("母") || gender.contains("雌") || g.hasPrefix("f") || g.contains("female") || g.contains("woman") || g.contains("girl")
    }

    /// Animals (tag "animal"): eat by body weight, don't count as people in survivor tallies.
    public var isAnimal: Bool { (tags ?? []).contains("animal") }
}

public struct EpilogueDef: Codable, Sendable {
    public var when: String
    public var text: String
}

public struct GoalDef: Codable, Sendable {
    public var text: String
    public var check: String
}

public struct InjuryInit: Codable, Sendable {
    public var kind: String
    public var severity: Double
    public var part: String?
    public var label: String?
    public var treated: Bool?
    /// Original (untranslated) part / label; filled in when a translation is applied.
    public var partKey: String?
    public var labelKey: String?
}

public struct TraitsDef: Codable, Sendable {
    public var selfish: Double?
    public var brave: Double?
    public var trusting: Double?
    public var ambition: Double?
    public var temper: Double?
}

public struct TaskDef: Codable, Sendable {
    public var id: String
    public var name: String
    public var desc: String
    /// "rest" | "light" | "heavy"
    public var exertion: String
    public var outdoor: Bool
    public var hours: Int?
    public var when: String?
    public var mobility: Bool?
    /// "none" | "other" | "any" — whether the task needs a target person.
    public var target: String?
    public var max: Int?
    public var hint: String?
    public var effects: [Effect]
}

public struct EventDef: Codable, Sendable {
    public var id: String
    /// "group" | "individual" | "nominate" | "leader" | "solo"
    public var kind: String
    public var text: String
    public var options: [OptionDef]?
    /// For nominate: effects applied with the chosen person as actor and target.
    public var effects: [Effect]?
    public var result: String?
    public var when: String?
    /// Scripted: fires at this round (if `when` also holds).
    public var atRound: Int?
    public var once: Bool?
    /// Random-pool weight. 0/nil = never random (scripted/scheduled only).
    public var weight: Double?
    public var minRound: Int?
    public var maxRound: Int?
    public var cooldown: Int?
    public var priority: Int?
    public var major: Bool?
    public var who: String?
    public var whoWhen: String?
    public var pre: [Effect]?
    public var icon: String?
}

public struct OptionDef: Codable, Sendable {
    public var id: String
    public var label: String
    public var hint: String?
    public var tags: [String]?
    public var when: String?
    public var effects: [Effect]?
    public var result: String?
}

public struct EndingDef: Codable, Sendable {
    public var id: String
    public var title: String
    public var when: String?
    public var text: String
    /// "good" | "bitter" | "bad"
    public var tone: String?
}

// MARK: - Effects

/// One effect in the scenario effect language. A flat struct: which fields are
/// used depends on `e`. The built-in scenarios in Resources/Scenarios show every kind in use.
public struct Effect: Codable, Sendable {
    public var e: String
    public var id: String?
    public var add: Num?
    public var set: Num?
    public var who: String?
    public var from: String?
    public var to: String?
    public var stat: String?
    public var kind: String?
    public var severity: Num?
    public var part: String?
    public var label: String?
    /// Original (untranslated) part / label; filled in when a translation is applied.
    public var partKey: String?
    public var labelKey: String?
    public var amount: Num?
    public var treated: Bool?
    public var cause: String?
    public var text: String?
    public var vis: String?
    public var p: Num?
    public var then: [Effect]?
    public var `else`: [Effect]?
    public var when: String?
    public var skill: String?
    public var dc: Num?
    public var `do`: [Effect]?
    public var event: String?
    public var `in`: Num?
    public var pool: String?
    public var rolls: Num?
    public var base: Num?
    public var per: Double?
    public var weather: [String: Double]?
    public var project: String?
    public var rounds: Num?
    public var onReturn: [Effect]?
    /// `away` only: how hard the trip is ("rest" | "light" | "heavy", default "light") and how many hours a day
    /// are spent on the move (default 6; from the scenario's work start, else 08:00). The rest of the day is camp.
    public var exertion: String?
    public var hours: Num?
    public var ending: String?
    public var on: Bool?
    public var hidden: Bool?

    public init(e: String) { self.e = e }

    public static let knownTypes: Set<String> = [
        "res", "var", "flag", "stat", "injure", "heal", "trust", "kill", "log", "say",
        "chance", "check", "if", "each", "schedule", "loot", "yield", "work", "shelter",
        "item", "away", "leader", "exile", "evacuate", "leave", "end", "reveal", "weather", "join", "buff"
    ]
}

// MARK: - Shared constants

public enum Skill {
    public static let all = ["medical", "survival", "strength", "technical", "navigation", "social"]
    public static let namesZH: [String: String] = [
        "medical": "医疗", "survival": "野外", "strength": "体能",
        "technical": "技术", "navigation": "方向", "social": "威望"
    ]
    public static let namesEN: [String: String] = [
        "medical": "Medical", "survival": "Survival", "strength": "Strength",
        "technical": "Technical", "navigation": "Navigation", "social": "Standing"
    ]
    /// Skill names in the interface language.
    public static var names: [String: String] { Loc.ui == .en ? namesEN : namesZH }
    public static func name(_ s: String, _ lang: Lang) -> String { (lang == .en ? namesEN : namesZH)[s] ?? s }
}

public enum Exertion: String, Sendable {
    case rest, light, heavy
    public var label: String { label(Loc.ui) }

    public func label(_ lang: Lang) -> String {
        switch self {
        case .rest: return Loc.pick("休息", "rest", lang)
        case .light: return Loc.pick("轻体力", "light work", lang)
        case .heavy: return Loc.pick("重体力", "heavy work", lang)
        }
    }
}
