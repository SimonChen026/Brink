import Foundation

/// When everyone dies, how it happened decides which ending it is (D-056). On the harder settings most games end
/// that way, and "everyone died" should not be a single page.
extension GameEngine {
    /// A coarse kind for a cause of death. The engine writes its causes in Chinese; scenario causes are in the
    /// game's language, so both are matched.
    static func deathKind(_ raw: String) -> String {
        let r = raw.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { r.contains($0) } }
        if has(["窒息", "缺氧", "二氧化碳", "瓦斯", "一氧化碳", "suffocat", "asphyx", "oxygen", "carbon", "methane", "gas"]) { return "air" }
        if has(["失温", "冻", "hypotherm", "frost", "froze", "freez", "cold"]) { return "cold" }
        if has(["溺", "淹", "drown"]) { return "water" }
        if has(["腹泻", "diarrh", "dysenter"]) { return "sick" }
        if has(["脱水", "中暑", "热射", "渴", "dehydrat", "heatstroke", "heat stroke", "heat exhaust", "thirst"]) { return "thirst" }
        if has(["饥", "饿", "耗尽", "starv", "hunger", "exhaust"]) { return "spent" }
        if has(["病", "感染", "败血", "中毒", "高原", "破伤风", "diseas", "illness", "infect", "sepsis", "poison", "fever", "tetanus", "altitude"]) { return "sick" }
        return "hurt"
    }

    /// The ending for a game in which every player died and nobody got out, or nil to use the scenario's own.
    func wipeVariant(base: EndingDef?) -> EndingDef? {
        guard !scenario.isTutorial, state.setup.difficulty != nil, let base else { return nil }
        let players = state.participants.compactMap { state.character($0) }.filter { !$0.isNPC }
        guard players.count >= 2, players.allSatisfy({ $0.status == .dead }),
              !state.characters.contains(where: { !$0.isNPC && $0.status == .rescued }) else { return nil }
        let deaths = players.compactMap { c in c.deathRound.map { (c, $0) } }.sorted { ($0.1, $0.0.id) < ($1.1, $1.0.id) }
        guard let first = deaths.first, let last = deaths.last else { return nil }
        func make(_ id: String, _ zh: String, _ en: String, _ codaZh: String, _ codaEn: String) -> EndingDef {
            EndingDef(id: "wipe_" + id, title: L(zh, en), when: nil, text: base.text + "\n\n" + L(codaZh, codaEn), tone: "bad")
        }
        let lastName = name(last.0.id)

        if last.1 == first.1 {
            return make("together", "一夜之间", "In One Night", "没有人等到下一个早晨。", "Nobody saw another morning.")
        }
        if deaths.count >= 3, last.1 - deaths[deaths.count - 2].1 >= 3 {
            return make("last", "最后一个人", "The Last One",
                        "\(lastName) 在空下来的地方又撑了几天，一个人，没有谁听见。",
                        "\(lastName) lasted a few more days in the emptied place, alone, with no one to hear.")
        }
        let hold = rescueHold
        if hold > 0, last.1 == hold - 1 {
            return make("short", "差一天", "A Day Short", "只要再撑过一两天，或许就会有人找到这里。", "Had they held out a day or two longer, someone might have found the place.")
        }
        var kinds: [String: Int] = [:]
        for (c, _) in deaths { kinds[c.deathKind ?? "hurt", default: 0] += 1 }
        if let top = kinds.sorted(by: { ($1.value, $0.key) < ($0.value, $1.key) }).first, top.key != "hurt", Double(top.value) >= Double(deaths.count) * 0.6 {
            switch top.key {
            case "cold": return make("cold", "冻僵的营地", "The Frozen Camp", "冷，是带走大多数人的东西。", "Cold was what took most of them.")
            case "thirst": return make("thirst", "干透了", "Dried Out", "是渴把大多数人带走的。", "Thirst took most of them.")
            case "spent": return make("spent", "耗尽", "Worn to Nothing", "没有哪一样东西单独杀死了他们：是日子，一天一天，把人耗空了。",
                                      "No single thing killed them. It was the days, one after another, that wore them hollow.")
            case "sick": return make("sick", "病倒的人", "Down With It", "先倒下一个，然后是下一个。", "One fell sick, then the next.")
            case "air": return make("air", "没有空气", "No Air", "最后带走他们的，是空气。", "In the end it was the air that took them.")
            case "water": return make("water", "水里", "In the Water", "水带走了大多数人。", "The water took most of them.")
            default: break
            }
        }
        return nil
    }
}
