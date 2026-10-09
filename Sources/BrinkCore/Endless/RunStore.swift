import Foundation

/// A run on disk: the run itself and, mid-chapter, the chapter's game state (D-039).
public struct RunSave: Codable, Sendable {
    public var run: EndlessRun
    public var chapterState: GameState?
    public var savedAt: Date
    public var manual: Bool?

    public init(run: EndlessRun, chapterState: GameState?, savedAt: Date = Date(), manual: Bool? = nil) {
        self.run = run
        self.chapterState = chapterState
        self.savedAt = savedAt
        self.manual = manual
    }

    /// Where the run stands, without the mode's name ("After chapter 3", "Finale").
    public var progress: String {
        let parts = title.components(separatedBy: " · ")
        return parts.count > 1 ? parts.dropFirst().joined(separator: " · ") : title
    }

    /// "Endless · Chapter 3 · The Shaft" (in the run's language).
    public var title: String {
        let L = run.L
        var parts = [L("无尽模式", "Endless")]
        switch run.phase {
        case .chapter:
            if let p = run.current { parts.append(run.chapterLabel(p.number, finale: p.finale)) }
        case .hub:
            parts.append(run.chapter == 0 ? L("开训前", "Before the first drill") : L("第 \(run.chapter) 关之后", "After chapter \(run.chapter)"))
        case .finaleDone, .ended:
            parts.append(run.grand.map { L("大结局「\($0.title)」", "Grand ending: \($0.title)") } ?? L("已结束", "Over"))
        }
        return parts.joined(separator: " · ")
    }
}

public enum RunStore {
    public static var directory: URL {
        let d = AppPaths.saves.appendingPathComponent("Runs", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    public static func url(_ runId: String) -> URL { directory.appendingPathComponent("\(AppPaths.safeName(runId)).json") }

    /// Same folder as the manual game saves.
    static var slotsDirectory: URL {
        let d = AppPaths.saves.appendingPathComponent("Slots", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// The automatic save of a run (one file per run, overwritten).
    public static func save(_ run: EndlessRun, chapterState: GameState?) {
        let s = RunSave(run: run, chapterState: run.phase == .chapter ? chapterState : nil)
        if let data = try? JSONEncoder().encode(s) { try? data.write(to: url(run.id), options: .atomic) }
    }

    /// A manual save of a run: a copy that doesn't move on with the run.
    @discardableResult
    public static func saveSlot(_ run: EndlessRun, chapterState: GameState?) -> URL? {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        let u = slotsDirectory.appendingPathComponent("\(AppPaths.safeName(run.id))-c\(run.chapter)-\(f.string(from: Date())).json")
        let s = RunSave(run: run, chapterState: run.phase == .chapter ? chapterState : nil, manual: true)
        guard let data = try? JSONEncoder().encode(s) else { return nil }
        do { try data.write(to: u, options: .atomic) } catch { return nil }
        return u
    }

    public static func load(_ url: URL) -> RunSave? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RunSave.self, from: d)
    }

    /// Every run's automatic save, newest first.
    public static func list() -> [(url: URL, save: RunSave)] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { u in load(u).map { (u, $0) } }.sorted { $0.save.savedAt > $1.save.savedAt }
    }

    /// Manual run saves (they live with the other manual saves).
    public static func slots() -> [(url: URL, save: RunSave)] {
        let files = (try? FileManager.default.contentsOfDirectory(at: slotsDirectory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("run-") }.compactMap { u in load(u).map { (u, $0) } }
            .sorted { $0.save.savedAt > $1.save.savedAt }
    }

    /// The most recent run that isn't over.
    public static func latestActive() -> RunSave? { list().first { $0.save.run.phase != .ended }?.save }

    /// The player deleting a run: it goes to the Trash, so a slip can be undone.
    public static func delete(_ url: URL) { AppPaths.trash(url) }
}
