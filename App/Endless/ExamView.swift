import SwiftUI
import BrinkCore

/// Sitting an exam:
/// - `.practice`: the exam room — any certificate, 10 questions, the explanation right after each answer, no certificate;
/// - `.certify`: a certification from the "我" page — 20 mostly expert questions, 19 to pass, 40 s each, results at the end;
/// - `.run`: a certification between chapters of a run (counts for the run and for "我").
struct ExamView: View {
    enum Mode: Equatable {
        case run(playerId: String)
        case practice
        case certify(certId: String)
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismissSheet
    let mode: Mode
    /// When shown as a screen (the exam room) instead of a sheet.
    var onClose: (() -> Void)? = nil
    /// Snapshots: open straight on a certificate, optionally with the first answer given.
    var preset: String? = nil
    var presetAnswer: Int? = nil

    func dismiss() { if let onClose { onClose() } else { dismissSheet() } }

    @State private var cert: CertificateDef?
    @State private var paper: ExamPaper?
    @State private var index = 0
    @State private var answers: [Int?] = []
    @State private var chosen: Int?
    @State private var finished = false
    @State private var deadline = Date()
    @State private var newlyHeld = false
    @State private var confirmLeave = false

    var lang: Lang {
        if case .run = mode, let r = model.run { return r.lang }
        return model.uiLang
    }

    var certifying: Bool { paper?.isCertification ?? (mode != .practice) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cert.map { $0.text(lang).full } ?? (mode == .practice ? L("考场 · 练习", "Exam room · practice") : L("资格认证", "Certification")))
                        .font(Theme.title(24))
                    if cert != nil {
                        Text(certifying ? L("资格认证 · 20 题 · 对 19 题通过 · 每题 40 秒", "Certification · 20 questions · 19 to pass · 40 s each")
                                        : L("练习 · 不发证书", "Practice · no certificate"))
                            .font(.system(size: 11)).foregroundStyle(certifying ? Theme.flare : Theme.dim)
                    }
                }
                Spacer()
                if let p = paper, !finished {
                    Text("\(index + 1) / \(p.total)").font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.dim)
                }
                Button(L("关闭", "Close")) {
                    // walking out of a certification counts as handing it in: ask first
                    if let p = paper, p.isCertification, !finished, answers.contains(where: { $0 != nil }) || index > 0 {
                        confirmLeave = true
                    } else {
                        dismiss()
                    }
                }
                .buttonStyle(GhostButtonStyle())
                .keyboardShortcut(.cancelAction)
                .alert(L("现在离开就算交卷", "Leaving now hands the paper in"), isPresented: $confirmLeave) {
                    Button(L("交卷离开", "Hand in and leave"), role: .destructive) { dismiss() }
                    Button(L("继续答题", "Keep going"), role: .cancel) {}
                } message: {
                    Text(L("已经答的题照常算分，没答的算错。", "Answered questions count as usual; the rest count as wrong."))
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 16)
            Divider()
            Group {
                if let cert, let paper {
                    if finished { result(cert, paper) } else if paper.isCertification { certQuestion(cert, paper) } else { practiceQuestion(cert, paper) }
                } else {
                    picker
                }
            }
            .padding(26)
        }
        .background(Theme.bg)
        .onDisappear {
            // Walking out of a certification halfway still counts as the attempt (no peeking at the paper).
            if let cert, let paper, paper.isCertification, !finished, answers.contains(where: { $0 != nil }) || index > 0 {
                submit(cert, paper)
            }
        }
        .onAppear {
            if case .certify(let id) = mode, cert == nil, let c = model.library.first(where: { $0.id == id }) { begin(c) }
            if let id = preset, cert == nil, let c = model.library.first(where: { $0.id == id }) {
                begin(c)
                if let a = presetAnswer { chosen = a; answers[0] = a }
            }
        }
    }

    // MARK: Choosing a certificate (practice, or a run's interlude)

    var picker: some View {
        let lib = model.library
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if case .run(let pid) = mode, let r = model.run, let p = r.player(pid) {
                    Text(L("资格认证很难：20 道题，大多是考官级的难题，对 19 道才算通过，每题限时 40 秒，交卷后才公布对错。开始答题后中途离开也算考过一次。通过后：对应技能 +1，技能点 +2（满分再 +1），经验 +50（满分 +70），证书也会记进“我”。这次考完，下一关之后才能再考。你现在 Lv\(p.level)。",
                           "Certification is hard: 20 questions, mostly examiner-level, 19 to pass, 40 seconds each, results only at the end. Once you start, leaving halfway still counts as your attempt. A pass gives +1 to its skill, +2 skill points (+1 more for a perfect score), +50 XP (+70 for perfect), and the certificate goes on your “Me” page too. After this one, the next exam comes after the next chapter. You're Lv \(p.level)."))
                        .font(.system(size: 13)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(L("练习不计入征程，不发证书：每套 10 题，答完每题马上看解析和出处。想拿证，到“我”里参加资格认证（20 题、对 19 题才通过）。",
                           "Practice doesn't count and gives no certificate: 10 questions a paper, with the explanation and source right after each answer. For the real certificate, take the certification from your “Me” page (20 questions, 19 to pass)."))
                        .font(.system(size: 13)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                }
                if mode == .practice { BenchPanel() }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 10)], spacing: 10) {
                    ForEach(lib) { c in certCard(c) }
                }
            }
        }
    }

    func lockReason(_ c: CertificateDef) -> String? {
        if case .run(let pid) = mode, let r = model.run {
            if let reason = r.lockReason(pid, c) { return reason }
            return c.questions.count < Exams.certCount ? L("题库还没准备好", "Question bank not ready") : nil
        }
        return c.questions.count < c.count ? L("题库还没准备好", "Question bank not ready") : nil
    }

    func certCard(_ c: CertificateDef) -> some View {
        let lock = lockReason(c)
        let color = Color(hex: c.color) ?? Theme.flare
        let t = c.text(lang)
        let best = UserDefaults.standard.integer(forKey: "practiceBest.\(c.id)")
        let held = model.profile.has(c.id)
        return Button {
            guard lock == nil else { return }
            begin(c)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: c.icon).foregroundStyle(color).font(.system(size: 18))
                    Text(t.name).font(.system(size: 15, weight: .semibold))
                    if held && mode == .practice { Image(systemName: "checkmark.seal.fill").foregroundStyle(color).help(L("你已经取得这张证", "You hold this certificate")) }
                    Spacer()
                    if let lock { Text(lock).font(.system(size: 11)).foregroundStyle(Theme.faint) }
                    else if mode == .practice && best > 0 { Text(L("最好 \(best)/\(c.count)", "best \(best)/\(c.count)")).font(.system(size: 11)).foregroundStyle(Theme.dim) }
                }
                Text(t.desc).font(.system(size: 12)).foregroundStyle(Theme.dim).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                Text(c.effectText(lang)).font(.system(size: 11, weight: .medium)).foregroundStyle(color.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
                Text(t.realWorld).font(.system(size: 10)).foregroundStyle(Theme.faint).lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(lock == nil ? color.opacity(0.5) : Theme.line.opacity(0.4), lineWidth: 1))
            .opacity(lock == nil ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(lock != nil)
    }

    func begin(_ c: CertificateDef) {
        cert = c
        switch mode {
        case .run(let pid):
            if let r = model.run, let p = r.player(pid) { paper = RunAI.paper(r, p, c) }
        case .certify:
            paper = Exams.drawCertification(c, seed: UInt64(Date().timeIntervalSince1970 * 1000) % 9_000_000 + 1)
        case .practice:
            paper = Exams.draw(c, seed: UInt64(Date().timeIntervalSince1970 * 1000) % 9_000_000 + 1)
        }
        answers = Array(repeating: nil, count: paper?.total ?? 0)
        index = 0
        chosen = nil
        finished = false
        newlyHeld = false
        deadline = Date().addingTimeInterval(TimeInterval(paper?.timeLimit ?? 0))
    }

    // MARK: Practice: the answer and the explanation right away

    func practiceQuestion(_ cert: CertificateDef, _ paper: ExamPaper) -> some View {
        let item = paper.items[index]
        let s = Exams.shown(item, cert, lang)
        let color = Color(hex: cert.color) ?? Theme.flare
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Meter(value: Double(index) / Double(paper.total), color: color, height: 4)
                HStack(spacing: 8) {
                    tags(cert, item)
                    Text(L("已答对 \(Exams.grade(paper, cert, answers: answers)) 题", "\(Exams.grade(paper, cert, answers: answers)) correct so far")).font(.system(size: 11)).foregroundStyle(Theme.faint)
                }
                Text(s.q).font(Theme.prose(19)).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 8) {
                    ForEach(Array(s.options.enumerated()), id: \.offset) { i, o in
                        optionButton(i, o, correct: s.correct, reveal: chosen != nil, selected: chosen == i) {
                            guard chosen == nil else { return }
                            chosen = i
                            answers[index] = i
                        }
                    }
                }
                if let c = chosen {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: c == s.correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                            Text(c == s.correct ? L("答对了", "Correct") : L("答错了，正确答案是 \(Exams.letters[s.correct])", "Wrong — the answer is \(Exams.letters[s.correct])"))
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(c == s.correct ? Theme.good : Theme.danger)
                        Text(s.explain).font(.system(size: 13)).lineSpacing(3).foregroundStyle(Theme.text.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
                        if let src = s.source { Text(L("出处：\(src)", "Source: \(src)")).font(.system(size: 11)).foregroundStyle(Theme.faint) }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 4))
                    HStack {
                        Spacer()
                        Button(index + 1 < paper.total ? L("下一题", "Next question") : L("交卷", "Hand it in")) { advance(cert, paper) }
                            .buttonStyle(PrimaryButtonStyle(color: color))
                            .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Certification: the clock runs, results only at the end

    func certQuestion(_ cert: CertificateDef, _ paper: ExamPaper) -> some View {
        let item = paper.items[index]
        let s = Exams.shown(item, cert, lang)
        let color = Color(hex: cert.color) ?? Theme.flare
        let limit = Double(paper.timeLimit ?? Exams.certTimeLimit)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Meter(value: Double(index) / Double(paper.total), color: color, height: 4)
                TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
                    let left = max(0, deadline.timeIntervalSince(ctx.date))
                    HStack(spacing: 8) {
                        tags(cert, item)
                        Spacer()
                        Image(systemName: "timer").foregroundStyle(left < 10 ? Theme.danger : Theme.dim)
                        Text("\(Int(left.rounded(.up))) s").font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(left < 10 ? Theme.danger : Theme.text)
                        Meter(value: left / limit, color: left < 10 ? Theme.danger : color, height: 4).frame(width: 140)
                    }
                }
                Text(s.q).font(Theme.prose(19)).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 8) {
                    ForEach(Array(s.options.enumerated()), id: \.offset) { i, o in
                        optionButton(i, o, correct: s.correct, reveal: false, selected: chosen == i) {
                            chosen = i
                            answers[index] = i
                        }
                    }
                }
                HStack {
                    Text(L("选好后点“下一题”确认；时间到了按当前的选择交，没选算错。", "Pick an answer and confirm with “Next”; when time runs out, your current choice counts (none = wrong)."))
                        .font(.system(size: 11)).foregroundStyle(Theme.faint)
                    Spacer()
                    Button(index + 1 < paper.total ? L("下一题", "Next question") : L("交卷", "Hand it in")) { advance(cert, paper) }
                        .buttonStyle(PrimaryButtonStyle(color: color))
                        .keyboardShortcut(.defaultAction)
                        .disabled(chosen == nil)
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task(id: index) {
            // the clock for this question
            let q = index
            while !Task.isCancelled && Date() < deadline {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            if !Task.isCancelled && q == index && !finished { advance(cert, paper) }
        }
    }

    @ViewBuilder
    func tags(_ cert: CertificateDef, _ item: PaperItem) -> some View {
        let q = cert.question(item.questionId)
        if q?.expert ?? false { Chip(text: L("考官级", "Examiner level"), color: Theme.danger) }
        else if q?.hard ?? false { Chip(text: L("难题", "Hard"), color: Theme.warn) }
    }

    func optionButton(_ i: Int, _ text: String, correct: Int, reveal: Bool, selected: Bool, action: @escaping () -> Void) -> some View {
        let bg: Color = !reveal ? (selected ? Theme.panelHi : Theme.panelHi) : (i == correct ? Theme.good.opacity(0.22) : (selected ? Theme.danger.opacity(0.22) : Theme.panelHi.opacity(0.5)))
        let stroke: Color = !reveal ? (selected ? Theme.flare : Theme.line) : (i == correct ? Theme.good : (selected ? Theme.danger : Color.clear))
        return Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Text(Exams.letters[i]).font(.system(size: 13, weight: .bold)).frame(width: 18)
                Text(text).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(bg, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(stroke, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [])
    }

    func advance(_ cert: CertificateDef, _ paper: ExamPaper) {
        guard !finished else { return }
        if index + 1 < paper.total {
            index += 1
            chosen = nil
            deadline = Date().addingTimeInterval(TimeInterval(paper.timeLimit ?? 0))
            return
        }
        finished = true
        submit(cert, paper)
    }

    /// Records the sitting where it belongs: the run, the profile ("我"), or the practice best.
    func submit(_ cert: CertificateDef, _ paper: ExamPaper) {
        let score = Exams.grade(paper, cert, answers: answers)
        let passed = score >= paper.pass(cert)
        switch mode {
        case .run:
            let rec = ExamRecord(certId: cert.id, interlude: model.run?.interlude ?? 0, score: score, total: paper.total, passed: passed, by: "human", answers: answers, paper: paper, note: nil)
            model.recordHumanExam(rec)
            newlyHeld = model.recordProfileExam(cert.id, score: score, total: paper.total, passed: passed, source: "run")
        case .certify:
            newlyHeld = model.recordProfileExam(cert.id, score: score, total: paper.total, passed: passed, source: "hall")
        case .practice:
            let key = "practiceBest.\(cert.id)"
            if score > UserDefaults.standard.integer(forKey: key) { UserDefaults.standard.set(score, forKey: key) }
        }
    }

    // MARK: The result

    func result(_ cert: CertificateDef, _ paper: ExamPaper) -> some View {
        let score = Exams.grade(paper, cert, answers: answers)
        let pass = paper.pass(cert)
        let passed = score >= pass
        let color = Color(hex: cert.color) ?? Theme.flare
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text("\(score)/\(paper.total)").font(.system(size: 54, weight: .bold)).monospacedDigit().foregroundStyle(passed ? Theme.good : Theme.danger)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(passed ? (score == paper.total ? L("满分通过", "Perfect score") : L("通过", "Passed")) : L("没有通过", "Not passed"))
                            .font(.system(size: 20, weight: .semibold))
                        Text(L("及格线 \(pass)/\(paper.total)", "Pass mark \(pass)/\(paper.total)")).font(.system(size: 12)).foregroundStyle(Theme.dim)
                    }
                }
                if paper.isCertification {
                    if passed {
                        CertificateCard(cert: cert, holder: model.profile.name ?? model.run?.human?.name ?? L("你", "You"),
                                        held: model.profile.held(cert.id), lang: lang)
                            .frame(maxWidth: 560)
                        if case .run = mode {
                            Text(cert.effectText(lang) + L(" · 技能点 +\(score == paper.total ? 3 : 2) · 经验 +\(score == paper.total ? 70 : 50)", " · skill points +\(score == paper.total ? 3 : 2) · XP +\(score == paper.total ? 70 : 50)"))
                                .font(.system(size: 12)).foregroundStyle(Theme.dim)
                        }
                        if newlyHeld { Text(L("证书已经记进“我”，以后每一段新征程都会带着它。", "The certificate is on your “Me” page and comes with you into every new run.")).font(.system(size: 12)).foregroundStyle(Theme.good) }
                    } else {
                        Text(mode == .practice ? "" : (mode == Mode.certify(certId: cert.id)
                             ? L("资格认证没有通过。12 小时后才能再考这张证——先去考场练练？", "Not certified. You can retake this one in 12 hours — practise in the exam room meanwhile?")
                             : L("下一关之后可以再考。", "You can try again after the next chapter.")))
                            .font(.system(size: 13)).foregroundStyle(Theme.dim)
                    }
                }
                Divider()
                SectionLabel(text: L("回顾", "Review"))
                ExamReviewList(cert: cert, paper: paper, answers: answers, lang: lang, who: L("你", "you"))
                HStack {
                    if mode == .practice {
                        Button(L("再来一套", "Another paper")) { begin(cert) }.buttonStyle(GhostButtonStyle())
                        Button(L("换一张证", "Another certificate")) { self.cert = nil; self.paper = nil }.buttonStyle(GhostButtonStyle())
                    }
                    Spacer()
                    Button(L("完成", "Done")) {
                        if mode == .practice { self.cert = nil; self.paper = nil } else { dismiss() }
                    }
                    .buttonStyle(PrimaryButtonStyle(color: color))
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

/// The exam room on the home screen: practice any certificate.
struct ExamHallView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ExamView(mode: .practice, onClose: { model.screen = .home })
    }
}

/// Question-by-question review of a sitting: the answer given, the right one, the explanation.
struct ExamReviewList: View {
    let cert: CertificateDef
    let paper: ExamPaper
    let answers: [Int?]
    let lang: Lang
    var who: String

    func letter(_ i: Int) -> String { i >= 0 && i < Exams.letters.count ? String(Exams.letters[i]) : "?" }
    func option(_ opts: [String], _ i: Int) -> String { i >= 0 && i < opts.count ? opts[i] : "?" }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(paper.items.enumerated()), id: \.offset) { i, item in
                let s = Exams.shown(item, cert, lang)
                let a = i < answers.count ? answers[i] : nil
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: a == s.correct ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(a == s.correct ? Theme.good : Theme.danger)
                        Text("\(i + 1). \(s.q)").font(.system(size: 13, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                    }
                    if s.options.isEmpty {
                        // the question was taken out of the bank after this sheet was saved
                        Text(L("这道题已经不在题库里了。", "This question is no longer in the bank."))
                            .font(.system(size: 12)).foregroundStyle(Theme.faint)
                    } else {
                        Text(L("正确答案：", "Answer: ") + "\(letter(s.correct)). \(option(s.options, s.correct))"
                             + (a == nil ? L("（没有作答）", " (no answer)") : (a != s.correct ? L("（\(who)选了 \(letter(a!))：\(option(s.options, a!))）", " (\(who) chose \(letter(a!)): \(option(s.options, a!)))") : "")))
                            .font(.system(size: 12)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                    }
                    Text(s.explain).font(.system(size: 11)).foregroundStyle(Theme.faint).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
        }
    }
}

/// An answer sheet: an AI player's (from the camp) or a model's (from the exam room).
struct ExamRecordView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let who: String
    let byLine: String
    let record: ExamRecord
    var lang: Lang? = nil

    init(player: RunPlayer, record: ExamRecord) {
        self.who = player.name
        self.byLine = player.shownController
        self.record = record
    }

    init(model name: String, record: ExamRecord, lang: Lang) {
        self.who = name
        self.byLine = L("考场", "Exam room")
        self.record = record
        self.lang = lang
    }

    var body: some View {
        let lang = self.lang ?? model.run?.lang ?? model.uiLang
        let player = (name: who, controllerLabel: byLine)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("\(player.name) 的答卷", "\(player.name)'s answer sheet")).font(Theme.title(22))
                    Text("\(player.controllerLabel) · " + (ExamLibrary.cert(record.certId)?.text(lang).full ?? record.certId)).font(.system(size: 12)).foregroundStyle(Theme.dim)
                }
                Spacer()
                Text("\(record.score)/\(record.total)").font(.system(size: 30, weight: .bold)).monospacedDigit().foregroundStyle(record.passed ? Theme.good : Theme.danger)
                Button(L("关闭", "Close")) { dismiss() }.buttonStyle(GhostButtonStyle())
            }
            .padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let note = record.note, !note.isEmpty {
                        Text("“\(note)”").font(Theme.prose(15)).foregroundStyle(Theme.text.opacity(0.9))
                    }
                    if let cert = ExamLibrary.cert(record.certId), let paper = record.paper, let answers = record.answers {
                        ExamReviewList(cert: cert, paper: paper, answers: answers, lang: lang, who: who)
                    } else {
                        Text(L("这次没有答卷（调用失败缺考）。", "No answer sheet this time (the call failed).")).foregroundStyle(Theme.dim)
                    }
                }
                .padding(20)
            }
        }
        .background(Theme.bg)
    }
}

/// "Let a model take them": a configured AI model sits all twelve exams.
struct BenchPanel: View {
    @Environment(AppModel.self) private var model
    @State private var seat = ""
    @State private var sheet: ExamRecord?

    var body: some View {
        let bench = model.bench
        let options = model.seatOptions.filter { $0.id != "rule" }
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    SectionLabel(text: L("让大模型考一遍", "Let an AI model take them all"))
                    Spacer()
                    if options.isEmpty {
                        Text(L("先在设置里配置一个模型", "Set up a model in Settings first")).font(.system(size: 11)).foregroundStyle(Theme.faint)
                    } else {
                        Picker("", selection: $seat) {
                            ForEach(options, id: \.id) { o in Text(o.label).tag(o.id) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 260)
                        if bench.running {
                            Button(L("停止", "Stop")) { bench.stop() }.buttonStyle(GhostButtonStyle())
                        } else {
                            Button(L("开考", "Start")) {
                                if let ref = ModelRef(seatId: seat.isEmpty ? (options.first?.id ?? "") : seat) {
                                    bench.start(ref: ref, config: model.config, library: model.library, lang: model.uiLang)
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        }
                    }
                }
                Text(L("十二张证各考一套资格认证（20 题，大多是考官级难题，对 19 题才通过），成绩记进“模型战绩”。可以拿来比比哪个模型的求生常识最扎实。",
                       "One certification paper for each of the twelve certificates (20 questions, mostly examiner-level, 19 to pass); the results go on the leaderboard. A way to see which model knows its survival basics best."))
                    .font(.system(size: 11)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                if let m = bench.model, !bench.results.isEmpty || bench.running {
                    HStack(spacing: 8) {
                        Text(m).font(.system(size: 13, weight: .semibold))
                        if bench.questions > 0 {
                            Text(L("通过 \(bench.passed)/\(bench.results.count) · 答对 \(Int(Double(bench.correct) / Double(bench.questions) * 100))%",
                                   "passed \(bench.passed)/\(bench.results.count) · \(Int(Double(bench.correct) / Double(bench.questions) * 100))% right"))
                                .font(.system(size: 12)).foregroundStyle(Theme.dim)
                        }
                        if bench.running, let c = bench.current, let cert = ExamLibrary.cert(c) {
                            ProgressView().controlSize(.mini)
                            Text(L("正在考「\(cert.name(model.uiLang))」", "Sitting \(cert.name(model.uiLang))")).font(.system(size: 11)).foregroundStyle(Theme.secret)
                        }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 6)], alignment: .leading, spacing: 6) {
                        ForEach(model.library) { c in
                            if let r = bench.results[c.id] {
                                Button { sheet = r } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: c.icon).foregroundStyle(Color(hex: c.color) ?? Theme.dim)
                                        Text(c.name(model.uiLang)).font(.system(size: 11)).lineLimit(1)
                                        Spacer()
                                        Text(r.by == "absent" ? L("缺考", "missed") : "\(r.score)/\(r.total)").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                                            .foregroundStyle(r.passed ? Theme.good : Theme.danger)
                                    }
                                    .padding(.horizontal, 8).padding(.vertical, 5)
                                    .background(Theme.panelHi, in: RoundedRectangle(cornerRadius: 4))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if let e = bench.error { Text(e).font(.system(size: 11)).foregroundStyle(Theme.danger).lineLimit(2) }
                }
            }
        }
        .onAppear { if seat.isEmpty { seat = options.first?.id ?? "" } }
        .sheet(isPresented: Binding(get: { sheet != nil }, set: { if !$0 { sheet = nil } })) {
            if let r = sheet { ExamRecordView(model: model.bench.model ?? "", record: r, lang: model.uiLang).environment(model).frame(minWidth: 720, minHeight: 600) }
        }
    }
}
