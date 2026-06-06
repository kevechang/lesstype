import Foundation

@MainActor
public final class VoiceSessionCoordinator {
    public private(set) var state: AppState = .idle {
        didSet {
            stateObserver?(state)
        }
    }

    private let preferencesStore: PreferencesStore
    private let liveRecognition: LiveRecognitionServing
    private let postProcessor: TextPostProcessor
    private let noteStructuring: NoteStructuringService
    private let textEnhancement: TextEnhancementService
    private let finalTranscription: CodexASRFinalTranscriptionService
    private let textInsertion: TextInsertionServing
    private let recordHistory: @MainActor @Sendable (VoiceSessionHistoryEntry) -> Void
    private var activeMode: AppMode?
    private var stateObserver: ((AppState) -> Void)?

    public init(
        preferencesStore: PreferencesStore,
        liveRecognition: LiveRecognitionServing,
        postProcessor: TextPostProcessor,
        noteStructuring: NoteStructuringService,
        textEnhancement: TextEnhancementService,
        finalTranscription: CodexASRFinalTranscriptionService = CodexASRFinalTranscriptionService(),
        textInsertion: TextInsertionServing,
        recordHistory: @escaping @MainActor @Sendable (VoiceSessionHistoryEntry) -> Void = { _ in }
    ) {
        self.preferencesStore = preferencesStore
        self.liveRecognition = liveRecognition
        self.postProcessor = postProcessor
        self.noteStructuring = noteStructuring
        self.textEnhancement = textEnhancement
        self.finalTranscription = finalTranscription
        self.textInsertion = textInsertion
        self.recordHistory = recordHistory
    }

    public func setStateObserver(_ observer: @escaping (AppState) -> Void) {
        stateObserver = observer
        observer(state)
    }

    public func toggle(_ mode: AppMode) async throws {
        do {
            if activeMode == mode {
                try await commitCurrent()
            } else if activeMode == nil {
                try await start(mode)
            } else {
                await discard()
                try await start(mode)
            }
        } catch {
            if isCancellation(error) {
                activeMode = nil
                state = .idle
                return
            }
            activeMode = nil
            state = .error(message: errorMessage(for: error))
            throw error
        }
    }

    public func commitCurrent() async throws {
        guard let mode = activeMode else {
            return
        }

        do {
            try await finishAndInsert(mode)
        } catch {
            if isCancellation(error) {
                activeMode = nil
                state = .idle
                return
            }
            activeMode = nil
            state = .error(message: errorMessage(for: error))
            throw error
        }
    }

    public func discard() async {
        await liveRecognition.cancel()
        activeMode = nil
        state = .idle
    }

    public func cancel() async {
        await discard()
    }

    private func start(_ mode: AppMode) async throws {
        activeMode = mode
        state = .previewing(mode, text: "")
        try await liveRecognition.start(
            languageMode: preferencesStore.preferences.languageMode,
            capturesAudio: preferencesStore.preferences.cloudTranscriptionEnabled,
            onPreview: { [weak self] text in
                guard let self, self.activeMode == mode else {
                    return
                }
                self.state = .previewing(mode, text: text)
            }
        )
    }

    private func finishAndInsert(_ mode: AppMode) async throws {
        state = .recognizing(mode)
        let recognitionResult = try await liveRecognition.finish()
        defer {
            if let audioURL = recognitionResult.audioURL {
                try? FileManager.default.removeItem(at: audioURL)
            }
        }
        let recognizedText = await finalTranscription.resolvedText(
            from: recognitionResult,
            preferences: preferencesStore.preferences
        )
        guard !recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SpeechRecognitionError.noResult
        }

        let finalText: String
        switch mode {
        case .ordinary:
            finalText = try await textEnhancement.enhance(
                recognizedText,
                preferences: preferencesStore.preferences
            )
        case .structured:
            state = .structuring(text: recognizedText)
            finalText = try await noteStructuring.structure(
                recognizedText,
                preferences: preferencesStore.preferences
            )
        }

        let outputText = TextPostProcessor.simplifiedChinese(finalText)
        state = .inserting(text: outputText)
        try await textInsertion.insert(outputText)
        activeMode = nil
        state = .completed(text: outputText)
        recordHistory(
            VoiceSessionHistoryEntry(
                mode: mode,
                recognizedText: recognizedText,
                outputText: outputText,
                outcome: .inserted
            )
        )
    }

    private func errorMessage(for error: Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.isEmpty {
            return "操作失败。"
        }
        return message
    }

    private func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || Task.isCancelled
    }
}
