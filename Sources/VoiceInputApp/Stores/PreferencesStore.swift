import Foundation
import Observation
import Security

public protocol APIKeyStoring: Sendable {
    func loadAPIKey() -> String
    func saveAPIKey(_ apiKey: String)
    func loadAPIKey(for scope: ModelConfigurationScope) -> String
    func saveAPIKey(_ apiKey: String, for scope: ModelConfigurationScope)
}

@Observable
@MainActor
public final class PreferencesStore {
    private static let preferencesKey = "preferences"

    private let defaults: UserDefaults
    private let apiKeyStore: APIKeyStoring
    private let codexASRCredentialStore: CodexASRCredentialStoring

    public private(set) var preferences: Preferences

    public init(
        defaults: UserDefaults = .standard,
        apiKeyStore: APIKeyStoring = KeychainAPIKeyStore(),
        codexASRCredentialStore: CodexASRCredentialStoring = KeychainCodexASRCredentialStore()
    ) {
        self.defaults = defaults
        self.apiKeyStore = apiKeyStore
        self.codexASRCredentialStore = codexASRCredentialStore
        if let data = defaults.data(forKey: Self.preferencesKey),
           let decoded = try? JSONDecoder().decode(Preferences.self, from: data) {
            preferences = Self.migratedPreferences(from: decoded)
        } else {
            preferences = .defaults
        }
        let legacyAPIKey = apiKeyStore.loadAPIKey()
        preferences.apiKey = legacyAPIKey
        let ordinaryAPIKey = apiKeyStore.loadAPIKey(for: .ordinary)
        let structuredAPIKey = apiKeyStore.loadAPIKey(for: .structured)
        preferences.ordinaryAPIKey = ordinaryAPIKey.isEmpty ? legacyAPIKey : ordinaryAPIKey
        preferences.structuredAPIKey = structuredAPIKey.isEmpty ? legacyAPIKey : structuredAPIKey
        if preferences.codexASREmail == nil {
            preferences.codexASREmail = codexASRCredentialStore.loadCodexASRCredentials()?.email
        }
    }

    public func save(_ preferences: Preferences) {
        self.preferences = preferences
        apiKeyStore.saveAPIKey(preferences.apiKey)
        apiKeyStore.saveAPIKey(preferences.ordinaryAPIKey, for: .ordinary)
        apiKeyStore.saveAPIKey(preferences.structuredAPIKey, for: .structured)
        var persistedPreferences = preferences
        persistedPreferences.apiKey = ""
        persistedPreferences.ordinaryAPIKey = ""
        persistedPreferences.structuredAPIKey = ""
        if let data = try? JSONEncoder().encode(persistedPreferences) {
            defaults.set(data, forKey: Self.preferencesKey)
        }
    }

    public func importCodexASRCredentials(from data: Data) throws {
        let credentials = try CodexASRCredentials.imported(from: data)
        codexASRCredentialStore.saveCodexASRCredentials(credentials)
        var updatedPreferences = preferences
        updatedPreferences.codexASREmail = credentials.email
        updatedPreferences.cloudTranscriptionEnabled = true
        save(updatedPreferences)
    }

    public func deleteCodexASRCredentials() {
        codexASRCredentialStore.deleteCodexASRCredentials()
        var updatedPreferences = preferences
        updatedPreferences.codexASREmail = nil
        updatedPreferences.cloudTranscriptionEnabled = false
        save(updatedPreferences)
    }

    private static func migratedPreferences(from decoded: Preferences) -> Preferences {
        var migrated = decoded
        migrateLegacyDefaultHotkeys(&migrated)
        migrateLegacyDefaultStructuringPrompt(&migrated)
        return migrated
    }

    private static func migrateLegacyDefaultHotkeys(_ preferences: inout Preferences) {
        if preferences.ordinaryHotkey == legacyOrdinaryHotkey {
            preferences.ordinaryShortcut = Preferences.defaults.ordinaryShortcut
            preferences.ordinaryHotkey = Preferences.defaults.ordinaryHotkey
        }
        if preferences.structuredHotkey == legacyStructuredHotkey {
            preferences.structuredShortcut = Preferences.defaults.structuredShortcut
            preferences.structuredHotkey = Preferences.defaults.structuredHotkey
        }
        if preferences.cancelHotkey == legacyCancelHotkey {
            preferences.cancelShortcut = Preferences.defaults.cancelShortcut
            preferences.cancelHotkey = Preferences.defaults.cancelHotkey
        }
        if preferences.resolvedDiscardHotkey == legacyDiscardHotkey {
            preferences.discardShortcut = Preferences.defaults.discardShortcut
            preferences.discardHotkey = Preferences.defaults.discardHotkey
        }
    }

    private static func migrateLegacyDefaultStructuringPrompt(_ preferences: inout Preferences) {
        let prompt = preferences.polishedStructuringPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard prompt == legacyPolishedStructuringPrompt.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return
        }
        preferences.polishedStructuringPrompt = ModelPromptDefaults.polishedStructuring
        if preferences.preserveOriginalWhenStructuringEnabled != true {
            preferences.preserveOriginalWhenStructuringEnabled = true
        }
    }

    private static let legacyOrdinaryHotkey = HotkeyShortcut(
        kind: .key,
        keyCode: 6,
        modifierFlags: HotkeyModifier.function.rawValue,
        displayName: "fn+z"
    )
    private static let legacyStructuredHotkey = HotkeyShortcut(
        kind: .key,
        keyCode: 7,
        modifierFlags: HotkeyModifier.function.rawValue,
        displayName: "fn+x"
    )
    private static let legacyCancelHotkey = HotkeyShortcut(
        kind: .functionOnly,
        keyCode: 63,
        modifierFlags: HotkeyModifier.function.rawValue,
        displayName: "Fn"
    )
    private static let legacyDiscardHotkey = HotkeyShortcut(
        kind: .key,
        keyCode: 53,
        modifierFlags: 0,
        displayName: "Esc"
    )
    private static let legacyPolishedStructuringPrompt = """
    将下面的中文或中英混杂口语整理成清晰笔记。
    要求：去掉口水词，合并重复，输出 2 到 8 条有序列表，用 1. 2. 3. 这种编号，不扩写事实。
    """
}

public struct KeychainAPIKeyStore: APIKeyStoring {
    private let service = "app.typeart.voiceinput"
    private let account = "cloud-model-api-key"

    public init() {}

    public func loadAPIKey() -> String {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let apiKey = String(data: data, encoding: .utf8) else {
            return ""
        }
        return apiKey
    }

    public func saveAPIKey(_ apiKey: String) {
        save(apiKey, account: account)
    }

    public func loadAPIKey(for scope: ModelConfigurationScope) -> String {
        var query = baseQuery(account: accountName(for: scope))
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let apiKey = String(data: data, encoding: .utf8) else {
            return ""
        }
        return apiKey
    }

    public func saveAPIKey(_ apiKey: String, for scope: ModelConfigurationScope) {
        save(apiKey, account: accountName(for: scope))
    }

    private func save(_ apiKey: String, account: String) {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedKey.isEmpty {
            SecItemDelete(baseQuery(account: account) as CFDictionary)
            return
        }

        let data = Data(trimmedKey.utf8)
        let status = SecItemUpdate(
            baseQuery(account: account) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecItemNotFound {
            var item = baseQuery(account: account)
            item[kSecValueData as String] = data
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    private func accountName(for scope: ModelConfigurationScope) -> String {
        switch scope {
        case .ordinary:
            "ordinary-cloud-model-api-key"
        case .structured:
            "structured-cloud-model-api-key"
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
