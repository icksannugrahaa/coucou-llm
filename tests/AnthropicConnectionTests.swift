import Foundation

/// Stand-in for the app's Keychain cache (AnthropicConnection.swift only needs `get`).
final class KeychainStore: @unchecked Sendable {
    static let shared = KeychainStore()
    func get(_ key: String) -> String? { nil }
}

@main
enum AnthropicConnectionTests {
    static func main() {
        // No token at all: nothing to connect with
        precondition(ClaudeCodeSettings.connection(from: [:]) == nil)
        precondition(ClaudeCodeSettings.connection(from: ["ANTHROPIC_BASE_URL": "https://x.dev"]) == nil)

        // The user's proxy: base URL without trailing slash, bearer token, opus override only
        let proxy = ClaudeCodeSettings.connection(from: [
            "ANTHROPIC_AUTH_TOKEN": "t",
            "ANTHROPIC_BASE_URL": "https://ai.example.works/",
            "ANTHROPIC_DEFAULT_OPUS_MODEL": "proxy-model",
        ])!
        precondition(proxy.baseURL == "https://ai.example.works")
        precondition(proxy.authToken == "t" && proxy.apiKey == nil)
        // Every Claude model goes to the only override
        precondition(proxy.model("claude-sonnet-4-6") == "proxy-model")
        precondition(proxy.model("claude-haiku-4-5") == "proxy-model")
        precondition(proxy.model("claude-opus-4-1") == "proxy-model")

        // Headers: bearer token, version, JSON; no x-api-key
        let req = proxy.request("/v1/messages", timeout: 10)!
        precondition(req.url?.absoluteString == "https://ai.example.works/v1/messages")
        precondition(req.value(forHTTPHeaderField: "Authorization") == "Bearer t")
        precondition(req.value(forHTTPHeaderField: "x-api-key") == nil)
        precondition(req.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")

        // Aliases mapped like Claude Code: haiku → haiku override, opus → opus, rest → main
        let mapped = ClaudeCodeSettings.connection(from: [
            "ANTHROPIC_API_KEY": "k",
            "ANTHROPIC_MODEL": "main-m",
            "ANTHROPIC_DEFAULT_OPUS_MODEL": "opus-m",
            "ANTHROPIC_SMALL_FAST_MODEL": "fast-m",
        ])!
        precondition(mapped.baseURL == "https://api.anthropic.com")
        precondition(mapped.request("/v1/models", timeout: 5)!.value(forHTTPHeaderField: "x-api-key") == "k")
        precondition(mapped.model("claude-haiku-4-5") == "fast-m")
        precondition(mapped.model("claude-opus-4-1") == "opus-m")
        precondition(mapped.model("claude-sonnet-4-6") == "main-m")
        precondition((mapped.mapped(["model": "claude-sonnet-4-6", "max_tokens": 1])["model"] as? String) == "main-m")

        // No overrides: the requested model is sent as is
        let plain = ClaudeCodeSettings.connection(from: ["ANTHROPIC_AUTH_TOKEN": "t"])!
        precondition(plain.model("claude-sonnet-4-6") == "claude-sonnet-4-6")

        print("Anthropic connection: 18 cases passed")
    }
}
