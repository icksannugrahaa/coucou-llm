import Foundation

/// Stand-in for the app's Keychain cache (AnthropicConnection.swift only needs `get`).
final class KeychainStore: @unchecked Sendable {
    static let shared = KeychainStore()
    func get(_ key: String) -> String? { nil }
}

@main
enum AnthropicConnectionTests {
    static func main() {
        typealias Custom = AnthropicCustomEndpoint

        // Not usable: no token, no URL, not a web URL
        precondition(Custom.connection(baseURL: "https://x.dev", token: nil, model: "") == nil)
        precondition(Custom.connection(baseURL: "https://x.dev", token: "", model: "") == nil)
        precondition(Custom.connection(baseURL: "", token: "t", model: "") == nil)
        precondition(Custom.connection(baseURL: "x.dev", token: "t", model: "") == nil)

        // URL clean-up: slashes and a pasted /v1 or /v1/messages are dropped
        precondition(Custom.normalised(" https://ai.example.works/ ") == "https://ai.example.works")
        precondition(Custom.normalised("https://ai.example.works/v1") == "https://ai.example.works")
        precondition(Custom.normalised("https://ai.example.works/v1/messages/") == "https://ai.example.works")
        precondition(Custom.normalised("https://gw.example.com/anthropic") == "https://gw.example.com/anthropic")

        // A gateway: token sent both ways, every model replaced by the endpoint's one
        let proxy = Custom.connection(baseURL: "https://ai.example.works/v1", token: "t", model: " proxy-model ")!
        let req = proxy.request("/v1/messages", timeout: 10)!
        precondition(req.url?.absoluteString == "https://ai.example.works/v1/messages")
        precondition(req.value(forHTTPHeaderField: "Authorization") == "Bearer t")
        precondition(req.value(forHTTPHeaderField: "x-api-key") == "t")
        precondition(req.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        precondition(proxy.model("claude-sonnet-4-6") == "proxy-model")
        precondition(proxy.model("claude-haiku-4-5") == "proxy-model")
        precondition((proxy.mapped(["model": "claude-sonnet-4-6", "max_tokens": 1])["model"] as? String) == "proxy-model")

        // No model typed: the requested one is sent as is
        let plain = Custom.connection(baseURL: "https://ai.example.works", token: "t", model: "")!
        precondition(plain.model("claude-sonnet-4-6") == "claude-sonnet-4-6")

        // The API key: x-api-key only, to Anthropic
        let key = AnthropicConnection(baseURL: AnthropicConnection.anthropicBaseURL, apiKey: "k",
                                      authToken: nil, modelOverride: nil)
        let keyReq = key.request("/v1/models", timeout: 5)!
        precondition(keyReq.url?.host == "api.anthropic.com")
        precondition(keyReq.value(forHTTPHeaderField: "x-api-key") == "k")
        precondition(keyReq.value(forHTTPHeaderField: "Authorization") == nil)

        print("Anthropic connection: 20 cases passed")
    }
}
