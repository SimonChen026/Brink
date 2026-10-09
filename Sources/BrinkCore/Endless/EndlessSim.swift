import Foundation

/// Plays whole endless runs headlessly with the rule AI (CLI balance runs and tests).
public enum EndlessSim {

    /// - Parameters:
    ///   - humanSeat: seat 1 is the "human" (played by the rule AI here), so the human-out ending can happen.
    ///   - afterFinale: chapters to keep going after the finale (0 = close the book).
    public static func play(seed: UInt64, lang: Lang = .zh, humanSeat: Bool = true, hardcore: Bool = false, maxChapters: Int = 40,
                            afterFinale: Int = 0, scenarios: [Scenario], library: [CertificateDef],
                            onChapter: ((EndlessRun, GameEngine) -> Void)? = nil) -> EndlessRun {
        var seats: [SeatSpec] = []
        for i in 0..<5 {
            seats.append(SeatSpec(seat: (humanSeat && i == 0) ? "human" : "rule", label: (humanSeat && i == 0) ? Loc.pick("玩家", "Player", lang) : Loc.pick("基础人机", "Basic bot", lang)))
        }
        var run = EndlessRun.new(seats: seats, options: RunOptions(spectator: !humanSeat, hardcore: hardcore, debate: true, autoAdvance: true),
                                 lang: lang, seed: seed, now: Date(timeIntervalSince1970: 1_700_000_000 + Double(seed)))
        var rng = SeededRNG(seed: seed ^ 0xE11D)
        let byId = Dictionary(scenarios.map { ($0.id, ScenarioLibrary.localized($0, lang: lang)) }, uniquingKeysWith: { a, _ in a })
        var afterCount = 0
        while run.phase != .ended && run.chapter < maxChapters {
            if run.phase == .finaleDone {
                if afterFinale > afterCount && run.canContinue { run.continueEndless() } else { run.close(); break }
            }
            if run.cycle >= 2 {
                if afterCount >= afterFinale { run.retire(library: library); break }
                afterCount += 1
            }
            for p in run.active { RunAI.ruleInterlude(&run, p.id, library, includeHuman: true) }
            let choices = run.nextChoices.filter { byId[$0] != nil }
            guard let next = rng.pick(choices), let base = byId[next] else { break }
            let plan = run.makePlan(base, humanRole: nil, library: library)
            run.begin(plan)
            let scenario = EndlessRun.buildScenario(base, plan: plan, lang: lang)
            let setup = run.setup(for: plan, scenario: scenario, library: library)
            let engine = GameEngine(scenario: scenario, setup: setup)
            AutoRunner.playToEnd(engine)
            run.complete(engine, library: library)
            onChapter?(run, engine)
        }
        return run
    }
}
