import Foundation

/// What people do for each other besides voting (D-053): handing over food and water, sleeping side by side for
/// warmth, falling apart when it's too much, and sitting with someone until they come back.
extension GameEngine {
    /// Two people sharing body heat through the night: about as much as an extra blanket.
    static let huddleWarmth = 3.0
    /// What passes from one sleeper to the next.
    static let contagious: [String] = ["dysentery", "illness"]

    // MARK: Night: gifts and sleeping arrangements

    /// Called from `resolveNight` before the round's physiology runs.
    func arrangeNight(_ decisions: [String: NightDecision], present: [String]) {
        tonightRationGifts = []
        tonightStashWater = [:]
        tonightHuddles = [:]

        // Gifts
        for id in present {
            guard let g = decisions[id]?.gift, let to = resolveName(g.to), to != id,
                  let target = state.character(to), target.alive, target.present else { continue }
            if g.from == "stash" {
                giveFromStash(id, to: to)
            } else {
                let portion = min(1, max(0.25, ((g.portion ?? 0.5) * 4).rounded() / 4))
                tonightRationGifts.append((from: id, to: to, portion: portion))
                let part: String
                switch portion {
                case ..<0.3: part = L("四分之一", "a quarter of")
                case ..<0.6: part = L("一半", "half of")
                case ..<0.9: part = L("四分之三", "three-quarters of")
                default: part = L("全部", "all of")
                }
                log(.result, L("\(name(id)) 把自己今天\(part)的口粮和水分给了 \(name(to))。", "\(name(id)) gives \(name(to)) \(part) their food and water for today."), actor: id, target: to)
                nudgeTrust(to, toward: id, by: 6)
                for o in present where o != id && o != to { nudgeTrust(o, toward: id, by: 2) }
                mutate(id) { $0.morale = min(100, $0.morale + 2) }
                mutate(to) { $0.morale = min(100, $0.morale + 3) }
            }
        }

        // Sleeping side by side: mutual choices first, then whoever is still free
        var wants: [(String, String)] = []
        for id in present {
            guard let raw = decisions[id]?.huddle, let to = resolveName(raw), to != id,
                  let t = state.character(to), t.alive, t.present else { continue }
            wants.append((id, to))
        }
        var pairs: [(String, String)] = []
        func pair(_ a: String, _ b: String) {
            tonightHuddles[a] = b
            tonightHuddles[b] = a
            pairs.append((a, b))
        }
        for (a, b) in wants where tonightHuddles[a] == nil && tonightHuddles[b] == nil && wants.contains(where: { $0.0 == b && $0.1 == a }) { pair(a, b) }
        for (a, b) in wants where tonightHuddles[a] == nil && tonightHuddles[b] == nil { pair(a, b) }
        if !pairs.isEmpty {
            let list = pairs.map { L("\(name($0.0)) 和 \(name($0.1))", "\(name($0.0)) and \(name($0.1))") }.joined(separator: L("；", "; "))
            log(.system, L("今晚挤在一起睡：\(list)。", "Sleeping side by side tonight: \(list)."))
            for (a, b) in pairs {
                nudgeTrust(a, toward: b, by: 2)
                nudgeTrust(b, toward: a, by: 2)
                mutate(a) { $0.morale = min(100, $0.morale + 1) }
                mutate(b) { $0.morale = min(100, $0.morale + 1) }
            }
        }
    }

    /// Hidden food and water handed over quietly: the other eats it tonight.
    func giveFromStash(_ id: String, to: String) {
        guard let c = state.character(id) else { return }
        let food = min(c.stash["food"] ?? 0, 600)
        let water = min(c.stash["water"] ?? 0, 1)
        guard food > 0 || water > 0 else {
            log(.secret, L("\(name(id)) 想分点私藏给 \(name(to))，可是已经什么都没有了。", "\(name(id)) wanted to share something hidden with \(name(to)), but there's nothing left."), actor: id, vis: .only([id]))
            return
        }
        mutate(id) { p in
            p.stash["food"] = max(0, (p.stash["food"] ?? 0) - food)
            p.stash["water"] = max(0, (p.stash["water"] ?? 0) - water)
        }
        mutate(to) { $0.lastIntake += food }
        tonightStashWater[to, default: 0] += water
        var what: [String] = []
        if food > 0 { what.append(L("\(Int(food)) 千卡吃的", "\(Int(food)) kcal of food")) }
        if water > 0 { what.append(L("\(Fmt.number(water, 1)) 升水", "\(Fmt.number(water, 1)) L of water")) }
        let detail = what.joined(separator: Loc.comma(lang))
        log(.secret, L("\(name(id)) 悄悄把自己藏的东西给了 \(name(to))：\(detail)。", "\(name(id)) quietly gives \(name(to)) some of what they'd hidden away: \(detail)."), actor: id, target: to, vis: .only([id, to]))
        nudgeTrust(to, toward: id, by: 10)
    }

    func nudgeTrust(_ who: String, toward other: String, by amount: Double) {
        mutate(who) { $0.trust[other] = max(-100, min(100, ($0.trust[other] ?? 0) + amount)) }
    }

    /// Ration gifts move part of the giver's share to the other person (called while rations are handed out).
    func applyRationGifts(_ given: inout [String: Double]) {
        for gift in tonightRationGifts {
            guard let g = given[gift.from], g > 0, given[gift.to] != nil else { continue }
            let moved = g * gift.portion
            given[gift.from] = g - moved
            given[gift.to, default: 0] += moved
        }
    }

    /// Warmth from the person you're sleeping next to (night hours, both in the shelter).
    func huddleWarmthNow(_ id: String, clockHour ch: Int) -> Double {
        guard ch >= 21 || ch < 7, let partner = tonightHuddles[id],
              let p = state.character(partner), p.alive, p.present, !state.guards.contains(partner), !state.guards.contains(id) else { return 0 }
        return GameEngine.huddleWarmth
    }

    // MARK: End of the round

    /// Sleeping next to someone sick is how illness spreads in a shelter.
    func spreadIllness() {
        let pairs = tonightHuddles.keys.sorted().map { ($0, tonightHuddles[$0]!) }
        for (a, b) in pairs {
            guard let sick = state.character(b), let me = state.character(a), me.alive, sick.alive else { continue }
            for kind in GameEngine.contagious {
                guard sick.injuries.contains(where: { $0.kind == kind && $0.severity > 10 }),
                      !me.injuries.contains(where: { $0.kind == kind }), state.rng.chance(0.15) else { continue }
                addInjury(a, kind: kind, severity: 12, part: nil, label: nil, partKey: nil, labelKey: nil)
                let k = InjuryKind.name(kind, lang)
                log(.result, L("\(name(a)) 也染上了\(k)——昨晚和 \(name(b)) 挤在一起睡。", "\(name(a)) has come down with \(k) too — they slept next to \(name(b))."), actor: a)
            }
        }
    }

    /// Too little hope for too long and a person falls apart: they can't do anything until someone sits with them,
    /// and the despair spreads a little.
    func checkBreakdowns() {
        let round = state.round
        for c in state.characters where c.alive && c.present && !hasBuff(c.id, "breakdown") && c.morale < 10 {
            if scenario.character(c.id)?.isAnimal ?? false { continue }
            if let last = c.lastBreakdown, round - last < 4 { continue }
            let p = min(0.35, 0.1 + (10 - c.morale) * 0.025)
            guard state.rng.chance(p) else { continue }
            addBuff(c.id, "breakdown", rounds: 2)
            mutate(c.id) { $0.lastBreakdown = round }
            let n = name(c.id)
            let lines = [
                L("\(n) 撑不住了：抱着头缩在角落里，谁说话都不应。", "\(n) has fallen apart — curled up in a corner, head in hands, not answering anyone."),
                L("\(n) 突然大哭起来，哭到喘不上气，说再也不想动了。", "\(n) suddenly breaks down sobbing, can't catch a breath, says they can't go on."),
                L("\(n) 一整天盯着一个地方发呆，叫名字也没有反应。", "\(n) stares at one spot all day and doesn't react to their own name."),
                L("\(n) 冲着所有人吼了一通，然后一个人走到边上坐着，怎么劝都不回来。", "\(n) shouts at everyone, then goes and sits apart and won't come back however they're asked.")
            ]
            log(.result, state.rng.pick(lines) ?? lines[0], actor: c.id)
            for o in state.characters where o.alive && o.present && o.id != c.id {
                mutate(o.id) { $0.morale = max(0, $0.morale - 1) }
            }
        }
    }

    func clearNightArrangements() {
        tonightRationGifts = []
        tonightStashWater = [:]
        tonightHuddles = [:]
    }

    // MARK: Comforting someone

    /// People who could use someone sitting with them today.
    func comfortTargets(for id: String) -> [String] {
        state.characters
            .filter { $0.alive && $0.present && $0.id != id && !(scenario.character($0.id)?.isAnimal ?? false) && ($0.morale < 35 || hasBuff($0.id, "breakdown")) }
            // whoever has fallen apart first, then the lowest spirits
            .sorted { (hasBuff($0.id, "breakdown") ? 0 : 1, $0.morale, $0.id) < (hasBuff($1.id, "breakdown") ? 0 : 1, $1.morale, $1.id) }
            .map(\.id)
    }

    /// A day spent listening: it steadies them, and it can bring someone back from a breakdown. Works better from
    /// someone they trust, and from someone good with people.
    func performComfort(by id: String, on t: String) -> [String] {
        guard let tc = state.character(t), tc.alive else { return [] }
        let trust = tc.trust[id] ?? 0
        let social = Double(scenario.character(id)?.skill("social") ?? 0)
        var gain = (8 + 0.08 * max(-50, trust) + 2.5 * social) * state.rng.range(0.8, 1.2)
        gain = max(2, gain)
        let wasDown = hasBuff(t, "breakdown")
        mutate(t) { $0.morale = min(100, $0.morale + gain) }
        nudgeTrust(t, toward: id, by: 4)
        nudgeTrust(id, toward: t, by: 3)
        mutate(id) { $0.morale = min(100, $0.morale + 1) }
        if wasDown { addBuff(t, "breakdown", rounds: 0) }
        addBuff(t, "comforted", rounds: 1)
        practice(id, "social")
        var notes = [L("陪着 \(name(t)) 说了一整天的话，\(name(t)) 士气 +\(Int(gain.rounded()))", "spent the day with \(name(t)), talking it through: \(name(t)) morale +\(Int(gain.rounded()))")]
        if wasDown { notes.append(L("\(name(t)) 从崩溃里缓过来了", "\(name(t)) has come back from the breakdown")) }
        return notes
    }
}
