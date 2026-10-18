import Foundation

// MARK: - Where Coucou's Claude calls go

/// The connection behind every Claude call of Coucou (chat, voice, Flow clean-up, Notetaker):
/// either the user's Anthropic API key (Keychain), or the endpoint Claude Code is set up with
/// in `~/.claude/settings.json` (`env`: `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN` /
/// `ANTHROPIC_API_KEY`, `ANTHROPIC_MODEL` / `ANTHROPIC_DEFAULT_*_MODEL`). That file is only
/// read, never written, and its token is never copied anywhere.
enum AnthropicSource: String, CaseIterable, Sendable {
    case apiKey
    case claudeCodeSettings

    static let defaultsKey = "anthropicSource"

    static var current: AnthropicSource {
        #if APPSTORE
        return .apiKey   // the sandbox can't read ~/.claude
        #else
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
              let source = AnthropicSource(rawValue: raw) else { return .apiKey }
        return source
        #endif
    }
}

struct AnthropicConnection: Sendable {
    /// Server root, without a trailing slash ("https://api.anthropic.com").
    let baseURL: String
    let apiKey: String?          // sent as x-api-key
    let authToken: String?       // sent as Authorization: Bearer
    /// Claude Code's model overrides (settings.json only).
    let models: ModelOverrides

    struct ModelOverrides: Sendable, Equatable {
        var main: String?        // ANTHROPIC_MODEL
        var opus: String?        // ANTHROPIC_DEFAULT_OPUS_MODEL
        var sonnet: String?      // ANTHROPIC_DEFAULT_SONNET_MODEL
        var haiku: String?       // ANTHROPIC_DEFAULT_HAIKU_MODEL, or ANTHROPIC_SMALL_FAST_MODEL

        var isEmpty: Bool { [main, opus, sonnet, haiku].allSatisfy { $0 == nil } }
    }

    static let anthropicBaseURL = "https://api.anthropic.com"
    static let version = "2023-06-01"

    /// The connection to use now, or nil when Claude isn't set up (no key, or no usable
    /// settings.json).
    static func current() -> AnthropicConnection? {
        switch AnthropicSource.current {
        case .apiKey:
            guard let key = KeychainStore.shared.get("anthropic-api-key"), !key.isEmpty else { return nil }
            return AnthropicConnection(baseURL: anthropicBaseURL, apiKey: key, authToken: nil,
                                       models: ModelOverrides())
        case .claudeCodeSettings:
            return ClaudeCodeSettings.connection()
        }
    }

    static var isConfigured: Bool { current() != nil }

    /// A request to `path` ("/v1/messages") with the auth and version headers set.
    func request(_ path: String, timeout: TimeInterval) -> URLRequest? {
        guard let url = URL(string: baseURL + path) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        if let apiKey, !apiKey.isEmpty { request.setValue(apiKey, forHTTPHeaderField: "x-api-key") }
        if let authToken, !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        request.setValue(Self.version, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        return request
    }

    /// The model actually sent. With the API key: the requested one. With Claude Code's
    /// settings: mapped the way Claude Code maps its aliases (a haiku request goes to the
    /// haiku override, and so on), falling back to the main override.
    func model(_ requested: String) -> String {
        guard !models.isEmpty else { return requested }
        let r = requested.lowercased()
        let pick: String?
        if r.contains("haiku") {
            pick = models.haiku ?? models.main ?? models.sonnet ?? models.opus
        } else if r.contains("opus") {
            pick = models.opus ?? models.main ?? models.sonnet
        } else {
            pick = models.main ?? models.sonnet ?? models.opus
        }
        return pick ?? requested
    }

    /// Same request body with its "model" mapped.
    func mapped(_ body: [String: Any]) -> [String: Any] {
        guard let m = body["model"] as? String else { return body }
        var body = body
        body["model"] = model(m)
        return body
    }
}

// MARK: - ~/.claude/settings.json

/// Reads the `env` block Claude Code CLI uses for a custom endpoint. Read-only.
enum ClaudeCodeSettings {
    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }

    static func env() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let env = root["env"] as? [String: Any] else { return [:] }
        return env.compactMapValues { value in
            let s = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (s?.isEmpty ?? true) ? nil : s
        }
    }

    /// nil when there is no token at all (nothing Coucou could authenticate with).
    static func connection() -> AnthropicConnection? {
        connection(from: env())
    }

    static func connection(from env: [String: String]) -> AnthropicConnection? {
        let token = env["ANTHROPIC_AUTH_TOKEN"]
        let key = env["ANTHROPIC_API_KEY"]
        guard token != nil || key != nil else { return nil }
        var base = env["ANTHROPIC_BASE_URL"] ?? AnthropicConnection.anthropicBaseURL
        while base.hasSuffix("/") { base.removeLast() }
        let models = AnthropicConnection.ModelOverrides(
            main: env["ANTHROPIC_MODEL"],
            opus: env["ANTHROPIC_DEFAULT_OPUS_MODEL"],
            sonnet: env["ANTHROPIC_DEFAULT_SONNET_MODEL"],
            haiku: env["ANTHROPIC_DEFAULT_HAIKU_MODEL"] ?? env["ANTHROPIC_SMALL_FAST_MODEL"])
        return AnthropicConnection(baseURL: base, apiKey: key, authToken: token, models: models)
    }

    /// What Settings shows: the endpoint and the model, never the token.
    static func summary() -> (baseURL: String, model: String?)? {
        guard let conn = connection() else { return nil }
        return (conn.baseURL, conn.models.isEmpty ? nil : conn.model("claude-sonnet"))
    }
}
