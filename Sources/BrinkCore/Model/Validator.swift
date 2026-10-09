import Foundation

/// Static checks for a scenario: references, expressions, selectors, templates.
public struct ScenarioValidator {
    public let s: Scenario
    public private(set) var errors: [String] = []
    public private(set) var warnings: [String] = []

    var flagsSet: Set<String> = ["theft_caught", "theft_suspected"]
    var flagsRead: [(String, String)] = []
    var scheduledEvents: Set<String> = []

    public init(_ s: Scenario) { self.s = s }

    static let selectors: Set<String> = [
        "actor", "self", "target", "protagonist", "all", "everyone", "players", "npcs", "others",
        "random", "randomPlayer", "randomOther", "leader", "weakest", "strongest", "injured",
        "voters", "opponents", "away", "none"
    ]
    static let singleIdents: Set<String> = [
        "round", "day", "hour", "hours", "alive", "present", "participants", "dead", "exiled", "away",
        "guards", "hasLeader", "temp", "high", "low", "wind", "visibility", "precip", "sun", "shelter",
        "fire", "fireLit", "avgMorale", "avgHealth", "minHealth", "injuredCount", "foodDays", "waterDays",
        "stolen", "rationFood", "rationWater", "altitude", "rescued", "hardness", "true", "false"
    ]
    static let charFields: Set<String> = [
        "alive", "present", "away", "dead", "exiled", "joined", "health", "morale", "fatigue", "core", "thirst",
        "hunger", "fat", "clo", "wet", "injured", "infected", "injury", "skill", "item", "stash", "revealed",
        "leader", "npc", "age", "female", "tag", "trust", "trusted", "led", "thefts", "caught", "efficiency",
        "mobile", "canHeavy", "task", "deathRound", "is", "rescued", "thirstL", "weight", "gone", "goal", "animal", "buff", "maxHealth"
    ]
    static let stats: Set<String> = ["health", "morale", "fatigue", "core", "thirst", "energy", "fat", "clo", "wet"]
    static let eventKinds: Set<String> = ["group", "individual", "nominate", "leader", "solo"]

    public mutating func validate() -> Bool {
        errors = []
        warnings = []
        checkBasics()
        collectFlagsAndSchedules()
        checkCharacters()
        checkTasks()
        checkEvents()
        checkEndings()
        checkMisc()
        for (flag, whereRead) in flagsRead where !flagsSet.contains(flag) && !flag.hasPrefix("revealed_") && !flag.hasPrefix("stash_found_") {
            warnings.append("flag.\(flag) 被读取（\(whereRead)）但从未被设置")
        }
        for e in s.events where (e.weight ?? 0) <= 0 && e.atRound == nil && !scheduledEvents.contains(e.id) {
            warnings.append("事件 \(e.id) 既没有 weight、atRound，也没有被 schedule，永远不会触发")
        }
        return errors.isEmpty
    }

    // MARK: Basics

    mutating func checkBasics() {
        if s.id.isEmpty || s.id.contains(" ") { errors.append("id 不能为空或含空格") }
        if s.characters.count < 3 || s.characters.count > 6 { errors.append("characters 应为 3~6 人（建议 5 人），当前 \(s.characters.count)") }
        for r in s.rescues ?? [] where s.event(r) == nil { errors.append("rescues 里的事件 '\(r)' 不存在") }
        if (s.hardship ?? 1) < 0 || (s.hardship ?? 1) > 5 { errors.append("hardship 应在 0~5 之间") }
        if s.climate.weather[s.climate.initialWeather] == nil { errors.append("climate.initialWeather '\(s.climate.initialWeather)' 不存在") }
        for (wid, w) in s.climate.weather {
            if w.next.isEmpty { errors.append("weather.\(wid).next 不能为空") }
            for k in w.next.keys where s.climate.weather[k] == nil { errors.append("weather.\(wid).next 引用了不存在的天气 '\(k)'") }
        }
        if let f = s.shelter.fire, s.resource(f.resource) == nil { errors.append("shelter.fire.resource '\(f.resource)' 不是资源") }
        let rd = s.rationDef
        if rd.food.isEmpty || rd.water.isEmpty { errors.append("rations.food / rations.water 不能为空") }
        if rd.defaultFood >= rd.food.count || rd.defaultWater >= rd.water.count { errors.append("rations.default* 越界") }
        if s.resource("food") == nil { errors.append("必须有 id 为 food 的资源（单位：千卡）") }
        if s.resource("water") == nil { errors.append("必须有 id 为 water 的资源（单位：升）") }
        dupCheck(s.resources.map(\.id), "resources")
        dupCheck((s.vars ?? []).map(\.id), "vars")
        dupCheck(s.allCharacters.map(\.id), "characters/npcs")
        dupCheck(s.tasks.map(\.id), "tasks")
        dupCheck(s.events.map(\.id), "events")
        dupCheck(s.endings.map(\.id), "endings")
        dupCheck((s.projects ?? []).map(\.id), "projects")
        for t in s.tasks where ["rest", "care", "guard"].contains(t.id) {
            errors.append("task id '\(t.id)' 与内置任务重名")
        }
        if s.endings.first(where: { $0.id == s.defaultEnding }) == nil { errors.append("defaultEnding '\(s.defaultEnding)' 不在 endings 里") }
        if s.endings.first(where: { $0.id == s.wipeEnding }) == nil { errors.append("wipeEnding '\(s.wipeEnding)' 不在 endings 里") }
        if s.clock.roundHours <= 0 {
            errors.append("clock.roundHours=\(s.clock.roundHours) 必须大于 0（一回合的小时数）")
        } else if 24 % s.clock.roundHours != 0 && s.clock.roundHours % 24 != 0 {
            warnings.append("clock.roundHours=\(s.clock.roundHours) 不能整除 24，昼夜标签可能奇怪")
        }
        if s.clock.maxRounds < 1 { errors.append("clock.maxRounds 必须至少为 1") }
        if let wh = s.clock.workHours, wh < 0 { errors.append("clock.workHours 不能为负") }
        if let ws = s.clock.workStart {
            if ws.hours.isEmpty { errors.append("clock.workStart 不能是空列表") }
            for h in ws.hours where h < 0 || h > 23 { errors.append("clock.workStart 的钟点 \(h) 应在 0~23") }
        }
        if s.briefing.isEmpty { errors.append("briefing 不能为空") }
    }

    mutating func dupCheck(_ ids: [String], _ what: String) {
        var seen: Set<String> = []
        for id in ids {
            if seen.contains(id) { errors.append("\(what) 中 id 重复：\(id)") }
            seen.insert(id)
        }
    }

    // MARK: Flags / schedules (pre-pass)

    mutating func collectFlagsAndSchedules() {
        func walk(_ effects: [Effect]?) {
            for e in effects ?? [] {
                if e.e == "flag", let id = e.id, e.on ?? true { flagsSet.insert(id) }
                if e.e == "schedule", let ev = e.event { scheduledEvents.insert(ev) }
                walk(e.then); walk(e.else); walk(e.do); walk(e.onReturn)
            }
        }
        walk(s.onStart)
        walk(s.rules)
        for c in s.allCharacters { walk(c.secretReveal) }
        for t in s.tasks { walk(t.effects) }
        for p in s.projects ?? [] { walk(p.onComplete) }
        for (_, pool) in s.pools ?? [:] { for it in pool.items { walk(it.effects) } }
        for ev in s.events {
            walk(ev.pre); walk(ev.effects)
            for o in ev.options ?? [] { walk(o.effects) }
        }
    }

    // MARK: Characters

    mutating func checkCharacters() {
        let ids = Set(s.allCharacters.map(\.id))
        for c in s.allCharacters {
            let w = "角色 \(c.id)"
            for k in c.skills.keys where !Skill.all.contains(k) { errors.append("\(w) 技能名无效：\(k)（可用：\(Skill.all.joined(separator: ","))）") }
            for v in c.skills.values where v < 0 || v > 3 { errors.append("\(w) 技能值应为 0~3") }
            if c.fat <= 0.02 || c.fat > 0.6 { errors.append("\(w) fat 是体脂比例（0.05~0.45）") }
            if c.weight < 15 || c.weight > 160 { errors.append("\(w) weight 单位是 kg") }
            if c.clo < 0 || c.clo > 5 { errors.append("\(w) clo 应在 0~5") }
            for inj in c.injuries ?? [] where InjuryKind.table[inj.kind] == nil { errors.append("\(w) 伤病类型无效：\(inj.kind)") }
            for k in (c.relations ?? [:]).keys where !ids.contains(k) { errors.append("\(w) relations 引用了不存在的角色 \(k)") }
            for k in (c.items ?? [:]).keys where k.isEmpty { errors.append("\(w) items 有空 id") }
            for k in (c.stash ?? [:]).keys where !["food", "water"].contains(k) { warnings.append("\(w) stash 只有 food/water 会被“吃私藏”使用：\(k)") }
            if let g = c.goal {
                expr(g.check, "\(w).goal.check")
                if g.check.contains("goal") { errors.append("\(w).goal.check 不能引用 goal 字段（会递归）") }
            }
            for (i, e) in (c.epilogues ?? []).enumerated() {
                expr(e.when, "\(w).epilogues[\(i)].when")
                templ(e.text, "\(w).epilogues[\(i)].text")
            }
            for (i, l) in (c.lines ?? []).enumerated() {
                templ(l, "\(w).lines[\(i)]")
                if l.isEmpty { errors.append("\(w).lines[\(i)] 是空字符串") }
            }
            if let t = c.autoTask, s.task(t) == nil && !["rest", "guard"].contains(t) {
                errors.append("\(w).autoTask '\(t)' 不是任务 id（NPC 只能做不需要指定对象的任务）")
            }
            if let t = c.autoTask, let td = s.task(t), (td.target ?? "none") != "none" {
                errors.append("\(w).autoTask '\(t)' 需要指定对象，NPC 不能自动做")
            }
            effects(c.secretReveal, "\(w).secretReveal")
            if !(s.npcs ?? []).contains(where: { $0.id == c.id }) {
                if c.secret == nil { warnings.append("\(w) 没有 secret（建议每个玩家角色都有秘密）") }
                if c.goal == nil { warnings.append("\(w) 没有 goal") }
                if c.autoTask != nil || c.lines != nil { warnings.append("\(w) 是玩家角色，autoTask / lines 只对 NPC 生效") }
            }
            if (c.epilogues ?? []).isEmpty { warnings.append("\(w) 没有 epilogues（结局后的个人尾声）") }
        }
    }

    // MARK: Tasks

    mutating func checkTasks() {
        if s.tasks.count < 3 { warnings.append("tasks 少于 3 个，分工阶段会很单调") }
        for t in s.tasks {
            let w = "任务 \(t.id)"
            if Exertion(rawValue: t.exertion) == nil { errors.append("\(w) exertion 只能是 rest/light/heavy") }
            if let tg = t.target, !["none", "other", "any"].contains(tg) { errors.append("\(w) target 只能是 none/other/any") }
            if let c = t.when { expr(c, "\(w).when") }
            templ(t.desc, "\(w).desc")
            effects(t.effects, w)
        }
        for b in s.builtinTasks ?? [] where !["rest", "care", "guard"].contains(b) {
            errors.append("builtinTasks 只能包含 rest/care/guard")
        }
    }

    // MARK: Events

    mutating func checkEvents() {
        for ev in s.events {
            let w = "事件 \(ev.id)"
            if !Self.eventKinds.contains(ev.kind) { errors.append("\(w) kind 无效：\(ev.kind)") }
            templ(ev.text, "\(w).text")
            if let c = ev.when { expr(c, "\(w).when") }
            if let c = ev.whoWhen { expr(c, "\(w).whoWhen") }
            if let who = ev.who { selector(who, "\(w).who") }
            effects(ev.pre, "\(w).pre")
            if ev.kind == "nominate" {
                if ev.effects == nil && ev.result == nil { errors.append("\(w) nominate 需要 effects 或 result") }
                effects(ev.effects, "\(w).effects")
                if let r = ev.result { templ(r, "\(w).result") }
            } else {
                let opts = ev.options ?? []
                if opts.count < 2 { errors.append("\(w) 至少需要 2 个选项") }
                if opts.count > 5 { warnings.append("\(w) 选项超过 5 个") }
                dupCheck(opts.map(\.id), "\(w).options")
                for o in opts {
                    templ(o.label, "\(w).\(o.id).label")
                    if let h = o.hint { templ(h, "\(w).\(o.id).hint") }
                    if let r = o.result { templ(r, "\(w).\(o.id).result") }
                    if let c = o.when { expr(c, "\(w).\(o.id).when") }
                    effects(o.effects, "\(w).\(o.id)")
                    if (o.when == nil) == false { /* ok */ }
                }
                if !opts.contains(where: { $0.when == nil }) {
                    warnings.append("\(w) 所有选项都有 when 条件，可能出现无选项可选（事件会被跳过）")
                }
            }
            if ev.kind == "solo" && ev.who == nil && ev.whoWhen == nil {
                // random protagonist — fine
            }
            if let at = ev.atRound, at > s.clock.maxRounds { warnings.append("\(w) atRound 超过 maxRounds") }
        }
        if s.events.filter({ ($0.weight ?? 0) > 0 }).count < 6 {
            warnings.append("随机事件（weight>0）少于 6 个，重玩性会差")
        }
    }

    mutating func checkEndings() {
        for e in s.endings {
            if let c = e.when { expr(c, "结局 \(e.id).when") }
            templ(e.text, "结局 \(e.id).text")
            if let t = e.tone, !["good", "bitter", "bad"].contains(t) { errors.append("结局 \(e.id) tone 只能是 good/bitter/bad") }
        }
    }

    mutating func checkMisc() {
        if let t = s.exileText { templ(t, "exileText") }
        effects(s.onStart, "onStart")
        effects(s.rules, "rules")
        for p in s.projects ?? [] {
            if let c = p.when { expr(c, "项目 \(p.id).when") }
            effects(p.onComplete, "项目 \(p.id).onComplete")
            if p.work <= 0 { errors.append("项目 \(p.id) work 必须 > 0") }
        }
        for (pid, pool) in s.pools ?? [:] {
            if pool.items.isEmpty { errors.append("pool \(pid) 没有 items") }
            for (i, it) in pool.items.enumerated() {
                if let r = it.res, s.resource(r) == nil { errors.append("pool \(pid)[\(i)] res '\(r)' 不存在") }
                if let a = it.amount, a.count != 2 || a[0] > a[1] { errors.append("pool \(pid)[\(i)] amount 应为 [min,max]") }
                effects(it.effects, "pool \(pid)[\(i)]")
            }
        }
        for v in s.vars ?? [] {
            if let f = v.format, !["level", "percent", "number"].contains(f) { errors.append("var \(v.id) format 只能是 level/percent/number") }
        }
    }

    // MARK: Effects

    mutating func effects(_ list: [Effect]?, _ w: String) {
        for (i, e) in (list ?? []).enumerated() {
            effect(e, "\(w)[\(i)]")
        }
    }

    mutating func effect(_ e: Effect, _ w: String) {
        guard Effect.knownTypes.contains(e.e) else {
            errors.append("\(w) 未知效果类型 '\(e.e)'")
            return
        }
        let w = "\(w)(\(e.e))"
        func need(_ cond: Bool, _ field: String) {
            if !cond { errors.append("\(w) 缺少字段 \(field)") }
        }
        for n in [e.add, e.set, e.severity, e.amount, e.p, e.dc, e.in, e.rolls, e.base, e.rounds, e.hours] {
            if let x = n?.expression { expr(x, w) }
        }
        if let c = e.when { expr(c, w) }
        if let who = e.who, e.e != "leader" || who != "none" { selector(who, "\(w).who") }
        if let f = e.from { selector(f, "\(w).from") }
        switch e.e {
        case "res":
            need(e.id != nil, "id")
            if let id = e.id, s.resource(id) == nil { errors.append("\(w) 资源 '\(id)' 不存在") }
            need(e.add != nil || e.set != nil, "add 或 set")
        case "var":
            need(e.id != nil, "id")
            if let id = e.id, s.variable(id) == nil { errors.append("\(w) 变量 '\(id)' 不存在") }
            need(e.add != nil || e.set != nil, "add 或 set")
        case "flag":
            need(e.id != nil, "id")
        case "stat":
            need(e.stat != nil, "stat")
            if let st = e.stat, !Self.stats.contains(st) { errors.append("\(w) stat 无效：\(st)（可用：\(Self.stats.sorted().joined(separator: ","))）") }
            need(e.add != nil || e.set != nil, "add 或 set")
        case "injure":
            need(e.kind != nil, "kind")
            if let k = e.kind, InjuryKind.table[k] == nil { errors.append("\(w) 伤病类型无效：\(k)（可用：\(InjuryKind.table.keys.sorted().joined(separator: ","))）") }
            need(e.severity != nil, "severity")
        case "heal":
            if let k = e.kind, k != "any", k != "all", InjuryKind.table[k] == nil { errors.append("\(w) kind 无效：\(k)") }
        case "trust":
            need(e.add != nil, "add")
            if let t = e.to { selector(t, "\(w).to") }
        case "log", "say":
            need(e.text != nil, "text")
            if let t = e.text { templ(t, w) }
            if let v = e.vis, !["public", "god", "actor", "target"].contains(v) { errors.append("\(w) vis 只能是 public/god/actor/target") }
        case "chance":
            need(e.p != nil, "p")
            effects(e.then, "\(w).then"); effects(e.else, "\(w).else")
        case "check":
            need(e.skill != nil, "skill")
            if let sk = e.skill, !Skill.all.contains(sk) { errors.append("\(w) 技能无效：\(sk)") }
            effects(e.then, "\(w).then"); effects(e.else, "\(w).else")
        case "if":
            need(e.when != nil, "when")
            effects(e.then, "\(w).then"); effects(e.else, "\(w).else")
        case "each":
            need(e.do != nil, "do")
            effects(e.do, "\(w).do")
        case "schedule":
            need(e.event != nil, "event")
            if let ev = e.event, s.event(ev) == nil { errors.append("\(w) 事件 '\(ev)' 不存在") }
        case "loot":
            need(e.pool != nil, "pool")
            if let p = e.pool, s.pools?[p] == nil { errors.append("\(w) pool '\(p)' 不存在") }
        case "yield":
            need(e.id != nil, "id")
            if let id = e.id, s.resource(id) == nil { errors.append("\(w) 资源 '\(id)' 不存在") }
            if let sk = e.skill, !Skill.all.contains(sk) { errors.append("\(w) 技能无效：\(sk)") }
            for k in (e.weather ?? [:]).keys where s.climate.weather[k] == nil { errors.append("\(w) weather 键 '\(k)' 不存在") }
        case "work":
            need(e.project != nil, "project")
            if let p = e.project, s.project(p) == nil { errors.append("\(w) 项目 '\(p)' 不存在") }
            if let sk = e.skill, !Skill.all.contains(sk) { errors.append("\(w) 技能无效：\(sk)") }
        case "shelter":
            need(e.add != nil, "add")
        case "item":
            need(e.id != nil, "id")
        case "away":
            // optional: exertion (rest/light/heavy, default light) and hours on the move per day (0–24, default 6)
            need(e.rounds != nil, "rounds")
            if let x = e.exertion, Exertion(rawValue: x) == nil { errors.append("\(w) exertion 只能是 rest/light/heavy") }
            if case .const(let h)? = e.hours, h < 0 || h > 24 { errors.append("\(w) hours 是每天在路上的小时数，应在 0~24") }
            effects(e.onReturn, "\(w).onReturn")
        case "end":
            need(e.ending != nil, "ending")
            if let en = e.ending, en != "auto", s.endings.first(where: { $0.id == en }) == nil { errors.append("\(w) 结局 '\(en)' 不存在") }
        case "weather":
            need(e.to != nil, "to")
            if let t = e.to, s.climate.weather[t] == nil { errors.append("\(w) 天气 '\(t)' 不存在") }
        case "buff":
            need(e.id != nil, "id")
            if let id = e.id, !Buffs.timedIds.contains(id) {
                errors.append("\(w) 状态 '\(id)' 不存在或不能由事件添加（可用：\(Buffs.timedIds.joined(separator: " "))）")
            }
        case "join":
            need(e.id != nil, "id")
            if let id = e.id, s.character(id) == nil { errors.append("\(w) 角色 '\(id)' 不存在") }
            if let id = e.id, s.character(id)?.joinsLater != true { warnings.append("\(w) 角色 '\(id)' 没有 joinsLater: true") }
        default:
            break
        }
    }

    mutating func selector(_ sel: String, _ w: String) {
        if Self.selectors.contains(sel) { return }
        if sel.hasPrefix("best:"), Skill.all.contains(String(sel.dropFirst(5))) { return }
        if s.character(sel) != nil { return }
        errors.append("\(w) 选择器无效：'\(sel)'")
    }

    // MARK: Expressions

    mutating func expr(_ source: String, _ w: String) {
        let node: ExprNode
        do {
            node = try Expr.parse(source)
        } catch {
            errors.append("\(w) 表达式错误：\(error)")
            return
        }
        for id in Expr.identifiers(in: node) {
            if let problem = checkIdent(id, w) { errors.append("\(w) 表达式 `\(source)`：\(problem)") }
        }
    }

    mutating func checkIdent(_ id: String, _ w: String) -> String? {
        let parts = id.split(separator: ".").map(String.init)
        guard let head = parts.first else { return "空标识符" }
        if parts.count == 1 {
            return Self.singleIdents.contains(head) ? nil : "未知变量 '\(id)'"
        }
        let rest = Array(parts.dropFirst())
        switch head {
        case "res": return s.resource(rest.joined(separator: ".")) == nil ? "资源 '\(rest.joined(separator: "."))' 不存在" : nil
        case "var": return s.variable(rest.joined(separator: ".")) == nil ? "变量 '\(rest.joined(separator: "."))' 不存在" : nil
        case "flag":
            flagsRead.append((rest.joined(separator: "."), w))
            return nil
        case "weather": return s.climate.weather[rest[0]] == nil ? "天气 '\(rest[0])' 不存在" : nil
        case "project", "done": return s.project(rest[0]) == nil ? "项目 '\(rest[0])' 不存在" : nil
        case "fired": return s.event(rest[0]) == nil ? "事件 '\(rest[0])' 不存在" : nil
        case "actor", "target", "self", "protagonist":
            return Self.charFields.contains(rest[0]) ? skillCheck(rest) : "角色字段 '\(rest[0])' 无效"
        case "leader":
            if rest.count == 1, s.character(rest[0]) != nil { return nil }
            return Self.charFields.contains(rest[0]) ? skillCheck(rest) : "leader 字段 '\(rest[0])' 无效"
        case "trust":
            guard rest.count >= 2 else { return "trust 需要 trust.a.b" }
            for x in rest.prefix(2) where x != "actor" && x != "leader" && s.character(x) == nil { return "trust 引用了不存在的角色 \(x)" }
            return nil
        case "voters": return nil
        default:
            if Self.charFields.contains(head), s.character(rest[0]) != nil {
                return skillCheck([head] + Array(rest.dropFirst()))
            }
            if s.character(head) != nil, Self.charFields.contains(rest[0]) {
                return skillCheck(rest)
            }
            return "未知标识符 '\(id)'"
        }
    }

    func skillCheck(_ path: [String]) -> String? {
        if path.first == "skill" {
            guard path.count > 1, Skill.all.contains(path[1]) else { return "skill 后面要接技能名（\(Skill.all.joined(separator: ","))）" }
        }
        if path.first == "is" {
            guard path.count > 1, s.character(path[1]) != nil else { return "is 后面要接角色 id，例如 actor.is.zhou" }
        }
        if path.first == "task" {
            guard path.count > 1, s.task(path[1]) != nil || ["rest", "care", "guard"].contains(path[1]) else { return "task 后面要接任务 id" }
        }
        return nil
    }

    // MARK: Templates

    mutating func templ(_ t: String, _ w: String) {
        var i = t.startIndex
        while i < t.endIndex {
            if t[i] == "{", let close = t[i...].firstIndex(of: "}") {
                let key = String(t[t.index(after: i)..<close])
                if !templateKeyOK(key) { errors.append("\(w) 文本占位符无效：{\(key)}") }
                i = t.index(after: close)
            } else {
                i = t.index(after: i)
            }
        }
    }

    mutating func templateKeyOK(_ key: String) -> Bool {
        let simple: Set<String> = ["actor", "self", "target", "protagonist", "leader", "day", "round", "temp", "low", "high", "weather", "shelter", "survivors", "dead", "aliveCount", "voters"]
        if simple.contains(key) { return true }
        let parts = key.split(separator: ".").map(String.init)
        if parts.count == 2, ScenarioText.pronounForms.contains(parts[1]) {
            return ["actor", "self", "target", "protagonist", "leader"].contains(parts[0])
        }
        if parts.count == 3, parts[0] == "name", ScenarioText.pronounForms.contains(parts[2]) {
            return s.character(parts[1]) != nil
        }
        if parts.count == 2 {
            switch parts[0] {
            case "name": return s.character(parts[1]) != nil
            case "res": return s.resource(parts[1]) != nil
            case "var": return s.variable(parts[1]) != nil
            default: break
            }
        }
        return checkIdent(key, "template") == nil
    }
}
