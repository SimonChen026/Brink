import SwiftUI
import AppKit
import BrinkCore

/// The cover: a live 3D scene of one of the disasters behind the title, then endless mode and the scenarios.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var heroIndex = 0
    @State private var heroTick = 0
    private let columns = [GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 18)]

    /// The cover cycles through the eight disasters (the finale stays a surprise).
    var heroScenarios: [Scenario] { model.scenarios.filter { !($0.hidden ?? false) } }

    /// The finale joins the list once a run has reached a grand ending.
    var gridScenarios: [Scenario] {
        let unlocked = !(model.gallery.unlocked["_grand"] ?? []).isEmpty
        return model.scenarios.filter { !$0.isTutorial && (!($0.hidden ?? false) || unlocked) }
    }

    /// "十场灾难" / "Ten disasters": spelled out, so a new scenario file just works.
    static func spelled(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .spellOut
        f.locale = Locale(identifier: Loc.ui == .en ? "en" : "zh_Hans")
        let w = f.string(from: NSNumber(value: n)) ?? "\(n)"
        return Loc.ui == .en ? w.prefix(1).uppercased() + w.dropFirst() : w
    }

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        hero(height: max(540, min(geo.size.height * 0.74, 700)), proxy: proxy)
                        VStack(alignment: .leading, spacing: 34) {
                            EndlessFeature()
                            VStack(alignment: .leading, spacing: 6) {
                                Text(L("\(Self.spelled(gridScenarios.count))场灾难", "\(Self.spelled(gridScenarios.count)) disasters")).font(Theme.title(26))
                                Text(L("每一场都根据真实发生过的灾难改编。单独打一局，或者在无尽模式里一场接一场地闯。",
                                       "Each one is based on a disaster that really happened. Play one on its own, or take them on one after another in endless mode."))
                                    .font(.system(size: 13)).foregroundStyle(Theme.dim)
                                Rectangle().fill(Theme.line).frame(height: 1).padding(.top, 10)
                            }
                            .id("scenarios")
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 26) {
                                ForEach(gridScenarios, id: \.id) { s in
                                    ScenarioCard(scenario: s, endingsFound: model.gallery.unlocked[s.id]?.count ?? 0, image: model.art.image(s.id)) { model.screen = .setup(s.id) }
                                }
                            }
                            if !model.loadErrors.isEmpty {
                                Panel {
                                    VStack(alignment: .leading, spacing: 6) {
                                        SectionLabel(text: L("有场景文件加载失败", "Some scenario files failed to load"))
                                        ForEach(model.loadErrors, id: \.self) { Text($0).font(.system(size: 12)).foregroundStyle(Theme.danger) }
                                    }
                                }
                            }
                            footer
                        }
                        .padding(.horizontal, 48)
                        .padding(.bottom, 40)
                    }
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    // e.g. "Pick one" at the end of the tutorial
                    if let t = model.homeScrollTarget {
                        model.homeScrollTarget = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation(.easeInOut(duration: 0.6)) { proxy.scrollTo(t, anchor: .top) }
                        }
                    }
                }
            }
        }
        .onAppear { model.art.load(model.scenarios.filter { !$0.isTutorial }) }
        .task(id: heroTick) {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                if Task.isCancelled { break }
                withAnimation(.easeInOut(duration: 1.4)) { heroIndex += 1 }
            }
        }
    }

    // MARK: Hero

    func hero(height: CGFloat, proxy: ScrollViewProxy) -> some View {
        let list = heroScenarios
        let s: Scenario? = list.isEmpty ? nil : list[((heroIndex % list.count) + list.count) % list.count]
        return ZStack(alignment: .bottomLeading) {
            ZStack {
                Theme.bg
                if let s {
                    CoverHero(scenario: s)
                        .id(s.id)
                        .transition(.opacity)
                }
            }
            .frame(height: height)
            .clipped()

            // scrims only for legibility: the toolbar at the top, the title on the left, the page at the bottom
            LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.18))
            LinearGradient(colors: [.black.opacity(0.78), .black.opacity(0.4), .clear], startPoint: .leading, endPoint: UnitPoint(x: 0.66, y: 0.5))
            LinearGradient(colors: [.clear, Theme.bg.opacity(0.6), Theme.bg], startPoint: UnitPoint(x: 0.5, y: 0.6), endPoint: .bottom)

            VStack(alignment: .leading, spacing: 14) {
                Text(model.uiLang == .en ? "A SURVIVAL GAME" : "生存决策游戏")
                    .font(.system(size: 12, weight: .medium)).tracking(model.uiLang == .en ? 3 : 1)
                    .foregroundStyle(.white.opacity(0.62))
                Text(L("绝境", "BRINK"))
                    .font(model.uiLang == .en ? .system(size: 96, weight: .bold, design: .serif) : .custom(Theme.serif, size: 104).weight(.bold))
                    .tracking(model.uiLang == .en ? 6 : 12)
                    .foregroundStyle(Theme.text)
                Text(L("\(Self.spelled(list.count))场真实的灾难。你，和几个大模型扮演的幸存者。", "\(Self.spelled(list.count)) real disasters. You, and survivors played by AI models."))
                    .font(Theme.prose(19))
                    .foregroundStyle(.white.opacity(0.86))
                let hasSave = model.autosave.map { $0.state.phase != .ended } ?? false
                // first time here: the tutorial is the big button
                let firstTime = !model.tutorialDone && !hasSave && model.latestRun == nil
                HStack(spacing: 10) {
                    if !model.tutorialDone {
                        Button(L("新手教程 · 10 分钟", "Tutorial · 10 min")) { model.startTutorial() }
                            .buttonStyle(CoverButtonStyle(prominent: firstTime))
                            .help(L("第一次玩？跟着提示打一局短的", "New here? Play a short game with tips"))
                    }
                    if let save = model.autosave, save.state.phase != .ended {
                        let title = save.title ?? model.scenario(save.scenarioId)?.title ?? save.scenarioId
                        Button(L("继续：\(title) · 第 \(save.state.round) 回合", "Continue: \(title) · round \(save.state.round)")) { model.resume() }
                            .buttonStyle(CoverButtonStyle(prominent: true))
                            .keyboardShortcut(.defaultAction)
                    }
                    if let run = model.latestRun {
                        Button(L("继续征程", "Continue the run") + " · " + run.progress) { model.continueLatestRun() }
                            .buttonStyle(CoverButtonStyle(prominent: !hasSave))
                    } else {
                        Button(L("开始无尽模式", "Start endless mode")) { model.screen = .runSetup }
                            .buttonStyle(CoverButtonStyle(prominent: !hasSave && !firstTime))
                    }
                    Button(L("选一个场景", "Pick a disaster")) {
                        withAnimation(.easeInOut(duration: 0.5)) { proxy.scrollTo("scenarios", anchor: .top) }
                    }
                    .buttonStyle(CoverButtonStyle(prominent: false))
                }
                .padding(.top, 8)
                if let s { heroCaption(s, count: list.count) }
            }
            .padding(.leading, 56)
            .padding(.bottom, 52)
            .padding(.trailing, 40)
        }
        .frame(height: height)
        .overlay(alignment: .topTrailing) { toolbar.padding(.top, 16).padding(.trailing, 22) }
    }

    /// "‹ 03 / 08 › 矿难 · 2010 智利 — tagline": which cover is showing, as plain text.
    func heroCaption(_ s: Scenario, count: Int) -> some View {
        let i = ((heroIndex % count) + count) % count
        return HStack(spacing: 12) {
            Button { step(-1) } label: { Text("‹").font(.system(size: 17)) }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.7))
                .help(L("上一个", "Previous"))
            Text(String(format: "%02d / %02d", i + 1, count))
                .font(.system(size: 12).monospacedDigit()).foregroundStyle(.white.opacity(0.6))
            Button { step(1) } label: { Text("›").font(.system(size: 17)) }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.7))
                .help(L("下一个", "Next"))
            Button { model.screen = .setup(s.id) } label: {
                HStack(spacing: 8) {
                    Text("\(s.title) · \(s.subtitle)").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.92))
                    Text(s.tagline).font(.system(size: 12)).foregroundStyle(.white.opacity(0.62)).lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .help(L("打开这个场景", "Open this scenario"))
        }
        .padding(.top, 12)
        .frame(maxWidth: 760, alignment: .leading)
    }

    func step(_ d: Int) {
        withAnimation(.easeInOut(duration: 1.0)) { heroIndex += d }
        heroTick += 1
    }

    var toolbar: some View {
        HStack(spacing: 2) {
            Button(L("我", "Me")) { model.screen = .me }
                .buttonStyle(CoverToolStyle())
                .help(L("我的资格证和考试记录", "My certificates and exam record"))
            Button(L("读取存档", "Load game")) { model.showSaves = true }
                .buttonStyle(CoverToolStyle())
            Button(L("考场", "Exams")) { model.screen = .examHall }
                .buttonStyle(CoverToolStyle())
                .help(L("练习资格考试，或者让大模型来考", "Practise the certificate exams, or let an AI model sit them"))
            Button(L("模型战绩", "Leaderboard")) { model.screen = .leaderboard }
                .buttonStyle(CoverToolStyle())
            DifficultyButton(place: .cover)
            Button(L("设置", "Settings")) { model.showSettings = true }
                .buttonStyle(CoverToolStyle())
            Menu {
                Button { model.setLanguage(nil) } label: { Text(L("跟随系统", "Follow the system")) + Text(model.config.language == nil ? " ✓" : "") }
                Button { model.setLanguage("zh") } label: { Text("中文" + (model.config.language == "zh" ? " ✓" : "")) }
                Button { model.setLanguage("en") } label: { Text("English" + (model.config.language == "en" ? " ✓" : "")) }
            } label: { Text(model.uiLang == .en ? "EN" : "中文").font(.system(size: 12, weight: .medium)) }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.horizontal, 10).padding(.vertical, 6)
            .help(L("界面语言", "Language"))
            Menu {
                Button(L("新手教程", "Tutorial")) { model.startTutorial() }
                Divider()
                Button(L("打开自定义场景文件夹", "Open custom scenarios folder")) {
                    let dir = ScenarioLibrary.userDirectory()
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(dir)
                }
                Button(L("重新加载场景", "Reload scenarios")) { model.reloadScenarios() }
                Button(L("打开对局记录文件夹", "Open game logs folder")) { NSWorkspace.shared.open(AppPaths.logs) }
            } label: { Image(systemName: "ellipsis") }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.horizontal, 10).padding(.vertical, 6)
            .help(L("更多", "More"))
        }
        .environment(\.colorScheme, .dark)
    }

    var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            modelsLine
            Text(Self.versionLine).font(.system(size: 11)).foregroundStyle(Theme.faint)
        }
    }

    /// "Version 1.2.0 (120)": so it's plain which build is open.
    static var versionLine: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return L("绝境 Brink · 版本 \(v)（\(b)）", "Brink · version \(v) (\(b))")
    }

    var modelsLine: some View {
        let n = model.config.availableModels.count
        return Text(n > 0
                    ? L("已配置 \(n) 个可用模型。开局时可以给每个角色分配不同的模型，让它们互相较量。", "\(n) model(s) ready. When you start a game you can give each character a different model and watch them go at it.")
                    : L("还没有配置任何大模型的 API key，AI 角色会由离线的基础人机扮演。点右上角“设置”填入 Kimi、GLM、DeepSeek 等的 key。",
                        "No AI model API keys yet, so offline basic bots play the other characters. Open Settings (top right) to add keys for Kimi, GLM, DeepSeek and others."))
            .font(.system(size: 12))
            .foregroundStyle(n > 0 ? Theme.faint : Theme.warn)
            .padding(.top, 6)
    }
}

/// The hero's picture: the still right away, the live drifting scene over it once it's built.
struct CoverHero: View {
    @Environment(AppModel.self) private var model
    let scenario: Scenario

    var body: some View {
        ZStack {
            if SceneDisplay.stills {
                // screenshots: a full-resolution still of the same view
                CoverStill(state: model.art.state(scenario))
            } else {
                if let img = model.art.image(scenario.id) {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                }
                CoverSceneView(state: model.art.state(scenario))
            }
        }
    }
}

/// Buttons on the cover: bone-white for the main action, a dark plate with a hairline for the rest.
/// No blur, no shadow: they sit on a scrim already.
struct CoverButtonStyle: ButtonStyle {
    var prominent: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .foregroundStyle(prominent ? Theme.bg : Theme.text)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(prominent ? Theme.flare.opacity(configuration.isPressed ? 0.8 : 1) : Color.black.opacity(configuration.isPressed ? 0.6 : 0.42))
            )
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(.white.opacity(prominent ? 0 : 0.28), lineWidth: 1))
    }
}

/// Plain text links in the cover's top-right corner.
struct CoverToolStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.55 : 0.86))
            .contentShape(Rectangle())
    }
}

// MARK: - Scenario cards

/// A plate and a caption, like a page in a field guide: the picture, then the title, the line, the facts.
struct ScenarioCard: View {
    let scenario: Scenario
    var endingsFound = 0
    var image: NSImage?
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    if let image {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Theme.panelHi
                    }
                }
                .frame(height: 164)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(Rectangle().stroke(hover ? Theme.dim.opacity(0.7) : Theme.line, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(scenario.title).font(Theme.title(22)).foregroundStyle(Theme.text)
                        Text(scenario.subtitle).font(.system(size: 12)).foregroundStyle(Theme.dim)
                        Spacer(minLength: 0)
                    }
                    Text(scenario.tagline)
                        .font(Theme.prose(14))
                        .foregroundStyle(Theme.text.opacity(0.82))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 0) {
                        Text(facts).font(.system(size: 11)).foregroundStyle(Theme.faint)
                        Spacer(minLength: 8)
                        DifficultyMarks(level: scenario.difficulty)
                    }
                    .padding(.top, 2)
                }
                .padding(.top, 12)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
    }

    var facts: String {
        var parts = [L("\(scenario.characters.count) 名可选角色", "\(scenario.characters.count) playable")]
        if let n = scenario.npcs?.count, n > 0 { parts.append(L("\(n) 个 NPC", "\(n) NPCs")) }
        if endingsFound > 0 { parts.append(L("结局 \(endingsFound)/\(scenario.endings.count)", "endings \(endingsFound)/\(scenario.endings.count)")) }
        return parts.joined(separator: " · ")
    }
}

/// Difficulty as five short bars.
struct DifficultyMarks: View {
    let level: Int
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                Rectangle().fill(i < level ? Theme.dim : Theme.line).frame(width: 7, height: 3)
            }
        }
        .help(L("难度 \(level)/5", "Difficulty \(level)/5"))
    }
}

// MARK: - Endless mode

/// The endless mode's feature plate: the finale's snowy night behind it.
struct EndlessFeature: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let found = (model.gallery.unlocked["_grand"] ?? []).count
        let questions = model.library.map(\.questions.count).reduce(0, +)
        ZStack(alignment: .leading) {
            Group {
                if let img = model.art.image(EndlessRun.finaleId) {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Theme.panelHi
                }
            }
            .frame(height: 256)
            .frame(maxWidth: .infinity)
            .clipped()
            LinearGradient(colors: [.black.opacity(0.88), .black.opacity(0.6), .clear], startPoint: .leading, endPoint: UnitPoint(x: 0.8, y: 0.5))
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(L("无尽模式", "Endless")).font(Theme.title(34)).foregroundStyle(Theme.text)
                    Text(L("八场推演，一场真的", "Eight drills. One that's real.")).font(Theme.prose(16)).foregroundStyle(.white.opacity(0.7))
                }
                Text(L("你和四个 AI 玩家一关接一关地闯八场灾难，每关扮演不同的人。攒经验、升级、考资格证、加技能点；八场之后是终章——这一次不是推演，你们以自己的身份出场。打完，看大结局。",
                       "You and four AI players take on the eight disasters one after another, playing someone new each time. Earn experience, level up, sit certificate exams, spend skill points. After the eight comes the finale — this time it isn't a drill, and you play yourselves. Then the grand ending."))
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: 560, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text([L("\(model.library.count) 张资格证 · \(questions) 道真题", "\(model.library.count) certificates · \(questions) real questions"),
                      L("经验 · 等级 · 技能点", "XP · levels · skill points"),
                      L("大结局 \(found)/\(GrandEndings.all.count)", "grand endings \(found)/\(GrandEndings.all.count)")].joined(separator: "   ·   "))
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                HStack(spacing: 10) {
                    if let save = model.latestRun {
                        Button(L("继续：", "Continue: ") + save.progress) { model.continueLatestRun() }
                            .buttonStyle(CoverButtonStyle(prominent: true))
                        Button(L("新的征程", "New run")) { model.screen = .runSetup }.buttonStyle(CoverButtonStyle(prominent: false))
                    } else {
                        Button(L("开始征程", "Start a run")) { model.screen = .runSetup }
                            .buttonStyle(CoverButtonStyle(prominent: true))
                    }
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 30)
        }
        .frame(height: 256)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.line, lineWidth: 1))
    }
}
