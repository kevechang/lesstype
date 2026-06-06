import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    let store: PreferencesStore
    let runtimeStatus: RuntimeStatus?
    let sessionHistoryStore: SessionHistoryStore?
    let retryHotkeys: (() -> Void)?
    let launchAtLoginUpdater: LaunchAtLoginPreferenceUpdater
    private let phraseCorrection = PhraseCorrectionService()
    private let permissionService = PermissionService()

    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedSection: VoiceInputSettingsSection? = .overview
    @State private var recordingTarget: ShortcutTarget?
    @State private var permissions = PermissionSnapshot(
        microphoneGranted: false,
        speechGranted: false,
        accessibilityGranted: false
    )
    @State private var launchAtLoginErrorMessage: String?
    @State private var codexASRImportErrorMessage: String?
    @State private var isImportingCodexASRAccount = false
    @State private var newPhraseText = ""
    @State private var phraseVariantDrafts: [UUID: String] = [:]

    init(
        store: PreferencesStore,
        runtimeStatus: RuntimeStatus? = nil,
        sessionHistoryStore: SessionHistoryStore? = nil,
        retryHotkeys: (() -> Void)? = nil,
        launchAtLoginUpdater: LaunchAtLoginPreferenceUpdater = LaunchAtLoginPreferenceUpdater()
    ) {
        self.store = store
        self.runtimeStatus = runtimeStatus
        self.sessionHistoryStore = sessionHistoryStore
        self.retryHotkeys = retryHotkeys
        self.launchAtLoginUpdater = launchAtLoginUpdater
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                ForEach(VoiceInputSettingsSection.allCases) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    detailHeader
                    Form {
                        detailContent(for: selectedSection ?? .overview)
                    }
                    .formStyle(.grouped)
                }
                .padding(22)
                .frame(maxWidth: 760, alignment: .leading)
            }
            .background(.background)
        }
        .background(
            ShortcutRecorderView(
                isRecording: recordingTarget != nil,
                onRecord: saveRecordedShortcut
            )
            .frame(width: 0, height: 0)
        )
        .frame(minWidth: 820, minHeight: 620)
        .task {
            await refreshPermissions()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await refreshPermissions()
                }
            }
        }
        .fileImporter(
            isPresented: $isImportingCodexASRAccount,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false,
            onCompletion: importCodexASRAccount
        )
    }

    private var selectedSectionValue: VoiceInputSettingsSection {
        selectedSection ?? .overview
    }

    private var detailHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: selectedSectionValue.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedSectionValue.title)
                    .font(.title2.weight(.semibold))
                Text(sectionSubtitle(for: selectedSectionValue))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func detailContent(for section: VoiceInputSettingsSection) -> some View {
        switch section {
        case .overview:
            overviewSection
            permissionSection
            systemSection
        case .shortcuts:
            shortcutsSection
        case .recognition:
            inputHabitSection
            codexASRSection
        case .models:
            modelEnhancementSection
            Section("普通模式模型") {
                modelConfigurationControls(scope: .ordinary, isEnabled: store.preferences.ordinaryModelEnhancementEnabled == true)
            }
            Section("分点模式模型") {
                modelConfigurationControls(scope: .structured, isEnabled: store.preferences.cloudEnhancementEnabled)
            }
        case .phrases:
            phraseSection
        case .prompts:
            promptSection
        case .floatingPanel:
            floatingPanelSection
        case .diagnostics:
            diagnosticsSection
        case .history:
            historySection
        }
    }

    private func sectionSubtitle(for section: VoiceInputSettingsSection) -> String {
        switch section {
        case .overview:
            "查看当前可用性和常用状态。"
        case .shortcuts:
            "设置开始、结束和放弃本次输入的全局快捷键。"
        case .recognition:
            "调整语言习惯、标点和 Codex ASR。"
        case .models:
            "分别配置普通模式和分点模式的大模型增强。"
        case .phrases:
            "维护需要高准确率识别的专有词组。"
        case .prompts:
            "编辑普通模式和分点模式的大模型提示词。"
        case .floatingPanel:
            "控制录音和识别过程中的小浮窗显示方式。"
        case .diagnostics:
            "排查快捷键、ASR、大模型和输入状态。"
        case .history:
            "查看本次运行期间最近完成的输入。"
        }
    }

    private var overviewSection: some View {
        Section("当前状态") {
            LabeledContent("快捷键监听", value: runtimeStatus?.hotkeysRunning == true ? "运行中" : "未启动")
            LabeledContent("普通记录", value: store.preferences.ordinaryHotkey.displayName)
            LabeledContent("自动分点", value: store.preferences.structuredHotkey.displayName)
            LabeledContent("Codex ASR", value: store.preferences.cloudTranscriptionEnabled ? "已启用" : "未启用")
            LabeledContent("最近 ASR", value: runtimeStatus?.lastASRCall ?? "未调用")
            LabeledContent("最近大模型", value: runtimeStatus?.lastModelCall ?? "尚未调用")
            if let retryHotkeys {
                Button {
                    retryHotkeys()
                    Task {
                        await refreshPermissions()
                    }
                } label: {
                    Label("重新启用快捷键", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private var inputHabitSection: some View {
        Section("输入习惯") {
            Picker("识别语言偏好", selection: binding(\.languageMode)) {
                Text("中文优先").tag(LanguageMode.chineseFirst)
                Text("英文优先").tag(LanguageMode.englishFirst)
                Text("自动").tag(LanguageMode.automatic)
            }
            Toggle("使用中文标点", isOn: binding(\.chinesePunctuationEnabled))
            Picker("自动加逗号", selection: binding(\.commaStyle)) {
                Text("关闭").tag(CommaStyle.off)
                Text("保守").tag(CommaStyle.conservative)
                Text("常规").tag(CommaStyle.regular)
            }
            Toggle("中英文之间自动留空格", isOn: binding(\.mixedLanguageSpacingEnabled))
        }
    }

    private var phraseSection: some View {
        Section("高频词组") {
            HStack(spacing: 8) {
                TextField("输入词组，例如 Claude", text: $newPhraseText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addPhrase)
                Button(action: addPhrase) {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
                .help("添加词组")
            }

            if phraseEntries.isEmpty {
                Text("还没有高频词组。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(phraseEntries) { entry in
                        phraseEntryView(entry)
                    }
                }
            }

            Text("每个词条可以继续添加常见误识别写法。普通模式会本地修正；开启大模型时会自动带入提示词。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var shortcutsSection: some View {
        Section("快捷键") {
            shortcutControl("普通记录", shortcut: store.preferences.ordinaryHotkey, target: .ordinary)
            shortcutControl("自动分点", shortcut: store.preferences.structuredHotkey, target: .structured)
            shortcutControl("结束并插入", shortcut: store.preferences.cancelHotkey, target: .cancel)
            shortcutControl("放弃本次内容", shortcut: store.preferences.resolvedDiscardHotkey, target: .discard)
            let warnings = HotkeyDiagnostics.warnings(for: store.preferences)
            if warnings.isEmpty {
                Label("未发现明显冲突", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var floatingPanelSection: some View {
        Section("浮窗") {
            Picker("显示方式", selection: floatingPanelDisplayModeBinding) {
                Text("不显示").tag(FloatingPanelDisplayMode.hidden)
                Text("极简状态").tag(FloatingPanelDisplayMode.minimal)
                Text("显示文本预览").tag(FloatingPanelDisplayMode.text)
            }
            Text("不显示浮窗时，错误提示仍会临时显示。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var codexASRSection: some View {
        Section("Codex ASR") {
            Toggle("使用 Codex ASR 做最终转写", isOn: binding(\.cloudTranscriptionEnabled))
            LabeledContent("已导入账号", value: store.preferences.codexASREmail ?? "未导入")
            LabeledContent("最近一次调用", value: runtimeStatus?.lastASRCall ?? "未调用")
            LabeledContent("调用统计", value: asrUsageSnapshot.summaryText)
            LabeledContent("结果分布", value: asrUsageSnapshot.detailText)
            if asrUsageSnapshot.isLastQuotaLimited {
                Text("上次 Codex ASR 暂时不可用，可能是账号额度或频率限制。已自动改用 Apple 识别，稍后再试即可。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button {
                    isImportingCodexASRAccount = true
                } label: {
                    Label("导入 CPA 账号 JSON", systemImage: "square.and.arrow.down")
                }
                Button(role: .destructive) {
                    store.deleteCodexASRCredentials()
                    codexASRImportErrorMessage = nil
                } label: {
                    Label("移除账号", systemImage: "trash")
                }
                .disabled(store.preferences.codexASREmail == nil)
            }
            Text("录音时仍用 Apple 语音做实时预览，结束后用导入账号调用 ChatGPT 转写；失败会自动回退到 Apple 结果。")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let codexASRImportErrorMessage {
                Text(codexASRImportErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var modelEnhancementSection: some View {
        Section("大模型增强") {
            Toggle("分点模式使用大模型", isOn: binding(\.cloudEnhancementEnabled))
            Toggle("分点模式仅分点不改写原文", isOn: preserveOriginalWhenStructuringBinding)
                .disabled(!store.preferences.cloudEnhancementEnabled)
            Toggle("普通模式使用大模型润色", isOn: ordinaryModelEnhancementBinding)
            Text("普通模式和分点模式可以分别配置不同模型、接口地址和 API Key。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var promptSection: some View {
        Section("提示词") {
            promptEditor(
                title: "普通模式大模型转写",
                text: ordinaryEnhancementPromptBinding,
                defaultPrompt: ModelPromptDefaults.ordinaryEnhancement
            )
            promptEditor(
                title: "分点模式润色整理",
                text: polishedStructuringPromptBinding,
                defaultPrompt: ModelPromptDefaults.polishedStructuring
            )
            promptEditor(
                title: "分点模式仅分点",
                text: preserveOriginalStructuringPromptBinding,
                defaultPrompt: ModelPromptDefaults.preserveOriginalStructuring
            )
        }
    }

    private var systemSection: some View {
        Section("系统") {
            Toggle("开机自启动", isOn: launchAtLoginBinding)
            if let launchAtLoginErrorMessage {
                Text(launchAtLoginErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var diagnosticsSection: some View {
        Section("诊断") {
            diagnosticRows
            Button {
                copyDiagnostics()
            } label: {
                Label("复制诊断信息", systemImage: "doc.on.doc")
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private var historySection: some View {
        Section("最近输入") {
            if let sessionHistoryStore {
                if sessionHistoryStore.entries.isEmpty {
                    Text("还没有历史记录。完成一次输入后会显示最近结果。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sessionHistoryStore.entries.prefix(12)) { entry in
                        historyEntryView(entry)
                    }
                    Button(role: .destructive) {
                        sessionHistoryStore.clear()
                    } label: {
                        Label("清空本次运行历史", systemImage: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            } else {
                Text("当前窗口没有接入运行历史。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var permissionSection: some View {
        Section("系统权限") {
            permissionRow("麦克风", granted: permissions.microphoneGranted) {
                Task {
                    _ = await permissionService.requestMicrophone()
                    await refreshPermissions()
                }
            }
            permissionRow("语音识别", granted: permissions.speechGranted) {
                Task {
                    _ = await permissionService.requestSpeech()
                    await refreshPermissions()
                }
            }
            permissionRow("辅助功能（全局快捷键和文本插入需要）", granted: permissions.accessibilityGranted) {
                permissionService.requestAccessibilityPrompt()
                permissionService.openAccessibilitySettings()
                Task {
                    await refreshPermissions()
                }
            }
        }
    }

    private func permissionRow(_ title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Label(granted ? "已授权" : "未授权", systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(granted ? .green : .orange)
            Text(title)
            Spacer()
            Button(granted ? "重新检查" : "去授权", action: action)
        }
    }

    private func shortcutControl(_ title: String, shortcut: HotkeyShortcut, target: ShortcutTarget) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                Text(recordingTarget == target ? "请按键..." : shortcut.displayName)
                    .font(.body.monospaced())
                    .foregroundStyle(recordingTarget == target ? Color.accentColor : Color.secondary)
            }
            Spacer()
            Button(recordingTarget == target ? "取消录制" : "设置") {
                recordingTarget = recordingTarget == target ? nil : target
            }
        }
    }

    private func saveRecordedShortcut(_ shortcut: HotkeyShortcut) {
        guard let recordingTarget else {
            return
        }

        var preferences = store.preferences
        switch recordingTarget {
        case .ordinary:
            preferences.ordinaryHotkey = shortcut
            preferences.ordinaryShortcut = shortcut.displayName
        case .structured:
            preferences.structuredHotkey = shortcut
            preferences.structuredShortcut = shortcut.displayName
        case .cancel:
            preferences.cancelHotkey = shortcut
            preferences.cancelShortcut = shortcut.displayName
        case .discard:
            preferences.discardHotkey = shortcut
            preferences.discardShortcut = shortcut.displayName
        }
        store.save(preferences)
        self.recordingTarget = nil
        retryHotkeys?()
    }

    private func refreshPermissions() async {
        permissions = await permissionService.snapshot()
    }

    @ViewBuilder
    private func modelConfigurationControls(scope: ModelConfigurationScope, isEnabled: Bool) -> some View {
        Group {
            Picker("接口类型", selection: modelAPIStyleBinding(for: scope)) {
                Text("本地 Codex").tag(ModelAPIStyle.codexCLI)
                Text("OpenAI Responses").tag(ModelAPIStyle.openAIResponses)
                Text("OpenAI 兼容 Chat").tag(ModelAPIStyle.openAICompatibleChat)
                Text("Claude 原生 Messages").tag(ModelAPIStyle.anthropicMessages)
            }
            .disabled(!isEnabled)

            TextField("模型名称（第三方接口通常必填）", text: modelNameBinding(for: scope))
                .disabled(!isEnabled)

            TextField("API URL", text: apiURLBinding(for: scope))
                .disabled(!isEnabled || modelAPIStyle(for: scope) == .codexCLI)

            SecureField("API Key（留空则使用 Codex/OpenAI 本地配置）", text: apiKeyBinding(for: scope))
                .disabled(!isEnabled || modelAPIStyle(for: scope) == .codexCLI)

            Text("OpenAI 兼容 Chat 适合 OpenRouter、DeepSeek 等兼容接口；Claude 原生 Messages 适合 Anthropic 原生接口。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<Preferences, Value>) -> Binding<Value> {
        Binding(
            get: { store.preferences[keyPath: keyPath] },
            set: { value in
                var preferences = store.preferences
                preferences[keyPath: keyPath] = value
                store.save(preferences)
            }
        )
    }

    private func apiURLBinding(for scope: ModelConfigurationScope) -> Binding<String> {
        Binding(
            get: {
                let configuredURL = store.preferences.apiURL(for: scope)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return configuredURL.isEmpty ? modelAPIStyle(for: scope).defaultAPIURL.absoluteString : configuredURL
            },
            set: { value in
                var preferences = store.preferences
                switch scope {
                case .ordinary:
                    preferences.ordinaryAPIURL = value
                case .structured:
                    preferences.structuredAPIURL = value
                }
                store.save(preferences)
            }
        )
    }

    private func modelNameBinding(for scope: ModelConfigurationScope) -> Binding<String> {
        Binding(
            get: { store.preferences.modelName(for: scope) ?? "" },
            set: { value in
                var preferences = store.preferences
                switch scope {
                case .ordinary:
                    preferences.ordinaryModelName = value
                case .structured:
                    preferences.structuredModelName = value
                }
                store.save(preferences)
            }
        )
    }

    private var asrUsageSnapshot: CodexASRUsageSnapshot {
        runtimeStatus?.asrUsageSnapshot ?? .empty
    }

    @ViewBuilder
    private var diagnosticRows: some View {
        LabeledContent("快捷键监听", value: runtimeStatus?.hotkeysRunning == true ? "运行中" : "未启动")
        LabeledContent("快捷键启动", value: runtimeStatus?.hotkeyStartFailed == true ? "失败" : "正常")
        LabeledContent("最近动作", value: runtimeStatus?.lastHotkeyAction ?? "尚未触发")
        LabeledContent("最近 ASR", value: runtimeStatus?.lastASRCall ?? "未调用")
        LabeledContent("最近大模型", value: runtimeStatus?.lastModelCall ?? "尚未调用")
        let warnings = HotkeyDiagnostics.warnings(for: store.preferences)
        if warnings.isEmpty {
            Text(HotkeyDiagnostics.summary(for: store.preferences))
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text(warnings.joined(separator: "\n"))
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func historyEntryView(_ entry: VoiceSessionHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.mode.localizedName)
                    .font(.headline)
                Spacer()
                Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(entry.outputText)
                .lineLimit(3)
                .textSelection(.enabled)
            if entry.recognizedText != entry.outputText {
                Text("原始：\(entry.recognizedText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 4)
    }

    private func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnosticText, forType: .string)
    }

    private var diagnosticText: String {
        [
            "快捷键监听：\(runtimeStatus?.hotkeysRunning == true ? "运行中" : "未启动")",
            "快捷键启动失败：\(runtimeStatus?.hotkeyStartFailed == true ? "是" : "否")",
            "最近动作：\(runtimeStatus?.lastHotkeyAction ?? "尚未触发")",
            "最近 ASR：\(runtimeStatus?.lastASRCall ?? "未调用")",
            "最近大模型：\(runtimeStatus?.lastModelCall ?? "尚未调用")",
            "ASR 调用统计：\(asrUsageSnapshot.summaryText)",
            "ASR 结果分布：\(asrUsageSnapshot.detailText)",
            "快捷键诊断：\(HotkeyDiagnostics.summary(for: store.preferences))"
        ].joined(separator: "\n")
    }

    private func apiKeyBinding(for scope: ModelConfigurationScope) -> Binding<String> {
        Binding(
            get: { store.preferences.apiKey(for: scope) },
            set: { value in
                var preferences = store.preferences
                switch scope {
                case .ordinary:
                    preferences.ordinaryAPIKey = value
                case .structured:
                    preferences.structuredAPIKey = value
                }
                store.save(preferences)
            }
        )
    }

    private func modelAPIStyleBinding(for scope: ModelConfigurationScope) -> Binding<ModelAPIStyle> {
        Binding(
            get: { modelAPIStyle(for: scope) },
            set: { value in
                var preferences = store.preferences
                switch scope {
                case .ordinary:
                    preferences.ordinaryModelAPIStyle = value
                    if shouldReplaceAPIURL(preferences.ordinaryAPIURL ?? preferences.apiURL) {
                        preferences.ordinaryAPIURL = value.defaultAPIURL.absoluteString
                    }
                case .structured:
                    preferences.structuredModelAPIStyle = value
                    if shouldReplaceAPIURL(preferences.structuredAPIURL ?? preferences.apiURL) {
                        preferences.structuredAPIURL = value.defaultAPIURL.absoluteString
                    }
                }
                store.save(preferences)
            }
        )
    }

    private func modelAPIStyle(for scope: ModelConfigurationScope) -> ModelAPIStyle {
        store.preferences.modelAPIStyle(for: scope) ?? .codexCLI
    }

    private func shouldReplaceAPIURL(_ url: String?) -> Bool {
        let value = url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if value.isEmpty {
            return true
        }
        return ModelAPIStyle.allCases.contains { style in
            normalizeURL(value) == normalizeURL(style.defaultAPIURL.absoluteString)
        }
    }

    private func normalizeURL(_ url: String) -> String {
        url.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
    }

    private var floatingPanelDisplayModeBinding: Binding<FloatingPanelDisplayMode> {
        Binding(
            get: { store.preferences.floatingPanelDisplayMode ?? .hidden },
            set: { value in
                var preferences = store.preferences
                preferences.floatingPanelDisplayMode = value
                store.save(preferences)
            }
        )
    }

    private var ordinaryModelEnhancementBinding: Binding<Bool> {
        Binding(
            get: { store.preferences.ordinaryModelEnhancementEnabled == true },
            set: { value in
                var preferences = store.preferences
                preferences.ordinaryModelEnhancementEnabled = value
                store.save(preferences)
            }
        )
    }

    private var preserveOriginalWhenStructuringBinding: Binding<Bool> {
        Binding(
            get: { store.preferences.preserveOriginalWhenStructuringEnabled == true },
            set: { value in
                var preferences = store.preferences
                preferences.preserveOriginalWhenStructuringEnabled = value
                store.save(preferences)
            }
        )
    }

    private var ordinaryEnhancementPromptBinding: Binding<String> {
        optionalStringBinding(\.ordinaryEnhancementPrompt, fallback: ModelPromptDefaults.ordinaryEnhancement)
    }

    private var polishedStructuringPromptBinding: Binding<String> {
        optionalStringBinding(\.polishedStructuringPrompt, fallback: ModelPromptDefaults.polishedStructuring)
    }

    private var preserveOriginalStructuringPromptBinding: Binding<String> {
        optionalStringBinding(\.preserveOriginalStructuringPrompt, fallback: ModelPromptDefaults.preserveOriginalStructuring)
    }

    private func optionalStringBinding(_ keyPath: WritableKeyPath<Preferences, String?>, fallback: String) -> Binding<String> {
        Binding(
            get: { store.preferences[keyPath: keyPath] ?? fallback },
            set: { value in
                var preferences = store.preferences
                preferences[keyPath: keyPath] = value
                store.save(preferences)
            }
        )
    }

    @ViewBuilder
    private func promptEditor(title: String, text: Binding<String>, defaultPrompt: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button("恢复默认") {
                    text.wrappedValue = defaultPrompt
                }
                .buttonStyle(.borderless)
            }
            TextEditor(text: text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 118)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(.vertical, 4)
    }

    private var phraseEntries: [PhraseCorrectionEntry] {
        phraseCorrection.entries(from: store.preferences)
    }

    @ViewBuilder
    private func phraseEntryView(_ entry: PhraseCorrectionEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(entry.phrase)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button {
                    removePhrase(entry)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("删除词组")
            }

            if !entry.variants.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(entry.variants, id: \.self) { variant in
                        HStack(spacing: 4) {
                            Text(variant)
                                .font(.caption)
                                .lineLimit(1)
                            Button {
                                removeVariant(variant, from: entry)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .help("删除误识别写法")
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.tertiary.opacity(0.45), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
            }

            HStack(spacing: 6) {
                TextField("误识别写法", text: variantDraftBinding(for: entry.id))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addVariant(to: entry)
                    }
                Button {
                    addVariant(to: entry)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("添加误识别写法")
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func variantDraftBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { phraseVariantDrafts[id] ?? "" },
            set: { phraseVariantDrafts[id] = $0 }
        )
    }

    private func addPhrase() {
        let rawText = newPhraseText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty else {
            return
        }

        let additions = rawText
            .replacingOccurrences(of: "，", with: ",")
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { PhraseCorrectionEntry(phrase: $0) }

        guard !additions.isEmpty else {
            return
        }

        savePhraseEntries(phraseEntries + additions)
        newPhraseText = ""
    }

    private func removePhrase(_ entry: PhraseCorrectionEntry) {
        savePhraseEntries(phraseEntries.filter { $0.id != entry.id })
        phraseVariantDrafts[entry.id] = nil
    }

    private func addVariant(to entry: PhraseCorrectionEntry) {
        let variant = (phraseVariantDrafts[entry.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !variant.isEmpty else {
            return
        }

        var entries = phraseEntries
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else {
            return
        }
        entries[index].variants.append(variant)
        savePhraseEntries(entries)
        phraseVariantDrafts[entry.id] = ""
    }

    private func removeVariant(_ variant: String, from entry: PhraseCorrectionEntry) {
        var entries = phraseEntries
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else {
            return
        }
        entries[index].variants.removeAll { $0 == variant }
        savePhraseEntries(entries)
    }

    private func savePhraseEntries(_ entries: [PhraseCorrectionEntry]) {
        var normalizedPreferences = store.preferences
        normalizedPreferences.phraseCorrectionsText = ""
        normalizedPreferences.phraseCorrectionEntries = entries

        var preferences = store.preferences
        preferences.phraseCorrectionsText = ""
        preferences.phraseCorrectionEntries = phraseCorrection.entries(from: normalizedPreferences)
        store.save(preferences)
    }

    private func importCodexASRAccount(_ result: Result<[URL], Error>) {
        do {
            let url = try result.get().first
            guard let url else {
                return
            }
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let data = try Data(contentsOf: url)
            try store.importCodexASRCredentials(from: data)
            codexASRImportErrorMessage = nil
        } catch {
            codexASRImportErrorMessage = "导入失败：\(error.localizedDescription)"
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { store.preferences.launchAtLoginEnabled == true },
            set: { value in
                do {
                    let updatedPreferences = try launchAtLoginUpdater.preferencesByApplying(value, to: store.preferences)
                    store.save(updatedPreferences)
                    launchAtLoginErrorMessage = nil
                } catch {
                    launchAtLoginErrorMessage = "开机自启动设置失败：\(error.localizedDescription)"
                }
            }
        )
    }
}

private extension AppMode {
    var localizedName: String {
        switch self {
        case .ordinary:
            "普通记录"
        case .structured:
            "自动分点"
        }
    }
}
