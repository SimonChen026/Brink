import SwiftUI
import BrinkCore

enum Screen: Equatable {
    case home
    case setup(String)
    case game
    case leaderboard
    // endless mode
    case runSetup
    case runHub
    case grand
    case examHall
    case me
}

@MainActor
@Observable
final class AppModel {
    var config: AppConfig
    /// Scenarios as written (Chinese source); `scenarios` are the same in the interface language.
    var baseScenarios: [Scenario] = []
    var scenarios: [Scenario] = []
    var loadErrors: [String] = []
    var screen: Screen = .home
    var session: GameSession?
    var showSettings = false
    var showSaves = false
    var autosave: GameSession.SaveFile?
    var tournament: Tournament?
    /// Interface language (also the language of new games).
    var uiLang: Lang
    /// A short notice shown at the bottom of the window (e.g. "Saved").
    var toast: String?
    /// Endings the player has reached, per scenario.
    var gallery = EndingGallery.load()
    // Endless mode (see AppModel+Run.swift)
    var run: EndlessRun?
    let runAI = InterludeAI()
    /// The exam room's "let a model take every exam".
    let bench = ExamBench()
    /// Key art for the cover (stills of every scenario's 3D scene).
    let art = CoverArt()
    /// "我": the human's certificates and exam record.
    var profile = PlayerProfile.load()
    var library: [CertificateDef] = ExamLibrary.all()
    /// The most recent unfinished run (for the home screen).
    var latestRun: RunSave?
    /// Spectator runs: pause the automatic progression.
    var autoPaused = false
    // Tutorial (see Tutorial/TutorialGuide.swift)
    /// Tips dismissed in the current tutorial game.
    var tutorialSeen = AppModel.loadTutorialSeen()
    /// Tips switched off for the rest of the current tutorial game.
    var tutorialMuted = UserDefaults.standard.bool(forKey: "tutorial.muted")
    /// The tutorial has been finished once (the home screen stops pushing it).
    var tutorialDone = UserDefaults.standard.bool(forKey: "tutorialDone")
    /// Where the home screen should scroll to when it next appears (e.g. "scenarios").
    var homeScrollTarget: String?
    @ObservationIgnored var autoTask: Task<Void, Never>?
    /// The AI players' exam round in the camp; cancelled when the player leaves the run.
    @ObservationIgnored var interludeTask: Task<Void, Never>?
    @ObservationIgnored var autoMark: Date?
    @ObservationIgnored private var tournamentTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    struct Tournament {
        var scenarioId: String
        var seats: [String: String]
        var total: Int
        var played: Int
        var rotate: Bool
        var debate: Bool
        var baseSeed: UInt64
    }

    init() {
        let cfg = AppConfig.load()
        config = cfg
        uiLang = cfg.uiLang
        Loc.ui = cfg.uiLang
        reloadScenarios()
        autosave = GameSession.loadAutosave()
        latestRun = RunStore.latestActive()
    }

    func reloadScenarios() {
        let (s, e) = ScenarioLibrary.loadAll()
        baseScenarios = s
        loadErrors = e
        scenarios = s.map { ScenarioLibrary.localized($0, lang: uiLang) }
    }

    /// The scenario in the interface language, or in another language (for saves).
    func scenario(_ id: String, lang: Lang? = nil) -> Scenario? {
        let l = lang ?? uiLang
        if l == uiLang { return scenarios.first { $0.id == id } }
        return baseScenarios.first { $0.id == id }.map { ScenarioLibrary.localized($0, lang: l) }
    }

    /// nil = follow the system.
    func setLanguage(_ code: String?) {
        config.language = code
        saveConfig()
        uiLang = config.uiLang
        Loc.ui = uiLang
        reloadScenarios()
    }

    func saveConfig() { config.save() }

    /// A certification sitting by the human (exam room or run). Returns true when it earned a new certificate.
    @discardableResult
    func recordProfileExam(_ certId: String, score: Int, total: Int, passed: Bool, source: String) -> Bool {
        let new = profile.record(certId, score: score, total: total, passed: passed, source: source)
        profile.save()
        return new
    }

    func renameProfile(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.name = n.isEmpty ? nil : n
        profile.save()
    }

    /// Settings → clear records: logs, the leaderboard, the endings gallery and saves go to the Trash
    /// (and, if asked, the certificates and exam record too). The settings and API keys stay.
    func clearRecords(includeCertificates: Bool) -> Int {
        stopTournament()
        if run != nil { leaveRun() }
        session?.stop()
        session = nil
        let fm = FileManager.default
        var items = [ModelStatsStore.url, EndingGallery.url, GameSession.autosaveURL]
        for dir in [AppPaths.logs, GameSession.slotsDirectory, RunStore.directory] {
            items += (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        }
        if includeCertificates { items.append(PlayerProfile.url) }
        var moved = 0
        for u in items where fm.fileExists(atPath: u.path) {
            if (try? fm.trashItem(at: u, resultingItemURL: nil)) != nil { moved += 1 }
        }
        for c in library { UserDefaults.standard.removeObject(forKey: "practiceBest.\(c.id)") }
        gallery = EndingGallery.load()
        autosave = nil
        latestRun = nil
        if includeCertificates { profile = PlayerProfile.load() }
        screen = .home
        return moved
    }

    func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if !Task.isCancelled { self?.toast = nil }
        }
    }

    func start(scenario: Scenario, setup: GameSetup) {
        session?.stop()
        var setup = setup
        setup.language = uiLang
        let s = GameSession(scenario: scenario, setup: setup, config: config)
        session = s
        screen = .game
        s.start()
    }

    func resume() {
        guard let save = autosave else { return }
        load(save)
    }

    /// Continue a saved game, in the language it was played in.
    func load(_ save: GameSession.SaveFile) {
        if run != nil { leaveRun() }
        guard let sc = scenario(save.scenarioId, lang: save.lang) else {
            showToast(L("找不到这个存档的场景：\(save.scenarioId)", "The scenario for this save is missing: \(save.scenarioId)"))
            return
        }
        stopTournament()
        session?.stop()
        let s = GameSession(scenario: sc, saved: save.state, config: config, gameId: save.gameId)
        session = s
        screen = .game
        showSaves = false
        s.start()
    }

    /// Save the running game to a new slot.
    func saveGame() {
        if run != nil { saveRunSlot(); return }
        guard let s = session, !s.finished else { return }
        if s.saveToSlot() != nil {
            showToast(L("已存档：\(s.scenario.title) · 第 \(s.state.round) 回合", "Saved: \(s.scenario.title) · round \(s.state.round)"))
        } else {
            showToast(L("存档失败", "Couldn't save"))
        }
    }

    func startTournament(scenario: Scenario, seats: [String: String], games: Int, rotate: Bool, debate: Bool, seed: UInt64? = nil) {
        stopTournament()
        tournament = Tournament(scenarioId: scenario.id, seats: seats, total: max(1, games), played: 0, rotate: rotate, debate: debate, baseSeed: seed ?? UInt64.random(in: 1...900_000))
        tournamentTask = Task { [weak self] in await self?.runTournament(scenario) }
    }

    func stopTournament() {
        tournamentTask?.cancel()
        tournamentTask = nil
        tournament = nil
    }

    private func runTournament(_ s: Scenario) async {
        while let t = tournament, t.played < t.total, !Task.isCancelled {
            let order = s.characters.map(\.id)
            let seatList = order.map { t.seats[$0] ?? "rule" }
            var controllers: [String: ControllerKind] = [:]
            for (i, cid) in order.enumerated() {
                // rotate seats so every model plays every role over several games
                let idx = t.rotate ? (i + t.played) % seatList.count : i
                controllers[cid] = controller(forSeat: seatList[idx])
            }
            var setup = GameSetup(scenarioId: s.id, seed: t.baseSeed + UInt64(t.played), controllers: controllers, debate: t.debate, spectator: true)
            setup.fastPace = config.fastPace ?? true
            setup.difficulty = config.newGameDifficulty
            start(scenario: s, setup: setup)
            while let sess = session, !sess.finished, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
            if Task.isCancelled || tournament == nil { return }
            tournament?.played += 1
            if let t2 = tournament, t2.played < t2.total {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
        if tournament != nil {
            tournament = nil
            session?.stop()
            session = nil
            screen = .leaderboard
        }
    }

    func leaveGame() {
        if tournament != nil { stopTournament() }
        if run != nil { leaveRun(); return }
        session?.stop()
        session = nil
        autosave = GameSession.loadAutosave()
        gallery = EndingGallery.load()
        screen = .home
    }

    /// Model choices for a seat (basic bot + every usable provider/model).
    var seatOptions: [(id: String, label: String)] {
        var out: [(String, String)] = [("rule", L("基础人机（离线）", "Basic bot (offline)"))]
        for ref in config.availableModels {
            out.append((ref.id, config.label(for: ref)))
        }
        return out
    }

    func controller(forSeat seat: String) -> ControllerKind {
        if seat == "rule" { return .rule }
        if seat == "human" { return .human }
        if let ref = ModelRef(seatId: seat) { return .llm(seat: ref.id, label: config.label(for: ref)) }
        return .rule
    }
}
