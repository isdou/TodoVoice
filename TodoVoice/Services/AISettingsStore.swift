import Foundation
import Security

@MainActor
final class AISettingsStore: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            if isEnabled && !hasAPIKey {
                isEnabled = false
                return
            }
            UserDefaults.standard.set(isEnabled, forKey: DefaultsKey.isEnabled)
        }
    }
    @Published private(set) var hasAPIKey: Bool

    init() {
        var keyExists = false

        #if DEBUG
        keyExists = KeychainStore.readAPIKey() != nil
        // Development builds can receive a key only for the first launch via
        // devicectl/simctl environment injection. It is immediately moved to
        // Keychain and is never compiled into the application bundle.
        if let injectedKey = ProcessInfo.processInfo.environment["TODO_MIMO_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !injectedKey.isEmpty {
            do {
                try KeychainStore.saveAPIKey(injectedKey)
                keyExists = KeychainStore.readAPIKey() != nil
                if keyExists {
                    UserDefaults.standard.set(true, forKey: DefaultsKey.isEnabled)
                }
            } catch {
                keyExists = KeychainStore.readAPIKey() != nil
            }
        }
        #endif

        hasAPIKey = keyExists
        if UserDefaults.standard.object(forKey: DefaultsKey.isEnabled) == nil {
            isEnabled = keyExists
        } else {
            isEnabled = keyExists && UserDefaults.standard.bool(forKey: DefaultsKey.isEnabled)
        }
        UserDefaults.standard.set(isEnabled, forKey: DefaultsKey.isEnabled)
    }

    func apiKey() -> String? {
        KeychainStore.readAPIKey()
    }

    func saveAPIKey(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AISettingsError.emptyAPIKey }
        try KeychainStore.saveAPIKey(trimmed)
        hasAPIKey = true
        isEnabled = true
    }

    func removeAPIKey() {
        KeychainStore.deleteAPIKey()
        hasAPIKey = false
        isEnabled = false
    }
}

enum MiMoConfiguration {
    static let model = "mimo-v2.5"
    static let baseURL = URL(string: "https://token-plan-cn.xiaomimimo.com/v1")!
}

enum AISettingsError: LocalizedError {
    case emptyAPIKey
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyAPIKey:
            return "请输入 API Key"
        case .keychain:
            return "无法安全保存密钥，请稍后重试"
        }
    }
}

private enum DefaultsKey {
    static let isEnabled = "ai.todoExtraction.enabled"
}

private enum KeychainStore {
    private static let service = "com.isdou.TodoVoice.mimo"
    private static let account = "api-key"

    static func readAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func saveAPIKey(_ value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw AISettingsError.emptyAPIKey
        }

        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw AISettingsError.keychain(updateStatus)
        }

        var insert = identity
        attributes.forEach { insert[$0.key] = $0.value }
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AISettingsError.keychain(addStatus)
        }
    }

    static func deleteAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
