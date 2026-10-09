import SwiftUI
import BrinkCore

struct SetupView: View {
    @Environment(AppModel.self) private var model
    let scenario: Scenario

    @State private var spectator = false
    @State private var me: String = ""
    @State private var seats: [String: String] = [:]
    @State private var debate = true
    @State private var fastPace = false
    @State private var difficulty: Difficulty = .hard
    @State private var seedText = ""
    @State private var delay: Double = 1.2
    @State private var games = 1
    @State private var rotate = true
    @State private var preview: SceneState?
    @State private var previewHour: Double?
    @State private var previewWeather: String?
    @State private var cameraReset = 0

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
            sceneHero
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Button { model.screen = .home } label: { Text(L("‹ 返回", "‹ Back")).font(.system(size: 13)) }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.dim)
                        .keyboardShortcut(.cancelAction)
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(scenario.title).font(Theme.title(42))
                        Text(scenario.subtitle).font(.system(size: 15)).foregroundStyle(Theme.dim)
                    }
                    Text(scenario.tagline).font(Theme.prose(18)).foregroundStyle(Theme.text.opacity(0.85))
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(scenario.briefing, id: \.self) { p in
                            Text(p).font(Theme.prose(15)).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    infoRow
                    Panel {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel(text: L("真实原型", "Based on real events"))
                            Text(scenario.inspiration).font(.system(size: 13)).foregroundStyle(Theme.dim).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let notes = scenario.modelNotes, !notes.isEmpty {
                        Panel {
                            VStack(alignment: .leading, spacing: 8) {
                                SectionLabel(text: L("这个场景模拟了什么", "What this scenario simulates"))
                                ForEach(notes, id: \.self) { n in
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text("—").font(.system(size: 13)).foregroundStyle(Theme.faint)
                                        Text(n).font(.system(size: 13)).foregroundStyle(Theme.dim).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }
                    npcPanel
                    endingsPanel
                }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(32)
            }
            }
            .frame(maxWidth: .infinity)

            Divider().background(Theme.line)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SectionLabel(text: L("怎么玩", "How to play"))
                    Picker("", selection: $spectator) {
                        Text(L("亲自下场", "Play")).tag(false)
                        Text(L("观战：让大模型内斗", "Watch the AI models fight it out")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(spectator ? L("五个角色全部交给 AI。你开着上帝视角，看它们的内心独白、私聊和暗中行动。", "All five characters go to the AI. You watch in God view: their inner thoughts, whispers and secret moves.")
                                   : L("你扮演其中一个人，其他人由大模型或基础人机扮演。你只知道你的角色知道的事。", "You play one of them; AI models or basic bots play the others. You only know what your character knows."))
                        .font(.system(size: 12)).foregroundStyle(Theme.dim)

                    SectionLabel(text: spectator ? L("谁来扮演谁", "Who plays whom") : L("选你的角色，再给其他人分配模型", "Pick your character, then give the others a model"))
                    VStack(spacing: 8) {
                        ForEach(scenario.characters, id: \.id) { c in
                            seatRow(c)
                        }
                    }
                    HStack(spacing: 8) {
                        Menu(L("全部用同一个", "Same for everyone")) {
                            ForEach(model.seatOptions, id: \.id) { o in
                                Button(o.label) { for c in scenario.characters where c.id != meId { seats[c.id] = o.id } }
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        Button(L("随机混搭", "Shuffle")) { mix() }.buttonStyle(GhostButtonStyle())
                            .disabled(model.config.availableModels.isEmpty)
                    }
                    if model.config.availableModels.isEmpty {
                        Text(L("还没有可用的大模型。到“设置”里填入 API key 后，这里就能选 Kimi、GLM、DeepSeek 等。", "No AI models available yet. Add an API key in Settings and you can pick Kimi, GLM, DeepSeek and others here."))
                            .font(.system(size: 12)).foregroundStyle(Theme.warn)
                        Button(L("打开设置", "Open Settings")) { model.showSettings = true }.buttonStyle(GhostButtonStyle())
                    }

                    SectionLabel(text: L("难度", "Difficulty"))
                    DifficultyPicker(level: $difficulty)

                    SectionLabel(text: L("选项", "Options"))
                    Toggle(L("大事先表态、辩论一轮再表决（更像真人吵架，但调用次数更多）", "For big decisions, state positions and argue once before the vote (more like real people arguing, but more model calls)"), isOn: $debate)
                        .font(.system(size: 13))
                    Toggle(L("快节奏：大模型白天分工时，一并想好晚上私下做什么（每天少问一到两轮，快很多）", "Fast pace: AI models decide tonight's private moves along with the day's work (one or two fewer rounds of calls a day — much faster)"), isOn: $fastPace)
                        .font(.system(size: 13))
                    HStack {
                        Text(L("随机种子", "Random seed")).font(.system(size: 13))
                        TextField(L("留空 = 随机", "empty = random"), text: $seedText).textFieldStyle(.roundedBorder).frame(width: 140)
                    }
                    if spectator {
                        HStack {
                            Stepper(L("连续打 \(games) 局", "\(games) game(s) in a row"), value: $games, in: 1...30).font(.system(size: 13))
                            Toggle(L("每局轮换角色", "Rotate roles"), isOn: $rotate).font(.system(size: 13)).disabled(games < 2)
                        }
                        if games > 1 {
                            Text(L("每一局结束后自动开下一局，换一个随机种子；轮换角色时，每个模型会轮流扮演不同的人，战绩更公平。打完自动打开“模型战绩”。",
                                   "Each game starts the next with a new seed. With rotation, every model takes a turn at every role, which makes the leaderboard fairer. The leaderboard opens when they're done."))
                                .font(.system(size: 11)).foregroundStyle(Theme.dim)
                        }
                        HStack {
                            Text(L("每步停顿", "Pause per step")).font(.system(size: 13))
                            Slider(value: $delay, in: 0...5, step: 0.5).frame(width: 160)
                            Text(L("\(String(format: "%.1f", delay)) 秒", "\(String(format: "%.1f", delay)) s")).font(.system(size: 12)).foregroundStyle(Theme.dim).monospacedDigit()
                        }
                    }

                    let llmSeats = scenario.characters.filter { c in (spectator || c.id != me) && (seats[c.id] ?? "rule") != "rule" }.count
                    if llmSeats > 0 {
                        let perRound = Double(llmSeats) * (debate ? 3.7 : 3.0) - (fastPace ? Double(llmSeats) : 0)
                        let rounds = Double(scenario.clock.maxRounds) * 0.7
                        let calls = max(10, Int((perRound * rounds / 10).rounded()) * 10), tokens = max(1, Int((perRound * rounds * 1.3 / 10).rounded()))
                        Text(L("预计：每回合约 \(Int(perRound)) 次模型调用，一局约 \(calls) 次、\(tokens) 万 token 上下（大部分是输入）。DeepSeek、Kimi、GLM 等都会自动缓存相同的前缀，实际花费会更低。",
                               "Estimate: about \(Int(perRound)) model calls per round, roughly \(calls) per game and around \(tokens * 10)k tokens (mostly input). DeepSeek, Kimi, GLM and others cache repeated prefixes automatically, so the real cost is lower."))
                            .font(.system(size: 11)).foregroundStyle(Theme.faint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button {
                        startGame()
                    } label: {
                        Text(spectator ? L("开始观战", "Start watching") : L("开始", "Start"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!spectator && me.isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("⌘↩")
                    .padding(.top, 6)
                }
                .padding(28)
            }
            .frame(width: 430)
            .background(Theme.panel.opacity(0.5))
        }
        .onAppear(perform: setup)
    }

    var meId: String? { spectator ? nil : (me.isEmpty ? nil : me) }

    /// The other people in the story (NPCs: hurt, old, young, passers-by, animals …).
    @ViewBuilder
    var npcPanel: some View {
        if let npcs = scenario.npcs, !npcs.isEmpty {
            Panel {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: L("还有这些人（NPC，不参与决策）", "Also there (NPCs — they don't vote)"))
                    ForEach(npcs, id: \.id) { n in
                        HStack(alignment: .top, spacing: 10) {
                            Avatar(id: n.id, name: n.name, size: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(n.name).font(.system(size: 13, weight: .semibold))
                                    Text(n.isAnimal ? n.role : L("\(n.age)岁 · \(n.role)", "\(n.age) · \(n.role)")).font(.system(size: 11)).foregroundStyle(Theme.dim).lineLimit(1)
                                    if n.joinsLater ?? false { Chip(text: L("中途出现", "turns up later"), color: Theme.faint) }
                                    if n.autoTask != nil { Chip(text: L("会帮忙", "helps out"), color: Theme.faint) }
                                }
                                Text(n.bio).font(.system(size: 11)).foregroundStyle(Theme.faint).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Endings found so far (titles of the rest stay hidden).
    var endingsPanel: some View {
        let found = scenario.endings.filter { model.gallery.has(scenario.id, $0.id) }.count
        return Panel {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: L("结局 \(found)/\(scenario.endings.count)", "Endings \(found)/\(scenario.endings.count)"))
                ForEach(scenario.endings, id: \.id) { e in
                    let has = model.gallery.has(scenario.id, e.id)
                    HStack(spacing: 8) {
                        Rectangle().fill(has ? Theme.tone(e.tone ?? "bitter") : Theme.line).frame(width: 8, height: 2)
                        Text(has ? e.title : L("尚未解锁", "Not found yet")).font(.system(size: 13, weight: has ? .semibold : .regular))
                            .foregroundStyle(has ? Theme.text : Theme.faint)
                    }
                }
                Text(L("结局由你们的选择和运气决定。每个人还有自己的尾声。", "Endings depend on your choices and on luck. Everyone also gets their own epilogue."))
                    .font(.system(size: 11)).foregroundStyle(Theme.faint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The scenario's 3D scene: drag to look around; try other times of day and weather.
    var sceneHero: some View {
        ZStack(alignment: .bottom) {
            if let st = previewState {
                SceneDisplay(state: st, resetToken: cameraReset)
            } else {
                Theme.panel
            }
            HStack(spacing: 8) {
                Picker("", selection: Binding(get: { previewHour ?? -1 }, set: { previewHour = $0 < 0 ? nil : $0 })) {
                    Text(L("开局时", "Start")).tag(-1.0)
                    Text(L("清晨", "Dawn")).tag(7.0)
                    Text(L("正午", "Noon")).tag(13.0)
                    Text(L("黄昏", "Dusk")).tag(18.4)
                    Text(L("深夜", "Night")).tag(23.0)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 300)
                Menu {
                    Button(L("开局天气", "Starting weather")) { previewWeather = nil }
                    ForEach(scenario.climate.weather.keys.sorted(), id: \.self) { k in
                        Button(scenario.climate.weather[k]?.name ?? k) { previewWeather = k }
                    }
                } label: {
                    Label(previewWeather.flatMap { scenario.climate.weather[$0]?.name } ?? L("天气", "Weather"), systemImage: "cloud.sun")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer()
                Text(L("拖动旋转 · 滚动缩放", "Drag to orbit · scroll to zoom")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                Button { cameraReset += 1 } label: { Image(systemName: "scope") }
                    .buttonStyle(.plain)
                    .help(L("回到默认视角", "Reset the view"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.black.opacity(0.35))
        }
        .frame(height: 330)
        .clipped()
    }

    var previewState: SceneState? {
        guard var st = preview else { return nil }
        if let h = previewHour {
            st.hour = h
            st.fireLit = scenario.shelter.fire != nil && (h >= 18 || h < 6)
        }
        if let w = previewWeather, let def = scenario.climate.weather[w] {
            st.weather = w
            st.precip = def.precip ?? 0
            st.wind = def.wind ?? 10
            st.visibility = def.visibility ?? 1
            st.sun = def.sun ?? 1
        }
        return st
    }

    /// Where, when and how long, as one line of plain facts (wraps when it has to).
    var infoRow: some View {
        var facts = [scenario.setting.location]
        if let alt = scenario.setting.altitude { facts.append(L("海拔 \(Int(alt)) 米", "\(Int(alt)) m above sea level")) }
        if let d = scenario.setting.date { facts.append(d) }
        facts.append(L("每回合 \(scenario.clock.roundHours) 小时，最多 \(scenario.clock.maxRounds) 回合", "\(scenario.clock.roundHours) h per round, up to \(scenario.clock.maxRounds) rounds"))
        return Text(facts.joined(separator: "  ·  "))
            .font(.system(size: 12)).foregroundStyle(Theme.dim)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    func seatRow(_ c: CharacterDef) -> some View {
        let isMe = !spectator && me == c.id
        HStack(alignment: .top, spacing: 10) {
            Avatar(id: c.id, name: c.name, size: 32)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(c.name).font(.system(size: 14, weight: .semibold))
                    Text(L("\(c.age)岁 · \(c.role)", "\(c.age) · \(c.role)")).font(.system(size: 12)).foregroundStyle(Theme.dim).lineLimit(1)
                }
                Text(c.bio).font(.system(size: 11)).foregroundStyle(Theme.faint).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Text(Skill.all.filter { c.skill($0) > 0 }.map { "\(Skill.names[$0]!) \(c.skill($0))" }.joined(separator: " · "))
                    .font(.system(size: 11)).foregroundStyle(Theme.dim)
                if isMe {
                    Text(L("这是你", "This is you")).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.flare)
                } else {
                    Picker("", selection: Binding(get: { seats[c.id] ?? "rule" }, set: { seats[c.id] = $0 })) {
                        ForEach(model.seatOptions, id: \.id) { o in Text(o.label).tag(o.id) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 260)
                    .help(L("基础人机：游戏自带的离线小程序，按角色性格做决定，不联网、不花钱。其他选项是你在设置里配好的大模型。",
                            "Basic bot: a small offline program built into the game that decides by the character's personality — no internet, no cost. The other choices are the AI models you've set up in Settings."))
                }
            }
            Spacer()
            if !spectator {
                Button(isMe ? L("已选", "Chosen") : L("扮演", "Play")) { me = c.id }
                    .buttonStyle(GhostButtonStyle())
                    .disabled(isMe)
            }
        }
        .padding(10)
        .background(isMe ? Theme.panelHi : Color.clear)
        .overlay(alignment: .leading) { Rectangle().fill(isMe ? Theme.flare : Color.clear).frame(width: 2) }
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(isMe ? Theme.flare.opacity(0.5) : Theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    func setup() {
        if preview == nil { preview = SceneState.preview(scenario) }
        debate = model.config.debate
        fastPace = model.config.fastPace ?? true
        difficulty = model.config.newGameDifficulty
        delay = model.config.autoDelay
        let valid = Set(model.seatOptions.map(\.id))
        // Default: one model per configured provider, dealt round-robin, so different vendors face off.
        var perProvider: [String] = []
        for p in model.config.providers where p.isUsable {
            if let m = p.models.first { perProvider.append(ModelRef(providerId: p.id, model: m).id) }
        }
        for (i, c) in scenario.characters.enumerated() {
            if let last = model.config.lastSeats[c.id], valid.contains(last) {
                seats[c.id] = last
            } else if !perProvider.isEmpty {
                seats[c.id] = perProvider[i % perProvider.count]
            } else {
                seats[c.id] = "rule"
            }
        }
        if me.isEmpty { me = scenario.characters.first?.id ?? "" }
    }

    func mix() {
        let models = model.config.availableModels.map(\.id)
        guard !models.isEmpty else { return }
        var pool = models.shuffled()
        for c in scenario.characters where c.id != meId {
            if pool.isEmpty { pool = models.shuffled() }
            seats[c.id] = pool.removeFirst()
        }
    }

    func startGame() {
        var controllers: [String: ControllerKind] = [:]
        for c in scenario.characters {
            if !spectator && c.id == me {
                controllers[c.id] = .human
            } else {
                controllers[c.id] = model.controller(forSeat: seats[c.id] ?? "rule")
            }
        }
        for (k, v) in seats { model.config.lastSeats[k] = v }
        model.config.debate = debate
        model.config.fastPace = fastPace
        model.config.difficulty = difficulty
        model.config.autoDelay = delay
        model.saveConfig()
        if spectator && games > 1 {
            model.startTournament(scenario: scenario, seats: seats, games: games, rotate: rotate, debate: debate, seed: UInt64(seedText.trimmingCharacters(in: .whitespaces)))
            return
        }
        let seed = UInt64(seedText.trimmingCharacters(in: .whitespaces)) ?? UInt64.random(in: 1...999_999)
        var setup = GameSetup(scenarioId: scenario.id, seed: seed, controllers: controllers, debate: debate, spectator: spectator)
        setup.fastPace = fastPace
        setup.difficulty = difficulty
        model.start(scenario: scenario, setup: setup)
    }
}
