import Foundation

// MARK: - Controllers / setup

/// Who controls a character seat.
public enum ControllerKind: Codable, Sendable, Equatable, Hashable {
    case human
    case rule
    /// LLM seat. `seat` is a profile id from app settings (provider + model).
    case llm(seat: String, label: String)

    public var label: String { label(Loc.ui) }

    public func label(_ lang: Lang) -> String {
        switch self {
        case .human: return Loc.pick("玩家", "Player", lang)
        case .rule: return Loc.pick("基础人机", "Basic bot", lang)
        case .llm(_, let label): return label
        }
    }

    public var isHuman: Bool { if case .human = self { return true }; return false }
}

public struct GameSetup: Codable, Sendable {
    public var scenarioId: String
    public var seed: UInt64
    /// character id → controller. Characters not listed default to rule AI.
    public var controllers: [String: ControllerKind]
    public var debate: Bool
    public var spectator: Bool
    /// Language this game is played in (nil in saves made before languages existed → Chinese).
    public var language: Lang?
    /// Extra system-prompt text per character (endless mode: the player's career memory).
    public var notes: [String: String]? = nil
    /// Set when this game is a chapter of an endless run.
    public var chapter: ChapterTag? = nil
    /// Fast pace: AI models decide the day's work and the night's moves in one call (D-046).
    public var fastPace: Bool? = nil
    /// nil in older saves and endless chapters: normal.
    public var difficulty: Difficulty? = nil

    public var level: Difficulty { difficulty ?? .normal }

    public var lang: Lang { language ?? .zh }

    public init(scenarioId: String, seed: UInt64, controllers: [String: ControllerKind], debate: Bool = true, spectator: Bool = false, language: Lang = .zh) {
        self.scenarioId = scenarioId
        self.seed = seed
        self.controllers = controllers
        self.debate = debate
        self.spectator = spectator
        self.language = language
    }
}

/// What a chapter of an endless run looks like from inside the game (for display).
public struct ChapterTag: Codable, Sendable {
    public var runId: String
    public var number: Int
    public var finale: Bool
    /// character id → the run player playing it
    public var seats: [String: SeatTag]
    /// Mutator names (in the run's language).
    public var mutators: [String]

    public init(runId: String, number: Int, finale: Bool, seats: [String: SeatTag], mutators: [String]) {
        self.runId = runId
        self.number = number
        self.finale = finale
        self.seats = seats
        self.mutators = mutators
    }
}

public struct SeatTag: Codable, Sendable {
    public var playerId: String
    public var name: String
    public var level: Int
    /// Certificate short names (in the run's language).
    public var certs: [String]

    public init(playerId: String, name: String, level: Int, certs: [String]) {
        self.playerId = playerId
        self.name = name
        self.level = level
        self.certs = certs
    }
}

// MARK: - Characters

public enum CharStatus: String, Codable, Sendable {
    case active, away, dead, exiled, notJoined, rescued, gone

    public var label: String { label(Loc.ui) }

    public func label(_ lang: Lang) -> String {
        switch self {
        case .active: return Loc.pick("在营地", "at camp", lang)
        case .away: return Loc.pick("外出", "away", lang)
        case .dead: return Loc.pick("遇难", "dead", lang)
        case .exiled: return Loc.pick("被驱逐", "expelled", lang)
        case .notJoined: return Loc.pick("未出现", "not here yet", lang)
        case .rescued: return Loc.pick("已获救", "rescued", lang)
        case .gone: return Loc.pick("离开了", "gone", lang)
        }
    }
}

public struct Injury: Codable, Sendable, Identifiable, Equatable {
    public var id: Int
    public var kind: String
    public var severity: Double
    public var part: String?
    public var label: String?
    public var treated: Bool
    /// Language-independent identity of part / label (the scenario's original text), so that
    /// "same injury again" works the same way whatever language the game is played in.
    public var partKey: String? = nil
    public var labelKey: String? = nil

    /// Does this injury match a new one of the same kind on the same part?
    func same(kind k: String, partKey pk: String?, labelKey lk: String?) -> Bool {
        kind == k && (partKey ?? part) == pk && (labelKey ?? label) == lk
    }

    public var displayName: String { displayName(Loc.ui) }

    public func displayName(_ lang: Lang) -> String {
        if let label { return label }
        let base = InjuryKind.name(kind, lang)
        if let part, !part.isEmpty { return lang == .en ? "\(base) (\(Loc.lowerFirst(part, lang)))" : "\(part)\(base)" }
        return base
    }
}

public struct CharacterStats: Codable, Sendable {
    public var thefts = 0
    public var caught = 0
    public var stashEaten = 0.0
    public var whispers = 0
    public var motions = 0
    public var exileVotes = 0
    public var roundsLed = 0
    public var cared = 0
    public var outdoorHours = 0.0
    public var llmCalls = 0
    public var llmFailures = 0
    /// How often each skill was put to use (practice, for endless-mode progression).
    public var skillUse: [String: Int]?
    public init() {}
}

public struct CharacterState: Codable, Sendable, Identifiable {
    public var id: String
    public var isNPC: Bool
    public var status: CharStatus
    public var health: Double
    public var core: Double
    /// Water deficit in liters (negative = slightly over-hydrated buffer).
    public var thirst: Double
    public var fatKg: Double
    /// Recent food intake / expenditure ratio (exponential moving average).
    public var energyEMA: Double
    public var fatigue: Double
    public var morale: Double
    public var clo: Double
    public var wetHours: Double
    public var injuries: [Injury]
    public var items: [String: Double]
    public var stash: [String: Double]
    public var trust: [String: Double]
    public var secretRevealed: Bool
    public var awayRounds: Int
    public var awayReturn: [Effect]?
    /// Extra °C of protection while away (0 = open bivouac; ~10 = a hut / wreck / tent).
    public var awayCamp: Double = 0
    public var deathRound: Int?
    public var deathCause: String?
    /// A coarse kind of the cause (cold, thirst, sick…), for the ending when everyone dies (D-056).
    public var deathKind: String? = nil
    public var punishedRounds: Int
    public var diary: [String]
    public var lastTask: String?
    public var lastIntake: Double
    public var lastNeed: Double
    public var lastWater: Double
    public var stats: CharacterStats
    /// Last round's measured expenditure (shown to the leader as guidance).
    public var reportKcal: Double = 0
    public var reportWater: Double = 0
    public var roundWaterLoss: Double = 0
    /// Timed statuses (see Buffs.swift); conditions and mastery are derived, not stored.
    public var buffs: [ActiveBuff]? = nil
    /// Round of this person's last breakdown (D-053): nobody falls apart again straight away.
    public var lastBreakdown: Int? = nil

    /// Alive and still in the story (in camp or away on an expedition).
    public var alive: Bool { status == .active || status == .away }
    public var present: Bool { status == .active }
    /// Made it out (rescued early) or still alive.
    public var survived: Bool { alive || status == .rescued }
    public var rescuedRound: Int?
}

// MARK: - Policy

public struct Policy: Codable, Sendable, Equatable {
    /// kcal per person per 24h
    public var food: Double
    /// liters per person per 24h
    public var water: Double
    public var fire: Bool
    /// "equal" | "injured" | "workers" | "leader"
    public var priority: String

    public init(food: Double, water: Double, fire: Bool, priority: String) {
        self.food = food
        self.water = water
        self.fire = fire
        self.priority = priority
    }

    public static let priorities: [(String, String)] = [
        ("equal", "平均分"), ("injured", "伤病优先"), ("workers", "干重活的优先"), ("leader", "领头人优先")
    ]
    static let prioritiesEN: [String: String] = [
        "equal": "shared equally", "injured": "injured first", "workers": "heavy workers first", "leader": "leader first"
    ]

    public static func priorityLabel(_ p: String, _ lang: Lang = Loc.ui) -> String {
        lang == .en ? (prioritiesEN[p] ?? p) : (priorities.first { $0.0 == p }?.1 ?? p)
    }
}

// MARK: - Log

public enum LogKind: String, Codable, Sendable {
    case report      // morning report / system status
    case situation   // the pop-up sentence of an event
    case speech      // public speech
    case vote        // vote tally
    case result      // outcome text
    case task        // task outcome
    case death
    case whisper     // private message (private visibility)
    case thought     // inner monologue (god only)
    case diary       // diary (god only)
    case secret      // secret actions (god only)
    case system      // generic system notice
    case ending
    case debug
}

public enum Visibility: Codable, Sendable, Equatable {
    case everyone
    case only([String])
    case god
}

public struct LogEntry: Codable, Sendable, Identifiable {
    public var id: Int
    public var round: Int
    public var kind: LogKind
    public var text: String
    public var detail: String?
    public var actor: String?
    public var target: String?
    public var visibility: Visibility
    public var phase: String?

    /// What a stance says when the person said nothing.
    public static func silent(_ lang: Lang) -> String { lang == .en ? "(says nothing)" : "（没说话）" }
    public var isSilent: Bool { text == "（没说话）" || text == "(says nothing)" }

    public func visible(to who: String?) -> Bool {
        switch visibility {
        case .everyone: return true
        case .god: return false
        case .only(let ids):
            guard let who else { return false }
            return ids.contains(who)
        }
    }
}

// MARK: - Events at runtime

public struct ResolvedOption: Codable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var hint: String?
    public var tags: [String]
    public var available: Bool
}

public enum MotionType: String, Codable, Sendable {
    case elect, punish, exile, search, thief
}

public struct Motion: Codable, Sendable, Equatable {
    public var type: MotionType
    public var proposer: String?
    public var target: String?
}

public struct ActiveEvent: Codable, Sendable {
    public var def: EventDef
    public var text: String
    public var protagonist: String?
    public var deciders: [String]
    public var options: [ResolvedOption]
    public var motion: Motion?
    public var nominees: [String]

    public var kind: String { def.kind }
    public var isMajor: Bool { def.major ?? false }

    public var kindLabel: String { kindLabel(Loc.ui) }

    public func kindLabel(_ lang: Lang) -> String {
        switch def.kind {
        case "group": return Loc.pick("集体表决", "Group vote", lang)
        case "individual": return Loc.pick("各自决定", "Everyone decides for themselves", lang)
        case "nominate": return Loc.pick("推选一个人", "Choose someone", lang)
        case "leader": return Loc.pick("领头人拍板", "The leader decides", lang)
        case "solo": return Loc.pick("只有当事人决定", "Only one person decides", lang)
        default: return def.kind
        }
    }
}

public struct ScheduledEvent: Codable, Sendable {
    public var eventId: String
    public var round: Int
    public var actor: String?
    public var target: String?
}

// MARK: - Decisions

public struct SituationDecision: Codable, Sendable {
    public var choice: String
    public var speech: String?
    public var thought: String?
    public var fallback: Bool?

    public init(choice: String, speech: String? = nil, thought: String? = nil, fallback: Bool? = nil) {
        self.choice = choice
        self.speech = speech
        self.thought = thought
        self.fallback = fallback
    }
}

public struct TaskDecision: Codable, Sendable {
    public var task: String
    public var target: String?
    public var speech: String?
    public var thought: String?
    public var policy: Policy?
    public var fallback: Bool?

    public init(task: String, target: String? = nil, speech: String? = nil, thought: String? = nil, policy: Policy? = nil, fallback: Bool? = nil) {
        self.task = task
        self.target = target
        self.speech = speech
        self.thought = thought
        self.policy = policy
        self.fallback = fallback
    }
}

public struct Whisper: Codable, Sendable {
    public var to: String
    public var text: String
    public init(to: String, text: String) { self.to = to; self.text = text }
}

public struct NightDecision: Codable, Sendable {
    public var whispers: [Whisper]
    /// "none" | "steal" | "stash" | "reveal"
    public var secret: String
    public var motion: Motion?
    public var diary: String?
    public var thought: String?
    public var fallback: Bool?
    /// Who to sleep next to tonight (sharing body heat; D-053).
    public var huddle: String?
    /// Food and water handed to someone tonight (D-053).
    public var gift: Gift?

    public init(whispers: [Whisper] = [], secret: String = "none", motion: Motion? = nil, diary: String? = nil, thought: String? = nil, fallback: Bool? = nil,
                huddle: String? = nil, gift: Gift? = nil) {
        self.whispers = whispers
        self.secret = secret
        self.motion = motion
        self.diary = diary
        self.thought = thought
        self.fallback = fallback
        self.huddle = huddle
        self.gift = gift
    }
}

/// Handing food and water to someone: part of your own share of today's rations (everyone sees it),
/// or what you've hidden away (only the two of you know).
public struct Gift: Codable, Sendable, Equatable {
    public var to: String
    /// "ration" | "stash"
    public var from: String
    /// ration only: the part of your share you give away (0.25…1, default ½)
    public var portion: Double?

    public init(to: String, from: String = "ration", portion: Double? = nil) {
        self.to = to
        self.from = from
        self.portion = portion
    }
}

/// How hard the world is (D-053). Older saves have none: normal.
public enum Difficulty: String, Codable, Sendable, CaseIterable {
    case normal, hard, brink

    /// Starting supplies.
    public var startScale: Double { switch self { case .normal: return 1; case .hard: return 0.8; case .brink: return 0.65 } }
    /// Everything found, foraged, built up or handed out during the game.
    public var gainScale: Double { switch self { case .normal: return 1; case .hard: return 0.85; case .brink: return 0.7 } }
    /// How badly accidents and events hurt.
    public var injuryScale: Double { switch self { case .normal: return 1; case .hard: return 1.3; case .brink: return 1.6 } }
    /// Starting morale.
    public var moraleOffset: Double { switch self { case .normal: return 0; case .hard: return -8; case .brink: return -15 } }
    /// A harsher spell of weather, in °C: colder where it's cold, hotter where it's hot.
    public var weatherShift: Double { switch self { case .normal: return 0; case .hard: return 2.5; case .brink: return 4.5 } }
    /// How often something goes wrong on top of the scenario's own script (per day, and it grows as the days go by; D-055).
    public var hardshipRate: Double { switch self { case .normal: return 0; case .hard: return 0.35; case .brink: return 0.55 } }
    /// Health lost per day to simply being worn down by the ordeal, rising as it drags on (D-055).
    public var wearPerDay: Double { switch self { case .normal: return 0; case .hard: return 3; case .brink: return 4.5 } }
    /// How much longer help takes to come (times the scenario's `rescueAfter` rounds).
    public var rescueDelay: Double { switch self { case .normal: return 0; case .hard: return 1; case .brink: return 1.3 } }
    /// How hard cold, thirst, hunger and heat hit the body, and how slowly it mends.
    public var vitalsScale: Double { switch self { case .normal: return 1; case .hard: return 1.25; case .brink: return 1.5 } }

    public func label(_ lang: Lang) -> String {
        switch self {
        case .normal: return Loc.pick("普通", "Normal", lang)
        case .hard: return Loc.pick("困难", "Hard", lang)
        case .brink: return Loc.pick("绝境", "Brink", lang)
        }
    }

    public func blurb(_ lang: Lang) -> String {
        switch self {
        case .normal: return Loc.pick("按场景原本的物资和伤情。", "Supplies and injuries as the scenario describes them.", lang)
        case .hard: return Loc.pick("开局物资少两成，找到的东西少一成半，伤得更重，士气更低，天气更狠，身体也更不经熬；日子越长，越容易出岔子：生病、受伤、补给受潮、夜里的崩溃。", "A fifth less to start with, less found along the way, worse injuries, lower spirits, harsher weather and bodies that give out sooner. The longer it goes on, the more goes wrong: sickness, accidents, spoiled supplies, bad nights.", lang)
        case .brink: return Loc.pick("开局物资只剩六成半，找到的东西少三成，伤得重得多，天气极端，身体撑不了多久，几乎天天出岔子。绝大多数局没人能活着出去。", "Barely two-thirds of the supplies, a third less found, far worse injuries, extreme weather, bodies that fail fast, and something going wrong almost every day. In nearly every game no one gets out.", lang)
        }
    }
}

// MARK: - Phase / ending

public enum GamePhase: String, Codable, Sendable {
    case situation, tasks, night, ended

    public var label: String { label(Loc.ui) }

    public func label(_ lang: Lang) -> String {
        switch self {
        case .situation: return Loc.pick("局势", "Situation", lang)
        case .tasks: return Loc.pick("分工", "Work", lang)
        case .night: return Loc.pick("入夜", "Night", lang)
        case .ended: return Loc.pick("结局", "Ending", lang)
        }
    }
}

public struct CharacterResult: Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var controller: String
    public var survived: Bool
    public var fate: String
    public var goal: String?
    public var goalAchieved: Bool
    public var score: Int
    public var epilogue: String?
    public var isNPC: Bool?
}

public struct EndingResult: Codable, Sendable {
    public var id: String
    public var title: String
    public var text: String
    public var tone: String
    public var round: Int
    public var results: [CharacterResult]
    /// NPC fates and epilogues.
    public var others: [CharacterResult]?
}

public struct TaskAssignment: Codable, Sendable {
    public var task: String
    public var target: String?
}

// MARK: - Game state

public struct GameState: Codable, Sendable {
    public var scenarioId: String
    public var setup: GameSetup
    public var rng: SeededRNG
    public var round: Int
    public var phase: GamePhase
    public var characters: [CharacterState]
    public var resources: [String: Double]
    public var vars: [String: Double]
    public var flags: Set<String>
    public var projects: [String: Double]
    public var projectsDone: Set<String>
    /// pool id → remaining stock per item (-1 = unlimited)
    public var poolStock: [String: [Int]]
    public var weather: String
    public var forcedWeather: String?
    public var forcedWeatherRounds: Int
    public var dayHigh: Double
    public var dayLow: Double
    public var tempDay: Int
    public var shelterIntegrity: Double
    public var leader: String?
    public var policy: Policy
    public var firedEvents: [String: Int]
    public var scheduled: [ScheduledEvent]
    public var eventQueue: [ActiveEvent]
    public var currentEvent: ActiveEvent?
    public var pendingMotions: [Motion]
    public var assignments: [String: TaskAssignment]
    public var guards: [String]
    public var log: [LogEntry]
    public var nextId: Int
    public var ending: EndingResult?
    public var fireLit: Bool
    public var antibioticsGiven: Set<String>
    public var stolenTonight: Double
    public var foodAtDawn: Double
    public var stanceSpeeches: [String: String] = [:]
    /// True while endings and personal goals are being evaluated (rescued people count as alive).
    public var evaluatingEnding: Bool = false

    public func character(_ id: String) -> CharacterState? {
        characters.first { $0.id == id }
    }

    public func index(of id: String) -> Int? {
        characters.firstIndex { $0.id == id }
    }

    public var participants: [String] {
        characters.filter { !$0.isNPC }.map(\.id)
    }

    public var presentParticipants: [String] {
        characters.filter { !$0.isNPC && $0.present }.map(\.id)
    }

    public var aliveParticipants: [String] {
        characters.filter { !$0.isNPC && $0.alive }.map(\.id)
    }
}
