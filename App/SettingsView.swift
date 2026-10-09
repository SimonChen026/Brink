import SwiftUI
import BrinkCore

struct SettingsView: View {
    @State private var confirmClear = false
    @State private var clearCerts = false
    @State private var clearedCount: Int?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var selected: String = "deepseek"
    @State private var status: [String: String] = [:]
    @State private var statusOK: [String: Bool] = [:]
    @State private var busy: Set<String> = []
    @State private var newModel = ""

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            List(selection: $selected) {
                Section(L("通用", "General")) {
                    Label(L("语言与显示", "Language & display"), systemImage: "globe").tag("general")
                }
                Section(L("大模型", "AI models")) {
                    ForEach(model.config.providers) { p in
                        HStack {
                            Circle().fill(p.isUsable ? Theme.good : (p.enabled ? Theme.warn : Theme.line)).frame(width: 7, height: 7)
                            Text(p.displayName)
                        }
                        .tag(p.id)
                    }
                }
            }
            .frame(width: 220)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(selected == "general" ? L("设置", "Settings") : L("模型设置", "Model settings")).font(Theme.title(22))
                    Spacer()
                    Button(L("完成", "Done")) { model.saveConfig(); dismiss() }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.cancelAction)
                }
                .padding(20)
                if selected == "general" {
                    generalForm
                } else if let idx = model.config.providers.firstIndex(where: { $0.id == selected }) {
                    providerForm($model.config.providers[idx])
                }
            }
        }
        .background(Theme.bg)
        .onDisappear { model.saveConfig() }
    }

    var generalForm: some View {
        Form {
            Section(L("语言", "Language")) {
                Picker(L("界面和新对局的语言", "Interface and new games"), selection: Binding(
                    get: { model.config.language ?? "system" },
                    set: { model.setLanguage($0 == "system" ? nil : $0) })) {
                    Text(L("跟随系统", "Follow the system")).tag("system")
                    Text("中文").tag("zh")
                    Text("English").tag("en")
                }
                Text(L("切换后，界面、场景内容、AI 的提示词和基础人机的台词都会换成新的语言。已经开始的对局（包括存档）保持原来的语言。",
                       "Switching changes the interface, scenario text, the prompts the AI players get and the basic bots' lines. Games already in progress (and saves) keep their language."))
                    .font(.system(size: 11)).foregroundStyle(Theme.dim)
            }
            Section(L("对局节奏", "Pace")) {
                Toggle(L("新对局和无尽模式默认用快节奏：大模型分工时一并决定夜里的事", "Use fast pace by default for new games and endless runs: AI models decide the night along with the day's work"), isOn: Binding(
                    get: { model.config.fastPace ?? true },
                    set: { model.config.fastPace = $0; model.saveConfig() }))
                Picker(L("每次调用最多等", "Longest wait for one call"), selection: Binding(
                    get: { Int(model.config.callTimeoutSeconds) },
                    set: { model.config.callTimeout = Double($0); model.saveConfig() })) {
                    ForEach([45, 60, 90, 120, 240], id: \.self) { Text(L("\($0) 秒", "\($0) s")).tag($0) }
                }
                Text(L("超过这个时间还没回答，这一步就由基础人机先替它做，游戏不会被一个慢模型卡住。智谱 GLM 想再快一点，可以在它的“额外参数”里填 {\"thinking\":{\"type\":\"disabled\"}} 关掉深度思考。",
                       "If a model hasn't answered by then, a basic bot takes that step for it, so one slow model can't hold up the game. To speed up Zhipu GLM further, put {\"thinking\":{\"type\":\"disabled\"}} in its “Extra parameters” to turn off deep thinking."))
                    .font(.system(size: 11)).foregroundStyle(Theme.dim)
            }
            Section(L("显示", "Display")) {
                Toggle(L("对局时显示 3D 现场", "Show the live 3D scene during a game"), isOn: Binding(
                    get: { model.config.showScene ?? true },
                    set: { model.config.showScene = $0; model.saveConfig() }))
            }
            Section(L("记录", "Records")) {
                Toggle(L("连“我”的资格证和考试记录也一起清空", "Also clear my certificates and exam record"), isOn: $clearCerts)
                HStack {
                    Text(L("把对局记录、模型战绩、结局图鉴、练习成绩和所有存档（含无尽征程）移到废纸篓。设置和 API key 不受影响。",
                           "Moves game logs, the model leaderboard, the endings gallery, practice scores and every save (endless runs included) to the Trash. Settings and API keys stay."))
                        .font(.system(size: 11)).foregroundStyle(Theme.dim)
                    Spacer()
                    Button(L("清空记录…", "Clear records…"), role: .destructive) { confirmClear = true }
                }
                if let n = clearedCount {
                    Text(L("已移到废纸篓：\(n) 个文件。", "Moved to the Trash: \(n) file(s).")).font(.system(size: 11)).foregroundStyle(Theme.good)
                }
            }
        }
        .formStyle(.grouped)
        .alert(L("清空记录？", "Clear records?"), isPresented: $confirmClear) {
            Button(L("清空", "Clear"), role: .destructive) { clearedCount = model.clearRecords(includeCertificates: clearCerts) }
            Button(L("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(clearCerts ? L("对局记录、战绩、结局、存档，以及你的资格证，都会移到废纸篓。", "Logs, the leaderboard, endings, saves and your certificates will go to the Trash.")
                            : L("对局记录、战绩、结局和存档会移到废纸篓；资格证保留。", "Logs, the leaderboard, endings and saves will go to the Trash; your certificates stay."))
        }
    }

    @ViewBuilder
    func providerForm(_ p: Binding<ProviderProfile>) -> some View {
        Form {
            Section {
                Toggle(L("启用", "Enabled"), isOn: p.enabled)
                TextField(L("名称", "Name"), text: p.name)
                Picker(L("协议", "Protocol"), selection: p.kind) {
                    ForEach(ProviderKind.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                TextField("Base URL", text: p.baseURL)
                SecureField("API Key", text: p.apiKey)
                Text(L("保存在 macOS 钥匙串里，不会写进任何文件。", "Stored in the macOS Keychain, never in a file."))
                    .font(.system(size: 11)).foregroundStyle(Theme.dim)
                if let env = p.wrappedValue.envKey {
                    let found = ProcessInfo.processInfo.environment[env] != nil
                    Text(L("也可以不填，改用环境变量 \(env)\(found ? "（已检测到）" : "")", "Or leave it empty and use the environment variable \(env)\(found ? " (found)" : "")"))
                        .font(.system(size: 11)).foregroundStyle(Theme.dim)
                }
                if let note = p.wrappedValue.displayNote {
                    Text(note).font(.system(size: 11)).foregroundStyle(Theme.dim)
                }
            }
            Section(L("模型（每一个都可以单独分配给一个角色）", "Models (each one can be given its own character)")) {
                ForEach(Array(p.wrappedValue.models.enumerated()), id: \.offset) { i, m in
                    HStack {
                        Text(m).font(.system(size: 12, design: .monospaced))
                        Spacer()
                        Button { p.wrappedValue.models.remove(at: i) } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField(L("添加模型名，例如 deepseek-chat", "Add a model name, e.g. deepseek-chat"), text: $newModel)
                    Button(L("添加", "Add")) {
                        let m = newModel.trimmingCharacters(in: .whitespaces)
                        if !m.isEmpty && !p.wrappedValue.models.contains(m) { p.wrappedValue.models.append(m) }
                        newModel = ""
                    }
                }
                HStack {
                    Button(busy.contains("list") ? L("拉取中…", "Fetching…") : L("拉取模型列表", "Fetch model list")) { fetchModels(p) }
                        .disabled(busy.contains("list"))
                    Button(busy.contains("test") ? L("测试中…", "Testing…") : L("测试连接", "Test connection")) { test(p.wrappedValue) }
                        .disabled(busy.contains("test") || p.wrappedValue.models.isEmpty)
                    if let s = status[p.wrappedValue.id] {
                        Text(s).font(.system(size: 11)).foregroundStyle(statusOK[p.wrappedValue.id] == true ? Theme.good : Theme.danger).lineLimit(3).textSelection(.enabled)
                    }
                }
            }
            Section(L("高级", "Advanced")) {
                Toggle(L("要求 JSON 输出（response_format）", "Ask for JSON output (response_format)"), isOn: p.jsonMode)
                HStack {
                    Text(L("温度", "Temperature"))
                    Slider(value: p.temperature, in: 0...1.5, step: 0.1)
                    Text(String(format: "%.1f", p.wrappedValue.temperature)).monospacedDigit()
                }
                Stepper(L("最多同时请求 \(p.wrappedValue.maxConcurrent) 个", "At most \(p.wrappedValue.maxConcurrent) requests at a time"), value: p.maxConcurrent, in: 1...10)
                TextField(L("额外请求参数（JSON）", "Extra request parameters (JSON)"), text: p.extraBody, axis: .vertical)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(2...4)
            }
        }
        .formStyle(.grouped)
    }

    func fetchModels(_ p: Binding<ProviderProfile>) {
        busy.insert("list")
        let profile = p.wrappedValue
        Task {
            do {
                let list = try await LLMClient(timeout: 20).listModels(profile: profile)
                await MainActor.run {
                    let chat = list.filter { !$0.contains("embed") && !$0.contains("tts") && !$0.contains("whisper") && !$0.contains("image") }
                    for m in chat.prefix(30) where !p.wrappedValue.models.contains(m) { p.wrappedValue.models.append(m) }
                    status[profile.id] = L("拉取到 \(list.count) 个模型", "Found \(list.count) models")
                    statusOK[profile.id] = true
                    busy.remove("list")
                }
            } catch {
                await MainActor.run {
                    status[profile.id] = L("失败：", "Failed: ") + Redact.text("\(error)")
                    statusOK[profile.id] = false
                    busy.remove("list")
                }
            }
        }
    }

    func test(_ profile: ProviderProfile) {
        guard let m = profile.models.first else { return }
        busy.insert("test")
        Task {
            do {
                let r = try await LLMClient(timeout: 25).complete(profile: profile, model: m, system: L("你是一个测试助手。只输出 JSON。", "You are a test assistant. Output JSON only."),
                                                      user: L("输出 {\"ok\": true, \"msg\": \"用一句话打个招呼\"}", "Output json: {\"ok\": true, \"msg\": \"say hello in one sentence\"}"), jsonMode: true, maxTokens: 120, temperature: 0.7)
                await MainActor.run {
                    status[profile.id] = L("连接正常 · ", "Connected · ") + "\(m) \(String(format: "%.1f", r.seconds))s" + Loc.colon(Loc.ui) + Redact.text(String(r.text.prefix(80)))
                    statusOK[profile.id] = true
                    busy.remove("test")
                }
            } catch {
                await MainActor.run {
                    status[profile.id] = L("失败：", "Failed: ") + Redact.text("\(error)")
                    statusOK[profile.id] = false
                    busy.remove("test")
                }
            }
        }
    }
}

struct LeaderboardView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmReset = false
    @State private var store = ModelStatsStore.load()

    static func examText(_ r: ModelRecord) -> String {
        guard let t = r.examsTaken, t > 0 else { return "—" }
        let pct = Int((r.examAccuracy ?? 0) * 100)
        return L("过 \(r.examsPassed ?? 0)/\(t) · 答对 \(pct)%", "\(r.examsPassed ?? 0)/\(t) passed · \(pct)% right")
    }

    var body: some View {
        let rows = store.records.values.sorted { $0.avgScore > $1.avgScore }
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Button { model.screen = .home } label: { Label(L("返回", "Back"), systemImage: "chevron.left") }.buttonStyle(.plain).foregroundStyle(Theme.dim)
                Spacer()
            }
            HStack(alignment: .firstTextBaseline) {
                Text(L("模型战绩", "Model leaderboard")).font(Theme.title(40))
                Spacer()
                if store.games > 0 {
                    Button(L("清空战绩…", "Reset…")) { confirmReset = true }
                        .buttonStyle(GhostButtonStyle())
                        .alert(L("清空模型战绩？", "Reset the leaderboard?"), isPresented: $confirmReset) {
                            Button(L("移到废纸篓", "Move to Trash"), role: .destructive) {
                                if FileManager.default.fileExists(atPath: ModelStatsStore.url.path) {
                                    try? FileManager.default.trashItem(at: ModelStatsStore.url, resultingItemURL: nil)
                                }
                                store = ModelStatsStore.load()
                            }
                            Button(L("取消", "Cancel"), role: .cancel) {}
                        } message: {
                            Text(L("战绩文件会移到废纸篓，需要的话可以放回来。", "The leaderboard file goes to the Trash; you can put it back if you change your mind."))
                        }
                }
            }
            Text(L("每一局结束后，扮演每个角色的模型都会记一次分：活下来 50 分，完成个人目标 30 分，再按全队存活比例加最多 20 分。一共 \(store.games) 局。无尽模式里大模型玩家真的去答资格考试，成绩也记在这里。",
                   "After every game, each model that played a character is scored: 50 for surviving, 30 for the personal goal, and up to 20 for how many of the group made it. \(store.games) game(s) so far. In endless mode the AI-model players really sit the certificate exams; their results are here too."))
                .font(.system(size: 13)).foregroundStyle(Theme.dim)
            if rows.isEmpty {
                Panel { Text(L("还没有完成的对局。去打一局，或者开一局观战，让几个大模型斗一斗。", "No finished games yet. Play one — or start a spectator game and let a few models fight it out.")).foregroundStyle(Theme.dim) }
            } else {
                Table(rows) {
                    TableColumn(L("模型", "Model")) { r in Text(ModelStatsStore.displayName(r.id)).font(.system(size: 13, weight: .semibold)) }
                        .width(min: 180, ideal: 240)
                    TableColumn(L("局数", "Games")) { r in Text("\(r.games)").monospacedDigit() }.width(50)
                    TableColumn(L("平均分", "Avg score")) { r in Text(String(format: "%.1f", r.avgScore)).monospacedDigit() }.width(70)
                    TableColumn(L("存活率", "Survived")) { r in Text("\(Int(r.survivalRate * 100))%").monospacedDigit() }.width(60)
                    TableColumn(L("完成目标", "Goals")) { r in Text("\(r.goals)").monospacedDigit() }.width(70)
                    TableColumn(L("偷吃（被抓）", "Thefts (caught)")) { r in Text("\(r.thefts) (\(r.caught))").monospacedDigit() }.width(100)
                    TableColumn(L("提动议", "Motions")) { r in Text("\(r.motions)").monospacedDigit() }.width(60)
                    TableColumn(L("投票赶人 / 被赶走", "Exile votes / exiled")) { r in Text("\(r.exileVotes) / \(r.exiled)").monospacedDigit() }.width(120)
                    Group {
                        TableColumn(L("当领头人", "Rounds led")) { (r: ModelRecord) in Text("\(r.roundsLed)").monospacedDigit() }.width(80)
                        TableColumn(L("资格考试", "Exams")) { (r: ModelRecord) in
                            Text(LeaderboardView.examText(r)).monospacedDigit().foregroundStyle((r.examsTaken ?? 0) > 0 ? Theme.text : Theme.faint)
                        }
                        .width(150)
                        TableColumn(L("调用/失败", "Calls/failed")) { (r: ModelRecord) in Text("\(r.calls)/\(r.failures)").monospacedDigit() }.width(80)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 4))
            }
            Spacer()
        }
        .padding(36)
        .onAppear { store = ModelStatsStore.load() }
    }
}
