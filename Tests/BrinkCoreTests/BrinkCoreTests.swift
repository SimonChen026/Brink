import XCTest
@testable import BrinkCore

final class BrinkCoreTests: XCTestCase {
    func testExpressions() throws {
        let node = try Expr.parse("1 + 2 * 3 >= 7 && !(4 < 2) && min(3, 5) == 3 && if(1, 2, 3) == 2")
        XCTAssertEqual(Expr.evaluate(node, resolve: { _ in nil }, random: { 0.5 }), 1)
        XCTAssertThrowsError(try Expr.parse("a ? b : c"))
    }

    func testJSONExtract() {
        let raw = "<think>hmm</think>好的：\n```json\n{\"choice\": \"B\", \"speech\": \"走吧，{别等了}\"}\n```"
        let obj = JSONExtract.object(from: raw)
        XCTAssertEqual(obj?["choice"] as? String, "B")
        XCTAssertEqual(obj?["speech"] as? String, "走吧，{别等了}")
    }

    func testBuiltInScenariosValidateAndFinish() throws {
        let (scenarios, errors) = ScenarioLibrary.loadAll()
        XCTAssertTrue(errors.isEmpty, errors.joined(separator: "\n"))
        XCTAssertFalse(scenarios.isEmpty)
        for s in scenarios {
            var v = ScenarioValidator(s)
            XCTAssertTrue(v.validate(), "\(s.id): \(v.errors.joined(separator: "; "))")
            let engine = GameEngine(scenario: s, setup: GameSetup(scenarioId: s.id, seed: 1, controllers: [:]))
            AutoRunner.playToEnd(engine)
            XCTAssertTrue(engine.isOver, "\(s.id) did not finish")
            XCTAssertNotNil(engine.state.ending)
        }
    }

    func testDeterministicReplay() {
        guard let s = ScenarioLibrary.loadAll().scenarios.first else { return }
        func run() -> String {
            let e = GameEngine(scenario: s, setup: GameSetup(scenarioId: s.id, seed: 99, controllers: [:]))
            AutoRunner.playToEnd(e)
            return Transcript.text(e)
        }
        XCTAssertEqual(run(), run())
    }

    func testEvacuationEndsGameAsSurvivors() throws {
        guard let s = ScenarioLibrary.loadAll().scenarios.first(where: { $0.id == "snowline" }) else { return }
        let e = GameEngine(scenario: s, setup: GameSetup(scenarioId: s.id, seed: 3, controllers: [:]))
        e.state.flags.insert("rescued")
        let ids = e.state.participants
        for id in ids.dropLast() { e.evacuate(id) }
        XCTAssertFalse(e.isOver)
        e.evacuate(ids.last!)
        XCTAssertTrue(e.isOver)
        let end = try XCTUnwrap(e.state.ending)
        XCTAssertTrue(end.results.allSatisfy { $0.survived }, "rescued people must count as survivors")
        XCTAssertNotEqual(end.id, s.wipeEnding)
    }

    func testParsingLLMReplies() {
        let sit = Prompting.parseSituation(JSONExtract.object(from: "```json\n{\"thought\":\"冷\",\"choice\":\"B\",\"speech\":\"走\"}\n```")!)
        XCTAssertEqual(sit?.choice, "B")
        let task = Prompting.parseTask(["task": "melt_snow", "target": "null", "policy": ["food": 1200, "water": "2", "fire": "true", "priority": "injured"]])
        XCTAssertEqual(task?.task, "melt_snow")
        XCTAssertNil(task?.target)
        XCTAssertEqual(task?.policy?.water, 2)
        XCTAssertEqual(task?.policy?.fire, true)
        let night = Prompting.parseNight(["whispers": [["to": "lin", "text": "小心他"]], "secret": "STEAL", "motion": "exile:zhou", "diary": "记住"])
        XCTAssertEqual(night.secret, "steal")
        XCTAssertEqual(night.motion?.type, .exile)
        XCTAssertEqual(night.motion?.target, "zhou")
        XCTAssertEqual(night.whispers.first?.to, "lin")
    }

    func testSaveRoundTrip() throws {
        guard let s = ScenarioLibrary.loadAll().scenarios.first else { return }
        let e = GameEngine(scenario: s, setup: GameSetup(scenarioId: s.id, seed: 5, controllers: [:]))
        for _ in 0..<6 { AutoRunner.step(e) }
        let data = try JSONEncoder().encode(e.state)
        let back = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertEqual(back.round, e.state.round)
        XCTAssertEqual(back.log.count, e.state.log.count)
    }

    // MARK: - Languages

    /// Translation only changes text: the same seed must play out identically in Chinese and English.
    func testLanguagesPlayIdentically() {
        for base in ScenarioLibrary.loadAll().scenarios {
            let en = ScenarioLibrary.localized(base, lang: .en)
            for seed in [UInt64(1), 2, 3] {
                let a = GameEngine(scenario: base, setup: GameSetup(scenarioId: base.id, seed: seed, controllers: [:], language: .zh))
                let b = GameEngine(scenario: en, setup: GameSetup(scenarioId: base.id, seed: seed, controllers: [:], language: .en))
                AutoRunner.playToEnd(a)
                AutoRunner.playToEnd(b)
                XCTAssertEqual(a.state.ending?.id, b.state.ending?.id, "\(base.id) seed \(seed): different ending")
                XCTAssertEqual(a.state.round, b.state.round, "\(base.id) seed \(seed): different length")
                XCTAssertEqual(a.state.characters.map(\.status), b.state.characters.map(\.status), "\(base.id) seed \(seed): different fates")
                XCTAssertEqual(a.state.log.count, b.state.log.count, "\(base.id) seed \(seed): different log")
            }
        }
    }

    /// An English game (engine text + scenario overlay) must not show any Chinese.
    func testEnglishGamesHaveNoChinese() {
        for base in ScenarioLibrary.loadAll().scenarios {
            let en = ScenarioLibrary.localized(base, lang: .en)
            for seed in [UInt64(2), 7] {
                let e = GameEngine(scenario: en, setup: GameSetup(scenarioId: base.id, seed: seed, controllers: [:], language: .en))
                AutoRunner.playToEnd(e)
                let text = Transcript.markdown(e, godView: true)
                let bad = text.split(separator: "\n").filter { Loc.hasCJK(String($0)) }
                XCTAssertTrue(bad.isEmpty, "\(base.id) seed \(seed): Chinese left in English game:\n" + bad.prefix(5).joined(separator: "\n"))
                for id in base.characters.map(\.id) {
                    let prompt = Prompting.system(e, id) + Prompting.observation(e, id)
                    XCTAssertFalse(Loc.hasCJK(prompt), "\(base.id): Chinese in the English prompt for \(id)")
                }
            }
        }
    }

    func testPronounsAndInlineNames() {
        guard let s = ScenarioLibrary.loadAll().scenarios.first(where: { $0.id == "snowline" }) else { return }
        let e = GameEngine(scenario: s, setup: GameSetup(scenarioId: s.id, seed: 1, controllers: [:], language: .en))
        guard let woman = s.characters.first(where: { $0.isFemale }), let man = s.characters.first(where: { !$0.isFemale }) else { return }
        XCTAssertEqual(e.render("{actor.he} left. {actor.he} came back with {actor.his} pack.", EffCtx(actor: woman.id)), "She left. She came back with her pack.")
        XCTAssertEqual(e.render("I saw {actor.him}.", EffCtx(actor: man.id)), "I saw him.")
        XCTAssertEqual(Loc.inline("Brazier (dries clothes)", .en), "brazier")
        XCTAssertEqual(Loc.inline("The fire", .en), "fire")
        XCTAssertEqual(Loc.inline("火盆（烘衣服）", .zh), "火盆")
        XCTAssertEqual(Loc.inline("SOS sign", .en), "SOS sign")
    }

    func testSaveKeepsLanguage() throws {
        guard let s = ScenarioLibrary.loadAll().scenarios.first else { return }
        let e = GameEngine(scenario: ScenarioLibrary.localized(s, lang: .en), setup: GameSetup(scenarioId: s.id, seed: 5, controllers: [:], language: .en))
        for _ in 0..<12 { AutoRunner.step(e) }
        let file = GameSession.SaveFile(gameId: "t", scenarioId: s.id, state: e.state, savedAt: Date(), title: "x", progress: "y", manual: true)
        let back = try JSONDecoder().decode(GameSession.SaveFile.self, from: JSONEncoder().encode(file))
        XCTAssertEqual(back.lang, .en)
        XCTAssertEqual(back.state.round, e.state.round)
        XCTAssertEqual(back.manual, true)
    }

    @MainActor
    func testSaveSlots() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("brink-test-\(UUID().uuidString)")
        let previousHome = ProcessInfo.processInfo.environment["BRINK_HOME"]
        setenv("BRINK_HOME", tmp.path, 1)
        // put back whatever was there (a test run may itself be sandboxed with BRINK_HOME)
        defer { if let h = previousHome { setenv("BRINK_HOME", h, 1) } else { unsetenv("BRINK_HOME") }; try? FileManager.default.removeItem(at: tmp) }
        guard let base = ScenarioLibrary.loadAll().scenarios.first else { return }
        let s = ScenarioLibrary.localized(base, lang: .en)
        let session = GameSession(scenario: s, setup: GameSetup(scenarioId: s.id, seed: 4, controllers: [:], spectator: true, language: .en),
                                  config: AppConfig(providers: []))
        session.debugAdvance(6)
        XCTAssertNotNil(session.saveToSlot())
        let manual = GameSession.listSaves().filter { !$0.isAutosave }
        XCTAssertEqual(manual.count, 1)
        XCTAssertEqual(manual.first?.file.lang, .en)
        XCTAssertEqual(manual.first?.file.state.round, session.state.round)
        XCTAssertEqual(manual.first?.file.title, s.title)
        // the save resumes into an identical game
        let resumed = GameEngine(scenario: s, state: manual[0].file.state)
        XCTAssertEqual(resumed.state.log.count, session.state.log.count)
        GameSession.deleteSave(manual[0])
        XCTAssertTrue(GameSession.listSaves().filter { !$0.isAutosave }.isEmpty)
    }

    /// The tutorial is short, gentle and always reaches its rescue (D-043).
    func testTutorialIsShortAndGentle() throws {
        let s = try XCTUnwrap(ScenarioLibrary.loadAll().scenarios.first { $0.isTutorial })
        XCTAssertTrue(s.hidden ?? false, "the tutorial must not be listed with the eight disasters")
        XCTAssertNotNil(s.characters.first { $0.id == "xiaoman" }, "the tutorial's player character is missing")
        var people = 0, dead = 0
        for seed in UInt64(1)...80 {
            let e = GameEngine(scenario: s, setup: GameSetup(scenarioId: s.id, seed: seed, controllers: [:]))
            AutoRunner.playToEnd(e)
            XCTAssertTrue(e.isOver)
            XCTAssertEqual(e.state.round, 4, "seed \(seed): the tutorial should end in round 4")
            XCTAssertTrue(e.state.flags.contains("rescued"), "seed \(seed): no rescue")
            for id in ["r1_stay_or_go", "r2_goods", "r3_missing", "r4_rescue"] {
                XCTAssertEqual(e.state.firedEvents[id], Int(id.dropFirst().prefix(1)), "seed \(seed): \(id) didn't happen in its round")
            }
            people += e.state.characters.count
            dead += e.state.characters.filter { !$0.alive }.count
        }
        XCTAssertLessThanOrEqual(Double(dead) / Double(people), 0.02, "the tutorial is too deadly")
    }

    /// Maximum health from the skills, and timed statuses (D-044).
    func testMaxHealthAndStatuses() throws {
        let s = try XCTUnwrap(ScenarioLibrary.loadAll().scenarios.first { $0.isTutorial })
        let e = GameEngine(scenario: s, setup: GameSetup(scenarioId: s.id, seed: 4, controllers: [:]))
        // 老周: Strength 2, Survival 2 → 100 + 6 + 2; 阿杰: Strength 3 → 100 + 9
        XCTAssertEqual(e.maxHealth("laozhou"), 108)
        XCTAssertEqual(e.state.character("laozhou")?.health, 108, "people start at full health")
        XCTAssertEqual(e.maxHealth("ajie"), 109)
        XCTAssertEqual(e.maxHealth("xiaoyu"), 100)
        // knacks come at skill 4 (endless-mode training), not with a scenario expert's 3
        XCTAssertFalse(e.hasBuff("wangbo", "m_survival"))
        var trained = s
        if let i = trained.characters.firstIndex(where: { $0.id == "ajie" }) { trained.characters[i].skills["strength"] = 4 }
        let e2 = GameEngine(scenario: trained, setup: GameSetup(scenarioId: s.id, seed: 4, controllers: [:]))
        XCTAssertTrue(e2.hasBuff("ajie", "m_strength"))
        XCTAssertEqual(e2.maxHealth("ajie"), 117)

        // a scenario's buff effect: everyone gets it, it counts the current round and wears off
        let grant = try JSONDecoder().decode(Effect.self, from: Data(#"{"e":"buff","who":"all","id":"hope","rounds":2}"#.utf8))
        var notes: [String] = []
        e.run([grant], EffCtx(), notes: &notes)
        XCTAssertTrue(e.hasBuff("xiaoman", "hope"))
        XCTAssertTrue(e.truthy("xiaoman.buff.hope", EffCtx()))
        XCTAssertGreaterThan(e.buffMods("xiaoman").eff, 0)
        e.tickBuffs()
        XCTAssertTrue(e.hasBuff("xiaoman", "hope"))
        e.tickBuffs()
        XCTAssertFalse(e.hasBuff("xiaoman", "hope"))

        // resting leaves people rested for the next round; keeping watch leaves them up all night
        e.state.assignments["xiaoman"] = TaskAssignment(task: "rest", target: nil)
        if let i = e.state.index(of: "xiaoman") { e.state.characters[i].fatigue = 10 }
        e.state.guards = ["ajie"]
        e.tickBuffs()
        XCTAssertTrue(e.hasBuff("xiaoman", "rested"))
        XCTAssertTrue(e.hasBuff("ajie", "sleepless"))
        XCTAssertLessThan(e.buffMods("ajie").eff, 0)

        // a death shakes everyone who was there
        e.killCharacter("sujie", cause: "意外")
        XCTAssertTrue(e.hasBuff("laozhou", "shaken"))
        XCTAssertTrue(e.buffs("sujie").isEmpty)

        // the effect only takes ids the engine can time
        var bad = s
        bad.events[0].options?[0].effects = [try JSONDecoder().decode(Effect.self, from: Data(#"{"e":"buff","who":"all","id":"m_medical"}"#.utf8))]
        var v = ScenarioValidator(bad)
        XCTAssertFalse(v.validate())
    }

    /// API keys live in the Keychain, never in config.json, and are masked in any text (D-047).
    func testKeysStayOutOfTheConfigFile() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("brink-keys-\(UUID().uuidString)")
        let previousHome = ProcessInfo.processInfo.environment["BRINK_HOME"]
        setenv("BRINK_HOME", tmp.path, 1)
        // put back whatever was there (a test run may itself be sandboxed with BRINK_HOME)
        defer { if let h = previousHome { setenv("BRINK_HOME", h, 1) } else { unsetenv("BRINK_HOME") }; try? FileManager.default.removeItem(at: tmp); KeyStore.save([:]) }
        XCTAssertFalse(KeyStore.usesKeychain, "tests must never touch the real Keychain")
        // a config from an older version, with the key written into the file
        var legacy = AppConfig(providers: ProviderProfile.presets)
        legacy.providers[0].apiKey = "sk-test-0123456789abcdef"
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        try JSONEncoder().encode(legacy).write(to: AppConfig.fileURL)
        let cfg = AppConfig.load()
        XCTAssertEqual(cfg.providers[0].apiKey, "sk-test-0123456789abcdef", "still usable in memory")
        XCTAssertEqual(KeyStore.key(for: cfg.providers[0].id), "sk-test-0123456789abcdef")
        XCTAssertFalse(try String(contentsOf: AppConfig.fileURL, encoding: .utf8).contains("0123456789abcdef"), "moved out of config.json")
        cfg.save()
        XCTAssertFalse(try String(contentsOf: AppConfig.fileURL, encoding: .utf8).contains("0123456789abcdef"))
        let msg = Redact.text("401 Incorrect API key provided: sk-test-0123456789abcdef. Authorization: Bearer abcdefghijklmnopqrstuvwxyz")
        XCTAssertFalse(msg.contains("0123456789abcdef"))
        XCTAssertFalse(msg.contains("abcdefghijklmnop"))
        XCTAssertEqual(Redact.mask("sk-test-0123456789abcdef"), "sk-test-…cdef")
    }
}
