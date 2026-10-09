import Foundation

/// What a status changes. Multipliers are 1 and additions 0 when neutral.
public struct BuffMods: Sendable, Equatable {
    /// Added to the task-efficiency multiplier.
    public var eff = 0.0
    /// Morale per day.
    public var morale = 0.0
    /// Multiplier on morale losses.
    public var moraleLoss = 1.0
    /// °C felt everywhere / only outdoors and away.
    public var warm = 0.0
    public var warmOut = 0.0
    /// Multipliers on water loss, energy use and fatigue gained.
    public var water = 1.0
    public var kcal = 1.0
    public var fatigue = 1.0
    /// Multipliers on injury healing and infection risk.
    public var heal = 1.0
    public var infection = 1.0
    /// Multiplier on the chance of an outdoor accident.
    public var accident = 1.0
    /// Multipliers on the care this person gives and on project work.
    public var care = 1.0
    public var work = 1.0
    /// Extra body water lost, liters per day (the salt from a drink of seawater …).
    public var fluid = 0.0
    /// Can't do heavy work / can't do anything but lie there (foul air, stupor).
    public var noHeavy = false
    public var incapacitated = false

    public init() {}

    mutating func add(_ o: BuffMods) {
        eff += o.eff
        morale += o.morale
        moraleLoss *= o.moraleLoss
        warm += o.warm
        warmOut += o.warmOut
        water *= o.water
        kcal *= o.kcal
        fatigue *= o.fatigue
        heal *= o.heal
        infection *= o.infection
        accident *= o.accident
        care *= o.care
        work *= o.work
        fluid += o.fluid
        noHeavy = noHeavy || o.noHeavy
        incapacitated = incapacitated || o.incapacitated
    }
}

/// A status effect on a person: a buff (增益) or a debuff (减益).
public struct BuffDef: Sendable, Identifiable {
    public let id: String
    let zh: String
    let en: String
    public let icon: String
    public let good: Bool
    let zhDesc: String
    let enDesc: String
    public var mods = BuffMods()
    /// Shown for clarity only: the engine already models the effect (cold, thirst, fatigue …).
    public var display = false
    /// Only its owner (and god view) can see it.
    public var secret = false
    /// Can be granted for a number of rounds (by the engine or a scenario's `buff` effect).
    public var timed = false

    public func name(_ lang: Lang) -> String { Loc.pick(zh, en, lang) }
    public func desc(_ lang: Lang) -> String { Loc.pick(zhDesc, enDesc, lang) }
}

/// A timed status on a character.
public struct ActiveBuff: Codable, Sendable, Equatable {
    public var id: String
    /// Rounds left, counting the current one.
    public var rounds: Int
}

/// A status as shown and applied right now.
public struct BuffInstance: Sendable, Identifiable {
    public let def: BuffDef
    /// Rounds left for timed statuses; nil while a condition holds.
    public let rounds: Int?
    public var id: String { def.id }
}

public enum Buffs {
    static func def(_ id: String, _ zh: String, _ en: String, _ icon: String, good: Bool, _ zhDesc: String, _ enDesc: String,
                    display: Bool = false, secret: Bool = false, timed: Bool = false, _ set: (inout BuffMods) -> Void = { _ in }) -> BuffDef {
        var m = BuffMods()
        set(&m)
        return BuffDef(id: id, zh: zh, en: en, icon: icon, good: good, zhDesc: zhDesc, enDesc: enDesc, mods: m, display: display, secret: secret, timed: timed)
    }

    /// Every built-in status, in display order (buffs first).
    public static let all: [BuffDef] = [
        // conditions
        def("fed", "吃饱了", "Well fed", "fork.knife", good: true,
            "最近吃得够：干活效率 +5%，士气每天 +1。", "Eating enough lately: work efficiency +5%, morale +1 a day.") { $0.eff = 0.05; $0.morale = 1 },
        def("spirited", "斗志昂扬", "In good spirits", "flame", good: true,
            "士气在 75 以上：干活效率 +5%，士气下降少 10%。", "Morale above 75: work efficiency +5%, morale falls 10% less.") { $0.eff = 0.05; $0.moraleLoss = 0.9 },
        def("led", "有主心骨", "Steady leadership", "crown", good: true,
            "领头人威望够高（4 级以上）：士气下降少 10%。", "The leader commands respect (Standing 4+): morale falls 10% less.") { $0.moraleLoss = 0.9 },
        // timed
        def("rested", "养足精神", "Well rested", "bed.double", good: true,
            "上一回合好好歇了一场：干活效率 +8%，疲劳增长少 10%。", "Took a proper rest last round: work efficiency +8%, fatigue builds 10% slower.",
            timed: true) { $0.eff = 0.08; $0.fatigue = 0.9 },
        def("warmed", "烤了一夜火", "Warm night", "fireplace", good: true,
            "昨晚守着火过夜：士气每天 +1。", "Spent the night by the fire: morale +1 a day.",
            timed: true) { $0.morale = 1 },
        def("cared", "有人照顾", "Looked after", "hands.sparkles", good: true,
            "刚被人照顾过：伤好得快 10%，士气下降少 10%。", "Someone has been looking after them: injuries heal 10% faster, morale falls 10% less.",
            timed: true) { $0.heal = 1.1; $0.moraleLoss = 0.9 },
        def("comforted", "有人说说话", "A word in the dark", "bubble.left.and.bubble.right", good: true,
            "夜里有信得过的人跟自己说了几句话：士气下降少 10%。", "Someone they trust had a quiet word with them last night: morale falls 10% less.",
            timed: true) { $0.moraleLoss = 0.9 },
        def("hope", "有了盼头", "Something to hope for", "sun.horizon", good: true,
            "出现了转机：士气下降少 25%，干活效率 +5%。", "Things have taken a turn for the better: morale falls 25% less, work efficiency +5%.",
            timed: true) { $0.moraleLoss = 0.75; $0.eff = 0.05 },
        def("shaken", "惊魂未定", "Shaken", "exclamationmark.triangle", good: false,
            "刚经历了死亡或大变故：干活效率 −8%，士气下降多 15%。", "Just lived through a death or a disaster: work efficiency −8%, morale falls 15% more.",
            timed: true) { $0.eff = -0.08; $0.moraleLoss = 1.15 },
        def("sleepless", "熬了一夜", "Up all night", "moon.zzz", good: false,
            "昨晚守夜没睡好：干活效率 −10%，疲劳增长多 25%。", "Kept watch instead of sleeping: work efficiency −10%, fatigue builds 25% faster.",
            timed: true) { $0.eff = -0.1; $0.fatigue = 1.25 },
        def("guilty", "心虚", "Guilty conscience", "eye.slash", good: false,
            "偷吃了公共的东西，还没被发现：士气每天 −3。", "Stole from the common supplies and hasn't been found out: morale −3 a day.",
            secret: true, timed: true) { $0.morale = -3 },
        def("brine", "喝了海水", "Seawater inside", "drop.halffull", good: false,
            "喝下去的盐要用身体里的水排出去：这一天多失水约 0.8 升。", "The salt has to be flushed out with the body's own water: about 0.8 L more lost over the day.",
            timed: true) { $0.fluid = 0.8 },
        def("breathless", "喘不上气", "Short of air", "lungs", good: false,
            "头昏脑涨、喘不过气：干活效率 −30%，干不了重活。", "Light-headed and gasping: work efficiency −30%, no heavy work.",
            timed: true) { $0.eff = -0.3; $0.noHeavy = true },
        def("stupor", "神志不清", "Barely conscious", "zzz", good: false,
            "昏昏沉沉、叫不太醒：什么活也干不了。", "Drowsy and hard to rouse: can't do any work.",
            timed: true) { $0.eff = -0.5; $0.noHeavy = true; $0.incapacitated = true },
        def("breakdown", "崩溃", "Breakdown", "cloud.rain", good: false,
            "撑不住了：缩在一边，谁也不理，什么活也干不了。有人陪着说一天话，才能缓过来；不然要两天。", "Has fallen apart: withdrawn, not talking, can't do any work. A day with someone sitting with them brings them back; otherwise it takes two.",
            timed: true) { $0.eff = -0.5; $0.noHeavy = true; $0.incapacitated = true },
        // conditions the physiology already models (shown so the player can see them)
        def("hungry", "饿", "Hungry", "fork.knife.circle", good: false,
            "吃得比消耗少一大截：干活效率下降，士气下滑，扛冻能力变差。", "Eating far less than they burn: works less well, loses heart, copes worse with cold.", display: true),
        def("parched", "口渴", "Thirsty", "drop.triangle", good: false,
            "缺水超过体重的 3%：士气下滑；超过 6% 开始伤身。", "Short of water by over 3% of body weight: morale slips; past 6% it starts to do harm.", display: true),
        def("soaked", "湿透了", "Soaked", "drop.fill", good: false,
            "衣服湿了：体感温度低 6°C，直到烘干。", "Wet clothes: it feels 6°C colder until they dry.", display: true),
        def("chilled", "发冷", "Chilled", "thermometer.snowflake", good: false,
            "体温低于 36°C：再冷下去就是失温。", "Core temperature below 36°C: any colder and it's hypothermia.", display: true),
        def("feverish", "发热", "Feverish", "thermometer.sun", good: false,
            "体温高于 38°C：中暑或者在发烧。", "Core temperature above 38°C: overheating, or a fever.", display: true),
        def("exhausted", "筋疲力尽", "Exhausted", "battery.25percent", good: false,
            "疲劳 75 以上：干活效率下降，扛冻能力变差。", "Fatigue above 75: works less well and copes worse with cold.", display: true),
        def("despair", "心灰意冷", "In despair", "cloud.rain", good: false,
            "士气低于 20：干活效率 −20%。", "Morale below 20: work efficiency −20%.", display: true),
        // mastery: a skill at 4 or more
        def("m_medical", "妙手", "Skilled hands", "cross.case", good: true,
            "医疗 4 级以上：照顾伤员的效果 +20%，自己的伤好得快 15%。", "Medical 4+: care given is 20% more effective; own injuries heal 15% faster.") { $0.care = 1.2; $0.heal = 1.15 },
        def("m_survival", "野外老手", "Bushcraft", "leaf", good: true,
            "野外 4 级以上：在户外体感 +1°C，户外出意外的概率 −40%。", "Survival 4+: outdoors it feels 1°C warmer; 40% fewer outdoor accidents.") { $0.warmOut = 1; $0.accident = 0.6 },
        def("m_strength", "皮实", "Tough", "figure.strengthtraining.traditional", good: true,
            "体能 4 级以上：血量上限 +5，疲劳增长少 15%。", "Strength 4+: +5 maximum health, fatigue builds 15% slower.") { $0.fatigue = 0.85 },
        def("m_technical", "巧手", "Handy", "wrench.and.screwdriver", good: true,
            "技术 4 级以上：工程进度 +15%。", "Technical 4+: project work goes 15% further.") { $0.work = 1.15 },
        def("m_navigation", "识途", "Pathfinder", "map", good: true,
            "方向 4 级以上：户外出意外的概率 −30%。", "Navigation 4+: 30% fewer outdoor accidents.") { $0.accident = 0.7 },
        def("m_social", "众望", "Respected", "person.3", good: true,
            "威望 4 级以上：当领头人时，在场的人都“有主心骨”。", "Standing 4+: as leader, everyone present has “steady leadership”."),
        // know-how from endless-mode certificates (already applied by the physiology)
        def("p_warm", "保暖有方", "Dressing for the cold", "snowflake", good: true,
            "寒区证：衣物保温 +0.3 clo。", "Cold-weather certificate: clothing +0.3 clo.", display: true),
        def("p_wet", "湿冷不慌", "Wet and calm", "water.waves", good: true,
            "海上证：湿透时扣的保暖减半。", "Sea-survival certificate: being wet costs half as much warmth.", display: true),
        def("p_water", "惜汗如金", "Rationing sweat", "sun.max", good: true,
            "沙漠证：失水少 12%。", "Desert certificate: 12% less water lost.", display: true),
        def("p_calm", "临危不乱", "Calm in a crisis", "brain.head.profile", good: true,
            "心理急救证：士气下降少 25%。", "Psychological first aid certificate: morale falls 25% less.", display: true)
    ]

    static let byId: [String: BuffDef] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    public static func def(_ id: String) -> BuffDef? { byId[id] }
    /// Ids a scenario's `buff` effect may grant.
    public static var timedIds: [String] { all.filter(\.timed).map(\.id) }
    static let mastery: [(skill: String, buff: String)] = [("medical", "m_medical"), ("survival", "m_survival"), ("strength", "m_strength"),
                                                          ("technical", "m_technical"), ("navigation", "m_navigation"), ("social", "m_social")]
    static let perks: [(perk: String, buff: String)] = [("warm", "p_warm"), ("wet", "p_wet"), ("water", "p_water"), ("calm", "p_calm")]

    /// A skill at this level or more brings its knack (mastery). Classic characters top out at 3,
    /// so knacks are something endless-mode players train for.
    public static let masteryLevel = 4
    /// Health per point of Strength and of Survival, and the extra for Tough (Strength 4+).
    public static let healthPerStrength = 3.0, healthPerSurvival = 1.0, toughHealth = 5.0

    /// Maximum health from the body and the skills: 100, +3 per Strength, +1 per Survival, +5 for Tough (Strength 4+).
    public static func healthCap(_ def: CharacterDef?) -> Double {
        guard let def, !def.isAnimal else { return 100 }
        let str = Double(def.skill("strength")), surv = Double(def.skill("survival"))
        return min(140, 100 + healthPerStrength * str + healthPerSurvival * surv + (str >= Double(masteryLevel) ? toughHealth : 0))
    }
}

extension GameEngine {
    /// Maximum health (see `Buffs.healthCap`).
    public func maxHealth(_ id: String) -> Double { Buffs.healthCap(scenario.character(id)) }

    /// Everything affecting this person right now: conditions, mastery, know-how and timed statuses.
    public func buffs(_ id: String) -> [BuffInstance] {
        guard let c = state.character(id), c.alive, let def = scenario.character(id) else { return [] }
        var out: [BuffInstance] = []
        func on(_ bid: String, _ rounds: Int? = nil) {
            if let d = Buffs.def(bid), !out.contains(where: { $0.id == bid }) { out.append(BuffInstance(def: d, rounds: rounds)) }
        }
        let animal = def.isAnimal
        if c.energyEMA >= 0.9 { on("fed") }
        if c.morale >= 75 && !animal { on("spirited") }
        if let l = state.leader, l != id, c.present, state.character(l)?.present ?? false,
           (scenario.character(l)?.skill("social") ?? 0) >= Buffs.masteryLevel { on("led") }
        for b in c.buffs ?? [] where b.rounds > 0 { on(b.id, b.rounds) }
        if c.energyEMA < 0.55 { on("hungry") }
        if max(0, c.thirst) / def.weight * 100 >= 3 { on("parched") }
        if c.wetHours > 0 { on("soaked") }
        if c.core < 36 { on("chilled") }
        if c.core > 38 { on("feverish") }
        if c.fatigue >= 75 { on("exhausted") }
        if c.morale < 20 && !animal { on("despair") }
        if !animal {
            for m in Buffs.mastery where def.skill(m.skill) >= Buffs.masteryLevel { on(m.buff) }
            for p in Buffs.perks where def.hasPerk(p.perk) { on(p.buff) }
        }
        // buffs before debuffs, otherwise in library order
        let order = Dictionary(uniqueKeysWithValues: Buffs.all.enumerated().map { ($1.id, $0) })
        return out.sorted { ($0.def.good ? 0 : 1, order[$0.id] ?? 0) < ($1.def.good ? 0 : 1, order[$1.id] ?? 0) }
    }

    /// The statuses another player can see on this person.
    public func visibleBuffs(_ id: String, viewer: String?) -> [BuffInstance] {
        buffs(id).filter { !$0.def.secret || viewer == id }
    }

    public func hasBuff(_ id: String, _ bid: String) -> Bool { buffs(id).contains { $0.id == bid } }

    /// Combined effect of everything on this person.
    public func buffMods(_ id: String) -> BuffMods {
        var m = BuffMods()
        for b in buffs(id) where !b.def.display { m.add(b.def.mods) }
        return m
    }

    /// Grants a timed status (refreshing it if it's already running); rounds <= 0 removes it.
    func addBuff(_ id: String, _ bid: String, rounds: Int) {
        guard Buffs.def(bid) != nil, state.character(id)?.alive ?? false else { return }
        mutate(id) { p in
            var list = p.buffs ?? []
            if rounds <= 0 {
                list.removeAll { $0.id == bid }
            } else if let j = list.firstIndex(where: { $0.id == bid }) {
                list[j].rounds = max(list[j].rounds, rounds)
            } else {
                list.append(ActiveBuff(id: bid, rounds: rounds))
            }
            p.buffs = list.isEmpty ? nil : list
        }
    }

    /// End of a round: timed statuses run down, then this round's rest, watch and fire leave their mark on the next.
    func tickBuffs() {
        for i in state.characters.indices {
            guard var list = state.characters[i].buffs else { continue }
            for j in list.indices { list[j].rounds -= 1 }
            list.removeAll { $0.rounds <= 0 }
            state.characters[i].buffs = list.isEmpty ? nil : list
        }
        for c in state.characters where c.present {
            let task = state.assignments[c.id]?.task
            if task == "rest" && c.fatigue <= 40 { addBuff(c.id, "rested", rounds: 1) }
            if state.guards.contains(c.id) { addBuff(c.id, "sleepless", rounds: 1) }
            if state.fireLit && !isAnimal(c.id) { addBuff(c.id, "warmed", rounds: 1) }
        }
    }
}
