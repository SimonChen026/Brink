import Foundation

/// The simulation engine. Owns the game state and applies the scenario rules.
/// It never talks to LLMs: controllers collect decisions and feed them in.
public final class GameEngine {
    public let scenario: Scenario
    public var state: GameState
    /// Tonight's arrangements (D-053): set when the night is resolved, used by that round's rations and
    /// physiology, cleared at the end of the round — never saved.
    var tonightRationGifts: [(from: String, to: String, portion: Double)] = []
    var tonightStashWater: [String: Double] = [:]
    var tonightHuddles: [String: String] = [:]

    // MARK: Init

    public init(scenario: Scenario, setup: GameSetup) {
        self.scenario = scenario
        var rng = SeededRNG(seed: setup.seed)
        let rd = scenario.rationDef

        var chars: [CharacterState] = []
        for def in scenario.characters {
            chars.append(GameEngine.makeCharacter(def, isNPC: false, rng: &rng))
        }
        for def in scenario.npcs ?? [] {
            chars.append(GameEngine.makeCharacter(def, isNPC: true, rng: &rng))
        }

        var resources: [String: Double] = [:]
        for r in scenario.resources { resources[r.id] = r.initial }
        // harder settings start with less, and lower spirits (D-053)
        let level = setup.level
        if level != .normal {
            for r in scenario.resources {
                var v = r.initial * level.startScale
                if (r.decimals ?? 0) == 0 { v = v.rounded() }
                resources[r.id] = v
            }
            for i in chars.indices { chars[i].morale = max(0, min(100, chars[i].morale + level.moraleOffset)) }
        }
        var vars: [String: Double] = [:]
        for v in scenario.vars ?? [] { vars[v.id] = v.initial }
        var pools: [String: [Int]] = [:]
        for (pid, pool) in scenario.pools ?? [:] {
            pools[pid] = pool.items.map { $0.stock ?? -1 }
        }

        let cold = scenario.climate.tempLow < 8
        let policy = Policy(
            food: rd.food[min(max(0, rd.defaultFood), rd.food.count - 1)],
            water: rd.water[min(max(0, rd.defaultWater), rd.water.count - 1)],
            fire: scenario.shelter.fire != nil && cold,
            priority: "equal"
        )

        self.state = GameState(
            scenarioId: scenario.id,
            setup: setup,
            rng: rng,
            round: 1,
            phase: .situation,
            characters: chars,
            resources: resources,
            vars: vars,
            flags: [],
            projects: [:],
            projectsDone: [],
            poolStock: pools,
            weather: scenario.climate.initialWeather,
            forcedWeather: nil,
            forcedWeatherRounds: 0,
            dayHigh: scenario.climate.tempHigh,
            dayLow: scenario.climate.tempLow,
            tempDay: 0,
            shelterIntegrity: scenario.shelter.integrity,
            leader: nil,
            policy: policy,
            firedEvents: [:],
            scheduled: [],
            eventQueue: [],
            currentEvent: nil,
            pendingMotions: [],
            assignments: [:],
            guards: [],
            log: [],
            nextId: 1,
            ending: nil,
            fireLit: false,
            antibioticsGiven: [],
            stolenTonight: 0,
            foodAtDawn: 0
        )
        rollDayTemperatures(day: currentDay)
        for p in scenario.briefing.prefix(1) {
            log(.system, p)
        }
        run(scenario.onStart, EffCtx())
        beginRound(first: true)
    }

    /// Resume from a saved state.
    public init(scenario: Scenario, state: GameState) {
        self.scenario = scenario
        self.state = state
    }

    /// Starting injuries (from the scenario) are numbered from here, well clear of `state.nextId`.
    static let startingInjuryIds = 100_000

    static func makeCharacter(_ def: CharacterDef, isNPC: Bool, rng: inout SeededRNG) -> CharacterState {
        var injuries: [Injury] = []
        var nextLocal = startingInjuryIds + rng.int(0, 9999) * 10
        for inj in def.injuries ?? [] {
            injuries.append(Injury(id: nextLocal, kind: inj.kind, severity: inj.severity, part: inj.part, label: inj.label, treated: inj.treated ?? false,
                                   partKey: inj.partKey ?? inj.part, labelKey: inj.labelKey ?? inj.label))
            nextLocal += 1
        }
        var trust: [String: Double] = [:]
        for (k, v) in def.relations ?? [:] { trust[k] = v }
        return CharacterState(
            id: def.id,
            isNPC: isNPC,
            status: (def.joinsLater ?? false) ? .notJoined : .active,
            health: Buffs.healthCap(def),
            core: 37,
            thirst: 0,
            fatKg: def.weight * def.fat,
            energyEMA: 1,
            fatigue: 20,
            morale: def.morale ?? 55,
            clo: def.clo,
            wetHours: 0,
            injuries: injuries,
            items: def.items ?? [:],
            stash: def.stash ?? [:],
            trust: trust,
            secretRevealed: false,
            awayRounds: 0,
            awayReturn: nil,
            deathRound: nil,
            deathCause: nil,
            punishedRounds: 0,
            diary: [],
            lastTask: nil,
            lastIntake: 0,
            lastNeed: 0,
            lastWater: 0,
            stats: CharacterStats()
        )
    }

    // MARK: Helpers

    /// Language of this game's generated text.
    public var lang: Lang { state.setup.lang }

    /// The Chinese or English text, by this game's language.
    public func L(_ zh: @autoclosure () -> String, _ en: @autoclosure () -> String) -> String { lang == .en ? en() : zh() }

    public func name(_ id: String?) -> String {
        guard let id else { return L("某人", "someone") }
        return scenario.character(id)?.name ?? id
    }

    public func isAnimal(_ id: String) -> Bool { scenario.character(id)?.isAnimal ?? false }

    /// Endless mode: know-how the player brings into this role (see CharacterDef.perks).
    public func hasPerk(_ id: String, _ perk: String) -> Bool { scenario.character(id)?.hasPerk(perk) ?? false }

    /// Counts one use of a skill by a player character (practice for endless-mode progression).
    func practice(_ id: String?, _ skill: String, _ n: Int = 1) {
        guard let id, let i = state.index(of: id), !state.characters[i].isNPC else { return }
        state.characters[i].stats.skillUse = (state.characters[i].stats.skillUse ?? [:]).merging([skill: n], uniquingKeysWith: +)
    }

    /// Who plays this character, as shown in results ("Sean Shen · DeepSeek" in an endless run).
    public func playedBy(_ id: String) -> String {
        let c = controller(id).label(lang)
        guard let seat = state.setup.chapter?.seats[id] else { return c }
        if controller(id).isHuman { return seat.name }
        return "\(seat.name) · \(c)"
    }

    public func controller(_ id: String) -> ControllerKind {
        state.setup.controllers[id] ?? .rule
    }

    public var isOver: Bool { state.phase == .ended }

    public var roundLabel: String {
        let tpl = scenario.clock.roundLabel ?? L("第{day}天", "Day {day}")
        let hours = roundStartHour
        return tpl
            .replacingOccurrences(of: "{day}", with: String(currentDay))
            .replacingOccurrences(of: "{round}", with: String(state.round))
            .replacingOccurrences(of: "{hours}", with: String(hours))
    }

    public var clockLabel: String {
        let h = currentClockHour
        let part: String
        switch h {
        case 5..<9: part = L("清晨", "Dawn")
        case 9..<12: part = L("上午", "Morning")
        case 12..<14: part = L("中午", "Noon")
        case 14..<18: part = L("下午", "Afternoon")
        case 18..<22: part = L("傍晚", "Evening")
        default: part = L("深夜", "Night")
        }
        return String(format: "%@ %02d:00", part, h)
    }

    @discardableResult
    func log(_ kind: LogKind, _ text: String, detail: String? = nil, actor: String? = nil, target: String? = nil, vis: Visibility = .everyone) -> Int {
        let entry = LogEntry(id: state.nextId, round: state.round, kind: kind, text: text, detail: detail, actor: actor, target: target, visibility: vis, phase: state.phase.rawValue)
        state.nextId += 1
        state.log.append(entry)
        return entry.id
    }

    func mutate(_ id: String, _ f: (inout CharacterState) -> Void) {
        guard let i = state.index(of: id) else { return }
        f(&state.characters[i])
    }

    // MARK: Round start

    func beginRound(first: Bool = false) {
        state.phase = .situation
        state.assignments = [:]
        state.guards = []
        state.stolenTonight = 0
        state.foodAtDawn = state.resources["food"] ?? 0

        // Weather transition
        let weatherBefore = state.weather
        if !first {
            if let forced = state.forcedWeather, state.forcedWeatherRounds > 0 {
                state.weather = forced
                state.forcedWeatherRounds -= 1
                if state.forcedWeatherRounds <= 0 { state.forcedWeather = nil }
            } else {
                let w = weatherDef
                let keys = w.next.keys.sorted()
                if let idx = state.rng.weightedIndex(keys.map { w.next[$0] ?? 0 }) {
                    state.weather = keys[idx]
                }
            }
        }
        let day = currentDay
        // Re-roll today's temperatures when the day changed or the weather changed, so that the
        // weather shown and the temperatures simulated always agree.
        if day != state.tempDay || first || state.weather != weatherBefore { rollDayTemperatures(day: day) }

        morningReport(first: first)
        ambientLine()
        buildEventQueue(first: first)
        advanceEvent()
    }

    func morningReport(first: Bool) {
        let w = weatherDef
        let text = "\(roundLabel) · \(clockLabel) · \(w.name) \(Fmt.temp(state.dayLow)) ~ \(Fmt.temp(state.dayHigh))"
        var detail: [String] = []
        let alive = Double(state.characters.filter { $0.alive }.count)
        if alive > 0, let food = state.resources["food"] {
            // at the current ration (the same figure the AI players are given)
            let perDay = state.policy.food > 0 ? state.policy.food : 2000
            let d = String(format: "%.1f", food / (alive * perDay))
            detail.append(L("食物 \(Fmt.amount(food, "food", scenario))（按现在的配给够全员约 \(d) 天）", "Food: \(Fmt.amount(food, "food", scenario)) (≈\(d) days for everyone at the current ration)"))
        }
        if let water = state.resources["water"] {
            detail.append(L("饮用水 \(Fmt.amount(water, "water", scenario))", "Water: \(Fmt.amount(water, "water", scenario))"))
        }
        for v in scenario.vars ?? [] where v.show ?? false {
            let value = Fmt.variable(state.vars[v.id] ?? 0, v, lang)
            detail.append(L("\(v.name) \(value)", "\(v.name): \(Loc.lowerFirst(value, lang))"))
        }
        var detailText = detail.joined(separator: Loc.semi(lang))
        if let d = w.desc, !d.isEmpty {
            let desc: String
            if lang == .en {
                desc = (d.hasSuffix(".") || d.hasSuffix("。") ? d : d + ".") + (detailText.isEmpty ? "" : " ")
            } else {
                desc = d.hasSuffix("。") ? d : d + "。"
            }
            detailText = desc + detailText
        }
        log(.report, text, detail: detailText)
    }

    /// Now and then an NPC says something (flavor; no effect on the simulation).
    func ambientLine() {
        let talkers = state.characters.filter { c in
            c.present && c.isNPC && !(scenario.character(c.id)?.lines ?? []).isEmpty
        }
        guard !talkers.isEmpty, state.rng.chance(0.4) else { return }
        guard let who = state.rng.pick(talkers), let line = state.rng.pick(scenario.character(who.id)?.lines ?? []) else { return }
        log(.speech, render(line, EffCtx(actor: who.id)), actor: who.id)
    }

    // MARK: Events

    func buildEventQueue(first: Bool) {
        var queue: [ActiveEvent] = []

        // 1. A pending motion from last night (dropped if the proposer didn't live to see the morning)
        let motions = state.pendingMotions
        state.pendingMotions.removeAll()
        if let m = motions.first(where: { m in m.proposer.map { state.character($0)?.present ?? false } ?? true }) {
            if let ev = makeMotionEvent(m) { queue.append(ev) }
        }

        // 2. Scheduled + scripted events (highest priority first)
        var candidates: [(EventDef, ScheduledEvent?)] = []
        for s in state.scheduled where s.round <= state.round {
            if let def = scenario.event(s.eventId) { candidates.append((def, s)) }
        }
        for def in scenario.events {
            guard let at = def.atRound, at <= state.round else { continue }
            if (def.once ?? true), state.firedEvents[def.id] != nil { continue }
            if candidates.contains(where: { $0.0.id == def.id }) { continue }
            if let maxR = def.maxRound, state.round > maxR { continue }
            if let w = def.when, !truthy(w, EffCtx()) { continue }
            candidates.append((def, nil))
        }
        candidates.sort { ($0.0.priority ?? 0) > ($1.0.priority ?? 0) }

        var scenarioEvent: ActiveEvent?
        for (def, sched) in candidates {
            // Help that hasn't had time to arrive yet waits for a later round (D-055).
            if isHeld(def.id) {
                if let sched, let i = state.scheduled.firstIndex(where: { $0.eventId == sched.eventId && $0.round == sched.round }) {
                    state.scheduled[i].round = state.round + 1
                }
                continue
            }
            // A scheduled event whose condition doesn't hold yet waits for a later round.
            if let sched, let w = def.when, !truthy(w, EffCtx(actor: sched.actor, target: sched.target)) {
                if let i = state.scheduled.firstIndex(where: { $0.eventId == sched.eventId && $0.round == sched.round }) {
                    state.scheduled[i].round = state.round + 1
                }
                continue
            }
            if let ev = activate(def, actor: sched?.actor, target: sched?.target) {
                scenarioEvent = ev
                if let sched { removeScheduled(sched) }
                break
            } else if let sched {
                // could not activate (e.g. nobody eligible) — drop it
                removeScheduled(sched)
            }
        }

        // 3. Random event
        if scenarioEvent == nil {
            var pool: [EventDef] = []
            var weights: [Double] = []
            for def in scenario.events {
                guard let w = def.weight, w > 0 else { continue }
                if def.atRound != nil || isHeld(def.id) { continue }
                if (def.once ?? true), state.firedEvents[def.id] != nil { continue }
                if let minR = def.minRound, state.round < minR { continue }
                if let maxR = def.maxRound, state.round > maxR { continue }
                if let cd = def.cooldown, let last = state.firedEvents[def.id], state.round - last < cd { continue }
                if let c = def.when, !truthy(c, EffCtx()) { continue }
                pool.append(def)
                weights.append(w)
            }
            var tries = 0
            while scenarioEvent == nil && !pool.isEmpty && tries < 6 {
                tries += 1
                guard let idx = state.rng.weightedIndex(weights) else { break }
                if let ev = activate(pool[idx]) {
                    scenarioEvent = ev
                } else {
                    pool.remove(at: idx)
                    weights.remove(at: idx)
                }
            }
        }
        if scenarioEvent == nil {
            scenarioEvent = quietEvent()
        }
        if let ev = scenarioEvent { queue.append(ev) }

        // 4. First round: pick a leader after the opening event
        if first && state.leader == nil {
            if let ev = makeMotionEvent(Motion(type: .elect, proposer: nil, target: nil)) { queue.append(ev) }
        }
        state.eventQueue = queue
    }

    /// Removes exactly one matching scheduled entry (others for the same event stay queued).
    func removeScheduled(_ sched: ScheduledEvent) {
        if let i = state.scheduled.firstIndex(where: { $0.eventId == sched.eventId && $0.round == sched.round && $0.actor == sched.actor && $0.target == sched.target }) {
            state.scheduled.remove(at: i)
        }
    }

    /// Pops the next queued event, or moves to the tasks phase.
    func advanceEvent() {
        while !state.eventQueue.isEmpty {
            var ev = state.eventQueue.removeFirst()
            // Re-check deciders (someone may have died in a previous event this morning)
            ev.deciders = ev.deciders.filter { state.character($0)?.present ?? false }
            if ev.deciders.isEmpty { continue }
            state.currentEvent = ev
            let ctx = EffCtx(actor: ev.protagonist, target: ev.motion?.target, protagonist: ev.protagonist)
            run(ev.def.pre, ctx)
            // the event's own opening may have cost someone their life: the dead don't vote
            let still = ev.deciders.filter { state.character($0)?.present ?? false }
            if still.isEmpty { state.currentEvent = nil; continue }
            state.currentEvent?.deciders = still
            log(.situation, ev.text, actor: ev.protagonist)
            state.phase = .situation
            return
        }
        state.currentEvent = nil
        if state.presentParticipantsCount == 0 {
            // everyone is away: skip directly to night
            state.phase = .night
        } else {
            state.phase = .tasks
        }
    }

    /// Turn an event definition into an active event, or nil if it can't happen now.
    func activate(_ def: EventDef, actor: String? = nil, target: String? = nil) -> ActiveEvent? {
        let present = state.presentParticipants
        guard !present.isEmpty else { return nil }
        var protagonist: String? = actor
        var deciders: [String] = present
        if def.kind == "solo" {
            var candidates = present
            if let sel = def.who {
                let picked = select(sel, EffCtx(actor: actor, target: target)).filter { present.contains($0) }
                candidates = picked
            }
            if let filter = def.whoWhen {
                candidates = candidates.filter { truthy(filter, EffCtx(actor: $0, target: target)) }
            }
            if let a = actor, candidates.contains(a) {
                protagonist = a
            } else {
                guard let p = state.rng.pick(candidates) else { return nil }
                protagonist = p
            }
            deciders = [protagonist!]
        }
        let ctx = EffCtx(actor: protagonist, target: target, protagonist: protagonist)
        var options: [ResolvedOption] = []
        var nominees: [String] = []
        if def.kind == "nominate" {
            nominees = present
        } else {
            for o in def.options ?? [] {
                let ok = o.when.map { truthy($0, ctx) } ?? true
                options.append(ResolvedOption(id: o.id, label: render(o.label, ctx), hint: o.hint.map { render($0, ctx) }, tags: o.tags ?? [], available: ok))
            }
            if !options.contains(where: { $0.available }) { return nil }
        }
        let text = render(def.text, ctx)
        return ActiveEvent(def: def, text: text, protagonist: protagonist, deciders: deciders, options: options, motion: nil, nominees: nominees)
    }

    func quietEvent() -> ActiveEvent? {
        let def = EventDef(
            id: "_quiet", kind: "individual",
            text: L("暂时没有新的变故。每个人都在想自己的事。", "Nothing new for now. Everyone is lost in their own thoughts."),
            options: [
                OptionDef(id: "encourage", label: L("给大家打气", "Lift everyone's spirits"), hint: L("稍微提升自己的士气，也让别人更信任你", "A little better morale for you, and a little more trust from the others"), tags: ["altruistic", "safe"], when: nil,
                          effects: [eff("stat", who: "actor", stat: "morale", add: 4), eff("trust", from: "others", to: "actor", add: 2)], result: L("{actor} 给大家打了打气。", "{actor} tries to keep everyone's spirits up.")),
                OptionDef(id: "sleep", label: L("抓紧时间睡一会", "Grab some sleep"), hint: L("恢复体力", "Recover your strength"), tags: ["safe", "selfish"], when: nil,
                          effects: [eff("stat", who: "actor", stat: "fatigue", add: -12)], result: L("{actor} 缩在角落里睡了一会。", "{actor} curls up in a corner and sleeps for a while.")),
                OptionDef(id: "inventory", label: L("清点一遍物资", "Count the supplies again"), hint: L("什么也不会多出来，但心里有数", "Nothing appears out of thin air, but at least you know where you stand"), tags: ["safe"], when: nil,
                          effects: [eff("stat", who: "actor", stat: "morale", add: 1)], result: L("{actor} 又数了一遍剩下的东西。", "{actor} counts what's left, one more time."))
            ],
            effects: nil, result: nil, when: nil, atRound: nil, once: false, weight: 0, minRound: nil, maxRound: nil, cooldown: nil, priority: nil, major: false, who: nil, whoWhen: nil, pre: nil, icon: nil
        )
        return activate(def)
    }

    // MARK: Situation phase

    /// Records first-round stances in a debated (major) event.
    public func recordStances(_ decisions: [String: SituationDecision]) {
        guard let ev = state.currentEvent else { return }
        for id in ev.deciders {
            guard let d = decisions[id] else { continue }
            let label = optionLabel(ev, normalizeChoice(ev, d.choice, decider: id))
            let speech = (d.speech ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            log(.speech, speech.isEmpty ? LogEntry.silent(lang) : speech, detail: L("倾向：\(label)", "leaning: \(label)"), actor: id)
            state.stanceSpeeches[id] = speech
            if let t = d.thought, !t.isEmpty {
                log(.thought, t, actor: id, vis: .god)
            }
        }
    }

    public func optionLabel(_ ev: ActiveEvent, _ choice: String) -> String {
        if ev.def.kind == "nominate" { return name(choice) }
        return ev.options.first { $0.id == choice }?.label ?? choice
    }

    /// Normalizes a raw choice to a valid option id / nominee.
    public func normalizeChoice(_ ev: ActiveEvent, _ raw: String, decider: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if ev.def.kind == "nominate" {
            if ev.nominees.contains(s) { return s }
            if let byName = ev.nominees.first(where: { name($0) == s || s.contains(name($0)) }) { return byName }
            return ev.nominees.first { $0 != decider } ?? ev.nominees.first ?? decider
        }
        let avail = ev.options.filter { $0.available }
        if avail.contains(where: { $0.id == s }) { return s }
        // letter (A/B/C) or label match
        let letters = ["A", "B", "C", "D", "E", "F"]
        if let li = letters.firstIndex(of: s.uppercased()), li < ev.options.count, ev.options[li].available {
            return ev.options[li].id
        }
        if let byLabel = avail.first(where: { s.contains($0.label) || $0.label.contains(s) && !s.isEmpty }) { return byLabel.id }
        return avail.first?.id ?? s
    }

    public func resolveSituation(_ raw: [String: SituationDecision]) {
        guard state.phase == .situation, let ev = state.currentEvent else { return }
        var decisions: [String: SituationDecision] = [:]
        for id in ev.deciders {
            var d = raw[id] ?? SituationDecision(choice: "", fallback: true)
            d.choice = normalizeChoice(ev, d.choice, decider: id)
            decisions[id] = d
        }
        // Final speeches & thoughts
        for id in ev.deciders {
            guard let d = decisions[id] else { continue }
            let speech = (d.speech ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !speech.isEmpty && state.stanceSpeeches[id] != speech {
                let fb = (d.fallback ?? false) ? L(" · 基础人机代答", " · a basic bot stood in") : ""
                log(.speech, speech, detail: L("选择：\(optionLabel(ev, d.choice))\(fb)", "choice: \(optionLabel(ev, d.choice))\(fb)"), actor: id)
            }
            if let t = d.thought, !t.isEmpty { log(.thought, t, actor: id, vis: .god) }
        }
        state.stanceSpeeches = [:]

        if let m = ev.motion {
            resolveMotion(ev, m, decisions)
        } else {
            switch ev.def.kind {
            case "individual":
                resolveIndividual(ev, decisions)
            case "nominate":
                resolveNominate(ev, decisions)
            case "solo":
                let p = ev.protagonist ?? ev.deciders.first!
                applyOption(ev, decisions[p]?.choice ?? "", actor: p, voters: [p], opponents: [])
            default: // group / leader
                resolveVote(ev, decisions)
            }
            state.firedEvents[ev.def.id] = state.round
        }
        checkWipe()
        if state.phase == .ended { return }
        advanceEvent()
    }

    func tally(_ ids: [String], _ decisions: [String: SituationDecision]) -> [(String, [String])] {
        var groups: [String: [String]] = [:]
        var order: [String] = []
        for id in ids {
            guard let c = decisions[id]?.choice else { continue }
            if groups[c] == nil { order.append(c) }
            groups[c, default: []].append(id)
        }
        return order.map { ($0, groups[$0]!) }.sorted { $0.1.count > $1.1.count }
    }

    func pickWinner(_ t: [(String, [String])]) -> String? {
        guard let top = t.first else { return nil }
        let tied = t.filter { $0.1.count == top.1.count }
        if tied.count == 1 { return top.0 }
        if let l = state.leader, let lc = tied.first(where: { $0.1.contains(l) }) { return lc.0 }
        return state.rng.pick(tied)?.0
    }

    func voteSummary(_ ev: ActiveEvent, _ t: [(String, [String])]) -> String {
        t.map { item in
            let names = item.1.map { name($0) }.joined(separator: Loc.sep(lang))
            return L("\(optionLabel(ev, item.0)) \(item.1.count)票（\(names)）", "\(optionLabel(ev, item.0)) \(item.1.count) (\(names))")
        }.joined(separator: Loc.semi(lang))
    }

    func resolveVote(_ ev: ActiveEvent, _ decisions: [String: SituationDecision]) {
        let t = tally(ev.deciders, decisions)
        var winner: String?
        var decidedBy = ""
        if ev.def.kind == "leader", let l = state.leader, ev.deciders.contains(l), let lc = decisions[l]?.choice {
            winner = lc
            decidedBy = L("领头人\(name(l))拍板", "Leader \(name(l)) decides")
        } else {
            winner = pickWinner(t)
            decidedBy = L("表决", "Vote")
        }
        guard let w = winner else { return }
        let voters = t.first { $0.0 == w }?.1 ?? []
        let opponents = ev.deciders.filter { !voters.contains($0) }
        log(.vote, "\(decidedBy)\(Loc.colon(lang))\(optionLabel(ev, w))", detail: voteSummary(ev, t))
        let actor = voters.isEmpty ? (state.leader ?? ev.deciders.first!) : (state.rng.pick(voters) ?? voters[0])
        applyOption(ev, w, actor: actor, voters: voters, opponents: opponents)
    }

    func resolveIndividual(_ ev: ActiveEvent, _ decisions: [String: SituationDecision]) {
        let t = tally(ev.deciders, decisions)
        if ev.deciders.count > 1 {
            log(.vote, L("各人的选择", "Each chose for themselves"), detail: voteSummary(ev, t))
        }
        for id in ev.deciders {
            guard let d = decisions[id] else { continue }
            let same = t.first { $0.0 == d.choice }?.1 ?? [id]
            applyOption(ev, d.choice, actor: id, voters: same, opponents: ev.deciders.filter { !same.contains($0) })
            if state.phase == .ended { return }
        }
    }

    func resolveNominate(_ ev: ActiveEvent, _ decisions: [String: SituationDecision]) {
        let t = tally(ev.deciders, decisions)
        guard let w = pickWinner(t) else { return }
        log(.vote, L("大家推选了 \(name(w))", "The group picks \(name(w))"), detail: voteSummary(ev, t))
        let voters = t.first { $0.0 == w }?.1 ?? []
        let ctx = EffCtx(actor: w, target: w, protagonist: w, voters: voters, opponents: ev.deciders.filter { !voters.contains($0) })
        var notes: [String] = []
        var entryId: Int?
        if let r = ev.def.result { entryId = log(.result, render(r, ctx), actor: w) }
        run(ev.def.effects, ctx, notes: &notes)
        if let entryId, let i = state.log.firstIndex(where: { $0.id == entryId }) {
            state.log[i].detail = notes.isEmpty ? nil : notes.joined(separator: Loc.comma(lang))
        } else if !notes.isEmpty {
            log(.result, notes.joined(separator: Loc.comma(lang)), actor: w)
        }
    }

    func applyOption(_ ev: ActiveEvent, _ optionId: String, actor: String, voters: [String], opponents: [String]) {
        guard let opt = ev.def.options?.first(where: { $0.id == optionId }) else { return }
        let ctx = EffCtx(actor: actor, target: ev.motion?.target, protagonist: ev.protagonist, voters: voters, opponents: opponents)
        var notes: [String] = []
        // Log the outcome line first so that anything the effects log (deaths, the ending) follows it.
        var entryId: Int?
        if let r = opt.result { entryId = log(.result, render(r, ctx), actor: actor) }
        run(opt.effects, ctx, notes: &notes)
        let detail = notes.isEmpty ? nil : notes.joined(separator: Loc.comma(lang))
        if let entryId, let i = state.log.firstIndex(where: { $0.id == entryId }) {
            state.log[i].detail = detail
        } else if let detail {
            log(.result, detail, actor: actor)
        }
    }

    // MARK: Tasks phase

    public struct TaskOption: Identifiable, Sendable {
        public var id: String
        public var name: String
        public var desc: String
        public var exertion: Exertion
        public var outdoor: Bool
        public var available: Bool
        public var reason: String?
        public var needsTarget: Bool
        public var targets: [String]
        public var hint: String?
    }

    public func taskOptions(for id: String) -> [TaskOption] {
        var out: [TaskOption] = []
        let mob = mobility(id)
        let present = state.characters.filter { $0.present }.map(\.id)
        let builtins = scenario.builtinTasks ?? ["rest", "care", "guard"]
        let ctx = EffCtx(actor: id)
        // someone who can barely stay conscious can only lie there
        let downed = buffMods(id).incapacitated
        let downedReason = hasBuff(id, "breakdown") ? L("崩溃了，什么也干不了", "has fallen apart, can't do anything") : L("神志不清，什么也干不了", "barely conscious, can't do anything")
        for t in scenario.tasks {
            let ex = Exertion(rawValue: t.exertion) ?? .light
            var ok = true
            var reason: String?
            if downed { ok = false; reason = downedReason }
            if ok, let w = t.when, !truthy(w, ctx) { ok = false; reason = L("条件不满足", "not possible right now") }
            if ok && ex == .heavy && !mob.canHeavy { ok = false; reason = L("身体状况做不了重活", "too weak for heavy work") }
            if ok && ((t.mobility ?? t.outdoor) && !mob.canMove) { ok = false; reason = L("行动不便", "can't get around") }
            let needs = (t.target ?? "none") != "none"
            var targets: [String] = []
            if needs {
                targets = present.filter { t.target == "any" || $0 != id }
                if targets.isEmpty { ok = false; reason = L("没有可选对象", "no one to choose") }
            }
            out.append(TaskOption(id: t.id, name: t.name, desc: render(t.desc, ctx), exertion: ex, outdoor: t.outdoor, available: ok, reason: reason, needsTarget: needs, targets: targets, hint: t.hint))
        }
        if builtins.contains("care") {
            let injured = present.filter { pid in
                guard let c = state.character(pid) else { return false }
                return c.injuries.contains { $0.severity > 5 } || c.health < 70
            }
            let hasMed = (state.resources["medkit"] ?? 0) >= 1
            let desc = hasMed
                ? L("照料一个伤病员：清创、包扎、固定（会用掉 1 份急救用品；有抗生素时也会用来治感染）。骨折、烧伤、冻伤、挤压伤和内伤处理好一次就够了，之后只能靠时间慢慢长。医疗技能越高效果越好。",
                    "Tend to someone hurt or sick: clean, dress, splint (uses 1 first-aid kit; antibiotics go to infections if you have any). A fracture, burn, frostbite, crush or internal injury only needs seeing to once — after that it just takes time. Medical skill makes it work better.")
                : L("照料一个伤病员。没有急救用品，只能清洗伤口、固定、喂水，效果有限；骨折、烧伤、冻伤处理过一次以后，只能靠时间。",
                    "Tend to someone hurt or sick. Without first-aid supplies you can only clean wounds, splint and give water — it helps a little; once a fracture, burn or frostbite has been seen to, only time heals it.")
            let careReason = downed ? downedReason : (injured.isEmpty ? L("没有需要照顾的人", "no one needs care") : nil)
            out.append(TaskOption(id: "care", name: L("照顾伤员", "Care for the injured"), desc: desc, exertion: .light, outdoor: false, available: !injured.isEmpty && !downed, reason: careReason, needsTarget: true, targets: injured, hint: nil))
        }
        if builtins.contains("guard") {
            out.append(TaskOption(id: "guard", name: L("守夜看物资", "Guard the supplies"), desc: L("夜里轮流守着公共物资，能发现偷吃的人，但自己睡不好。", "Take turns watching the common supplies at night. You may catch a thief, but you won't sleep well."), exertion: .light, outdoor: false, available: !downed, reason: downed ? downedReason : nil, needsTarget: false, targets: [], hint: nil))
        }
        let low = comfortTargets(for: id)
        if !low.isEmpty {
            out.append(TaskOption(id: "comfort", name: L("陪伴安抚", "Comfort someone"),
                                  desc: L("陪一个快撑不住的人待一天：听他把话说完，帮他把事情一件件理清。能稳住情绪，也能把崩溃的人拉回来。对方越信任你、你越会和人打交道，效果越好。",
                                          "Spend the day with someone close to breaking: let them talk, help them sort things out one at a time. It steadies them, and it can bring someone back from a breakdown. Works better the more they trust you and the better you are with people."),
                                  exertion: .light, outdoor: false, available: !downed, reason: downed ? downedReason : nil, needsTarget: true, targets: low, hint: nil))
        }
        if builtins.contains("rest") {
            out.append(TaskOption(id: "rest", name: L("休息", "Rest"), desc: L("躲在庇护所里保存体力，恢复疲劳和伤病。", "Stay in the shelter, save your strength, recover from fatigue and injuries."), exertion: .rest, outdoor: false, available: true, reason: nil, needsTarget: false, targets: [], hint: nil))
        }
        return out
    }

    public func resolveTasks(_ decisions: [String: TaskDecision]) {
        guard state.phase == .tasks else { return }
        let present = state.presentParticipants

        // Leader policy
        if let l = state.leader, present.contains(l), let p = decisions[l]?.policy {
            let old = state.policy
            state.policy = sanitizePolicy(p)
            if state.policy != old {
                log(.system, L("领头人\(name(l))调整了配给：\(policyText(state.policy))", "Leader \(name(l)) changes the rations — \(policyText(state.policy))"))
            }
        }

        // Speeches
        for id in present {
            guard let d = decisions[id] else { continue }
            if let s = d.speech?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                log(.speech, s, actor: id)
            }
            if let t = d.thought, !t.isEmpty { log(.thought, t, actor: id, vis: .god) }
        }

        // Validate & assign
        var counts: [String: Int] = [:]
        for id in present {
            let opts = taskOptions(for: id)
            var d = decisions[id] ?? TaskDecision(task: "rest")
            var opt = opts.first { $0.id == d.task && $0.available }
            if let o = opt, let maxW = scenario.task(o.id)?.max, counts[o.id, default: 0] >= maxW { opt = nil }
            if opt == nil {
                d.task = "rest"
                opt = opts.first { $0.id == "rest" }
                d.target = nil
            }
            if let o = opt, o.needsTarget {
                if d.target == nil || !o.targets.contains(d.target!) {
                    if let t = d.target, let byName = o.targets.first(where: { name($0) == t || t.contains(name($0)) }) {
                        d.target = byName
                    } else {
                        // pick the worst-off valid target
                        d.target = o.targets.min { (state.character($0)?.health ?? 100) < (state.character($1)?.health ?? 100) }
                    }
                }
            }
            counts[d.task, default: 0] += 1
            state.assignments[id] = TaskAssignment(task: d.task, target: d.target)
            mutate(id) { $0.lastTask = d.task }
        }
        // NPCs: rest, or do their own job when they're able to
        var npcWorkers: [(String, String)] = []
        for c in state.characters where c.present && c.isNPC {
            var task = "rest"
            if let auto = scenario.character(c.id)?.autoTask,
               taskOptions(for: c.id).contains(where: { $0.id == auto && $0.available && !$0.needsTarget }) {
                task = auto
                npcWorkers.append((c.id, auto))
            }
            state.assignments[c.id] = TaskAssignment(task: task, target: nil)
        }

        // Execute tasks in a stable order (scenario task order)
        let order = scenario.tasks.map(\.id) + ["care", "comfort", "guard", "rest"]
        for taskId in order {
            for id in present where state.assignments[id]?.task == taskId {
                executeTask(id, taskId, target: state.assignments[id]?.target)
                if state.phase == .ended { return }
            }
        }
        for (id, task) in npcWorkers {
            executeTask(id, task, target: nil)
            if state.phase == .ended { return }
        }
        // Outdoor accidents from weather
        let w = weatherDef
        if let risk = w.outdoorRisk, risk > 0 {
            for id in present {
                guard let a = state.assignments[id], taskShape(a.task).1 else { continue }
                // never alone outside: with someone on the same job, slips are rarer and get help at once (D-053)
                let buddy = present.first { $0 != id && state.assignments[$0]?.task == a.task }
                if state.rng.chance(risk * buffMods(id).accident * (buddy == nil ? 1 : 0.6)) {
                    let kinds = [("sprain", "脚踝", "ankle", 30.0), ("laceration", "手臂", "arm", 30.0), ("fracture", "手腕", "wrist", 35.0)]
                    let k = state.rng.pick(kinds)!
                    let part = L(k.1, k.2)
                    let sev = state.rng.range(k.3 * 0.6, k.3 * 1.3) * state.setup.level.injuryScale * (buddy == nil ? 1 : 0.75)
                    addInjury(id, kind: k.0, severity: sev, part: part, label: nil, partKey: k.1, labelKey: nil)
                    let kindName = InjuryKind.name(k.0, lang)
                    let help = buddy.map { L("幸好 \(name($0)) 就在旁边，马上把人扶了回来。", " Luckily \(name($0)) was right there and got them back at once.") } ?? ""
                    log(.result, L("\(w.name)里干活，\(name(id))出了意外：\(part)\(kindName)。", "Working out in the \(w.name.lowercased()), \(name(id)) has an accident: \(kindName) (\(part)).") + help, actor: id)
                }
            }
        }
        checkWipe()
        if state.phase == .ended { return }
        state.phase = .night
    }

    func sanitizePolicy(_ p: Policy) -> Policy {
        let rd = scenario.rationDef
        func nearest(_ v: Double, _ opts: [Double]) -> Double {
            opts.min { abs($0 - v) < abs($1 - v) } ?? v
        }
        var out = p
        out.food = nearest(p.food, rd.food)
        out.water = nearest(p.water, rd.water)
        if scenario.shelter.fire == nil { out.fire = false }
        if !Policy.priorities.contains(where: { $0.0 == p.priority }) { out.priority = "equal" }
        return out
    }

    public func policyText(_ p: Policy) -> String {
        var s = L("每人每天食物 \(Int(p.food)) 千卡、水 \(Fmt.number(p.water, 1)) 升，\(Policy.priorityLabel(p.priority, lang))",
                  "per person per day: \(Int(p.food)) kcal of food, \(Fmt.number(p.water, 1)) L of water, \(Policy.priorityLabel(p.priority, lang))")
        if let f = scenario.shelter.fire {
            let label = Loc.inline(f.label ?? L("火", "fire"), lang)
            s += p.fire ? L("，晚上点\(label)", ", \(label) lit at night") : L("，不点\(label)", ", no \(label) at night")
        }
        return s
    }

    func executeTask(_ id: String, _ taskId: String, target: String?) {
        var notes: [String] = []
        let taskName: String
        switch taskId {
        case "rest":
            let cap = maxHealth(id)
            mutate(id) { $0.fatigue = max(0, $0.fatigue - 10); $0.health = min(cap, $0.health + 2) }
            return
        case "guard":
            state.guards.append(id)
            practice(id, "survival")
            taskName = L("守夜看物资", "Guard the supplies")
            notes.append(L("今晚守着物资", "keeps watch over the supplies tonight"))
        case "care":
            taskName = L("照顾伤员", "Care for the injured")
            guard let t = target else { return }
            notes.append(contentsOf: performCare(by: id, on: t))
        case "comfort":
            taskName = L("陪伴安抚", "Comfort someone")
            guard let t = target, t != id else { return }
            notes.append(contentsOf: performComfort(by: id, on: t))
        default:
            guard let def = scenario.task(taskId) else { return }
            taskName = def.name
            run(def.effects, EffCtx(actor: id, target: target), notes: &notes)
        }
        log(.task, "\(name(id)) · \(taskName)", detail: notes.isEmpty ? L("没什么收获", "nothing to show for it") : notes.joined(separator: Loc.comma(lang)), actor: id, target: target)
    }

    func performCare(by carer: String, on target: String) -> [String] {
        guard let c = state.character(target), c.alive else { return [] }
        let skill = Double(scenario.character(carer)?.skill("medical") ?? 0)
        var notes: [String] = []
        let hasMed = (state.resources["medkit"] ?? 0) >= 1
        // Antibiotics for infections
        if c.injuries.contains(where: { $0.kind == "infection" }), (state.resources["antibiotics"] ?? 0) >= 1 {
            state.resources["antibiotics", default: 0] -= 1
            state.antibioticsGiven.insert(target)
            notes.append(L("给\(name(target))用了抗生素", "gave \(name(target)) antibiotics"))
        }
        // What hands can still help with: an infection (unless it already had antibiotics this round), a fracture /
        // burn / frostbite / crush / internal injury not yet seen to, and any other wound or illness.
        let open = c.injuries.filter { inj in
            if inj.kind == "infection" { return !state.antibioticsGiven.contains(target) }
            if InjuryKind.firstAidOnce.contains(inj.kind) { return !inj.treated }
            return true
        }
        // Treat the worst of them
        if let worst = open.max(by: { $0.severity < $1.severity }) {
            let once = InjuryKind.firstAidOnce.contains(worst.kind)
            let usesKit = hasMed && worst.severity > 15
            if usesKit {
                state.resources["medkit", default: 0] -= 1
                notes.append(L("用掉 1 份急救用品", "used 1 first-aid kit"))
            }
            var reduce: Double
            var treated: Bool
            if once {
                // splint it, dress it, rewarm it — once. Bone and burnt or frozen flesh then mend at their own pace.
                reduce = (usesKit ? 4 : 1) + skill
                treated = true
            } else if worst.kind == "infection" {
                // open, clean and dress the festering wound
                reduce = usesKit ? 10 : 3 + 3 * skill
                treated = usesKit || skill >= 2
            } else {
                reduce = usesKit ? 8 + 6 * skill : 3 + 3 * skill
                treated = usesKit || skill >= 2
            }
            reduce *= efficiency(carer) * buffMods(carer).care
            if once { reduce = min(5, reduce) }
            mutate(target) { p in
                if let j = p.injuries.firstIndex(where: { $0.id == worst.id }) {
                    p.injuries[j].severity = max(0, p.injuries[j].severity - reduce)
                    if treated { p.injuries[j].treated = true }
                }
                p.injuries.removeAll { $0.severity <= 0 }
            }
            let who = name(target), inj = worst.displayName(lang)
            switch worst.kind {
            case "fracture": notes.append(L("给\(who)的\(inj)上了夹板", "splinted \(who)'s \(inj)"))
            case "burn": notes.append(L("给\(who)的\(inj)冲了凉水、包扎好了", "cooled and dressed \(who)'s \(inj)"))
            case "frostbite": notes.append(L("把\(who)的\(inj)慢慢回暖、包扎好了", "rewarmed and dressed \(who)'s \(inj)"))
            case "crush", "trauma": notes.append(L("把\(who)的\(inj)处理、固定好了", "dressed and immobilised \(who)'s \(inj)"))
            default: notes.append(L("\(who)的\(inj)减轻了\(treated ? "，并做了处理" : "")", "\(who)'s \(inj) eased\(treated ? " and was treated" : "")"))
            }
        } else {
            let cap = maxHealth(target)
            mutate(target) { $0.health = min(cap, $0.health + 3 + 2 * skill) }
            notes.append(L("\(name(target))喝了水、躺着歇了歇", "\(name(target)) drank some water and rested"))
        }
        mutate(target) { p in
            p.morale = min(100, p.morale + 5)
            if carer != target { p.trust[carer] = min(100, (p.trust[carer] ?? 0) + 6) }
        }
        mutate(carer) { $0.stats.cared += 1 }
        addBuff(target, "cared", rounds: 2)
        practice(carer, "medical", 2)
        return notes
    }

    // MARK: Night phase

    public func resolveNight(_ decisions: [String: NightDecision]) {
        guard state.phase == .night else { return }
        let present = state.presentParticipants

        // Whispers, diaries, thoughts
        for id in present {
            guard let d = decisions[id] else { continue }
            if let t = d.thought, !t.isEmpty { log(.thought, t, actor: id, vis: .god) }
            for w in d.whispers.prefix(2) {
                guard let to = resolveName(w.to), to != id, state.character(to)?.alive ?? false else { continue }
                let text = w.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                log(.whisper, text, actor: id, target: to, vis: .only([id, to]))
                mutate(id) { $0.stats.whispers += 1 }
                // a quiet word from someone you trust helps a little
                if (state.character(to)?.trust[id] ?? 0) >= 20 { addBuff(to, "comforted", rounds: 1) }
            }
            if let diary = d.diary?.trimmingCharacters(in: .whitespacesAndNewlines), !diary.isEmpty {
                let label = roundLabel
                // Take the separator up front: reading `self.lang` inside the closure would be a
                // second access to `state` while `mutate` holds it exclusively (fatal at runtime).
                let colon = Loc.colon(lang)
                mutate(id) { p in
                    p.diary.append("\(label)\(colon)\(diary)")
                    if p.diary.count > 12 { p.diary.removeFirst(p.diary.count - 12) }
                }
                log(.diary, diary, actor: id, vis: .god)
            }
        }

        // Secret actions
        var thieves: [String] = []
        for id in present {
            guard let d = decisions[id] else { continue }
            switch d.secret {
            case "steal": thieves.append(id)
            case "stash": eatStash(id)
            case "reveal": revealSecret(id, voluntary: true)
            default: break
            }
        }
        for id in state.rng.shuffled(thieves) { attemptTheft(id) }

        // Gifts and who sleeps next to whom (D-053)
        arrangeNight(decisions, present: present)

        // Motions → pick one for tomorrow morning
        var motions: [Motion] = []
        for id in present {
            guard var m = decisions[id]?.motion else { continue }
            m.proposer = id
            if let t = m.target { m.target = resolveName(t) }
            if [.punish, .exile].contains(m.type) {
                guard let t = m.target, t != id, state.character(t)?.present ?? false else { continue }
            }
            if m.type == .thief { continue }
            motions.append(m)
            mutate(id) { $0.stats.motions += 1 }
            log(.secret, L("\(name(id)) 打算明早提出动议：\(motionLabel(m))", "\(name(id)) plans to propose in the morning: \(motionLabel(m))"), actor: id, vis: .god)
        }
        if state.pendingMotions.isEmpty, !motions.isEmpty {
            let rank: [MotionType: Int] = [.exile: 4, .punish: 3, .search: 2, .elect: 1]
            let best = motions.max { (rank[$0.type] ?? 0) < (rank[$1.type] ?? 0) }!
            state.pendingMotions.append(best)
        }

        endOfRound()
    }

    func resolveName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if state.character(s) != nil { return s }
        return state.characters.first { name($0.id) == s || (!s.isEmpty && s.contains(name($0.id))) }?.id
    }

    public func motionLabel(_ m: Motion) -> String {
        switch m.type {
        case .elect: return L("重新推选领头人", "choose a new leader")
        case .punish: return L("惩罚\(name(m.target))（口粮减半三天）", "punish \(name(m.target)) (half rations for three days)")
        case .exile: return L("把\(name(m.target))赶出队伍", "throw \(name(m.target)) out of the group")
        case .search: return L("搜查所有人的私人物品", "search everyone's belongings")
        case .thief: return L("处置偷吃的\(name(m.target))", "deal with \(name(m.target)), who stole food")
        }
    }

    func eatStash(_ id: String) {
        guard let c = state.character(id) else { return }
        let food = c.stash["food"] ?? 0
        let water = c.stash["water"] ?? 0
        guard food > 0 || water > 0 else { return }
        let f = min(food, 500)
        let w = min(water, 1)
        mutate(id) { p in
            p.stash["food"] = max(0, food - f)
            p.stash["water"] = max(0, water - w)
            p.lastIntake += f
            p.thirst -= w
            p.stats.stashEaten += f
        }
        let wz = w > 0 ? "，\(Fmt.number(w, 1)) 升水" : "", we = w > 0 ? ", \(Fmt.number(w, 1)) L of water" : ""
        log(.secret, L("\(name(id)) 偷偷吃了自己的私藏（\(Int(f)) 千卡\(wz)）。", "\(name(id)) secretly eats from a private stash (\(Int(f)) kcal\(we))."), actor: id, vis: .god)
        // someone might notice
        if state.rng.chance(0.08) {
            let others = state.presentParticipants.filter { $0 != id }
            if let witness = state.rng.pick(others) {
                log(.result, L("\(name(witness)) 半夜闻到 \(name(id)) 那边有吃东西的味道。", "In the middle of the night, \(name(witness)) smells food from where \(name(id)) is lying."), actor: witness, target: id)
                mutate(witness) { $0.trust[id] = max(-100, ($0.trust[id] ?? 0) - 15) }
            }
        }
    }

    func attemptTheft(_ id: String) {
        let food = state.resources["food"] ?? 0
        let water = state.resources["water"] ?? 0
        var tookFood = 0.0
        var tookWater = 0.0
        if food >= 100 {
            tookFood = min(600, food)
        } else if water >= 0.3 {
            tookWater = min(1, water)
        } else {
            log(.secret, L("\(name(id)) 想偷吃，但公共物资里已经没什么可拿的了。", "\(name(id)) means to steal food, but there's nothing left in the common supplies."), actor: id, vis: .god)
            return
        }
        state.resources["food"] = food - tookFood
        state.resources["water"] = water - tookWater
        state.stolenTonight += tookFood
        mutate(id) { p in
            p.lastIntake += tookFood
            p.thirst -= tookWater
            p.stats.thefts += 1
        }
        let what = tookFood > 0 ? L("\(Int(tookFood)) 千卡食物", "\(Int(tookFood)) kcal of food") : L("\(Fmt.number(tookWater, 1)) 升水", "\(Fmt.number(tookWater, 1)) L of water")
        log(.secret, L("\(name(id)) 趁夜偷吃了公共物资（\(what)）。", "\(name(id)) steals from the common supplies in the night (\(what))."), actor: id, vis: .god)

        // Detection
        var p = 0.12
        var catcher: String?
        for g in state.guards where g != id {
            let skill = Double(scenario.character(g)?.skill("survival") ?? 0)
            let pg = 0.3 + 0.1 * skill
            p += pg
            if catcher == nil && state.rng.chance(pg) { catcher = g }
        }
        if catcher == nil && state.rng.chance(0.12) {
            catcher = state.rng.pick(state.presentParticipants.filter { $0 != id && !state.guards.contains($0) })
        }
        if let c = catcher {
            mutate(id) { $0.stats.caught += 1 }
            log(.result, L("\(name(c)) 当场撞见 \(name(id)) 在偷吃公共物资（\(what)）。", "\(name(c)) catches \(name(id)) red-handed, stealing from the common supplies (\(what))."), actor: c, target: id)
            for other in state.characters where other.alive && other.id != id {
                mutate(other.id) { $0.trust[id] = max(-100, ($0.trust[id] ?? 0) - (other.id == c ? 45 : 30)) }
            }
            state.flags.insert("theft_caught")
            state.pendingMotions.insert(Motion(type: .thief, proposer: c, target: id), at: 0)
        } else {
            addBuff(id, "guilty", rounds: 2)
        }
    }

    public func revealSecret(_ id: String, voluntary: Bool) {
        guard let def = scenario.character(id), let secret = def.secret, let c = state.character(id), !c.secretRevealed else { return }
        mutate(id) { $0.secretRevealed = true }
        state.flags.insert("revealed_\(id)")
        if voluntary {
            log(.result, L("\(name(id)) 向大家坦白了一件事：\(secret)", "\(name(id)) comes clean about something: \(secret)"), actor: id)
        } else {
            log(.result, L("\(name(id)) 藏着的事被揭开了：\(secret)", "What \(name(id)) was hiding comes out: \(secret)"), actor: id)
        }
        var notes: [String] = []
        run(def.secretReveal, EffCtx(actor: id), notes: &notes)
    }

    // MARK: End of round

    func endOfRound() {
        // Rations & fire: food is eaten now; each person's water is handed out and drunk hour by hour
        var water = distributeRations()
        // hidden water someone was given tonight (in a fixed order)
        for to in tonightStashWater.keys.sorted() {
            if let i = state.index(of: to), i < water.count { water[i] += tonightStashWater[to] ?? 0 }
        }
        if let fire = scenario.shelter.fire {
            let need = fire.perRound * Double(hoursPerRound) / 24
            if state.policy.fire {
                if (state.resources[fire.resource] ?? 0) >= need - 1e-9 {
                    state.resources[fire.resource, default: 0] -= need
                    state.fireLit = true
                } else {
                    state.fireLit = false
                    let fuel = Loc.inline(scenario.resource(fire.resource)?.name ?? L("燃料", "fuel"), lang)
                    let label = Loc.inline(fire.label ?? L("火", "fire"), lang)
                    log(.system, L("\(fuel)不够了，今晚没法点\(label)。", "Not enough \(fuel) — no \(label) tonight."))
                }
            } else {
                state.fireLit = false
            }
        }

        // Hour-by-hour physiology (statuses as they stood when the night began)
        var damage: [String: [String: Double]] = [:]
        var coldHours: [String: Double] = [:]
        var mods: [String: BuffMods] = [:]
        for c in state.characters where c.alive { mods[c.id] = buffMods(c.id) }
        let handedOut = water
        simulateRoundHours(damage: &damage, coldHours: &coldHours, mods: mods, water: &water)
        // whatever nobody needed to drink goes back into the common supply (in a fixed order)
        var unused = 0.0
        for i in state.characters.indices where i < water.count {
            unused += water[i]
            state.characters[i].lastWater = handedOut[i] - water[i]
        }
        if unused > 1e-9 { state.resources["water", default: 0] += unused }
        settleEnergy()
        progressInjuries(damage: &damage, mods: mods)
        updateMorale(coldHours: coldHours, mods: mods)
        spreadIllness()
        checkBreakdowns()
        applyWear(damage: &damage)
        clearNightArrangements()

        // Deaths from accumulated damage
        for c in state.characters where c.alive && c.health <= 0 {
            let cause = damage[c.id]?.max { $0.value < $1.value }?.key ?? "伤重"
            killCharacter(c.id, cause: cause)
        }

        // Expedition returns
        for c in state.characters where c.status == .away {
            var rounds = c.awayRounds - 1
            if rounds <= 0 {
                mutate(c.id) { $0.status = .active; $0.awayRounds = 0 }
                let effects = c.awayReturn?.filter { $0.e != GameEngine.awayPlanTag }
                mutate(c.id) { $0.awayReturn = nil }
                var notes: [String] = []
                log(.result, L("\(name(c.id)) 回来了。", "\(name(c.id)) is back."), actor: c.id)
                run(effects, EffCtx(actor: c.id), notes: &notes)
                if !notes.isEmpty { log(.task, L("\(name(c.id)) · 外出归来", "\(name(c.id)) · back from outside"), detail: notes.joined(separator: Loc.comma(lang)), actor: c.id) }
                rounds = 0
            }
            if state.character(c.id)?.status == .away {
                mutate(c.id) { $0.awayRounds = rounds }
            }
        }

        // Shelter wear
        let sh = scenario.shelter
        var wear = sh.decay ?? 0
        if (weatherDef.precip ?? 0) >= 2 { wear += sh.stormDecay ?? 0 }
        state.shelterIntegrity = max(0, state.shelterIntegrity - wear)

        // Scenario rules (hazards, rescue…)
        run(scenario.rules, EffCtx())
        tickBuffs()
        rollHardship()

        // Bookkeeping
        if let l = state.leader { mutate(l) { $0.stats.roundsLed += 1 }; practice(l, "social") }
        for i in state.characters.indices where state.characters[i].punishedRounds > 0 {
            state.characters[i].punishedRounds -= 1
        }

        // Unnoticed theft may still be noticed in the morning
        if state.stolenTonight > 300 && !state.pendingMotions.contains(where: { $0.type == .thief }) && state.rng.chance(0.5) {
            state.flags.insert("theft_suspected")
            log(.system, L("早上清点物资时，大家发现食物比昨晚少了一截。有人偷吃了。", "Counting the supplies in the morning, everyone sees there's less food than last night. Someone has been stealing."))
            for i in state.characters.indices where state.characters[i].alive {
                state.characters[i].morale = max(0, state.characters[i].morale - 4)
            }
        }

        if state.phase == .ended { return }
        checkWipe()
        if state.phase == .ended { return }
        if state.round >= scenario.clock.maxRounds {
            finish(endingId: scenario.defaultEnding)
            return
        }
        state.round += 1
        beginRound()
    }

    /// Shares out the round's food (eaten now) and water. The water is taken out of the stock and handed to each
    /// person (returned by index in `state.characters`) to be drunk hour by hour; see `simulateRoundHours`.
    func distributeRations() -> [Double] {
        var water = Array(repeating: 0.0, count: state.characters.count)
        let factor = Double(hoursPerRound) / 24
        let eaters = state.characters.filter { $0.alive }
        guard !eaters.isEmpty else { return water }
        func demand(_ c: CharacterState, base: Double) -> Double {
            var d = base * factor
            if c.punishedRounds > 0 { d *= 0.5 }
            if c.isNPC && (scenario.character(c.id)?.tags ?? []).contains("child") { d *= 0.6 }
            if let def = scenario.character(c.id), def.isAnimal { d *= max(0.15, pow(def.weight / 65, 0.75)) }
            return d
        }
        for (resId, base) in [("food", state.policy.food), ("water", state.policy.water)] {
            let stock = state.resources[resId] ?? 0
            var demands: [String: Double] = [:]
            for c in eaters { demands[c.id] = demand(c, base: base) }
            // summed in a fixed order: dictionary order varies between instances, and so would the rounding
            let total = eaters.map { demands[$0.id] ?? 0 }.reduce(0, +)
            var given: [String: Double] = [:]
            if total <= stock {
                given = demands
            } else {
                var remaining = stock
                var firstClass: [String] = []
                switch state.policy.priority {
                case "injured":
                    firstClass = eaters.filter { c in c.injuries.contains { $0.severity > 25 } || c.health < 50 }.map(\.id)
                case "workers":
                    firstClass = eaters.filter { c in
                        guard let a = state.assignments[c.id] else { return false }
                        return taskShape(a.task).0 == .heavy
                    }.map(\.id)
                case "leader":
                    if let l = state.leader { firstClass = [l] }
                default: break
                }
                for id in firstClass {
                    let g = min(remaining, demands[id] ?? 0)
                    given[id] = g
                    remaining -= g
                }
                let rest = eaters.map(\.id).filter { !firstClass.contains($0) }
                let restTotal = rest.map { demands[$0] ?? 0 }.reduce(0, +)
                for id in rest {
                    given[id] = restTotal > 0 ? remaining * (demands[id] ?? 0) / restTotal : 0
                }
            }
            // part of someone's share handed to another tonight (D-053)
            applyRationGifts(&given)
            var used = 0.0
            // in the eaters' order, not the dictionary's (which differs between instances)
            for c in eaters {
                guard let g = given[c.id] else { continue }
                used += g
                if resId == "food" {
                    mutate(c.id) { $0.lastIntake += g }
                } else if let i = state.index(of: c.id) {
                    water[i] = g
                }
            }
            state.resources[resId] = max(0, stock - used)
        }
        return water
    }

    public func killCharacter(_ id: String, cause rawCause: String) {
        guard let c = state.character(id), c.alive else { return }
        // engine causes are written in Chinese; scenario causes are already in the game's language
        let cause = lang == .en ? (Physio.causeEN[rawCause] ?? rawCause) : rawCause
        let round = state.round
        mutate(id) { p in
            p.status = .dead
            p.deathRound = round
            p.deathCause = cause
            p.deathKind = GameEngine.deathKind(rawCause)
            p.health = 0
        }
        log(.death, L("\(name(id)) 没能撑过去。", "\(name(id)) didn't make it."), detail: L("死因：\(cause)", "Cause of death: \(cause)"), actor: id)
        if state.leader == id {
            state.leader = nil
            log(.system, L("领头人死了，队伍暂时没有拿主意的人。", "The leader is dead. For now, no one is in charge."))
        }
        let isChild = (scenario.character(id)?.tags ?? []).contains("child")
        let animal = isAnimal(id)
        for o in state.characters where o.alive {
            let t = o.trust[id] ?? 0
            let loss = (animal ? 3 : 8 + max(0, t) / 10 + (isChild ? 8 : 0)) * (hasPerk(o.id, "calm") ? 0.75 : 1)
            mutate(o.id) { $0.morale = max(0, $0.morale - loss) }
            if !animal && o.present && !isAnimal(o.id) { addBuff(o.id, "shaken", rounds: 2) }
        }
    }

    func checkWipe() {
        guard state.phase != .ended else { return }
        if state.aliveParticipants.isEmpty {
            let anyoneOut = state.characters.contains { !$0.isNPC && $0.status == .rescued }
            finish(endingId: anyoneOut ? "auto" : scenario.wipeEnding)
        }
    }

    // MARK: Endings

    public func finish(endingId: String) {
        guard state.phase != .ended else { return }
        state.evaluatingEnding = true
        defer { state.evaluatingEnding = false }
        var def = scenario.endings.first { $0.id == endingId }
        if endingId == "auto" || def == nil {
            def = scenario.endings.first { e in e.when.map { truthy($0, EffCtx()) } ?? false } ?? scenario.endings.first { $0.id == scenario.defaultEnding }
        }
        if endingId == scenario.wipeEnding, let v = wipeVariant(base: def) { def = v }
        let ending = def ?? EndingDef(id: "end", title: L("终局", "The End"), when: nil, text: L("故事结束了。", "The story is over."), tone: "bitter")
        let total = Double(max(1, state.participants.count + (scenario.npcs ?? []).filter { !$0.isAnimal }.count))
        let survivors = Double(state.characters.filter { $0.survived && $0.status != .notJoined && !isAnimal($0.id) }.count)
        var results: [CharacterResult] = []
        var others: [CharacterResult] = []
        for c in state.characters where c.status != .notJoined {
            let def = scenario.character(c.id)
            let alive = c.survived
            var goalOK = false
            if let g = def?.goal {
                goalOK = truthy(g.check, EffCtx(actor: c.id, target: nil, protagonist: c.id))
            }
            let fate: String
            switch c.status {
            case .dead:
                let r = c.deathRound ?? state.round, why = Loc.lowerFirst(c.deathCause ?? L("原因不明", "unknown cause"), lang)
                fate = L("第\(r)回合遇难（\(why)）", "died in round \(r) (\(why))")
            case .exiled: fate = L("被赶出队伍，下落不明", "thrown out of the group, fate unknown")
            case .away: fate = L("还在外面，生死未卜", "still out there, fate unknown")
            case .rescued: fate = L("第\(c.rescuedRound ?? state.round)回合被救走", "rescued in round \(c.rescuedRound ?? state.round)")
            case .gone: fate = L("离开了队伍", "left the group")
            default: fate = L("活了下来", "survived")
            }
            // First matching epilogue for this character
            var epilogue: String?
            for e in def?.epilogues ?? [] where truthy(e.when, EffCtx(actor: c.id, target: nil, protagonist: c.id)) {
                epilogue = render(e.text, EffCtx(actor: c.id, target: nil, protagonist: c.id))
                break
            }
            let score = (alive && c.status != .away ? 50 : 0) + (goalOK ? 30 : 0) + Int((20 * survivors / total).rounded())
            let r = CharacterResult(id: c.id, name: name(c.id), controller: c.isNPC ? "NPC" : playedBy(c.id),
                                    survived: alive && c.status != .away, fate: fate, goal: def?.goal?.text, goalAchieved: goalOK,
                                    score: c.isNPC ? 0 : score, epilogue: epilogue, isNPC: c.isNPC)
            if c.isNPC { others.append(r) } else { results.append(r) }
        }
        let text = render(ending.text, EffCtx())
        state.ending = EndingResult(id: ending.id, title: ending.title, text: text, tone: ending.tone ?? "bitter", round: state.round, results: results, others: others)
        log(.ending, ending.title, detail: text)
        state.phase = .ended
        state.currentEvent = nil
        state.eventQueue = []
    }
}

extension GameState {
    var presentParticipantsCount: Int { presentParticipants.count }
}
