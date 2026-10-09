import Foundation

/// Runs a whole game synchronously with rule bots (headless simulations, tests).
public enum AutoRunner {

    @discardableResult
    public static func playToEnd(_ engine: GameEngine, maxSteps: Int = 2000) -> EndingResult? {
        var steps = 0
        while !engine.isOver && steps < maxSteps {
            steps += 1
            step(engine)
        }
        return engine.state.ending
    }

    /// Advances exactly one phase using rule bots for every participant.
    public static func step(_ engine: GameEngine) {
        switch engine.state.phase {
        case .situation:
            guard let ev = engine.state.currentEvent else {
                engine.advanceEvent()
                return
            }
            var ds: [String: SituationDecision] = [:]
            for id in ev.deciders { ds[id] = RuleBot.situation(engine, id) }
            if ev.isMajor && engine.state.setup.debate {
                engine.recordStances(ds)
            }
            engine.resolveSituation(ds)
        case .tasks:
            var ds: [String: TaskDecision] = [:]
            var taken: [String: Int] = [:]
            // leader first, then the others: they hear each other's plans
            let order = engine.state.presentParticipants.sorted { a, _ in a == engine.state.leader }
            for id in order {
                let d = RuleBot.task(engine, id, taken: taken)
                ds[id] = d
                taken[d.task, default: 0] += 1
            }
            engine.resolveTasks(ds)
        case .night:
            var ds: [String: NightDecision] = [:]
            for id in engine.state.presentParticipants { ds[id] = RuleBot.night(engine, id) }
            engine.resolveNight(ds)
        case .ended:
            return
        }
    }
}
