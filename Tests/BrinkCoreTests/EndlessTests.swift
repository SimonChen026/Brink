import XCTest
@testable import BrinkCore

/// Endless mode: growth rules, chapters, runs, exams, saves (D-035 – D-040).
final class EndlessTests: XCTestCase {

    func testProgressionMath() {
        XCTAssertEqual(Progression.xpAt(1), 0)
        XCTAssertEqual(Progression.xpAt(2), 100)
        XCTAssertEqual(Progression.xpAt(5), 1000)
        XCTAssertEqual(Progression.level(forXP: 299), 2)
        XCTAssertEqual(Progression.level(forXP: 300), 3)

        var p = RunPlayer(id: "p1", persona: Persona(name: "A", female: false, age: 30, weight: 70, fat: 0.18, temperament: "steady"),
                          seat: "rule", controllerLabel: "Rule AI", resolve: 3, joinedChapter: 1)
        XCTAssertEqual(p.gain(1000), 4)                       // L1 → L5
        XCTAssertEqual(p.points, 1 + 1 + 1 + 2)               // L5 gives 2
        p.raise("medical"); p.raise("medical")                // costs 1 + 2
        XCTAssertEqual(p.rank("medical"), 2)
        XCTAssertEqual(p.points, 2)
        p.raise("strength")                                   // not trainable
        XCTAssertEqual(p.rank("strength"), 0)
        p.lower("medical")
        XCTAssertEqual(p.rank("medical"), 1)
        XCTAssertEqual(p.points, 4)

        // practice: 20 points → a free rank in survival; ranks from practice can't be refunded for points
        let up = p.addPractice(["survival": 25])
        XCTAssertEqual(up, ["survival"])
        XCTAssertEqual(p.rank("survival"), 1)
        XCTAssertFalse(p.canLower("survival"))
    }

    func scenarios() -> [Scenario] { ScenarioLibrary.loadAll().scenarios }

    func testChapterBuildAppliesPlayerGrowth() throws {
        let all = scenarios()
        let base = try XCTUnwrap(all.first { $0.id == "snowline" })
        var run = EndlessRun.new(seats: (0..<5).map { SeatSpec(seat: $0 == 0 ? "human" : "rule", label: "x") }, options: RunOptions(), lang: .zh, seed: 5)
        run.update("p1") { $0.ranks = ["medical": 3, "survival": 1]; $0.certs = [CertRecord(id: "cold", interlude: 0, score: 9, total: 10)] }
        let cold = CertificateDef(id: "cold", skill: "survival", bonus: 1, perk: "warm", requires: [], minLevel: 1, count: 10, pass: 8, icon: "", color: "",
                                  zh: CertText(name: "寒区", full: "", desc: "", realWorld: ""), en: CertText(name: "Cold", full: "", desc: "", realWorld: ""), questions: [])
        let plan = run.makePlan(base, humanRole: "lin", library: [cold])
        XCTAssertEqual(plan.cast["lin"]?.playerId, "p1")
        let built = EndlessRun.buildScenario(base, plan: plan, lang: .zh)
        let lin = try XCTUnwrap(built.character("lin"))
        let orig = try XCTUnwrap(base.character("lin"))
        XCTAssertEqual(lin.skill("medical"), min(5, orig.skill("medical") + 3))
        XCTAssertEqual(lin.skill("survival"), min(5, orig.skill("survival") + 1 + 1))
        XCTAssertEqual(lin.skill("strength"), orig.skill("strength"))
        XCTAssertEqual(lin.perks, ["warm"])
        XCTAssertEqual(lin.clo, orig.clo + 0.3, accuracy: 1e-9)
        XCTAssertEqual(Set(plan.cast.values.map(\.playerId)), Set(run.active.map(\.id)))
        // rebuilding from the same plan is identical (resuming a saved chapter)
        let again = EndlessRun.buildScenario(base, plan: plan, lang: .zh)
        XCTAssertEqual(again.characters.map { $0.skills }, built.characters.map { $0.skills })
    }

    func testRunsAreDeterministicAndLanguageIndependent() {
        let all = scenarios()
        let lib = ExamLibrary.all()
        func signature(_ lang: Lang) -> [String] {
            let r = EndlessSim.play(seed: 17, lang: lang, maxChapters: 9, scenarios: all, library: lib)
            return r.history.map { h in "\(h.scenarioId)|\(h.cleared)|" + h.lines.map { "\($0.playerId):\($0.survived)" }.joined(separator: ",") }
                + r.players.map { "\($0.id):L\($0.level):xp\($0.xp):r\($0.resolve):c\($0.certs.map(\.id).joined(separator: "+"))" }
        }
        let a = signature(.zh)
        XCTAssertFalse(a.isEmpty)
        XCTAssertEqual(a, signature(.zh), "same seed must replay the same run")
        XCTAssertEqual(a, signature(.en), "a run must play the same in both languages")
    }

    func testNormalModeNeverThrowsAnyoneOutOfADrill() {
        let all = scenarios()
        for seed in UInt64(1)...UInt64(6) {
            let r = EndlessSim.play(seed: seed, maxChapters: 8, scenarios: all, library: ExamLibrary.all())
            XCTAssertEqual(r.history.count, 8)
            XCTAssertTrue(r.players.allSatisfy { !$0.out }, "seed \(seed): nobody leaves in normal mode")
            XCTAssertEqual(Set(r.played).count, 8, "each drill is played once")
            XCTAssertTrue(r.players.allSatisfy { $0.level >= 2 }, "everyone levels up over eight drills")
        }
    }

    func testIronModeCanEndTheRun() {
        let all = scenarios()
        var ended = 0
        for seed in UInt64(1)...UInt64(12) {
            let r = EndlessSim.play(seed: seed, hardcore: true, maxChapters: 8, scenarios: all, library: ExamLibrary.all())
            if r.phase == .ended, r.grand?.id == "unfinished" { ended += 1; XCTAssertTrue(r.human?.out ?? false) }
        }
        XCTAssertGreaterThan(ended, 0)
    }

    func testRunSaveRoundTrip() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("brink-run-\(UUID().uuidString)")
        let previousHome = ProcessInfo.processInfo.environment["BRINK_HOME"]
        setenv("BRINK_HOME", tmp.path, 1)
        // put back whatever was there (a test run may itself be sandboxed with BRINK_HOME)
        defer { if let h = previousHome { setenv("BRINK_HOME", h, 1) } else { unsetenv("BRINK_HOME") }; try? FileManager.default.removeItem(at: tmp) }
        let all = scenarios()
        let base = try XCTUnwrap(all.first { $0.id == "rubble" })
        var run = EndlessRun.new(seats: (0..<5).map { SeatSpec(seat: $0 == 0 ? "human" : "rule", label: "x") }, options: RunOptions(), lang: .en, seed: 9)
        let localized = ScenarioLibrary.localized(base, lang: .en)
        let plan = run.makePlan(localized, humanRole: nil, library: [])
        run.begin(plan)
        let sc = EndlessRun.buildScenario(localized, plan: plan, lang: .en)
        let engine = GameEngine(scenario: sc, setup: run.setup(for: plan, scenario: sc, library: []))
        for _ in 0..<6 { AutoRunner.step(engine) }
        RunStore.save(run, chapterState: engine.state)
        let loaded = try XCTUnwrap(RunStore.latestActive())
        XCTAssertEqual(loaded.run.id, run.id)
        XCTAssertEqual(loaded.run.phase, .chapter)
        XCTAssertEqual(loaded.run.lang, .en)
        let st = try XCTUnwrap(loaded.chapterState)
        XCTAssertEqual(st.round, engine.state.round)
        XCTAssertEqual(st.setup.chapter?.number, 1)
        // resume: rebuild the chapter's scenario from the saved plan and play on
        let rebuilt = EndlessRun.buildScenario(localized, plan: try XCTUnwrap(loaded.run.current), lang: .en)
        let resumed = GameEngine(scenario: rebuilt, state: st)
        AutoRunner.playToEnd(resumed)
        AutoRunner.playToEnd(engine)
        XCTAssertEqual(resumed.state.ending?.id, engine.state.ending?.id)
        var r2 = loaded.run
        XCTAssertNotNil(r2.complete(resumed, library: []))
        XCTAssertEqual(r2.phase, .hub)
        XCTAssertEqual(r2.history.count, 1)
    }

    func testExamDrawGradeAndParse() {
        var qs: [ExamQuestion] = []
        for i in 0..<14 {
            let t = QText(q: "q\(i)", options: ["a", "b", "c", "d"], explain: "e")
            qs.append(ExamQuestion(id: "t\(i)", answer: i % 4, hard: i < 4, source: nil, zh: t, en: t))
        }
        let cert = CertificateDef(id: "t", skill: "medical", bonus: 1, perk: nil, requires: [], minLevel: 1, count: 10, pass: 8, icon: "", color: "",
                                  zh: CertText(name: "t", full: "t", desc: "", realWorld: ""), en: CertText(name: "t", full: "t", desc: "", realWorld: ""), questions: qs)
        let paper = Exams.draw(cert, seed: 42)
        XCTAssertEqual(paper.total, 10)
        XCTAssertEqual(Set(paper.items.map(\.questionId)).count, 10)
        XCTAssertGreaterThanOrEqual(paper.items.filter { cert.question($0.questionId)?.hard ?? false }.count, 4)
        let right = paper.items.map { Exams.correctPosition($0, cert) }
        XCTAssertEqual(Exams.grade(paper, cert, answers: right), 10)
        for (i, item) in paper.items.enumerated() {
            let q = cert.question(item.questionId)!
            XCTAssertEqual(item.order[right[i]], q.answer)
        }
        let letters = right.map { Exams.letters[$0] }
        let parsed = Exams.parseAnswers(["answers": letters, "comment": "ok"], count: 10)
        XCTAssertEqual(parsed.answers.compactMap { $0 }, right)
        XCTAssertEqual(parsed.comment, "ok")
        XCTAssertEqual(Exams.draw(cert, seed: 42).items.map(\.questionId), paper.items.map(\.questionId))
    }

    func testExamBanksLoadAndAreWellFormed() {
        let (certs, errors) = ExamLibrary.load()
        XCTAssertTrue(errors.isEmpty, errors.joined(separator: "\n"))
        XCTAssertEqual(certs.count, 12)
        for c in certs where !c.questions.isEmpty {
            XCTAssertEqual(ExamLibrary.check(c), [], c.id)
        }
    }

    func testEnglishRunTextHasNoChinese() throws {
        let all = scenarios()
        let lib = ExamLibrary.all()
        var run = EndlessSim.play(seed: 4, lang: .en, maxChapters: 3, scenarios: all, library: lib)
        // pretend seat 2 is an AI model, to get its career memory and its interlude prompt
        run.update("p2") { $0.seat = "cli::mock"; $0.controllerLabel = "mock" }
        let base = ScenarioLibrary.localized(try XCTUnwrap(all.first { $0.id == run.nextChoices.first }), lang: .en)
        let plan = run.makePlan(base, humanRole: nil, library: lib)
        let sc = EndlessRun.buildScenario(base, plan: plan, lang: .en)
        let setup = run.setup(for: plan, scenario: sc, library: lib)
        var texts: [String] = Array((setup.notes ?? [:]).values) + (setup.chapter?.mutators ?? [])
        XCTAssertFalse((setup.notes ?? [:]).isEmpty)
        texts.append(RunAI.planPrompt(run, "p2", lib))
        if let c = lib.first(where: { $0.questions.count >= $0.count }), let p = run.player("p2") {
            texts.append(Exams.userPrompt(RunAI.paper(run, p, c), c, playerName: p.name, .en))
        }
        for h in run.history { texts.append(h.title); texts.append(h.endingTitle); texts += h.lines.map { $0.fate + $0.characterName + $0.playerName } }
        if let r = run.lastReport { texts += r.players.values.flatMap { $0.breakdown.map(\.label) + [$0.fate] } }
        run.retire(library: lib)
        let g = try XCTUnwrap(run.grand)
        texts += [g.title, g.text] + g.recap + g.legacies.flatMap { [$0.title, $0.fate, $0.epilogue] + $0.certs }
        for t in texts { XCTAssertFalse(Loc.hasCJK(t), "Chinese in English run text: \(t.prefix(160))") }
        XCTAssertEqual(Set(g.legacies.map(\.epilogue)).count, g.legacies.count, "everyone's afterwards should read differently")
    }

    /// The right answer must not be guessable from its length (an easy tell for people and models alike).
    func testExamAnswersAreNotGivenAwayByLength() {
        for c in ExamLibrary.load().certs {
            for lang in [Lang.zh, .en] {
                let longest = c.questions.filter { q in
                    let lens = q.text(lang).options.map(\.count)
                    return lens[q.answer] == lens.max()! && lens.filter { $0 == lens.max()! }.count == 1
                }.count
                XCTAssertLessThanOrEqual(longest, max(3, c.questions.count / 3), "\(c.id) (\(lang.rawValue)): the correct option is the longest in \(longest)/\(c.questions.count)")
            }
        }
    }

    func testCertificationPapersAreHard() {
        for c in ExamLibrary.all() where c.questions.count >= Exams.certCount {
            let paper = Exams.drawCertification(c, seed: 77)
            XCTAssertEqual(paper.total, Exams.certCount, c.id)
            XCTAssertEqual(paper.pass(c), Exams.certPass)
            XCTAssertTrue(paper.isCertification)
            XCTAssertEqual(paper.timeLimit, Exams.certTimeLimit)
            XCTAssertEqual(Set(paper.items.map(\.questionId)).count, paper.total, "no repeats")
            let hard = paper.items.filter { c.question($0.questionId)?.hard ?? false }.count
            let available = c.questions.filter { $0.hard ?? false }.count
            XCTAssertGreaterThanOrEqual(hard, min(16, available), "\(c.id): a certification paper is mostly hard/expert")
            let experts = c.questions.filter { $0.expert ?? false }.count
            if experts >= 8 {
                XCTAssertGreaterThanOrEqual(paper.items.filter { c.question($0.questionId)?.expert ?? false }.count, 8, c.id)
            }
            // practice papers stay at 10
            XCTAssertEqual(Exams.draw(c, seed: 77).total, c.count)
        }
    }

    func testProfileCertificatesCooldownAndRuns() {
        var p = PlayerProfile()
        let t0 = Date(timeIntervalSince1970: 2_000_000_000)
        let cert = CertificateDef(id: "wfr", skill: "medical", bonus: 1, perk: nil, requires: ["firstaid"], minLevel: 3, count: 10, pass: 8, icon: "", color: "",
                                  zh: CertText(name: "w", full: "", desc: "", realWorld: ""), en: CertText(name: "w", full: "", desc: "", realWorld: ""),
                                  questions: (0..<36).map { i in ExamQuestion(id: "w\(i)", answer: 0, hard: true, expert: i < 12, source: "x",
                                                                              zh: QText(q: "q", options: ["a", "b", "c", "d"], explain: "e"),
                                                                              en: QText(q: "q", options: ["a", "b", "c", "d"], explain: "e")) })
        XCTAssertNotNil(p.lockReason(cert, lang: .zh, now: t0), "needs first aid first")
        XCTAssertTrue(p.record("firstaid", score: 19, total: 20, passed: true, source: "hall", now: t0))
        XCTAssertNil(p.lockReason(cert, lang: .zh, now: t0))
        XCTAssertFalse(p.record("wfr", score: 17, total: 20, passed: false, source: "hall", now: t0))
        XCTAssertNotNil(p.cooldownUntil("wfr", now: t0.addingTimeInterval(3600)), "a failed attempt locks the certificate for a while")
        XCTAssertNil(p.cooldownUntil("wfr", now: t0.addingTimeInterval(Exams.cooldownHours * 3600 + 1)))
        XCTAssertFalse(p.record("firstaid", score: 20, total: 20, passed: true, source: "run", now: t0), "a certificate is granted once")
        XCTAssertEqual(p.certs.count, 1)
        XCTAssertTrue(p.held("firstaid")?.serial.hasPrefix("BRK-FIR-") ?? false)
        // held certificates come along into a new run, for the human only
        let run = EndlessRun.new(seats: (0..<5).map { SeatSpec(seat: $0 == 0 ? "human" : "rule", label: "x") }, options: RunOptions(), lang: .zh, seed: 1, humanCerts: p.certs)
        XCTAssertTrue(run.human?.has("firstaid") ?? false)
        XCTAssertFalse(run.players.filter { !$0.isHuman }.contains { $0.has("firstaid") })
    }

    func testRecordExamGivesCertificateAndPoints() {
        var run = EndlessRun.new(seats: (0..<5).map { SeatSpec(seat: $0 == 0 ? "human" : "rule", label: "x") }, options: RunOptions(), lang: .zh, seed: 3)
        let psych = CertificateDef(id: "psych", skill: "social", bonus: 1, perk: "calm", requires: [], minLevel: 1, count: 10, pass: 8, icon: "", color: "",
                                   zh: CertText(name: "p", full: "", desc: "", realWorld: ""), en: CertText(name: "p", full: "", desc: "", realWorld: ""), questions: [])
        run.recordExam("p1", ExamRecord(certId: "psych", interlude: 0, score: 10, total: 10, passed: true, by: "human", answers: nil, paper: nil, note: nil), library: [psych])
        let p = run.player("p1")!
        XCTAssertTrue(p.has("psych"))
        XCTAssertEqual(p.points, 3, "perfect: 3 points (70 XP is not yet a level)")
        XCTAssertEqual(p.xp, 70)
        XCTAssertEqual(p.maxResolve, 4)
        XCTAssertTrue(run.examUsed("p1"))
        XCTAssertEqual(p.bonus("social", [psych]), 1)
        XCTAssertEqual(p.perks([psych]), ["calm"])
    }
}
