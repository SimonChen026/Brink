import Foundation

/// Walks every player-facing string in a scenario. Used to apply translation overlays
/// and to extract the strings that need translating.
public enum ScenarioText {

    /// Returns a copy of the scenario with every player-facing string passed through `f`.
    public static func map(_ s: Scenario, _ f: (String) -> String) -> Scenario {
        var s = s
        s.title = f(s.title)
        s.subtitle = f(s.subtitle)
        s.tagline = f(s.tagline)
        s.inspiration = f(s.inspiration)
        s.modelNotes = s.modelNotes?.map(f)
        s.briefing = s.briefing.map(f)
        s.setting.location = f(s.setting.location)
        s.setting.date = s.setting.date.map(f)
        s.setting.description = s.setting.description.map(f)
        s.clock.roundLabel = s.clock.roundLabel.map(f)
        for k in s.climate.weather.keys.sorted() {
            guard var w = s.climate.weather[k] else { continue }
            w.name = f(w.name)
            w.desc = w.desc.map(f)
            s.climate.weather[k] = w
        }
        s.shelter.name = f(s.shelter.name)
        if var fire = s.shelter.fire {
            fire.label = fire.label.map(f)
            s.shelter.fire = fire
        }
        s.resources = s.resources.map { r in
            var r = r
            r.name = f(r.name)
            r.unit = f(r.unit)
            r.desc = r.desc.map(f)
            return r
        }
        s.vars = s.vars?.map { v in
            var v = v
            v.name = f(v.name)
            v.unit = v.unit.map(f)
            v.levels = v.levels?.map(f)
            v.desc = v.desc.map(f)
            return v
        }
        if let pools = s.pools {
            var out: [String: PoolDef] = [:]
            for k in pools.keys.sorted() {
                guard var p = pools[k] else { continue }
                p.name = f(p.name)
                p.items = p.items.map { it in
                    var it = it
                    it.text = it.text.map(f)
                    it.effects = effects(it.effects, f)
                    return it
                }
                out[k] = p
            }
            s.pools = out
        }
        s.projects = s.projects?.map { p in
            var p = p
            p.name = f(p.name)
            p.desc = f(p.desc)
            p.onComplete = effects(p.onComplete, f) ?? []
            return p
        }
        s.characters = s.characters.map { character($0, f) }
        s.npcs = s.npcs?.map { character($0, f) }
        s.tasks = s.tasks.map { t in
            var t = t
            t.name = f(t.name)
            t.desc = f(t.desc)
            t.hint = t.hint.map(f)
            t.effects = effects(t.effects, f) ?? []
            return t
        }
        s.onStart = effects(s.onStart, f)
        s.rules = effects(s.rules, f)
        s.events = s.events.map { e in
            var e = e
            e.text = f(e.text)
            e.result = e.result.map(f)
            e.pre = effects(e.pre, f)
            e.effects = effects(e.effects, f)
            e.options = e.options?.map { o in
                var o = o
                o.label = f(o.label)
                o.hint = o.hint.map(f)
                o.result = o.result.map(f)
                o.effects = effects(o.effects, f)
                return o
            }
            return e
        }
        s.endings = s.endings.map { e in
            var e = e
            e.title = f(e.title)
            e.text = f(e.text)
            return e
        }
        if let names = s.itemNames {
            var out: [String: String] = [:]
            for k in names.keys.sorted() { out[k] = names[k].map { $0.isEmpty ? $0 : f($0) } }
            s.itemNames = out
        }
        s.exileText = s.exileText.map(f)
        return s
    }

    static func character(_ c: CharacterDef, _ f: (String) -> String) -> CharacterDef {
        var c = c
        c.name = f(c.name)
        c.gender = f(c.gender)
        c.role = f(c.role)
        c.bio = f(c.bio)
        c.personality = f(c.personality)
        c.voice = c.voice.map(f)
        c.secret = c.secret.map(f)
        c.secretReveal = effects(c.secretReveal, f)
        if var g = c.goal {
            g.text = f(g.text)
            c.goal = g
        }
        c.injuries = c.injuries?.map { i in
            var i = i
            if i.partKey == nil { i.partKey = i.part }
            if i.labelKey == nil { i.labelKey = i.label }
            i.part = i.part.map(f)
            i.label = i.label.map(f)
            return i
        }
        c.epilogues = c.epilogues?.map { e in
            var e = e
            e.text = f(e.text)
            return e
        }
        c.lines = c.lines?.map(f)
        return c
    }

    static func effects(_ list: [Effect]?, _ f: (String) -> String) -> [Effect]? {
        list?.map { e in
            var e = e
            e.text = e.text.map(f)
            if e.partKey == nil { e.partKey = e.part }
            if e.labelKey == nil { e.labelKey = e.label }
            e.part = e.part.map(f)
            e.label = e.label.map(f)
            e.cause = e.cause.map(f)
            e.then = effects(e.then, f)
            e.else = effects(e.else, f)
            e.do = effects(e.do, f)
            e.onReturn = effects(e.onReturn, f)
            return e
        }
    }

    /// All distinct non-empty player-facing strings, in document order.
    public static func collect(_ s: Scenario) -> [String] {
        var seen: Set<String> = []
        var out: [String] = []
        _ = map(s) { str in
            if !str.isEmpty && !seen.contains(str) {
                seen.insert(str)
                out.append(str)
            }
            return str
        }
        return out
    }

    /// Apply a "Chinese → translation" table.
    public static func translate(_ s: Scenario, _ table: [String: String]) -> Scenario {
        map(s) { table[$0] ?? $0 }
    }

    /// Pronoun suffixes understood by the renderer: {actor.he}, {target.his}, {name.zhou.him}, {actor.ta} …
    public static let pronounForms: Set<String> = ["he", "He", "him", "his", "His", "hers", "himself", "ta"]

    /// The distinct placeholders a translation must keep (pronoun placeholders are optional,
    /// and a placeholder may appear a different number of times).
    public static func placeholderSet(_ s: String) -> Set<String> {
        Set(placeholders(s).filter { p in
            let inner = p.dropFirst().dropLast().split(separator: ".").map(String.init)
            return !(inner.count >= 2 && pronounForms.contains(inner.last!))
        })
    }

    /// Placeholders like {actor} or {name.zhou} contained in a string.
    public static func placeholders(_ s: String) -> [String] {
        var out: [String] = []
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "{", let close = s[i...].firstIndex(of: "}") {
                out.append(String(s[i...close]))
                i = s.index(after: close)
            } else {
                i = s.index(after: i)
            }
        }
        return out.sorted()
    }
}

/// A translation overlay file: `Scenarios/en/<id>.json`.
public struct ScenarioOverlay: Codable, Sendable {
    public var id: String
    public var lang: String
    public var strings: [String: String]

    public init(id: String, lang: String, strings: [String: String]) {
        self.id = id
        self.lang = lang
        self.strings = strings
    }
}
