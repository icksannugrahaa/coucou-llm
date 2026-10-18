import Foundation

// MARK: - Where Coucou's Claude calls go

/// The connection behind every Claude call of Coucou (chat, voice, Flow clean-up, Notetaker):
/// either the user's Anthropic API key, or a custom endpoint speaking the Anthropic API
/// (a proxy, a gateway — the same kind Claude Code reaches with ANTHROPIC_BASE_URL and
/// ANTHROPIC_AUTH_TOKEN). Both are typed in Settings → Chat; tokens live in the Keychain.
enum AnthropicSource: String, CaseIterable, Sendable {
    case apiKey
    case customEndpoint

    static let defaultsKey = "anthropicSource"

    static var current: AnthropicSource {
        #if APPSTORE
        return .apiKey   // the App Store build keeps the API key only
        #else
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
              let source = AnthropicSource(rawValue: raw) else { return .apiKey }
        return source
        #endif
    }
}

/// The custom endpoint as typed in Settings.
enum AnthropicCustomEndpoint {
    static let baseURLKey = "anthropicCustomBaseURL"     // UserDefaults
    static let modelKey   = "anthropicCustomModel"       // UserDefaults
    static let tokenKey   = "anthropic-custom-token"     // Keychain

    static var baseURL: String {
        get { UserDefaults.standard.string(forKey: baseURLKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: baseURLKey) }
    }
    static var model: String {
        get { UserDefaults.standard.string(forKey: modelKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: modelKey) }
    }
    static var token: String? { KeychainStore.shared.get(tokenKey) }

    /// Trims spaces and trailing slashes, and drops a pasted "/v1/messages" or "/v1".
    static func normalised(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        for suffix in ["/v1/messages", "/v1"] where s.hasSuffix(suffix) {
            s = String(s.dropLast(suffix.count))
        }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    static func connection(baseURL: String, token: String?, model: String) -> AnthropicConnection? {
        let base = normalised(baseURL)
        guard base.hasPrefix("http://") || base.hasPrefix("https://"),
              let token, !token.isEmpty else { return nil }
        let m = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return AnthropicConnection(baseURL: base, apiKey: token, authToken: token,
                                   modelOverride: m.isEmpty ? nil : m)
    }
}

struct AnthropicConnection: Sendable {
    /// Server root, without a trailing slash ("https://api.anthropic.com").
    let baseURL: String
    let apiKey: String?          // sent as x-api-key
    let authToken: String?       // sent as Authorization: Bearer
    /// Custom endpoint: the one model every call uses (the endpoint's own name for it).
    let modelOverride: String?

    static let anthropicBaseURL = "https://api.anthropic.com"
    static let version = "2023-06-01"

    /// The connection to use now, or nil when Claude isn't set up.
    static func current() -> AnthropicConnection? {
        switch AnthropicSource.current {
        case .apiKey:
            guard let key = KeychainStore.shared.get("anthropic-api-key"), !key.isEmpty else { return nil }
            return AnthropicConnection(baseURL: anthropicBaseURL, apiKey: key, authToken: nil,
                                       modelOverride: nil)
        case .customEndpoint:
            return AnthropicCustomEndpoint.connection(baseURL: AnthropicCustomEndpoint.baseURL,
                                                      token: AnthropicCustomEndpoint.token,
                                                      model: AnthropicCustomEndpoint.model)
        }
    }

    static var isConfigured: Bool { current() != nil }

    /// A request to `path` ("/v1/messages") with the auth and version headers set.
    /// A custom endpoint gets its token both ways (x-api-key and Bearer): gateways
    /// read one or the other.
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

    /// The model actually sent: the custom endpoint's model when one is set, else the requested one.
    func model(_ requested: String) -> String { modelOverride ?? requested }

    /// Same request body with its "model" mapped.
    func mapped(_ body: [String: Any]) -> [String: Any] {
        guard let m = body["model"] as? String else { return body }
        var body = body
        body["model"] = model(m)
        return body
    }
}
