import XCTest
@testable import BrinkCore

/// Giving, sleeping side by side, breakdowns and comfort, difficulty (D-053).
final class BondsTests: XCTestCase {
    func scenario(_ id: String) throws -> Scenario {
        let all = ScenarioLibrary.loadAll().scenarios
        return try XCTUnwrap(all.first { $0.id == id })
    }

    /// Plays with basic bots until the night phase, then hands back the engine.
    func toNight(_ s: Scenario, seed: UInt64 = 3, level: Difficulty? = nil) -> GameEngine {
        var setup = GameSetup(scenarioId: s.id, seed: seed, controllers: [:])
        setup.difficulty = level
        let e = GameEngine(scenario: s, setup: setup)
        var steps = 0
        while e.state.phase != .night && !e.isOver && steps < 50 { AutoRunner.step(e); steps += 1 }
        return e
    }

    func testHuddlingKeepsPairsWarmerOnAColdNight() throws {
        let s = try scenario("snowline")
        let alone = toNight(s)
        let paired = toNight(s)
        let ids = paired.state.presentParticipants
        XCTAssertGreaterThanOrEqual(ids.count, 2)
        let a = ids[0], b = ids[1]
        var together: [String: NightDecision] = [:]
        var apart: [String: NightDecision] = [:]
        for id in ids { together[id] = NightDecision(); apart[id] = NightDecision() }
        together[a] = NightDecision(huddle: b)
        together[b] = NightDecision(huddle: a)
        alone.resolveNight(apart)
        paired.resolveNight(together)
        let coreAlone = (alone.state.character(a)?.core ?? 0) + (alone.state.character(b)?.core ?? 0)
        let corePaired = (paired.state.character(a)?.core ?? 0) + (paired.state.character(b)?.core ?? 0)
        XCTAssertGreaterThanOrEqual(corePaired, coreAlone, "sharing body heat never leaves them colder")
        XCTAssertTrue(paired.state.log.contains { $0.text.contains(paired.name(a)) && $0.text.contains(paired.name(b)) && $0.kind == .system },
                      "who slept next to whom is logged")
        XCTAssertTrue(paired.tonightHuddles.isEmpty, "tonight's arrangements don't outlive the round")
    }

    func testGivingYourRationMovesFoodToTheOther() throws {
        let s = try scenario("snowline")
        let keep = toNight(s)
        let give = toNight(s)
        let ids = give.state.presentParticipants
        let a = ids[0], b = ids[1]
        let beforeA = give.state.character(a)?.lastIntake ?? 0
        let beforeB = give.state.character(b)?.lastIntake ?? 0
        var none: [String: NightDecision] = [:]
        for id in ids { none[id] = NightDecision() }
        var gifts = none
        gifts[a] = NightDecision(gift: Gift(to: b, from: "ration", portion: 1))
        keep.resolveNight(none)
        give.resolveNight(gifts)
        // the giver ate less than when keeping their share, the recipient more
        let keptA = (keep.state.character(a)?.lastIntake ?? 0) - beforeA
        let gaveA = (give.state.character(a)?.lastIntake ?? 0) - beforeA
        let keptB = (keep.state.character(b)?.lastIntake ?? 0) - beforeB
        let gotB = (give.state.character(b)?.lastIntake ?? 0) - beforeB
        XCTAssertLessThanOrEqual(gaveA, keptA)
        XCTAssertGreaterThanOrEqual(gotB, keptB)
        XCTAssertGreaterThan((give.state.character(b)?.trust[a] ?? 0), (keep.state.character(b)?.trust[a] ?? 0), "the recipient trusts the giver more")
    }

    func testBreakdownStopsWorkAndComfortBringsThemBack() throws {
        let s = try scenario("snowline")
        let e = toNight(s)
        let ids = e.state.presentParticipants
        let down = ids[0], friend = ids[1]
        e.addBuff(down, "breakdown", rounds: 2)
        XCTAssertTrue(e.buffMods(down).incapacitated, "someone who has fallen apart can't work")
        XCTAssertFalse(e.taskOptions(for: down).contains { $0.available && $0.id != "rest" }, "only rest is left")
        let opt = try XCTUnwrap(e.taskOptions(for: friend).first { $0.id == "comfort" })
        XCTAssertTrue(opt.targets.contains(down))
        let before = e.state.character(down)?.morale ?? 0
        _ = e.performComfort(by: friend, on: down)
        XCTAssertFalse(e.hasBuff(down, "breakdown"), "a day with someone brings them back")
        XCTAssertGreaterThan(e.state.character(down)?.morale ?? 0, before)
    }

    func testHarderSettingsStartWithLessAndHurtMore() throws {
        let s = try scenario("snowline")
        let normal = GameEngine(scenario: s, setup: GameSetup(scenarioId: s.id, seed: 1, controllers: [:]))
        var hardSetup = GameSetup(scenarioId: s.id, seed: 1, controllers: [:])
        hardSetup.difficulty = .brink
        let brink = GameEngine(scenario: s, setup: hardSetup)
        XCTAssertLessThan(brink.state.resources["food"] ?? 0, normal.state.resources["food"] ?? 0)
        let mN = normal.state.characters.map(\.morale).reduce(0, +)
        let mB = brink.state.characters.map(\.morale).reduce(0, +)
        XCTAssertLessThan(mB, mN)
        // and over many games, fewer people make it
        var aliveN = 0, aliveB = 0
        for seed in 1...40 {
            let n = GameEngine(scenario: s, setup: GameSetup(scenarioId: s.id, seed: UInt64(seed), controllers: [:]))
            var bs = GameSetup(scenarioId: s.id, seed: UInt64(seed), controllers: [:])
            bs.difficulty = .brink
            let b = GameEngine(scenario: s, setup: bs)
            AutoRunner.playToEnd(n)
            AutoRunner.playToEnd(b)
            aliveN += n.state.characters.filter { $0.alive && !$0.isNPC }.count
            aliveB += b.state.characters.filter { $0.alive && !$0.isNPC }.count
        }
        XCTAssertLessThan(aliveB, aliveN)
    }

    func testAIRepliesWithHuddleAndGiftAreRead() {
        let d = Prompting.parseNight(["huddle": "b", "gift": ["to": "c", "from": "stash"], "secret": "none"])
        XCTAssertEqual(d.huddle, "b")
        XCTAssertEqual(d.gift, Gift(to: "c", from: "stash", portion: nil))
        let none = Prompting.parseNight(["huddle": "null", "gift": NSNull()])
        XCTAssertNil(none.huddle)
        XCTAssertNil(none.gift)
    }
}
