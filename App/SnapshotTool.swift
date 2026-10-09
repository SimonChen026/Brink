import SwiftUI
import AppKit
import BrinkCore

/// Renders key screens to PNG files and quits. Used to check layouts without a screen:
///   BRINK_SNAPSHOT=/tmp/shots open -a Brink   (or run the binary with the env var)
@MainActor
enum SnapshotTool {
    static func runIfRequested(model: AppModel) {
        // Development tooling. A release build only honours it against a sandbox home (BRINK_HOME), so it can
        // never touch the player's own saves or settings, and never sees their Keychain keys.
        #if !DEBUG
        guard ProcessInfo.processInfo.environment["BRINK_HOME"] != nil else { return }
        #endif
        // BRINK_LANG=en|zh renders the screens in that language
        if let l = ProcessInfo.processInfo.environment["BRINK_LANG"], Lang(rawValue: l) != nil { model.setLanguage(l) }
        // End-to-end check of back-to-back spectator games: BRINK_DEMO_TOURNAMENT=<games>
        if let n = ProcessInfo.processInfo.environment["BRINK_DEMO_TOURNAMENT"].flatMap(Int.init),
           let dir = ProcessInfo.processInfo.environment["BRINK_SNAPSHOT"], let s = model.scenarios.first {
            try? FileManager.default.createDirectory(at: URL(fileURLWithPath: dir), withIntermediateDirectories: true)
            Task { @MainActor in
                model.config.autoDelay = 0
                var seats: [String: String] = [:]
                for c in s.characters { seats[c.id] = "rule" }
                model.startTournament(scenario: s, seats: seats, games: n, rotate: true, debate: true)
                model.session?.delay = 0
                for _ in 0..<1200 {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    model.session?.delay = 0
                    if model.screen == .leaderboard { break }
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
                render(LeaderboardView(), model: model, size: CGSize(width: 1320, height: 860), to: URL(fileURLWithPath: dir).appendingPathComponent("tournament-leaderboard.png"))
                NSApp.terminate(nil)
            }
            return
        }
        // Live LLM spectator check against whatever providers are configured: BRINK_SNAPSHOT_LLM=1
        if ProcessInfo.processInfo.environment["BRINK_SNAPSHOT_LLM"] != nil,
           let dir = ProcessInfo.processInfo.environment["BRINK_SNAPSHOT"], let s = model.scenarios.first {
            try? FileManager.default.createDirectory(at: URL(fileURLWithPath: dir), withIntermediateDirectories: true)
            Task { @MainActor in
                let refs = model.config.availableModels
                var controllers: [String: ControllerKind] = [:]
                for (i, c) in s.characters.enumerated() where !refs.isEmpty {
                    let r = refs[i % refs.count]
                    controllers[c.id] = .llm(seat: r.id, label: model.config.label(for: r))
                }
                let live = GameSession(scenario: s, setup: GameSetup(scenarioId: s.id, seed: 8, controllers: controllers, spectator: true), config: model.config)
                live.delay = 0
                live.start()
                for _ in 0..<150 { try? await Task.sleep(nanoseconds: 100_000_000); if live.state.round >= 3 { break } }
                live.paused = true
                try? await Task.sleep(nanoseconds: 300_000_000)
                render(GameView(session: live), model: model, size: CGSize(width: 1320, height: 860), to: URL(fileURLWithPath: dir).appendingPathComponent("llm-spectator.png"))
                render(CallLogView(session: live), model: model, size: CGSize(width: 1100, height: 700), to: URL(fileURLWithPath: dir).appendingPathComponent("llm-calls.png"))
                live.stop()
                NSApp.terminate(nil)
            }
            return
        }
        // 3D scenes through the app's own registry and mapping: BRINK_SNAPSHOT_SCENES=1
        if ProcessInfo.processInfo.environment["BRINK_SNAPSHOT_SCENES"] != nil, let dir = ProcessInfo.processInfo.environment["BRINK_SNAPSHOT"] {
            let out = URL(fileURLWithPath: dir)
            try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            // BRINK_SNAPSHOT_ONLY=tutorial,flood renders just those scenarios
            let only = ProcessInfo.processInfo.environment["BRINK_SNAPSHOT_ONLY"].map { Set($0.split(separator: ",").map(String.init)) }
            for s in model.scenarios where only?.contains(s.id) ?? true {
                // a game a few rounds in, at dusk with the fire going
                let e = GameEngine(scenario: s, setup: GameSetup(scenarioId: s.id, seed: 3, controllers: [:], language: model.uiLang))
                for _ in 0..<9 where !e.isOver { AutoRunner.step(e) }
                for (name, hour) in [("day", 11.0), ("dusk", 18.4)] {
                    var st = SceneState(engine: e)
                    st.hour = hour
                    if hour > 18 { st.fireLit = s.shelter.fire != nil }
                    let t0 = Date()
                    let scene = SceneRegistry.make(s.id)
                    scene.update(st, animated: false)
                    let built = Date().timeIntervalSince(t0)
                    let img = SceneSnapshot.image(scene, size: CGSize(width: 1280, height: 720))
                    try? SceneSnapshot.writePNG(img, to: out.appendingPathComponent("scene-\(s.id)-\(name).png"))
                    print("scene \(s.id) \(name): \(type(of: scene)) built in \(String(format: "%.2f", built))s, \(st.people.count) people")
                }
                if s.id == "tutorial" {
                    // the tutorial's later states: a rainy night with the SOS out, and the road crew at daybreak
                    var night = SceneState(engine: e)
                    night.hour = 21; night.weather = "rain"; night.precip = 1; night.sun = 0.1; night.visibility = 0.6
                    night.fireLit = true; night.vars["signal"] = 62; night.shelter = 60; night.resources["fuel"] = 2
                    night.flags.insert("goods_bought")
                    var dawn = night
                    dawn.hour = 6.7; dawn.weather = "cloudy"; dawn.precip = 0; dawn.sun = 0.3; dawn.visibility = 0.8
                    dawn.shelter = 82; dawn.flags.formUnion(["rescued", "drone"]); dawn.fired["r4_rescue"] = 4; dawn.event = "r4_rescue"
                    for (name, st) in [("night", night), ("rescue", dawn)] {
                        let scene = SceneRegistry.make(s.id)
                        scene.update(st, animated: false)
                        let img = SceneSnapshot.image(scene, size: CGSize(width: 1280, height: 720))
                        try? SceneSnapshot.writePNG(img, to: out.appendingPathComponent("scene-\(s.id)-\(name).png"))
                    }
                }
                if s.id == "icebound" {
                    // the ice storm's later states, each also as the game shows it (a wide strip above the feed):
                    // a night of heavy freezing rain round the fire drum, the pylon down; the armed police coming up
                    // from behind while the villagers sell by the guardrail; the army at work at midday; the road
                    // opening at the thaw
                    var night = SceneState(engine: e)
                    night.hour = 21; night.weather = "heavy_ice"; night.precip = 2; night.sun = 0; night.visibility = 0.3; night.temp = -3
                    night.vars["ice"] = 90; night.vars["clear"] = 45; night.vars["co"] = 55; night.fireLit = true
                    night.done.insert("fire_barrel"); night.flags.formUnion(["bonfire", "pylon_down", "lines_marked", "walked"])
                    var arrive = night
                    arrive.hour = 12; arrive.weather = "overcast"; arrive.precip = 0; arrive.sun = 0.2; arrive.visibility = 0.7; arrive.temp = -1
                    arrive.vars["ice"] = 70; arrive.vars["clear"] = 30; arrive.vars["co"] = 10; arrive.fireLit = false
                    arrive.flags.remove("bonfire"); arrive.flags.insert("market"); arrive.event = "army_arrives"; arrive.fired["army_arrives"] = arrive.round
                    var army = arrive
                    army.hour = 12.5; army.event = nil; army.fired["army_arrives"] = army.round - 1
                    army.vars["ice"] = 55; army.vars["clear"] = 80; army.flags.formUnion(["army", "barrel_moved", "oranges_given", "ropes"])
                    var open = army
                    open.hour = 15; open.weather = "thaw"; open.sun = 0.7; open.visibility = 1; open.temp = 3
                    open.vars["ice"] = 25; open.vars["clear"] = 100; open.flags.insert("road_open"); open.fired["road_opens"] = open.round
                    for (name, st) in [("night", night), ("arrive", arrive), ("army", army), ("open", open)] {
                        let scene = SceneRegistry.make(s.id)
                        scene.update(st, animated: false)
                        for (suffix, size) in [("", CGSize(width: 1280, height: 720)), ("-strip", CGSize(width: 1640, height: 400))] {
                            let img = SceneSnapshot.image(scene, size: size)
                            try? SceneSnapshot.writePNG(img, to: out.appendingPathComponent("scene-\(s.id)-\(name)\(suffix).png"))
                        }
                    }
                }
                if s.id == "fogforest" {
                    // the fog forest's later states: a drizzly night with the SOS half laid and lamps up the slope;
                    // a thinner afternoon with the pyre smoking and the drone over the gap; the camp moved down to
                    // the stream with the cattle trail found; the search team arriving; and the game's wide strip
                    var night = SceneState(engine: e)
                    night.hour = 21; night.weather = "drizzle"; night.precip = 1; night.sun = 0.05; night.visibility = 0.25
                    night.fireLit = true; night.vars["signal"] = 50; night.vars["search"] = 70; night.progress["sos"] = 0.6
                    var signal = night
                    signal.hour = 14; signal.weather = "overcast"; signal.precip = 0; signal.sun = 0.2; signal.visibility = 0.55
                    signal.vars["signal"] = 85; signal.done.insert("sos"); signal.flags.formUnion(["drone", "pyre_used"])
                    var stream = SceneState(engine: e)
                    stream.hour = 10; stream.fireLit = true; stream.flags.formUnion(["stream_camp", "trail"])
                    stream.vars["route"] = 45; stream.vars["signal"] = 30
                    var rescue = signal
                    rescue.hour = 15.5; rescue.weather = "drizzle"; rescue.precip = 1; rescue.visibility = 0.25
                    rescue.flags.insert("rescued"); rescue.fired["rescue_team"] = rescue.round; rescue.event = "rescue_team"
                    var strip = SceneState(engine: e)
                    strip.hour = 18.4; strip.fireLit = true
                    for (name, st, size) in [("night", night, CGSize(width: 1280, height: 720)), ("signal", signal, CGSize(width: 1280, height: 720)),
                                             ("stream", stream, CGSize(width: 1280, height: 720)), ("rescue", rescue, CGSize(width: 1280, height: 720)),
                                             ("strip", strip, CGSize(width: 1400, height: 300))] {
                        let scene = SceneRegistry.make(s.id)
                        scene.update(st, animated: false)
                        let img = SceneSnapshot.image(scene, size: size)
                        try? SceneSnapshot.writePNG(img, to: out.appendingPathComponent("scene-\(s.id)-\(name).png"))
                    }
                }
            }
            NSApp.terminate(nil)
            return
        }
        // Leave a run mid-chapter, come back from disk, finish the chapter: BRINK_DEMO_RESUME=1
        if ProcessInfo.processInfo.environment["BRINK_DEMO_RESUME"] != nil {
            Task { @MainActor in
                var seats = [SeatSpec(seat: "human", label: L("玩家", "Player"), name: "测试员", female: true)]
                seats += (0..<4).map { _ in SeatSpec(seat: "rule", label: L("基础人机", "Basic bot")) }
                model.newRun(seats: seats, options: RunOptions(), seed: 77)
                while model.runAI.running { try? await Task.sleep(nanoseconds: 50_000_000) }
                guard let first = model.run?.nextChoices.first else { print("resume: no choices"); NSApp.terminate(nil); return }
                let role = model.scenario(first)?.characters[2].id
                model.startChapter(first, humanRole: role)
                guard let s = model.session else { print("resume: no session"); NSApp.terminate(nil); return }
                s.stop()
                s.debugAdvance(9)
                let round = s.state.round, phase = s.state.phase
                print("resume: chapter 1 \(first), playing \(role ?? "-"), stopped at round \(round) \(phase.rawValue)")
                model.leaveRun()
                guard let save = RunStore.latestActive() else { print("resume: ❌ no save on disk"); NSApp.terminate(nil); return }
                model.resumeRun(save)
                guard let s2 = model.session else { print("resume: ❌ no session after resume"); NSApp.terminate(nil); return }
                print("resume: back at round \(s2.state.round) \(s2.state.phase.rawValue) — \(s2.state.round == round && s2.state.phase == phase ? "✅ same place" : "❌ different")")
                print("resume: human plays \(s2.humanId ?? "-"), skills \(s2.scenario.character(s2.humanId ?? "")?.skills ?? [:])")
                s2.stop()
                s2.debugAdvance(2000)
                model.completeChapter()
                if let r = model.run {
                    print("resume: after the chapter: phase \(r.phase.rawValue), chapters \(r.history.count), human Lv\(r.human?.level ?? 0) xp\(r.human?.xp ?? 0) resolve\(r.human?.resolve ?? 0)")
                }
                NSApp.terminate(nil)
            }
            return
        }
        // End-to-end check of a whole spectator run through the app's own flow: BRINK_DEMO_ENDLESS=<max chapters>
        if let n = ProcessInfo.processInfo.environment["BRINK_DEMO_ENDLESS"].flatMap(Int.init), let dir = ProcessInfo.processInfo.environment["BRINK_SNAPSHOT"] {
            SceneDisplay.stills = true
            let out = URL(fileURLWithPath: dir)
            try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            Task { @MainActor in
                model.config.autoDelay = 0
                var seats = (0..<5).map { _ in SeatSpec(seat: "rule", label: L("基础人机", "Basic bot")) }
                // BRINK_DEMO_LLM=1: the five seats are the models of a local "mock" provider (a local mock server)
                if ProcessInfo.processInfo.environment["BRINK_DEMO_LLM"] != nil {
                    let refs = model.config.availableModels.filter { $0.providerId == "mock" }
                    if !refs.isEmpty {
                        seats = (0..<5).map { i in let r = refs[i % refs.count]; return SeatSpec(seat: r.id, label: model.config.label(for: r)) }
                    }
                }
                model.newRun(seats: seats, options: RunOptions(spectator: true, hardcore: false, debate: true, autoAdvance: true), seed: 2024)
                var shotHub = false
                let t0 = Date()
                for _ in 0..<12000 {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    guard let r = model.run else { break }
                    if r.phase == .hub && r.chapter == 2 && !shotHub && !model.runAI.running {
                        shotHub = true
                        render(RunHubView(), model: model, size: CGSize(width: 1320, height: 860), to: out.appendingPathComponent("demo-hub-after-2.png"))
                    }
                    if r.phase == .finaleDone || r.phase == .ended || r.chapter >= n && r.phase == .hub { break }
                }
                if let r = model.run {
                    print("demo: phase \(r.phase.rawValue), chapters \(r.history.count), played \(r.played), cleared \(r.cleared), \(String(format: "%.0f", Date().timeIntervalSince(t0)))s")
                    for p in r.players { print("  \(p.name) Lv\(p.level) xp\(p.xp) resolve\(p.resolve) certs\(p.certs.map(\.id)) ranks\(p.ranks) out=\(p.out)") }
                    if let g = r.grand { print("  grand: \(g.title) — \(g.legacies.count) legacies") }
                    print("  interlude model calls: \(model.runAI.calls.count), failed \(model.runAI.calls.filter { $0.error != nil }.count); lessons: \(r.players.compactMap { $0.lessons?.last }.prefix(2))")
                    let board = ModelStatsStore.load()
                    for (k, v) in board.records { print("  leaderboard \(k): games \(v.games), exams \(v.examsTaken ?? 0) passed \(v.examsPassed ?? 0)") }
                    let saved = RunStore.load(RunStore.url(r.id))
                    print("  saved run on disk: phase \(saved?.run.phase.rawValue ?? "missing"), chapters \(saved?.run.history.count ?? -1)")
                    render(r.grand != nil ? AnyView(GrandEndingView()) : AnyView(RunHubView()), model: model, size: CGSize(width: 1320, height: 1800), to: out.appendingPathComponent("demo-end.png"))
                }
                NSApp.terminate(nil)
            }
            return
        }
        // The tutorial, tip by tip, played through to its last screen: BRINK_SNAPSHOT_TUTORIAL=1
        if ProcessInfo.processInfo.environment["BRINK_SNAPSHOT_TUTORIAL"] != nil, let dir = ProcessInfo.processInfo.environment["BRINK_SNAPSHOT"] {
            SceneDisplay.stills = true
            let out = URL(fileURLWithPath: dir)
            try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            Task { @MainActor in
                let size = CGSize(width: 1320, height: 860)
                model.art.loadNow(model.scenarios.filter { !$0.isTutorial })
                model.tutorialDone = false
                render(HomeView(), model: model, size: size, to: out.appendingPathComponent("t0-home.png"))
                model.config.autoDelay = 0
                model.startTutorial()
                guard let s = model.session else { print("tutorial: ❌ no session"); NSApp.terminate(nil); return }
                s.delay = 0
                @MainActor func wait(_ what: String, _ ok: @MainActor () -> Bool) async {
                    for _ in 0..<400 where !ok() { try? await Task.sleep(nanoseconds: 25_000_000) }
                    if !ok() { print("tutorial: ❌ timed out waiting for \(what)") }
                }
                var n = 1
                @MainActor func shot(_ name: String) {
                    let tip = model.tutorialTip(s)?.id ?? "-"
                    render(GameView(session: s), model: model, size: size, to: out.appendingPathComponent(String(format: "t%02d-%@.png", n, name)))
                    print("tutorial: t\(n) \(name) · round \(s.state.round) \(s.state.phase.rawValue) · tip \(tip)")
                    n += 1
                }
                @MainActor func next() { if let t = model.tutorialTip(s) { model.dismissTip(t.id) } }
                let me = TutorialGuide.playerId
                await wait("the first event") { s.pendingHuman == .situation(final: false) }
                shot("welcome"); next()
                shot("you"); next()
                shot("event"); next()
                s.submit(SituationDecision(choice: "stay", speech: L("天黑了，别冒险。", "It's dark. Let's not risk it.")))
                await wait("the final vote") { s.pendingHuman == .situation(final: true) }
                shot("final"); next()
                s.submit(SituationDecision(choice: "stay"))
                await wait("the election") { s.pendingHuman != nil && s.state.currentEvent?.def.id == "_elect" }
                shot("elect"); next()
                s.submit(SituationDecision(choice: me))
                // the election may have a second, final round
                await wait("the work") {
                    if case .situation? = s.pendingHuman { s.submit(SituationDecision(choice: me)) }
                    return s.pendingHuman == .tasks
                }
                shot("tasks"); next()
                shot("care"); next()
                shot("rations"); next()
                s.submit(TaskDecision(task: "care", target: "xiaoyu", speech: nil, policy: s.state.leader == me ? s.state.policy : nil))
                await wait("the night") { s.pendingHuman == .night }
                shot("night"); next()
                s.submit(NightDecision())
                await wait("the second day") { s.state.round >= 2 && s.pendingHuman != nil }
                shot("morning"); next()
                // the rest of the way with the rule AI's choices, stopping at each new tip
                while !s.finished {
                    await wait("a decision or the end") { s.pendingHuman != nil || s.finished }
                    if s.finished { break }
                    if let t = model.tutorialTip(s) { shot(t.id); model.dismissTip(t.id); continue }
                    switch s.pendingHuman {
                    case .situation?: s.submit(RuleBot.situation(s.engine, me))
                    case .tasks?: s.submit(RuleBot.task(s.engine, me))
                    case .night?: s.submit(RuleBot.night(s.engine, me))
                    case nil: break
                    }
                    try? await Task.sleep(nanoseconds: 30_000_000)
                }
                await wait("the end screen") { s.state.ending != nil }
                render(GameView(session: s), model: model, size: CGSize(width: 1320, height: 1400), to: out.appendingPathComponent(String(format: "t%02d-end.png", n)))
                print("tutorial: end · \(s.state.ending?.title ?? "?") · done \(model.tutorialDone)")
                model.leaveGame()
                NSApp.terminate(nil)
            }
            return
        }
        // Endless mode screens: BRINK_SNAPSHOT_ENDLESS=1
        if ProcessInfo.processInfo.environment["BRINK_SNAPSHOT_ENDLESS"] != nil, let dir = ProcessInfo.processInfo.environment["BRINK_SNAPSHOT"] {
            SceneDisplay.stills = true
            let out = URL(fileURLWithPath: dir)
            try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            Task { @MainActor in
                let size = CGSize(width: 1320, height: 860)
                let lang = model.uiLang
                let all = model.baseScenarios
                model.art.loadNow(model.scenarios)
                if ProcessInfo.processInfo.environment["BRINK_SNAPSHOT_COVERART"] != nil {
                    for s in model.scenarios { if let img = model.art.image(s.id) { try? SceneSnapshot.writePNG(img, to: out.appendingPathComponent("art-\(s.id).png")) } }
                }
                render(HomeView(), model: model, size: size, to: out.appendingPathComponent("e1-home.png"))
                render(HomeView(), model: model, size: CGSize(width: 1320, height: 1900), to: out.appendingPathComponent("e1b-home-tall.png"))
                render(RunSetupView(), model: model, size: size, to: out.appendingPathComponent("e2-run-setup.png"))
                // a run two drills in
                var r = EndlessSim.play(seed: 21, lang: lang, maxChapters: 2, scenarios: all, library: model.library)
                r.update(r.human?.id ?? "p1") { $0.points += 2 }
                model.run = r
                model.screen = .runHub
                render(RunHubView(), model: model, size: size, to: out.appendingPathComponent("e3-hub.png"))
                render(RunHubView(), model: model, size: CGSize(width: 1320, height: 1500), to: out.appendingPathComponent("e3b-hub-tall.png"))
                if let h = r.human {
                    render(ExamView(mode: .run(playerId: h.id)), model: model, size: CGSize(width: 900, height: 760), to: out.appendingPathComponent("e4-exam-picker.png"))
                    if let c = r.eligible(h.id, model.library).first {
                        render(ExamView(mode: .run(playerId: h.id), preset: c.id, presetAnswer: 1), model: model, size: CGSize(width: 900, height: 760), to: out.appendingPathComponent("e5-exam-question.png"))
                    }
                }
                // a chapter in progress
                if let next = r.nextChoices.first {
                    model.startChapter(next, humanRole: nil)
                    if let s = model.session {
                        s.stop()
                        s.debugAdvance(7)
                        render(GameView(session: s), model: model, size: size, to: out.appendingPathComponent("e6-chapter.png"))
                    }
                }
                // the finale itself: a run that has played its eight drills, then into the finale
                model.session?.stop()
                model.session = nil
                let eight = EndlessSim.play(seed: 33, lang: lang, maxChapters: 8, scenarios: all, library: model.library)
                model.run = eight
                model.screen = .runHub
                render(RunHubView(), model: model, size: CGSize(width: 1320, height: 1100), to: out.appendingPathComponent("e8-before-finale.png"))
                model.startChapter(EndlessRun.finaleId, humanRole: nil)
                if let s = model.session {
                    s.stop()
                    s.debugAdvance(5)
                    render(GameView(session: s), model: model, size: size, to: out.appendingPathComponent("e9-finale.png"))
                    s.debugAdvance(3)
                    render(GameView(session: s), model: model, size: size, to: out.appendingPathComponent("e9b-finale.png"))
                }
                model.session?.stop()
                model.session = nil
                // "我": a profile with a few certificates and a failed attempt
                var prof = PlayerProfile()
                prof.name = lang == .en ? "Evan Lin" : "林远"
                let t0 = Date().addingTimeInterval(-86_400 * 3)
                prof.record("firstaid", score: 19, total: 20, passed: true, source: "hall", now: t0)
                prof.record("cold", score: 20, total: 20, passed: true, source: "run", now: t0.addingTimeInterval(3600))
                prof.record("radio", score: 19, total: 20, passed: true, source: "hall", now: t0.addingTimeInterval(7200))
                prof.record("wfr", score: 17, total: 20, passed: false, source: "hall", now: Date().addingTimeInterval(-3600))
                model.profile = prof
                render(MeView(), model: model, size: CGSize(width: 1320, height: 1500), to: out.appendingPathComponent("e10-me.png"))
                render(ExamView(mode: .certify(certId: "sea")), model: model, size: CGSize(width: 900, height: 760), to: out.appendingPathComponent("e11-certify.png"))
                model.profile = PlayerProfile()
                // a whole run to its grand ending
                let full = EndlessSim.play(seed: 33, lang: lang, maxChapters: 12, scenarios: all, library: model.library)
                var done = full
                if done.grand == nil { done.retire(library: model.library) }
                model.session = nil
                model.run = done
                render(GrandEndingView(), model: model, size: CGSize(width: 1320, height: 2000), to: out.appendingPathComponent("e7-grand.png"))
                model.run = nil
                NSApp.terminate(nil)
            }
            return
        }
        guard let dir = ProcessInfo.processInfo.environment["BRINK_SNAPSHOT"] else { return }
        SceneDisplay.stills = true
        let out = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        Task { @MainActor in
            let size = CGSize(width: 1320, height: 860)
            model.art.loadNow(model.scenarios)
            render(HomeView(), model: model, size: size, to: out.appendingPathComponent("1-home.png"))
            if let s = model.scenarios.first {
                render(SetupView(scenario: s), model: model, size: size, to: out.appendingPathComponent("2-setup.png"))
                render(SetupView(scenario: s), model: model, size: CGSize(width: 1320, height: 2300), to: out.appendingPathComponent("2b-setup-tall.png"))

                // Player mode: answer prompts automatically and capture each kind once.
                var controllers: [String: ControllerKind] = [:]
                for c in s.characters { controllers[c.id] = .rule }
                let meId = s.characters[1].id
                controllers[meId] = .human
                let player = GameSession(scenario: s, setup: GameSetup(scenarioId: s.id, seed: 3, controllers: controllers, language: model.uiLang), config: model.config)
                player.start()
                var shot: Set<String> = []
                for _ in 0..<300 {
                    try? await Task.sleep(nanoseconds: 60_000_000)
                    guard let p = player.pendingHuman else { continue }
                    switch p {
                    case .situation(let final):
                        let key = final ? "3b-game-debate" : "3-game-player"
                        if !shot.contains(key) {
                            shot.insert(key)
                            render(GameView(session: player), model: model, size: size, to: out.appendingPathComponent("\(key).png"))
                        }
                        if let ev = player.state.currentEvent {
                            let choice = ev.def.kind == "nominate" ? meId : (ev.options.first { $0.available }?.id ?? "")
                            player.submit(SituationDecision(choice: choice, speech: L("先堵断口，今晚不能再冻着了。", "Block the gap first. We can't freeze again tonight.")))
                        }
                    case .tasks:
                        if !shot.contains("4-game-tasks") {
                            shot.insert("4-game-tasks")
                            render(GameView(session: player), model: model, size: size, to: out.appendingPathComponent("4-game-tasks.png"))
                        }
                        player.submit(TaskDecision(task: "rest"))
                    case .night:
                        if !shot.contains("4b-game-night") {
                            shot.insert("4b-game-night")
                            render(GameView(session: player), model: model, size: size, to: out.appendingPathComponent("4b-game-night.png"))
                        }
                        player.submit(NightDecision())
                    }
                    if shot.count >= 4 { break }
                }
                player.stop()

                // Spectator with god view after a few rounds.
                let spec = GameSession(scenario: s, setup: GameSetup(scenarioId: s.id, seed: 11, controllers: [:], spectator: true, language: model.uiLang), config: model.config)
                spec.debugAdvance(14)
                spec.godView = true
                render(GameView(session: spec), model: model, size: size, to: out.appendingPathComponent("5-game-spectator.png"))
                spec.saveToSlot()
                render(SavesView(), model: model, size: CGSize(width: 900, height: 560), to: out.appendingPathComponent("6b-saves.png"))
                spec.debugAdvance(400)
                render(GameView(session: spec), model: model, size: size, to: out.appendingPathComponent("6-game-end.png"))
                GameSession.clearAutosave()
            }
            // One spectator frame per other scenario (checks labels, panels, scenario-specific vars)
            if ProcessInfo.processInfo.environment["BRINK_SNAPSHOT_ALL"] != nil {
                for sc in model.scenarios.dropFirst() {
                    let spec = GameSession(scenario: sc, setup: GameSetup(scenarioId: sc.id, seed: 5, controllers: [:], spectator: true, language: model.uiLang), config: model.config)
                    spec.debugAdvance(10)
                    spec.godView = true
                    render(GameView(session: spec), model: model, size: size, to: out.appendingPathComponent("9-\(sc.id).png"))
                }
                GameSession.clearAutosave()
            }
            render(SettingsView(), model: model, size: CGSize(width: 900, height: 640), to: out.appendingPathComponent("7-settings.png"))
            render(LeaderboardView(), model: model, size: size, to: out.appendingPathComponent("8-leaderboard.png"))
            NSApp.terminate(nil)
        }
    }

    static func render<V: View>(_ view: V, model: AppModel, size: CGSize, to url: URL) {
        let root = view
            .environment(model)
            .frame(width: size.width, height: size.height)
            .background(Theme.bg)
            .foregroundStyle(Theme.text)
            .preferredColorScheme(.dark)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
        }
        window.contentView = nil
    }
}
