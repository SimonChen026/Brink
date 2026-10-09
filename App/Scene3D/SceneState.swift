import Foundation

/// Someone shown in the 3D scene.
struct ScenePerson: Equatable {
    var id: String
    /// Index into `SK.clothing` (same palette as the character colors in the UI).
    var colorIndex: Int = 0
    /// Badly hurt or very sick: shown lying down.
    var injured: Bool = false
    var npc: Bool = false
    var child: Bool = false
    var leader: Bool = false
    var female: Bool = false
    /// Animals (dog, camel, pig …) are drawn as a four-legged figure sized by `weight`.
    var animal: Bool = false
    /// Body weight in kg.
    var weight: Double = 65
}

/// Everything a 3D scene needs to know about the current game moment.
/// Plain values only, so scene code doesn't depend on the game engine.
struct SceneState: Equatable {
    /// Scenario id ("snowline", …).
    var scenario: String = ""
    /// Clock hour, 0–24 (fractional).
    var hour: Double = 13
    /// Weather id from the scenario (e.g. "clear", "blizzard").
    var weather: String = "clear"
    /// 0 none, 1 light, 2 heavy.
    var precip: Double = 0
    /// km/h
    var wind: Double = 10
    /// 0–1 (1 = clear).
    var visibility: Double = 1
    /// Sunshine 0–1 (0 = thick overcast).
    var sun: Double = 1
    /// Air temperature °C.
    var temp: Double = 10
    /// The shelter fire / stove / lamp is burning.
    var fireLit: Bool = false
    /// People at camp (alive, not away).
    var people: [ScenePerson] = []
    /// Number of people who died (bodies may be shown).
    var dead: Int = 0
    /// Scenario variables (water level, signal, …) by id.
    var vars: [String: Double] = [:]
    /// Scenario flags that are set.
    var flags: Set<String> = []
    /// Completed projects (ids).
    var done: Set<String> = []
    /// Progress of unfinished projects 0–1 by id.
    var progress: [String: Double] = [:]
    /// Events that have happened: event id → round it happened in.
    var fired: [String: Int] = [:]
    /// The event being decided right now (id), if any.
    var event: String?
    /// Shelter integrity 0–100.
    var shelter: Double = 100
    var round: Int = 1
    var day: Int = 1
    var resources: [String: Double] = [:]
    /// The game is over (ending reached).
    var ended: Bool = false
    /// The game's language ("zh" / "en"), for signs painted in the scene.
    var lang: String = "zh"

    func v(_ key: String, _ fallback: Double = 0) -> Double { vars[key] ?? fallback }
    func has(_ flag: String) -> Bool { flags.contains(flag) }
    func res(_ key: String) -> Double { resources[key] ?? 0 }
    /// The event has happened at some point.
    func happened(_ id: String) -> Bool { fired[id] != nil }
    /// The event is on right now, or happened this round.
    func now(_ id: String) -> Bool { event == id || fired[id] == round }
    /// Project progress 0–1 (1 when done).
    func project(_ id: String) -> Double { done.contains(id) ? 1 : (progress[id] ?? 0) }

    /// Is it dark outside?
    var isNight: Bool { hour < 6.0 || hour >= 19.5 }

    /// Sun elevation in degrees (day arc 6h–18h, peak at noon; negative at night).
    func sunElevation(peak: Double = 55) -> Double {
        let x = (hour - 6) / 12 * Double.pi
        // below the horizon at night: down to −30° at midnight
        return sin(x) * ((hour >= 6 && hour <= 18) ? peak : 30)
    }
}
