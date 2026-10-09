import Foundation

public struct LLMResult: Sendable {
    public var text: String
    public var inputTokens: Int
    public var outputTokens: Int
    public var seconds: Double
    public var reasoning: String?
}

public struct LLMError: Error, CustomStringConvertible, Sendable {
    public let status: Int?
    public let message: String
    public var description: String {
        if let status { return "HTTP \(status)：\(message)" }
        return message
    }
}

/// Talks to OpenAI-compatible and Anthropic endpoints. Adapts automatically when a
/// provider rejects a parameter (response_format, temperature, max_tokens).
public actor LLMClient {
    private let session: URLSession
    /// provider|model → parameters known to be rejected
    private var rejected: [String: Set<String>] = [:]
    private var inFlight: [String: Int] = [:]
    private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    public init(timeout: TimeInterval = 240) {
        // ephemeral: no disk cache, no cookies, no credential store — requests carrying a key leave no trace on disk
        let cfg = URLSessionConfiguration.ephemeral
        cfg.urlCache = nil
        cfg.httpCookieStorage = nil
        cfg.httpShouldSetCookies = false
        cfg.urlCredentialStorage = nil
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = timeout * 2
        self.session = URLSession(configuration: cfg)
    }

    /// A key only travels over https, or to this machine (Ollama and other local servers).
    static func keyAllowed(_ url: URL) -> Bool {
        if url.scheme?.lowercased() == "https" { return true }
        let host = (url.host ?? "").lowercased()
        return ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host) || host.hasSuffix(".localhost")
    }

    /// Attaches the key as the given header, refusing plain-http addresses on the network.
    private func attachKey(_ key: String, header: String, prefix: String = "", to req: inout URLRequest) throws {
        guard !key.isEmpty else { return }
        guard let url = req.url, Self.keyAllowed(url) else {
            throw LLMError(status: nil, message: L("为了保护 API key，只通过 https 发送（本机地址除外）。请把 Base URL 改成 https:// 开头。",
                                                    "To protect your API key it is only sent over https (or to this Mac). Change the Base URL to start with https://."))
        }
        Redact.register(key)
        req.setValue(prefix + key, forHTTPHeaderField: header)
    }

    // MARK: Concurrency limit per provider

    private func acquire(_ key: String, limit: Int) async {
        if inFlight[key, default: 0] < max(1, limit) {
            inFlight[key, default: 0] += 1
            return
        }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            waiters[key, default: []].append(c)
        }
        inFlight[key, default: 0] += 1
    }

    private func release(_ key: String) {
        inFlight[key, default: 1] -= 1
        if var w = waiters[key], !w.isEmpty {
            let next = w.removeFirst()
            waiters[key] = w
            next.resume()
        }
    }

    // MARK: Public API

    public func complete(profile: ProviderProfile, model: String, system: String, user: String,
                         jsonMode: Bool, maxTokens: Int, temperature: Double?) async throws -> LLMResult {
        await acquire(profile.id, limit: profile.maxConcurrent)
        defer { release(profile.id) }
        var attempt = 0
        var lastError: Error = LLMError(status: nil, message: L("未知错误", "unknown error"))
        while attempt < 4 {
            attempt += 1
            do {
                switch profile.kind {
                case .openAI:
                    return try await openAI(profile, model, system, user, jsonMode: jsonMode && profile.jsonMode, maxTokens: maxTokens, temperature: temperature)
                case .anthropic:
                    return try await anthropic(profile, model, system, user, maxTokens: maxTokens, temperature: temperature)
                }
            } catch let e as LLMError {
                lastError = e
                let key = "\(profile.id)|\(model)"
                let msg = e.message.lowercased()
                if e.status == 400 || e.status == 422 {
                    var learned = false
                    // the standard parameters, plus anything from "extra parameters" the model turns out not to support
                    let candidates = ["response_format", "temperature", "max_tokens"] + extraKeys(profile.extraBody)
                    for p in candidates where msg.contains(p.lowercased()) && !(rejected[key]?.contains(p) ?? false) {
                        rejected[key, default: []].insert(p)
                        learned = true
                    }
                    if !learned && jsonMode && !(rejected[key]?.contains("response_format") ?? false) && (msg.contains("json") || msg.contains("format")) {
                        rejected[key, default: []].insert("response_format")
                        learned = true
                    }
                    if learned { continue }
                    throw e
                }
                if e.status == 401 || e.status == 403 || e.status == 404 { throw e }
                // 429 / 5xx / network: back off and retry
                let wait = UInt64(Double(attempt) * 1.5 * 1_000_000_000)
                try? await Task.sleep(nanoseconds: wait)
            } catch {
                lastError = error
                if (error as? URLError)?.code == .cancelled || (error as? URLError)?.code == .timedOut || Task.isCancelled { throw error }
                try? await Task.sleep(nanoseconds: UInt64(Double(attempt) * 1_000_000_000))
            }
        }
        throw lastError
    }

    /// GET /models for OpenAI-compatible providers.
    public func listModels(profile: ProviderProfile) async throws -> [String] {
        guard profile.kind == .openAI else { return profile.models }
        guard let url = URL(string: trimmed(profile.baseURL) + "/models") else { throw LLMError(status: nil, message: L("Base URL 无效", "invalid base URL")) }
        var req = URLRequest(url: url)
        try attachKey(profile.effectiveKey, header: "Authorization", prefix: "Bearer ", to: &req)
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw LLMError(status: status, message: String(data: data, encoding: .utf8)?.prefix(300).description ?? "") }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["data"] as? [[String: Any]] else { return [] }
        return arr.compactMap { $0["id"] as? String }.sorted()
    }

    // MARK: Providers

    private func trimmed(_ base: String) -> String {
        var b = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while b.hasSuffix("/") { b.removeLast() }
        return b
    }

    private func openAI(_ p: ProviderProfile, _ model: String, _ system: String, _ user: String,
                        jsonMode: Bool, maxTokens: Int, temperature: Double?) async throws -> LLMResult {
        let base = trimmed(p.baseURL)
        let path = base.hasSuffix("/chat/completions") ? "" : "/chat/completions"
        guard let url = URL(string: base + path) else { throw LLMError(status: nil, message: L("Base URL 无效：\(p.baseURL)", "invalid base URL: \(p.baseURL)")) }
        let key = "\(p.id)|\(model)"
        let bad = rejected[key] ?? []
        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "stream": false
        ]
        if bad.contains("max_tokens") {
            body["max_completion_tokens"] = maxTokens
        } else {
            body["max_tokens"] = maxTokens
        }
        if let t = temperature, !bad.contains("temperature") { body["temperature"] = t }
        if jsonMode && !bad.contains("response_format") { body["response_format"] = ["type": "json_object"] }
        mergeExtra(p.extraBody, skipping: bad, into: &body)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try attachKey(p.effectiveKey, header: "Authorization", prefix: "Bearer ", to: &req)
        if p.id == "openrouter" { req.setValue("Brink", forHTTPHeaderField: "X-Title") }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let t0 = Date()
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw LLMError(status: status, message: errorMessage(data))
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError(status: status, message: L("返回的不是 JSON", "the response is not JSON"))
        }
        if let err = obj["error"] as? [String: Any] {
            throw LLMError(status: status, message: (err["message"] as? String) ?? "\(err)")
        }
        guard let choices = obj["choices"] as? [[String: Any]], let first = choices.first,
              let message = first["message"] as? [String: Any] else {
            let body = String(data: data, encoding: .utf8)?.prefix(300) ?? ""
            throw LLMError(status: status, message: L("返回格式异常：\(body)", "unexpected response format: \(body)"))
        }
        var text = ""
        if let c = message["content"] as? String {
            text = c
        } else if let parts = message["content"] as? [[String: Any]] {
            text = parts.compactMap { $0["text"] as? String }.joined()
        }
        let reasoning = message["reasoning_content"] as? String ?? message["reasoning"] as? String
        let usage = obj["usage"] as? [String: Any]
        return LLMResult(text: text,
                         inputTokens: usage?["prompt_tokens"] as? Int ?? 0,
                         outputTokens: usage?["completion_tokens"] as? Int ?? 0,
                         seconds: Date().timeIntervalSince(t0),
                         reasoning: reasoning)
    }

    private func anthropic(_ p: ProviderProfile, _ model: String, _ system: String, _ user: String,
                           maxTokens: Int, temperature: Double?) async throws -> LLMResult {
        let base = trimmed(p.baseURL)
        let path = base.hasSuffix("/v1/messages") ? "" : (base.hasSuffix("/v1") ? "/messages" : "/v1/messages")
        guard let url = URL(string: base + path) else { throw LLMError(status: nil, message: L("Base URL 无效：\(p.baseURL)", "invalid base URL: \(p.baseURL)")) }
        let key = "\(p.id)|\(model)"
        let bad = rejected[key] ?? []
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [["role": "user", "content": user]]
        ]
        if let t = temperature, !bad.contains("temperature") { body["temperature"] = min(1, t) }
        mergeExtra(p.extraBody, skipping: bad, into: &body)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try attachKey(p.effectiveKey, header: "x-api-key", to: &req)
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let t0 = Date()
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw LLMError(status: status, message: errorMessage(data)) }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = obj["content"] as? [[String: Any]] else {
            throw LLMError(status: status, message: L("返回格式异常", "unexpected response format"))
        }
        let text = content.filter { ($0["type"] as? String) == "text" }.compactMap { $0["text"] as? String }.joined()
        let usage = obj["usage"] as? [String: Any]
        return LLMResult(text: text,
                         inputTokens: usage?["input_tokens"] as? Int ?? 0,
                         outputTokens: usage?["output_tokens"] as? Int ?? 0,
                         seconds: Date().timeIntervalSince(t0),
                         reasoning: nil)
    }

    private func mergeExtra(_ extra: String, skipping bad: Set<String> = [], into body: inout [String: Any]) {
        let t = extra.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let d = t.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        for (k, v) in obj where !bad.contains(k) { body[k] = v }
    }

    private func extraKeys(_ extra: String) -> [String] {
        guard let d = extra.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [] }
        return obj.keys.sorted()
    }

    private func errorMessage(_ data: Data) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let e = obj["error"] as? [String: Any], let m = e["message"] as? String { return m }
            if let e = obj["error"] as? String { return e }
            if let m = obj["message"] as? String { return m }
        }
        return String(data: data, encoding: .utf8).map { String($0.prefix(400)) } ?? L("无响应内容", "(empty response)")
    }
}

/// Pulls a JSON object out of a model reply (strips <think> blocks, code fences, chatter).
public enum JSONExtract {
    public static func object(from raw: String) -> [String: Any]? {
        var s = raw
        // remove <think>...</think>
        while let start = s.range(of: "<think>"), let end = s.range(of: "</think>", range: start.upperBound..<s.endIndex) {
            s.removeSubrange(start.lowerBound..<end.upperBound)
        }
        s = s.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
        // try every '{' as a start, take the matching '}' by brace depth
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            if chars[i] == "{" {
                var depth = 0
                var inString = false
                var escape = false
                var j = i
                while j < chars.count {
                    let c = chars[j]
                    if inString {
                        if escape { escape = false }
                        else if c == "\\" { escape = true }
                        else if c == "\"" { inString = false }
                    } else {
                        if c == "\"" { inString = true }
                        else if c == "{" { depth += 1 }
                        else if c == "}" {
                            depth -= 1
                            if depth == 0 { break }
                        }
                    }
                    j += 1
                }
                if j < chars.count {
                    let candidate = String(chars[i...j])
                    if let obj = parse(candidate) { return obj }
                }
            }
            i += 1
        }
        return nil
    }

    static func parse(_ s: String) -> [String: Any]? {
        if let d = s.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { return o }
        // tolerate trailing commas and Chinese quotes
        var fixed = s.replacingOccurrences(of: "，}", with: "}")
        fixed = fixed.replacingOccurrences(of: ",}", with: "}").replacingOccurrences(of: ",]", with: "]")
        fixed = fixed.replacingOccurrences(of: ", }", with: "}").replacingOccurrences(of: ", ]", with: "]")
        if let d = fixed.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { return o }
        return nil
    }

    public static func string(_ obj: [String: Any], _ keys: String...) -> String? {
        for k in keys {
            if let v = obj[k] as? String { return v }
            if let v = obj[k] as? NSNumber { return v.stringValue }
        }
        return nil
    }
}
