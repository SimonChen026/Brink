import SwiftUI
import AppKit
import BrinkCore

struct EndOverlay: View {
    @Environment(AppModel.self) private var model
    let session: GameSession
    let ending: EndingResult
    @State private var hidden = false
    /// Whether this ending was new when the game finished (checked once).
    @State private var isNew: Bool?

    var body: some View {
        if hidden {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(L("结局：\(ending.title)", "Ending: \(ending.title)")) { hidden = false }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(20)
                }
            }
        } else {
            ZStack {
                Color.black.opacity(0.6).ignoresSafeArea()
                ScrollView {
                    content
                        .padding(32)
                        .frame(maxWidth: 860)
                        .background(Theme.bg, in: RoundedRectangle(cornerRadius: 4))
                        .overlay(alignment: .top) { Rectangle().fill(Theme.tone(ending.tone)).frame(height: 2) }
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.line, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(.vertical, 40)
                }
                .scrollIndicators(.hidden)
            }
            .onAppear {
                // the gallery was updated when the game finished; it's new if the home screen's copy didn't have it yet
                if isNew == nil { isNew = !model.gallery.has(session.scenario.id, ending.id) }
            }
        }
    }

    var content: some View {
        let others = ending.others ?? []
        let epilogues = (ending.results + others).filter { $0.epilogue != nil }
        let found = session.scenario.endings.filter { model.gallery.has(session.scenario.id, $0.id) || $0.id == ending.id }.count
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                let anyoneOut = ending.results.contains { $0.survived }
                Text(ending.tone == "good" ? L("活下来了", "THEY MADE IT") : (ending.tone == "bad" && !anyoneOut ? L("没有人回来", "NO ONE CAME BACK") : L("代价", "THE PRICE")))
                    .font(.system(size: 12, weight: .semibold)).tracking(model.uiLang == .en ? 1.5 : 0)
                    .foregroundStyle(Theme.tone(ending.tone))
                if isNew == true && !session.scenario.isTutorial { Chip(text: L("新结局", "New ending"), color: Theme.flare) }
                Spacer()
                if !session.scenario.isTutorial {
                    Text(L("本场景结局 \(found)/\(session.scenario.endings.count)", "Endings found \(found)/\(session.scenario.endings.count)"))
                        .font(.system(size: 11)).foregroundStyle(Theme.faint)
                }
            }
            Text(ending.title).font(Theme.title(40))
            Text(ending.text).font(Theme.prose(16)).lineSpacing(6).fixedSize(horizontal: false, vertical: true)
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text(L("角色", "Character")).foregroundStyle(Theme.faint)
                    Text(L("扮演者", "Played by")).foregroundStyle(Theme.faint)
                    Text(L("结果", "Fate")).foregroundStyle(Theme.faint)
                    Text(L("个人目标", "Personal goal")).foregroundStyle(Theme.faint)
                    Text(L("得分", "Score")).foregroundStyle(Theme.faint)
                }
                .font(.system(size: 11, weight: .semibold))
                ForEach(ending.results) { r in
                    GridRow {
                        HStack(spacing: 6) {
                            Avatar(id: r.id, name: r.name, size: 20, dead: !r.survived)
                            Text(r.name).font(.system(size: 13, weight: .semibold))
                        }
                        Text(r.controller).font(.system(size: 12)).foregroundStyle(Theme.dim)
                        Text(r.fate).font(.system(size: 12)).foregroundStyle(r.survived ? Theme.good : Theme.danger)
                        HStack(spacing: 6) {
                            Text(r.goalAchieved ? L("达成", "done") : L("未达成", "not done")).font(.system(size: 11))
                                .foregroundStyle(r.goalAchieved ? Theme.good : Theme.faint)
                            Text(r.goal ?? "—").font(.system(size: 12)).foregroundStyle(Theme.dim).lineLimit(1)
                                .help(r.goal ?? "")
                        }
                        Text("\(r.score)").font(.system(size: 14, weight: .bold)).monospacedDigit()
                    }
                }
            }
            if !others.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    SectionLabel(text: L("其他人", "The others"))
                    ForEach(others) { r in
                        HStack(spacing: 6) {
                            Avatar(id: r.id, name: r.name, size: 18, dead: !r.survived)
                            Text(r.name).font(.system(size: 12, weight: .semibold))
                            Text(r.fate).font(.system(size: 12)).foregroundStyle(r.survived ? Theme.good : Theme.danger)
                        }
                    }
                }
            }
            if !epilogues.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: L("后来", "Afterwards"))
                    ForEach(epilogues) { r in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(r.survived ? Theme.text : Theme.dim)
                                Text(r.epilogue ?? "").font(Theme.prose(14)).lineSpacing(4).foregroundStyle(Theme.text.opacity(0.9))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            if let t = model.tournament {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(t.played + 1 < t.total ? L("连续对局：第 \(t.played + 2)/\(t.total) 局马上开始……", "Next game (\(t.played + 2)/\(t.total)) starting…") : L("连续对局全部结束，马上打开模型战绩……", "All games done — opening the leaderboard…"))
                        .font(.system(size: 12)).foregroundStyle(Theme.secret)
                }
            }
            if model.run != nil {
                runButtons
            } else if session.scenario.isTutorial {
                TutorialNextSteps(session: session, lookBack: $hidden)
            } else {
            HStack(spacing: 10) {
                Button(L("再来一局", "Play again")) {
                    let sid = session.scenario.id
                    model.leaveGame()
                    model.screen = .setup(sid)
                }
                .buttonStyle(PrimaryButtonStyle())
                if let url = session.savedTranscript {
                    Button(L("打开完整记录", "Open full log")) { NSWorkspace.shared.open(url) }.buttonStyle(GhostButtonStyle())
                    Button(L("在访达中显示", "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }.buttonStyle(GhostButtonStyle())
                }
                Button(L("回看过程", "Look back")) { hidden = true }.buttonStyle(GhostButtonStyle())
                Spacer()
                Button(L("模型战绩", "Leaderboard")) { model.leaveGame(); model.screen = .leaderboard }.buttonStyle(GhostButtonStyle())
                Button(L("返回主页", "Home")) { model.leaveGame() }.buttonStyle(GhostButtonStyle())
            }
            }
        }
    }

    /// Endless mode: this ending is a chapter of a run.
    var runButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let r = model.run, r.options.spectator {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    if let c = model.autoCountdown {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(L("\(c) 秒后回到训练营……", "Back to the camp in \(c) s…")).font(.system(size: 12)).foregroundStyle(Theme.secret)
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                Button {
                    model.completeChapter()
                } label: {
                    Text(session.state.setup.chapter?.finale == true ? L("看大结局", "See the grand ending") : L("回训练营：结算经验", "Back to the camp: experience"))
                }
                .buttonStyle(PrimaryButtonStyle())
                Button(L("回看过程", "Look back")) { hidden = true }.buttonStyle(GhostButtonStyle())
                if let url = session.savedTranscript {
                    Button(L("打开完整记录", "Open full log")) { NSWorkspace.shared.open(url) }.buttonStyle(GhostButtonStyle())
                }
                Spacer()
                Button(L("返回主页", "Home")) { model.leaveRun() }.buttonStyle(GhostButtonStyle())
            }
        }
    }
}

struct CallLogView: View {
    @Environment(\.dismiss) private var dismiss
    let session: GameSession
    @State private var selected: UUID?

    var body: some View {
        let calls = session.callLog.reversed()
        HStack(spacing: 0) {
            List(selection: $selected) {
                ForEach(Array(calls)) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("R\(c.round) · \(c.phase)").font(.system(size: 11)).foregroundStyle(Theme.dim)
                            Text(session.engine.name(c.character)).font(.system(size: 12, weight: .semibold))
                            Spacer()
                            if c.error != nil { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.danger) }
                        }
                        Text(c.model).font(.system(size: 10)).foregroundStyle(Theme.faint)
                        Text(String(format: "%.1fs · %d/%d tokens", c.seconds, c.inputTokens, c.outputTokens)).font(.system(size: 10)).foregroundStyle(Theme.faint)
                    }
                    .tag(c.id)
                }
            }
            .frame(width: 280)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L("AI 调用记录", "AI call log")).font(Theme.title(20))
                    Spacer()
                    Button(L("关闭", "Close")) { dismiss() }.buttonStyle(GhostButtonStyle()).keyboardShortcut(.cancelAction)
                }
                if let id = selected, let c = session.callLog.first(where: { $0.id == id }) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            if let e = c.error { Text(e).foregroundStyle(Theme.danger).textSelection(.enabled) }
                            SectionLabel(text: L("回答", "Response"))
                            Text(c.response).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                            SectionLabel(text: L("提示词（末尾部分）", "Prompt (the end of it)"))
                            Text(c.prompt).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.dim).textSelection(.enabled)
                        }
                    }
                } else {
                    Text(session.callLog.isEmpty ? L("还没有调用过大模型（AI 角色可能都是基础人机）。", "No AI model calls yet (the AI characters may all be basic bots).") : L("选择左边的一次调用查看详情。", "Pick a call on the left to see the details."))
                        .foregroundStyle(Theme.dim)
                    Spacer()
                }
            }
            .padding(20)
        }
        .background(Theme.bg)
    }
}
