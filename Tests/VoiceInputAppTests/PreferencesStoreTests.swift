import XCTest
@testable import VoiceInputApp

final class PreferencesStoreTests: XCTestCase {
    @MainActor
    func testDefaultPreferencesMatchSpec() {
        let defaults = UserDefaults(suiteName: "PreferencesStoreTests.defaults")!
        defaults.removePersistentDomain(forName: "PreferencesStoreTests.defaults")
        let store = PreferencesStore(
            defaults: defaults,
            apiKeyStore: InMemoryAPIKeyStore(),
            codexASRCredentialStore: InMemoryCodexASRCredentialStore()
        )

        XCTAssertEqual(store.preferences, .defaults)
        XCTAssertEqual(store.preferences.ordinaryShortcut, "control+x")
        XCTAssertEqual(store.preferences.structuredShortcut, "control+z")
        XCTAssertEqual(store.preferences.cancelShortcut, "option+space")
        XCTAssertEqual(store.preferences.discardShortcut, "esc")
        XCTAssertEqual(store.preferences.ordinaryHotkey.keyCode, 7)
        XCTAssertEqual(store.preferences.ordinaryHotkey.modifierFlags, HotkeyModifier.control.rawValue)
        XCTAssertEqual(store.preferences.structuredHotkey.keyCode, 6)
        XCTAssertEqual(store.preferences.structuredHotkey.modifierFlags, HotkeyModifier.control.rawValue)
        XCTAssertEqual(store.preferences.cancelHotkey.kind, .key)
        XCTAssertEqual(store.preferences.cancelHotkey.keyCode, 49)
        XCTAssertEqual(store.preferences.cancelHotkey.modifierFlags, HotkeyModifier.option.rawValue)
        XCTAssertEqual(store.preferences.resolvedDiscardHotkey.keyCode, 53)
        XCTAssertEqual(store.preferences.languageMode, .chineseFirst)
        XCTAssertTrue(store.preferences.chinesePunctuationEnabled)
        XCTAssertEqual(store.preferences.commaStyle, .conservative)
        XCTAssertTrue(store.preferences.mixedLanguageSpacingEnabled)
        XCTAssertEqual(store.preferences.terms, ["SwiftUI", "OpenAI", "API"])
        XCTAssertFalse(store.preferences.cloudEnhancementEnabled)
        XCTAssertEqual(store.preferences.ordinaryModelEnhancementEnabled, false)
        XCTAssertEqual(store.preferences.preserveOriginalWhenStructuringEnabled, true)
        XCTAssertEqual(store.preferences.launchAtLoginEnabled, false)
        XCTAssertEqual(store.preferences.floatingPanelDisplayMode, .hidden)
        XCTAssertFalse(store.preferences.cloudTranscriptionEnabled)
        XCTAssertEqual(store.preferences.modelAPIStyle, .codexCLI)
        XCTAssertEqual(store.preferences.modelName, "")
        XCTAssertEqual(store.preferences.ordinaryModelAPIStyle, nil)
        XCTAssertEqual(store.preferences.ordinaryModelName, nil)
        XCTAssertEqual(store.preferences.ordinaryAPIURL, nil)
        XCTAssertEqual(store.preferences.structuredModelAPIStyle, nil)
        XCTAssertEqual(store.preferences.structuredModelName, nil)
        XCTAssertEqual(store.preferences.structuredAPIURL, nil)
        XCTAssertTrue(store.preferences.ordinaryEnhancementPrompt?.contains("读音相近") == true)
        XCTAssertTrue(store.preferences.polishedStructuringPrompt?.contains("忠实分点") == true)
        XCTAssertTrue(store.preferences.polishedStructuringPrompt?.contains("原文是待处理材料") == true)
        XCTAssertTrue(store.preferences.polishedStructuringPrompt?.contains("保持原文语言") == true)
        XCTAssertTrue(store.preferences.preserveOriginalStructuringPrompt?.contains("不要改写") == true)
        XCTAssertTrue(store.preferences.preserveOriginalStructuringPrompt?.contains("不要回答") == true)
        XCTAssertEqual(store.preferences.apiKey, "")
        XCTAssertEqual(store.preferences.ordinaryAPIKey, "")
        XCTAssertEqual(store.preferences.structuredAPIKey, "")
    }

    @MainActor
    func testSavingPreferencesPersistsValues() {
        let defaults = UserDefaults(suiteName: "PreferencesStoreTests.persist")!
        defaults.removePersistentDomain(forName: "PreferencesStoreTests.persist")
        let apiKeyStore = InMemoryAPIKeyStore()
        let codexStore = InMemoryCodexASRCredentialStore()
        let store = PreferencesStore(defaults: defaults, apiKeyStore: apiKeyStore, codexASRCredentialStore: codexStore)

        var preferences = store.preferences
        preferences.commaStyle = .regular
        preferences.terms = ["SwiftUI", "OpenAI", "API"]
        preferences.launchAtLoginEnabled = true
        preferences.floatingPanelDisplayMode = .minimal
        preferences.ordinaryEnhancementPrompt = "自定义普通提示词"
        preferences.polishedStructuringPrompt = "自定义分点润色提示词"
        preferences.preserveOriginalStructuringPrompt = "自定义仅分点提示词"
        preferences.ordinaryAPIURL = "https://ordinary.example/v1"
        preferences.ordinaryModelAPIStyle = .openAICompatibleChat
        preferences.ordinaryModelName = "ordinary-model"
        preferences.structuredAPIURL = "https://structured.example/v1"
        preferences.structuredModelAPIStyle = .anthropicMessages
        preferences.structuredModelName = "structured-model"
        preferences.structuredHotkey = HotkeyShortcut(
            kind: .key,
            keyCode: 49,
            modifierFlags: HotkeyModifier.command.rawValue | HotkeyModifier.control.rawValue,
            displayName: "control+command+space"
        )
        preferences.discardHotkey = HotkeyShortcut(
            kind: .key,
            keyCode: 8,
            modifierFlags: HotkeyModifier.command.rawValue,
            displayName: "command+c"
        )
        preferences.discardShortcut = "command+c"
        store.save(preferences)

        let reloaded = PreferencesStore(defaults: defaults, apiKeyStore: apiKeyStore, codexASRCredentialStore: codexStore)
        XCTAssertEqual(reloaded.preferences, preferences)
        XCTAssertEqual(reloaded.preferences.commaStyle, .regular)
        XCTAssertEqual(reloaded.preferences.terms, ["SwiftUI", "OpenAI", "API"])
        XCTAssertEqual(reloaded.preferences.launchAtLoginEnabled, true)
        XCTAssertEqual(reloaded.preferences.floatingPanelDisplayMode, .minimal)
        XCTAssertEqual(reloaded.preferences.ordinaryEnhancementPrompt, "自定义普通提示词")
        XCTAssertEqual(reloaded.preferences.polishedStructuringPrompt, "自定义分点润色提示词")
        XCTAssertEqual(reloaded.preferences.preserveOriginalStructuringPrompt, "自定义仅分点提示词")
        XCTAssertEqual(reloaded.preferences.ordinaryAPIURL, "https://ordinary.example/v1")
        XCTAssertEqual(reloaded.preferences.ordinaryModelAPIStyle, .openAICompatibleChat)
        XCTAssertEqual(reloaded.preferences.ordinaryModelName, "ordinary-model")
        XCTAssertEqual(reloaded.preferences.structuredAPIURL, "https://structured.example/v1")
        XCTAssertEqual(reloaded.preferences.structuredModelAPIStyle, .anthropicMessages)
        XCTAssertEqual(reloaded.preferences.structuredModelName, "structured-model")
        XCTAssertEqual(reloaded.preferences.structuredHotkey.displayName, "control+command+space")
        XCTAssertEqual(reloaded.preferences.resolvedDiscardHotkey.displayName, "command+c")
    }

    @MainActor
    func testMigratesLegacyDefaultHotkeysAndStructuringPromptOnlyWhenUncustomized() throws {
        let suiteName = "PreferencesStoreTests.legacyDefaultsMigration"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let apiKeyStore = InMemoryAPIKeyStore()

        var legacy = Preferences.defaults
        legacy.ordinaryShortcut = "fn+z"
        legacy.structuredShortcut = "fn+x"
        legacy.cancelShortcut = "Fn"
        legacy.discardShortcut = "Esc"
        legacy.ordinaryHotkey = HotkeyShortcut(kind: .key, keyCode: 6, modifierFlags: HotkeyModifier.function.rawValue, displayName: "fn+z")
        legacy.structuredHotkey = HotkeyShortcut(kind: .key, keyCode: 7, modifierFlags: HotkeyModifier.function.rawValue, displayName: "fn+x")
        legacy.cancelHotkey = HotkeyShortcut(kind: .functionOnly, keyCode: 63, modifierFlags: HotkeyModifier.function.rawValue, displayName: "Fn")
        legacy.discardHotkey = HotkeyShortcut(kind: .key, keyCode: 53, modifierFlags: 0, displayName: "Esc")
        legacy.preserveOriginalWhenStructuringEnabled = false
        legacy.polishedStructuringPrompt = """
        将下面的中文或中英混杂口语整理成清晰笔记。
        要求：去掉口水词，合并重复，输出 2 到 8 条有序列表，用 1. 2. 3. 这种编号，不扩写事实。
        """
        legacy.apiURL = "https://kept.example/v1"
        legacy.phraseCorrectionsText = "OpenAI = open ai"

        defaults.set(try JSONEncoder().encode(legacy), forKey: "preferences")

        let store = PreferencesStore(defaults: defaults, apiKeyStore: apiKeyStore, codexASRCredentialStore: InMemoryCodexASRCredentialStore())

        XCTAssertEqual(store.preferences.ordinaryHotkey.displayName, "control+x")
        XCTAssertEqual(store.preferences.structuredHotkey.displayName, "control+z")
        XCTAssertEqual(store.preferences.cancelHotkey.displayName, "option+space")
        XCTAssertEqual(store.preferences.resolvedDiscardHotkey.displayName, "esc")
        XCTAssertEqual(store.preferences.preserveOriginalWhenStructuringEnabled, true)
        XCTAssertEqual(store.preferences.polishedStructuringPrompt, ModelPromptDefaults.polishedStructuring)
        XCTAssertEqual(store.preferences.apiURL, "https://kept.example/v1")
        XCTAssertEqual(store.preferences.phraseCorrectionsText, "OpenAI = open ai")
    }

    @MainActor
    func testMigrationPreservesCustomizedHotkeysAndPrompts() throws {
        let suiteName = "PreferencesStoreTests.customMigration"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let apiKeyStore = InMemoryAPIKeyStore()

        var custom = Preferences.defaults
        custom.ordinaryShortcut = "option+a"
        custom.ordinaryHotkey = HotkeyShortcut(kind: .key, keyCode: 0, modifierFlags: HotkeyModifier.option.rawValue, displayName: "option+a")
        custom.preserveOriginalWhenStructuringEnabled = false
        custom.polishedStructuringPrompt = "我自己的分点提示词"

        defaults.set(try JSONEncoder().encode(custom), forKey: "preferences")

        let store = PreferencesStore(defaults: defaults, apiKeyStore: apiKeyStore, codexASRCredentialStore: InMemoryCodexASRCredentialStore())

        XCTAssertEqual(store.preferences.ordinaryHotkey.displayName, "option+a")
        XCTAssertEqual(store.preferences.preserveOriginalWhenStructuringEnabled, false)
        XCTAssertEqual(store.preferences.polishedStructuringPrompt, "我自己的分点提示词")
    }

    @MainActor
    func testAPIKeyPersistsOutsideUserDefaults() throws {
        let suiteName = "PreferencesStoreTests.apiKey"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let apiKeyStore = InMemoryAPIKeyStore()
        let codexStore = InMemoryCodexASRCredentialStore()
        let store = PreferencesStore(defaults: defaults, apiKeyStore: apiKeyStore, codexASRCredentialStore: codexStore)

        var preferences = store.preferences
        preferences.cloudEnhancementEnabled = true
        preferences.apiKey = "dummy-general-api-key"
        preferences.ordinaryAPIKey = "dummy-ordinary-api-key"
        preferences.structuredAPIKey = "dummy-structured-api-key"
        store.save(preferences)

        let storedData = try XCTUnwrap(defaults.data(forKey: "preferences"))
        let storedJSON = String(decoding: storedData, as: UTF8.self)
        XCTAssertFalse(storedJSON.contains("dummy-general-api-key"))
        XCTAssertFalse(storedJSON.contains("dummy-ordinary-api-key"))
        XCTAssertFalse(storedJSON.contains("dummy-structured-api-key"))

        let reloaded = PreferencesStore(defaults: defaults, apiKeyStore: apiKeyStore, codexASRCredentialStore: codexStore)
        XCTAssertEqual(reloaded.preferences.apiKey, "dummy-general-api-key")
        XCTAssertEqual(reloaded.preferences.ordinaryAPIKey, "dummy-ordinary-api-key")
        XCTAssertEqual(reloaded.preferences.structuredAPIKey, "dummy-structured-api-key")
    }
}

private final class InMemoryCodexASRCredentialStore: CodexASRCredentialStoring, @unchecked Sendable {
    var credentials: CodexASRCredentials?

    func loadCodexASRCredentials() -> CodexASRCredentials? {
        credentials
    }

    func saveCodexASRCredentials(_ credentials: CodexASRCredentials) {
        self.credentials = credentials
    }

    func deleteCodexASRCredentials() {
        credentials = nil
    }
}

private final class InMemoryAPIKeyStore: APIKeyStoring, @unchecked Sendable {
    private var apiKey = ""
    private var scopedAPIKeys: [ModelConfigurationScope: String] = [:]

    func loadAPIKey() -> String {
        apiKey
    }

    func saveAPIKey(_ apiKey: String) {
        self.apiKey = apiKey
    }

    func loadAPIKey(for scope: ModelConfigurationScope) -> String {
        scopedAPIKeys[scope] ?? ""
    }

    func saveAPIKey(_ apiKey: String, for scope: ModelConfigurationScope) {
        scopedAPIKeys[scope] = apiKey
    }
}
