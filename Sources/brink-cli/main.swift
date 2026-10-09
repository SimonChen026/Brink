import Foundation
import BrinkCore

// brink-cli — headless tools for 绝境 (Brink)
//
//   brink-cli validate [file.json ...]       validate scenarios (default: all built-in)
//   brink-cli sim <file.json|id> [--runs N] [--seed S]
//                                            run N rule-bot games, print balance stats
//   brink-cli play <file.json|id> [--seed S] [--public]
//                                            print one full rule-bot game transcript
//   brink-cli llm-test <baseURL> <model> <apiKeyEnvVar> [--anthropic]
//                                            one round-trip to an LLM provider

setvbuf(stdout, nil, _IOLBF, 0)

var args = Array(CommandLine.arguments.dropFirst())

func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let v = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return v
}

func flag(_ name: String) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i)
    return true
}

func loadScenario(_ ref: String) -> Scenario {
    let url = URL(fileURLWithPath: ref)
    if FileManager.default.fileExists(atPath: url.path) {
        do { return try ScenarioLibrary.load(url) } catch {
            print("❌ \(error)")
            exit(1)
        }
    }
    let (all, errors) = ScenarioLibrary.loadAll()
    if let s = all.first(where: { $0.id == ref }) { return s }
    print("❌ 找不到场景 \(ref)")
    for e in errors { print("   \(e)") }
    exit(1)
}

func validate(_ s: Scenario, file: String) -> Bool {
    var v = ScenarioValidator(s)
    let ok = v.validate()
    print("\(ok ? "✅" : "❌") \(file)  [\(s.id) · \(s.title)]  角色\(s.characters.count) 任务\(s.tasks.count) 事件\(s.events.count) 结局\(s.endings.count)")
    for e in v.errors { print("   错误：\(e)") }
    for w in v.warnings { print("   提醒：\(w)") }
    // Smoke test: a few rule-bot games must finish without hanging.
    if ok {
        for seed in UInt64(1)...UInt64(3) {
            let engine = GameEngine(scenario: s, setup: GameSetup(scenarioId: s.id, seed: seed, controllers: [:]))
            AutoRunner.playToEnd(engine)
            if !engine.isOver {
                print("   错误：模拟 seed=\(seed) 在 2000 步内没有结束")
                return false
            }
        }
    }
    return ok
}

let command = args.first ?? "help"
if !args.isEmpty { args.removeFirst() }

// Commands that run whole sessions write logs, the leaderboard and the endings gallery. Unless asked
// otherwise (--keep-data), keep them away from the real app data folder.
if ["llm-play", "llm-endless", "llm-exam"].contains(command) && !flag("--keep-data") && ProcessInfo.processInfo.environment["BRINK_HOME"] == nil {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("brink-cli-\(ProcessInfo.processInfo.processIdentifier)")
    setenv("BRINK_HOME", tmp.path, 1)
    print("（数据目录：\(tmp.path)；加 --keep-data 写进应用的数据目录）")
}

switch command {
case "validate":
    var allOK = true
    if args.isEmpty {
        guard let dir = ScenarioLibrary.builtInDirectory(),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            print("找不到内置场景目录")
            exit(1)
        }
        for f in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where f.pathExtension == "json" {
            do {
                let s = try ScenarioLibrary.load(f)
                allOK = validate(s, file: f.lastPathComponent) && allOK
            } catch {
                print("❌ \(error)")
                allOK = false
            }
        }
    } else {
        for path in args {
            do {
                let s = try ScenarioLibrary.load(URL(fileURLWithPath: path))
                allOK = validate(s, file: path) && allOK
            } catch {
                print("❌ \(error)")
                allOK = false
            }
        }
    }
    exit(allOK ? 0 : 1)

case "sim":
    let runs = Int(option("--runs") ?? "200") ?? 200
    let seed0 = UInt64(option("--seed") ?? "1000") ?? 1000
    guard let ref = args.first else { print("用法: brink-cli sim <file|id> [--runs N]"); exit(1) }
    let s = loadScenario(ref)
    var endings: [String: Int] = [:]
    var survive: [String: Int] = [:]
    var goals: [String: Int] = [:]
    var causes: [String: Int] = [:]
    var rounds = 0
    var survivorsTotal = 0
    var thefts = 0, caught = 0, exiles = 0, leaders: [String: Int] = [:]
    var eventsFired: [String: Int] = [:]
    var anySurvivor = 0
    var npcSurvive: [String: Int] = [:]
    var epiloguesSeen: [String: Set<String>] = [:]
    let level = option("--difficulty").flatMap(Difficulty.init(rawValue:))
    for i in 0..<runs {
        var setup = GameSetup(scenarioId: s.id, seed: seed0 + UInt64(i), controllers: [:])
        setup.difficulty = level
        let engine = GameEngine(scenario: s, setup: setup)
        AutoRunner.playToEnd(engine)
        guard let end = engine.state.ending else { continue }
        endings[end.title, default: 0] += 1
        rounds += end.round
        for r in end.results {
            if r.survived { survive[r.name, default: 0] += 1 }
            if r.goalAchieved { goals[r.name, default: 0] += 1 }
        }
        if end.results.contains(where: { $0.survived }) { anySurvivor += 1 }
        for r in end.others ?? [] where r.survived { npcSurvive[r.name, default: 0] += 1 }
        for r in end.results + (end.others ?? []) { if let e = r.epilogue { epiloguesSeen[r.id, default: []].insert(e) } }
        survivorsTotal += engine.state.characters.filter { $0.survived && $0.status != .notJoined }.count
        for c in engine.state.characters {
            if let cause = c.deathCause { causes[cause, default: 0] += 1 }
            if c.status == .exiled { exiles += 1 }
            thefts += c.stats.thefts
            caught += c.stats.caught
            if c.stats.roundsLed > 0 { leaders[engine.name(c.id), default: 0] += c.stats.roundsLed }
        }
        for (id, _) in engine.state.firedEvents { eventsFired[id, default: 0] += 1 }
    }
    let n = Double(runs)
    print("《\(s.title)》 \(runs) 局基础人机模拟")
    print("平均回合数：\(String(format: "%.1f", Double(rounds) / n))  平均幸存人数（含NPC）：\(String(format: "%.2f", Double(survivorsTotal) / n)) / \(s.allCharacters.count)")
    print("有玩家角色活下来的局：\(String(format: "%.0f", Double(anySurvivor) / n * 100))%")
    print("结局分布：")
    for (k, v) in endings.sorted(by: { $0.value > $1.value }) { print("  \(k)：\(String(format: "%.0f", Double(v) / n * 100))%") }
    print("角色存活率 / 个人目标达成率：")
    for c in s.characters {
        print("  \(c.name)：存活 \(String(format: "%.0f", Double(survive[c.name] ?? 0) / n * 100))%  目标 \(String(format: "%.0f", Double(goals[c.name] ?? 0) / n * 100))%")
    }
    if let npcs = s.npcs, !npcs.isEmpty {
        print("NPC 存活率（只算出场的）：" + npcs.map { "\($0.name) \(String(format: "%.0f", Double(npcSurvive[$0.name] ?? 0) / n * 100))%" }.joined(separator: "，"))
    }
    print("尾声出现过的条数：" + s.allCharacters.map { "\($0.name) \(epiloguesSeen[$0.id]?.count ?? 0)/\($0.epilogues?.count ?? 0)" }.joined(separator: "，"))
    print("死因：")
    for (k, v) in causes.sorted(by: { $0.value > $1.value }) { print("  \(k)：\(v)") }
    print("偷吃 \(thefts) 次（被抓 \(caught)），驱逐 \(exiles) 人")
    print("当领头人的回合数：" + leaders.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: "，"))
    let never = s.events.filter { eventsFired[$0.id] == nil }.map(\.id)
    if !never.isEmpty { print("从未触发的事件：\(never.joined(separator: ", "))") }
    print("事件触发次数（前 40）：" + eventsFired.sorted { $0.value > $1.value }.prefix(40).map { "\($0.key)×\($0.value)" }.joined(separator: " "))

case "play":
    let seed = UInt64(option("--seed") ?? "42") ?? 42
    let publicOnly = flag("--public")
    let vitals = flag("--vitals")
    let lang = Lang(rawValue: option("--lang") ?? "zh") ?? .zh
    guard let ref = args.first else { print("用法: brink-cli play <file|id> [--lang en]"); exit(1) }
    var s = loadScenario(ref)
    if lang == .en {
        let overlayURL = URL(fileURLWithPath: ref).deletingLastPathComponent().appendingPathComponent("en/\(s.id).json")
        if let d = FileManager.default.contents(atPath: overlayURL.path), let o = try? JSONDecoder().decode(ScenarioOverlay.self, from: d) {
            s = ScenarioText.translate(s, o.strings)
        } else {
            s = ScenarioLibrary.localized(s, lang: .en)
        }
    }
    var playSetup = GameSetup(scenarioId: s.id, seed: seed, controllers: [:], language: lang)
    playSetup.difficulty = option("--difficulty").flatMap(Difficulty.init(rawValue:))
    let engine = GameEngine(scenario: s, setup: playSetup)
    if vitals {
        var lastRound = 0
        while !engine.isOver {
            AutoRunner.step(engine)
            if engine.state.round != lastRound {
                lastRound = engine.state.round
                var line = "R\(lastRound) \(engine.state.weather) \(Int(engine.state.dayLow))~\(Int(engine.state.dayHigh))°C 庇护所\(Int(engine.state.shelterIntegrity)) 火\(engine.state.fireLit ? "有" : "无") 食\(Int(engine.state.resources["food"] ?? 0)) 水\(String(format: "%.1f", engine.state.resources["water"] ?? 0)) 燃\(String(format: "%.1f", engine.state.resources["fuel"] ?? 0)) 配给\(Int(engine.state.policy.food))/\(engine.state.policy.water)"
                for c in engine.state.characters where c.alive {
                    let w = s.character(c.id)?.weight ?? 65
                    line += "\n   \(engine.name(c.id))[\(c.status.rawValue)] HP\(Int(c.health)) 体温\(String(format: "%.1f", c.core)) 缺水\(String(format: "%.1f", max(0, c.thirst) / w * 100))% 脂\(String(format: "%.1f", c.fatKg)) 摄入\(String(format: "%.2f", c.energyEMA)) 疲\(Int(c.fatigue)) 士气\(Int(c.morale)) 任务:\(c.lastTask ?? "-") 伤:" + c.injuries.map { "\($0.displayName)\(Int($0.severity))" }.joined(separator: ",")
                }
                print(line)
            }
        }
        if let e = engine.state.ending { print("结局：\(e.title)") }
    } else {
        AutoRunner.playToEnd(engine)
        print(Transcript.text(engine, godView: !publicOnly))
    }

case "strings":
    // All player-facing strings of a scenario (what an English overlay must translate).
    guard let ref = args.first else { print("用法: brink-cli strings <file.json>"); exit(1) }
    let s = loadScenario(ref)
    let list = ScenarioText.collect(s)
    let data = try! JSONSerialization.data(withJSONObject: list, options: [.prettyPrinted, .withoutEscapingSlashes])
    print(String(data: data, encoding: .utf8)!)

case "l10n-stub":
    // Create/extend Scenarios/en/<id>.json with every untranslated string mapped to "".
    guard let ref = args.first else { print("用法: brink-cli l10n-stub <file.json>"); exit(1) }
    let s = loadScenario(ref)
    let url = URL(fileURLWithPath: ref).deletingLastPathComponent().appendingPathComponent("en").appendingPathComponent("\(s.id).json")
    var overlay = (try? JSONDecoder().decode(ScenarioOverlay.self, from: Data(contentsOf: url))) ?? ScenarioOverlay(id: s.id, lang: "en", strings: [:])
    var added = 0
    for str in ScenarioText.collect(s) where overlay.strings[str] == nil {
        overlay.strings[str] = ""
        added += 1
    }
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try! enc.encode(overlay).write(to: url)
    print("写入 \(url.path)：新增 \(added) 条待翻译，共 \(overlay.strings.count) 条")

case "l10n-check":
    // Check an English overlay: coverage, placeholders, leftover Chinese.
    guard let ref = args.first else { print("用法: brink-cli l10n-check <file.json> [overlay.json]"); exit(1) }
    let s = loadScenario(ref)
    let overlayPath = args.count > 1 ? args[1] : URL(fileURLWithPath: ref).deletingLastPathComponent().appendingPathComponent("en/\(s.id).json").path
    guard let data = FileManager.default.contents(atPath: overlayPath), let overlay = try? JSONDecoder().decode(ScenarioOverlay.self, from: data) else {
        print("❌ 读不到对照表 \(overlayPath)")
        exit(1)
    }
    let needed = ScenarioText.collect(s)
    var missing: [String] = [], bad: [String] = [], cjk: [String] = []
    for str in needed {
        guard let en = overlay.strings[str], !en.trimmingCharacters(in: .whitespaces).isEmpty else { missing.append(str); continue }
        if ScenarioText.placeholderSet(str) != ScenarioText.placeholderSet(en) { bad.append("\(str)\n      → \(en)") }
        if Loc.hasCJK(en) { cjk.append(en) }
    }
    let unused = Set(overlay.strings.keys).subtracting(needed)
    print("\(missing.isEmpty && bad.isEmpty && cjk.isEmpty ? "✅" : "❌") \(s.id)：需要 \(needed.count) 条，缺 \(missing.count)，占位符不一致 \(bad.count)，英文里残留中文 \(cjk.count)，多余 \(unused.count)")
    for m in missing.prefix(30) { print("   缺：\(m)") }
    for b in bad.prefix(30) { print("   占位符：\(b)") }
    for c in cjk.prefix(30) { print("   残留中文：\(c)") }
    exit(missing.isEmpty && bad.isEmpty && cjk.isEmpty ? 0 : 1)

case "langdiff":
    // Plays the same seed in Chinese and English and shows where the games first differ.
    let seed = UInt64(option("--seed") ?? "1") ?? 1
    guard let ref = args.first else { print("用法: brink-cli langdiff <file> [--seed S]"); exit(1) }
    let zh = loadScenario(ref)
    let overlayURL = URL(fileURLWithPath: ref).deletingLastPathComponent().appendingPathComponent("en/\(zh.id).json")
    guard let d = FileManager.default.contents(atPath: overlayURL.path), let o = try? JSONDecoder().decode(ScenarioOverlay.self, from: d) else { print("没有英文对照表"); exit(1) }
    let en = ScenarioText.translate(zh, o.strings)
    let a = GameEngine(scenario: zh, setup: GameSetup(scenarioId: zh.id, seed: seed, controllers: [:], language: .zh))
    let b = GameEngine(scenario: en, setup: GameSetup(scenarioId: zh.id, seed: seed, controllers: [:], language: .en))
    var steps = 0
    while !a.isOver || !b.isOver {
        if !a.isOver { AutoRunner.step(a) }
        if !b.isOver { AutoRunner.step(b) }
        steps += 1
        func sig(_ e: GameEngine) -> [String] {
            e.state.characters.map { c in "\(c.id) \(c.status) hp\(Int(c.health * 10)) inj\(c.injuries.count) sev\(Int(c.injuries.map(\.severity).reduce(0, +) * 10)) core\(Int(c.core * 100))" }
        }
        let sa = sig(a), sb = sig(b)
        if sa != sb {
            print("第 \(steps) 步、第 \(a.state.round) 回合（\(a.state.phase)）开始身体状态不同：")
            for (x, y) in zip(sa, sb) where x != y {
                print("  zh: \(x)\n  en: \(y)")
                let id = String(x.split(separator: " ")[0])
                print("    zh 伤病: " + (a.state.character(id)?.injuries.map { "\($0.kind)/\($0.part ?? "-")/\($0.label ?? "-")/\(Int($0.severity))" }.joined(separator: ", ") ?? ""))
                print("    en 伤病: " + (b.state.character(id)?.injuries.map { "\($0.kind)/\($0.part ?? "-")/\($0.label ?? "-")/\(Int($0.severity))" }.joined(separator: ", ") ?? ""))
            }
            exit(0)
        }
        let la = a.state.log, lb = b.state.log
        if la.count != lb.count || zip(la, lb).contains(where: { $0.kind != $1.kind || $0.actor != $1.actor }) {
            let i = (0..<min(la.count, lb.count)).first(where: { la[$0].kind != lb[$0].kind || la[$0].actor != lb[$0].actor }) ?? min(la.count, lb.count)
            print("第 \(steps) 步、第 \(a.state.round)/\(b.state.round) 回合开始不同（日志第 \(i) 条）：")
            for j in max(0, i - 3)..<min(max(la.count, lb.count), i + 3) {
                print("  zh[\(j)] \(j < la.count ? "\(la[j].kind) \(la[j].text.prefix(60)) | \(la[j].detail?.prefix(60) ?? "")" : "-")")
                print("  en[\(j)] \(j < lb.count ? "\(lb[j].kind) \(lb[j].text.prefix(60)) | \(lb[j].detail?.prefix(60) ?? "")" : "-")")
            }
            exit(0)
        }
    }
    print("✅ 两种语言完全一致（\(a.state.round) 回合）")

case "fuzz":
    // Random (often invalid) decisions to stress rarely used engine paths.
    let runs = Int(option("--runs") ?? "300") ?? 300
    guard let ref = args.first else { print("用法: brink-cli fuzz <file|id> [--runs N]"); exit(1) }
    let s = loadScenario(ref)
    var rng = SeededRNG(seed: 777)
    var ended = 0, exiles = 0, maxSteps = 0
    for i in 0..<runs {
        let e = GameEngine(scenario: s, setup: GameSetup(scenarioId: s.id, seed: UInt64(i + 1), controllers: [:], debate: rng.chance(0.5)))
        var steps = 0
        while !e.isOver && steps < 3000 {
            steps += 1
            let ids = e.state.characters.map(\.id) + ["nobody", ""]
            switch e.state.phase {
            case .situation:
                guard let ev = e.state.currentEvent else { AutoRunner.step(e); continue }
                var ds: [String: SituationDecision] = [:]
                for id in ev.deciders {
                    let pool = ev.options.map(\.id) + ev.nominees + ["Z", "", "A", "C"]
                    ds[id] = SituationDecision(choice: rng.pick(pool) ?? "", speech: rng.chance(0.5) ? "随便说点什么" : nil)
                }
                if ev.isMajor && rng.chance(0.5) { e.recordStances(ds) }
                e.resolveSituation(ds)
            case .tasks:
                var ds: [String: TaskDecision] = [:]
                let taskIds = s.tasks.map(\.id) + ["rest", "care", "guard", "bogus"]
                let rd = s.rationDef
                for id in e.state.presentParticipants {
                    ds[id] = TaskDecision(task: rng.pick(taskIds)!, target: rng.pick(ids), policy: Policy(food: rng.pick(rd.food + [99999, -5])!, water: rng.pick(rd.water + [0])!, fire: rng.chance(0.5), priority: rng.pick(["equal", "injured", "workers", "leader", "x"])!))
                }
                e.resolveTasks(ds)
            case .night:
                var ds: [String: NightDecision] = [:]
                for id in e.state.presentParticipants {
                    let mt = rng.pick([MotionType.elect, .punish, .exile, .search, .thief])!
                    ds[id] = NightDecision(whispers: [Whisper(to: rng.pick(ids)!, text: "嘘")], secret: rng.pick(["none", "steal", "stash", "reveal", "fly"])!, motion: rng.chance(0.3) ? Motion(type: mt, target: rng.pick(ids)) : nil, diary: "记一笔")
                }
                e.resolveNight(ds)
            case .ended: break
            }
            for c in e.state.characters {
                // health may go up to the character's own maximum (D-044), not just 100
                if c.health > e.maxHealth(c.id) + 0.0001 || c.morale < -0.001 || c.morale > 100.0001 || c.fatKg < 0 { print("⚠️ 角色状态越界 seed=\(i + 1) \(c.id) health=\(c.health) morale=\(c.morale) fat=\(c.fatKg)") }
            }
            for (k, v) in e.state.resources where v < -0.0001 { print("⚠️ 资源为负 seed=\(i + 1) \(k)=\(v)") }
        }
        if e.isOver { ended += 1 }
        exiles += e.state.characters.filter { $0.status == .exiled }.count
        maxSteps = max(maxSteps, steps)
    }
    print("fuzz \(s.id)：\(runs) 局，结束 \(ended)，驱逐 \(exiles) 人，最多 \(maxSteps) 步")

case "llm-play":
    // All five seats played by one OpenAI-compatible model. Example:
    //   brink-cli llm-play snowline --base https://api.deepseek.com --model deepseek-chat --key-env DEEPSEEK_API_KEY
    let base = option("--base") ?? "http://127.0.0.1:18080/v1"
    let model = option("--model") ?? "mock"
    let keyEnv = option("--key-env")
    let seed = UInt64(option("--seed") ?? "7") ?? 7
    let maxRounds = Int(option("--rounds") ?? "0") ?? 0
    let lang = Lang(rawValue: option("--lang") ?? "zh") ?? .zh
    guard let ref = args.first else { print("用法: brink-cli llm-play <file|id> --base URL --model M [--key-env VAR] [--lang en]"); exit(1) }
    var s = loadScenario(ref)
    if lang == .en {
        let overlayURL = URL(fileURLWithPath: ref).deletingLastPathComponent().appendingPathComponent("en/\(s.id).json")
        if let d = FileManager.default.contents(atPath: overlayURL.path), let o = try? JSONDecoder().decode(ScenarioOverlay.self, from: d) {
            s = ScenarioText.translate(s, o.strings)
        }
    }
    let key = keyEnv.flatMap { ProcessInfo.processInfo.environment[$0] } ?? ""
    let profile = ProviderProfile(id: "cli", name: "CLI", kind: .openAI, baseURL: base, apiKey: key, models: [model], enabled: true, maxConcurrent: 5)
    let config = AppConfig(providers: [profile], debate: true, autoDelay: 0)
    var controllers: [String: ControllerKind] = [:]
    let seat = ModelRef(providerId: "cli", model: model)
    for c in s.characters { controllers[c.id] = .llm(seat: seat.id, label: model) }
    var setup = GameSetup(scenarioId: s.id, seed: seed, controllers: controllers, debate: !flag("--no-debate"), spectator: true, language: lang)
    setup.fastPace = flag("--fast")
    let session = GameSession(scenario: s, setup: setup, config: config)
    session.delay = 0
    var printed = 0
    session.start()
    while !session.finished {
        try? await Task.sleep(nanoseconds: 200_000_000)
        let log = session.engine.state.log
        while printed < log.count {
            print(Transcript.line(log[printed], session.engine))
            printed += 1
        }
        if maxRounds > 0 && session.engine.state.round > maxRounds { session.stop(); break }
    }
    print("\n—— 调用统计 ——")
    for (k, u) in session.usage { print("\(k)：\(u.calls) 次，失败 \(u.failures)，输入 \(u.inputTokens) / 输出 \(u.outputTokens) tokens，累计 \(String(format: "%.0f", u.seconds))s") }
    if let e = session.lastError { print("最后一个错误：\(e)") }
    let fallbacks = session.engine.state.log.filter { $0.kind == .speech }.count
    print("发言条数：\(fallbacks)")

case "exam-check":
    // Validate the certificate question banks.
    let (certs, errors) = ExamLibrary.load()
    for e in errors { print("❌ \(e)") }
    var total = 0
    for c in certs {
        let problems = ExamLibrary.check(c)
        let hard = c.questions.filter { $0.hard ?? false }.count
        total += c.questions.count
        print("\(problems.isEmpty ? "✅" : "❌") \(c.id)  \(c.zh.name) / \(c.en.name)  \(c.questions.count) 题（难题 \(hard)）  \(c.effectText(.zh))")
        for p in problems { print("   \(p)") }
    }
    print("共 \(certs.count) 张证、\(total) 道题")
    if !errors.isEmpty || certs.contains(where: { !ExamLibrary.check($0).isEmpty }) { exit(1) }

case "endless":
    // Whole endless runs with the rule AI: how far do they get, what grand endings, how strong at the finale.
    let runs = Int(option("--runs") ?? "50") ?? 50
    let seed0 = UInt64(option("--seed") ?? "1") ?? 1
    let lang = Lang(rawValue: option("--lang") ?? "zh") ?? .zh
    let maxCh = Int(option("--max") ?? "40") ?? 40
    let after = Int(option("--after") ?? "0") ?? 0
    let spectator = flag("--spectator")
    let hardcore = flag("--hardcore")
    let verbose = flag("--verbose")
    let show = flag("--show")
    let (all, loadErrors) = ScenarioLibrary.loadAll()
    for e in loadErrors { print("⚠️ \(e)") }
    let library = ExamLibrary.all()
    if all.first(where: { $0.id == EndlessRun.finaleId }) == nil { print("⚠️ 没有终章（finale.json），征程会停在终章之前") }
    var grand: [String: Int] = [:]
    var reachedFinale = 0, chaptersToFinale = 0, totalChapters = 0
    var levelAtFinale = 0.0, certsAtFinale = 0.0, bonusAtFinale = 0.0, finalePlayers = 0
    var finaleSurvivors = 0
    var clearStats: [String: (played: Int, cleared: Int)] = [:]
    var departures = 0, humanOut = 0
    var examTaken = 0, examPassed = 0
    var byIndex: [Int: (n: Int, human: Int, team: Int, all: Int, allSurv: Int)] = [:]
    var finaleEndings: [String: Int] = [:]
    for i in 0..<runs {
        let run = EndlessSim.play(seed: seed0 + UInt64(i), lang: lang, humanSeat: !spectator, hardcore: hardcore, maxChapters: maxCh, afterFinale: after,
                                  scenarios: all, library: library) { r, engine in
            if verbose, let h = r.history.last {
                print("  run\(i) 第\(h.number)关 \(h.title)：\(h.endingTitle) \(h.cleared ? "通关" : "失败") " + h.lines.map { "\($0.playerName)\($0.survived ? "✓" : "✗")" }.joined(separator: " "))
            }
        }
        if show && i == 0, let g = run.grand {
            print("【\(g.title)】\(g.text)")
            if let a = g.addendum { print(a) }
            if let ft = g.finaleTitle { print("  终章「\(ft)」：\(g.finaleText ?? "")") }
            for l in g.legacies { print("  \(l.name)〔\(l.title)〕Lv\(l.level) \(l.fate)：\(l.epilogue)") }
            for r in g.recap { print("  · \(r)") }
        }
        totalChapters += run.history.count
        for (k, h) in run.history.enumerated() {
            var st = byIndex[k + 1] ?? (0, 0, 0, 0, 0)
            st.n += 1
            if h.lines.first(where: { run.player($0.playerId)?.isHuman ?? false })?.survived ?? false { st.human += 1 }
            if h.cleared { st.team += 1 }
            st.all += h.lines.count
            st.allSurv += h.lines.filter(\.survived).count
            byIndex[k + 1] = st
        }
        if let g = run.grand { grand[g.title, default: 0] += 1 }
        for h in run.history {
            var st = clearStats[h.scenarioId] ?? (0, 0)
            st.played += 1
            if h.cleared { st.cleared += 1 }
            clearStats[h.scenarioId] = st
        }
        if let f = run.history.firstIndex(where: { $0.finale }) {
            finaleEndings["\(run.history[f].endingTitle)（\(run.history[f].lines.filter(\.survived).count) 人）", default: 0] += 1
            reachedFinale += 1
            chaptersToFinale += f + 1
            finaleSurvivors += run.history[f].lines.filter(\.survived).count
            for p in run.players where p.history.contains(where: { $0.finale }) {
                finalePlayers += 1
                levelAtFinale += Double(p.level)
                certsAtFinale += Double(p.certs.count)
                bonusAtFinale += Double(Progression.trainable.map { p.bonus($0, library) }.reduce(0, +))
            }
        }
        departures += run.players.filter(\.out).count
        if run.human?.out ?? false, !(run.history.last?.finale ?? false) { humanOut += 1 }
        for p in run.players { examTaken += p.totals.examsTaken; examPassed += p.totals.examsPassed }
    }
    let n = Double(runs)
    print("无尽模式 \(runs) 段征程（\(spectator ? "观战" : "有玩家座位") \(hardcore ? "铁人" : "普通")，语言 \(lang.rawValue)）")
    print("到达终章：\(String(format: "%.0f", Double(reachedFinale) / n * 100))%，平均第 \(reachedFinale > 0 ? String(format: "%.1f", Double(chaptersToFinale) / Double(reachedFinale)) : "-") 关到达；平均每段 \(String(format: "%.1f", Double(totalChapters) / n)) 关")
    if !spectator { print("玩家心力耗尽、终章前出局：\(String(format: "%.0f", Double(humanOut) / n * 100))%") }
    if finalePlayers > 0 {
        print("到终章时：平均 Lv\(String(format: "%.1f", levelAtFinale / Double(finalePlayers)))，资格证 \(String(format: "%.1f", certsAtFinale / Double(finalePlayers))) 张，技能加成合计 +\(String(format: "%.1f", bonusAtFinale / Double(finalePlayers)))")
        print("终章里活下来的玩家：平均 \(String(format: "%.2f", Double(finaleSurvivors) / Double(reachedFinale))) / 5")
    }
    if !finaleEndings.isEmpty {
        print("终章结局（括号里是活下来的玩家数）：" + finaleEndings.sorted { $0.value > $1.value }.prefix(14).map { "\($0.key) \(String(format: "%.0f", Double($0.value) / n * 100))%" }.joined(separator: "，"))
    }
    print("大结局分布：")
    for (k, v) in grand.sorted(by: { $0.value > $1.value }) { print("  \(k)：\(String(format: "%.0f", Double(v) / n * 100))%") }
    print("各场景通关率（玩过的局里至少一个玩家活下来）：")
    for id in EndlessRun.drills + [EndlessRun.finaleId] {
        guard let st = clearStats[id] else { continue }
        print("  \(id)：\(st.cleared)/\(st.played) = \(String(format: "%.0f", Double(st.cleared) / Double(max(1, st.played)) * 100))%")
    }
    print("按关数：第几关 局数 / 玩家座位存活 / 全队通关 / 玩家角色平均存活")
    for k in byIndex.keys.sorted() where k <= 14 {
        let st = byIndex[k]!
        print("  第\(k)关 \(st.n) / \(String(format: "%.0f", Double(st.human) / Double(st.n) * 100))% / \(String(format: "%.0f", Double(st.team) / Double(st.n) * 100))% / \(String(format: "%.0f", Double(st.allSurv) / Double(max(1, st.all)) * 100))%")
    }
    print("心力耗尽离队的玩家：平均每段 \(String(format: "%.1f", Double(departures) / n)) 人；考试 \(examTaken) 次，通过 \(examPassed) 次（\(String(format: "%.0f", Double(examPassed) / Double(max(1, examTaken)) * 100))%）")

case "llm-endless":
    // An endless run with five LLM players (default: the local mock server): exams, skill points, career memory.
    let base = option("--base") ?? "http://127.0.0.1:18080/v1"
    let model = option("--model") ?? "mock"
    let keyEnv = option("--key-env")
    let chapters = Int(option("--chapters") ?? "2") ?? 2
    let lang = Lang(rawValue: option("--lang") ?? "zh") ?? .zh
    let key = keyEnv.flatMap { ProcessInfo.processInfo.environment[$0] } ?? ""
    let profile = ProviderProfile(id: "cli", name: "CLI", kind: .openAI, baseURL: base, apiKey: key, models: [model], enabled: true, maxConcurrent: 5)
    var config = AppConfig(providers: [profile], debate: true, autoDelay: 0)
    config.logPrompts = true
    let seat = ModelRef(providerId: "cli", model: model)
    let (all, _) = ScenarioLibrary.loadAll()
    let library = ExamLibrary.all()
    var run = EndlessRun.new(seats: (0..<5).map { _ in SeatSpec(seat: seat.id, label: model) }, options: RunOptions(spectator: true), lang: lang, seed: 77)
    let ai = InterludeAI()
    var calls = 0, notesSeen = 0
    for ch in 0..<chapters {
        await ai.perform(run, config: config, library: library) { f in f(&run) }
        for p in run.active {
            print("  \(p.name) Lv\(p.level) 点数\(p.points) 加点\(p.ranks) 证书\(p.certs.map(\.id))  \(ai.status[p.id] ?? "")  “\(p.lastWords ?? "")”")
        }
        var rng = SeededRNG(seed: UInt64(ch + 5))
        guard let next = rng.pick(run.nextChoices), let baseSc = all.first(where: { $0.id == next }) else { break }
        let localized = ScenarioLibrary.localized(baseSc, lang: lang)
        let plan = run.makePlan(localized, humanRole: nil, library: library)
        run.begin(plan)
        let sc = EndlessRun.buildScenario(localized, plan: plan, lang: lang)
        let session = GameSession(scenario: sc, setup: run.setup(for: plan, scenario: sc, library: library), config: config)
        session.delay = 0
        session.start()
        while !session.finished { try? await Task.sleep(nanoseconds: 200_000_000) }
        calls += session.callLog.count
        notesSeen += session.callLog.filter { $0.prompt.contains("【你的经历】") || $0.prompt.contains("[Your record]") }.count
        run.complete(session.engine, library: library)
        if let h = run.history.last { print("第\(h.number)关 \(h.title)：\(h.endingTitle) " + h.lines.map { "\($0.playerName)\($0.survived ? "✓" : "✗")" }.joined(separator: " ")) }
    }
    await ai.perform(run, config: config, library: library) { f in f(&run) }
    print("对局里的模型调用 \(calls) 次，其中带【你的经历】的 \(notesSeen) 次；考试和加点调用 \(ai.calls.count) 次，失败 \(ai.calls.filter { $0.error != nil }.count) 次")
    for p in run.active { print("  \(p.name) Lv\(p.level) 证书\(p.certs.map(\.id)) 考试\(p.exams.map { "\($0.certId) \($0.score)/\($0.total)\($0.by)" })") }

case "llm-exam":
    // One AI model sits all twelve certificate exams (default: the local mock server).
    let base = option("--base") ?? "http://127.0.0.1:18080/v1"
    let model = option("--model") ?? "mock"
    let keyEnv = option("--key-env")
    let lang = Lang(rawValue: option("--lang") ?? "zh") ?? .zh
    let key = keyEnv.flatMap { ProcessInfo.processInfo.environment[$0] } ?? ""
    let profile = ProviderProfile(id: "cli", name: "CLI", kind: .openAI, baseURL: base, apiKey: key, models: [model], enabled: true, maxConcurrent: 3)
    let config = AppConfig(providers: [profile], debate: true, autoDelay: 0)
    let bench = ExamBench()
    bench.start(ref: ModelRef(providerId: "cli", model: model), config: config, library: ExamLibrary.all(), lang: lang)
    while bench.running { try? await Task.sleep(nanoseconds: 200_000_000) }
    for c in ExamLibrary.all() {
        guard let r = bench.results[c.id] else { continue }
        print("\(r.passed ? "✅" : "❌") \(c.name(lang))  \(r.score)/\(r.total)  \(r.note ?? "")")
    }
    print("通过 \(bench.passed)/\(bench.results.count)，答对 \(bench.correct)/\(bench.questions)")

case "llm-test":
    guard args.count >= 3 else { print("用法: brink-cli llm-test <baseURL> <model> <API_KEY_ENV_VAR> [--anthropic]"); exit(1) }
    let anthropic = flag("--anthropic")
    let base = args[0], model = args[1], envVar = args[2]
    let key = ProcessInfo.processInfo.environment[envVar] ?? ""
    let profile = ProviderProfile(id: "test", name: "test", kind: anthropic ? .anthropic : .openAI, baseURL: base, apiKey: key, models: [model], enabled: true)
    let client = LLMClient()
    do {
        let r = try await client.complete(profile: profile, model: model, system: "你是一个测试助手。只输出 JSON。", user: "输出 {\"ok\": true, \"msg\": \"一句中文问候\"}", jsonMode: true, maxTokens: 200, temperature: 0.7)
        print("✅ \(r.text)")
        print("   tokens: in \(r.inputTokens) out \(r.outputTokens)  \(String(format: "%.1f", r.seconds))s")
    } catch {
        print("❌ " + Redact.text("\(error)"))
    }

default:
    print("""
    brink-cli — 绝境 命令行工具
      validate [file.json ...]           校验场景（默认校验全部内置场景）
      sim <file|id> [--runs N] [--seed S] [--difficulty normal|hard|brink] 基础人机批量模拟，输出平衡数据
      play <file|id> [--seed S] [--public] [--lang en] 打印一局完整记录
      strings <file>                     列出场景里所有需要翻译的文字
      l10n-stub <file>                   生成/补全英文对照表 Scenarios/en/<id>.json
      l10n-check <file> [overlay]        检查英文对照表：漏译、占位符、残留中文
      exam-check                         检查资格证题库
      endless [--runs N] [--spectator] [--hardcore] [--after N] [--verbose]  基础人机模拟整段无尽征程
      llm-test <baseURL> <model> <ENV_VAR> [--anthropic]  测试大模型连通
    """)
}
