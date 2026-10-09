import Foundation

public enum ProviderKind: String, Codable, Sendable, CaseIterable {
    case openAI      // OpenAI-compatible /chat/completions
    case anthropic   // Anthropic Messages API

    public var label: String {
        switch self {
        case .openAI: return L("OpenAI 兼容", "OpenAI-compatible")
        case .anthropic: return "Anthropic"
        }
    }
}

/// A configured LLM provider (one API key, one base URL, several models).
public struct ProviderProfile: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var kind: ProviderKind
    public var baseURL: String
    public var apiKey: String
    public var models: [String]
    public var enabled: Bool
    public var jsonMode: Bool
    public var temperature: Double
    public var maxConcurrent: Int
    /// Extra JSON merged into the request body, e.g. {"thinking":{"type":"disabled"}}
    public var extraBody: String
    public var envKey: String?
    public var note: String?

    public init(id: String, name: String, kind: ProviderKind, baseURL: String, apiKey: String, models: [String], enabled: Bool,
                jsonMode: Bool = true, temperature: Double = 0.9, maxConcurrent: Int = 5, extraBody: String = "", envKey: String? = nil, note: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.models = models
        self.enabled = enabled
        self.jsonMode = jsonMode
        self.temperature = temperature
        self.maxConcurrent = maxConcurrent
        self.extraBody = extraBody
        self.envKey = envKey
        self.note = note
    }

    /// API key from the profile, falling back to the environment variable.
    public var effectiveKey: String {
        if !apiKey.trimmingCharacters(in: .whitespaces).isEmpty { return apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let env = envKey, let v = ProcessInfo.processInfo.environment[env], !v.isEmpty { return v }
        return ""
    }

    public var needsKey: Bool { !baseURL.contains("localhost") && !baseURL.contains("127.0.0.1") }

    public var isUsable: Bool { enabled && !models.isEmpty && (!needsKey || !effectiveKey.isEmpty) }

    public static let presets: [ProviderProfile] = [
        ProviderProfile(id: "deepseek", name: "DeepSeek", kind: .openAI, baseURL: "https://api.deepseek.com", apiKey: "",
                        models: ["deepseek-chat", "deepseek-reasoner"], enabled: true, envKey: "DEEPSEEK_API_KEY",
                        note: "platform.deepseek.com 申请 key。deepseek-chat 速度快、便宜，适合做玩家。"),
        ProviderProfile(id: "kimi", name: "Kimi（月之暗面）", kind: .openAI, baseURL: "https://api.moonshot.cn/v1", apiKey: "",
                        models: ["kimi-k2-turbo-preview", "kimi-k2-0905-preview", "kimi-latest", "moonshot-v1-32k"], enabled: true, envKey: "MOONSHOT_API_KEY",
                        note: "platform.moonshot.cn 申请 key。可以点“拉取模型列表”获取最新型号。"),
        ProviderProfile(id: "glm", name: "智谱 GLM", kind: .openAI, baseURL: "https://open.bigmodel.cn/api/paas/v4", apiKey: "",
                        models: ["glm-4.6", "glm-4.5-air", "glm-4-flash"], enabled: true, extraBody: #"{"thinking":{"type":"disabled"}}"#, envKey: "ZHIPUAI_API_KEY",
                        note: "open.bigmodel.cn 申请 key。glm-4-flash 免费。默认关掉了深度思考（“额外参数”里的 thinking），回答快很多；想让它多想想就删掉那一项。"),
        ProviderProfile(id: "qwen", name: "通义千问", kind: .openAI, baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", apiKey: "",
                        models: ["qwen-plus", "qwen-max", "qwen-turbo"], enabled: false, envKey: "DASHSCOPE_API_KEY",
                        note: "阿里云百炼申请 key。Qwen3 开源模型非流式调用需要额外参数 {\"enable_thinking\":false}。"),
        ProviderProfile(id: "doubao", name: "豆包（火山方舟）", kind: .openAI, baseURL: "https://ark.cn-beijing.volces.com/api/v3", apiKey: "",
                        models: ["doubao-seed-1-6-250615"], enabled: false, envKey: "ARK_API_KEY",
                        note: "火山方舟控制台申请 key，模型名填控制台里的模型 ID 或推理接入点 ID。"),
        ProviderProfile(id: "siliconflow", name: "硅基流动", kind: .openAI, baseURL: "https://api.siliconflow.cn/v1", apiKey: "",
                        models: ["deepseek-ai/DeepSeek-V3", "Qwen/Qwen2.5-72B-Instruct", "THUDM/GLM-4-9B-0414"], enabled: false, envKey: "SILICONFLOW_API_KEY",
                        note: "一个 key 可以用很多开源模型。"),
        ProviderProfile(id: "openrouter", name: "OpenRouter", kind: .openAI, baseURL: "https://openrouter.ai/api/v1", apiKey: "",
                        models: ["deepseek/deepseek-chat", "moonshotai/kimi-k2", "z-ai/glm-4.6"], enabled: false, envKey: "OPENROUTER_API_KEY"),
        ProviderProfile(id: "openai", name: "OpenAI", kind: .openAI, baseURL: "https://api.openai.com/v1", apiKey: "",
                        models: ["gpt-5-mini", "gpt-5", "gpt-4.1-mini"], enabled: false, extraBody: #"{"reasoning_effort":"minimal"}"#, envKey: "OPENAI_API_KEY",
                        note: "platform.openai.com 申请 key。默认把推理强度设成 minimal（“额外参数”），一局快很多。"),
        ProviderProfile(id: "claude", name: "Claude（Anthropic）", kind: .anthropic, baseURL: "https://api.anthropic.com", apiKey: "",
                        models: ["claude-opus-5-5", "claude-fable-5-1", "claude-sonnet-5-5", "claude-haiku-4-5-20251001"], enabled: false, jsonMode: false, envKey: "ANTHROPIC_API_KEY"),
        ProviderProfile(id: "ollama", name: "Ollama（本地）", kind: .openAI, baseURL: "http://localhost:11434/v1", apiKey: "",
                        models: ["qwen2.5:7b"], enabled: false, maxConcurrent: 1,
                        note: "本机运行 ollama serve，模型名填 ollama list 里看到的名字。"),
        ProviderProfile(id: "custom", name: "自定义（OpenAI 兼容）", kind: .openAI, baseURL: "https://", apiKey: "",
                        models: [], enabled: false, note: "任何兼容 OpenAI /chat/completions 的服务，包括各种中转。")
    ]
}

extension ProviderProfile {
    static let presetNamesEN: [String: String] = [
        "kimi": "Kimi (Moonshot AI)", "glm": "Zhipu GLM", "qwen": "Qwen (Alibaba Cloud)", "doubao": "Doubao (Volcano Ark)",
        "siliconflow": "SiliconFlow", "claude": "Claude (Anthropic)", "ollama": "Ollama (local)", "custom": "Custom (OpenAI-compatible)"
    ]
    static let presetNotesEN: [String: String] = [
        "deepseek": "Get a key at platform.deepseek.com. deepseek-chat is fast and cheap — a good player.",
        "kimi": "Get a key at platform.moonshot.cn. Use “Fetch model list” to get the latest models.",
        "glm": "Get a key at open.bigmodel.cn. glm-4-flash is free. Deep thinking is off by default (the “thinking” entry in Extra parameters), which makes replies much faster; delete it to let the model think longer.",
        "openai": "Get a key at platform.openai.com. Reasoning effort is set to minimal by default (Extra parameters), which keeps games quick.",
        "qwen": "Get a key from Alibaba Cloud Model Studio. Non-streaming calls to open-weight Qwen3 models need the extra parameter {\"enable_thinking\":false}.",
        "doubao": "Get a key in the Volcano Ark console; use the model ID or the inference endpoint ID as the model name.",
        "siliconflow": "One key for lots of open-weight models.",
        "ollama": "Run ollama serve on this Mac and use the names shown by ollama list.",
        "custom": "Any service compatible with OpenAI /chat/completions, including proxies."
    ]

    /// Name in the interface language (unless the user renamed it).
    public var displayName: String {
        if Loc.ui == .en, let p = Self.presets.first(where: { $0.id == id }), p.name == name, let en = Self.presetNamesEN[id] { return en }
        return name
    }

    /// Setup hint in the interface language (unless the user changed it).
    public var displayNote: String? {
        if Loc.ui == .en, let p = Self.presets.first(where: { $0.id == id }), p.note == note, let en = Self.presetNotesEN[id] { return en }
        return note
    }
}

/// One playable AI "seat" option = provider + model.
public struct ModelRef: Codable, Sendable, Hashable, Identifiable {
    public var providerId: String
    public var model: String
    public var id: String { "\(providerId)::\(model)" }

    public init(providerId: String, model: String) {
        self.providerId = providerId
        self.model = model
    }

    public init?(seatId: String) {
        let parts = seatId.components(separatedBy: "::")
        guard parts.count == 2 else { return nil }
        self.providerId = parts[0]
        self.model = parts[1]
    }
}

public struct AppConfig: Codable, Sendable {
    public var providers: [ProviderProfile]
    public var debate: Bool
    public var autoDelay: Double
    public var logPrompts: Bool
    public var lastSeats: [String: String]
    /// "zh", "en", or nil = follow the system language.
    public var language: String?
    /// Show the live 3D scene above the story feed (nil = yes).
    public var showScene: Bool?
    /// Fast pace for new games (nil = on): work and night decided in one call per AI model.
    public var fastPace: Bool?
    /// Longest wait for one model call, in seconds (nil = 120); after that the rule AI answers that step.
    public var callTimeout: Double?
    /// Difficulty for new single games (nil = hard; D-053).
    public var difficulty: Difficulty?

    public var newGameDifficulty: Difficulty { difficulty ?? .hard }

    /// The wait limit actually used.
    public var callTimeoutSeconds: Double { min(600, max(20, callTimeout ?? 120)) }

    public init(providers: [ProviderProfile], debate: Bool = true, autoDelay: Double = 0.8, logPrompts: Bool = false, lastSeats: [String: String] = [:]) {
        self.providers = providers
        self.debate = debate
        self.autoDelay = autoDelay
        self.logPrompts = logPrompts
        self.lastSeats = lastSeats
    }

    /// The language the interface (and new games) use.
    public var uiLang: Lang { language.flatMap(Lang.init(rawValue:)) ?? Loc.systemDefault }

    public static var fileURL: URL { AppPaths.support.appendingPathComponent("config.json") }

    public static func load() -> AppConfig {
        var cfg: AppConfig
        if let data = try? Data(contentsOf: fileURL), let c = try? JSONDecoder().decode(AppConfig.self, from: data) {
            cfg = c
        } else {
            cfg = AppConfig(providers: ProviderProfile.presets)
        }
        // Add presets introduced after the config was first written.
        for p in ProviderProfile.presets where !cfg.providers.contains(where: { $0.id == p.id }) {
            cfg.providers.append(p)
        }
        // API keys live in the Keychain (D-047). A key still sitting in config.json (older versions)
        // moves there now, and the file is rewritten without it.
        var stored = KeyStore.all()
        var migrated = false
        for i in cfg.providers.indices {
            let id = cfg.providers[i].id
            let inFile = cfg.providers[i].apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !inFile.isEmpty { stored[id] = inFile; migrated = true }
            cfg.providers[i].apiKey = stored[id] ?? ""
        }
        if migrated && KeyStore.save(stored) { cfg.save() }
        return cfg
    }

    /// Writes the settings. The keys go to the Keychain; the file never contains one.
    public func save() {
        var copy = self
        var keys: [String: String] = [:]
        for i in copy.providers.indices {
            keys[copy.providers[i].id] = copy.providers[i].apiKey
            copy.providers[i].apiKey = ""
        }
        KeyStore.save(keys)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(copy) else { return }
        let url = AppConfig.fileURL
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func provider(_ id: String) -> ProviderProfile? {
        providers.first { $0.id == id }
    }

    /// All usable (provider, model) pairs.
    public var availableModels: [ModelRef] {
        providers.filter(\.isUsable).flatMap { p in p.models.map { ModelRef(providerId: p.id, model: $0) } }
    }

    public func label(for ref: ModelRef) -> String {
        let pname = provider(ref.providerId)?.name ?? ref.providerId
        let short = pname.components(separatedBy: "（").first ?? pname
        return "\(short) · \(ref.model)"
    }
}
