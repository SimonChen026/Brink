import Foundation
import Observation

/// One record of an LLM call (for the debug panel and saved logs).
public struct LLMCallRecord: Identifiable, Sendable {
    public let id = UUID()
    public var character: String
    public var model: String
    public var phase: String
    public var round: Int
    public var prompt: String
    public var response: String
    public var seconds: Double
    public var inputTokens: Int
    public var outputTokens: Int
    public var error: String?
}

public struct SeatUsage: Codable, Sendable {
    public var calls = 0
    public var failures = 0
    public var inputTokens = 0
    public var outputTokens = 0
    public var seconds = 0.0
    public init() {}
}

public enum HumanPrompt: Equatable, Sendable {
    case situation(final: Bool)
    case tasks
    case night
}

enum HumanAnswer {
    case situation(SituationDecision)
    case tasks(TaskDecision)
    case night(NightDecision)
}

/// Runs a game: asks humans, LLMs and rule bots for decisions and feeds them to the engine.
@MainActor
@Observable
public final class GameSession {
    public let engine: GameEngine
    public private(set) var state: GameState
    public let config: AppConfig
    public let humanId: String?
    public var godView: Bool
    public var autoPlay: Bool = true
    public var delay: Double
    public var paused: Bool = false
    public private(set) var thinking: Set<String> = []
    /// When each seat in `thinking` was asked (for the waiting panel's timers).
    public private(set) var thinkingSince: [String: Date] = [:]
    /// Seats the player chose not to wait for: their open call is dropped and the rule AI takes the step.
    @ObservationIgnored private var skipRequested: Set<String> = []
    public private(set) var pendingHuman: HumanPrompt?
    public private(set) var stances: [String: SituationDecision] = [:]
    public private(set) var plannedTasks: [String: TaskDecision] = [:]
    public private(set) var callLog: [LLMCallRecord] = []
    public private(set) var usage: [String: SeatUsage] = [:]
    public private(set) var lastError: String?
    public private(set) var finished = false
    public private(set) var savedTranscript: URL?
    public let gameId: String
    /// Endless mode: the chapter is saved with its run instead of in the classic autosave.
    @ObservationIgnored public var autosaveOverride: (@MainActor (GameState) -> Void)?

    @ObservationIgnored private let client: LLMClient
    /// Fast pace: night moves the AI models already chose together with the day's work.
    @ObservationIgnored private var earlyNight: [String: NightDecision] = [:]
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var humanCont: CheckedContinuation<HumanAnswer, Never>?
    @ObservationIgnored private var stepOnce = false
    /// Set by `stop()`: whatever the loop was waiting for is abandoned, never resolved or saved.
    @ObservationIgnored private var stopped = false

    public var scenario: Scenario { engine.scenario }
    public var spectator: Bool { humanId == nil }

    public init(scenario: Scenario, setup: GameSetup, config: AppConfig) {
        self.engine = GameEngine(scenario: scenario, setup: setup)
        self.state = engine.state
        self.config = config
        self.client = LLMClient(timeout: config.callTimeoutSeconds)
        self.humanId = setup.controllers.first { $0.value.isHuman }?.key
        self.godView = setup.spectator
        self.delay = config.autoDelay
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        self.gameId = "\(f.string(from: Date()))-\(scenario.id)"
    }

    /// Resume a saved game.
    public init(scenario: Scenario, saved: GameState, config: AppConfig, gameId: String) {
        self.engine = GameEngine(scenario: scenario, state: saved)
        self.state = saved
        self.config = config
        self.client = LLMClient(timeout: config.callTimeoutSeconds)
        self.humanId = saved.setup.controllers.first { $0.value.isHuman }?.key
        self.godView = saved.setup.spectator
        self.delay = config.autoDelay
        self.gameId = gameId
    }

    public var humanAlive: Bool {
        guard let h = humanId else { return false }
        return state.character(h)?.present ?? false
    }

    @ObservationIgnored private var revealedOnDeath = false

    func sync() {
        state = engine.state
        // When the player's character is gone, the rest of the story is watched from above.
        if humanId != nil && !humanAlive && !revealedOnDeath {
            revealedOnDeath = true
            godView = true
        }
    }

    // MARK: Loop control

    public func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in await self?.run() }
    }

    public func stop() {
        stopped = true
        loop?.cancel()
        loop = nil
        if let c = humanCont {
            humanCont = nil
            c.resume(returning: .night(NightDecision()))
        }
    }

    public func step() { stepOnce = true }

    func run() async {
        while !engine.isOver && !Task.isCancelled {
            await gate()
            if Task.isCancelled { break }
            switch engine.state.phase {
            case .situation: await runSituation()
            case .tasks: await runTasks()
            case .night: await runNight()
            case .ended: break
            }
            // leaving mid-decision must not decide the turn for the player or overwrite the save
            if stopped || Task.isCancelled { return }
            sync()
            autosave()
            if spectator || !humanAlive {
                // let the viewer read what just happened
                let ns = UInt64(max(0, delay) * 1_000_000_000)
                if ns > 0 { try? await Task.sleep(nanoseconds: ns) }
            }
        }
        if engine.isOver && !stopped { finishGame() }
    }

    /// In spectator mode, wait while paused (or until a single step is requested).
    func gate() async {
        guard spectator || !humanAlive else { return }
        while (paused || !autoPlay) && !stepOnce && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        stepOnce = false
    }

    // MARK: Human input

    func askHuman(_ p: HumanPrompt) async -> HumanAnswer {
        pendingHuman = p
        let a = await withCheckedContinuation { (c: CheckedContinuation<HumanAnswer, Never>) in
            humanCont = c
        }
        pendingHuman = nil
        return a
    }

    public func submit(_ d: SituationDecision) {
        guard case .situation = pendingHuman, let c = humanCont else { return }
        humanCont = nil
        c.resume(returning: .situation(d))
    }

    public func submit(_ d: TaskDecision) {
        guard pendingHuman == .tasks, let c = humanCont else { return }
        humanCont = nil
        c.resume(returning: .tasks(d))
    }

    public func submit(_ d: NightDecision) {
        guard pendingHuman == .night, let c = humanCont else { return }
        humanCont = nil
        c.resume(returning: .night(d))
    }

    func isHumanDecider(_ id: String) -> Bool {
        id == humanId && humanAlive
    }

    // MARK: Phases

    func runSituation() async {
        guard let ev = engine.state.currentEvent else {
            engine.advanceEvent()
            return
        }
        let deciders = ev.deciders
        let debate = ev.isMajor && engine.state.setup.debate && deciders.count > 1
        let first = await collectSituation(deciders, stances: nil)
        if stopped { return }
        // everyone already wants the same thing: a second round of argument would change nothing
        let picks = Set(deciders.compactMap { id in first[id].map { engine.normalizeChoice(ev, $0.choice, decider: id) } })
        let unanimous = picks.count == 1 && deciders.allSatisfy { first[$0] != nil }
        if debate && !unanimous {
            engine.recordStances(first)
            stances = first
            sync()
            let final = await collectSituation(deciders, stances: first)
            if stopped { return }
            engine.resolveSituation(final)
        } else {
            engine.resolveSituation(first)
        }
        stances = [:]
        sync()
    }

    func collectSituation(_ ids: [String], stances: [String: SituationDecision]?) async -> [String: SituationDecision] {
        var out: [String: SituationDecision] = [:]
        var jobs: [(String, ModelRef, String, String)] = []
        // a quiet round's small personal choice isn't worth a round of model calls
        let quiet = engine.state.currentEvent?.def.id == "_quiet"
        for id in ids where !isHumanDecider(id) {
            if !quiet, case .llm(let seat, _) = engine.controller(id), let ref = ModelRef(seatId: seat) {
                jobs.append((id, ref, Prompting.system(engine, id), Prompting.situation(engine, id, stances: stances)))
            } else {
                out[id] = RuleBot.situation(engine, id)
            }
        }
        let needHuman = ids.contains { isHumanDecider($0) }
        async let human: HumanAnswer? = needHuman ? askHuman(.situation(final: stances != nil)) : nil
        let llm = await runJobs(jobs, phase: GamePhase.situation.label(engine.lang), maxTokens: 3000)
        for (id, obj) in llm {
            if let obj, let d = Prompting.parseSituation(obj) { out[id] = d } else {
                var d = RuleBot.situation(engine, id)
                d.fallback = true
                out[id] = d
            }
        }
        if let h = await human, case .situation(let d) = h, let hid = humanId { out[hid] = d }
        return out
    }

    func runTasks() async {
        let present = engine.state.presentParticipants
        var out: [String: TaskDecision] = [:]
        var taken: [String: Int] = [:]
        plannedTasks = [:]
        let needHuman = present.contains { isHumanDecider($0) }
        async let human: HumanAnswer? = needHuman ? askHuman(.tasks) : nil

        // Rule bots decide instantly, leader first.
        for id in present.sorted(by: { a, _ in a == engine.state.leader }) where !isHumanDecider(id) {
            if case .llm = engine.controller(id) { continue }
            let d = RuleBot.task(engine, id, taken: taken)
            out[id] = d
            taken[d.task, default: 0] += 1
            plannedTasks[id] = d
        }
        // LLM leader first so the others can hear the plan, then the rest in parallel.
        let llmIds = present.filter { id in
            if isHumanDecider(id) { return false }
            if case .llm = engine.controller(id) { return true }
            return false
        }
        // Fast pace: everyone at once, and tonight's moves in the same call.
        let fast = engine.state.setup.fastPace ?? false
        earlyNight = [:]
        let waves: [[String]] = {
            if !fast, let l = engine.state.leader, llmIds.contains(l) { return [[l], llmIds.filter { $0 != l }] }
            return [llmIds]
        }()
        for wave in waves where !wave.isEmpty {
            var jobs: [(String, ModelRef, String, String)] = []
            for id in wave {
                guard case .llm(let seat, _) = engine.controller(id), let ref = ModelRef(seatId: seat) else { continue }
                let prompt = fast ? Prompting.dayAndNight(engine, id, planned: plannedTasks) : Prompting.tasks(engine, id, planned: plannedTasks)
                jobs.append((id, ref, Prompting.system(engine, id), prompt))
            }
            let res = await runJobs(jobs, phase: GamePhase.tasks.label(engine.lang), maxTokens: fast ? 4000 : 3000)
            for (id, obj) in res {
                var d: TaskDecision
                if let obj, let parsed = Prompting.parseTask(obj) { d = parsed } else {
                    d = RuleBot.task(engine, id, taken: taken)
                    d.fallback = true
                }
                if fast, let obj, ["whispers", "secret", "motion", "diary", "日记", "huddle", "gift"].contains(where: { obj[$0] != nil }) {
                    var n = Prompting.parseNight(obj)
                    n.thought = nil   // the one thought belongs to the day's decision
                    earlyNight[id] = n
                }
                out[id] = d
                taken[d.task, default: 0] += 1
                plannedTasks[id] = d
            }
        }
        if let h = await human, case .tasks(let d) = h, let hid = humanId { out[hid] = d }
        if stopped { return }
        engine.resolveTasks(out)
        plannedTasks = [:]
        sync()
    }

    func runNight() async {
        let present = engine.state.presentParticipants
        var out: [String: NightDecision] = [:]
        var jobs: [(String, ModelRef, String, String)] = []
        for id in present where !isHumanDecider(id) {
            if case .llm = engine.controller(id), var early = earlyNight[id] {
                // chosen this morning: whispers to, or motions against, anyone who died or left since don't happen
                let here = Set(present)
                early.whispers.removeAll { !here.contains($0.to) }
                if let t = early.motion?.target, !here.contains(t) { early.motion = nil }
                // the huddle partner or the gift's recipient may be anyone still here (NPCs included)
                let around = Set(engine.state.characters.filter { $0.alive && $0.present }.map(\.id))
                if let h = early.huddle, !around.contains(h), engine.state.characters.first(where: { engine.name($0.id) == h }) == nil { early.huddle = nil }
                if let g = early.gift, !around.contains(g.to), engine.state.characters.first(where: { engine.name($0.id) == g.to }) == nil { early.gift = nil }
                out[id] = early
            } else if case .llm(let seat, _) = engine.controller(id), let ref = ModelRef(seatId: seat) {
                jobs.append((id, ref, Prompting.system(engine, id), Prompting.night(engine, id)))
            } else {
                out[id] = RuleBot.night(engine, id)
            }
        }
        let needHuman = present.contains { isHumanDecider($0) }
        async let human: HumanAnswer? = needHuman ? askHuman(.night) : nil
        let res = await runJobs(jobs, phase: GamePhase.night.label(engine.lang), maxTokens: 3500)
        for (id, obj) in res {
            if let obj { out[id] = Prompting.parseNight(obj) } else {
                var d = RuleBot.night(engine, id)
                d.fallback = true
                out[id] = d
            }
        }
        if let h = await human, case .night(let d) = h, let hid = humanId { out[hid] = d }
        earlyNight = [:]
        if stopped { return }
        engine.resolveNight(out)
        sync()
    }

    // MARK: LLM calls

    /// One model call with a real wall-clock limit (queueing and the client's own retries included).
    /// When the limit passes the request is cancelled and the rule AI takes that step.
    func completeWithin(_ seconds: Double, seat: String? = nil, profile: ProviderProfile, model: String, system: String, user: String, maxTokens: Int) async throws -> LLMResult {
        let client = self.client
        return try await withThrowingTaskGroup(of: LLMResult.self) { group in
            group.addTask {
                try await client.complete(profile: profile, model: model, system: system, user: user, jsonMode: true, maxTokens: maxTokens, temperature: profile.temperature)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw CallTimeout(seconds: seconds)
            }
            if let seat {
                // the player pressed "don't wait": checked four times a second
                group.addTask { @MainActor [weak self] in
                    while true {
                        try await Task.sleep(nanoseconds: 250_000_000)
                        if self?.skipRequested.contains(seat) ?? true { throw CallSkipped() }
                    }
                }
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw CallTimeout(seconds: seconds) }
            return first
        }
    }

    func runJobs(_ jobs: [(String, ModelRef, String, String)], phase: String, maxTokens: Int) async -> [(String, [String: Any]?)] {
        guard !jobs.isEmpty else { return [] }
        let now = Date()
        for j in jobs {
            thinking.insert(j.0)
            thinkingSince[j.0] = now
            skipRequested.remove(j.0)
        }
        var results: [(String, [String: Any]?)] = []
        await withTaskGroup(of: (String, [String: Any]?).self) { group in
            for j in jobs {
                group.addTask { @MainActor in
                    let obj = await self.call(id: j.0, ref: j.1, system: j.2, user: j.3, phase: phase, maxTokens: maxTokens)
                    return (j.0, obj)
                }
            }
            for await r in group {
                thinking.remove(r.0)
                thinkingSince[r.0] = nil
                skipRequested.remove(r.0)
                results.append(r)
            }
        }
        return results
    }

    func call(id: String, ref: ModelRef, system: String, user: String, phase: String, maxTokens: Int) async -> [String: Any]? {
        let label = config.label(for: ref)
        guard let profile = config.provider(ref.providerId) else {
            lastError = L("找不到模型配置：\(label)", "No model settings found for \(label)")
            return nil
        }
        // Hybrid/always-on reasoning models spend tokens thinking before the JSON; give them more room.
        // (Only generated tokens are billed, so a high ceiling costs nothing for models that stop early.)
        let reasoning = ["reasoner", "thinking", "r1", "qwq", "o1", "o3", "o4", "gpt-5", "glm-4.5", "glm-4.6", "glm-z1", "qwen3", "k2-thinking"].contains { ref.model.lowercased().contains($0) }
        let tokens = reasoning ? max(maxTokens, 8000) : maxTokens
        var prompt = user
        for attempt in 0..<2 {
            do {
                let r = try await completeWithin(config.callTimeoutSeconds, seat: id, profile: profile, model: ref.model, system: system, user: prompt, maxTokens: tokens)
                var u = usage[label] ?? SeatUsage()
                u.calls += 1
                u.inputTokens += r.inputTokens
                u.outputTokens += r.outputTokens
                u.seconds += r.seconds
                usage[label] = u
                engine.mutate(id) { $0.stats.llmCalls += 1 }
                record(LLMCallRecord(character: id, model: label, phase: phase, round: engine.state.round, prompt: config.logPrompts ? system + "\n\n" + prompt : String(prompt.suffix(1500)), response: r.text, seconds: r.seconds, inputTokens: r.inputTokens, outputTokens: r.outputTokens, error: nil))
                if let obj = JSONExtract.object(from: r.text) { return obj }
                if attempt == 0 {
                    prompt = user + engine.L("\n\n（注意：你上一次的回答不是合法的 JSON。这一次只输出一个 JSON 对象，不要任何其他文字。）",
                                             "\n\n(Note: your last answer was not valid json. This time output a single JSON object and nothing else.)")
                }
            } catch {
                if stopped || Task.isCancelled { return nil }
                if error is CallSkipped {
                    // the player's choice, not the model's failure
                    record(LLMCallRecord(character: id, model: label, phase: phase, round: engine.state.round, prompt: String(prompt.suffix(1500)), response: "", seconds: 0, inputTokens: 0, outputTokens: 0, error: "skipped"))
                    return nil
                }
                var u = usage[label] ?? SeatUsage()
                u.failures += 1
                usage[label] = u
                engine.mutate(id) { $0.stats.llmFailures += 1 }
                let why = Redact.text("\(error)")
                lastError = L("\(engine.name(id))（\(label)）调用失败：\(why)", "Call for \(engine.name(id)) (\(label)) failed: \(why)")
                record(LLMCallRecord(character: id, model: label, phase: phase, round: engine.state.round, prompt: String(prompt.suffix(1500)), response: "", seconds: 0, inputTokens: 0, outputTokens: 0, error: why))
                // waiting the full limit a second time would only double the stall
                if error is CallTimeout || (error as? URLError)?.code == .timedOut { break }
                if let e = error as? LLMError, let st = e.status, [401, 403, 404].contains(st) { return nil }
            }
        }
        return nil
    }

    func record(_ r: LLMCallRecord) {
        callLog.append(r)
        if callLog.count > 300 { callLog.removeFirst(callLog.count - 300) }
    }

    public func clearError() { lastError = nil }

    /// The difficulty button works in ordinary games that are still running.
    public var canChangeDifficulty: Bool {
        !engine.scenario.isTutorial && state.setup.chapter == nil && state.phase != .ended && !finished
    }

    /// Changes how hard the world is, from now on (the button in the top bar).
    public func setDifficulty(_ level: Difficulty) {
        guard canChangeDifficulty, level != state.setup.level else { return }
        engine.changeDifficulty(to: level)
        sync()
    }

    /// Stop waiting for the seats still thinking: the rule AI takes this step for them.
    public func skipThinking() {
        skipRequested.formUnion(thinking)
    }

    /// Director mode (spectator): force a scenario event at the start of the next round.
    public func injectEvent(_ id: String) {
        guard engine.scenario.event(id) != nil, !engine.isOver else { return }
        engine.state.scheduled.removeAll { $0.eventId == id }
        engine.state.scheduled.append(ScheduledEvent(eventId: id, round: engine.state.round + 1, actor: nil, target: nil))
        engine.state.firedEvents[id] = nil
        injected = id
        sync()
    }

    public private(set) var injected: String?

    /// Events a director can schedule (short labels).
    public var directorEvents: [(id: String, label: String)] {
        engine.scenario.events.filter { $0.kind != "nominate" || $0.effects != nil }.map { ev in
            let someone = engine.L("某人", "someone")
            let t = engine.render(ev.text.replacingOccurrences(of: "{actor}", with: someone).replacingOccurrences(of: "{target}", with: someone), EffCtx())
            let short = t.count > 34 ? String(t.prefix(34)) + "…" : t
            return (ev.id, short)
        }
    }

    /// Advance the game with rule bots (used for UI previews and snapshots). Not for normal play.
    public func debugAdvance(_ steps: Int) {
        for _ in 0..<steps where !engine.isOver { AutoRunner.step(engine) }
        sync()
        if engine.isOver { finishGame() }
    }

    // MARK: Saving

    public static var autosaveURL: URL { AppPaths.saves.appendingPathComponent("autosave.json") }

    public struct SaveFile: Codable {
        public var gameId: String
        public var scenarioId: String
        public var state: GameState
        public var savedAt: Date
        /// Scenario title and round label at save time, in the game's language (for the save list).
        public var title: String?
        public var progress: String?
        /// Made with the save button (vs. the automatic save).
        public var manual: Bool?

        public var lang: Lang { state.setup.lang }
    }

    /// A save on disk.
    public struct SaveSlot: Identifiable {
        public var url: URL
        public var file: SaveFile
        public var isAutosave: Bool
        public var id: String { url.lastPathComponent }
    }

    func makeSaveFile(manual: Bool) -> SaveFile {
        SaveFile(gameId: gameId, scenarioId: scenario.id, state: engine.state, savedAt: Date(),
                 title: scenario.title, progress: "\(engine.roundLabel) · \(engine.clockLabel)", manual: manual)
    }

    func autosave() {
        if let o = autosaveOverride { o(engine.state); return }
        if let data = try? JSONEncoder().encode(makeSaveFile(manual: false)) {
            try? data.write(to: GameSession.autosaveURL, options: .atomic)
        }
    }

    /// Manual saves live here, one file each.
    public static var slotsDirectory: URL {
        let d = AppPaths.saves.appendingPathComponent("Slots", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Writes the current game as a new manual save.
    @discardableResult
    public func saveToSlot() -> URL? {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        let url = GameSession.slotsDirectory.appendingPathComponent("\(AppPaths.safeName(scenario.id))-r\(engine.state.round)-\(f.string(from: Date())).json")
        guard let data = try? JSONEncoder().encode(makeSaveFile(manual: true)) else { return nil }
        do { try data.write(to: url, options: .atomic) } catch { return nil }
        return url
    }

    /// All saves, newest first (the automatic save included).
    public static func listSaves() -> [SaveSlot] {
        var out: [SaveSlot] = []
        let dec = JSONDecoder()
        if let a = loadAutosave() { out.append(SaveSlot(url: autosaveURL, file: a, isAutosave: true)) }
        let files = (try? FileManager.default.contentsOfDirectory(at: slotsDirectory, includingPropertiesForKeys: nil)) ?? []
        for u in files where u.pathExtension == "json" {
            if let d = try? Data(contentsOf: u), let f = try? dec.decode(SaveFile.self, from: d) {
                out.append(SaveSlot(url: u, file: f, isAutosave: false))
            }
        }
        return out.sorted { $0.file.savedAt > $1.file.savedAt }
    }

    public static func deleteSave(_ slot: SaveSlot) {
        AppPaths.trash(slot.url)
    }

    public static func loadAutosave() -> SaveFile? {
        guard let data = try? Data(contentsOf: autosaveURL) else { return nil }
        guard let save = try? JSONDecoder().decode(SaveFile.self, from: data) else {
            // the next game would overwrite it: keep a copy first
            AppPaths.keepUnreadable(autosaveURL)
            return nil
        }
        return save
    }

    public static func clearAutosave() {
        try? FileManager.default.removeItem(at: autosaveURL)
    }

    func finishGame() {
        guard !finished else { return }
        finished = true
        sync()
        if let o = autosaveOverride { o(engine.state) } else { GameSession.clearAutosave() }
        let md = Transcript.markdown(engine, godView: true)
        let url = AppPaths.logs.appendingPathComponent("\(AppPaths.safeName(gameId)).md")
        try? md.write(to: url, atomically: true, encoding: .utf8)
        savedTranscript = url
        // Raw LLM calls (for debugging prompts and model behavior)
        if !callLog.isEmpty {
            var lines: [String] = []
            for c in callLog {
                let obj: [String: Any] = ["round": c.round, "phase": c.phase, "character": c.character, "model": c.model,
                                          "seconds": c.seconds, "in": c.inputTokens, "out": c.outputTokens,
                                          "error": Redact.text(c.error ?? ""), "response": Redact.text(c.response), "prompt_tail": Redact.text(c.prompt)]
                if let d = try? JSONSerialization.data(withJSONObject: obj), let line = String(data: d, encoding: .utf8) { lines.append(line) }
            }
            try? lines.joined(separator: "\n").write(to: AppPaths.logs.appendingPathComponent("\(AppPaths.safeName(gameId))-calls.jsonl"), atomically: true, encoding: .utf8)
        }
        // the tutorial doesn't count towards the leaderboard or the endings gallery
        if scenario.isTutorial { return }
        var store = ModelStatsStore.load()
        store.record(engine: engine, config: config, usage: usage)
        store.save()
        if let end = engine.state.ending {
            var gallery = EndingGallery.load()
            gallery.unlock(scenario: scenario.id, ending: end.id)
            gallery.save()
        }
    }
}

// MARK: - Model leaderboard

public struct ModelRecord: Codable, Sendable, Identifiable {
    public var id: String
    public var games = 0
    public var survived = 0
    public var goals = 0
    public var score = 0
    public var thefts = 0
    public var caught = 0
    public var motions = 0
    public var exileVotes = 0
    public var roundsLed = 0
    public var exiled = 0
    public var calls = 0
    public var failures = 0
    /// Certificate exams sat in endless mode (optional: older leaderboards don't have them).
    public var examsTaken: Int?
    public var examsPassed: Int?
    public var examCorrect: Int?
    public var examQuestions: Int?

    public init(id: String) { self.id = id }

    public var examAccuracy: Double? {
        guard let q = examQuestions, q > 0 else { return nil }
        return Double(examCorrect ?? 0) / Double(q)
    }

    public var survivalRate: Double { games == 0 ? 0 : Double(survived) / Double(games) }
    public var avgScore: Double { games == 0 ? 0 : Double(score) / Double(games) }
}

public struct ModelStatsStore: Codable, Sendable {
    public var records: [String: ModelRecord] = [:]
    public var games = 0

    public init() {}

    /// Record keys for non-model seats (kept stable across languages).
    public static let humanKey = "玩家（你）"
    /// Storage key of the basic bots in the leaderboard (kept as it was when they were called 规则AI, so old stats still count).
    public static let ruleKey = "规则AI"

    /// Display name of a record key.
    public static func displayName(_ key: String) -> String {
        switch key {
        case humanKey: return L("玩家（你）", "Player (you)")
        case ruleKey: return L("基础人机", "Basic bot")
        default: return key
        }
    }

    public static var url: URL { AppPaths.support.appendingPathComponent("leaderboard.json") }

    public static func load() -> ModelStatsStore {
        guard let d = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(ModelStatsStore.self, from: d) else { return ModelStatsStore() }
        return s
    }

    public func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(self) { try? d.write(to: ModelStatsStore.url, options: .atomic) }
    }

    /// An LLM player sat a certificate exam.
    public mutating func recordExam(key: String, record: ExamRecord) {
        var rec = records[key] ?? ModelRecord(id: key)
        rec.examsTaken = (rec.examsTaken ?? 0) + 1
        if record.passed { rec.examsPassed = (rec.examsPassed ?? 0) + 1 }
        rec.examCorrect = (rec.examCorrect ?? 0) + record.score
        rec.examQuestions = (rec.examQuestions ?? 0) + record.total
        records[key] = rec
    }

    public mutating func record(engine: GameEngine, config: AppConfig, usage: [String: SeatUsage]) {
        guard let end = engine.state.ending else { return }
        games += 1
        for r in end.results {
            let key: String
            switch engine.controller(r.id) {
            case .llm(let seat, let label): key = ModelRef(seatId: seat).map { config.label(for: $0) } ?? label
            // stable keys (shown translated in the leaderboard)
            case .human: key = ModelStatsStore.humanKey
            case .rule: key = ModelStatsStore.ruleKey
            }
            var rec = records[key] ?? ModelRecord(id: key)
            rec.games += 1
            if r.survived { rec.survived += 1 }
            if r.goalAchieved { rec.goals += 1 }
            rec.score += r.score
            if let c = engine.state.character(r.id) {
                rec.thefts += c.stats.thefts
                rec.caught += c.stats.caught
                rec.motions += c.stats.motions
                rec.exileVotes += c.stats.exileVotes
                rec.roundsLed += c.stats.roundsLed
                rec.calls += c.stats.llmCalls
                rec.failures += c.stats.llmFailures
                if c.status == .exiled { rec.exiled += 1 }
            }
            records[key] = rec
        }
    }
}


// MARK: - Ending gallery

/// Which endings the player has seen, per scenario.
public struct EndingGallery: Codable, Sendable {
    public var unlocked: [String: [String]] = [:]

    public init() {}

    public static var url: URL { AppPaths.support.appendingPathComponent("endings.json") }

    public static func load() -> EndingGallery {
        guard let d = try? Data(contentsOf: url), let g = try? JSONDecoder().decode(EndingGallery.self, from: d) else { return EndingGallery() }
        return g
    }

    public func save() {
        if let d = try? JSONEncoder().encode(self) { try? d.write(to: EndingGallery.url, options: .atomic) }
    }

    public mutating func unlock(scenario: String, ending: String) {
        var list = unlocked[scenario] ?? []
        if !list.contains(ending) { list.append(ending) }
        unlocked[scenario] = list
    }

    public func has(_ scenario: String, _ ending: String) -> Bool {
        unlocked[scenario]?.contains(ending) ?? false
    }
}

/// The player stopped waiting for a model call.
public struct CallSkipped: Error, CustomStringConvertible {
    public var description: String { L("玩家没有等它", "skipped by the player") }
}

/// A model call that took longer than the configured limit.
public struct CallTimeout: Error, CustomStringConvertible {
    public let seconds: Double
    public var description: String { L("超过 \(Int(seconds)) 秒没有回答", "no answer within \(Int(seconds)) s") }
}
