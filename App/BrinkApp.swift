import SwiftUI
import AppKit
import BrinkCore

@main
struct BrinkApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup(L("绝境", "Brink")) {
            RootView()
                .environment(model)
                .frame(minWidth: 1180, minHeight: 760)
                .preferredColorScheme(.dark)
                .onAppear { SnapshotTool.runIfRequested(model: model) }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L("返回主页", "Back to Home")) { model.leaveGame() }.keyboardShortcut("h", modifiers: [.command, .shift])
                Button(L("读取存档…", "Load Game…")) { model.showSaves = true }.keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                Button(L("存档", "Save Game")) { model.saveGame() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(model.run == nil && (model.session == nil || model.session?.finished == true))
            }
            CommandGroup(after: .appSettings) {
                Button(L("设置…", "Settings…")) { model.showSettings = true }.keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ZStack {
            Theme.bg.ignoresSafeArea()
            switch model.screen {
            case .home:
                HomeView()
            case .setup(let id):
                if let s = model.scenario(id) { SetupView(scenario: s) } else { HomeView() }
            case .game:
                if let session = model.session { GameView(session: session) } else { HomeView() }
            case .leaderboard:
                LeaderboardView()
            case .runSetup:
                RunSetupView()
            case .runHub:
                RunHubView()
            case .grand:
                GrandEndingView()
            case .examHall:
                ExamHallView()
            case .me:
                MeView()
            }
        }
        // rebuild everything when the interface language changes
        .id(model.uiLang)
        .foregroundStyle(Theme.text)
        // controls (sliders, switches, menus, links) take the bone accent instead of system blue
        .tint(Theme.flare)
        .overlay(alignment: .bottom) {
            if let t = model.toast {
                Text(t)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Theme.panelHi, in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.line, lineWidth: 1))
                    .padding(.bottom, 26)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.toast)
        .sheet(isPresented: $model.showSettings) {
            SettingsView()
                .environment(model)
                .frame(minWidth: 860, minHeight: 600)
        }
        .sheet(isPresented: $model.showSaves) {
            SavesView()
                .environment(model)
                .frame(minWidth: 720, minHeight: 520)
        }
    }
}

/// Saved games: continue or delete.
struct SavesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var slots: [GameSession.SaveSlot] = []
    @State private var confirmDelete: GameSession.SaveSlot?
    @State private var runs: [(url: URL, save: RunSave, manual: Bool)] = []
    @State private var confirmDeleteRun: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L("读取存档", "Load game")).font(Theme.title(26))
                Spacer()
                Button(L("打开存档文件夹", "Open saves folder")) { NSWorkspace.shared.open(AppPaths.saves) }.buttonStyle(GhostButtonStyle())
                Button(L("关闭", "Close")) { dismiss() }.buttonStyle(GhostButtonStyle()).keyboardShortcut(.cancelAction)
            }
            if slots.isEmpty && runs.isEmpty {
                Panel {
                    Text(L("还没有存档。对局中按 ⌘S（或点顶栏的存档按钮）就能存一个；游戏也会自动保存最近的进度。",
                           "No saves yet. Press ⌘S during a game (or use the save button in the top bar); the game also saves your latest progress automatically."))
                        .foregroundStyle(Theme.dim)
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if !runs.isEmpty {
                            SectionLabel(text: L("无尽模式", "Endless"))
                            ForEach(runs, id: \.url) { r in runRow(r) }
                            if !slots.isEmpty { SectionLabel(text: L("单局", "Single games")).padding(.top, 8) }
                        }
                        ForEach(slots) { slot in row(slot) }
                    }
                }
            }
        }
        .padding(26)
        .background(Theme.bg)
        .onAppear { reload() }
        .alert(L("删除这段征程的存档？", "Delete this run's save?"), isPresented: Binding(get: { confirmDeleteRun != nil }, set: { if !$0 { confirmDeleteRun = nil } })) {
            Button(L("删除", "Delete"), role: .destructive) {
                if let u = confirmDeleteRun { RunStore.delete(u) }
                confirmDeleteRun = nil
                reload()
                model.latestRun = RunStore.latestActive()
            }
            Button(L("取消", "Cancel"), role: .cancel) { confirmDeleteRun = nil }
        } message: {
            Text(L("存档会移到废纸篓。", "The save goes to the Trash."))
        }
        .alert(L("删除这个存档？", "Delete this save?"), isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button(L("删除", "Delete"), role: .destructive) {
                if let s = confirmDelete {
                    GameSession.deleteSave(s)
                    if s.isAutosave { model.autosave = nil }
                }
                confirmDelete = nil
                reload()
            }
            Button(L("取消", "Cancel"), role: .cancel) { confirmDelete = nil }
        } message: {
            Text(L("存档会移到废纸篓。", "The save goes to the Trash."))
        }
    }

    func reload() {
        slots = GameSession.listSaves()
        runs = RunStore.list().map { ($0.url, $0.save, false) } + RunStore.slots().map { ($0.url, $0.save, true) }
        runs.sort { $0.save.savedAt > $1.save.savedAt }
    }

    func runRow(_ r: (url: URL, save: RunSave, manual: Bool)) -> some View {
        let run = r.save.run
        let names = run.active.map { $0.isHuman ? $0.name + L("（你）", " (you)") : $0.name }.joined(separator: L("、", ", "))
        return HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(r.save.title).font(.system(size: 15, weight: .semibold))
                    Chip(text: r.manual ? L("手动存档", "Manual save") : L("自动存档", "Autosave"), color: r.manual ? Theme.dim : Theme.warn)
                    Chip(text: run.lang.label, color: Theme.dim)
                    if run.phase == .ended { Chip(text: L("已结束", "Finished"), color: Theme.faint) }
                }
                Text(L("推演 \(run.played.count)/8 · 通关 \(run.cleared.count) · ", "Drills \(run.played.count)/8 · cleared \(run.cleared.count) · ") + names)
                    .font(.system(size: 12)).foregroundStyle(Theme.dim).lineLimit(1)
                Text(r.save.savedAt.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 11)).foregroundStyle(Theme.faint)
            }
            Spacer()
            Button(run.phase == .ended ? L("看结局", "See the ending") : L("继续", "Continue")) { model.resumeRun(r.save) }
                .buttonStyle(PrimaryButtonStyle())
            Button(L("删除", "Delete")) { confirmDeleteRun = r.url }
                .buttonStyle(GhostButtonStyle())
        }
        .padding(12)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.line, lineWidth: 1))
    }

    func row(_ slot: GameSession.SaveSlot) -> some View {
        let f = slot.file
        let base = model.baseScenarios.first { $0.id == f.scenarioId }
        let title = f.title ?? base?.title ?? f.scenarioId
        let me = f.state.setup.controllers.first { $0.value.isHuman }?.key
        let meName = me.flatMap { id in model.scenario(f.scenarioId, lang: f.lang)?.character(id)?.name }
        let alive = f.state.characters.filter { !$0.isNPC && $0.alive }.count
        let total = f.state.characters.filter { !$0.isNPC }.count
        return HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    if slot.isAutosave { Chip(text: L("自动存档", "Autosave"), color: Theme.warn) }
                    Chip(text: f.lang.label, color: Theme.dim)
                    if f.state.phase == .ended { Chip(text: L("已结束", "Finished"), color: Theme.faint) }
                }
                Text([f.progress ?? L("第 \(f.state.round) 回合", "Round \(f.state.round)"),
                      meName.map { L("你扮演\($0)", "you play \($0)") } ?? L("观战", "spectating"),
                      L("玩家角色还剩 \(alive)/\(total) 人", "\(alive)/\(total) player characters left")].joined(separator: " · "))
                    .font(.system(size: 12)).foregroundStyle(Theme.dim)
                Text(f.savedAt.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 11)).foregroundStyle(Theme.faint)
            }
            Spacer()
            Button(L("继续", "Continue")) { model.load(f) }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(f.state.phase == .ended)
            Button(L("删除", "Delete")) { confirmDelete = slot }
                .buttonStyle(GhostButtonStyle())
        }
        .padding(12)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.line, lineWidth: 1))
    }
}
