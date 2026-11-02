import Foundation

// Shadow only the defaults entry point; the production source reads and writes a real isolated suite.
@MainActor
enum UserDefaults {
    static let suiteName = "fr.louisraille.NotchBuddy.ChatSubscriptionTests.\(UUID().uuidString)"
    static let standard = Foundation.UserDefaults(suiteName: suiteName)!
}

enum ChatProvider: String {
    case anthropic, google, openai, ollama, lmstudio, deepseek, qwen, moonshot, custom, cursor, copilot

    var displayName: String { rawValue }

    var keychainKey: String {
        self == .custom ? "openai-compatible-key" : "\(rawValue)-api-key"
    }
}

enum SubscriptionCLI: String, CaseIterable {
    case claude, antigravity, gemini, codex, cursor, copilot

    var displayName: String { rawValue }
}

struct CLILocator: Sendable {
    static let shared = CLILocator()

    // Every CLI is available, so API-only routing cannot pass just because a tool is missing.
    func isInstalled(_ cli: SubscriptionCLI) -> Bool { true }
}

@MainActor
final class KeychainStore {
    static let shared = KeychainStore()
    var values: [String: String] = [:]

    func get(_ key: String) -> String? { values[key] }
}

@MainActor
struct AnthropicConnection {
    static var configured: AnthropicConnection?

    static func current() -> AnthropicConnection? { configured }
}

@MainActor
final class AppState {
    struct ChangePublisher {
        func send() {}
    }

    let objectWillChange = ChangePublisher()
    var chatProvider: ChatProvider = .anthropic
    var claudeModel = "subscription-claude-model"
    var activeChatModel = "api-endpoint-model"
    var fetchedProviderModels: [ChatProvider: [(id: String, label: String)]] = [:]
    var providerModelFetchError: [ChatProvider: String] = [:]
}

@main
@MainActor
enum ChatSubscriptionTests {
    static var checks = 0
    static var failures = 0

    static func main() {
        let passed = run()
        exit(passed ? EXIT_SUCCESS : EXIT_FAILURE)
    }

    static func run() -> Bool {
        defer { reset() }
        customHasNoCLI()
        configuredConnectionDefaultsToAPI()
        explicitChoiceTakesPrecedence()
        missingConnectionDefaultsToSubscription()
        pickerSelectsRoutingModel()
        print("ChatSubscription: \(checks - failures)/\(checks) checks passed")
        return failures == 0
    }

    static func reset() {
        UserDefaults.standard.removePersistentDomain(forName: UserDefaults.suiteName)
        KeychainStore.shared.values = [:]
        AnthropicConnection.configured = nil
    }

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func customHasNoCLI() {
        reset()
        let state = AppState()
        state.chatProvider = .custom
        check(ChatProvider.custom.subscriptionCLIs.isEmpty, "custom has no subscription CLI")
        check(ChatProvider.custom.installedCLI == nil, "custom has no installed CLI even when all tools are available")
        check(!state.usesSubscription(.custom), "custom defaults to API without a key")
        state.setUsesSubscription(true, for: .custom)
        check(!state.usesSubscription(.custom), "custom ignores an explicit subscription preference")
        check(state.subscriptionTool(.custom) == nil, "custom has no subscription tool")
        check(!state.subscriptionReady(.custom), "custom is never subscription-ready")
        check(state.pickerModel == state.activeChatModel, "custom picker uses API model")
    }

    static func configuredConnectionDefaultsToAPI() {
        reset()
        let state = AppState()
        AnthropicConnection.configured = AnthropicConnection()
        check(KeychainStore.shared.get(ChatProvider.anthropic.keychainKey) == nil, "connection fixture has no direct API key")
        check(UserDefaults.standard.object(forKey: "chat.useSubscription.anthropic") == nil, "connection fixture has no explicit preference")
        check(!state.usesSubscription(.anthropic), "valid Anthropic connection defaults to API without a direct key")
        check(!state.subscriptionReady(.anthropic), "configured API does not become subscription-ready because Claude is installed")
        check(state.pickerModel == state.activeChatModel, "configured connection picker uses API model")
    }

    static func explicitChoiceTakesPrecedence() {
        reset()
        let state = AppState()
        for connected in [false, true] {
            for directKey in [false, true] {
                AnthropicConnection.configured = connected ? AnthropicConnection() : nil
                KeychainStore.shared.values = directKey ? [ChatProvider.anthropic.keychainKey: "test-only-key"] : [:]
                for chosen in [true, false] {
                    state.setUsesSubscription(chosen, for: .anthropic)
                    let context = "choice=\(chosen), connection=\(connected), directKey=\(directKey)"
                    check(UserDefaults.standard.object(forKey: "chat.useSubscription.anthropic") as? Bool == chosen,
                          "explicit choice persisted: \(context)")
                    check(state.usesSubscription(.anthropic) == chosen, "explicit choice overrides defaults: \(context)")
                    check(AppState().usesSubscription(.anthropic) == chosen, "fresh state honors persisted choice: \(context)")
                }
            }
        }
    }

    static func missingConnectionDefaultsToSubscription() {
        reset()
        let state = AppState()
        check(AnthropicConnection.current() == nil, "subscription fixture has no connection")
        check(KeychainStore.shared.get(ChatProvider.anthropic.keychainKey) == nil, "subscription fixture has no key")
        check(state.usesSubscription(.anthropic), "no connection or key defaults to subscription")
        check(state.subscriptionReady(.anthropic), "default subscription is ready when Claude is installed")
        KeychainStore.shared.values[ChatProvider.anthropic.keychainKey] = ""
        check(state.usesSubscription(.anthropic), "empty direct key also defaults to subscription")
        KeychainStore.shared.values[ChatProvider.anthropic.keychainKey] = "test-only-key"
        check(!state.usesSubscription(.anthropic), "nonempty direct key defaults to API")
    }

    static func pickerSelectsRoutingModel() {
        reset()
        let state = AppState()
        check(state.claudeModel != state.activeChatModel, "picker fixture distinguishes subscription and API models")
        state.setUsesSubscription(true, for: .anthropic)
        check(state.pickerModel == state.claudeModel, "Claude subscription picker uses claudeModel")
        state.setUsesSubscription(false, for: .anthropic)
        check(state.pickerModel == state.activeChatModel, "Claude API picker uses activeChatModel")
        state.setUsesSubscription(true, for: .anthropic)
        check(state.pickerModel == state.claudeModel, "switching back restores subscription model")
        state.chatProvider = .google
        state.setUsesSubscription(true, for: .google)
        check(state.pickerModel == "", "non-Claude subscription picker uses CLI default model")
        state.setUsesSubscription(false, for: .google)
        check(state.pickerModel == state.activeChatModel, "non-Claude API picker uses activeChatModel")
    }
}
