import Foundation

/// Builds the prompts an LLM player sees (in the game's language). Each player only sees what
/// their character could know: public events, their own whispers, their own secret and diary.
public enum Prompting {

    // MARK: Labels

    static func trustLabel(_ t: Double, _ lang: Lang) -> String {
        switch t {
        case 50...: return Loc.pick("非常信任", "trust completely", lang)
        case 20..<50: return Loc.pick("比较信任", "fairly trust", lang)
        case -20..<20: return Loc.pick("一般", "neutral", lang)
        case -50 ..< -20: return Loc.pick("有些怀疑", "somewhat suspicious", lang)
        default: return Loc.pick("很不信任", "deeply distrust", lang)
        }
    }

    static func skillText(_ def: CharacterDef, _ lang: Lang) -> String {
        Skill.all.map { lang == .en ? "\(Skill.name($0, lang)) \(def.skill($0))" : "\(Skill.name($0, lang))\(def.skill($0))" }
            .joined(separator: Loc.sep(lang))
    }

    static func ageRole(_ def: CharacterDef, _ lang: Lang) -> String {
        lang == .en ? "\(def.age), \(def.role)" : "\(def.age)岁，\(def.role)"
    }

    // MARK: System prompt (stable for the whole game)

    public static func system(_ engine: GameEngine, _ id: String) -> String {
        let s = engine.scenario
        let lang = engine.lang
        let L = engine.L
        guard let me = s.character(id) else { return "" }
        var out: [String] = []
        out.append(L("你正在参与《绝境》——一场根据真实灾难改编的生存模拟。你扮演其中一名幸存者。你不是 AI 助手，你就是这个人：用他的眼睛看，用他的脑子想，用他的嘴说话。",
                     "You are taking part in Brink, a survival simulation based on real disasters. You play one of the survivors. You are not an AI assistant — you ARE this person: see through their eyes, think with their mind, speak with their mouth."))
        out.append("")
        out.append(L("【场景】《\(s.title)》\(s.subtitle)", "[Scenario] \(s.title) — \(s.subtitle)"))
        out.append(s.briefing.joined(separator: "\n"))
        var loc = L("【地点】\(s.setting.location)", "[Location] \(s.setting.location)")
        if let alt = s.setting.altitude { loc += L("，海拔约 \(Int(alt)) 米", ", about \(Int(alt)) m above sea level") }
        if let d = s.setting.date { loc += L("｜\(d)", " | \(d)") }
        out.append(loc)
        out.append("")
        out.append(L("【你是】\(me.name)，\(me.gender)，\(ageRole(me, lang))。", "[You are] \(me.name), \(me.gender), \(ageRole(me, lang))."))
        out.append(L("【背景】\(me.bio)", "[Background] \(me.bio)"))
        out.append(L("【性格】\(me.personality)", "[Personality] \(me.personality)"))
        if let v = me.voice { out.append(L("【说话方式】\(v)", "[How you talk] \(v)")) }
        out.append(L("【技能】\(skillText(me, lang))（0=不会，3=专家，5=顶尖）", "[Skills] \(skillText(me, lang)) (0 = none, 3 = expert, 5 = the best there is)"))
        if let sec = me.secret { out.append(L("【你的秘密】\(sec)（只有你自己知道。说不说、什么时候说、对谁说，由你决定。）", "[Your secret] \(sec) (Only you know this. Whether, when and to whom you reveal it is up to you.)")) }
        if let g = me.goal { out.append(L("【你的个人目标】\(g.text)", "[Your personal goal] \(g.text)")) }
        // endless mode: the player's career memory (other chapters, the other players)
        if let note = engine.state.setup.notes?[id], !note.isEmpty {
            out.append("")
            out.append(note)
        }
        out.append("")
        out.append(L("【同伴】（大家都知道的公开信息）", "[The others] (public knowledge)"))
        for c in s.allCharacters where c.id != id {
            let tag = (s.npcs ?? []).contains { $0.id == c.id } ? L("（不参与决策）", " (takes no part in decisions)") : ""
            out.append(L("- \(c.name)\(tag)：\(c.gender)，\(ageRole(c, lang))。\(c.bio)", "- \(c.name)\(tag): \(c.gender), \(ageRole(c, lang)). \(c.bio)"))
        }
        out.append("")
        out.append(L("""
        【规则】
        1. 活下去是第一位的，其次是你的个人目标。你可以合作，也可以自私、隐瞒、撒谎、拉帮结派、背叛——取决于你的性格和处境。别人也一样，不要轻信任何人。
        2. 世界由客观的物理和生理规律决定（体温、热量、饮水、伤病、天气）。你只能决定自己做什么，结果不由你说了算。吃饱、好好休息、守着火过夜、被人照顾、出现转机，会带来增益；守夜熬夜、目睹有人死去、偷吃心虚，会带来减益。体能和野外技能越高，血量上限越高；某项技能到 4 级，还会有一项额外的本事。
        3. 说话要像真人，像在黑暗里压低嗓子跟身边的人说话：口语，短句，常常只说半句；会重复，会被自己的话噎住，会骂一句，会答非所问，也会沉默（不想说话就把 speech 留成空字符串）。多说身上的感觉（冷、渴、饿、疼、困）和眼前看到的东西，不要报数字，不要复述选项和规则，不要像发言稿那样总结陈词。可以直接叫名字、接别人刚说的话、反驳、插嘴；对孩子、对信得过的人、对不对付的人，语气各不相同。越累越渴，话越慢越短。符合你的身份、性格和说话方式，一般不超过 50 个字。不要写旁白，不要用括号描写动作。
        4. 完全代入这个人，包括他的自私、恐惧、偏见和缺点。不要说教，不要总想着做“正确的事”；真实的人在绝境里会算计、会犯错、会翻脸。
        5. 每次只输出一个 JSON 对象（json 格式），不要输出任何其他文字，不要用代码块。
        6. 想法、发言、私聊、日记都用中文写，不要夹杂英文。
        """, """
        [Rules]
        1. Staying alive comes first, then your personal goal. You may cooperate — or be selfish, hide things, lie, form alliances, betray — depending on your personality and situation. So may everyone else; don't trust anyone blindly.
        2. The world follows objective physical and physiological rules (body temperature, calories, water, injuries, weather). You only decide what you do; you don't get to decide the outcome. Eating enough, a proper rest, a night by the fire, being looked after and a turn for the better give buffs; keeping watch all night, seeing someone die and the guilt of stealing give debuffs. Strength and Survival raise your maximum health, and any skill at 4 or more brings an extra knack.
        3. Talk like a real person, the way you would to someone next to you in the dark with your voice kept low: spoken language, short sentences, often only half a sentence. You repeat yourself, choke on your own words, swear once, answer a different question, or say nothing (leave speech as an empty string). Talk about what your body feels (cold, thirst, hunger, pain, tiredness) and what you can see, not numbers; do not repeat the options or the rules, and do not wrap up like a speech. You can call people by name, pick up what someone just said, push back, cut in; your tone differs for a child, for someone you trust, for someone you do not. The more tired and thirsty you are, the slower and shorter you talk. Fit who you are and how you talk; usually under 30 words. No narration, no actions in brackets.
        4. Inhabit this person fully, including their selfishness, fear, prejudice and flaws. Don't preach and don't always try to do "the right thing"; real people in desperate situations scheme, make mistakes and turn on each other.
        5. Every time, output exactly one JSON object (json format) and nothing else — no other text, no code fences.
        6. Write your thoughts, speech, whispers and diary in English only.
        """))
        return out.joined(separator: "\n")
    }

    // MARK: Observation (what this character knows right now)

    public static func observation(_ engine: GameEngine, _ id: String) -> String {
        let s = engine.scenario
        let st = engine.state
        let lang = engine.lang
        let L = engine.L
        let sep = Loc.sep(lang), semi = Loc.semi(lang)
        guard let me = st.character(id), let meDef = s.character(id) else { return "" }
        var out: [String] = []
        let w = engine.weatherDef
        let lo = Fmt.temp(st.dayLow), hi = Fmt.temp(st.dayHigh)
        out.append(L("【现在】\(engine.roundLabel) \(engine.clockLabel)｜天气：\(w.name)，今天 \(lo) ~ \(hi)\(w.desc.map { "。\($0)" } ?? "")",
                     "[Now] \(engine.roundLabel), \(engine.clockLabel) | Weather: \(w.name), today \(lo) to \(hi)\(w.desc.map { ". \($0)" } ?? "")"))

        // Self
        let weight = meDef.weight
        let pct = max(0, me.thirst) / weight * 100
        let spare = max(0, me.fatKg - weight * Physio.essentialFatFraction(female: meDef.isFemale))
        let burn = max(1500, me.reportKcal > 0 ? me.reportKcal : 2500)
        let fatDays = spare * Physio.kcalPerKgFat / burn
        let pctS = String(format: "%.1f", pct), coreS = String(format: "%.1f", me.core)
        let fed = Int(min(1, me.energyEMA) * 100)
        let cap = Int(engine.maxHealth(id))
        var body = L("【你的身体】健康 \(Int(me.health))/\(cap)（\(Physio.healthLabel(me.health, lang))）；体温 \(coreS)°C（\(Physio.coreLabel(me.core, lang))）",
                     "[Your body] health \(Int(me.health))/\(cap) (\(Physio.healthLabel(me.health, lang))); core temperature \(coreS)°C (\(Physio.coreLabel(me.core, lang)))")
        body += L("；\(Physio.dehydrationLabel(pct, lang))（缺水约体重的 \(pctS)%）", "; \(Physio.dehydrationLabel(pct, lang)) (water deficit ≈ \(pctS)% of body weight)")
        body += L("；\(Physio.hungerLabel(me.energyEMA, lang))（最近吃到的只有消耗的 \(fed)%，体脂还能撑约 \(Int(fatDays)) 天）",
                  "; \(Physio.hungerLabel(me.energyEMA, lang)) (lately eating \(fed)% of what you burn; body fat would last about \(Int(fatDays)) more days)")
        body += L("；疲劳 \(Int(me.fatigue))/100（\(Physio.fatigueLabel(me.fatigue, lang))）；士气 \(Int(me.morale))/100（\(Physio.moraleLabel(me.morale, lang))）",
                  "; fatigue \(Int(me.fatigue))/100 (\(Physio.fatigueLabel(me.fatigue, lang))); morale \(Int(me.morale))/100 (\(Physio.moraleLabel(me.morale, lang)))")
        if me.wetHours > 0 { body += L("；衣服是湿的", "; your clothes are wet") }
        out.append(body)
        if !me.injuries.isEmpty {
            out.append(L("  伤病：", "  Injuries: ") + me.injuries.map { inj in
                let sev = InjuryKind.severityLabel(inj.severity, lang)
                return L("\(inj.displayName(lang))（\(sev)\(inj.treated ? "，已处理" : "")）", "\(inj.displayName(lang)) (\(sev)\(inj.treated ? ", treated" : ""))")
            }.joined(separator: sep))
        }
        let statuses = engine.buffs(id)
        if !statuses.isEmpty {
            out.append(L("  状态：", "  Status: ") + statuses.map { b in
                let d = b.def.desc(lang).trimmingCharacters(in: CharacterSet(charactersIn: "。."))
                let left = b.rounds.map { L("，还剩 \($0) 回合", ", \($0) round(s) left") } ?? ""
                return L("\(b.def.name(lang))（\(d)\(left)）", "\(b.def.name(lang)) (\(d)\(left))")
            }.joined(separator: sep))
        }
        let items = me.items.filter { $0.value > 0 && !s.itemName($0.key).isEmpty }.sorted { $0.key < $1.key }.map { "\(s.itemName($0.key))×\(Fmt.number($0.value, 0))" }
        if !items.isEmpty { out.append(L("  随身物品：", "  You carry: ") + items.joined(separator: sep)) }
        let stash = me.stash.filter { $0.value > 0 && ($0.key == "food" || $0.key == "water") }.sorted { $0.key < $1.key }.map { k, v in
            k == "food" ? L("食物 \(Int(v)) 千卡", "\(Int(v)) kcal of food") : L("水 \(Fmt.number(v, 1)) 升", "\(Fmt.number(v, 1)) L of water")
        }
        if !stash.isEmpty { out.append(L("  你的私藏（只有你知道）：", "  Your private stash (only you know): ") + stash.joined(separator: sep)) }
        if me.punishedRounds > 0 { out.append(L("  你正在受罚：口粮减半（还剩 \(me.punishedRounds) 回合）", "  You are being punished: half rations (\(me.punishedRounds) more round(s))")) }

        // Group
        let leader = st.leader.map { $0 == id ? L("你自己", "you") : engine.name($0) } ?? L("还没有领头人", "no leader yet")
        out.append(L("【队伍】领头人：\(leader)｜配给：\(engine.policyText(st.policy))", "[The group] Leader: \(leader) | Rations: \(engine.policyText(st.policy))"))
        let fireLabel = Loc.inline(s.shelter.fire?.label ?? L("火", "fire"), lang)
        out.append(L("  庇护所：\(s.shelter.name)（完好度 \(Int(st.shelterIntegrity))%）\(st.fireLit ? "，昨晚点着\(fireLabel)" : "")",
                     "  Shelter: \(s.shelter.name) (condition \(Int(st.shelterIntegrity))%)\(st.fireLit ? ", the \(fireLabel) burned last night" : "")"))
        var stock: [String] = []
        for r in s.resources {
            let v = st.resources[r.id] ?? 0
            if (r.hidden ?? false) && v <= 0 { continue }
            var t = "\(r.name) \(Fmt.amount(v, r.id, s))"
            if r.id == "food" {
                let alive = Double(max(1, st.characters.filter { $0.alive }.count))
                let days = String(format: "%.1f", st.policy.food > 0 ? v / (alive * st.policy.food) : 99)
                t += L("（按现在的配给够全员吃约 \(days) 天）", " (≈\(days) days for everyone at current rations)")
            }
            stock.append(t)
        }
        out.append(L("  物资：", "  Supplies: ") + stock.joined(separator: sep))
        let shown = (s.vars ?? []).filter { $0.show ?? false }.map { "\($0.name)\(Loc.colon(lang))\(Fmt.variable(st.vars[$0.id] ?? 0, $0, lang))" }
        if !shown.isEmpty { out.append(L("  状况：", "  Situation: ") + shown.joined(separator: semi)) }
        let projects = (s.projects ?? []).filter { p in
            !(st.projectsDone.contains(p.id)) && ((st.projects[p.id] ?? 0) > 0 || (p.when.map { engine.truthy($0, EffCtx(actor: id)) } ?? true))
        }.map { "\($0.name) \(Int(min(1, (st.projects[$0.id] ?? 0) / max(1, $0.work)) * 100))%" }
        if !projects.isEmpty { out.append(L("  工程：", "  Projects: ") + projects.joined(separator: sep)) }
        let done = (s.projects ?? []).filter { st.projectsDone.contains($0.id) }.map(\.name)
        if !done.isEmpty { out.append(L("  已完成：", "  Finished: ") + done.joined(separator: sep)) }

        // Others
        out.append(L("【其他人】", "[The others]"))
        for c in st.characters where c.id != id && c.status != .notJoined {
            let name = engine.name(c.id)
            switch c.status {
            case .dead:
                out.append(L("  - \(name)：已遇难（第 \(c.deathRound ?? 0) 回合，\(c.deathCause ?? "")）", "  - \(name): dead (round \(c.deathRound ?? 0), \(c.deathCause ?? ""))"))
                continue
            case .exiled:
                out.append(L("  - \(name)：被赶出了队伍", "  - \(name): thrown out of the group"))
                continue
            case .away:
                out.append(L("  - \(name)：外出中", "  - \(name): away"))
                continue
            case .rescued:
                out.append(L("  - \(name)：已经被救走了", "  - \(name): already rescued"))
                continue
            case .gone:
                out.append(L("  - \(name)：已经离开了", "  - \(name): has left"))
                continue
            default: break
            }
            var looks: [String] = []
            looks.append(L("看起来\(Physio.healthLabel(c.health, lang))", "looks \(Physio.healthLabel(c.health, lang))"))
            if c.core < 34.5 { looks.append(L("冻得说不出话", "too cold to speak")) } else if c.core < 36 { looks.append(L("在发抖", "shivering")) }
            if c.core > 38.5 { looks.append(L("在发烧", "feverish")) }
            let cw = s.character(c.id)?.weight ?? 65
            if max(0, c.thirst) / cw * 100 > 4 { looks.append(L("嘴唇干裂", "cracked lips")) }
            if c.morale < 20 { looks.append(L("一直不说话", "hasn't said a word in a while")) }
            let inj = c.injuries.filter { $0.severity > 12 }.map { "\($0.displayName(lang))·\(InjuryKind.severityLabel($0.severity, lang))" }
            if !inj.isEmpty { looks.append(L("伤病：", "injuries: ") + inj.joined(separator: sep)) }
            let seen = engine.visibleBuffs(c.id, viewer: id).filter { !$0.def.display }.map { $0.def.name(lang) }
            if !seen.isEmpty { looks.append(L("状态：", "status: ") + seen.joined(separator: sep)) }
            if c.secretRevealed, let sec = s.character(c.id)?.secret {
                looks.append(L("已被揭开的秘密：\(sec.replacingOccurrences(of: "你", with: "他"))", "secret now known: \(sec)"))
            }
            let tags = (st.leader == c.id ? L("（领头人）", " (leader)") : "") + (c.isNPC ? L("（不参与决策）", " (takes no part in decisions)") : "")
            var line = "  - \(name)\(tags)\(Loc.colon(lang))" + looks.joined(separator: Loc.comma(lang))
            let t = me.trust[c.id] ?? 0
            line += L("；你对他/她：\(trustLabel(t, lang))（\(Int(t))）", "; you \(trustLabel(t, lang)) them (\(Int(t)))")
            out.append(line)
        }

        // Memory
        if !me.diary.isEmpty {
            out.append(L("【你的日记】（你自己写的，是你的长期记忆）", "[Your diary] (written by you — your long-term memory)"))
            for d in me.diary.suffix(6) { out.append("  \(d)") }
        }
        out.append(L("【最近发生的事】（你看到、听到的）", "[Recent events] (what you saw and heard)"))
        let visible = st.log.filter { $0.visible(to: id) && $0.kind != .debug }
        for e in visible.suffix(36) {
            out.append("  " + compactLine(e, engine, viewer: id))
        }
        return out.joined(separator: "\n")
    }

    static func compactLine(_ e: LogEntry, _ engine: GameEngine, viewer: String) -> String {
        let en = engine.lang == .en
        let you = en ? "you" : "你"
        let who = e.actor.map { $0 == viewer ? (en ? "You" : "你") : engine.name($0) } ?? ""
        let r = "[R\(e.round)]"
        func paren(_ s: String?) -> String { s.map { en ? " (\($0))" : "（\($0)）" } ?? "" }
        let colon = Loc.colon(engine.lang)
        switch e.kind {
        case .report: return "\(r) 【\(e.text)】"
        case .situation: return en ? "\(r) Situation: \(e.text)" : "\(r) 局势：\(e.text)"
        case .speech:
            if e.isSilent { return en ? "\(r) \(who) said nothing\(paren(e.detail))" : "\(r) \(who)没说话（\(e.detail ?? "")）" }
            return en ? "\(r) \(who) said: \(e.text)\(paren(e.detail))" : "\(r) \(who)说：\(e.text)\(paren(e.detail))"
        case .vote: return "\(r) ⚖ \(e.text)\(paren(e.detail))"
        case .result: return "\(r) → \(e.text)\(paren(e.detail))"
        case .task: return "\(r) · \(e.text)\(colon)\(e.detail ?? "")"
        case .death: return "\(r) ✝ \(e.text)\(paren(e.detail))"
        case .whisper:
            let to = e.target.map { $0 == viewer ? you : engine.name($0) } ?? ""
            return en ? "\(r) Whisper \(who)→\(to): \(e.text)" : "\(r) 私聊 \(who)→\(to)：\(e.text)"
        case .system: return "\(r) ※ \(e.text)\(paren(e.detail))"
        case .ending: return en ? "\(r) Ending: \(e.text)" : "\(r) 结局：\(e.text)"
        default: return "\(r) \(e.text)"
        }
    }

    public static func taskName(_ engine: GameEngine, _ id: String) -> String {
        switch id {
        case "rest": return engine.L("休息", "Rest")
        case "care": return engine.L("照顾伤员", "Care for the injured")
        case "guard": return engine.L("守夜看物资", "Guard the supplies")
        default: return engine.scenario.task(id)?.name ?? id
        }
    }

    // MARK: Phase prompts

    static func kindExplain(_ ev: ActiveEvent, _ lang: Lang) -> String {
        switch ev.def.kind {
        case "group": return Loc.pick("这是集体表决：少数服从多数，平票时领头人那一票说了算。", "This is a group vote: the majority wins; in a tie, the leader's vote decides.", lang)
        case "individual": return Loc.pick("这件事每个人各自决定，只对你自己生效。", "Everyone decides this for themselves; your choice only affects you.", lang)
        case "nominate": return Loc.pick("要推选一个人，得票最多的人当选（可以推选自己）。", "Choose one person; whoever gets the most votes is chosen (you may pick yourself).", lang)
        case "leader": return Loc.pick("这件事由领头人拍板，其他人可以表态施压。", "The leader makes the call; the others can voice their views and push.", lang)
        case "solo": return Loc.pick("这件事只有你需要做决定。", "Only you have to decide this.", lang)
        default: return ""
        }
    }

    static let letters = ["A", "B", "C", "D", "E", "F"]

    public static func situation(_ engine: GameEngine, _ id: String, stances: [String: SituationDecision]? = nil) -> String {
        guard let ev = engine.state.currentEvent else { return "" }
        let lang = engine.lang
        let L = engine.L
        var out: [String] = [observation(engine, id), ""]
        out.append(L("【现在发生的事】\(ev.text)", "[What is happening now] \(ev.text)"))
        out.append(kindExplain(ev, lang))
        if ev.def.kind == "nominate" {
            out.append(L("可以推选的人（用 ID 回答）：", "People you can choose (answer with the ID): ")
                       + ev.nominees.map { "\($0)=\(engine.name($0))\($0 == id ? L("（你自己）", " (you)") : "")" }.joined(separator: Loc.sep(lang)))
        } else {
            out.append(L("选项：", "Options:"))
            for (i, o) in ev.options.enumerated() where o.available {
                let letter = letters[min(i, letters.count - 1)]
                out.append(L("- \(letter)「\(o.label)」\(o.hint.map { "：\($0)" } ?? "")", "- \(letter) “\(o.label)”\(o.hint.map { ": \($0)" } ?? "")"))
            }
        }
        if let stances {
            out.append("")
            out.append(L("大家的初步表态：", "Where everyone stands so far:"))
            for d in ev.deciders {
                guard let s = stances[d] else { continue }
                let who = d == id ? L("你自己", "You") : engine.name(d)
                let choice = engine.optionLabel(ev, engine.normalizeChoice(ev, s.choice, decider: d))
                let speech = (s.speech ?? "").isEmpty ? L("（没说话）", "(said nothing)") : L("“\(s.speech!)”", "“\(s.speech!)”")
                out.append(L("- \(who)（倾向「\(choice)」）：\(speech)", "- \(who) (leaning “\(choice)”): \(speech)"))
            }
            out.append(L("现在是最终表决。你可以坚持，也可以改主意；可以反驳、拉拢或者讨价还价。", "Now comes the final vote. You can stick to your position or change your mind; argue, win people over or bargain."))
        }
        let choiceHint = ev.def.kind == "nominate" ? L("人物ID", "person ID") : L("选项字母", "option letter")
        out.append("")
        out.append(L("只输出 JSON：{\"thought\":\"你真实的内心想法，别人看不到，40字内\",\"choice\":\"\(choiceHint)\",\"speech\":\"你当众说的话，50字内，可以为空字符串\"}",
                     "Output json only: {\"thought\":\"what you really think, nobody else sees it, under 25 words\",\"choice\":\"\(choiceHint)\",\"speech\":\"what you say out loud, under 30 words, may be an empty string\"}"))
        return out.joined(separator: "\n")
    }

    public static func tasks(_ engine: GameEngine, _ id: String, planned: [String: TaskDecision] = [:], json: Bool = true) -> String {
        let s = engine.scenario
        let st = engine.state
        let lang = engine.lang
        let L = engine.L
        var out: [String] = [observation(engine, id), ""]
        let hours = s.clock.workHours ?? max(2, s.clock.roundHours / 3)
        out.append(L("【分工】接下来大约 \(hours) 个小时，你做什么？", "[Work] What do you do for the next \(hours) hours or so?"))
        let opts = engine.taskOptions(for: id)
        out.append(L("可以做：", "You can:"))
        for o in opts where o.available {
            let place = o.outdoor ? L("，户外", ", outdoors") : L("，室内", ", indoors")
            var line = L("- \(o.id)「\(o.name)」（\(o.exertion.label(lang))\(place)）：\(o.desc)", "- \(o.id) “\(o.name)” (\(o.exertion.label(lang))\(place)): \(o.desc)")
            if o.needsTarget { line += L(" 需要指定对象：", " Needs a target: ") + o.targets.map { "\($0)=\(engine.name($0))" }.joined(separator: Loc.sep(lang)) }
            out.append(line)
        }
        if opts.contains(where: { $0.available && $0.outdoor }) {
            out.append(L("户外的活最好结伴：同一件户外的活有两个人以上一起做，出意外的机会小得多，出了事也有人马上帮忙。",
                         "Don't go outside alone if you can help it: with two or more on the same outdoor job, accidents are much rarer and someone can help at once."))
        }
        let blocked = opts.filter { !$0.available }
        if !blocked.isEmpty {
            out.append(L("现在做不了：", "Not possible right now: ") + blocked.map { L("\($0.name)（\($0.reason ?? "")）", "\($0.name) (\($0.reason ?? ""))") }.joined(separator: Loc.sep(lang)))
        }
        if !planned.isEmpty {
            out.append(L("其他人已经说了要做的事：", "What the others said they'll do: ")
                       + planned.sorted { $0.key < $1.key }.map { "\(engine.name($0.key))→\(taskName(engine, $0.value.task))" }.joined(separator: Loc.semi(lang)))
        }
        let isLeader = st.leader == id
        if isLeader {
            let rd = s.rationDef
            let alive = st.characters.filter { $0.alive }
            let avgK = alive.isEmpty ? 0 : alive.map(\.reportKcal).reduce(0, +) / Double(alive.count)
            let avgW = alive.isEmpty ? 0 : alive.map(\.reportWater).reduce(0, +) / Double(alive.count)
            out.append("")
            out.append(L("你是领头人，还要定下今天的配给（每人每天）：", "You are the leader, so you also set today's rations (per person per day):"))
            out.append(L("  食物可选：", "  Food options: ") + rd.food.map { Fmt.number($0, 0) }.joined(separator: " / ") + L(" 千卡（现在 \(Int(st.policy.food))）", " kcal (now \(Int(st.policy.food)))"))
            out.append(L("  水可选：", "  Water options: ") + rd.water.map { Fmt.number($0, 1) }.joined(separator: " / ") + L(" 升（现在 \(Fmt.number(st.policy.water, 1))）", " L (now \(Fmt.number(st.policy.water, 1)))"))
            if avgK > 0 {
                out.append(L("  参考：上一回合大家平均每人实际消耗约 \(Int(avgK)) 千卡、\(Fmt.number(avgW, 1)) 升水（按一天算）。喝的水少于消耗会慢慢脱水。",
                             "  For reference: last round each person actually used about \(Int(avgK)) kcal and \(Fmt.number(avgW, 1)) L of water (per day). Drinking less than you lose means slowly dehydrating."))
            }
            if let f = s.shelter.fire {
                let label = Loc.inline(f.label ?? L("火", "fire"), lang)
                let res = s.resource(f.resource)
                let have = Fmt.amount(st.resources[f.resource] ?? 0, f.resource, s)
                out.append(L("  晚上点\(label)：true / false（每晚耗 \(Fmt.number(f.perRound, 1)) \(res?.unit ?? "") \(res?.name ?? "")，现有 \(have)）",
                             "  Light the \(label) tonight: true / false (uses \(Fmt.number(f.perRound, 1)) \(res?.unit ?? "") of \(Loc.inline(res?.name ?? "", lang)) per night; you have \(have))"))
            }
            out.append(L("  分配顺序：equal 平均分 / injured 伤病优先 / workers 干重活的优先 / leader 领头人优先",
                         "  Who eats first when there isn't enough: equal = shared equally / injured = the injured first / workers = heavy workers first / leader = the leader first"))
            out.append("")
            if !json { return out.joined(separator: "\n") }
            out.append(L("只输出 JSON：{\"thought\":\"内心想法，40字内\",\"task\":\"任务ID\",\"target\":\"对象ID或null\",\"speech\":\"当众说的话，可为空\",\"policy\":{\"food\":数字,\"water\":数字,\"fire\":true或false,\"priority\":\"equal\"}}",
                         "Output json only: {\"thought\":\"your private thoughts, under 25 words\",\"task\":\"task ID\",\"target\":\"person ID or null\",\"speech\":\"what you say out loud, may be empty\",\"policy\":{\"food\":number,\"water\":number,\"fire\":true or false,\"priority\":\"equal\"}}"))
        } else {
            out.append("")
            if !json { return out.joined(separator: "\n") }
            out.append(L("只输出 JSON：{\"thought\":\"内心想法，40字内\",\"task\":\"任务ID\",\"target\":\"对象ID或null\",\"speech\":\"当众说的话，可为空\"}",
                         "Output json only: {\"thought\":\"your private thoughts, under 25 words\",\"task\":\"task ID\",\"target\":\"person ID or null\",\"speech\":\"what you say out loud, may be empty\"}"))
        }
        return out.joined(separator: "\n")
    }

    public static func night(_ engine: GameEngine, _ id: String, early: Bool = false) -> String {
        let s = engine.scenario
        let st = engine.state
        let lang = engine.lang
        let L = engine.L
        guard let me = st.character(id) else { return "" }
        var out: [String] = early ? [] : [observation(engine, id), ""]
        out.append(early ? L("【今晚】干完活天就黑了。顺便想好今晚私下做什么：", "[Tonight] Once the work is done it will be dark. Decide now what you'll do in private tonight:")
                         : L("【入夜】现在是私下行动的时间。", "[Night] Time for private moves."))
        let others = st.characters.filter { $0.alive && $0.id != id && !$0.isNPC }.map { "\($0.id)=\(engine.name($0.id))" }
        out.append(L("可以私聊或针对的人（用 ID）：", "People you can whisper to or target (by ID): ") + others.joined(separator: Loc.sep(lang)))
        out.append(L("1. 私聊（最多 2 条，只有对方能看到）：拉拢、警告、交易、试探、撒谎都可以。不想说就给空数组。",
                     "1. Whispers (at most 2, only the recipient sees them): win someone over, warn, trade, probe, lie — anything goes. Use an empty array if you have nothing to say."))
        out.append(L("2. 暗中行动（选一个）：", "2. A secret action (pick one):"))
        out.append(L("   - none：什么也不做", "   - none: do nothing"))
        let guards = st.guards.filter { $0 != id }.map { engine.name($0) }
        let guardList = early ? L("要等分工定下来，选了“守夜”的人会守", "not settled until the work is shared out — whoever picks “keep watch” will be on it")
                              : (guards.isEmpty ? L("没有人", "nobody") : guards.joined(separator: Loc.sep(lang)))
        out.append(L("   - steal：趁人不注意偷吃公共食物（约 600 千卡）。今晚守夜的人：\(guardList)。被抓到会很难看，甚至被赶走。",
                     "   - steal: secretly eat from the common food (about 600 kcal). On watch tonight: \(guardList). Getting caught will be ugly — you might even be thrown out."))
        let stashFood = me.stash["food"] ?? 0
        let stashWater = me.stash["water"] ?? 0
        if stashFood > 0 || stashWater > 0 {
            out.append(L("   - stash：偷偷吃喝自己的私藏（还剩食物 \(Int(stashFood)) 千卡、水 \(Fmt.number(stashWater, 1)) 升）",
                         "   - stash: secretly eat and drink from your own stash (left: \(Int(stashFood)) kcal of food, \(Fmt.number(stashWater, 1)) L of water)"))
        }
        if s.character(id)?.secret != nil && !me.secretRevealed {
            out.append(L("   - reveal：主动向大家坦白你的秘密", "   - reveal: confess your secret to everyone"))
        }
        out.append(L("3. 提出动议（明早全体表决，可以不提）：none / elect 重新推选领头人 / punish 惩罚某人（口粮减半三天，需要 target）/ exile 把某人赶出队伍（需要 target）/ search 搜查所有人的私人物品",
                     "3. A motion (everyone votes on it in the morning; optional): none / elect = choose a new leader / punish = punish someone (half rations for three days, needs a target) / exile = throw someone out of the group (needs a target) / search = search everyone's belongings"))
        let around = st.characters.filter { $0.alive && $0.present && $0.id != id }.map { "\($0.id)=\(engine.name($0.id))" }
        out.append(L("4. 挨着谁睡（huddle，可以不选）：冷的夜里两个人挤在一起，能少丢不少体温；对方要是在拉肚子或者生病，你也可能被传上；热的时候挤在一起只会更热。可选（含孩子和动物）：",
                     "4. Who to sleep next to (huddle, optional): on a cold night two people side by side lose much less body heat; if they have diarrhoea or an illness you may catch it; in the heat it only makes things worse. You can choose (children and animals included): ") + around.joined(separator: Loc.sep(lang)))
        out.append(L("5. 分东西给谁（gift，可以不给）：from=ration 把你今天的一部分口粮和水分给对方（portion 0.25～1，大家都看得见）；from=stash 把你私藏的吃的喝的悄悄给对方（只有你们俩知道）。",
                     "5. Give someone food and water (gift, optional): from=ration hands them part of your own share today (portion 0.25–1; everyone sees it); from=stash quietly gives them some of what you've hidden (only the two of you know)."))
        out.append(L("6. 写日记：一两句话，记下你想记住的事、对别人的判断和你的打算。这是你唯一的长期记忆。",
                     "6. A diary entry: a sentence or two about what you want to remember, what you think of the others and what you plan. This is your only long-term memory."))
        out.append("")
        if early { return out.joined(separator: "\n") }
        out.append(L("只输出 JSON：{\"thought\":\"内心想法，40字内\",\"whispers\":[{\"to\":\"人物ID\",\"text\":\"私聊内容\"}],\"secret\":\"none\",\"motion\":{\"type\":\"none\",\"target\":null},\"huddle\":null,\"gift\":null,\"diary\":\"日记\"}",
                     "Output json only: {\"thought\":\"your private thoughts, under 25 words\",\"whispers\":[{\"to\":\"person ID\",\"text\":\"what you whisper\"}],\"secret\":\"none\",\"motion\":{\"type\":\"none\",\"target\":null},\"huddle\":null,\"gift\":null,\"diary\":\"diary entry\"}"))
        return out.joined(separator: "\n")
    }

    /// Fast pace: the day's work and tonight's private moves in one call (D-046).
    public static func dayAndNight(_ engine: GameEngine, _ id: String, planned: [String: TaskDecision] = [:]) -> String {
        let L = engine.L
        let leader = engine.state.leader == id
        let policy = leader ? L(",\"policy\":{\"food\":数字,\"water\":数字,\"fire\":true或false,\"priority\":\"equal\"}", ",\"policy\":{\"food\":number,\"water\":number,\"fire\":true or false,\"priority\":\"equal\"}") : ""
        return tasks(engine, id, planned: planned, json: false) + "\n" + night(engine, id, early: true) + "\n"
            + L("只输出 JSON：{\"thought\":\"内心想法，40字内\",\"task\":\"任务ID\",\"target\":\"对象ID或null\",\"speech\":\"当众说的话，可为空\"\(policy),\"whispers\":[{\"to\":\"人物ID\",\"text\":\"私聊内容\"}],\"secret\":\"none\",\"motion\":{\"type\":\"none\",\"target\":null},\"huddle\":null,\"gift\":null,\"diary\":\"日记\"}",
                "Output json only: {\"thought\":\"your private thoughts, under 25 words\",\"task\":\"task ID\",\"target\":\"person ID or null\",\"speech\":\"what you say out loud, may be empty\"\(policy),\"whispers\":[{\"to\":\"person ID\",\"text\":\"what you whisper\"}],\"secret\":\"none\",\"motion\":{\"type\":\"none\",\"target\":null},\"huddle\":null,\"gift\":null,\"diary\":\"diary entry\"}")
    }

    // MARK: Parsing

    public static func parseSituation(_ obj: [String: Any]) -> SituationDecision? {
        guard let choice = JSONExtract.string(obj, "choice", "选择", "option") else { return nil }
        return SituationDecision(choice: choice, speech: JSONExtract.string(obj, "speech", "发言", "say"), thought: JSONExtract.string(obj, "thought", "内心", "think"))
    }

    public static func parseTask(_ obj: [String: Any]) -> TaskDecision? {
        guard let task = JSONExtract.string(obj, "task", "任务") else { return nil }
        var target = JSONExtract.string(obj, "target", "对象")
        if let t = target, t.isEmpty || t == "null" || t == "无" || t.lowercased() == "none" { target = nil }
        var policy: Policy?
        if let p = obj["policy"] as? [String: Any] {
            let food = (p["food"] as? NSNumber)?.doubleValue ?? Double((p["food"] as? String) ?? "") ?? -1
            let water = (p["water"] as? NSNumber)?.doubleValue ?? Double((p["water"] as? String) ?? "") ?? -1
            var fire = false
            if let b = p["fire"] as? Bool { fire = b } else if let sx = p["fire"] as? String { fire = ["true", "是", "yes", "1"].contains(sx.lowercased()) } else if let n = p["fire"] as? NSNumber { fire = n.intValue != 0 }
            let pr = (p["priority"] as? String) ?? "equal"
            if food >= 0 && water >= 0 { policy = Policy(food: food, water: water, fire: fire, priority: pr) }
        }
        return TaskDecision(task: task, target: target, speech: JSONExtract.string(obj, "speech", "发言"), thought: JSONExtract.string(obj, "thought", "内心"), policy: policy)
    }

    public static func parseNight(_ obj: [String: Any]) -> NightDecision {
        var d = NightDecision()
        if let ws = obj["whispers"] as? [[String: Any]] {
            for w in ws.prefix(2) {
                if let to = JSONExtract.string(w, "to", "对象"), let text = JSONExtract.string(w, "text", "内容"), !text.isEmpty {
                    d.whispers.append(Whisper(to: to, text: text))
                }
            }
        }
        let secret = (JSONExtract.string(obj, "secret", "暗中行动") ?? "none").lowercased()
        d.secret = ["steal", "stash", "reveal"].contains(secret) ? secret : "none"
        if let m = obj["motion"] as? [String: Any] {
            let type = (JSONExtract.string(m, "type") ?? "none").lowercased()
            let target = JSONExtract.string(m, "target")
            if let mt = MotionType(rawValue: type), mt != .thief {
                d.motion = Motion(type: mt, target: (target == "null" || target == "") ? nil : target)
            }
        } else if let ms = obj["motion"] as? String {
            let parts = ms.split(separator: ":").map(String.init)
            if let mt = MotionType(rawValue: parts.first?.lowercased() ?? ""), mt != .thief {
                d.motion = Motion(type: mt, target: parts.count > 1 ? parts[1] : nil)
            }
        }
        d.diary = JSONExtract.string(obj, "diary", "日记")
        d.thought = JSONExtract.string(obj, "thought", "内心")
        let none: Set<String> = ["", "null", "none", "无", "不", "nobody"]
        if let h = JSONExtract.string(obj, "huddle", "挨着谁睡"), !none.contains(h.lowercased()) { d.huddle = h }
        if let g = obj["gift"] as? [String: Any], let to = JSONExtract.string(g, "to", "对象"), !none.contains(to.lowercased()) {
            let from = (JSONExtract.string(g, "from", "来源") ?? "ration").lowercased() == "stash" ? "stash" : "ration"
            let portion = (g["portion"] as? NSNumber)?.doubleValue ?? Double((g["portion"] as? String) ?? "")
            d.gift = Gift(to: to, from: from, portion: portion)
        }
        return d
    }
}
