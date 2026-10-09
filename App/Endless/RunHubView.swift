import SwiftUI
import AppKit
import BrinkCore

/// The camp between chapters: what happened, everyone's growth, exams, skill points, the next drill.
struct RunHubView: View {
    @Environment(AppModel.self) private var model
    @State private var pickedScenario: String?
    @State private var pickedRole: String?
    @State private var showExam = false
    @State private var confirmRetire = false
    @State private var showHelp = false
    @State private var review: (player: RunPlayer, record: ExamRecord)?

    var body: some View {
        if let run = model.run {
            VStack(spacing: 0) {
                topBar(run)
                HStack(alignment: .top, spacing: 14) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            DrillMap(run: run)
                            if let rep = run.lastReport { ReportPanel(run: run, report: rep) }
                            nextPanel(run)
                        }
                        .padding(.bottom, 20)
                    }
                    .frame(maxWidth: .infinity)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                SectionLabel(text: L("队伍", "The team"))
                                Spacer()
                                if model.runAI.running {
                                    ProgressView().controlSize(.mini)
                                    Text(L("AI 玩家在考试……", "AI players are sitting exams…")).font(.system(size: 11)).foregroundStyle(Theme.dim)
                                }
                            }
                            ForEach(run.active) { p in
                                PlayerCard(run: run, player: p, status: model.runAI.status[p.id], examButton: { showExam = true },
                                           reviewButton: { rec in review = (p, rec) })
                            }
                            let gone = run.players.filter(\.out)
                            if !gone.isEmpty {
                                SectionLabel(text: L("离开训练营的人", "Those who left the camp"))
                                ForEach(gone) { p in
                                    HStack(spacing: 8) {
                                        Avatar(id: p.id, name: p.name, size: 20, dead: true)
                                        Text(p.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.dim)
                                        Text(L("Lv\(p.level) · 第 \(p.outChapter ?? 0) 关后离开", "Lv \(p.level) · left after chapter \(p.outChapter ?? 0)")).font(.system(size: 11)).foregroundStyle(Theme.faint)
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 20)
                    }
                    .frame(width: 420)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
            }
            .sheet(isPresented: $showExam) {
                if let h = run.human {
                    ExamView(mode: .run(playerId: h.id)).environment(model).frame(minWidth: 760, minHeight: 640)
                }
            }
            .sheet(isPresented: $showHelp) { HelpView().frame(minWidth: 620, minHeight: 560) }
            .sheet(isPresented: Binding(get: { review != nil }, set: { if !$0 { review = nil } })) {
                if let r = review { ExamRecordView(player: r.player, record: r.record).environment(model).frame(minWidth: 720, minHeight: 600) }
            }
            .alert(L("结束这段征程？", "End this run?"), isPresented: $confirmRetire) {
                Button(L("结束，看结局", "End it and see the ending"), role: .destructive) { model.retireRun() }
                Button(L("再想想", "Not yet"), role: .cancel) {}
            } message: {
                Text(run.finaleReached ? L("终章已经打过了，结局会保留，并记下你们之后又闯了几关。", "The finale is behind you; its grand ending stays, with a note of how many more drills you took on.")
                                        : L("还没到终章。结束后会给出“收手”的结局。", "You haven't reached the finale. Ending now gives the “Walking Away” ending."))
            }
            .onChange(of: run.chapter) { _, _ in pickedScenario = nil; pickedRole = nil }
        } else {
            HomeView()
        }
    }

    func topBar(_ run: EndlessRun) -> some View {
        HStack(spacing: 14) {
            Button { model.leaveRun() } label: { Text(L("‹ 主页", "‹ Home")).font(.system(size: 13)) }
                .buttonStyle(.plain).foregroundStyle(Theme.dim)
                .help(L("返回主页（征程会自动保存）", "Back to Home (the run is saved automatically)"))
            Text(L("训练营", "The camp")).font(Theme.title(24))
            Text(run.cycle == 1 ? L("八场推演 · 已打 \(run.played.count)/8 · 通关 \(run.cleared.count)", "Eight drills · played \(run.played.count)/8 · cleared \(run.cleared.count)")
                                : (run.depth == 0 ? L("无尽 · 终章之后", "Endless · after the finale") : L("无尽 · 终章之后第 \(run.depth) 关", "Endless · \(run.depth) chapter(s) after the finale")))
                .font(.system(size: 13)).foregroundStyle(Theme.dim)
            if run.options.hardcore { Chip(text: L("铁人", "Iron"), color: Theme.danger) }
            if run.options.spectator { Chip(text: L("观战", "Watching"), color: Theme.secret) }
            Spacer()
            if run.options.spectator {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    if let c = model.autoCountdown {
                        Text(L("\(c) 秒后进入下一关", "Next chapter in \(c) s")).font(.system(size: 12)).foregroundStyle(Theme.secret).monospacedDigit()
                    }
                }
                Toggle(L("自动连播", "Autoplay"), isOn: Binding(get: { run.options.autoAdvance && !model.autoPaused }, set: { on in
                    model.autoPaused = !on
                    if on && !run.options.autoAdvance { model.mutateRun { $0.options.autoAdvance = true } }
                }))
                .toggleStyle(.switch).controlSize(.small).font(.system(size: 12))
            }
            Button(L("存档", "Save")) { model.saveRunSlot() }
                .buttonStyle(BarButtonStyle()).help(L("另存一份（⌘S）", "Save a copy (⌘S)"))
            Button("?") { showHelp = true }
                .buttonStyle(BarButtonStyle()).help(L("怎么玩", "How to play"))
            Button(L("结束征程", "End the run")) { confirmRetire = true }.buttonStyle(GhostButtonStyle())
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Theme.panel.opacity(0.6))
    }

    // MARK: Next chapter

    @ViewBuilder
    func nextPanel(_ run: EndlessRun) -> some View {
        let choices = run.nextChoices
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionLabel(text: choices == [EndlessRun.finaleId] ? L("终章", "The finale") : L("下一关", "Next chapter"))
                    Spacer()
                    if choices.count > 1 && !run.options.spectator {
                        Button(L("随机", "Random")) {
                            var rng = SeededRNG(seed: UInt64(Date().timeIntervalSince1970))
                            pickedScenario = rng.pick(choices)
                            pickedRole = nil
                        }
                        .buttonStyle(GhostButtonStyle())
                    }
                }
                if choices == [EndlessRun.finaleId] {
                    Text(L("八场推演都打完了。结业考核在一座海边小城举行——下午两点四十六分，地面开始摇晃。这一次不是推演，你们演的就是自己：名字、技能、资格证都是你们自己的。终章里死了就是真的死了。",
                           "All eight drills are done. The final assessment is held in a small town by the sea — and at 2:46 in the afternoon the ground starts to shake. This time it isn't a drill: you play yourselves, with your own names, skills and certificates. In the finale, death is real."))
                        .font(Theme.prose(15)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                    if model.scenario(EndlessRun.finaleId, lang: run.lang) == nil {
                        Text(L("（终章场景文件缺失）", "(the finale scenario file is missing)")).font(.system(size: 12)).foregroundStyle(Theme.danger)
                    }
                }
                if run.cycle >= 2 {
                    Text(L("终章之后的无尽推演：场景随机，每关会抽 1–3 个“变数”（寒潮、物资紧缺、旧伤未愈……），越往后越多。",
                           "Endless drills after the finale: random scenarios, and each one draws 1–3 twists (cold snap, short supplies, old wounds…) — more as you go."))
                        .font(.system(size: 12)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(choices, id: \.self) { id in
                        if let s = model.scenario(id, lang: run.lang) {
                            choiceCard(s, picked: pickedScenario == id, run: run)
                                .onTapGesture { if !run.options.spectator { pickedScenario = id; pickedRole = nil } }
                        }
                    }
                }
                if let sid = pickedScenario ?? (choices.count == 1 ? choices.first : nil), let s = model.scenario(sid, lang: run.lang), !run.options.spectator {
                    rolePicker(s, run: run)
                }
                if run.options.spectator {
                    HStack {
                        Text(model.runAI.running ? L("等 AI 玩家考完试……", "Waiting for the AI players to finish their exams…") : L("下一关会随机抽一个场景。", "The next scenario is drawn at random."))
                            .font(.system(size: 12)).foregroundStyle(Theme.dim)
                        Spacer()
                        Button(L("现在开始", "Start now")) {
                            var rng = SeededRNG(seed: run.seed &+ UInt64(run.chapter) &* 7919)
                            if let next = rng.pick(choices) { model.startChapter(next, humanRole: nil) }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(model.runAI.running || choices.allSatisfy { model.scenario($0, lang: run.lang) == nil })
                    }
                }
            }
        }
    }

    func choiceCard(_ s: Scenario, picked: Bool, run: EndlessRun) -> some View {
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(s.title).font(Theme.title(19))
                Spacer()
                DifficultyMarks(level: s.difficulty)
            }
            Text(s.subtitle).font(.system(size: 11)).foregroundStyle(Theme.dim).lineLimit(1)
            if let n = run.attempts[s.id], n > 0 {
                Text(L("打过 \(n) 次", "played \(n)×")).font(.system(size: 11)).foregroundStyle(Theme.faint)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(picked ? Theme.panelHi : Color.clear)
        .overlay(alignment: .leading) { Rectangle().fill(picked ? Theme.flare : Color.clear).frame(width: 2) }
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(picked ? Theme.flare.opacity(0.5) : Theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    func rolePicker(_ s: Scenario, run: EndlessRun) -> some View {
        let finale = s.id == EndlessRun.finaleId
        VStack(alignment: .leading, spacing: 8) {
            if finale {
                Text(L("终章里没有角色可选：你们就是你们自己。", "No roles to choose in the finale: you are yourselves.")).font(.system(size: 12)).foregroundStyle(Theme.dim)
                ForEach(run.active) { p in
                    HStack(alignment: .top, spacing: 10) {
                        Avatar(id: p.id, name: p.name, size: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(p.name).font(.system(size: 13, weight: .semibold))
                                Text(L("\(p.persona.female ? "女" : "男")，\(p.persona.age)岁 · Lv\(p.level)", "\(p.persona.female ? "female" : "male"), \(p.persona.age) · Lv \(p.level)"))
                                    .font(.system(size: 11)).foregroundStyle(Theme.dim)
                                if p.isHuman { Text(L("你", "you")).font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.flare) }
                            }
                            Text(Skill.all.map { sk in
                                let v = min(Progression.skillCap, (sk == "strength" ? (p.persona.age < 36 ? 2 : 1) : 1) + p.bonus(sk, model.library))
                                return "\(Skill.names[sk] ?? sk) \(v)"
                            }.joined(separator: " · "))
                            .font(.system(size: 11)).foregroundStyle(Theme.dim)
                        }
                    }
                }
            } else {
                SectionLabel(text: L("选你要扮演的人（技能已经算上你的加点和资格证）", "Pick who you'll play (skills include your ranks and certificates)"))
                ForEach(s.characters, id: \.id) { c in roleRow(c, run: run) }
            }
            HStack {
                Text(s.tagline).font(Theme.prose(13)).foregroundStyle(Theme.accent(s)).lineLimit(2)
                Spacer()
                Button {
                    model.startChapter(s.id, humanRole: finale ? nil : pickedRole)
                } label: {
                    Label(finale ? L("进入终章", "Enter the finale") : run.chapterLabel(run.chapter + 1, finale: false) + L(" · 开始", " · Start"), systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle(color: Theme.accent(s)))
                .disabled((!finale && pickedRole == nil && run.human != nil) || model.runAI.running)
                .help(model.runAI.running ? L("等 AI 玩家考完试", "Wait for the AI players to finish their exams") : "")
            }
        }
    }

    func roleRow(_ c: CharacterDef, run: EndlessRun) -> some View {
        let picked = pickedRole == c.id
        let me = run.human
        return HStack(alignment: .top, spacing: 10) {
            Avatar(id: c.id, name: c.name, size: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(c.name).font(.system(size: 13, weight: .semibold))
                    Text(L("\(c.age)岁 · \(c.role)", "\(c.age) · \(c.role)")).font(.system(size: 11)).foregroundStyle(Theme.dim).lineLimit(1)
                }
                Text(c.bio).font(.system(size: 11)).foregroundStyle(Theme.faint).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    ForEach(Skill.all, id: \.self) { sk in
                        let base = c.skill(sk)
                        let bonus = me.map { $0.bonus(sk, model.library) } ?? 0
                        let total = min(Progression.skillCap, base + bonus)
                        if total > 0 {
                            Text("\(Skill.names[sk] ?? sk) \(total)" + (bonus > 0 && total > base ? "↑" : ""))
                                .font(.system(size: 11, weight: bonus > 0 && total > base ? .semibold : .regular))
                                .foregroundStyle(bonus > 0 && total > base ? Theme.good : Theme.dim)
                        }
                    }
                }
            }
            Spacer()
            Button(picked ? L("已选", "Chosen") : L("扮演", "Play")) { pickedRole = c.id }
                .buttonStyle(GhostButtonStyle())
                .disabled(picked)
        }
        .padding(8)
        .background(picked ? Theme.panelHi : Theme.panelHi.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(picked ? Theme.flare.opacity(0.6) : Color.clear, lineWidth: 1))
    }
}

// MARK: - The eight drills + the finale

struct DrillMap: View {
    @Environment(AppModel.self) private var model
    let run: EndlessRun

    var body: some View {
        HStack(spacing: 6) {
            ForEach(EndlessRun.drills, id: \.self) { id in tile(id) }
            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.faint)
            finaleTile
        }
    }

    func tile(_ id: String) -> some View {
        let s = model.scenario(id, lang: run.lang)
        let played = run.played.contains(id) || (run.cycle > 1)
        let cleared = run.cleared.contains(id)
        let accent = Theme.accent(s)
        return VStack(spacing: 4) {
            Image(systemName: s?.icon ?? "flame").font(.system(size: 15)).foregroundStyle(played ? accent : Theme.faint)
            Text(s?.title ?? id).font(.system(size: 11, weight: .semibold)).foregroundStyle(played ? Theme.text : Theme.faint).lineLimit(1)
            Image(systemName: !run.played.contains(id) ? "circle" : (cleared ? "checkmark.circle.fill" : "xmark.circle"))
                .font(.system(size: 10))
                .foregroundStyle(!run.played.contains(id) ? Theme.faint : (cleared ? Theme.good : Theme.danger))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.line.opacity(0.5), lineWidth: 1))
        .help(s?.subtitle ?? id)
    }

    var finaleTile: some View {
        let unlocked = run.finaleUnlocked || run.finaleReached
        return VStack(spacing: 4) {
            Image(systemName: unlocked ? "water.waves" : "lock.fill").font(.system(size: 15)).foregroundStyle(unlocked ? Theme.flare : Theme.faint)
            Text(L("终章", "Finale")).font(.system(size: 11, weight: .bold)).foregroundStyle(unlocked ? Theme.flare : Theme.faint)
            Image(systemName: run.finaleReached ? "flag.checkered" : "circle").font(.system(size: 10)).foregroundStyle(run.finaleReached ? Theme.flare : Theme.faint)
        }
        .frame(width: 70)
        .padding(.vertical, 8)
        .background(unlocked ? Theme.panelHi : Theme.panel, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(unlocked ? Theme.flare.opacity(0.6) : Theme.line.opacity(0.5), lineWidth: 1))
    }
}

// MARK: - What the last chapter brought

struct ReportPanel: View {
    let run: EndlessRun
    let report: ChapterReport

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    SectionLabel(text: run.chapterLabel(report.number, finale: report.scenarioId == EndlessRun.finaleId) + " · " + report.scenarioTitle)
                    Chip(text: report.cleared ? L("通关", "Cleared") : L("全队倒下", "Team wiped out"), color: report.cleared ? Theme.good : Theme.danger)
                    if report.firstClear { Chip(text: L("首次通关", "First clear"), color: Theme.flare) }
                    if report.finaleUnlocked { Chip(text: L("终章已解锁", "Finale unlocked"), color: Theme.flare) }
                    Spacer()
                }
                Text(report.endingTitle).font(Theme.title(24)).foregroundStyle(Theme.tone(report.tone))
                Text(report.endingText).font(Theme.prose(13)).foregroundStyle(Theme.dim).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                Divider()
                ForEach(run.players.filter { report.players[$0.id] != nil }) { p in
                    if let r = report.players[p.id] { row(p, r) }
                }
                if !report.departures.isEmpty {
                    let names = report.departures.compactMap { run.player($0)?.name }
                    Text(L("心力耗尽，离开了训练营：\(names.joined(separator: "、"))", "Out of resolve, left the camp: \(names.joined(separator: ", "))"))
                        .font(.system(size: 12)).foregroundStyle(Theme.danger)
                }
                if !report.recruits.isEmpty {
                    let names = report.recruits.compactMap { run.player($0).map { "\($0.name)（Lv\($0.level)）" } }
                    Text(L("新人加入：\(names.joined(separator: "、"))", "Newcomers: \(names.joined(separator: ", "))"))
                        .font(.system(size: 12)).foregroundStyle(Theme.good)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func row(_ p: RunPlayer, _ r: PlayerChapter) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Avatar(id: p.id, name: p.name, size: 24, dead: !r.survived)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(p.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.person(p.id))
                    Text(L("演\(r.characterName)", "as \(r.characterName)")).font(.system(size: 12)).foregroundStyle(Theme.dim)
                    Text(r.survived ? L("活了下来", "survived") : r.fate).font(.system(size: 12)).foregroundStyle(r.survived ? Theme.good : Theme.danger).lineLimit(1)
                    if r.goalAchieved { Image(systemName: "target").font(.system(size: 10)).foregroundStyle(Theme.good).help(L("完成了个人目标", "Reached the personal goal")) }
                }
                Text(r.breakdown.map { "\($0.label) +\($0.xp)" }.joined(separator: " · "))
                    .font(.system(size: 10)).foregroundStyle(Theme.faint).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if r.levelAfter > r.levelBefore { Chip(text: L("升到 Lv\(r.levelAfter)", "Up to Lv \(r.levelAfter)"), color: Theme.flare) }
                    if r.resolveAfter != r.resolveBefore {
                        Chip(text: L("心力 \(r.resolveBefore)→\(r.resolveAfter)", "Resolve \(r.resolveBefore)→\(r.resolveAfter)"), color: r.resolveAfter > r.resolveBefore ? Theme.good : Theme.danger)
                    }
                    ForEach(r.freeRanks, id: \.self) { s in Chip(text: L("熟能生巧：\(Skill.names[s] ?? s) +1", "Practice: \(Skill.names[s] ?? s) +1"), color: Theme.good) }
                }
            }
            Spacer()
            Text("+\(r.xp) XP").font(.system(size: 14, weight: .bold)).monospacedDigit().foregroundStyle(Theme.flare)
        }
    }
}

// MARK: - A player

struct PlayerCard: View {
    @Environment(AppModel.self) private var model
    let run: EndlessRun
    let player: RunPlayer
    var status: String?
    var examButton: () -> Void = {}
    var reviewButton: (ExamRecord) -> Void = { _ in }

    var body: some View {
        let p = player
        let lib = model.library
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Avatar(id: p.id, name: p.name, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(p.name).font(.system(size: 14, weight: .semibold))
                        if p.isHuman { Text(L("你", "you")).font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.flare) }
                        Text(Personas.temperamentName(p.persona.temperament, Loc.ui)).font(.system(size: 10)).foregroundStyle(Theme.faint)
                    }
                    Text(p.isHuman ? L("玩家", "Player") : p.shownController).font(.system(size: 10)).foregroundStyle(Theme.faint).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Lv \(p.level)").font(.system(size: 15, weight: .bold)).monospacedDigit()
                    HStack(spacing: 2) {
                        ForEach(0..<p.maxResolve, id: \.self) { i in
                            Image(systemName: i < p.resolve ? "heart.fill" : "heart").font(.system(size: 9)).foregroundStyle(i < p.resolve ? Theme.danger : Theme.faint)
                        }
                    }
                    .help(L("心力", "Resolve"))
                }
            }
            HStack(spacing: 6) {
                Meter(value: p.levelProgress, color: Theme.flare, height: 4)
                Text("\(p.xp - Progression.xpAt(p.level))/\(Progression.xpToNext(p.level))").font(.system(size: 9)).foregroundStyle(Theme.faint).monospacedDigit()
            }
            VStack(spacing: 3) {
                ForEach(Progression.trainable, id: \.self) { s in skillRow(s, p, lib) }
                HStack(spacing: 4) {
                    Text(Skill.names["strength"] ?? "strength").font(.system(size: 11)).foregroundStyle(Theme.faint).frame(width: Loc.ui == .en ? 78 : 46, alignment: .leading)
                    Text(L("属于身体，随角色而定", "belongs to the body — depends on the role")).font(.system(size: 10)).foregroundStyle(Theme.faint)
                    Spacer()
                }
            }
            if p.isHuman && p.points > 0 {
                Text(L("还有 \(p.points) 个技能点可以加", "\(p.points) skill point(s) to spend")).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.flare)
            }
            if !p.certs.isEmpty {
                FlowChips(items: p.certs.compactMap { r in lib.first { $0.id == r.id }.map { ($0.name(Loc.ui), Color(hex: $0.color) ?? Theme.dim) } })
            }
            if p.isHuman {
                HStack {
                    if let last = p.exams.last(where: { $0.interlude == run.interlude }) {
                        Text(model.runAI.describe(last, Loc.ui)).font(.system(size: 11)).foregroundStyle(last.passed ? Theme.good : Theme.danger)
                    }
                    Spacer()
                    Button { examButton() } label: { Label(L("去考证", "Sit an exam"), systemImage: "pencil.and.list.clipboard") }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(run.examUsed(p.id) || run.eligible(p.id, lib).isEmpty || run.phase != .hub)
                }
                if run.examUsed(p.id) {
                    Text(L("这次已经考过了，下一关之后还能再考。", "You've sat your exam for now — another after the next chapter.")).font(.system(size: 10)).foregroundStyle(Theme.faint)
                }
            } else {
                HStack(spacing: 6) {
                    if let st = status {
                        Text(st).font(.system(size: 11)).foregroundStyle(Theme.dim)
                    } else if let last = p.exams.last(where: { $0.interlude == run.interlude }) {
                        Text(model.runAI.describe(last, Loc.ui)).font(.system(size: 11)).foregroundStyle(last.passed ? Theme.good : Theme.danger)
                    }
                    Spacer()
                    if let last = p.exams.last(where: { $0.interlude == run.interlude || $0.interlude == run.interlude - 1 }), last.paper != nil {
                        Button(L("看答卷", "Answer sheet")) { reviewButton(last) }.buttonStyle(.link).font(.system(size: 11))
                    }
                }
                if let w = p.lastWords, !w.isEmpty {
                    Text("“\(w)”").font(Theme.prose(12)).foregroundStyle(Theme.text.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                }
                if let lesson = p.lessons?.last {
                    Text(L("记下的教训：", "Lesson noted: ") + lesson).font(.system(size: 11)).foregroundStyle(Theme.secret.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(11)
        .background(p.isHuman ? Theme.panelHi : Theme.panel, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(p.isHuman ? Theme.flare.opacity(0.45) : Theme.line.opacity(0.5), lineWidth: 1))
    }

    func skillRow(_ s: String, _ p: RunPlayer, _ lib: [CertificateDef]) -> some View {
        let rank = p.rank(s), cert = p.certBonus(s, lib)
        let practice = p.practice[s] ?? 0
        let need = Progression.practiceNeeded(rank)
        return HStack(spacing: 4) {
            Text(Skill.names[s] ?? s).font(.system(size: 11)).foregroundStyle(Theme.dim).frame(width: Loc.ui == .en ? 78 : 46, alignment: .leading)
            HStack(spacing: 2) {
                ForEach(0..<Progression.maxRank, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5).fill(i < rank ? Theme.flare : Theme.line.opacity(0.6)).frame(width: 12, height: 6)
                }
                ForEach(0..<cert, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1.5).fill(Theme.good).frame(width: 12, height: 6)
                }
            }
            .help(L("加点 +\(rank)，资格证 +\(cert)", "Ranks +\(rank), certificates +\(cert)"))
            Text("+\(rank + cert)").font(.system(size: 10, weight: .semibold)).foregroundStyle(rank + cert > 0 ? Theme.text : Theme.faint).monospacedDigit().frame(width: 22)
            if rank < Progression.maxRank {
                Meter(value: Double(practice) / Double(need), color: Theme.good.opacity(0.6), height: 3)
                    .frame(width: 40)
                    .help(L("熟练度 \(practice)/\(need)：攒满免费 +1", "Practice \(practice)/\(need): fill it for a free +1"))
            } else {
                Spacer().frame(width: 40)
            }
            Spacer()
            if p.isHuman && run.phase == .hub {
                Button { model.lowerSkill(s) } label: { Image(systemName: "minus") }
                    .buttonStyle(.plain).foregroundStyle(p.canLower(s) ? Theme.dim : Theme.faint.opacity(0.4)).disabled(!p.canLower(s))
                    .help(L("退回一级", "Take back a rank"))
                Button { model.raiseSkill(s) } label: {
                    Text(rank < Progression.maxRank ? "+\(Progression.rankCost(rank + 1))" : L("满", "max")).font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(p.canRaise(s) ? Theme.flare : Theme.faint)
                .disabled(!p.canRaise(s))
                .help(L("花 \(Progression.rankCost(rank + 1)) 点升一级", "Spend \(Progression.rankCost(rank + 1)) point(s) for a rank"))
            }
        }
    }
}
