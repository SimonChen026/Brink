import Foundation

/// One player's place in the grand ending.
public struct Legacy: Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var controller: String
    public var isHuman: Bool
    public var level: Int
    public var certs: [String]
    public var chapters: Int
    public var survived: Int
    /// One line: walked out of the finale / died in it / left the camp after chapter N …
    public var fate: String
    public var alive: Bool
    public var title: String
    public var epilogue: String
}

/// The end of a run (D-038): the finale's ending, the road there, and everyone's "afterwards".
public struct GrandEnding: Codable, Sendable {
    public var id: String
    public var title: String
    public var tone: String
    public var text: String
    public var finaleTitle: String?
    public var finaleText: String?
    public var recap: [String]
    public var legacies: [Legacy]
    public var chapters: Int
    public var cleared: Int
    /// Added when a run went on endlessly after the finale and then stopped.
    public var addendum: String?
}

public enum GrandEndings {
    public enum Reason { case finale, fallen, retired }

    /// Every grand ending, for the gallery: (id, tone).
    public static let all: [(String, String)] = [("homecoming", "good"), ("higher_ground", "good"), ("embers", "bitter"), ("lone", "bitter"),
                                                 ("sea_remembers", "bad"), ("unfinished", "bad"), ("retired", "bitter")]

    public static func title(_ id: String, _ lang: Lang) -> String {
        switch id {
        case "homecoming": return Loc.pick("归航", "Homecoming", lang)
        case "higher_ground": return Loc.pick("高处", "Higher Ground", lang)
        case "embers": return Loc.pick("余烬", "Embers", lang)
        case "lone": return Loc.pick("独行", "Alone", lang)
        case "sea_remembers": return Loc.pick("海记得", "The Sea Remembers", lang)
        case "unfinished": return Loc.pick("未竟", "Unfinished", lang)
        case "retired": return Loc.pick("收手", "Walking Away", lang)
        default: return id
        }
    }

    static func joinNames(_ names: [String], _ lang: Lang) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        if lang == .en { return names.dropLast().joined(separator: ", ") + " and " + names.last! }
        return names.joined(separator: "、")
    }

    public static func compose(_ run: EndlessRun, reason: Reason, finaleEnding: EndingResult?, library: [CertificateDef]) -> GrandEnding {
        let lang = run.lang
        let L = run.L
        let cleared = run.cleared.count
        var id: String
        var tone: String
        var text: String

        switch reason {
        case .finale:
            let finale = run.history.last { $0.finale }
            let made = finale?.lines.filter(\.survived) ?? []
            let lost = finale?.lines.filter { !$0.survived } ?? []
            let names = joinNames(made.map(\.playerName), lang)
            let lostNames = joinNames(lost.map(\.playerName), lang)
            let npcSaved = finale?.npcSaved ?? 0
            let humanMade = made.contains { l in run.player(l.playerId)?.isHuman ?? false }
            // Homecoming: all five walk out, the finale ends well, and not one of the townspeople with them is lost
            if made.count >= 5 && (finaleEnding?.tone ?? "") == "good" && (finale?.npcLost ?? 0) == 0 {
                id = "homecoming"; tone = "good"
                text = L("八场推演，一场真的。海水退去的第四天，五个人都还在——瘦了，冻伤了，身上带着各自的伤，但都在，还和他们一起护住了 \(npcSaved) 个镇上的人。直升机把最后一批人送下山的时候，有人回头看了一眼山顶的神社，什么也没说。后来他们很少聚在一起谈那几天。可是每年三月的那个下午，五个人的手机会在同一个时刻亮起来。",
                         "Eight drills, and one that was real. On the fourth day after the sea drew back, all five of them were still there — thinner, frostbitten, each carrying their own injuries, but there — and \(npcSaved) people from the town had made it with them. When the helicopter took the last group down the hill, one of them looked back at the shrine on the summit and said nothing. They seldom met to talk about those days afterwards. But every March, on that one afternoon, five phones light up at the same moment.")
            } else if made.count >= 3 {
                id = "higher_ground"; tone = (finaleEnding?.tone ?? "bitter") == "bad" ? "bitter" : "good"
                text = L("他们记住了训练营里最朴素的那一课：地面摇得又久又狠，就往高处跑，不要等。\(names)活着走下了那座山。\(lost.isEmpty ? "" : "\(lostNames)没有。")后来\(made.count) 个人各自回到了自己的城市，有人换了工作，有人在家里多备了一个背包。每当有人问起那几天，他们只说：“我们去了高处。”",
                         "They remembered the plainest lesson of the camp: when the ground shakes hard and long, head for high ground and don't wait. \(names) walked down that hill alive.\(lost.isEmpty ? "" : " \(lostNames) did not.") Afterwards the \(made.count) of them went back to their own cities; one changed jobs, others started keeping a packed bag by the door. Whenever anyone asks about those days, they only say: \"We went to high ground.\"")
            } else if made.count >= 1 {
                if made.count == 1 && humanMade && !run.options.spectator {
                    id = "lone"; tone = "bitter"
                    text = L("最后从山上走下来的只有你一个。你在避难所的名单上写下了另外四个名字：\(lostNames)。后来你又去过一次那座小城，海堤加高了，山上的神社修好了，石阶旁边多了一块碑。你在碑前站了很久，想起八场推演里他们每一个人的样子——那些吵过的架、分过的半块饼干。训练营教会了你怎么活下来，没教你活下来以后怎么办。",
                             "You were the only one who walked down from the hill. On the shelter's list you wrote the other four names: \(lostNames). You went back to that town once, later. The seawall was higher, the shrine on the hill had been repaired, and there was a new stone beside the steps. You stood in front of it for a long time, remembering each of them from the eight drills — the arguments, the half biscuit shared. The camp taught you how to survive. It never taught you what to do after.")
                } else {
                    id = "embers"; tone = "bitter"
                    text = L("活下来的是\(names)。那一夜的雪、山下烧了三天的火、收音机里越来越长的名单，他们后来都很少提起。\(lostNames)留在了那座小城。活着的人把他们的资格证收在一起，寄回了训练营。证书上的照片还是第一天拍的，每个人都在笑。",
                             "The ones who lived were \(names). The snow that night, the fires that burned below for three days, the lists on the radio that kept getting longer — they seldom spoke of any of it later. \(lostNames) stayed behind in that town. The survivors gathered up their certificates and mailed them back to the camp. The photos on them were taken on the first day; everyone is smiling.")
                }
            } else {
                id = "sea_remembers"; tone = "bad"
                text = L("那天下午之后，培训中心的名册上，五个名字后面都画上了同一个记号。他们闯过了八场推演，最后一场却没有重来的机会。几个月后，搜救队在山脚的瓦砾里找到了一本被海水泡过的笔记本，里面是密密麻麻的考证笔记：心肺复苏每分钟 100 到 120 次；地面摇得久，就往高处跑。",
                         "After that afternoon, the same mark was drawn next to all five names in the training centre's register. They had come through eight drills; the last one gave no second chance. Months later a search team found a sea-soaked notebook in the rubble at the foot of the hill, full of exam notes in small handwriting: CPR, 100 to 120 compressions a minute. If the ground shakes for a long time, go to high ground.")
            }
        case .fallen:
            id = "unfinished"; tone = "bad"
            let human = run.human
            let n = human?.outChapter ?? run.chapter
            text = L("第 \(n) 关之后，你的心力耗尽了，离开了训练营。八场推演你们闯过了 \(cleared) 场，终章的那座海边小城你没能去成。临走那天，留下来的人帮你把行李搬到门口。没有人说再见，只有人说：“下次。”可是对有些事来说，没有下次。",
                     "After chapter \(n) your resolve ran out and you left the camp. Of the eight drills you had cleared \(cleared); you never made it to the seaside town of the finale. On the day you left, the ones who stayed carried your bags to the gate. No one said goodbye. Someone said, \"Next time.\" For some things, there is no next time.")
        case .retired:
            id = "retired"; tone = "bitter"
            text = L("闯过 \(cleared) 场推演之后，你决定到此为止。不是所有人都要走到最后——知道什么时候停下，也是训练营教过的一课。你把资格证装进抽屉，偶尔拿出来看看，想起那些雪夜、那片海、那些你扮演过的人。",
                     "After clearing \(cleared) drill(s), you decided that was enough. Not everyone has to go all the way — knowing when to stop is one of the things the camp teaches too. You put your certificates in a drawer and take them out now and then, remembering the snowy nights, the sea, all the people you once played.")
        }

        let recap = run.history.map { h -> String in
            let label = h.finale ? L("终章", "Finale") : L("第 \(h.number) 关", "Chapter \(h.number)")
            let fallen = h.lines.filter { !$0.survived }.map { L("\($0.playerName)（\($0.characterName)）", "\($0.playerName) (\($0.characterName))") }
            let tail = fallen.isEmpty ? L("玩家全员生还", "every player survived") : L("倒下：", "fell: ") + joinNames(fallen, lang)
            return L("\(label)《\(h.title)》· 「\(h.endingTitle)」· \(tail)", "\(label) — \(h.title) · \"\(h.endingTitle)\" · \(tail)")
        }

        let legacies = GrandEndings.legacies(run, library: library)
        var g = GrandEnding(id: id, title: title(id, lang), tone: tone, text: text, finaleTitle: finaleEnding?.title, finaleText: finaleEnding?.text,
                            recap: recap, legacies: legacies, chapters: run.history.count, cleared: cleared, addendum: nil)
        if reason != .finale && run.finaleReached { g.addendum = endlessAddendum(run) }
        return g
    }

    public static func endlessAddendum(_ run: EndlessRun) -> String {
        run.L("终章之后，他们又回到训练营，接着闯了 \(run.depth) 场推演。", "After the finale they went back to the camp and took on \(run.depth) more drill(s).")
    }

    /// Afterwards lines, by what the player leaned on most. {ta}/{he}/{his}/{He} are filled per player.
    static let livedOn: [String: [(String, String)]] = [
        "medical": [
            ("后来{ta}去考了真正的急救员证，周末在社区教人做心肺复苏。", "Later {he} took a real first-aid course and now teaches CPR at the community centre on weekends."),
            ("后来{ta}转行去了急诊科，同事都说{ta}处理伤口的手特别稳。", "Later {he} switched careers to emergency medicine; colleagues say {his} hands are the steadiest on the ward."),
            ("后来{ta}在家附近开了一个急救培训班，墙上挂着训练营的结业照。", "Later {he} started a first-aid class near home. The camp's graduation photo hangs on the wall."),
            ("后来{ta}报名成了红十字会的志愿者，哪里有灾，{ta}的名字就出现在哪里的名单上。", "Later {he} signed up as a Red Cross volunteer; wherever disaster struck, {his} name turned up on the list."),
            ("后来{ta}的包里永远装着止血带和三角巾，地铁上有人晕倒，{ta}总是第一个蹲下去。", "Later {he} always carried a tourniquet and a triangular bandage; when someone collapsed on the subway, {he} was always the first to kneel down.")
        ],
        "survival": [
            ("后来{ta}成了户外向导，每次带队出发前，都要把“三三法则”讲一遍。", "Later {he} became an outdoor guide; before every trip {he} goes over the rule of threes once more."),
            ("后来{ta}每年冬天都要去山里住几天，说是为了记住冷是什么感觉。", "Later {he} spent a few days in the mountains every winter — to remember what cold feels like, {he} said."),
            ("后来{ta}写了一本野外生存的小册子，印了几千本，送给附近的学校。", "Later {he} wrote a little survival handbook, printed a few thousand copies and gave them to local schools."),
            ("后来{ta}去山区的救援队当了几年队员，队里的人都叫{ta}“老推演”。", "Later {he} spent a few years with a mountain rescue team, where everyone called {him} \"the Drill\"."),
            ("后来{ta}在城郊开了一家户外用品店，每卖出一个睡袋，都要跟人讲一遍怎么垫地。", "Later {he} opened an outdoor shop on the edge of town, and with every sleeping bag sold came a lecture on insulating from the ground."),
            ("后来{ta}带着孩子去露营，生火、取水、搭棚子，一样一样地教。", "Later {he} took {his} children camping and taught them, one thing at a time: fire, water, shelter.")
        ],
        "technical": [
            ("后来{ta}进了应急通信队，背包里永远有两块备用电池。", "Later {he} joined an emergency communications team. There are always two spare batteries in {his} pack."),
            ("后来{ta}给老家的村子装了一套应急广播，喇叭现在还挂在村口的电线杆上。", "Later {he} put an emergency broadcast system in {his} home village; the loudspeaker still hangs on the pole by the gate."),
            ("后来{ta}开了一家修理铺，门口贴着一行字：电台、发电机、手摇灯，都修。", "Later {he} opened a repair shop with a sign on the door: radios, generators, wind-up lamps — all fixed here."),
            ("后来{ta}考了业余无线电执照，每个周末都在屋顶上守着频率，听全国各地的人说话。", "Later {he} got an amateur radio licence and spent weekends on the roof listening in, to voices from all over the country.")
        ],
        "navigation": [
            ("后来{ta}带过很多次搜救，从不让任何人在野外独自走散。", "Later {he} led many search-and-rescue trips and never let anyone wander off alone."),
            ("后来{ta}成了定向越野教练，第一课永远是：迷路了，先停下。", "Later {he} became an orienteering coach. The first lesson is always the same: if you're lost, stop."),
            ("后来{ta}把走过的每一条路都画成了地图，抽屉里攒了厚厚一摞。", "Later {he} drew a map of every route {he} ever walked; there's a thick stack of them in a drawer."),
            ("后来{ta}去了测绘院，给山区的村子画避难路线图。", "Later {he} joined a surveying institute and drew evacuation maps for mountain villages.")
        ],
        "social": [
            ("后来{ta}在灾后心理援助站做了几年志愿者，最擅长的是听人说话。", "Later {he} spent a few years volunteering at a post-disaster support centre. What {he} did best was listen."),
            ("后来{ta}当了社区应急志愿者的队长，每次演练都站在最前面喊口令。", "Later {he} became captain of the neighbourhood emergency volunteers, always at the front calling out the drill."),
            ("后来{ta}成了一名中学老师，开学第一课讲的是地震来了怎么办。", "Later {he} became a secondary-school teacher. The first lesson of every year is what to do in an earthquake."),
            ("后来{ta}去做了社区调解员，最难缠的争吵，到{ta}那里总能慢慢说开。", "Later {he} became a community mediator; even the worst quarrels slowly talked themselves out in front of {him}.")
        ],
        "": [
            ("后来{ta}回到了普通的生活，只是开始在家里备一个应急包。", "Later {he} went back to an ordinary life — except that now there's an emergency bag by the door."),
            ("后来{ta}很少提起训练营，只是每次住酒店，都会先去看一眼安全出口。", "Later {he} rarely mentioned the camp — but in every hotel, {he} checks the emergency exits first."),
            ("后来{ta}换了一份安稳的工作，只是手机里一直存着训练营那几个人的号码。", "Later {he} took a quiet, steady job — but the numbers of the people from the camp are still in {his} phone.")
        ]
    ]

    static let diedOn: [String: [(String, String)]] = [
        "medical": [("{name}教过别人的那套止血方法，后来有人在真的灾难里用上了。", "The way {name} taught people to stop bleeding was used, later, in a real disaster.")],
        "survival": [("大家后来在那座山上种了一棵树。冬天下雪的时候，有人会去看看树下的雪有没有化开。", "Afterwards they planted a tree on that hill. When it snows, someone goes to see whether the snow has melted under it.")],
        "technical": [("{ta}修好的那台收音机，后来一直放在神社的仓库里。", "The radio {he} fixed stayed in the shrine's storehouse ever after.")],
        "navigation": [("{ta}画的那张山路图，后来被印在了小城的避难指南上。", "The trail map {he} drew was later printed in the town's evacuation guide.")],
        "social": [("那一夜被{ta}安抚过的人，很多年后还记得{ta}的声音。", "People {he} calmed that night still remembered {his} voice years later.")],
        "": [("活下来的人后来说，{ta}是那天下午最先回头去拉别人的人之一。", "The survivors said later that {he} was among the first to turn back for others that afternoon.")]
    ]

    static func fill(_ t: String, _ p: RunPlayer) -> String {
        let f = p.persona.female
        return t.replacingOccurrences(of: "{ta}", with: f ? "她" : "他")
            .replacingOccurrences(of: "{He}", with: f ? "She" : "He")
            .replacingOccurrences(of: "{he}", with: f ? "she" : "he")
            .replacingOccurrences(of: "{his}", with: f ? "her" : "his")
            .replacingOccurrences(of: "{him}", with: f ? "her" : "him")
            .replacingOccurrences(of: "{name}", with: p.name)
    }

    /// Everyone's "afterwards", varied so that no two players read the same.
    static func legacies(_ run: EndlessRun, library: [CertificateDef]) -> [Legacy] {
        var usedTitles: Set<String> = []
        var usedLines: Set<String> = []
        var usedNotes: Set<String> = []
        return run.players.map { legacy($0, run: run, library: library, titles: &usedTitles, lines: &usedLines, notes: &usedNotes) }
    }

    static func legacy(_ p: RunPlayer, run: EndlessRun, library: [CertificateDef], titles: inout Set<String>, lines: inout Set<String>, notes: inout Set<String>) -> Legacy {
        let lang = run.lang
        let L = run.L
        let certs = p.certs.compactMap { r in library.first { $0.id == r.id } }
        let finaleRec = p.history.last { $0.finale }
        let alive: Bool
        var fate: String
        if let f = finaleRec {
            alive = f.survived
            fate = f.survived ? L("活着走出了终章", "walked out of the finale alive") : L("死在了终章里", "died in the finale")
            if !f.survived, let c = f.deathCause { fate += L("：\(c)", " — \(Loc.lowerFirst(c, lang))") }
        } else if p.out {
            alive = true
            fate = L("第 \(p.outChapter ?? 0) 关之后离开了训练营", "left the camp after chapter \(p.outChapter ?? 0)")
        } else {
            alive = true
            fate = L("一直走到了最后", "stayed to the end")
        }

        // What they leaned on most: certificates first, then ranks
        var weight: [String: Double] = [:]
        for c in certs { weight[c.skill, default: 0] += 2 }
        for (k, v) in p.ranks { weight[k, default: 0] += Double(v) }
        let top = weight.max { a, b in a.value == b.value ? a.key > b.key : a.value < b.value }?.key ?? ""
        let t = p.totals

        // A title nobody else has, if one fits
        // (title, the kind of closing line that goes with it)
        var candidates: [(String, String)] = []
        if t.chapters >= 5 && t.survived == t.chapters { candidates.append((L("不死鸟", "Unbreakable"), "lucky")) }
        if t.cared >= 15 { candidates.append((L("白衣", "The Medic"), "cared")) }
        if t.led >= 15 { candidates.append((L("领头人", "The Leader"), "led")) }
        if certs.count >= 8 { candidates.append((L("持证达人", "Certified in Everything"), "")) }
        if t.thefts >= 3 { candidates.append((L("夜里的手", "Night Hands"), "thefts")) }
        if t.deaths >= 4 { candidates.append((L("死过很多次的人", "Many Lives"), "deaths")) }
        if t.goals >= 4 { candidates.append((L("说到做到", "Keeps Promises"), "goals")) }
        if t.cared >= 8 { candidates.append((L("守夜人", "The Night Nurse"), "cared")) }
        if t.led >= 8 { candidates.append((L("拿主意的人", "The One Who Decides"), "led")) }
        let chosen = candidates.first { !titles.contains($0.0) }
        let title = chosen?.0 ?? Personas.temperamentName(p.persona.temperament, lang)
        let titleKind = chosen?.1 ?? ""
        titles.insert(title)

        let seed = EndlessRun.stableHash(run.id + p.id)
        func pick(_ options: [(String, String)], avoid: inout Set<String>) -> String {
            guard !options.isEmpty else { return "" }
            let start = Int(seed % UInt64(options.count))
            for k in 0..<options.count {
                let o = options[(start + k) % options.count]
                if !avoid.contains(o.0) { avoid.insert(o.0); return fill(lang == .en ? o.1 : o.0, p) }
            }
            return fill(lang == .en ? options[start].1 : options[start].0, p)
        }

        var parts: [String] = []
        let deadForGood = finaleRec.map { !$0.survived } ?? false
        if deadForGood {
            parts.append(pick(diedOn[top] ?? diedOn[""]!, avoid: &lines))
        } else if p.out && finaleRec == nil {
            parts.append(fill(L("离开训练营以后，{ta}很少说起推演里的事，但再也没有订过海边低处的房间。", "After leaving the camp {he} rarely spoke about the drills — but never again booked a room by the sea that wasn't high up."), p))
        } else {
            parts.append(pick(livedOn[top] ?? livedOn[""]!, avoid: &lines))
        }

        // One more line: the most telling thing about how they played (each kind used once if possible)
        // (kind, wordings, how telling) — the wording is picked only for the line actually used
        var extra: [(String, [(String, String)], Double)] = []
        if t.thefts >= 2 { extra.append(("thefts", [("推演里偷吃过的那几口，{ta}一直没跟人提起。", "{He} never told anyone about the food {he} stole in the drills."),
                                                    ("推演里那几个偷偷摸摸的夜晚，{ta}后来想起来，还是会脸红。", "Thinking back on those furtive nights in the drills still makes {him} blush.")], Double(t.thefts) * 1.2)) }
        if t.cared >= 8 { extra.append(("cared", [("很多人记得{ta}守着伤员过夜的样子。", "Many remember {him} sitting up all night with the injured."),
                                                  ("那些被{ta}包扎过的人，后来常常托人带话来道谢。", "People whose wounds {he} once dressed still send their thanks.")], Double(t.cared) / 4)) }
        if t.led >= 8 { extra.append(("led", [("那些年里，大家遇到拿不定的事，还是习惯先问{ta}。", "For years afterwards, when people couldn't decide something, they still asked {him} first."),
                                              ("后来每次聚会，大家还是自然而然地等{ta}先开口。", "At every reunion since, the others still wait for {him} to speak first.")], Double(t.led) / 5)) }
        if t.deaths >= 3 { extra.append(("deaths", [("在推演里“死”过 \(t.deaths) 次，{ta}说，每一次都是真的怕。", "{He} \"died\" \(t.deaths) times in the drills, and says {he} was truly afraid every time.")], Double(t.deaths))) }
        if t.chapters >= 4 && t.survived == t.chapters { extra.append(("lucky", [("推演里{ta}每一场都活着走了出来，{ta}自己说那是运气。", "{He} walked out of every single drill alive — luck, {he} says.")], 5)) }
        if t.goals >= 3 { extra.append(("goals", [("推演里许下的事，{ta}做到了 \(t.goals) 件。", "Of the things {he} set out to do in the drills, {he} managed \(t.goals).")], Double(t.goals))) }
        if t.examsTaken > t.examsPassed + 2 { extra.append(("exams", [("考试没过的那几次，{ta}把错题抄在了本子上，后来全背了下来。", "The exams {he} failed: {he} copied out every wrong answer and learned them all by heart.")], Double(t.examsTaken - t.examsPassed))) }
        extra.sort { $0.2 > $1.2 }
        // the line that explains the title comes first; otherwise the most telling one nobody else got
        if let e = extra.first(where: { $0.0 == titleKind }) ?? extra.first(where: { !notes.contains($0.0) }) ?? extra.first {
            notes.insert(e.0)
            let start = Int(seed % UInt64(e.1.count))
            var chosen = e.1[start]
            for k in 0..<e.1.count where !notes.contains(e.0 + ":" + e.1[(start + k) % e.1.count].0) { chosen = e.1[(start + k) % e.1.count]; break }
            notes.insert(e.0 + ":" + chosen.0)
            parts.append(fill(lang == .en ? chosen.1 : chosen.0, p))
        }

        return Legacy(id: p.id, name: p.name, controller: p.shownController, isHuman: p.isHuman, level: p.level, certs: certs.map { $0.name(lang) },
                      chapters: t.chapters, survived: t.survived, fate: fate, alive: alive, title: title, epilogue: parts.joined(separator: lang == .en ? " " : ""))
    }

}
