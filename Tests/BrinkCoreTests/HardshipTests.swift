import XCTest
@testable import BrinkCore

/// Harder settings: being worn down, things going wrong, help arriving later (D-055).
final class HardshipTests: XCTestCase {
    func scenario(_ id: String) throws -> Scenario {
        try XCTUnwrap(ScenarioLibrary.loadAll().scenarios.first { $0.id == id })
    }

    func engine(_ s: Scenario, seed: UInt64, _ level: Difficulty) -> GameEngine {
        var setup = GameSetup(scenarioId: s.id, seed: seed, controllers: [:])
        setup.difficulty = level
        return GameEngine(scenario: s, setup: setup)
    }

    func testNormalIsLeftAlone() {
        XCTAssertEqual(Difficulty.normal.hardshipRate, 0)
        XCTAssertEqual(Difficulty.normal.wearPerDay, 0)
        XCTAssertEqual(Difficulty.normal.rescueDelay, 0)
        XCTAssertEqual(Difficulty.normal.vitalsScale, 1)
        XCTAssertLessThan(Difficulty.hard.hardshipRate, Difficulty.brink.hardshipRate)
        XCTAssertLessThan(Difficulty.hard.wearPerDay, Difficulty.brink.wearPerDay)
        XCTAssertLessThan(Difficulty.hard.rescueDelay, Difficulty.brink.rescueDelay)
    }

    func testHelpTakesLongerToComeOnHarderSettings() throws {
        let s = try scenario("snowline")
        XCTAssertTrue(s.rescues?.contains("helicopter") ?? false)
        let normal = engine(s, seed: 1, .normal)
        let hard = engine(s, seed: 1, .hard)
        let brink = engine(s, seed: 1, .brink)
        XCTAssertEqual(normal.rescueHold, 0)
        XCTAssertGreaterThan(hard.rescueHold, 0)
        XCTAssertGreaterThan(brink.rescueHold, hard.rescueHold)
        XCTAssertFalse(normal.isHeld("helicopter"))
        XCTAssertTrue(hard.isHeld("helicopter"), "the helicopter can't come on the first day")
        XCTAssertFalse(hard.isHeld("not_a_rescue"), "only rescue events wait")
        hard.state.round = hard.rescueHold
        XCTAssertFalse(hard.isHeld("helicopter"), "once the wait is over it can come")
    }

    func testNobodyIsRescuedBeforeTheHoldOnHard() throws {
        for id in ["snowline", "adrift", "flood"] {
            let s = try scenario(id)
            for seed in 1...12 {
                let e = engine(s, seed: UInt64(seed), .hard)
                let hold = e.rescueHold
                AutoRunner.playToEnd(e)
                for c in e.state.characters where c.status == .rescued {
                    XCTAssertGreaterThanOrEqual(c.rescuedRound ?? 0, hold, "\(id) seed \(seed): \(c.id) was rescued before help could arrive")
                }
            }
        }
    }

    func testBeingWornDownCostsHealthAndIsEasedByCare() throws {
        let s = try scenario("snowline")
        func healthAfterOneDay(_ level: Difficulty, rest: Bool) -> Double {
            let e = engine(s, seed: 7, level)
            e.state.round = 5
            for id in e.state.presentParticipants { e.mutate(id) { $0.lastIntake = rest ? 1500 : 100; $0.morale = rest ? 70 : 10 } }
            var damage: [String: [String: Double]] = [:]
            let before = e.state.presentParticipants.compactMap { e.state.character($0)?.health }.reduce(0, +)
            e.applyWear(damage: &damage)
            let after = e.state.presentParticipants.compactMap { e.state.character($0)?.health }.reduce(0, +)
            return before - after
        }
        XCTAssertEqual(healthAfterOneDay(.normal, rest: false), 0, accuracy: 1e-9, "normal wears nobody down")
        let careless = healthAfterOneDay(.hard, rest: false)
        let cared = healthAfterOneDay(.hard, rest: true)
        XCTAssertGreaterThan(careless, 0)
        XCTAssertLessThan(cared, careless, "fed, hopeful people wear down more slowly")
        XCTAssertGreaterThan(healthAfterOneDay(.brink, rest: false), careless)
    }

    func testThingsGoWrongOnHardButNotOnNormal() throws {
        let s = try scenario("snowline")
        func misfortunes(_ level: Difficulty) -> Int {
            var total = 0
            for seed in 1...30 {
                let e = engine(s, seed: UInt64(seed), level)
                e.state.round = 6
                let before = e.state.log.count
                e.rollHardship()
                total += e.state.log.count - before
            }
            return total
        }
        XCTAssertEqual(misfortunes(.normal), 0)
        XCTAssertGreaterThan(misfortunes(.hard), 3)
        XCTAssertGreaterThan(misfortunes(.brink), misfortunes(.hard))
    }

    func testTheTutorialNeverGetsHarder() throws {
        let s = try scenario("tutorial")
        let e = engine(s, seed: 1, .brink)
        e.state.round = 5
        let before = e.state.log.count
        e.rollHardship()
        XCTAssertEqual(e.state.log.count, before)
        XCTAssertEqual(e.rescueHold, 0)
    }

    func testValidatorRejectsAnUnknownRescueEvent() throws {
        var bad = try scenario("snowline")
        bad.rescues = ["no_such_event"]
        var v = ScenarioValidator(bad)
        XCTAssertFalse(v.validate())
        XCTAssertTrue(v.errors.contains { $0.contains("no_such_event") })
    }

    func testEveryScenarioListsRealRescueEvents() throws {
        for s in ScenarioLibrary.loadAll().scenarios where s.rescueAfter != nil {
            XCTAssertFalse((s.rescues ?? []).isEmpty, "\(s.id) has a wait but no rescue events")
            for r in s.rescues ?? [] { XCTAssertNotNil(s.event(r), "\(s.id): \(r)") }
        }
    }

    func testDeathKindsAreRecognisedInBothLanguages() {
        XCTAssertEqual(GameEngine.deathKind("失温"), "cold")
        XCTAssertEqual(GameEngine.deathKind("Hypothermia"), "cold")
        XCTAssertEqual(GameEngine.deathKind("冻伤坏疽"), "cold")
        XCTAssertEqual(GameEngine.deathKind("二氧化碳中毒"), "air")
        XCTAssertEqual(GameEngine.deathKind("Carbon dioxide poisoning"), "air")
        XCTAssertEqual(GameEngine.deathKind("脱水"), "thirst")
        XCTAssertEqual(GameEngine.deathKind("中暑（热射病）"), "thirst")
        XCTAssertEqual(GameEngine.deathKind("体力耗尽"), "spent")
        XCTAssertEqual(GameEngine.deathKind("腹泻脱水"), "sick")
        XCTAssertEqual(GameEngine.deathKind("感染（败血症）"), "sick")
        XCTAssertEqual(GameEngine.deathKind("疾病"), "sick")
        XCTAssertEqual(GameEngine.deathKind("溺水"), "water")
        XCTAssertEqual(GameEngine.deathKind("失血"), "hurt")
    }

    func wipe(_ s: Scenario, rounds: [Int], cause: String, level: Difficulty? = .hard) -> EndingResult? {
        var setup = GameSetup(scenarioId: s.id, seed: 3, controllers: [:])
        setup.difficulty = level
        let e = GameEngine(scenario: s, setup: setup)
        for (id, r) in zip(e.state.participants, rounds) {
            e.state.round = r
            e.killCharacter(id, cause: cause)
        }
        e.checkWipe()
        return e.state.ending
    }

    func testWhenEveryoneDiesHowItHappenedDecidesTheEnding() throws {
        let s = try scenario("snowline")
        let n = s.characters.count
        XCTAssertEqual(wipe(s, rounds: Array(repeating: 4, count: n), cause: "失温")?.id, "wipe_together")
        XCTAssertEqual(wipe(s, rounds: [2, 3, 4, 5, 12].prefix(n).map { $0 }, cause: "失温")?.id, "wipe_last")
        XCTAssertEqual(wipe(s, rounds: [2, 3, 3, 4, 5].prefix(n).map { $0 }, cause: "失温")?.id, "wipe_cold")
        XCTAssertEqual(wipe(s, rounds: [2, 3, 3, 4, 5].prefix(n).map { $0 }, cause: "脱水")?.id, "wipe_thirst")
        XCTAssertEqual(wipe(s, rounds: [2, 3, 3, 4, 5].prefix(n).map { $0 }, cause: "失血")?.id, s.wipeEnding, "nothing stands out: the scenario's own ending")
        // no difficulty chosen (endless chapters, old saves): always the scenario's own ending
        XCTAssertEqual(wipe(s, rounds: [2, 3, 3, 4, 5].prefix(n).map { $0 }, cause: "失温", level: nil)?.id, s.wipeEnding)
        // the original ending's text is kept and a closing line added
        let ending = try XCTUnwrap(wipe(s, rounds: Array(repeating: 4, count: n), cause: "失温"))
        XCTAssertEqual(ending.tone, "bad")
        XCTAssertTrue(ending.text.contains("\n\n"))
    }

    func testDifficultyCanBeChangedDuringAGame() throws {
        let s = try scenario("snowline")
        let e = engine(s, seed: 2, .normal)
        XCTAssertEqual(e.rescueHold, 0)
        e.changeDifficulty(to: .brink)
        XCTAssertEqual(e.state.setup.level, .brink)
        XCTAssertGreaterThan(e.rescueHold, 0, "from now on help takes longer")
        XCTAssertTrue(e.state.log.contains { $0.kind == .system && $0.text.contains("难度") || $0.text.contains("Difficulty") })
        let before = e.state.log.count
        e.changeDifficulty(to: .brink)
        XCTAssertEqual(e.state.log.count, before, "choosing the same one again changes nothing")
        e.changeDifficulty(to: .normal)
        XCTAssertEqual(e.rescueHold, 0)
    }

    func testTheTutorialsDifficultyCannotBeChanged() throws {
        let e = engine(try scenario("tutorial"), seed: 1, .normal)
        e.changeDifficulty(to: .brink)
        XCTAssertEqual(e.state.setup.level, .normal)
    }
}
