import Foundation
import BrinkCore

extension SceneState {
    /// What the 3D scene should show for the current moment of a game.
    init(engine e: GameEngine) {
        self.init()
        let st = e.state
        let sc = e.scenario
        scenario = sc.id
        lang = e.lang.rawValue
        // Time of day follows the phase: morning event → daytime work → night.
        let rh = Double(sc.clock.roundHours)
        let offset: Double
        switch st.phase {
        case .situation: offset = min(1, rh * 0.1)
        case .tasks: offset = rh * 0.3
        case .night, .ended: offset = rh >= 12 ? rh * 0.58 : rh * 0.75
        }
        let absHour = Double(e.roundStartHour) + offset
        hour = (Double(sc.clock.startHour) + absHour).truncatingRemainder(dividingBy: 24)
        let w = e.weatherDef
        weather = st.weather
        precip = w.precip ?? 0
        wind = w.wind ?? 10
        visibility = w.visibility ?? 1
        sun = w.sun ?? 1
        temp = e.airTemp(absHour: Int(absHour))
        // The fire burns at night when the leader keeps it and there is fuel; mornings show last night's fire.
        if let fire = sc.shelter.fire {
            let need = fire.perRound * rh / 24
            let fuel = (st.resources[fire.resource] ?? 0) >= need - 1e-9
            switch st.phase {
            case .situation: fireLit = st.fireLit
            case .tasks: fireLit = st.policy.fire && fuel && temp < 5
            case .night, .ended: fireLit = st.policy.fire && fuel
            }
        }
        for c in st.characters where c.present {
            guard let def = sc.character(c.id) else { continue }
            let hurt = c.health < 35 || c.core < 33 || c.injuries.contains { $0.severity >= 45 }
            people.append(ScenePerson(id: c.id, colorIndex: SK.colorIndex(c.id), injured: hurt, npc: c.isNPC,
                                      child: (def.tags ?? []).contains("child") || (def.age > 0 && def.age < 13),
                                      leader: st.leader == c.id, female: def.isFemale, animal: def.isAnimal, weight: def.weight))
        }
        dead = st.characters.filter { $0.status == .dead && !(sc.character($0.id)?.isAnimal ?? false) }.count
        vars = st.vars
        flags = st.flags
        done = st.projectsDone
        for p in sc.projects ?? [] { progress[p.id] = min(1, (st.projects[p.id] ?? 0) / max(1, p.work)) }
        fired = st.firedEvents
        event = st.currentEvent?.def.id
        shelter = st.shelterIntegrity
        round = st.round
        day = e.currentDay
        resources = st.resources
        ended = st.phase == .ended
    }
}
