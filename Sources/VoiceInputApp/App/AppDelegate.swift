import AppKit
import Observation

@Observable
@MainActor
final class RuntimeStatus {
    var hotkeysRunning = false
    var hotkeyStartFailed = false
    var lastHotkeyAction = "尚未触发"
    var lastModelCall = "尚未调用"
    var lastASRCall = "未调用"
    var asrUsageSnapshot = CodexASRUsageSnapshot.empty
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let preferencesStore = PreferencesStore()
    let runtimeStatus = RuntimeStatus()
    let asrUsageStore = CodexASRUsageStore()
    let sessionHistoryStore = SessionHistoryStore()

    private let floatingPanel = FloatingPanelController()
    private let permissionService = PermissionService()
    private let operationRunner = SerializedOperationRunner()
    private var coordinator: VoiceSessionCoordinator?
    private var hotkeyService: HotkeyService?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        wireRuntimeServices()
        Task { @MainActor in
            permissionService.requestAccessibilityPrompt()
            startHotkeys()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        operationRunner.cancel()
        hotkeyService?.stop()
    }

    @objc func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func retryHotkeys() {
        permissionService.requestAccessibilityPrompt()
        startHotkeys()
    }

    private func wireRuntimeServices() {
        runtimeStatus.asrUsageSnapshot = asrUsageStore.snapshot
        let modelProvider = HybridModelProvider()
        let coordinator = VoiceSessionCoordinator(
            preferencesStore: preferencesStore,
            liveRecognition: AppleLiveSpeechRecognitionService(),
            postProcessor: TextPostProcessor(),
            noteStructuring: CloudOrLocalNoteStructuringService(
                local: LocalNoteStructuringService(),
                provider: modelProvider,
                reportStatus: { [weak runtimeStatus] status in
                    runtimeStatus?.lastModelCall = status
                }
            ),
            textEnhancement: ModelBackedTextEnhancementService(
                provider: modelProvider,
                reportStatus: { [weak runtimeStatus] status in
                    runtimeStatus?.lastModelCall = status
                }
            ),
            finalTranscription: CodexASRFinalTranscriptionService(
                reportStatus: { [weak runtimeStatus] status in
                    runtimeStatus?.lastASRCall = status
                },
                recordUsage: { [weak runtimeStatus, weak self] outcome in
                    guard let self else {
                        return
                    }
                    let snapshot = self.asrUsageStore.record(outcome)
                    runtimeStatus?.asrUsageSnapshot = snapshot
                    runtimeStatus?.lastASRCall = snapshot.lastStatusText
                }
            ),
            textInsertion: TextInsertionService(),
            recordHistory: { [weak self] entry in
                self?.sessionHistoryStore.record(entry)
            }
        )

        self.coordinator = coordinator
        coordinator.setStateObserver { [weak self] _ in
            self?.updateFloatingPanel()
        }
        hotkeyService = HotkeyService(
            preferences: { [weak self] in
                self?.preferencesStore.preferences ?? .defaults
            },
            handler: { [weak self] action in
                self?.handleHotkey(action)
            }
        )
    }

    private func startHotkeys() {
        hotkeyService?.start()
        runtimeStatus.hotkeysRunning = hotkeyService?.isRunning == true
        runtimeStatus.hotkeyStartFailed = hotkeyService?.lastStartFailed == true
        if hotkeyService?.lastStartFailed == true {
            renderHotkeyStartFailure()
        } else {
            updateFloatingPanel()
        }
    }

    private func handleHotkey(_ action: HotkeyAction) {
        switch action {
        case .toggleOrdinary:
            runtimeStatus.lastHotkeyAction = "\(preferencesStore.preferences.ordinaryHotkey.displayName) 普通记录"
            toggle(.ordinary)
        case .toggleStructured:
            runtimeStatus.lastHotkeyAction = "\(preferencesStore.preferences.structuredHotkey.displayName) 自动分点"
            toggle(.structured)
        case .commitCurrent:
            runtimeStatus.lastHotkeyAction = "结束并插入"
            commitCurrentSession()
        case .discard:
            runtimeStatus.lastHotkeyAction = "\(preferencesStore.preferences.resolvedDiscardHotkey.displayName) 放弃"
            discardCurrentSession()
        }
    }

    private func toggle(_ mode: AppMode) {
        guard let coordinator else {
            return
        }

        runSerializedOperation {
            do {
                try await coordinator.toggle(mode)
            } catch {
                self.updateFloatingPanel()
            }
            self.updateFloatingPanel()
        }
    }

    private func commitCurrentSession() {
        guard let coordinator else {
            return
        }

        runSerializedOperation {
            do {
                try await coordinator.commitCurrent()
            } catch {
                self.updateFloatingPanel()
            }
            self.updateFloatingPanel()
        }
    }

    private func discardCurrentSession() {
        guard let coordinator else {
            return
        }

        operationRunner.cancel()
        Task { @MainActor in
            await coordinator.discard()
            self.updateFloatingPanel()
        }
    }

    private func stopCurrentMode() {
        guard let coordinator, isListening(coordinator.state) else {
            return
        }

        commitCurrentSession()
    }

    private func mode(for state: AppState) -> AppMode? {
        switch state {
        case .recording(let mode), .recognizing(let mode), .previewing(let mode, _):
            mode
        case .idle, .structuring, .inserting, .completed, .error:
            nil
        }
    }

    private func isListening(_ state: AppState) -> Bool {
        switch state {
        case .recording, .previewing:
            true
        case .idle, .recognizing, .structuring, .inserting, .completed, .error:
            false
        }
    }

    private func runSerializedOperation(_ operation: @escaping @MainActor () async -> Void) {
        operationRunner.run {
            await operation()
            self.updateFloatingPanel()
        }
    }

    private func updateFloatingPanel() {
        guard let coordinator else {
            hotkeyService?.updateSessionActive(false)
            floatingPanel.hide()
            return
        }

        hotkeyService?.updateSessionActive(isListening(coordinator.state))
        let displayMode = preferencesStore.preferences.floatingPanelDisplayMode ?? .hidden
        switch coordinator.state {
        case let state where !FloatingPanelPresentationPolicy.shouldShow(state, mode: displayMode):
            floatingPanel.hide()
        default:
            floatingPanel.show(
                state: coordinator.state,
                stop: stopAction(for: coordinator.state),
                cancel: { [weak self] in self?.discardCurrentSession() },
                showsTextPreview: FloatingPanelPresentationPolicy.shouldUseTextPreview(mode: displayMode),
                asrStatus: runtimeStatus.lastASRCall,
                actionHint: "Space 完成   \(preferencesStore.preferences.resolvedDiscardHotkey.displayName) 放弃"
            )
        }
    }

    private func stopAction(for state: AppState) -> (() -> Void)? {
        guard !operationRunner.isRunning, isListening(state) else {
            return nil
        }

        return { [weak self] in
            self?.stopCurrentMode()
        }
    }

    private func renderHotkeyStartFailure() {
        floatingPanel.show(
            state: .error(message: "全局快捷键启动失败。请在系统设置里允许 lesstype 使用“辅助功能”，然后回到主界面点击“重新启用快捷键”。"),
            stop: nil,
            cancel: { [weak self] in self?.floatingPanel.hide() }
        )
    }
}
