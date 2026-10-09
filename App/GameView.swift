import SwiftUI
import AppKit
import BrinkCore

struct GameView: View {
    @Environment(AppModel.self) private var model
    @Bindable var session: GameSession
    @State private var showCalls = false
    @State private var showHelp = false
    @State private var inspect: String?

    var body: some View {
        let accent = Theme.accent(session.scenario)
        let tip = model.tutorialTip(session)
        VStack(spacing: 0) {
            TopBar(session: session, showCalls: $showCalls, showHelp: $showHelp)
                .guideGlow(tip?.spot == .topBar, radius: 4)
            if let err = session.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warn)
                    Text(err).font(.system(size: 12)).lineLimit(2)
                    Spacer()
                    Text(L("已由基础人机代为决定", "A basic bot decided instead")).font(.system(size: 11)).foregroundStyle(Theme.dim)
                    Button { session.clearError() } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }
                .padding(.horizontal, 16).padding(.vertical, 6)
                .background(Theme.warn.opacity(0.12))
            }
            HStack(alignment: .top, spacing: 12) {
                PartyPanel(session: session, inspect: $inspect)
                    .frame(width: 270)
                    .guideGlow(tip?.spot == .party)
                VStack(spacing: 10) {
                    if model.config.showScene ?? true {
                        LiveScene(session: session)
                            .guideGlow(tip?.spot == .scene)
                    }
                    FeedView(session: session)
                        .background(Theme.panel.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.line.opacity(0.5), lineWidth: 1))
                        .guideGlow(tip?.spot == .feed)
                    DecisionPanel(session: session)
                        .guideGlow(tip?.spot == .decision)
                }
                .frame(maxWidth: .infinity)
                .overlay(alignment: tip?.spot == .party ? .topLeading : (tip?.spot == .world ? .topTrailing : .top)) {
                    // tutorial: one tip at a time, floating over the scene so the decision panel stays usable
                    if let tip {
                        TutorialCard(tip: tip, onNext: { withAnimation(.easeOut(duration: 0.2)) { model.dismissTip(tip.id) } },
                                     onMute: { withAnimation(.easeOut(duration: 0.2)) { model.muteTips() } })
                            .padding(8)
                            .id(tip.id)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(.easeOut(duration: 0.25), value: tip?.id)
                WorldPanel(session: session, showCalls: $showCalls)
                    .frame(width: 270)
                    .guideGlow(tip?.spot == .world)
            }
            .padding(12)
        }
        .tint(accent)
        .onChange(of: session.pendingHuman) { _, new in
            // bounce the Dock icon when it's the player's turn and the app is in the background
            if new != nil && !NSApp.isActive { NSApp.requestUserAttention(.informationalRequest) }
        }
        .overlay {
            if session.finished || session.state.phase == .ended, let end = session.state.ending {
                EndOverlay(session: session, ending: end)
            }
        }
        .sheet(isPresented: $showHelp) {
            HelpView().frame(minWidth: 620, minHeight: 560)
        }
        .sheet(isPresented: $showCalls) {
            CallLogView(session: session)
                .frame(minWidth: 900, minHeight: 620)
        }
        .sheet(item: Binding(get: { inspect.map { InspectID(id: $0) } }, set: { inspect = $0?.id })) { item in
            CharacterDetail(session: session, id: item.id)
                .frame(minWidth: 520, minHeight: 520)
        }
    }
}

struct InspectID: Identifiable { let id: String }

/// The live 3D scene above the story feed.
struct LiveScene: View {
    @Environment(AppModel.self) private var model
    let session: GameSession
    @State private var reset = 0
    @State private var tall = false

    var body: some View {
        SceneDisplay(state: SceneState(engine: session.engine), resetToken: reset)
            .frame(height: tall ? 420 : 210)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.line.opacity(0.5), lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 10) {
                    Button { reset += 1 } label: { Image(systemName: "scope") }.help(L("回到默认视角", "Reset the view"))
                    Button { withAnimation(.easeOut(duration: 0.2)) { tall.toggle() } } label: {
                        Image(systemName: tall ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                    }.help(tall ? L("缩小", "Smaller") : L("放大", "Bigger"))
                    Button { model.config.showScene = false; model.saveConfig() } label: { Image(systemName: "xmark") }
                        .help(L("隐藏现场（顶栏的立方体按钮可以再打开）", "Hide the scene (the cube button in the top bar brings it back)"))
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.75))
                .padding(8)
                .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 4))
                .padding(8)
            }
    }
}

struct TopBar: View {
    @Environment(AppModel.self) private var model
    @Bindable var session: GameSession
    @Binding var showCalls: Bool
    @Binding var showHelp: Bool

    var body: some View {
        let s = session.scenario
        let st = session.state
        let w = s.climate.weather[st.weather]
        HStack(spacing: 16) {
            Button { model.leaveGame() } label: { Text(L("‹ 主页", "‹ Home")).font(.system(size: 13)) }
                .buttonStyle(.plain).foregroundStyle(Theme.dim)
                .help(L("返回主页（进度会自动保存，⌘⇧H）", "Back to Home (progress is saved automatically, ⌘⇧H)"))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(s.title).font(Theme.title(22))
                Text(s.subtitle).font(.system(size: 12)).foregroundStyle(Theme.dim)
                    .lineLimit(1).layoutPriority(-2)
            }
            Divider().frame(height: 22)
            Text("\(session.engine.roundLabel) · \(session.engine.clockLabel)")
                .font(.system(size: 13, weight: .medium)).monospacedDigit()
            HStack(spacing: 6) {
                Image(systemName: w?.icon ?? "cloud")
                Text("\(w?.name ?? st.weather) \(Fmt.temp(st.dayLow)) ~ \(Fmt.temp(st.dayHigh))").monospacedDigit()
            }
            .font(.system(size: 13))
            .foregroundStyle(Theme.dim)
            .lineLimit(1).layoutPriority(-1)
            PhasePill(phase: st.phase)
            if !session.canChangeDifficulty && st.setup.level != .normal {
                Text(st.setup.level.label(Loc.ui)).font(.system(size: 12)).foregroundStyle(st.setup.level == .brink ? Theme.danger : Theme.faint)
                    .help(st.setup.level.blurb(Loc.ui))
            }
            if let ch = st.setup.chapter {
                Chip(text: ch.finale ? L("终章 · 这一次不是推演", "Finale · not a drill") : L("无尽 · 第 \(ch.number) 关", "Endless · chapter \(ch.number)"), color: Theme.flare)
                ForEach(ch.mutators, id: \.self) { m in Chip(text: m, color: Theme.warn) }
            }
            if let t = model.tournament {
                Chip(text: L("连续对局 \(t.played + 1)/\(t.total)", "Game \(t.played + 1)/\(t.total)"), color: Theme.secret)
                Button(L("停止连续对局", "Stop the series")) { model.stopTournament() }.buttonStyle(.link).font(.system(size: 11))
            }
            Spacer()
            if let l = st.leader {
                HStack(spacing: 4) {
                    Text(L("领头", "Lead")).foregroundStyle(Theme.faint)
                    Text(session.engine.name(l)).foregroundStyle(Theme.warn)
                }
                .font(.system(size: 12))
                .help(L("领头人", "Leader"))
            }
            HStack(spacing: 6) {
                Toggle(L("上帝视角", "God view"), isOn: $session.godView)
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .help(session.spectator ? L("显示内心独白、私聊、日记和暗中行动", "Show inner thoughts, whispers, diaries and secret moves") : L("剧透：显示所有人的内心独白、私聊和暗中行动", "Spoilers: show everyone's inner thoughts, whispers and secret moves"))
                if session.canChangeDifficulty {
                    DifficultyButton(place: .bar, session: session)
                }
                Button("3D") {
                    model.config.showScene = !(model.config.showScene ?? true)
                    model.saveConfig()
                }
                .buttonStyle(BarButtonStyle())
                .help(L("显示/隐藏 3D 现场", "Show/hide the 3D scene"))
                Button(L("存档", "Save")) { model.saveGame() }
                    .buttonStyle(BarButtonStyle())
                    .disabled(session.finished || session.state.phase == .ended)
                    .help(L("存档（⌘S）", "Save (⌘S)"))
                Button(L("调用", "Calls")) { showCalls = true }
                    .buttonStyle(BarButtonStyle())
                    .help(L("每个模型这一局的调用、用时和原始回答", "Each model's calls, times and raw answers this game"))
                Button("?") { showHelp = true }
                    .buttonStyle(BarButtonStyle())
                    .help(L("怎么玩", "How to play"))
            }
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.top, 30)
        .padding(.bottom, 10)
        .background(Theme.panel.opacity(0.85))
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

/// 局势 — 分工 — 入夜, the current one underlined.
struct PhasePill: View {
    let phase: GamePhase
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array([GamePhase.situation, .tasks, .night].enumerated()), id: \.element) { i, p in
                if i > 0 { Text("—").foregroundStyle(Theme.line) }
                Text(p.label)
                    .font(.system(size: 12, weight: p == phase ? .semibold : .regular))
                    .foregroundStyle(p == phase ? Theme.text : Theme.faint)
                    .padding(.bottom, 3)
                    .overlay(alignment: .bottom) { Rectangle().fill(p == phase ? Theme.flare : Color.clear).frame(height: 1.5) }
            }
        }
        .font(.system(size: 12))
    }
}

/// Small text buttons in the game's top bar.
struct BarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(enabled ? Theme.text.opacity(configuration.isPressed ? 0.6 : 0.85) : Theme.faint)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.line, lineWidth: 1))
            .contentShape(Rectangle())
    }
}
