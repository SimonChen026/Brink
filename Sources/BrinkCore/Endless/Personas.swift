import Foundation

/// Names, bodies and temperaments for run players (who appear as themselves in the finale).
public enum Personas {
    /// (Chinese name, English name, female). In English a player goes by an English given name and the same surname.
    public static let names: [(String, String, Bool)] = [
        ("沈舟", "Sean Shen", false), ("叶知秋", "Chloe Ye", true), ("顾言", "Ian Gu", false), ("许诺", "Nora Xu", true),
        ("程野", "Eli Cheng", false), ("白露", "Lucy Bai", true), ("方远", "Evan Fang", false), ("温晴", "Claire Wen", true),
        ("齐昊", "Howard Qi", false), ("姜雪", "Sophie Jiang", true), ("孟凡", "Vincent Meng", false), ("罗衣", "Iris Luo", true),
        ("杜衡", "Henry Du", false), ("夏禾", "Hazel Xia", true), ("季川", "Carl Ji", false), ("钟灵", "Linda Zhong", true),
        ("严朔", "Simon Yan", false), ("梁音", "Yvonne Liang", true), ("邵峰", "Felix Shao", false), ("欧阳岚", "Laura Ouyang", true),
        ("陆川", "Lucas Lu", false), ("宋青", "Celia Song", true), ("聂远山", "Austin Nie", false), ("庄晓棠", "Tiffany Zhuang", true)
    ]

    public static let temperaments = ["steady", "bold", "warm", "shrewd", "anxious", "wry"]

    public static func temperamentName(_ t: String, _ lang: Lang) -> String {
        switch t {
        case "steady": return Loc.pick("沉稳", "steady", lang)
        case "bold": return Loc.pick("胆大", "bold", lang)
        case "warm": return Loc.pick("热心", "big-hearted", lang)
        case "shrewd": return Loc.pick("精明", "shrewd", lang)
        case "anxious": return Loc.pick("谨慎", "careful", lang)
        case "wry": return Loc.pick("嘴硬心软", "sharp-tongued, soft-hearted", lang)
        default: return t
        }
    }

    static func personality(_ t: String, _ lang: Lang) -> String {
        switch t {
        case "steady": return Loc.pick("话不多，做事有条理，遇事先想清楚再动。", "Doesn't say much, does things in order, thinks before moving.", lang)
        case "bold": return Loc.pick("敢冲在前面，拿主意快，有时候冲得太快。", "Goes first, decides fast — sometimes too fast.", lang)
        case "warm": return Loc.pick("见不得别人受苦，总想先顾别人，常常顾不上自己。", "Can't stand to see anyone suffer; looks after others first and forgets themselves.", lang)
        case "shrewd": return Loc.pick("什么都算得清，先保住自己，但不坏。", "Keeps careful accounts of everything and looks after number one — but isn't cruel.", lang)
        case "anxious": return Loc.pick("容易往坏处想，所以做事格外细心。", "Expects the worst, and is careful because of it.", lang)
        case "wry": return Loc.pick("嘴上不饶人，爱开玩笑，关键时刻靠得住。", "Teases everyone and never lets a remark pass, but can be counted on when it matters.", lang)
        default: return ""
        }
    }

    static func voice(_ t: String, _ lang: Lang) -> String {
        switch t {
        case "steady": return Loc.pick("说话慢，句子短，不说没用的。", "Speaks slowly, in short sentences, nothing wasted.", lang)
        case "bold": return Loc.pick("嗓门大，爱下结论，“走！”“就这么定了”。", "Loud, decisive: \"Let's go.\" \"That's settled.\"", lang)
        case "warm": return Loc.pick("温和，爱叫别人的名字，常问“你还好吗”。", "Gentle; uses people's names; keeps asking if they're all right.", lang)
        case "shrewd": return Loc.pick("说话留余地，喜欢讲条件。", "Hedges everything and likes to bargain.", lang)
        case "anxious": return Loc.pick("说话快，常问“然后呢”“万一呢”。", "Talks fast: \"And then what?\" \"What if?\"", lang)
        case "wry": return Loc.pick("带点讽刺，越紧张越爱开玩笑。", "Dry, a little sarcastic; the worse it gets, the more jokes.", lang)
        default: return ""
        }
    }

    static func traits(_ t: String) -> TraitsDef {
        switch t {
        case "steady": return TraitsDef(selfish: 0.3, brave: 0.55, trusting: 0.5, ambition: 0.45, temper: 0.2)
        case "bold": return TraitsDef(selfish: 0.4, brave: 0.85, trusting: 0.45, ambition: 0.7, temper: 0.55)
        case "warm": return TraitsDef(selfish: 0.12, brave: 0.6, trusting: 0.7, ambition: 0.3, temper: 0.25)
        case "shrewd": return TraitsDef(selfish: 0.62, brave: 0.4, trusting: 0.3, ambition: 0.6, temper: 0.4)
        case "anxious": return TraitsDef(selfish: 0.45, brave: 0.3, trusting: 0.4, ambition: 0.3, temper: 0.35)
        case "wry": return TraitsDef(selfish: 0.35, brave: 0.6, trusting: 0.45, ambition: 0.45, temper: 0.5)
        default: return TraitsDef(selfish: 0.4, brave: 0.5, trusting: 0.5, ambition: 0.5, temper: 0.4)
        }
    }

    /// A random persona, avoiding names already taken.
    public static func make(_ rng: inout SeededRNG, lang: Lang, taken: Set<String>, female: Bool? = nil) -> Persona {
        var pool = names.filter { !taken.contains($0.0) && !taken.contains($0.1) }
        if let f = female { pool = pool.filter { $0.2 == f } }
        if pool.isEmpty { pool = names }
        let n = rng.pick(pool)!
        let isF = n.2
        let age = rng.int(22, 54)
        let weight = isF ? rng.range(48, 66) : rng.range(60, 86)
        let fat = isF ? rng.range(0.22, 0.30) : rng.range(0.13, 0.23)
        return Persona(name: lang == .en ? n.1 : n.0, female: isF, age: age, weight: (weight * 2).rounded() / 2,
                       fat: (fat * 100).rounded() / 100, temperament: rng.pick(temperaments)!)
    }
}
