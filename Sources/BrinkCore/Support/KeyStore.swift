import Foundation
import Security

/// Where API keys live: one item in the macOS Keychain ("Brink" / "api-keys", a small JSON map
/// provider id → key). config.json never holds a key (D-047).
///
/// Runs with BRINK_HOME set (screenshots, the CLI, a portable copy) and unit tests keep keys in
/// memory only, so they never touch the user's real Keychain.
public enum KeyStore {
    static let service = "Brink"
    static let account = "api-keys"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: String]?
    nonisolated(unsafe) private static var memory: [String: String] = [:]

    /// True when keys go to the real Keychain.
    public static var usesKeychain: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["BRINK_HOME"] != nil || env["XCTestConfigurationFilePath"] != nil { return false }
        return NSClassFromString("XCTestCase") == nil
    }

    /// All stored keys, by provider id.
    public static func all() -> [String: String] {
        lock.lock(); defer { lock.unlock() }
        return loadLocked()
    }

    public static func key(for provider: String) -> String? {
        let v = all()[provider]
        return (v?.isEmpty ?? true) ? nil : v
    }

    /// Replaces the stored keys (empty values are dropped). Writes only when something changed.
    @discardableResult
    public static func save(_ keys: [String: String]) -> Bool {
        let clean = keys.compactMapValues { v -> String? in
            let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        lock.lock(); defer { lock.unlock() }
        if loadLocked() == clean { return true }
        guard usesKeychain else {
            memory = clean
            cache = clean
            return true
        }
        let ok = writeKeychain(clean)
        if ok { cache = clean }
        return ok
    }

    /// Every key currently known (for scrubbing text before it is shown or written to disk).
    public static var secrets: [String] { Array(all().values) }

    // MARK: Keychain

    private static func loadLocked() -> [String: String] {
        if let c = cache { return c }
        let v = usesKeychain ? readKeychain() : memory
        cache = v
        return v
    }

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func readKeychain() -> [String: String] {
        var q = baseQuery
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data,
              let map = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return map
    }

    private static func writeKeychain(_ keys: [String: String]) -> Bool {
        if keys.isEmpty {
            let s = SecItemDelete(baseQuery as CFDictionary)
            return s == errSecSuccess || s == errSecItemNotFound
        }
        guard let data = try? JSONEncoder().encode(keys) else { return false }
        let update = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return true }
        guard update == errSecItemNotFound else { return false }
        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrLabel as String] = "Brink — API keys"
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}

/// Masks secrets in any text that is shown, logged or written to disk.
public enum Redact {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var registered: Set<String> = []

    /// Keys that didn't come from the Keychain (environment variables, the CLI) but were sent somewhere:
    /// remembered for this run so they get masked too.
    public static func register(_ key: String) {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard k.count >= 8 else { return }
        lock.lock(); registered.insert(k); lock.unlock()
    }

    static var known: [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(registered)
    }

    /// "sk-proj-…9f3a": the first few characters and the last four.
    public static func mask(_ key: String) -> String {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard k.count > 8 else { return String(repeating: "•", count: max(4, k.count)) }
        let prefix = k.hasPrefix("sk-") ? (k.split(separator: "-").prefix(2).joined(separator: "-") + "-") : String(k.prefix(3))
        return "\(prefix)…\(k.suffix(4))"
    }

    /// Replaces known keys and anything that looks like a credential.
    public static func text(_ s: String, secrets: [String]? = nil) -> String {
        var out = s
        let all = (secrets ?? (KeyStore.secrets + known)).sorted { $0.count > $1.count }
        for k in all where k.count >= 8 { out = out.replacingOccurrences(of: k, with: mask(k)) }
        // (pattern, replacement): anything that looks like a credential, whoever's it is
        let patterns: [(String, String)] = [
            (#"(?i)(bearer\s+)[A-Za-z0-9._\-]{12,}"#, "$1••••"),
            (#"(?i)((?:api[_-]?key|x-api-key|authorization|access[_-]?token|secret)["'\s:=]+)[A-Za-z0-9._\-]{12,}"#, "$1••••"),
            (#"(?i)([?&](?:key|api_key|apikey|token|access_token)=)[^&\s"']+"#, "$1••••"),        // ?key=… in a URL
            (#"(?i)(\b[a-z][a-z0-9+.\-]*://)[^/\s:@]+:[^/\s@]+@"#, "$1••••@"),                 // user:pass@host
            (#"\bsk-[A-Za-z0-9_\-]{16,}"#, "sk-••••"),                                            // OpenAI, DeepSeek, Kimi, Anthropic…
            (#"\bAIza[0-9A-Za-z_\-]{30,}"#, "AIza••••"),                                          // Google
            (#"\b[0-9a-f]{32}\.[A-Za-z0-9]{12,}\b"#, "••••"),                                    // Zhipu id.secret
            (#"\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b"#, "••••")        // Ark and other UUID keys
        ]
        for (p, template) in patterns {
            guard let re = try? NSRegularExpression(pattern: p) else { continue }
            let range = NSRange(out.startIndex..., in: out)
            out = re.stringByReplacingMatches(in: out, range: range, withTemplate: template)
        }
        return out
    }
}
