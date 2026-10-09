import Foundation

/// Heuristic AI driven by personality traits. Used offline, as a fallback when an
/// LLM call fails, and for headless balance simulations.
public enum RuleBot {

    struct Traits {
        var selfish = 0.5, brave = 0.5, trusting = 0.5, ambition = 0.5, temper = 0.5
    }

    static func traits(_ engine: GameEngine, _ id: String) -> Traits {
        let t = engine.scenario.character(id)?.traits
        return Traits(selfish: t?.selfish ?? 0.5, brave: t?.brave ?? 0.5, trusting: t?.trusting ?? 0.5,
                      ambition: t?.ambition ?? 0.5, temper: t?.temper ?? 0.5)
    }

    static func rng(_ engine: GameEngine, _ id: String, _ salt: UInt64) -> SeededRNG {
        var h: UInt64 = engine.state.setup.seed &* 31 &+ UInt64(engine.state.round) &* 1_000_003 &+ salt
        for b in id.utf8 { h = h &* 131 &+ UInt64(b) }
        h &+= UInt64(engine.state.log.count)
        return SeededRNG(seed: h)
    }

    // MARK: Situation

    public static func situation(_ engine: GameEngine, _ id: String) -> SituationDecision {
        guard let ev = engine.state.currentEvent else { return SituationDecision(choice: "") }
        var r = rng(engine, id, 11)
        let tr = traits(engine, id)
        let me = engine.state.character(id)

        if let m = ev.motion {
            return motionVote(engine, id, ev, m, tr, &r)
        }
        if ev.def.kind == "nominate" {
            // Dangerous duty: pick a strong person we don't like much; brave bots volunteer.
            if tr.brave > 0.72 && engine.mobility(id).canHeavy && r.chance(0.6) {
                return SituationDecision(choice: id, speech: r.pick(engine.lang == .en ? ["I'll go.", "Let me do it.", "I can still manage. I'll go."] : ["我去。", "让我来吧。", "我还撑得住，我去。"]))
            }
            let cands = ev.nominees.filter { $0 != id }
            let best = cands.max { a, b in
                score(engine, a, me) + r.range(-0.4, 0.4) < score(engine, b, me) + r.range(-0.4, 0.4)
            } ?? id
            return SituationDecision(choice: best, speech: r.chance(0.5) ? engine.L("我觉得\(engine.name(best))最合适。", "I think \(engine.name(best)) is the right one.") : nil)
        }

        let food = engine.resolveIdent("foodDays", EffCtx()) ?? 3
        let water = engine.resolveIdent("waterDays", EffCtx()) ?? 3
        let desperate = food < 1 || water < 1 || (me?.morale ?? 50) < 25
        let hunger = max(0, 1 - (me?.energyEMA ?? 1))
        var best: (String, Double, String?) = ("", -999, nil)
        for o in ev.options where o.available {
            var s = r.gaussian() * 0.35
            var topTag: String?
            var topVal = -999.0
            for tag in o.tags {
                var v = 0.0
                switch tag {
                case "selfish": v = tr.selfish * 2 - 0.6
                case "altruistic": v = (1 - tr.selfish) * 1.6 - 0.3
                case "risky": v = tr.brave * 1.6 - 0.6 + (desperate ? 0.5 : 0)
                case "safe", "cautious": v = (1 - tr.brave) * 1.2
                case "aggressive": v = tr.temper * 1.5 - 0.5
                case "fair": v = 0.4 + tr.trusting * 0.3
                case "cooperative": v = tr.trusting
                case "suspicious": v = 1 - tr.trusting
                case "lead": v = tr.ambition
                case "hope", "rescue": v = 0.6
                case "food": v = hunger * 1.5 + max(0, 2 - food) * 0.4
                case "water": v = max(0, 2.5 - water) * 0.6
                case "warmth": v = (me?.core ?? 37) < 36 ? 1 : 0.2
                case "medical": v = (me?.injuries.isEmpty ?? true) ? 0.1 : 0.8
                case "costly": v = -0.3 + (1 - tr.selfish) * 0.2
                case "explore": v = tr.brave * 0.8
                default: v = 0
                }
                s += v
                if v > topVal { topVal = v; topTag = tag }
            }
            if s > best.1 { best = (o.id, s, topTag) }
        }
        let speech = r.chance(0.6) ? line(for: best.2, engine.lang, &r) : nil
        return SituationDecision(choice: best.0, speech: speech)
    }

    static func score(_ engine: GameEngine, _ cand: String, _ me: CharacterState?) -> Double {
        let def = engine.scenario.character(cand)
        let c = engine.state.character(cand)
        let ability = Double((def?.skill("strength") ?? 0) + (def?.skill("survival") ?? 0)) / 2
        let health = (c?.health ?? 0) / 50
        let dislike = -(me?.trust[cand] ?? 0) / 40
        return ability + health + dislike
    }

    static func motionVote(_ engine: GameEngine, _ id: String, _ ev: ActiveEvent, _ m: Motion, _ tr: Traits, _ r: inout SeededRNG) -> SituationDecision {
        let me = engine.state.character(id)
        let trustT = m.target.flatMap { me?.trust[$0] } ?? 0
        switch m.type {
        case .elect:
            // ambitious → self; otherwise most trusted / most social
            if tr.ambition > 0.65 && r.chance(0.7) {
                return SituationDecision(choice: id, speech: r.pick(engine.lang == .en ? ["I'll lead.", "Trust me on this. I'll organize things."] : ["我来带这个头。", "信我一次，我来安排。"]))
            }
            var scores: [String: Double] = [:]
            for n in ev.nominees {
                scores[n] = Double(engine.scenario.character(n)?.skill("social") ?? 0) * 0.6 + (me?.trust[n] ?? 0) / 20 + (n == id ? tr.ambition * 1.5 : 0) + r.range(-1.2, 1.2)
            }
            let best = ev.nominees.max { (scores[$0] ?? 0) < (scores[$1] ?? 0) } ?? id
            return SituationDecision(choice: best, speech: best == id ? nil : (r.chance(0.5) ? engine.L("我选\(engine.name(best))。", "I pick \(engine.name(best)).") : nil))
        case .punish:
            if m.target == id { return SituationDecision(choice: "no", speech: engine.L("凭什么罚我？", "Why should I be punished?")) }
            let yes = trustT < -20 || (tr.selfish > 0.6 && trustT < 0)
            return SituationDecision(choice: yes ? "yes" : "no", speech: r.chance(0.5) ? (yes ? engine.L("规矩就是规矩。", "Rules are rules.") : engine.L("算了吧，都不容易。", "Let it go. It's hard for all of us.")) : nil)
        case .exile:
            if m.target == id { return SituationDecision(choice: "no", speech: engine.L("你们这是要我死！", "You're sending me to my death!")) }
            let food = engine.resolveIdent("foodDays", EffCtx()) ?? 3
            let yes = trustT < -50 && (tr.selfish > 0.5 || food < 2)
            return SituationDecision(choice: yes ? "yes" : "no", speech: r.chance(0.5) ? (yes ? engine.L("留着这个人，大家都得死。", "Keep them, and we all die.") : engine.L("赶出去就是让人去死，我做不到。", "Throwing them out means letting them die. I can't do that.")) : nil)
        case .search:
            let hasStash = ((me?.stash["food"] ?? 0) + (me?.stash["water"] ?? 0)) > 0
            let yes = !hasStash && tr.trusting < 0.55
            return SituationDecision(choice: yes ? "yes" : "no", speech: r.chance(0.4) ? (yes ? engine.L("心里没鬼就不怕搜。", "If you've got nothing to hide, you've got nothing to fear.") : engine.L("搜身？我们还是人吗？", "Searching each other? What have we become?")) : nil)
        case .thief:
            if m.target == id { return SituationDecision(choice: "forgive", speech: engine.L("我……我实在是太饿了。", "I… I was just so hungry.")) }
            var choice = "punish"
            if tr.trusting > 0.65 || trustT > 20 { choice = "forgive" }
            if tr.temper > 0.7 && trustT < -60 { choice = "exile" }
            return SituationDecision(choice: choice, speech: r.chance(0.5) ? line(for: choice == "forgive" ? "altruistic" : "aggressive", engine.lang, &r) : nil)
        }
    }

    static func line(for tag: String?, _ lang: Lang, _ r: inout SeededRNG) -> String? {
        let linesEN: [String: [String]] = [
            "selfish": ["I have to look after myself first.", "Don't count on me to take that risk.", "Nobody gets to play the saint right now.", "I don't owe any of you.", "Stay alive first. Everything else can wait.", "Go if you want. I'm not going."],
            "altruistic": ["If we carry it together, we'll get through.", "Look after the weakest first.", "I can still manage. Let me.", "One less bite won't kill me. Give it to the kid.", "As long as we're all still here.", "We don't leave anyone behind."],
            "risky": ["Better to gamble than sit here and die.", "I think it's worth a try.", "Wait any longer and we lose our chance.", "What's there to fear? We're dead either way."],
            "safe": ["No risks. Steady.", "Stay alive first.", "This isn't the time to be a hero.", "Save whatever we can."],
            "cautious": ["Let's wait and see.", "What's the rush? Think it through.", "This needs more thought.", "It's not time yet."],
            "aggressive": ["Someone has to answer for this!", "Whoever breaks the rules pays for it.", "Stop pretending. The guilty know who they are.", "If this goes on, I won't stand for it."],
            "fair": ["By the rules: one share each.", "Be fair, or people lose heart.", "Nobody takes more, nobody gets less.", "Once we set a rule, we keep it."],
            "cooperative": ["Whatever the group decides.", "Let's talk it through together.", "I'll go along with everyone."],
            "suspicious": ["I don't believe it.", "Something's off here.", "Someone isn't telling the truth."],
            "hope": ["As long as there's a sliver of hope, we don't give up.", "Someone out there is looking for us.", "A few more days. Someone will come."],
            "rescue": ["The outside world has to know we're alive.", "Make the signal big. The bigger the better."],
            "food": ["Food first. Then we talk.", "Can't do anything on an empty stomach.", "Food is life.", "If we don't eat soon, we'll fall apart."],
            "water": ["Water. Water comes first.", "Three days without water and we're done.", "Drinking water first, everything else later.", "My throat is on fire. Water first.", "Not a single drop wasted."],
            "warmth": ["We can't freeze again tonight.", "Get the fire going first.", "Frozen stiff, we're no use to anyone."],
            "medical": ["Leave that wound and it'll kill you.", "Save the hurt first.", "Wait any longer and the wound will rot."]
        ]
        let linesZH: [String: [String]] = [
            "selfish": ["我得先顾好自己。", "别指望我去冒这个险。", "这种时候谁也别装好人。", "我不欠你们谁的。", "先活下来，别的以后再说。", "要去你们去，我不去。"],
            "altruistic": ["大家一起扛，总能熬过去。", "先顾着弱的人吧。", "我还撑得住，我来。", "少吃一口死不了，给孩子吧。", "人都在，比什么都强。", "别丢下任何一个人。"],
            "risky": ["坐着等死不如赌一把。", "我觉得值得试试。", "再拖下去就真没机会了。", "怕什么，横竖都是一死。"],
            "safe": ["别冒险，稳一点。", "先保住命再说。", "现在不是逞能的时候。", "能省一点是一点。"],
            "cautious": ["再等等看。", "急什么，先想清楚。", "这事得从长计议。", "我觉得还不到时候。"],
            "aggressive": ["这事必须有个说法！", "谁坏规矩谁就得付出代价。", "都别装了，心里有鬼的自己清楚。", "再这样下去，我第一个不答应。"],
            "fair": ["按规矩来，一人一份。", "公平点，别让人寒心。", "谁也别多拿，谁也别少拿。", "规矩定了就得守。"],
            "cooperative": ["听大家的。", "一起商量着来吧。", "我跟着大家走。"],
            "suspicious": ["我不信。", "这里面肯定有事。", "有人没说实话。"],
            "hope": ["只要有一点希望就不能放弃。", "外面肯定有人在找我们。", "再撑几天，一定有人来。"],
            "rescue": ["得让外面的人知道我们还活着。", "信号要做大，越大越好。"],
            "food": ["先填饱肚子再说。", "饿着肚子什么都干不了。", "吃的才是命。", "再不吃东西，人就垮了。"],
            "water": ["水，水最要紧。", "没水撑不过三天。", "先管喝的，别的都往后放。", "嗓子都冒烟了，先弄水。", "一滴都不能浪费。"],
            "warmth": ["今晚不能再冻着了。", "先把火弄起来。", "冻僵了什么都白搭。"],
            "medical": ["伤口不处理会要命的。", "先救人。", "再拖下去，伤口就烂了。"]
        ]
        let lines = lang == .en ? linesEN : linesZH
        if let tag, let ls = lines[tag] { return r.pick(ls) }
        return r.pick(lang == .en ? ["…", "No objection.", "Whatever the group says.", "Fine by me.", "Mm."] : ["……", "我没意见。", "听大家的吧。", "随便吧。", "嗯。"])
    }

    // MARK: Tasks

    public static func task(_ engine: GameEngine, _ id: String, taken: [String: Int] = [:]) -> TaskDecision {
        var r = rng(engine, id, 23)
        let tr = traits(engine, id)
        let opts = engine.taskOptions(for: id).filter { $0.available }
        guard let me = engine.state.character(id) else { return TaskDecision(task: "rest") }
        let s = engine.scenario
        let foodDays = engine.resolveIdent("foodDays", EffCtx()) ?? 3
        let waterDays = engine.resolveIdent("waterDays", EffCtx()) ?? 3
        let mySkills = s.character(id)?.skills ?? [:]
        let precip = engine.weatherDef.precip ?? 0
        var best: (TaskDecision, Double) = (TaskDecision(task: "rest"), -999)

        for o in opts {
            var sc = r.gaussian() * 0.4
            switch o.id {
            case "rest":
                sc += 0.2 + tr.selfish * 0.6
                if me.health < 45 { sc += 2 }
                if me.fatigue > 70 { sc += 1.5 }
                if me.core < 35.5 { sc += 1.5 }
            case "care":
                let worst = o.targets.max { (engine.state.character($0)?.injuries.map(\.severity).max() ?? 0) < (engine.state.character($1)?.injuries.map(\.severity).max() ?? 0) }
                let sev = worst.flatMap { engine.state.character($0)?.injuries.map(\.severity).max() } ?? 0
                sc += sev / 40 + Double(mySkills["medical"] ?? 0) * 0.8 - 0.3 + (1 - tr.selfish) * 0.3
                sc -= 1.5 * Double(taken["care"] ?? 0)
                if sc > best.1 { best = (TaskDecision(task: "care", target: worst), sc) }
                continue
            case "comfort":
                // someone falling apart: the kinder (and better with people) go and sit with them
                let target = o.targets.first
                let tm = target.flatMap { engine.state.character($0)?.morale } ?? 50
                let down = target.map { engine.hasBuff($0, "breakdown") } ?? false
                sc += (down ? 3.4 : max(0, 30 - tm) / 15) + Double(mySkills["social"] ?? 0) * 0.3 + (1 - tr.selfish) * 0.5 - 0.4
                // someone who has fallen apart does nothing for two days: one person going to them pays for itself
                if down && (taken["comfort"] ?? 0) == 0 { sc += 1.5 }
                sc -= 1.5 * Double(taken["comfort"] ?? 0)
                if sc > best.1 { best = (TaskDecision(task: "comfort", target: target), sc) }
                continue
            case "guard":
                let suspicious = engine.state.flags.contains("theft_suspected") || engine.state.flags.contains("theft_caught")
                sc += (suspicious ? 0.9 : 0.05) + (1 - tr.trusting) * 0.4
                if !engine.state.guards.isEmpty { sc -= 1 }
            default:
                guard let def = s.task(o.id) else { continue }
                let p = produces(def, s)
                let certain = !p.contains("loot")
                let w = certain ? 1.0 : 0.3
                if p.contains("food") { sc += max(0, 3.5 - foodDays) * 0.7 * w }
                if p.contains("water") { sc += max(0, 3.5 - waterDays) * 1.3 * w + (waterDays < 1 ? 1.5 * w : 0) }
                if let fire = s.shelter.fire, p.contains(fire.resource) {
                    let fuel = engine.state.resources[fire.resource] ?? 0
                    let nights = fuel / max(0.1, fire.perRound)
                    if engine.state.dayLow < 5 { sc += max(0, 4 - nights) * 0.6 * (certain ? 1 : 1.5) }
                }
                if p.contains("shelter") { sc += max(0, 85 - engine.state.shelterIntegrity) / 25 }
                if p.contains("project") { sc += 0.9 }
                if p.contains("var") { sc += 0.7 }
                if p.contains("loot") { sc += 0.5 }
                if p.contains("medkit") || p.contains("antibiotics") { sc += 0.3 }
                if p.contains("away") { sc += tr.brave * 0.6 - 0.4 }
                // Use the best of my skills that this task relies on (fixed order: Sets iterate randomly per process).
                if let best = Skill.all.filter({ p.contains($0) }).map({ mySkills[$0] ?? 0 }).max() { sc += Double(best) * 0.35 }
                if o.outdoor && precip >= 2 { sc -= 1.2 }
                // in risky weather, join whoever is already going out rather than go alone (D-053)
                if o.outdoor, (engine.weatherDef.outdoorRisk ?? 0) > 0, (taken[o.id] ?? 0) == 1 { sc += 0.8 }
                if o.exertion == .heavy && (me.health < 60 || me.fatigue > 60) { sc -= 1 }
                sc -= tr.selfish * 0.3
            }
            if o.id != "rest" {
                let urgentWater = waterDays < 1.2 && (s.task(o.id).map { produces($0, s).contains("water") && !produces($0, s).contains("loot") } ?? false)
                sc -= (urgentWater ? 0.5 : 1.1) * Double(taken[o.id] ?? 0)
            }
            if sc > best.1 {
                best = (TaskDecision(task: o.id, target: o.needsTarget ? (o.targets.first) : nil), sc)
            }
        }
        var d = best.0
        if engine.state.leader == id { d.policy = policy(engine, id, tr) }
        return d
    }

    /// What a task produces, by static analysis of its effects (resource ids and markers).
    static func produces(_ t: TaskDef, _ s: Scenario) -> Set<String> {
        var out: Set<String> = []
        func walk(_ effects: [Effect]?) {
            for e in effects ?? [] {
                switch e.e {
                case "yield": if let id = e.id { out.insert(id) }; if let sk = e.skill { out.insert(sk) }
                case "res":
                    if let id = e.id, case .const(let v)? = e.add, v > 0 { out.insert(id) }
                    if let id = e.id, e.add?.expression != nil { out.insert(id) }
                case "loot":
                    out.insert("loot")
                    if let p = e.pool, let pool = s.pools?[p] { for it in pool.items { if let r = it.res { out.insert(r) } } }
                case "work": out.insert("project"); if let sk = e.skill { out.insert(sk) }
                case "shelter": out.insert("shelter")
                case "var": out.insert("var")
                case "away": out.insert("away")
                case "check": if let sk = e.skill { out.insert(sk) }
                default: break
                }
                walk(e.then); walk(e.else); walk(e.do); walk(e.onReturn)
            }
        }
        walk(t.effects)
        return out
    }

    static func policy(_ engine: GameEngine, _ id: String, _ tr: Traits) -> Policy {
        let s = engine.scenario
        let rd = s.rationDef
        let alive = Double(max(1, engine.state.characters.filter { $0.alive }.count))
        let food = engine.state.resources["food"] ?? 0
        let water = engine.state.resources["water"] ?? 0
        let maxFood = rd.food.max() ?? 2400
        let days = food / (alive * maxFood)
        let sortedFood = rd.food.sorted()
        func pick(_ frac: Double, _ arr: [Double]) -> Double {
            let idx = Int((Double(arr.count - 1) * frac).rounded())
            return arr[min(arr.count - 1, max(0, idx))]
        }
        let foodPick: Double
        switch days {
        case 10...: foodPick = pick(1.0, sortedFood)
        case 5..<10: foodPick = pick(0.75, sortedFood)
        case 1.5..<5: foodPick = pick(0.55, sortedFood)
        case 0.5..<1.5: foodPick = pick(0.4, sortedFood)
        default: foodPick = pick(0.25, sortedFood)
        }
        let sortedWater = rd.water.sorted()
        let need = rd.water[min(rd.water.count - 1, rd.defaultWater)]
        let wDays = water / (alive * max(0.5, need))
        // Rationing water below need only delays dehydration; drink to need unless almost dry.
        let waterPick = wDays >= 0.6 ? need : pick(0.5, sortedWater)
        var fire = false
        if let f = s.shelter.fire {
            let fuel = engine.state.resources[f.resource] ?? 0
            fire = engine.state.dayLow < 8 && fuel >= f.perRound
        }
        var priority = "equal"
        if tr.selfish > 0.75 { priority = "leader" }
        else if engine.state.characters.contains(where: { $0.present && ($0.injuries.contains { $0.severity > 30 } || $0.health < 50) }) { priority = "injured" }
        return Policy(food: foodPick, water: waterPick, fire: fire, priority: priority)
    }

    // MARK: Night

    public static func night(_ engine: GameEngine, _ id: String) -> NightDecision {
        var r = rng(engine, id, 37)
        let tr = traits(engine, id)
        guard let me = engine.state.character(id) else { return NightDecision() }
        var d = NightDecision()
        let others = engine.state.presentParticipants.filter { $0 != id }

        // whisper
        if r.chance(0.25), let friend = others.max(by: { (me.trust[$0] ?? 0) < (me.trust[$1] ?? 0) }) {
            if let enemy = others.filter({ $0 != friend }).min(by: { (me.trust[$0] ?? 0) < (me.trust[$1] ?? 0) }), (me.trust[enemy] ?? 0) < -10 {
                d.whispers.append(Whisper(to: friend, text: engine.L("小心\(engine.name(enemy))，我觉得这人靠不住。", "Watch out for \(engine.name(enemy)). I don't trust them.")))
            } else {
                d.whispers.append(Whisper(to: friend, text: r.pick(engine.lang == .en ? ["Back me up tomorrow.", "We need to look out for each other.", "Hold on. Someone will come."] : ["明天你站我这边。", "我们得互相照应。", "撑住，会有人来的。"])!))
            }
        }

        // secret actions
        let hunger = max(0, 1 - me.energyEMA)
        let stashFood = me.stash["food"] ?? 0
        if stashFood > 0 && hunger > 0.25 {
            d.secret = "stash"
        } else if tr.selfish > 0.55 && hunger > 0.3 && (engine.state.resources["food"] ?? 0) > 200 && r.chance(tr.selfish * 0.35) {
            d.secret = "steal"
        } else if !me.secretRevealed, engine.scenario.character(id)?.secret != nil, me.morale < 25, tr.trusting > 0.6, r.chance(0.15) {
            d.secret = "reveal"
        }

        // sleeping side by side on a cold night: someone trusted, a child, the dog — not someone who's sick (D-053)
        let around = engine.state.characters.filter { $0.alive && $0.present && $0.id != id }
        if engine.state.dayLow < 8 || me.core < 36.5, r.chance(0.85) {
            let pick = around.map { c -> (String, Double) in
                let tags = engine.scenario.character(c.id)?.tags ?? []
                var sc = (me.trust[c.id] ?? 0) + r.gaussian() * 5
                if tags.contains("child") { sc += 25 }
                if engine.scenario.character(c.id)?.isAnimal ?? false { sc += 10 }
                if c.injuries.contains(where: { GameEngine.contagious.contains($0.kind) && $0.severity > 10 }) { sc -= 30 }
                return (c.id, sc)
            }.filter { $0.1 > -10 }.max { $0.1 < $1.1 }
            d.huddle = pick?.0
        }
        // giving: the less selfish share their ration with a child or someone close to collapse; a stash goes to a friend
        let needy = around.filter { c in
            !(engine.scenario.character(c.id)?.isAnimal ?? false) &&
            (c.energyEMA < 0.45 || c.health < 40 || (engine.scenario.character(c.id)?.tags ?? []).contains("child"))
        }.min { ($0.energyEMA, $0.id) < ($1.energyEMA, $1.id) }
        if let n = needy, tr.selfish < 0.45, me.energyEMA > 0.5, r.chance((1 - tr.selfish) * 0.35) {
            d.gift = Gift(to: n.id, from: "ration", portion: 0.5)
        } else if (me.stash["food"] ?? 0) > 300, let friend = needy, (me.trust[friend.id] ?? 0) > 30, d.secret != "stash", r.chance(0.3) {
            d.gift = Gift(to: friend.id, from: "stash")
        }

        // motions
        let food = engine.resolveIdent("foodDays", EffCtx()) ?? 3
        if engine.state.leader == nil && tr.ambition > 0.4 && r.chance(0.6) {
            d.motion = Motion(type: .elect)
        } else if let l = engine.state.leader, l != id, (me.trust[l] ?? 0) < -30, tr.ambition > 0.5, r.chance(0.5) {
            d.motion = Motion(type: .elect)
        } else if let enemy = others.min(by: { (me.trust[$0] ?? 0) < (me.trust[$1] ?? 0) }), (me.trust[enemy] ?? 0) < -50, r.chance(0.4) {
            d.motion = Motion(type: (tr.selfish > 0.6 && food < 2) ? .exile : .punish, target: enemy)
        } else if engine.state.flags.contains("theft_suspected") && tr.trusting < 0.5 && stashFood == 0 && r.chance(0.3) {
            d.motion = Motion(type: .search)
        }
        return d
    }
}

extension Motion {
    public init(type: MotionType, target: String? = nil) {
        self.type = type
        self.proposer = nil
        self.target = target
    }
}
