import SwiftUI
import BrinkCore

/// Endless mode: creating, playing, saving and ending runs (D-035 – D-040).
extension AppModel {

    var humanPlayerId: String? { run?.human?.id }

    // MARK: Creating / resuming

    func newRun(seats: [SeatSpec], options: RunOptions, seed: UInt64?) {
        stopTournament()
        session?.stop()
        session = nil
        library = ExamLibrary.all()
        // the certificates on your "我" page come along
        run = EndlessRun.new(seats: seats, options: options, lang: uiLang, seed: seed ?? UInt64.random(in: 1...999_999), humanCerts: profile.certs)
        if profile.name == nil, let n = run?.human?.name { renameProfile(n) }
        runAI.reset()
        autoPaused = false
        saveRun()
        screen = .runHub
        startInterludeAI()
        startAutoLoop()
    }

    func resumeRun(_ save: RunSave) {
        stopTournament()
        session?.stop()
        session = nil
        library = ExamLibrary.all()
        var r = save.run
        runAI.reset()
        autoPaused = false
        showSaves = false
        switch r.phase {
        case .chapter:
            guard let plan = r.current, let base = scenario(plan.scenarioId, lang: r.lang), let st = save.chapterState else {
                // the chapter can't be resumed: back to the camp
                r.phase = .hub
                r.current = nil
                run = r
                saveRun()
                screen = .runHub
                startInterludeAI()
                startAutoLoop()
                return
            }
            let sc = EndlessRun.buildScenario(base, plan: plan, lang: r.lang)
            run = r
            if st.phase == .ended {
                // finished before the app was closed: settle it now
                let engine = GameEngine(scenario: sc, state: st)
                settle(engine)
                return
            }
            let s = GameSession(scenario: sc, saved: st, config: config, gameId: plan.gameId)
            attach(s)
            session = s
            screen = .game
            s.start()
        case .hub:
            run = r
            screen = .runHub
            startInterludeAI()
        case .finaleDone, .ended:
            run = r
            screen = .grand
        }
        startAutoLoop()
    }

    func continueLatestRun() {
        if let s = RunStore.latestActive() { resumeRun(s) }
    }

    // MARK: Saving

    func saveRun(chapterState: GameState? = nil) {
        guard let r = run else { return }
        let state = chapterState ?? (r.phase == .chapter ? session?.engine.state : nil)
        RunStore.save(r, chapterState: state)
        // the run just saved is the newest one; only an ended run means looking through the folder again
        latestRun = r.phase == .ended ? RunStore.latestActive() : RunSave(run: r, chapterState: state)
    }

    /// Applies a change to the live run and saves it.
    func mutateRun(_ f: (inout EndlessRun) -> Void) {
        guard var r = run else { return }
        f(&r)
        run = r
        saveRun()
    }

    func saveRunSlot() {
        guard let r = run else { return }
        if RunStore.saveSlot(r, chapterState: r.phase == .chapter ? session?.engine.state : nil) != nil {
            showToast(L("已存档：\(RunSave(run: r, chapterState: nil).title)", "Saved: \(RunSave(run: r, chapterState: nil).title)"))
        } else {
            showToast(L("存档失败", "Couldn't save"))
        }
    }

    func attach(_ s: GameSession) {
        s.autosaveOverride = { [weak self] state in
            guard let self, let r = self.run, r.phase == .chapter else { return }
            RunStore.save(r, chapterState: state)
        }
    }

    // MARK: Chapters

    func startChapter(_ scenarioId: String, humanRole: String?) {
        guard var r = run, r.phase == .hub, let base = scenario(scenarioId, lang: r.lang) else { return }
        let plan = r.makePlan(base, humanRole: humanRole, library: library)
        r.begin(plan)
        let sc = EndlessRun.buildScenario(base, plan: plan, lang: r.lang)
        var setup = r.setup(for: plan, scenario: sc, library: library)
        setup.fastPace = config.fastPace ?? true
        let s = GameSession(scenario: sc, setup: setup, config: config)
        if ProcessInfo.processInfo.environment["BRINK_DEMO_ENDLESS"] != nil { s.delay = 0 }
        r.current?.gameId = s.gameId
        run = r
        attach(s)
        session = s
        autoMark = nil
        screen = .game
        saveRun(chapterState: s.engine.state)
        s.start()
    }

    /// The chapter is over: settle XP, levels, resolve; go back to the camp (or to the grand ending).
    func completeChapter() {
        guard let s = session, s.engine.isOver, run?.phase == .chapter else { return }
        session?.stop()
        session = nil
        settle(s.engine)
    }

    private func settle(_ engine: GameEngine) {
        guard var r = run else { return }
        r.complete(engine, library: library)
        run = r
        gallery = EndingGallery.load()
        if engine.state.ending != nil {
            var g = EndingGallery.load()
            g.unlock(scenario: engine.scenario.id, ending: engine.state.ending!.id)
            if let grand = r.grand, r.phase == .finaleDone || r.phase == .ended { g.unlock(scenario: "_grand", ending: grand.id) }
            g.save()
            gallery = g
        }
        runAI.reset()
        autoMark = nil
        saveRun()
        if r.phase == .hub {
            screen = .runHub
            startInterludeAI()
        } else {
            screen = .grand
        }
    }

    // MARK: The camp (between chapters)

    func startInterludeAI() {
        guard let r = run, r.phase == .hub, !runAI.running else { return }
        let runId = r.id, interlude = r.interlude
        interludeTask?.cancel()
        interludeTask = Task { [weak self] in
            guard let self else { return }
            await self.runAI.perform(r, config: self.config, library: self.library) { [weak self] f in
                // only into the run and the break it was started for, and not after the player walked away
                guard let self, !Task.isCancelled, self.run?.id == runId, self.run?.interlude == interlude else { return }
                self.mutateRun(f)
            }
        }
    }

    func recordHumanExam(_ record: ExamRecord) {
        guard let h = humanPlayerId else { return }
        let lib = library
        mutateRun { $0.recordExam(h, record, library: lib) }
    }

    func raiseSkill(_ skill: String) {
        guard let h = humanPlayerId else { return }
        mutateRun { r in r.update(h) { $0.raise(skill) } }
    }

    func lowerSkill(_ skill: String) {
        guard let h = humanPlayerId else { return }
        mutateRun { r in r.update(h) { $0.lower(skill) } }
    }

    // MARK: Ending

    func retireRun() {
        let lib = library
        mutateRun { $0.retire(library: lib) }
        if let g = run?.grand {
            var gal = EndingGallery.load()
            gal.unlock(scenario: "_grand", ending: g.id)
            gal.save()
            gallery = gal
        }
        session?.stop()
        session = nil
        screen = .grand
    }

    func continueEndless() {
        mutateRun { $0.continueEndless() }
        runAI.reset()
        screen = .runHub
        startInterludeAI()
    }

    func closeRun() {
        mutateRun { $0.close() }
        leaveRun()
    }

    /// Back to the home screen; the run stays saved.
    func leaveRun() {
        autoTask?.cancel()
        autoTask = nil
        interludeTask?.cancel()
        interludeTask = nil
        if let s = session, let r = run, r.phase == .chapter { RunStore.save(r, chapterState: s.engine.state) }
        session?.stop()
        session = nil
        run = nil
        latestRun = RunStore.latestActive()
        gallery = EndingGallery.load()
        autosave = GameSession.loadAutosave()
        screen = .home
    }

    // MARK: Spectator runs go on by themselves

    func startAutoLoop() {
        autoTask?.cancel()
        guard run?.options.spectator == true else { return }
        autoTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self else { return }
                self.autoStep()
            }
        }
    }

    /// Pauses of the automatic progression (shortened for the end-to-end check, BRINK_DEMO_ENDLESS).
    var autoWaits: (chapter: Double, hub: Double) {
        ProcessInfo.processInfo.environment["BRINK_DEMO_ENDLESS"] != nil ? (0.6, 0.6) : (12, 8)
    }

    private func autoStep() {
        guard let r = run, r.options.spectator, r.options.autoAdvance, !autoPaused else { autoMark = nil; return }
        switch r.phase {
        case .chapter:
            guard let s = session, s.finished else { autoMark = nil; return }
            if autoMark == nil { autoMark = Date() }
            if Date().timeIntervalSince(autoMark!) > autoWaits.chapter { autoMark = nil; completeChapter() }
        case .hub:
            guard !runAI.running else { autoMark = nil; return }
            if autoMark == nil { autoMark = Date() }
            if Date().timeIntervalSince(autoMark!) > autoWaits.hub {
                autoMark = nil
                var rng = SeededRNG(seed: r.seed &+ UInt64(r.chapter) &* 7919)
                if let next = rng.pick(r.nextChoices) { startChapter(next, humanRole: nil) }
            }
        default:
            autoMark = nil
        }
    }

    /// Seconds left before a spectator run moves on (for the countdown).
    var autoCountdown: Int? {
        guard let r = run, r.options.spectator, r.options.autoAdvance, !autoPaused, let m = autoMark else { return nil }
        let total: Double = r.phase == .chapter ? autoWaits.chapter : autoWaits.hub
        return max(0, Int((total - Date().timeIntervalSince(m)).rounded(.up)))
    }
}
