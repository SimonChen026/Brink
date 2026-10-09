import Foundation

// MARK: - Run model (D-035)

public enum RunPhase: String, Codable, Sendable {
    /// Between chapters (also before the first): exams, skill points, choosing the next scenario.
    case hub
    /// A chapter is being played.
    case chapter
    /// The finale is over; the grand ending is waiting to be read (then: end, or go on endlessly).
    case finaleDone
    /// The run is over.
    case ended
}

public struct RunOptions: Codable, Sendable {
    /// All five seats are AI; the player watches.
    public var spectator: Bool
    /// Iron mode: run out of resolve and you're out (the human's run ends; AI players are replaced).
    public var hardcore: Bool
    public var debate: Bool
    /// Spectator runs: go on to the next chapter by themselves.
    public var autoAdvance: Bool

    public init(spectator: Bool = false, hardcore: Bool = false, debate: Bool = true, autoAdvance: Bool = true) {
        self.spectator = spectator
        self.hardcore = hardcore
        self.debate = debate
        self.autoAdvance = autoAdvance
    }
}

/// A seat chosen when the run is created.
public struct SeatSpec: Sendable {
    public var seat: String
    public var label: String
    public var name: String?
    public var female: Bool?

    public init(seat: String, label: String, name: String? = nil, female: Bool? = nil) {
        self.seat = seat
        self.label = label
        self.name = name
        self.female = female
    }
}

/// How one run player enters one role. Everything needed to rebuild the chapter's scenario is here,
/// so a chapter saved halfway can be resumed exactly.
public struct CastEntry: Codable, Sendable {
    public var playerId: String
    /// Final skill values of the role (role's own + the player's bonus, capped).
    public var skills: [String: Int]
    public var perks: [String]
    public var cloBonus: Double
    /// Initial trust toward the other characters (merged over the role's own relations).
    public var relations: [String: Double]
    /// Starting morale (lower when the player's resolve is low).
    public var morale: Double?
    // The finale: the player plays themselves.
    public var persona: Persona?
    public var role: String?
    public var bio: String?
    public var personality: String?
    public var voice: String?
    public var traits: TraitsDef?
}

public struct ChapterPlan: Codable, Sendable {
    public var number: Int
    public var scenarioId: String
    public var finale: Bool
    public var cycle: Int
    public var seed: UInt64
    public var gameId: String
    /// character id → who plays it
    public var cast: [String: CastEntry]
    public var mutators: [String]
}

public struct SummaryLine: Codable, Sendable {
    public var playerId: String
    public var playerName: String
    public var characterName: String
    public var survived: Bool
    public var fate: String
}

public struct ChapterSummary: Codable, Sendable {
    public var number: Int
    public var scenarioId: String
    public var title: String
    public var endingTitle: String
    public var tone: String
    public var cleared: Bool
    public var finale: Bool
    public var cycle: Int
    public var mutators: [String]
    public var lines: [SummaryLine]
    /// NPCs (people, not animals) who made it / didn't.
    public var npcSaved: Int
    public var npcLost: Int
}

/// Shown in the hub right after a chapter.
public struct ChapterReport: Codable, Sendable {
    public var number: Int
    public var scenarioId: String
    public var scenarioTitle: String
    public var endingTitle: String
    public var endingText: String
    public var tone: String
    public var cleared: Bool
    public var firstClear: Bool
    public var finaleUnlocked: Bool
    public var players: [String: PlayerChapter]
    public var departures: [String]
    public var recruits: [String]
}

public struct EndlessRun: Codable, Sendable, Identifiable {
    public var id: String
    public var version = 1
    public var created: Date
    public var lang: Lang
    public var seed: UInt64
    public var options: RunOptions
    /// Everyone who has ever had a seat (those who went out keep `out = true`).
    public var players: [RunPlayer]
    public var phase: RunPhase = .hub
    /// Chapters started so far.
    public var chapter = 0
    /// Interludes so far (one exam per player per interlude).
    public var interlude = 0
    /// Cycle 1 = the eight drills + the finale; 2+ = endless after the finale.
    public var cycle = 1
    /// Chapters played after the finale.
    public var depth = 0
    /// Drills played in cycle 1 (each once, like a course), and those cleared (at least one run player survived).
    public var played: [String] = []
    public var cleared: [String] = []
    public var attempts: [String: Int] = [:]
    public var history: [ChapterSummary] = []
    public var current: ChapterPlan?
    public var lastReport: ChapterReport?
    public var grand: GrandEnding?
    /// player id → player id → how they've come to feel about each other (−60…60), carried across chapters.
    public var bonds: [String: [String: Double]] = [:]
    public var recruits = 0

    /// The eight drills, in their usual order.
    public static let drills = ["snowline", "adrift", "deepshaft", "rubble", "sandsea", "castaway", "polarnight", "flood"]
    public static let finaleId = "finale"
    /// Disasters added after the first eight: not part of the eight drills before the finale (its story
    /// counts eight), they join the pool for the endless chapters after it.
    public static let later = ["icebound", "fogforest"]

    public func L(_ zh: @autoclosure () -> String, _ en: @autoclosure () -> String) -> String { lang == .en ? en() : zh() }

    // MARK: Creation

    /// - Parameter humanCerts: certificates the human already holds (the "我" page); they come along into the run.
    public static func new(seats: [SeatSpec], options: RunOptions, lang: Lang, seed: UInt64, now: Date = Date(), humanCerts: [PlayerProfile.Held] = []) -> EndlessRun {
        var rng = SeededRNG(seed: seed ^ 0x51ED)
        var players: [RunPlayer] = []
        var taken: Set<String> = []
        for (i, s) in seats.prefix(5).enumerated() {
            var p = Personas.make(&rng, lang: lang, taken: taken, female: s.female)
            if let n = s.name?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty { p.name = n }
            if let f = s.female { p.female = f }
            taken.insert(p.name)
            var player = RunPlayer(id: "p\(i + 1)", persona: p, seat: s.seat, controllerLabel: s.label, resolve: Progression.baseResolve, joinedChapter: 1)
            if s.seat == "human" {
                player.certs = humanCerts.map { CertRecord(id: $0.id, interlude: 0, score: $0.score, total: $0.total) }
                player.resolve = player.maxResolve
            }
            players.append(player)
        }
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return EndlessRun(id: "run-\(f.string(from: now))", created: now, lang: lang, seed: seed, options: options, players: players)
    }

    // MARK: Queries

    /// The five players currently in the team.
    public var active: [RunPlayer] { Array(players.filter { !$0.out }.prefix(5)) }
    public var human: RunPlayer? { players.first { $0.isHuman } }
    public func player(_ id: String) -> RunPlayer? { players.first { $0.id == id } }

    public mutating func update(_ id: String, _ f: (inout RunPlayer) -> Void) {
        guard let i = players.firstIndex(where: { $0.id == id }) else { return }
        f(&players[i])
    }

    public var remainingDrills: [String] { EndlessRun.drills.filter { !played.contains($0) } }
    public var finaleUnlocked: Bool { cycle == 1 && remainingDrills.isEmpty }
    public var finaleReached: Bool { history.contains { $0.finale } }

    /// What can be played next.
    public var nextChoices: [String] {
        if cycle == 1 { return finaleUnlocked ? [EndlessRun.finaleId] : remainingDrills }
        return EndlessRun.drills + EndlessRun.later
    }

    public func examUsed(_ playerId: String) -> Bool {
        player(playerId)?.exams.contains { $0.interlude == interlude } ?? true
    }

    public func eligible(_ playerId: String, _ library: [CertificateDef]) -> [CertificateDef] {
        guard let p = player(playerId) else { return [] }
        return library.filter { c in
            !p.has(c.id) && p.level >= c.minLevel && c.requires.allSatisfy { p.has($0) } && c.questions.count >= c.count
        }
    }

    /// Why a certificate can't be taken yet (nil = it can).
    public func lockReason(_ playerId: String, _ c: CertificateDef) -> String? {
        guard let p = player(playerId) else { return "" }
        if p.has(c.id) { return L("已取得", "Already held") }
        if p.level < c.minLevel { return L("需要 Lv\(c.minLevel)", "Needs Lv \(c.minLevel)") }
        if let missing = c.requires.first(where: { !p.has($0) }) {
            let n = ExamLibrary.cert(missing)?.name(lang) ?? missing
            return L("需要先取得「\(n)」", "Needs “\(n)” first")
        }
        if c.questions.count < c.count { return L("题库还没准备好", "Question bank not ready") }
        return nil
    }

    /// Short label for the chapter about to be played / being played ("Chapter 3", "Finale", "Endless · 4").
    public func chapterLabel(_ n: Int, finale: Bool) -> String {
        if finale { return L("终章", "Finale") }
        return L("第 \(n) 关", "Chapter \(n)")
    }

    /// FNV-1a: stable across launches (Swift's own hashing is not).
    static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 1469598103934665603
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return h
    }

    static func mix(_ a: UInt64, _ b: UInt64) -> UInt64 {
        var r = SeededRNG(seed: a &+ 0x9E37 &* (b &+ 1))
        return r.next() % 900_000 + 1
    }

    // MARK: Planning a chapter

    /// Assigns roles and computes what every player brings. `scenario` is the localized base scenario.
    public func makePlan(_ scenario: Scenario, humanRole: String?, library: [CertificateDef]) -> ChapterPlan {
        let number = chapter + 1
        let finale = scenario.id == EndlessRun.finaleId
        let seed = EndlessRun.mix(self.seed, UInt64(number))
        var rng = SeededRNG(seed: seed ^ 0xCA57)
        let team = active
        let roles = scenario.characters.map(\.id)
        var assignment: [String: String] = [:]   // character → player
        if finale {
            for (i, cid) in roles.enumerated() where i < team.count { assignment[cid] = team[i].id }
        } else {
            var freeRoles = roles
            var freePlayers = team.map(\.id)
            let randomRole = rng.pick(freeRoles)
            if let h = team.first(where: { $0.isHuman }), let role = humanRole ?? randomRole, freeRoles.contains(role) {
                assignment[role] = h.id
                freeRoles.removeAll { $0 == role }
                freePlayers.removeAll { $0 == h.id }
            }
            let shuffled = rng.shuffled(freePlayers)
            for (i, cid) in freeRoles.enumerated() where i < shuffled.count { assignment[cid] = shuffled[i] }
        }

        var cast: [String: CastEntry] = [:]
        for cid in roles {
            guard let pid = assignment[cid], let p = player(pid), let def = scenario.character(cid) else { continue }
            var skills: [String: Int] = [:]
            for s in Skill.all {
                let base = finale ? EndlessRun.personaBase(s, p.persona) : def.skill(s)
                skills[s] = min(Progression.skillCap, base + p.bonus(s, library))
            }
            let perks = p.perks(library)
            var relations = def.relations ?? [:]
            for (ocid, opid) in assignment where ocid != cid {
                let carried = (bonds[pid]?[opid] ?? 0) * 0.4
                let base = finale ? 0 : (relations[ocid] ?? 0)
                relations[ocid] = min(60, max(-60, base + carried))
            }
            var e = CastEntry(playerId: pid, skills: skills, perks: perks, cloBonus: perks.contains("warm") ? 0.3 : 0, relations: relations)
            if p.resolve < Progression.baseResolve { e.morale = Double(40 + 5 * max(0, p.resolve)) }
            if finale {
                e.persona = p.persona
                e.role = L("学员 · Lv\(p.level)", "Trainee · Lv \(p.level)")
                e.bio = careerBio(p, library)
                e.personality = finalePersonality(p)
                e.voice = Personas.voice(p.persona.temperament, lang)
                e.traits = finaleTraits(p)
            }
            cast[cid] = e
        }

        var mutators: [String] = []
        if cycle >= 2 {
            let n = min(3, 1 + depth / 3)
            var pool = Mutators.all.filter { Mutators.applicable($0, scenario) }
            for _ in 0..<n {
                guard let m = rng.pick(pool) else { break }
                mutators.append(m)
                pool.removeAll { $0 == m || Mutators.conflicts($0, m) }
            }
        }
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        let gameId = "\(f.string(from: Date()))-\(scenario.id)-c\(number)"
        return ChapterPlan(number: number, scenarioId: scenario.id, finale: finale, cycle: cycle, seed: seed, gameId: gameId, cast: cast, mutators: mutators)
    }

    /// Starts playing a planned chapter.
    public mutating func begin(_ plan: ChapterPlan) {
        current = plan
        chapter = plan.number
        phase = .chapter
        lastReport = nil
        for i in players.indices { players[i].refundable = nil }
    }

    /// A player's own skills in the finale, before training: a little of everything; strength from age.
    static func personaBase(_ skill: String, _ p: Persona) -> Int {
        if skill == "strength" { return p.age < 36 ? 2 : 1 }
        return 1
    }

    func careerBio(_ p: RunPlayer, _ library: [CertificateDef]) -> String {
        let roles = p.history.filter { !$0.finale }.map { L("\($0.scenarioTitle)里的\($0.characterName)", "\($0.characterName) in \($0.scenarioTitle)") }
        let certs = p.certs.compactMap { r in library.first { $0.id == r.id }?.name(lang) }
        var s = L("训练营学员。在 \(roles.count) 场推演里演过：\(roles.isEmpty ? "——" : roles.joined(separator: "、"))。",
                  "A trainee. Played \(roles.count) drill(s): \(roles.isEmpty ? "—" : roles.joined(separator: "; ")).")
        s += certs.isEmpty ? L("还没有资格证。", " No certificates yet.") : L("持有：\(certs.joined(separator: "、"))。", " Holds: \(certs.joined(separator: ", ")).")
        return s
    }

    func finalePersonality(_ p: RunPlayer) -> String {
        var s = Personas.personality(p.persona.temperament, lang)
        let t = p.totals
        if t.cared >= 8 { s += L("推演里照顾过很多伤员。", " Looked after a lot of injured people in the drills.") }
        if t.led >= 8 { s += L("常常被推出来拿主意。", " Often ended up being the one who decides.") }
        if t.thefts >= 2 { s += L("推演里不止一次偷吃过公共物资，自己心里清楚。", " Stole from the common supplies more than once in the drills, and knows it.") }
        if t.deaths >= 2 { s += L("在推演里“死”过好几次，知道什么叫怕。", " \"Died\" several times in the drills and knows what fear is.") }
        if t.survived >= 6 { s += L("几乎每一场都活着走了出来。", " Walked out of nearly every drill alive.") }
        return s
    }

    func finaleTraits(_ p: RunPlayer) -> TraitsDef {
        var t = Personas.traits(p.persona.temperament)
        let thefts = Double(min(3, p.totals.thefts)), cared = Double(min(20, p.totals.cared))
        t.selfish = min(0.95, max(0.05, (t.selfish ?? 0.4) + 0.08 * thefts - 0.01 * cared))
        t.brave = min(0.95, max(0.05, (t.brave ?? 0.5) + 0.02 * Double(min(10, p.totals.survived))))
        return t
    }

    // MARK: Building the chapter

    /// The scenario as this chapter plays it: roles carry the players' skills and know-how; mutators applied.
    /// Depends only on the plan and the base scenario (in the run's language).
    public static func buildScenario(_ base: Scenario, plan: ChapterPlan, lang: Lang) -> Scenario {
        var s = base
        for i in s.characters.indices {
            let cid = s.characters[i].id
            guard let e = plan.cast[cid] else { continue }
            var c = s.characters[i]
            c.skills = e.skills
            c.perks = e.perks.isEmpty ? nil : e.perks
            c.clo += e.cloBonus
            var rel = c.relations ?? [:]
            for (k, v) in e.relations { rel[k] = v }
            c.relations = rel
            if let m = e.morale { c.morale = m }
            if let p = e.persona {
                c.name = p.name
                c.gender = lang == .en ? (p.female ? "female" : "male") : (p.female ? "女" : "男")
                c.age = p.age
                c.weight = p.weight
                c.fat = p.fat
                if let r = e.role { c.role = r }
                if let b = e.bio { c.bio = b }
                if let pe = e.personality { c.personality = pe }
                if let v = e.voice { c.voice = v }
                if let t = e.traits { c.traits = t }
            }
            s.characters[i] = c
        }
        for m in plan.mutators { Mutators.apply(m, to: &s, cast: Array(plan.cast.keys).sorted(), lang: lang) }
        return s
    }

    /// The game setup for a chapter: who controls whom, the LLM players' career memory, the chapter tag.
    public func setup(for plan: ChapterPlan, scenario: Scenario, library: [CertificateDef]) -> GameSetup {
        var controllers: [String: ControllerKind] = [:]
        var notes: [String: String] = [:]
        var seats: [String: SeatTag] = [:]
        for (cid, e) in plan.cast {
            guard let p = player(e.playerId) else { continue }
            switch p.seat {
            case "human": controllers[cid] = .human
            case "rule": controllers[cid] = .rule
            default: controllers[cid] = .llm(seat: p.seat, label: p.controllerLabel)
            }
            if p.isLLM { notes[cid] = careerNote(p, plan: plan, scenario: scenario, library: library) }
            seats[cid] = SeatTag(playerId: p.id, name: p.name, level: p.level, certs: p.certs.compactMap { r in library.first { $0.id == r.id }?.name(lang) })
        }
        var setup = GameSetup(scenarioId: scenario.id, seed: plan.seed, controllers: controllers, debate: options.debate, spectator: options.spectator, language: lang)
        setup.notes = notes
        setup.chapter = ChapterTag(runId: id, number: plan.number, finale: plan.finale, seats: seats, mutators: plan.mutators.map { Mutators.name($0, lang) })
        return setup
    }

    /// 【你的经历】: what an LLM player remembers of the run (D-039).
    func careerNote(_ p: RunPlayer, plan: ChapterPlan, scenario: Scenario, library: [CertificateDef]) -> String {
        var out: [String] = []
        let certs = p.certs.compactMap { r in library.first { $0.id == r.id }?.name(lang) }
        out.append(L("【你的经历】（玩家之间的记忆，不是这个角色的记忆）", "[Your record] (memories between players — not this character's memories)"))
        out.append(L("你是这个训练营里的玩家「\(p.name)」：Lv\(p.level)，心力 \(p.resolve)/\(p.maxResolve)，资格证：\(certs.isEmpty ? "无" : certs.joined(separator: "、"))。",
                     "You are the player \"\(p.name)\" in this training camp: Lv \(p.level), resolve \(p.resolve)/\(p.maxResolve), certificates: \(certs.isEmpty ? "none" : certs.joined(separator: ", "))."))
        if plan.finale {
            out.append(L("这是终章：这一次不是推演，你演的就是你自己。前面每一关学到的东西，现在都要用上。",
                         "This is the finale: this time it is not a drill — you are playing yourself. Everything you learned in the drills counts now."))
        } else {
            if options.hardcore {
                out.append(L("这是第 \(plan.number) 关推演（根据真实灾难做的全真模拟）。死在推演里会损失心力；心力耗尽就会离开训练营（铁人模式）。",
                             "This is drill \(plan.number) (a full simulation of a real disaster). Dying in a drill costs resolve; run out of resolve and you leave the camp (iron mode)."))
            } else {
                out.append(L("这是第 \(plan.number) 关推演（根据真实灾难做的全真模拟）。死在推演里会损失心力，心力低了下一关就会更消沉；活着走出来、帮别人、把事做成，都会让你成长。",
                             "This is drill \(plan.number) (a full simulation of a real disaster). Dying in a drill costs resolve, and low resolve weighs on you in the next one; walking out alive, helping others and getting things done all make you grow."))
            }
        }
        for h in p.history.suffix(8) {
            let how = h.survived ? L("活了下来", "survived") : h.fate
            out.append(L("- 第 \(h.chapter) 关《\(h.scenarioTitle)》你演\(h.characterName)：\(how)", "- Chapter \(h.chapter), \(h.scenarioTitle): you played \(h.characterName) — \(how)"))
        }
        if let lessons = p.lessons, !lessons.isEmpty {
            out.append(L("你自己记下的教训：", "Lessons you wrote down yourself:"))
            for l in lessons.suffix(5) { out.append("  · \(l)") }
        }
        var others: [String] = []
        for (cid, e) in plan.cast.sorted(by: { $0.key < $1.key }) where e.playerId != p.id {
            guard let o = player(e.playerId) else { continue }
            let who = scenario.character(cid)?.name ?? cid
            var line = L("「\(o.name)」演\(who)", "\"\(o.name)\" plays \(who)")
            let b = bonds[p.id]?[o.id] ?? 0
            if b >= 25 { line += L("（你们之前处得很好）", " (you got on well before)") } else if b <= -25 { line += L("（你们之前结过梁子）", " (there's bad blood between you)") }
            others.append(line)
        }
        if !others.isEmpty {
            out.append(L("这一关其他玩家：", "The other players this time: ") + others.joined(separator: L("；", "; ")))
            out.append(L("过去的恩怨可以带进来，也可以放下，由你决定。", "You may carry old grudges into this one, or let them go — your call."))
        }
        return out.joined(separator: "\n")
    }

    // MARK: Chapter results

    /// Settles a finished chapter: XP, levels, practice, resolve, departures, the report.
    @discardableResult
    public mutating func complete(_ engine: GameEngine, library: [CertificateDef]) -> ChapterReport? {
        guard let plan = current, let ending = engine.state.ending else { return nil }
        let s = engine.scenario
        let st = engine.state
        let finale = plan.finale
        let humanNPCs = (s.npcs ?? []).filter { !$0.isAnimal }
        let total = Double(max(1, s.characters.count + humanNPCs.count))
        let survivors = Double(st.characters.filter { $0.survived && $0.status != .notJoined && !engine.isAnimal($0.id) }.count)
        let anySurvived = plan.cast.keys.contains { cid in ending.results.first { $0.id == cid }?.survived ?? false }
        let cleared = anySurvived
        let firstClear = cleared && !finale && cycle == 1 && !self.cleared.contains(s.id)
        let wasUnlocked = finaleUnlocked
        let diff = 0.8 + 0.1 * Double(s.difficulty)

        var records: [String: PlayerChapter] = [:]
        var departures: [String] = []
        for (cid, e) in plan.cast.sorted(by: { $0.key < $1.key }) {
            guard let c = st.character(cid), let r = ending.results.first(where: { $0.id == cid }), let before = player(e.playerId) else { continue }
            let survived = r.survived
            let lastRound = c.deathRound ?? ending.round
            let days = Double(lastRound * s.clock.roundHours) / 24
            var items: [XPItem] = []
            if survived { items.append(XPItem(label: L("活了下来", "Survived"), xp: Int((100 * diff).rounded()))) }
            items.append(XPItem(label: L("撑过 \(Fmt.number(days, days < 10 ? 1 : 0)) 天", "Lasted \(Fmt.number(days, days < 10 ? 1 : 0)) days"), xp: min(150, Int((days * 12).rounded()))))
            if r.goalAchieved { items.append(XPItem(label: L("完成个人目标", "Personal goal"), xp: 60)) }
            let team = Int((60 * survivors / total).rounded())
            if team > 0 { items.append(XPItem(label: L("集体存活 \(Int(survivors))/\(Int(total))", "Group survival \(Int(survivors))/\(Int(total))"), xp: team)) }
            if ending.tone == "good" { items.append(XPItem(label: L("好结局", "Good ending"), xp: 40)) } else if ending.tone == "bitter" { items.append(XPItem(label: L("有代价的结局", "Bittersweet ending"), xp: 15)) }
            if c.stats.cared > 0 { items.append(XPItem(label: L("照顾伤员 \(c.stats.cared) 次", "Cared for the injured ×\(c.stats.cared)"), xp: min(60, 5 * c.stats.cared))) }
            if c.stats.roundsLed > 0 { items.append(XPItem(label: L("当领头人 \(c.stats.roundsLed) 回合", "Led for \(c.stats.roundsLed) round(s)"), xp: min(45, 3 * c.stats.roundsLed))) }
            if cleared { items.append(XPItem(label: L("全队通关", "Team cleared the chapter"), xp: 25)) }
            if firstClear { items.append(XPItem(label: L("第一次通过这个场景", "First clear of this scenario"), xp: 30)) }
            if finale && survived { items.append(XPItem(label: L("活着走出终章", "Walked out of the finale"), xp: 200)) }
            let xp = items.map(\.xp).reduce(0, +)

            var p = before
            let levelBefore = p.level, resolveBefore = p.resolve
            p.gain(xp)
            var practice: [String: Int] = [:]
            for (k, v) in c.stats.skillUse ?? [:] where Progression.trainable.contains(k) { practice[k] = v }
            let free = p.addPractice(practice)
            let fallen = !survived && c.status != .gone
            if finale {
                if !survived { p.resolve = 0 }
            } else if survived {
                p.resolve = min(p.maxResolve, p.resolve + 1)
            } else if fallen {
                p.resolve = max(0, p.resolve - 1)
            }
            p.totals.chapters += 1
            if survived { p.totals.survived += 1 }
            if c.status == .dead { p.totals.deaths += 1 }
            if c.status == .exiled { p.totals.exiled += 1 }
            if r.goalAchieved { p.totals.goals += 1 }
            p.totals.cared += c.stats.cared
            p.totals.thefts += c.stats.thefts
            p.totals.caught += c.stats.caught
            p.totals.led += c.stats.roundsLed
            let rec = PlayerChapter(chapter: plan.number, scenarioId: s.id, scenarioTitle: s.title, characterId: cid, characterName: engine.name(cid),
                                    survived: survived, status: c.status.rawValue, fate: r.fate, deathCause: c.deathCause, goalAchieved: r.goalAchieved,
                                    xp: xp, breakdown: items, levelBefore: levelBefore, levelAfter: p.level, resolveBefore: resolveBefore, resolveAfter: p.resolve,
                                    practice: practice, freeRanks: free, cared: c.stats.cared, thefts: c.stats.thefts, caught: c.stats.caught,
                                    led: c.stats.roundsLed, finale: finale)
            p.history.append(rec)
            // Normal mode: a drill never throws anyone out (low resolve only costs morale). The finale, and iron mode, do.
            if p.resolve <= 0 && (finale || options.hardcore) {
                p.out = true
                p.outChapter = plan.number
                departures.append(p.id)
            }
            records[p.id] = rec
            let pid = p.id
            update(pid) { $0 = p }
        }

        // Feelings between players carry over (end-of-chapter trust, smoothed).
        for (cid, e) in plan.cast {
            guard let c = st.character(cid) else { continue }
            for (ocid, oe) in plan.cast where ocid != cid {
                let t = c.trust[ocid] ?? 0
                let old = bonds[e.playerId]?[oe.playerId] ?? 0
                bonds[e.playerId, default: [:]][oe.playerId] = min(60, max(-60, old * 0.7 + t * 0.3))
            }
        }

        if cleared && cycle == 1 && !finale && !self.cleared.contains(s.id) { self.cleared.append(s.id) }
        if cycle == 1 && !finale && !played.contains(s.id) { played.append(s.id) }
        attempts[s.id, default: 0] += 1
        if cycle >= 2 { depth += 1 }
        let lines = plan.cast.sorted(by: { $0.key < $1.key }).compactMap { (cid, e) -> SummaryLine? in
            guard let r = ending.results.first(where: { $0.id == cid }), let p = player(e.playerId) else { return nil }
            return SummaryLine(playerId: p.id, playerName: p.name, characterName: r.name, survived: r.survived, fate: r.fate)
        }
        let others = ending.others ?? []
        let npcPeople = others.filter { o in !(s.character(o.id)?.isAnimal ?? false) }
        history.append(ChapterSummary(number: plan.number, scenarioId: s.id, title: s.title, endingTitle: ending.title, tone: ending.tone, cleared: cleared,
                                      finale: finale, cycle: plan.cycle, mutators: plan.mutators, lines: lines,
                                      npcSaved: npcPeople.filter(\.survived).count, npcLost: npcPeople.filter { !$0.survived }.count))

        // Replace AI players who went out (not right after the finale: the dead stay dead; newcomers
        // join only if the run goes on — see continueEndless).
        var recruitsNow: [String] = []
        let humanOut = departures.contains { player($0)?.isHuman ?? false }
        if !humanOut && !finale {
            for d in departures {
                guard let gone = player(d), !gone.isHuman else { continue }
                recruitsNow.append(recruit(replacing: gone))
            }
        }

        let report = ChapterReport(number: plan.number, scenarioId: s.id, scenarioTitle: s.title, endingTitle: ending.title, endingText: ending.text,
                                   tone: ending.tone, cleared: cleared, firstClear: firstClear, finaleUnlocked: !wasUnlocked && finaleUnlocked,
                                   players: records, departures: departures, recruits: recruitsNow)
        lastReport = report
        current = nil
        interlude += 1

        if finale {
            grand = GrandEndings.compose(self, reason: .finale, finaleEnding: ending, library: library)
            phase = .finaleDone
        } else if humanOut {
            grand = GrandEndings.compose(self, reason: .fallen, finaleEnding: nil, library: library)
            phase = .ended
        } else if options.spectator && active.isEmpty {
            grand = GrandEndings.compose(self, reason: .fallen, finaleEnding: nil, library: library)
            phase = .ended
        } else {
            phase = .hub
        }
        return report
    }

    /// A newcomer takes over a seat whose player left. Starts a couple of levels below the team.
    @discardableResult
    public mutating func recruit(replacing gone: RunPlayer) -> String {
        recruits += 1
        var rng = SeededRNG(seed: EndlessRun.mix(seed, UInt64(1000 + recruits)))
        let taken = Set(players.map(\.name))
        let persona = Personas.make(&rng, lang: lang, taken: taken)
        let team = active.filter { $0.id != gone.id }
        let avg = team.isEmpty ? 1 : team.map(\.level).reduce(0, +) / team.count
        let level = max(1, avg - 2)
        var p = RunPlayer(id: "r\(recruits)", persona: persona, seat: gone.seat, controllerLabel: gone.controllerLabel,
                          resolve: Progression.baseResolve, joinedChapter: chapter + 1)
        p.gain(Progression.xpAt(level))
        players.append(p)
        return p.id
    }

    // MARK: Exams

    /// Records an exam sitting: a pass gives the certificate, 2 skill points (+1 for a perfect score) and XP.
    public mutating func recordExam(_ playerId: String, _ record: ExamRecord, library: [CertificateDef]) {
        let interlude = self.interlude
        update(playerId) { p in
            var r = record
            r.interlude = interlude
            p.exams.append(r)
            p.totals.examsTaken += 1
            guard r.passed, !p.has(r.certId) else { return }
            p.totals.examsPassed += 1
            p.certs.append(CertRecord(id: r.certId, interlude: interlude, score: r.score, total: r.total))
            p.points += r.perfect ? 3 : 2
            p.gain(r.perfect ? 70 : 50)
            if library.first(where: { $0.id == r.certId })?.perk == "calm" { p.resolve = min(p.maxResolve, p.resolve + 1) }
        }
    }

    // MARK: Ending the run

    /// The player calls it a day.
    public mutating func retire(library: [CertificateDef]) {
        if grand == nil || !finaleReached {
            grand = GrandEndings.compose(self, reason: .retired, finaleEnding: nil, library: library)
        } else {
            let add = GrandEndings.endlessAddendum(self)
            grand?.addendum = add
        }
        phase = .ended
    }

    /// After reading the grand ending: keep going (endless) …
    public mutating func continueEndless() {
        guard phase == .finaleDone else { return }
        cycle = max(2, cycle + 1)
        // new trainees take the seats of those who died in the finale (same AI model behind the seat)
        let fallen = players.filter { $0.out && !$0.isHuman && $0.history.last?.finale == true }
        for f in fallen where active.count < 5 {
            let id = recruit(replacing: f)
            lastReport?.recruits.append(id)
        }
        phase = .hub
    }

    /// … or close the book.
    public mutating func close() {
        if phase == .finaleDone || phase == .hub { phase = .ended }
    }

    /// Whether the human can still go on after the finale (they must have walked out of it).
    public var canContinue: Bool {
        guard phase == .finaleDone else { return false }
        if options.spectator { return !active.isEmpty }
        return !(human?.out ?? true)
    }
}

// MARK: - Mutators (endless after the finale)

public enum Mutators {
    public static let all = ["cold_snap", "heat_wave", "short_supply", "no_meds", "old_wounds", "storm_season", "distrust"]

    public static func name(_ id: String, _ lang: Lang) -> String {
        switch id {
        case "cold_snap": return Loc.pick("寒潮", "Cold snap", lang)
        case "heat_wave": return Loc.pick("热浪", "Heat wave", lang)
        case "short_supply": return Loc.pick("物资紧缺", "Short on supplies", lang)
        case "no_meds": return Loc.pick("缺医少药", "Few medicines", lang)
        case "old_wounds": return Loc.pick("旧伤未愈", "Old wounds", lang)
        case "storm_season": return Loc.pick("风暴季", "Storm season", lang)
        case "distrust": return Loc.pick("互不信任", "Distrust", lang)
        default: return id
        }
    }

    public static func describe(_ id: String, _ lang: Lang) -> String {
        switch id {
        case "cold_snap": return Loc.pick("气温整体低 4°C", "Everything 4 °C colder", lang)
        case "heat_wave": return Loc.pick("气温整体高 4°C", "Everything 4 °C hotter", lang)
        case "short_supply": return Loc.pick("开局的食物和水只有七成", "Only 70% of the usual food and water at the start", lang)
        case "no_meds": return Loc.pick("急救用品和药品只剩四成", "Only 40% of the usual first-aid kits and medicines", lang)
        case "old_wounds": return Loc.pick("每个玩家角色开局都带着一处旧伤", "Every player character starts with an old injury", lang)
        case "storm_season": return Loc.pick("庇护所一开始就破了一块", "The shelter starts out damaged", lang)
        case "distrust": return Loc.pick("玩家角色之间的信任一开始就低", "The player characters start out distrusting each other", lang)
        default: return ""
        }
    }

    static func applicable(_ id: String, _ s: Scenario) -> Bool {
        switch id {
        case "cold_snap": return s.climate.tempLow < 15
        case "heat_wave": return s.climate.tempHigh > 24
        case "no_meds": return (s.resource("medkit")?.initial ?? 0) + (s.resource("antibiotics")?.initial ?? 0) > 0
        case "storm_season": return s.shelter.integrity > 30
        default: return true
        }
    }

    static func conflicts(_ a: String, _ b: String) -> Bool {
        Set([a, b]) == Set(["cold_snap", "heat_wave"])
    }

    static func apply(_ id: String, to s: inout Scenario, cast: [String], lang: Lang) {
        switch id {
        case "cold_snap":
            s.climate.tempHigh -= 4
            s.climate.tempLow -= 4
        case "heat_wave":
            s.climate.tempHigh += 4
            s.climate.tempLow += 4
        case "short_supply":
            scale(&s, ["food", "water"], 0.7)
        case "no_meds":
            scale(&s, ["medkit", "antibiotics"], 0.4)
        case "old_wounds":
            for (i, cid) in cast.enumerated() {
                guard let idx = s.characters.firstIndex(where: { $0.id == cid }) else { continue }
                let sprain = i % 2 == 0
                let partKey = sprain ? "脚踝" : "手臂"
                let part = lang == .en ? (sprain ? "ankle" : "arm") : partKey
                let inj = InjuryInit(kind: sprain ? "sprain" : "laceration", severity: 18, part: part, label: nil, treated: false, partKey: partKey, labelKey: nil)
                s.characters[idx].injuries = (s.characters[idx].injuries ?? []) + [inj]
            }
        case "storm_season":
            s.shelter.integrity = max(20, s.shelter.integrity - 20)
        case "distrust":
            for cid in cast {
                guard let idx = s.characters.firstIndex(where: { $0.id == cid }) else { continue }
                var rel = s.characters[idx].relations ?? [:]
                for o in cast where o != cid { rel[o] = (rel[o] ?? 0) - 15 }
                s.characters[idx].relations = rel
            }
        default: break
        }
    }

    static func scale(_ s: inout Scenario, _ ids: [String], _ f: Double) {
        for i in s.resources.indices where ids.contains(s.resources[i].id) {
            let r = s.resources[i]
            var v = r.initial * f
            if (r.decimals ?? 0) == 0 { v = v.rounded(.down) }
            s.resources[i].initial = v
        }
    }
}
