import Foundation

/// Things going wrong on top of the scenario's own script (D-055). The harder the setting, the more often a night
/// brings a fever, a bad fall, spoiled food or a leaking water bottle, and the longer the group holds out, the
/// more often it happens: nothing in the real stories is ever as tidy as its script.
extension GameEngine {
    /// Rounds that must pass before any rescue event can happen (0 = no hold).
    var rescueHold: Int {
        guard let after = scenario.rescueAfter, !scenario.isTutorial else { return 0 }
        return Int((Double(after) * state.setup.level.rescueDelay).rounded())
    }

    /// Help hasn't had time to arrive yet: this event waits.
    func isHeld(_ eventId: String) -> Bool {
        state.round < rescueHold && (scenario.rescues?.contains(eventId) ?? false)
    }

    /// Changes how hard the world is from now on (D-057). What already happened stays as it was: the starting
    /// supplies and spirits were set when the game began. Wear, misfortunes, injuries, help and the weather follow
    /// the new setting from here (the weather from the next day). Not in the tutorial or an endless chapter.
    public func changeDifficulty(to level: Difficulty) {
        let old = state.setup.level
        guard old != level, !scenario.isTutorial, state.setup.chapter == nil, state.phase != .ended else { return }
        state.setup.difficulty = level
        log(.system, L("难度从「\(old.label(lang))」调成了「\(level.label(lang))」，从现在起生效。",
                       "Difficulty changed from \(old.label(lang)) to \(level.label(lang)), starting now."))
    }

    /// Called once at the end of each round, after the scenario's own rules have run.
    func rollHardship() {
        let level = state.setup.level
        let rate = level.hardshipRate * (scenario.hardship ?? 1)
        guard rate > 0, !scenario.isTutorial, state.round >= 2, state.phase != .ended else { return }
        // a little worse every day, with a ceiling
        let p = min(0.9, rate * (1 + 0.05 * Double(state.round - 2)))
        var strikes = 0
        while strikes < 3 && state.rng.chance(strikes == 0 ? p : p * 0.4) {
            strikes += 1
            strike()
        }
    }

    /// Nobody stays strong through a long ordeal: everyone is worn down a little more each day, faster when they are
    /// hungry, hopeless or working flat out, slower when they are fed, rested and not alone with it.
    func applyWear(damage: inout [String: [String: Double]]) {
        let level = state.setup.level
        let base = level.wearPerDay * (scenario.hardship ?? 1)
        guard base > 0, !scenario.isTutorial else { return }
        let perRound = base * (1 + 0.1 * Double(state.round - 1)) * Double(hoursPerRound) / 24
        for c in state.characters where c.alive && c.present && !isAnimal(c.id) {
            var w = perRound
            if c.lastIntake >= 1200 { w *= 0.7 } else if c.lastIntake < 400 { w *= 1.3 }
            if state.assignments[c.id]?.task == "rest" { w *= 0.75 }
            if c.morale < 25 { w *= 1.3 } else if c.morale > 60 { w *= 0.8 }
            if hasBuff(c.id, "comforted") { w *= 0.8 }
            if tonightHuddles[c.id] != nil { w *= 0.9 }
            mutate(c.id) { $0.health -= w }
            damage[c.id, default: [:]]["体力耗尽", default: 0] += w
        }
        if level != .normal && state.round % 4 == 0 {
            log(.system, L("日子一天天拖下去，已经没有人还像刚来时那样有劲了。", "The days drag on, and nobody has the strength they had when this began."))
        }
    }

    private enum Misfortune: CaseIterable {
        case fever, cut, twist, gut, badFood, knock, spoiledFood, leakedWater, damp, badNight
    }

    private func strike() {
        let all = Misfortune.allCases
        let weights: [Double] = [3, 2, 2, 1.5, 0.8, 0.8, 2, 1.2, 1, 2.4]
        guard let i = state.rng.weightedIndex(weights) else { return }
        switch all[i] {
        case .fever:
            hurt(kind: "illness", lo: 22, hi: 42,
                 zh: { "\($0) 夜里发起烧来，浑身发冷，起不了身。" }, en: { "\($0) runs a fever in the night, shivering and unable to get up." })
        case .cut:
            hurt(kind: "laceration", lo: 18, hi: 38,
                 zh: { "\($0) 被锋利的碎片划开了手，血一直渗。" }, en: { "\($0) slices a hand open on something sharp, and it keeps bleeding." })
        case .twist:
            hurt(kind: "sprain", lo: 25, hi: 45,
                 zh: { "\($0) 在黑暗里踩空了一脚，脚踝扭了。" }, en: { "\($0) misses a step in the dark and twists an ankle." })
        case .gut:
            hurt(kind: "dysentery", lo: 25, hi: 45,
                 zh: { "\($0) 上吐下泻，整夜跑了好几趟。" }, en: { "\($0) is sick and has diarrhea, up again and again all night." })
        case .badFood:
            hurt(kind: "poisoning", lo: 18, hi: 30,
                 zh: { "\($0) 吃了放坏的东西，中毒了。" }, en: { "\($0) ate something that had gone off and is poisoned." })
        case .knock:
            hurt(kind: "concussion", lo: 20, hi: 40,
                 zh: { "\($0) 摔了一跤，头磕在硬东西上，一直发晕。" }, en: { "\($0) falls and strikes their head on something hard, and stays dizzy." })
        case .spoiledFood:
            spoil("food", lo: 0.07, hi: 0.16,
                  zh: { "一部分\($0)受了潮，发了霉，只能扔掉（\($1)）。" }, en: { "Some of the \($0) has gone damp and mouldy and has to be thrown away (\($1))." })
        case .leakedWater:
            spoil("water", lo: 0.07, hi: 0.15,
                  zh: { "盛\($0)的容器渗漏了，等发现时已经漏掉一截（\($1)）。" }, en: { "A container of \($0) was leaking; by the time anyone noticed a good part was gone (\($1))." })
        case .damp:
            spoil("fuel", lo: 0.1, hi: 0.2,
                  zh: { "一部分\($0)受了潮，点不着了（\($1)）。" }, en: { "Some of the \($0) got damp and won't light (\($1))." })
        case .badNight:
            let drop = state.rng.range(4, 9) * state.setup.level.injuryScale
            log(.result, L("这一夜谁也没睡好，有人在黑暗里小声地哭，有人一直在数还剩多少。大家的士气低了一截。",
                           "Nobody sleeps well tonight: someone cries quietly in the dark, someone keeps counting what is left. Spirits drop."))
            for c in state.characters where c.alive && c.present && !(scenario.character(c.id)?.isAnimal ?? false) {
                mutate(c.id) { $0.morale = max(0, $0.morale - drop) }
            }
        }
    }

    /// Someone gets hurt or sick. Weak people are more likely to be the one, but not only them.
    private func hurt(kind: String, lo: Double, hi: Double, zh: (String) -> String, en: (String) -> String) {
        let pool = state.characters.filter { $0.alive && $0.present && !(scenario.character($0.id)?.isAnimal ?? false) }
        guard !pool.isEmpty else { return }
        let weights = pool.map { c -> Double in
            let frailty = 1 + max(0, 100 - c.health) / 50 + c.fatigue / 100 + Double(c.injuries.count) * 0.3
            return (c.isNPC ? 0.5 : 1) * frailty
        }
        guard let i = state.rng.weightedIndex(weights) else { return }
        let id = pool[i].id
        let sev = state.rng.range(lo, hi) * state.setup.level.injuryScale
        addInjury(id, kind: kind, severity: sev, part: nil, label: nil, partKey: nil, labelKey: nil)
        log(.result, L(zh(name(id)), en(name(id))), actor: id)
    }

    /// A share of one kind of supply is lost.
    private func spoil(_ kind: String, lo: Double, hi: Double, zh: (String, String) -> String, en: (String, String) -> String) {
        let candidates = scenario.resources.filter { $0.kind == kind && (state.resources[$0.id] ?? 0) > 0.5 }
        guard let res = state.rng.pick(candidates) else { return }
        let stock = state.resources[res.id] ?? 0
        var lost = stock * state.rng.range(lo, hi)
        if (res.decimals ?? 0) == 0 { lost = max(1, lost.rounded()) }
        guard lost > 0 else { return }
        state.resources[res.id] = max(0, stock - lost)
        let nm = Loc.inline(res.name, lang)
        let amount = Fmt.signed(-lost, res.id, scenario)
        log(.result, L(zh(nm, amount), en(nm, amount)))
    }
}
