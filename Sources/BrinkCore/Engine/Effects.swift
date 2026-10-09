import Foundation

/// Binding context for effects, conditions and text templates.
public struct EffCtx {
    public var actor: String?
    public var target: String?
    public var protagonist: String?
    public var voters: [String] = []
    public var opponents: [String] = []

    public init(actor: String? = nil, target: String? = nil, protagonist: String? = nil, voters: [String] = [], opponents: [String] = []) {
        self.actor = actor
        self.target = target
        self.protagonist = protagonist
        self.voters = voters
        self.opponents = opponents
    }
}

/// Convenience builder for effects defined in code.
func eff(_ e: String, id: String? = nil, who: String? = nil, from: String? = nil, to: String? = nil, stat: String? = nil, add: Double? = nil, text: String? = nil) -> Effect {
    var x = Effect(e: e)
    x.id = id
    x.who = who
    x.from = from
    x.to = to
    x.stat = stat
    if let add { x.add = .const(add) }
    x.text = text
    return x
}

extension GameEngine {

    // MARK: - Expressions

    public func num(_ n: Num?, _ ctx: EffCtx, default d: Double = 0) -> Double {
        guard let n else { return d }
        switch n {
        case .const(let v): return v
        case .expr(let s): return eval(s, ctx)
        }
    }

    public func eval(_ source: String, _ ctx: EffCtx) -> Double {
        guard let node = try? Expr.parse(source) else { return 0 }
        return Expr.evaluate(node, resolve: { self.resolveIdent($0, ctx) }, random: { self.state.rng.unit() })
    }

    public func truthy(_ source: String, _ ctx: EffCtx) -> Bool {
        eval(source, ctx) != 0
    }

    /// Resolves an identifier like `res.food`, `actor.health`, `weather.blizzard`.
    func resolveIdent(_ name: String, _ ctx: EffCtx) -> Double? {
        let parts = name.split(separator: ".").map(String.init)
        guard let head = parts.first else { return nil }
        // Group counters count people only (animals have their own fields: dog.alive …)
        let alive = state.characters.filter { $0.alive && !isAnimal($0.id) }
        let present = state.characters.filter { $0.present && !isAnimal($0.id) }
        switch parts.count {
        case 1:
            switch head {
            case "round": return Double(state.round)
            case "day": return Double(currentDay)
            case "hardness": return Double(Difficulty.allCases.firstIndex(of: state.setup.level) ?? 0)
            case "hour": return Double(currentClockHour)
            case "hours": return Double(roundStartHour)
            case "alive":
                // While endings are evaluated, people who were rescued earlier count as alive.
                if state.evaluatingEnding { return Double(state.characters.filter { $0.survived && $0.status != .notJoined && !isAnimal($0.id) }.count) }
                return Double(alive.count)
            case "present": return Double(present.count)
            case "participants":
                if state.evaluatingEnding { return Double(state.characters.filter { !$0.isNPC && $0.survived }.count) }
                return Double(state.aliveParticipants.count)
            case "dead": return Double(state.characters.filter { $0.status == .dead && !isAnimal($0.id) }.count)
            case "exiled": return Double(state.characters.filter { $0.status == .exiled }.count)
            case "rescued": return Double(state.characters.filter { $0.status == .rescued }.count)
            case "away": return Double(state.characters.filter { $0.status == .away }.count)
            case "guards": return Double(state.guards.count)
            case "hasLeader": return state.leader != nil ? 1 : 0
            case "temp": return currentTemp
            case "high": return state.dayHigh
            case "low": return state.dayLow
            case "wind": return weatherDef.wind ?? 0
            case "visibility": return weatherDef.visibility ?? 1
            case "precip": return weatherDef.precip ?? 0
            case "sun": return weatherDef.sun ?? 1
            case "shelter": return state.shelterIntegrity
            case "fire": return state.policy.fire ? 1 : 0
            case "fireLit": return state.fireLit ? 1 : 0
            case "avgMorale":
                return present.isEmpty ? 0 : present.map(\.morale).reduce(0, +) / Double(present.count)
            case "avgHealth":
                return present.isEmpty ? 0 : present.map(\.health).reduce(0, +) / Double(present.count)
            case "minHealth": return present.map(\.health).min() ?? 0
            case "injuredCount": return Double(present.filter { c in c.injuries.contains { $0.severity > 20 } }.count)
            case "foodDays": return alive.isEmpty ? 0 : (state.resources["food"] ?? 0) / (Double(alive.count) * 2000)
            case "waterDays": return alive.isEmpty ? 0 : (state.resources["water"] ?? 0) / (Double(alive.count) * 2.5)
            case "stolen": return state.stolenTonight
            case "rationFood": return state.policy.food
            case "rationWater": return state.policy.water
            case "altitude": return altitude
            case "true": return 1
            case "false": return 0
            default: return nil
            }
        default:
            let rest = Array(parts.dropFirst())
            switch head {
            case "res": return state.resources[rest.joined(separator: ".")] ?? 0
            case "var": return state.vars[rest.joined(separator: ".")] ?? 0
            case "flag": return state.flags.contains(rest.joined(separator: ".")) ? 1 : 0
            case "weather": return state.weather == rest[0] ? 1 : 0
            case "project":
                let id = rest[0]
                guard let p = scenario.project(id) else { return 0 }
                if state.projectsDone.contains(id) { return 1 }
                return min(1, (state.projects[id] ?? 0) / max(1, p.work))
            case "done": return state.projectsDone.contains(rest[0]) ? 1 : 0
            case "fired": return state.firedEvents[rest[0]] != nil ? 1 : 0
            case "actor": return ctx.actor.flatMap { charField($0, Array(rest)) } ?? 0
            case "target": return ctx.target.flatMap { charField($0, Array(rest)) } ?? 0
            case "self": return ctx.actor.flatMap { charField($0, Array(rest)) } ?? 0
            case "protagonist": return ctx.protagonist.flatMap { charField($0, Array(rest)) } ?? 0
            case "leader":
                if rest.count == 1, scenario.character(rest[0]) != nil { return state.leader == rest[0] ? 1 : 0 }
                return state.leader.flatMap { charField($0, Array(rest)) } ?? 0
            case "trust":
                guard rest.count >= 2 else { return 0 }
                let a = rest[0] == "actor" ? (ctx.actor ?? "") : rest[0]
                let b = rest[1] == "actor" ? (ctx.actor ?? "") : (rest[1] == "leader" ? (state.leader ?? "") : rest[1])
                return state.character(a)?.trust[b] ?? 0
            case "voters": return Double(ctx.voters.count)
            default:
                // <field>.<charId>  e.g. alive.zhou, health.lin, skill.zhou.survival
                if rest.count >= 1, scenario.character(rest[0]) != nil {
                    return charField(rest[0], [head] + Array(rest.dropFirst()))
                }
                // <charId>.<field>  e.g. zhou.health
                if scenario.character(head) != nil {
                    return charField(head, rest)
                }
                return nil
            }
        }
    }

    /// Character field access. `path` like ["health"], ["skill","survival"], ["item","knife"].
    func charField(_ id: String, _ path: [String]) -> Double? {
        guard let c = state.character(id) else { return 0 }
        let def = scenario.character(id)
        guard let f = path.first else { return c.alive ? 1 : 0 }
        let weight = def?.weight ?? 65
        switch f {
        case "alive": return (c.alive || (state.evaluatingEnding && c.status == .rescued)) ? 1 : 0
        case "rescued": return c.status == .rescued ? 1 : 0
        case "present": return c.present ? 1 : 0
        case "away": return c.status == .away ? 1 : 0
        case "dead": return c.status == .dead ? 1 : 0
        case "exiled": return c.status == .exiled ? 1 : 0
        case "joined": return c.status != .notJoined ? 1 : 0
        case "health": return c.health
        case "maxHealth": return maxHealth(id)
        case "morale": return c.morale
        case "fatigue": return c.fatigue
        case "core": return c.core
        case "thirst": return max(0, c.thirst) / weight * 100
        case "thirstL": return c.thirst
        case "weight": return weight
        case "hunger": return max(0, 1 - c.energyEMA)
        case "fat": return max(0, c.fatKg - weight * Physio.essentialFatFraction(female: def?.isFemale ?? false))
        case "clo": return c.clo
        case "wet": return c.wetHours > 0 ? 1 : 0
        case "injured": return c.injuries.map(\.severity).max() ?? 0
        case "infected": return c.injuries.first { $0.kind == "infection" }?.severity ?? 0
        case "injury":
            guard path.count > 1 else { return c.injuries.map(\.severity).max() ?? 0 }
            return c.injuries.filter { $0.kind == path[1] }.map(\.severity).max() ?? 0
        case "skill": return Double(def?.skill(path.count > 1 ? path[1] : "") ?? 0)
        case "item": return c.items[path.count > 1 ? path[1] : ""] ?? 0
        case "stash": return c.stash[path.count > 1 ? path[1] : ""] ?? 0
        case "revealed": return c.secretRevealed ? 1 : 0
        case "leader": return state.leader == id ? 1 : 0
        case "npc": return c.isNPC ? 1 : 0
        case "animal": return (def?.isAnimal ?? false) ? 1 : 0
        case "age": return Double(def?.age ?? 0)
        case "female": return (def?.isFemale ?? false) ? 1 : 0
        case "gone": return c.status == .gone ? 1 : 0
        case "goal":
            guard let g = def?.goal, !g.check.contains("goal") else { return 0 }
            return truthy(g.check, EffCtx(actor: id, target: nil, protagonist: id)) ? 1 : 0
        case "tag": return (def?.tags ?? []).contains(path.count > 1 ? path[1] : "") ? 1 : 0
        case "trust":
            guard path.count > 1 else { return 0 }
            let other = path[1] == "leader" ? (state.leader ?? "") : path[1]
            return c.trust[other] ?? 0
        case "trusted":
            // average trust others have in this person
            let others = state.characters.filter { $0.alive && $0.id != id && !$0.isNPC }
            guard !others.isEmpty else { return 0 }
            return others.map { $0.trust[id] ?? 0 }.reduce(0, +) / Double(others.count)
        case "led": return Double(c.stats.roundsLed)
        case "thefts": return Double(c.stats.thefts)
        case "caught": return Double(c.stats.caught)
        case "efficiency": return efficiency(id)
        case "buff":
            guard path.count > 1 else { return Double(buffs(id).count) }
            return hasBuff(id, path[1]) ? 1 : 0
        case "mobile": return mobility(id).canMove ? 1 : 0
        case "canHeavy": return mobility(id).canHeavy ? 1 : 0
        case "task":
            guard path.count > 1 else { return 0 }
            return state.assignments[id]?.task == path[1] ? 1 : 0
        case "deathRound": return Double(c.deathRound ?? 0)
        case "is": return path.count > 1 && path[1] == id ? 1 : 0
        default: return nil
        }
    }

    // MARK: - Selectors

    /// Resolves a selector to living character ids.
    public func select(_ sel: String?, _ ctx: EffCtx) -> [String] {
        let s = sel ?? "actor"
        let present = state.characters.filter { $0.present }.map(\.id)
        switch s {
        case "actor", "self": return ctx.actor.map { [$0] } ?? []
        case "target": return ctx.target.map { [$0] } ?? []
        case "protagonist": return ctx.protagonist.map { [$0] } ?? []
        case "all": return present
        case "everyone": return state.characters.filter { $0.alive }.map(\.id)
        case "players": return state.characters.filter { $0.present && !$0.isNPC }.map(\.id)
        case "npcs": return state.characters.filter { $0.present && $0.isNPC }.map(\.id)
        case "others": return present.filter { $0 != ctx.actor }
        case "random": return state.rng.pick(present).map { [$0] } ?? []
        case "randomPlayer": return state.rng.pick(state.presentParticipants).map { [$0] } ?? []
        case "randomOther": return state.rng.pick(present.filter { $0 != ctx.actor }).map { [$0] } ?? []
        case "leader": return state.leader.flatMap { l in present.contains(l) ? [l] : nil } ?? []
        case "weakest": return present.min { (state.character($0)?.health ?? 0) < (state.character($1)?.health ?? 0) }.map { [$0] } ?? []
        case "strongest":
            return present.filter { !(state.character($0)?.isNPC ?? true) }.max { a, b in
                let sa = Double(scenario.character(a)?.skill("strength") ?? 0) + (state.character(a)?.health ?? 0) / 50
                let sb = Double(scenario.character(b)?.skill("strength") ?? 0) + (state.character(b)?.health ?? 0) / 50
                return sa < sb
            }.map { [$0] } ?? []
        case "injured": return present.filter { id in state.character(id)?.injuries.contains { $0.severity > 20 } ?? false }
        case "voters": return ctx.voters.filter { present.contains($0) }
        case "opponents": return ctx.opponents.filter { present.contains($0) }
        case "away": return state.characters.filter { $0.status == .away }.map(\.id)
        case "none": return []
        default:
            if s.hasPrefix("best:") {
                let skill = String(s.dropFirst(5))
                return state.presentParticipants.max { (scenario.character($0)?.skill(skill) ?? 0) < (scenario.character($1)?.skill(skill) ?? 0) }.map { [$0] } ?? []
            }
            if state.character(s) != nil {
                // specific character id (only if alive; joining handled by `join`)
                return (state.character(s)?.alive ?? false) ? [s] : []
            }
            return []
        }
    }

    // MARK: - Effects

    func run(_ effects: [Effect]?, _ ctx: EffCtx) {
        var notes: [String] = []
        run(effects, ctx, notes: &notes)
    }

    func run(_ effects: [Effect]?, _ ctx: EffCtx, notes: inout [String]) {
        guard let effects else { return }
        for e in effects {
            if state.phase == .ended { return }
            apply(e, ctx, notes: &notes)
        }
    }

    func apply(_ e: Effect, _ ctx: EffCtx, notes: inout [String]) {
        switch e.e {
        case "res":
            guard let id = e.id else { return }
            let old = state.resources[id] ?? 0
            var v = old
            if let s = e.set { v = num(s, ctx) }
            if let a = e.add { v += num(a, ctx) }
            v = max(0, v)
            // on harder settings whatever turns up is less (D-053)
            let gainScale = state.setup.level.gainScale
            if v > old && gainScale < 1 {
                v = old + (v - old) * gainScale
                if (scenario.resource(id)?.decimals ?? 0) == 0 { v = max(old + 1, v.rounded()) }
            }
            state.resources[id] = v
            let delta = v - old
            if abs(delta) > 1e-6 && !(e.hidden ?? false) {
                notes.append("\(scenario.resource(id)?.name ?? id) \(Fmt.signed(delta, id, scenario))")
            }

        case "var":
            guard let id = e.id else { return }
            let def = scenario.variable(id)
            let old = state.vars[id] ?? 0
            var v = old
            if let s = e.set { v = num(s, ctx) }
            if let a = e.add { v += num(a, ctx) }
            if let lo = def?.min { v = max(lo, v) }
            if let hi = def?.max { v = min(hi, v) }
            state.vars[id] = v
            if let def, def.show ?? false, abs(v - old) >= 0.5, !(e.hidden ?? false) {
                let d = v - old
                notes.append("\(def.name) \(d > 0 ? "+" : "")\(Fmt.number(d, 0))")
            }

        case "buff":
            guard let bid = e.id, let def = Buffs.def(bid) else { return }
            let rounds = e.rounds.map { Int(num($0, ctx).rounded()) } ?? 2
            let targets = select(e.who, ctx)
            for id in targets { addBuff(id, bid, rounds: rounds) }
            if rounds > 0 && !(e.hidden ?? false) && !targets.isEmpty {
                let who = targets.count > 1 ? L("众人", "everyone") : name(targets[0])
                notes.append(L("\(who)：\(def.name(lang))", "\(who): \(def.name(lang).lowercased())"))
            }

        case "flag":
            guard let id = e.id else { return }
            if e.on ?? true { state.flags.insert(id) } else { state.flags.remove(id) }

        case "stat":
            let targets = select(e.who, ctx)
            let stat = e.stat ?? "health"
            for id in targets {
                let amount = num(e.add, ctx)
                let setV = e.set.map { num($0, ctx) }
                let cap = maxHealth(id)
                mutate(id) { p in
                    func upd(_ x: inout Double, lo: Double, hi: Double) {
                        if let s = setV { x = s }
                        x += amount
                        x = min(hi, max(lo, x))
                    }
                    switch stat {
                    case "health": upd(&p.health, lo: -50, hi: cap)
                    case "morale": upd(&p.morale, lo: 0, hi: 100)
                    case "fatigue": upd(&p.fatigue, lo: 0, hi: 100)
                    case "core": upd(&p.core, lo: 20, hi: 45)
                    case "thirst": upd(&p.thirst, lo: -1.5, hi: 30)
                    case "energy": p.lastIntake += amount
                    case "fat": upd(&p.fatKg, lo: 0, hi: 80)
                    case "clo": upd(&p.clo, lo: 0, hi: 6)
                    case "wet": upd(&p.wetHours, lo: 0, hi: 72)
                    default: break
                    }
                }
                if !(e.hidden ?? false), targets.count == 1, ["health", "morale"].contains(stat), abs(amount) >= 1 {
                    let what = stat == "health" ? L("健康", "health") : L("士气", "morale")
                    notes.append("\(name(id)) \(what) \(amount > 0 ? "+" : "")\(Int(amount))")
                }
            }
            // big news for the whole group: something to hope for, or a shock
            if targets.count > 1 && stat == "morale" {
                let amount = num(e.add, ctx)
                if amount >= 8 { for id in targets where !isAnimal(id) { addBuff(id, "hope", rounds: 2) } }
                if amount <= -8 { for id in targets where !isAnimal(id) { addBuff(id, "shaken", rounds: 2) } }
            }
            if !(e.hidden ?? false), targets.count > 1, ["health", "morale"].contains(stat) {
                let amount = num(e.add, ctx)
                if abs(amount) >= 1 {
                    let what = stat == "health" ? L("健康", "health") : L("士气", "morale")
                    notes.append(L("众人\(what) \(amount > 0 ? "+" : "")\(Int(amount))", "everyone's \(what) \(amount > 0 ? "+" : "")\(Int(amount))"))
                }
            }
            for id in targets where (state.character(id)?.health ?? 1) <= 0 {
                killCharacter(id, cause: e.cause ?? "伤重")
            }

        case "injure":
            let kind = e.kind ?? "laceration"
            for id in select(e.who, ctx) {
                let sev = num(e.severity, ctx, default: 30) * state.setup.level.injuryScale
                addInjury(id, kind: kind, severity: sev, part: e.part, label: e.label, partKey: e.partKey ?? e.part, labelKey: e.labelKey ?? e.label)
                let kindName = InjuryKind.name(kind, lang)
                let n = e.label ?? (lang == .en ? (e.part.map { "\(kindName) (\(Loc.lowerFirst($0, lang)))" } ?? kindName) : (e.part ?? "") + kindName)
                let sevLabel = InjuryKind.severityLabel(sev, lang)
                notes.append(L("\(name(id)) 受伤：\(n)（\(sevLabel)）", "\(name(id)) is hurt: \(n) (\(sevLabel))"))
            }

        case "heal":
            let amount = num(e.amount, ctx, default: 20)
            for id in select(e.who, ctx) {
                var healedSomething = false
                mutate(id) { p in
                    let kind = e.kind ?? "any"
                    var idxs: [Int]
                    if kind == "any" {
                        idxs = p.injuries.indices.sorted { p.injuries[$0].severity > p.injuries[$1].severity }
                        idxs = Array(idxs.prefix(1))
                    } else if kind == "all" {
                        idxs = Array(p.injuries.indices)
                    } else {
                        idxs = p.injuries.indices.filter { p.injuries[$0].kind == kind }
                    }
                    for j in idxs {
                        p.injuries[j].severity -= amount
                        if e.treated ?? false { p.injuries[j].treated = true }
                        healedSomething = true
                    }
                    p.injuries.removeAll { $0.severity <= 0 }
                }
                if healedSomething && !(e.hidden ?? false) { notes.append(L("\(name(id)) 的伤情好转", "\(name(id))'s injuries improve")) }
            }

        case "trust":
            let froms = select(e.from ?? "others", ctx)
            let tos = select(e.to ?? "actor", ctx)
            let v = num(e.add, ctx)
            for f in froms {
                mutate(f) { p in
                    for t in tos where t != f {
                        p.trust[t] = min(100, max(-100, (p.trust[t] ?? 0) + v))
                    }
                }
            }

        case "kill":
            for id in select(e.who, ctx) {
                killCharacter(id, cause: e.cause ?? "意外")
            }

        case "log":
            guard let t = e.text else { return }
            let text = render(t, ctx)
            let vis: Visibility
            switch e.vis ?? "public" {
            case "god": vis = .god
            case "actor": vis = .only(ctx.actor.map { [$0] } ?? [])
            case "target": vis = .only(ctx.target.map { [$0] } ?? [])
            default: vis = .everyone
            }
            log(.result, text, actor: ctx.actor, vis: vis)

        case "say":
            guard let t = e.text, let who = select(e.who, ctx).first else { return }
            log(.speech, render(t, ctx), actor: who)

        case "chance":
            let p = num(e.p, ctx, default: 0.5)
            if state.rng.chance(p) { run(e.then, ctx, notes: &notes) } else { run(e.else, ctx, notes: &notes) }

        case "check":
            let who = select(e.who, ctx).first ?? ctx.actor
            let skill = Double(who.flatMap { scenario.character($0)?.skill(e.skill ?? "survival") } ?? 0)
            let dc = num(e.dc, ctx, default: 50)
            var p = 0.35 + 0.15 * skill - (dc - 50) / 100
            if let w = who { p *= (0.6 + 0.4 * efficiency(w)) }
            p = min(0.95, max(0.05, p))
            practice(who, e.skill ?? "survival")
            var sub = ctx
            if let w = who { sub.actor = w }
            if state.rng.chance(p) { run(e.then, sub, notes: &notes) } else { run(e.else, sub, notes: &notes) }

        case "if":
            if let c = e.when, truthy(c, ctx) { run(e.then, ctx, notes: &notes) } else { run(e.else, ctx, notes: &notes) }

        case "each":
            for id in select(e.who ?? "all", ctx) {
                var sub = ctx
                sub.actor = id
                run(e.do, sub, notes: &notes)
            }

        case "schedule":
            guard let ev = e.event else { return }
            let n = max(1, Int(num(e.in, ctx, default: 1).rounded()))
            state.scheduled.append(ScheduledEvent(eventId: ev, round: state.round + n, actor: ctx.actor, target: ctx.target))

        case "loot":
            guard let pid = e.pool, let pool = scenario.pools?[pid] else { return }
            let who = select(e.who, ctx).first ?? ctx.actor
            let rolls = max(1, Int(num(e.rolls, ctx, default: 1).rounded()))
            var stock = state.poolStock[pid] ?? pool.items.map { $0.stock ?? -1 }
            // a save from before the pool gained or lost items: line the stock up with the pool as it is now
            if stock.count > pool.items.count { stock.removeLast(stock.count - pool.items.count) }
            if stock.count < pool.items.count { stock += pool.items[stock.count...].map { $0.stock ?? -1 } }
            var found: [String] = []
            for _ in 0..<rolls {
                let weights = pool.items.enumerated().map { (i, it) in stock[i] == 0 ? 0 : it.weight }
                guard let idx = state.rng.weightedIndex(weights) else {
                    found.append(L("\(pool.name)已经搜不出什么了", "\(pool.name): nothing left to find"))
                    break
                }
                let item = pool.items[idx]
                if stock[idx] > 0 { stock[idx] -= 1 }
                var itemNotes: [String] = []
                if let r = item.res {
                    let range = item.amount ?? [1, 1]
                    let lo = range.first ?? 1
                    let hi = range.count > 1 ? range[1] : lo
                    var amt = state.rng.range(lo, hi) * state.setup.level.gainScale
                    if (scenario.resource(r)?.decimals ?? 0) == 0 { amt = amt.rounded() }
                    if amt > 0 {
                        state.resources[r, default: 0] += amt
                        itemNotes.append("\(scenario.resource(r)?.name ?? r) \(Fmt.signed(amt, r, scenario))")
                    }
                }
                var sub = ctx
                sub.actor = who
                run(item.effects, sub, notes: &itemNotes)
                if let raw = item.text {
                    // the item's text goes through the template like any other ({actor} → who found it)
                    let t = render(raw, sub)
                    // punctuation follows the game language, not hard-coded full-width brackets
                    let open = lang == .en ? " (" : "（"
                    let close = lang == .en ? ")" : "）"
                    found.append(itemNotes.isEmpty ? t : "\(t)\(open)\(itemNotes.joined(separator: Loc.comma(lang)))\(close)")
                } else if !itemNotes.isEmpty {
                    found.append(itemNotes.joined(separator: Loc.comma(lang)))
                }
            }
            state.poolStock[pid] = stock
            if found.isEmpty { found.append(L("一无所获", "found nothing")) }
            notes.append(contentsOf: found)

        case "yield":
            guard let id = e.id else { return }
            let who = select(e.who, ctx).first ?? ctx.actor
            let skill = Double(who.flatMap { scenario.character($0)?.skill(e.skill ?? "survival") } ?? 0)
            var amount = num(e.base, ctx, default: 1) * (1 + (e.per ?? 0.25) * skill)
            practice(who, e.skill ?? "survival")
            if let wm = e.weather { amount *= wm[state.weather] ?? 1 }
            if let w = who { amount *= efficiency(w) }
            amount *= state.rng.range(0.75, 1.25)
            amount *= state.setup.level.gainScale
            if (scenario.resource(id)?.decimals ?? 0) == 0 { amount = amount.rounded() }
            if amount > 0 {
                state.resources[id, default: 0] += amount
                notes.append("\(scenario.resource(id)?.name ?? id) \(Fmt.signed(amount, id, scenario))")
            } else {
                let rn = scenario.resource(id)?.name ?? id
                notes.append(L("\(rn) 没有收获", "no \(rn.lowercased()) gained"))
            }

        case "work":
            guard let pid = e.project, let proj = scenario.project(pid), !state.projectsDone.contains(pid) else { return }
            let who = select(e.who, ctx).first ?? ctx.actor
            let skill = Double(who.flatMap { scenario.character($0)?.skill(e.skill ?? "technical") } ?? 0)
            var pts = num(e.base, ctx, default: 5) * (1 + (e.per ?? 0.3) * skill)
            practice(who, e.skill ?? "technical")
            if let w = who { pts *= efficiency(w) * buffMods(w).work }
            let before = state.projects[pid] ?? 0
            let after = before + pts
            state.projects[pid] = after
            let pct = Int(min(100, after / proj.work * 100))
            notes.append(L("\(proj.name) 进度 \(pct)%", "\(proj.name) \(pct)% done"))
            if after >= proj.work {
                state.projectsDone.insert(pid)
                log(.result, L("「\(proj.name)」完成了。", "“\(proj.name)” is finished."), actor: who)
                var sub = ctx
                sub.actor = who
                run(proj.onComplete, sub, notes: &notes)
            }

        case "shelter":
            let old = state.shelterIntegrity
            state.shelterIntegrity = min(100, max(0, old + num(e.add, ctx)))
            let d = state.shelterIntegrity - old
            if abs(d) >= 1 { notes.append(L("\(scenario.shelter.name)完好度 \(d > 0 ? "+" : "")\(Int(d))", "\(scenario.shelter.name) condition \(d > 0 ? "+" : "")\(Int(d))")) }

        case "item":
            guard let id = e.id else { return }
            let v = num(e.add, ctx, default: 1)
            for who in select(e.who, ctx) {
                mutate(who) { p in
                    if e.hidden ?? false {
                        p.stash[id] = max(0, (p.stash[id] ?? 0) + v)
                    } else {
                        p.items[id] = max(0, (p.items[id] ?? 0) + v)
                    }
                }
            }

        case "away":
            let rounds = max(1, Int(num(e.rounds, ctx, default: 1).rounded()))
            let camp = num(e.amount, ctx, default: 0)
            // What the trip asks of the body each day (default: light work for 6 hours), kept with the trip.
            var plan = Effect(e: GameEngine.awayPlanTag)
            plan.exertion = (e.exertion.flatMap { Exertion(rawValue: $0) } ?? .light).rawValue
            plan.hours = .const(min(24, max(0, num(e.hours, ctx, default: 6).rounded())))
            for id in select(e.who, ctx) {
                mutate(id) { p in
                    p.status = .away
                    p.awayRounds = rounds
                    p.awayReturn = [plan] + (e.onReturn ?? [])
                    p.awayCamp = camp
                }
                if state.leader == id { /* leader keeps title while away */ }
                notes.append(L("\(name(id)) 出发了，预计 \(rounds) 个回合后回来", "\(name(id)) sets off, expected back in \(rounds) round\(rounds == 1 ? "" : "s")"))
            }

        case "leader":
            let ids = e.who == "none" ? [] : select(e.who, ctx)
            if let id = ids.first {
                state.leader = id
                log(.system, L("\(name(id)) 成了领头人。", "\(name(id)) becomes the leader."), actor: id)
            } else if e.who == "none" {
                state.leader = nil
            }

        case "exile":
            for id in select(e.who, ctx) {
                exile(id)
            }

        case "evacuate":
            for id in select(e.who, ctx) {
                evacuate(id, text: e.text.map { render($0, EffCtx(actor: id, target: ctx.target)) })
            }

        case "leave":
            for id in select(e.who, ctx) {
                leave(id, text: e.text.map { render($0, EffCtx(actor: id, target: ctx.target)) })
            }

        case "end":
            finish(endingId: e.ending ?? "auto")

        case "reveal":
            for id in select(e.who, ctx) { revealSecret(id, voluntary: false) }

        case "weather":
            guard let to = e.to, scenario.climate.weather[to] != nil else { return }
            state.weather = to
            let n = max(0, Int(num(e.rounds, ctx, default: 1).rounded()) - 1)
            state.forcedWeather = n > 0 ? to : nil
            state.forcedWeatherRounds = n

        case "join":
            guard let id = e.id, let c = state.character(id), c.status == .notJoined else { return }
            mutate(id) { $0.status = .active }
            log(.system, L("\(name(id)) 加入了队伍。", "\(name(id)) joins the group."), actor: id)

        default:
            break
        }
    }

    /// `partKey` / `labelKey`: the untranslated text, used to recognise the same injury again.
    func addInjury(_ id: String, kind: String, severity: Double, part: String?, label: String?, partKey: String?, labelKey: String?) {
        let newId = state.nextId
        state.nextId += 1
        mutate(id) { p in
            if let j = p.injuries.firstIndex(where: { $0.same(kind: kind, partKey: partKey, labelKey: labelKey) }) {
                p.injuries[j].severity = min(100, p.injuries[j].severity + severity * 0.7)
                p.injuries[j].treated = false
            } else {
                p.injuries.append(Injury(id: newId, kind: kind, severity: min(100, severity), part: part, label: label, treated: false,
                                         partKey: partKey, labelKey: labelKey))
            }
        }
    }

    /// Someone leaves the story alive (picked up by a boat, carried out by rescuers…).
    public func evacuate(_ id: String, text: String? = nil) {
        guard let c = state.character(id), c.alive else { return }
        let round = state.round
        mutate(id) { p in
            p.status = .rescued
            p.rescuedRound = round
        }
        if state.leader == id { state.leader = nil }
        log(.system, text ?? L("\(name(id)) 被救走了。", "\(name(id)) is taken to safety."), actor: id)
        if state.leader == nil && !state.aliveParticipants.isEmpty && state.characters.contains(where: { $0.status == .rescued && $0.id == id }) {
            // leadership gap is handled by the next elect motion
        }
        checkWipe()
    }

    /// Someone walks out of the story of their own accord (a stranger moves on, a herder goes home…).
    public func leave(_ id: String, text: String? = nil) {
        guard let c = state.character(id), c.alive else { return }
        let round = state.round
        mutate(id) { p in
            p.status = .gone
            p.deathRound = round
        }
        if state.leader == id { state.leader = nil }
        log(.system, text ?? L("\(name(id)) 离开了。", "\(name(id)) leaves."), actor: id)
        checkWipe()
    }

    func exile(_ id: String) {
        guard let c = state.character(id), c.alive else { return }
        mutate(id) { $0.status = .exiled }
        if state.leader == id { state.leader = nil }
        let text = scenario.exileText.map { render($0, EffCtx(actor: id)) } ?? L("\(name(id)) 被赶出了队伍，独自消失在外面。", "\(name(id)) is driven out of the group and disappears alone.")
        log(.death, text, actor: id)
        for o in state.characters where o.alive {
            mutate(o.id) { $0.morale = max(0, $0.morale - 6) }
        }
    }

    // MARK: - Templates

    /// Replaces {actor}, {target}, {leader}, {res.food}, {var.x}, {name.zhou}, {survivors}, …
    public func render(_ template: String, _ ctx: EffCtx) -> String {
        guard template.contains("{") else { return template }
        var out = ""
        var i = template.startIndex
        while i < template.endIndex {
            let ch = template[i]
            if ch == "{", let close = template[i...].firstIndex(of: "}") {
                let key = String(template[template.index(after: i)..<close])
                var value = renderKey(key, ctx) ?? "{\(key)}"
                // English pronouns at the start of a sentence: "… arm. {actor.he} came up" → "He came up"
                if lang == .en, let last = key.split(separator: ".").last, ["he", "him", "his", "hers", "himself"].contains(String(last)) {
                    let before = out.trimmingCharacters(in: .whitespaces)
                    if before.isEmpty || [".", "!", "?", "…", "\n", "“", "\"", "—"].contains(where: { before.hasSuffix($0) }), let f = value.first {
                        value = f.uppercased() + value.dropFirst()
                    }
                }
                out += value
                i = template.index(after: close)
            } else {
                out.append(ch)
                i = template.index(after: i)
            }
        }
        return out
    }

    /// he/she, him/her, his/her … by the character's gender (unknown → male forms).
    public func pronoun(_ id: String?, _ form: String) -> String {
        let female = id.flatMap { scenario.character($0)?.isFemale } ?? false
        switch form {
        case "he": return female ? "she" : "he"
        case "He": return female ? "She" : "He"
        case "him": return female ? "her" : "him"
        case "his": return female ? "her" : "his"
        case "His": return female ? "Her" : "His"
        case "hers": return female ? "hers" : "his"
        case "himself": return female ? "herself" : "himself"
        case "ta": return female ? "她" : "他"
        default: return form
        }
    }

    func renderKey(_ key: String, _ ctx: EffCtx) -> String? {
        switch key {
        case "actor", "self": return name(ctx.actor)
        case "target": return name(ctx.target)
        case "protagonist": return name(ctx.protagonist)
        case "leader": return state.leader.map { name($0) } ?? L("没人", "no one")
        case "day": return String(currentDay)
        case "round": return String(state.round)
        case "temp": return Fmt.temp(currentTemp)
        case "low": return Fmt.temp(state.dayLow)
        case "high": return Fmt.temp(state.dayHigh)
        case "weather": return weatherDef.name
        case "shelter": return scenario.shelter.name
        case "survivors":
            let s = state.characters.filter { $0.survived && $0.status != .notJoined && !isAnimal($0.id) }.map { name($0.id) }
            return s.isEmpty ? L("没有人", "no one") : s.joined(separator: Loc.sep(lang))
        case "dead":
            let s = state.characters.filter { $0.status == .dead && !isAnimal($0.id) }.map { name($0.id) }
            return s.isEmpty ? L("没有人", "no one") : s.joined(separator: Loc.sep(lang))
        case "aliveCount": return String(state.characters.filter { $0.survived && $0.status != .notJoined && !isAnimal($0.id) }.count)
        case "voters": return ctx.voters.map { name($0) }.joined(separator: Loc.sep(lang))
        default:
            let parts = key.split(separator: ".").map(String.init)
            // Pronouns for English text: {actor.he} {target.his} {name.zhou.him} …; Chinese {actor.ta} → 他/她
            if parts.count == 2, ScenarioText.pronounForms.contains(parts[1]) {
                switch parts[0] {
                case "actor", "self": return pronoun(ctx.actor, parts[1])
                case "target": return pronoun(ctx.target, parts[1])
                case "protagonist": return pronoun(ctx.protagonist, parts[1])
                case "leader": return pronoun(state.leader, parts[1])
                default: break
                }
            }
            if parts.count == 3, parts[0] == "name", ScenarioText.pronounForms.contains(parts[2]) {
                return pronoun(parts[1], parts[2])
            }
            if parts.count == 2 {
                switch parts[0] {
                case "name": return name(parts[1])
                case "res": return Fmt.amount(state.resources[parts[1]] ?? 0, parts[1], scenario)
                case "var":
                    if let def = scenario.variable(parts[1]) { return Fmt.variable(state.vars[parts[1]] ?? 0, def, lang) }
                    return Fmt.number(state.vars[parts[1]] ?? 0, 0)
                default: break
                }
            }
            if let v = resolveIdent(key, ctx) { return Fmt.number(v, abs(v - v.rounded()) < 0.05 ? 0 : 1) }
            return nil
        }
    }
}

// MARK: - Formatting

public enum Fmt {
    public static func number(_ v: Double, _ decimals: Int) -> String {
        if decimals <= 0 { return String(Int(v.rounded())) }
        return String(format: "%.\(decimals)f", v)
    }

    public static func temp(_ t: Double) -> String {
        "\(Int(t.rounded()))°C"
    }

    public static func amount(_ v: Double, _ resId: String, _ s: Scenario) -> String {
        let def = s.resource(resId)
        let n = number(v, def?.decimals ?? 0)
        return "\(n) \(unit(def?.unit ?? "", n))".trimmingCharacters(in: .whitespaces)
    }

    public static func signed(_ v: Double, _ resId: String, _ s: Scenario) -> String {
        let def = s.resource(resId)
        let n = number(abs(v), def?.decimals ?? 0)
        return "\(v >= 0 ? "+" : "−")\(n) \(unit(def?.unit ?? "", n))".trimmingCharacters(in: .whitespaces)
    }

    /// English count nouns used as units: singular for exactly 1, plural otherwise ("2 units", "1 dose").
    static let countUnits: [(String, String)] = [
        ("unit", "units"), ("dose", "doses"), ("piece", "pieces"), ("bundle", "bundles"), ("portion", "portions"),
        ("sheet", "sheets"), ("tire", "tires"), ("nut", "nuts"), ("pit", "pits"), ("hour", "hours"), ("can", "cans"),
        ("bottle", "bottles"), ("box", "boxes"), ("pack", "packs"), ("packet", "packets"), ("bag", "bags")
    ]

    static func unit(_ u: String, _ shown: String) -> String {
        let t = u.trimmingCharacters(in: .whitespaces)
        guard let pair = countUnits.first(where: { $0.0 == t || $0.1 == t }) else { return u }
        return (Double(shown) == 1) ? pair.0 : pair.1
    }

    public static func variable(_ v: Double, _ def: VarDef, _ lang: Lang = Loc.ui) -> String {
        switch def.format ?? "number" {
        case "level":
            let lo = def.min ?? 0
            let hi = def.max ?? 100
            let x = (v - lo) / max(1e-9, hi - lo)
            let labels = def.levels ?? (lang == .en ? ["low", "medium", "high", "very high"] : ["低", "中", "高", "极高"])
            let idx = min(labels.count - 1, max(0, Int(x * Double(labels.count))))
            return labels[idx]
        case "percent":
            return "\(Int(v.rounded()))%"
        default:
            return "\(number(v, abs(v - v.rounded()) < 0.05 ? 0 : 1))\(def.unit ?? "")"
        }
    }
}
