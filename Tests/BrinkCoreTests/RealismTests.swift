import XCTest
@testable import BrinkCore

/// Physiology and first-aid realism: fractures, infections, drinking, seawater, foul air.
final class RealismTests: XCTestCase {

    func scenario(_ id: String) throws -> Scenario {
        try XCTUnwrap(ScenarioLibrary.loadAll().scenarios.first { $0.id == id })
    }

    func engine(_ id: String, seed: UInt64 = 3) throws -> GameEngine {
        let s = try scenario(id)
        return GameEngine(scenario: s, setup: GameSetup(scenarioId: s.id, seed: seed, controllers: [:]))
    }

    /// Plays out only the body: rations, the hours, healing — no events or rules.
    func physiologyRound(_ e: GameEngine) {
        var water = e.distributeRations()
        var damage: [String: [String: Double]] = [:], cold: [String: Double] = [:]
        var mods: [String: BuffMods] = [:]
        for c in e.state.characters where c.alive { mods[c.id] = e.buffMods(c.id) }
        e.simulateRoundHours(damage: &damage, coldHours: &cold, mods: mods, water: &water)
        e.state.resources["water", default: 0] += water.reduce(0, +)
        e.settleEnergy()
        e.progressInjuries(damage: &damage, mods: mods)
        e.state.round += 1
    }

    /// A broken leg is splinted once; after that no amount of nursing gets the person walking for weeks.
    func testLegFractureStaysImmobileThroughCare() throws {
        let e = try engine("tutorial")
        e.state.resources["medkit"] = 6
        e.addInjury("ajie", kind: "fracture", severity: 40, part: "左腿", label: nil, partKey: "左腿", labelKey: nil)
        XCTAssertFalse(e.mobility("ajie").canMove, "a broken leg can't take weight")
        for _ in 0..<5 {
            _ = e.performCare(by: "xiaoman", on: "ajie")
            var damage: [String: [String: Double]] = [:]
            e.progressInjuries(damage: &damage)
            e.state.round += 1
        }
        let leg = try XCTUnwrap(e.state.character("ajie")?.injuries.first { $0.kind == "fracture" })
        XCTAssertTrue(leg.treated)
        XCTAssertGreaterThan(leg.severity, 30, "first aid takes at most ~5 off a fracture, once")
        XCTAssertFalse(e.mobility("ajie").canMove)
        // an arm fracture of the same severity doesn't stop anyone walking
        e.addInjury("laozhou", kind: "fracture", severity: 40, part: "左臂", label: nil, partKey: "左臂", labelKey: nil)
        XCTAssertTrue(e.mobility("laozhou").canMove)
    }

    /// With first-aid kits but no antibiotics, care still goes to a festering wound.
    func testInfectionIsCaredForWithoutAntibiotics() throws {
        let e = try engine("tutorial")
        e.state.resources["medkit"] = 2
        e.state.resources["antibiotics"] = 0
        e.addInjury("laozhou", kind: "infection", severity: 50, part: "手", label: nil, partKey: "手", labelKey: nil)
        _ = e.performCare(by: "xiaoman", on: "laozhou")
        let inf = try XCTUnwrap(e.state.character("laozhou")?.injuries.first { $0.kind == "infection" })
        XCTAssertLessThan(inf.severity, 45)
        XCTAssertTrue(inf.treated)
        XCTAssertEqual(e.state.resources["medkit"], 1)
    }

    /// Water handed out is drunk as thirst comes, so plenty of it keeps people hydrated even in the desert,
    /// and what nobody needed goes back into the stock.
    func testAmpleWaterKeepsPeopleHydratedInTheHeat() throws {
        let e = try engine("sandsea")
        e.state.resources["water"] = 500
        e.state.policy.water = 8
        var worst = 0.0
        for _ in 0..<6 {
            for c in e.state.characters where c.present { e.state.assignments[c.id] = TaskAssignment(task: "rest", target: nil) }
            physiologyRound(e)
            for c in e.state.characters where c.alive && !e.isAnimal(c.id) { worst = max(worst, e.dehydration(c)) }
        }
        XCTAssertLessThan(worst, 2, "people with plenty of water shouldn't end the day dehydrated")
        let people = Double(e.state.characters.filter { $0.alive }.count)
        XCTAssertGreaterThan(e.state.resources["water"] ?? 0, 500 - people * 8 * 3, "unneeded water is returned")
    }

    /// A drink of seawater helps for an hour or two and costs more water than it gave.
    func testSeawaterNetsNegativeWater() throws {
        let s = try scenario("adrift")
        let drink = try XCTUnwrap(s.event("r_seawater")?.options?.first { $0.id == "drink" })
        func thirstAfterADay(_ seawater: Bool) -> Double {
            let e = GameEngine(scenario: s, setup: GameSetup(scenarioId: s.id, seed: 4, controllers: [:]))
            e.state.resources["water"] = 0
            if seawater { e.run(drink.effects, EffCtx(actor: "zheng")) }
            physiologyRound(e)
            return e.state.character("zheng")?.thirst ?? 0
        }
        XCTAssertGreaterThan(thirstAfterADay(true), thirstAfterADay(false) + 0.2)
    }

    /// Foul air in the mine: 5% CO₂ stops heavy work, 7% puts people on the floor, 9% kills.
    func testDeepshaftCarbonDioxideIncapacitates() throws {
        let e = try engine("deepshaft")
        let id = try XCTUnwrap(e.state.presentParticipants.first)
        e.state.vars["co2"] = 5.6
        e.run(e.scenario.rules, EffCtx())
        XCTAssertTrue(e.hasBuff(id, "breathless"))
        XCTAssertFalse(e.mobility(id).canHeavy)

        let e2 = try engine("deepshaft")
        let before = try XCTUnwrap(e2.state.character(id)?.health)
        e2.state.vars["co2"] = 7.6
        e2.run(e2.scenario.rules, EffCtx())
        XCTAssertTrue(e2.hasBuff(id, "stupor"))
        XCTAssertLessThanOrEqual(try XCTUnwrap(e2.state.character(id)?.health), before - 30)
        XCTAssertEqual(e2.taskOptions(for: id).filter(\.available).map(\.id), ["rest"])

        let e3 = try engine("deepshaft")
        e3.state.vars["co2"] = 9.5
        e3.run(e3.scenario.rules, EffCtx())
        XCTAssertEqual(e3.state.character(id)?.status, .dead)
    }

    /// A round of zero (or negative) hours is an error, not a crash.
    func testValidatorRejectsZeroLengthRounds() throws {
        var s = try scenario("tutorial")
        s.clock.roundHours = 0
        var v = ScenarioValidator(s)
        XCTAssertFalse(v.validate())
    }
}
