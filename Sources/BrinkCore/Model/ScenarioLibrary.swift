import Foundation

public enum ScenarioLibrary {

    /// Directory holding the built-in scenario JSON files.
    public static func builtInDirectory() -> URL? {
        if let url = Bundle.main.url(forResource: "Scenarios", withExtension: nil) {
            return url
        }
        if let url = Bundle.module.url(forResource: "Scenarios", withExtension: nil) {
            return url
        }
        return nil
    }

    /// User scenarios live here (created on demand).
    public static func userDirectory() -> URL {
        AppPaths.support.appendingPathComponent("Scenarios", isDirectory: true)
    }

    public static func decode(_ data: Data) throws -> Scenario {
        do {
            return try JSONDecoder().decode(Scenario.self, from: data)
        } catch let e as DecodingError {
            throw ScenarioError(message: describe(e))
        }
    }

    public static func load(_ url: URL) throws -> Scenario {
        let data = try Data(contentsOf: url)
        do {
            return try decode(data)
        } catch let e as ScenarioError {
            throw ScenarioError(message: "\(url.lastPathComponent)：\(e.message)")
        }
    }

    /// Translation overlay for a scenario (built-in `Scenarios/<lang>/<id>.json`, or the same path in the user folder).
    public static func overlay(for id: String, lang: Lang) -> ScenarioOverlay? {
        guard lang != .zh else { return nil }
        var dirs: [URL] = []
        if let b = builtInDirectory() { dirs.append(b.appendingPathComponent(lang.rawValue)) }
        dirs.append(userDirectory().appendingPathComponent(lang.rawValue))
        for d in dirs.reversed() {
            let url = d.appendingPathComponent("\(id).json")
            if let data = try? Data(contentsOf: url), let o = try? JSONDecoder().decode(ScenarioOverlay.self, from: data) {
                return o
            }
        }
        return nil
    }

    /// The scenario in the requested language (falls back to Chinese for untranslated strings).
    public static func localized(_ s: Scenario, lang: Lang) -> Scenario {
        guard let o = overlay(for: s.id, lang: lang) else { return s }
        return ScenarioText.translate(s, o.strings)
    }

    /// Loads all scenarios in a language.
    public static func loadAll(lang: Lang) -> (scenarios: [Scenario], errors: [String]) {
        let (base, errors) = loadAll()
        return (base.map { localized($0, lang: lang) }, errors)
    }

    /// Loads built-in + user scenarios. Errors are returned, not thrown, so one bad file doesn't hide the rest.
    public static func loadAll() -> (scenarios: [Scenario], errors: [String]) {
        var dirs: [URL] = []
        if let b = builtInDirectory() { dirs.append(b) }
        dirs.append(userDirectory())
        var out: [Scenario] = []
        var errors: [String] = []
        var seen: Set<String> = []
        for dir in dirs {
            guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for f in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where f.pathExtension == "json" {
                do {
                    let s = try load(f)
                    if seen.contains(s.id) { continue }
                    seen.insert(s.id)
                    out.append(s)
                } catch {
                    errors.append("\(error)")
                }
            }
        }
        let order = ["snowline", "adrift", "deepshaft", "rubble", "sandsea", "castaway", "polarnight", "flood"]
        out.sort { a, b in
            let ia = order.firstIndex(of: a.id) ?? 100
            let ib = order.firstIndex(of: b.id) ?? 100
            return ia == ib ? a.id < b.id : ia < ib
        }
        return (out, errors)
    }

    static func describe(_ e: DecodingError) -> String {
        func path(_ ctx: DecodingError.Context) -> String {
            ctx.codingPath.map { k in k.intValue.map { "[\($0)]" } ?? ".\(k.stringValue)" }.joined()
        }
        switch e {
        case .keyNotFound(let key, let ctx):
            return "缺少字段 \(path(ctx)).\(key.stringValue)"
        case .typeMismatch(_, let ctx):
            return "类型不对 \(path(ctx))：\(ctx.debugDescription)"
        case .valueNotFound(_, let ctx):
            return "值为空 \(path(ctx))"
        case .dataCorrupted(let ctx):
            return "JSON 格式错误 \(path(ctx))：\(ctx.debugDescription) \(ctx.underlyingError.map { "\($0)" } ?? "")"
        @unknown default:
            return "\(e)"
        }
    }
}

public struct ScenarioError: Error, CustomStringConvertible {
    public let message: String
    public var description: String { message }
}

public enum AppPaths {
    public static var support: URL {
        // BRINK_HOME overrides the data folder (tests, snapshots).
        if let custom = ProcessInfo.processInfo.environment["BRINK_HOME"], !custom.isEmpty {
            let dir = URL(fileURLWithPath: custom, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("Brink", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static var logs: URL {
        let d = support.appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    public static var saves: URL {
        let d = support.appendingPathComponent("Saves", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Moves a file the player deleted to the Trash (removes it only where there is no Trash, e.g. in a sandbox home).
    public static func trash(_ url: URL) {
        let fm = FileManager.default
        if (try? fm.trashItem(at: url, resultingItemURL: nil)) == nil { try? fm.removeItem(at: url) }
    }

    /// A file that exists but can't be read (damaged, or from a newer version) is copied aside once as
    /// "<name>.unreadable-<date>.json" before anything overwrites it, so nothing is silently lost.
    public static func keepUnreadable(_ url: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path), let data = try? Data(contentsOf: url), !data.isEmpty else { return }
        let dir = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let siblings = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        if siblings.contains(where: { $0.lastPathComponent.hasPrefix(stem + ".unreadable-") && (try? Data(contentsOf: $0)) == data }) { return }
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        try? data.write(to: dir.appendingPathComponent("\(stem).unreadable-\(f.string(from: Date())).json"), options: .atomic)
    }

    /// An id made safe to use in a file name: letters, digits, "-" and "_" only, so a scenario or save
    /// file can never point a path outside its folder.
    public static func safeName(_ id: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        let clean = String(id.filter { allowed.contains($0) }.prefix(80))
        return clean.isEmpty ? "untitled" : clean
    }
}
