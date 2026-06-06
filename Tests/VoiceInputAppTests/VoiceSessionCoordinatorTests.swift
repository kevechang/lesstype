import XCTest
@testable import VoiceInputApp

@MainActor
final class VoiceSessionCoordinatorTests: XCTestCase {
    func testOrdinaryModeStopsAndInsertsProcessedText() async throws {
        let insertion = FakeTextInsertionService()
        let liveRecognition = FakeLiveRecognitionService(finalText: "我想用 swift ui 做 app 然后接 api")
        let coordinator = VoiceSessionCoordinator(
            preferencesStore: makePreferencesStore("Coordinator.ordinary"),
            liveRecognition: liveRecognition,
            postProcessor: TextPostProcessor(),
            noteStructuring: LocalNoteStructuringService(),
            textEnhancement: LocalTextEnhancementService(),
            textInsertion: insertion
        )

        try await coordinator.toggle(.ordinary)
        try await coordinator.toggle(.ordinary)

        XCTAssertEqual(insertion.insertedText, "我想用 SwiftUI 做 app，然后接 API。")
        XCTAssertEqual(coordinator.state, .completed(text: "我想用 SwiftUI 做 app，然后接 API。"))
        XCTAssertEqual(liveRecognition.startCallCount, 1)
        XCTAssertEqual(liveRecognition.finishCallCount, 1)
    }

    func testStructuredModeStopsStructuresAndInsertsBullets() async throws {
        let insertion = FakeTextInsertionService()
        let coordinator = VoiceSessionCoordinator(
            preferencesStore: makePreferencesStore("Coordinator.structured"),
            liveRecognition: FakeLiveRecognitionService(finalText: "嗯 先做普通模式 然后做分点模式"),
            postProcessor: TextPostProcessor(),
            noteStructuring: LocalNoteStructuringService(),
            textEnhancement: LocalTextEnhancementService(),
            textInsertion: insertion
        )

        try await coordinator.toggle(.structured)
        try await coordinator.toggle(.structured)

        XCTAssertEqual(insertion.insertedText, "1. 先做普通模式。\n2. 做分点模式。")
    }

    func testCancelStopsWithoutInsertion() async throws {
        let insertion = FakeTextInsertionService()
        let liveRecognition = FakeLiveRecognitionService(finalText: "不会插入")
        let coordinator = VoiceSessionCoordinator(
            preferencesStore: makePreferencesStore("Coordinator.cancel"),
            liveRecognition: liveRecognition,
            postProcessor: TextPostProcessor(),
            noteStructuring: LocalNoteStructuringService(),
            textEnhancement: LocalTextEnhancementService(),
            textInsertion: insertion
        )

        try await coordinator.toggle(.ordinary)
        await coordinator.discard()

        XCTAssertNil(insertion.insertedText)
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertEqual(liveRecognition.cancelCallCount, 1)
    }

    func testCommitCurrentInsertsInsteadOfDiscarding() async throws {
        let insertion = FakeTextInsertionService()
        let coordinator = VoiceSessionCoordinator(
            preferencesStore: makePreferencesStore("Coordinator.commitCurrent"),
            liveRecognition: FakeLiveRecognitionService(finalText: "直接放到聊天框"),
            postProcessor: TextPostProcessor(),
            noteStructuring: LocalNoteStructuringService(),
            textEnhancement: LocalTextEnhancementService(),
            textInsertion: insertion
        )

        try await coordinator.toggle(.ordinary)
        try await coordinator.commitCurrent()

        XCTAssertEqual(insertion.insertedText, "直接放到聊天框。")
    }

    func testStreamingPreviewUpdatesStateWhileRecording() async throws {
        let liveRecognition = FakeLiveRecognitionService(finalText: "最终文本", previews: ["第一段", "第一段 第二段"])
        let coordinator = VoiceSessionCoordinator(
            preferencesStore: makePreferencesStore("Coordinator.streamingPreview"),
            liveRecognition: liveRecognition,
            postProcessor: TextPostProcessor(),
            noteStructuring: LocalNoteStructuringService(),
            textEnhancement: LocalTextEnhancementService(),
            textInsertion: FakeTextInsertionService()
        )

        try await coordinator.toggle(.ordinary)

        XCTAssertEqual(coordinator.state, .previewing(.ordinary, text: "第一段 第二段"))
    }

    func testFinalInsertedTextUsesSimplifiedChinese() async throws {
        let insertion = FakeTextInsertionService()
        let coordinator = VoiceSessionCoordinator(
            preferencesStore: makePreferencesStore("Coordinator.simplifiedFinalText"),
            liveRecognition: FakeLiveRecognitionService(finalText: "這個語音識別輸出繁體中文"),
            postProcessor: TextPostProcessor(),
            noteStructuring: LocalNoteStructuringService(),
            textEnhancement: TraditionalTextEnhancementService(),
            textInsertion: insertion
        )

        try await coordinator.toggle(.ordinary)
        try await coordinator.commitCurrent()

        XCTAssertEqual(insertion.insertedText, "这个语音识别输出繁体中文")
        XCTAssertEqual(coordinator.state, .completed(text: "这个语音识别输出繁体中文"))
    }

    func testCompletedSessionRecordsLightweightHistoryEntry() async throws {
        let insertion = FakeTextInsertionService()
        let history = SessionHistoryStore(limit: 20)
        let coordinator = VoiceSessionCoordinator(
            preferencesStore: makePreferencesStore("Coordinator.history"),
            liveRecognition: FakeLiveRecognitionService(finalText: "我想记录一下历史"),
            postProcessor: TextPostProcessor(),
            noteStructuring: LocalNoteStructuringService(),
            textEnhancement: LocalTextEnhancementService(),
            textInsertion: insertion,
            recordHistory: { entry in
                history.record(entry)
            }
        )

        try await coordinator.toggle(.ordinary)
        try await coordinator.commitCurrent()

        let entry = try XCTUnwrap(history.entries.first)
        XCTAssertEqual(entry.mode, .ordinary)
        XCTAssertEqual(entry.recognizedText, "我想记录一下历史")
        XCTAssertEqual(entry.outputText, "我想记录一下历史。")
        XCTAssertEqual(entry.outcome, .inserted)
    }

    func testCloudTranscriptionResultReplacesAppleFinalTextBeforeInsertion() async throws {
        let audioURL = URL(fileURLWithPath: "/tmp/fake-codex-asr.m4a")
        let insertion = FakeTextInsertionService()
        let transcription = FakeAudioTranscriptionService(text: "Codex ASR 识别结果")
        let preferencesStore = makePreferencesStore("Coordinator.codexASR")
        var preferences = preferencesStore.preferences
        preferences.cloudTranscriptionEnabled = true
        preferences.chinesePunctuationEnabled = false
        preferencesStore.save(preferences)
        let coordinator = VoiceSessionCoordinator(
            preferencesStore: preferencesStore,
            liveRecognition: FakeLiveRecognitionService(finalText: "Apple 识别结果", audioURL: audioURL),
            postProcessor: TextPostProcessor(),
            noteStructuring: LocalNoteStructuringService(),
            textEnhancement: LocalTextEnhancementService(),
            finalTranscription: CodexASRFinalTranscriptionService(transcription: transcription),
            textInsertion: insertion
        )

        try await coordinator.toggle(.ordinary)
        try await coordinator.commitCurrent()

        XCTAssertEqual(transcription.requestedAudioURL, audioURL)
        XCTAssertEqual(insertion.insertedText, "Codex ASR 识别结果")
    }

    func testCloudTranscriptionRunsWhenAppleFinalTextIsEmptyButAudioExists() async throws {
        let audioURL = URL(fileURLWithPath: "/tmp/fake-codex-asr-empty-apple.wav")
        let insertion = FakeTextInsertionService()
        let transcription = FakeAudioTranscriptionService(text: "Codex 单独识别成功")
        let preferencesStore = makePreferencesStore("Coordinator.codexASREmptyApple")
        var preferences = preferencesStore.preferences
        preferences.cloudTranscriptionEnabled = true
        preferences.chinesePunctuationEnabled = false
        preferencesStore.save(preferences)
        let coordinator = VoiceSessionCoordinator(
            preferencesStore: preferencesStore,
            liveRecognition: FakeLiveRecognitionService(finalText: "", audioURL: audioURL),
            postProcessor: TextPostProcessor(),
            noteStructuring: LocalNoteStructuringService(),
            textEnhancement: LocalTextEnhancementService(),
            finalTranscription: CodexASRFinalTranscriptionService(transcription: transcription),
            textInsertion: insertion
        )

        try await coordinator.toggle(.ordinary)
        try await coordinator.commitCurrent()

        XCTAssertEqual(transcription.requestedAudioURL, audioURL)
        XCTAssertEqual(insertion.insertedText, "Codex 单独识别成功")
    }

    func testEmptyTextAfterCloudTranscriptionFailureDoesNotInsertBlankText() async throws {
        let audioURL = URL(fileURLWithPath: "/tmp/fake-codex-asr-failed.wav")
        let insertion = FakeTextInsertionService()
        let preferencesStore = makePreferencesStore("Coordinator.codexASREmptyFallback")
        var preferences = preferencesStore.preferences
        preferences.cloudTranscriptionEnabled = true
        preferencesStore.save(preferences)
        let coordinator = VoiceSessionCoordinator(
            preferencesStore: preferencesStore,
            liveRecognition: FakeLiveRecognitionService(finalText: "", audioURL: audioURL),
            postProcessor: TextPostProcessor(),
            noteStructuring: LocalNoteStructuringService(),
            textEnhancement: LocalTextEnhancementService(),
            finalTranscription: CodexASRFinalTranscriptionService(
                transcription: FailingAudioTranscriptionService()
            ),
            textInsertion: insertion
        )

        try await coordinator.toggle(.ordinary)
        do {
            try await coordinator.commitCurrent()
            XCTFail("Expected noResult to be thrown")
        } catch SpeechRecognitionError.noResult {}

        XCTAssertNil(insertion.insertedText)
        assertErrorState(coordinator.state)
    }

    func testStateObserverReceivesPreviewUpdatesWithoutPolling() async throws {
        let liveRecognition = FakeLiveRecognitionService(finalText: "最终文本", previews: ["第一段", "第一段 第二段"])
        let coordinator = VoiceSessionCoordinator(
            preferencesStore: makePreferencesStore("Coordinator.stateObserver"),
            liveRecognition: liveRecognition,
            postProcessor: TextPostProcessor(),
            noteStructuring: LocalNoteStructuringService(),
            textEnhancement: LocalTextEnhancementService(),
            textInsertion: FakeTextInsertionService()
        )
        var observedStates: [AppState] = []
        coordinator.setStateObserver { state in
            observedStates.append(state)
        }

        try await coordinator.toggle(.ordinary)

        XCTAssertTrue(observedStates.contains(.previewing(.ordinary, text: "第一段 第二段")))
    }

    func testStartRecordingFailureLeavesCoordinatorRecoverable() async throws {
        let liveRecognition = FakeLiveRecognitionService(finalText: "恢复后继续", startError: TestError.startFailed)
        let coordinator = VoiceSessionCoordinator(
            preferencesStore: makePreferencesStore("Coordinator.startFailure"),
            liveRecognition: liveRecognition,
            postProcessor: TextPostProcessor(),
            noteStructuring: LocalNoteStructuringService(),
            textEnhancement: LocalTextEnhancementService(),
            textInsertion: FakeTextInsertionService()
        )

        do {
            try await coordinator.toggle(.ordinary)
            XCTFail("Expected error to be thrown")
        } catch {}
        assertErrorState(coordinator.state)

        liveRecognition.startError = nil
        try await coordinator.toggle(.ordinary)

        XCTAssertEqual(liveRecognition.startCallCount, 2)
        XCTAssertEqual(liveRecognition.finishCallCount, 0)
        XCTAssertEqual(coordinator.state, .previewing(.ordinary, text: ""))
    }

    func testRecognitionFailureLeavesCoordinatorRecoverable() async throws {
        let liveRecognition = FakeLiveRecognitionService(finalText: "恢复后继续", finishError: TestError.recognitionFailed)
        let coordinator = VoiceSessionCoordinator(
            preferencesStore: makePreferencesStore("Coordinator.recognitionFailure"),
            liveRecognition: liveRecognition,
            postProcessor: TextPostProcessor(),
            noteStructuring: LocalNoteStructuringService(),
            textEnhancement: LocalTextEnhancementService(),
            textInsertion: FakeTextInsertionService()
        )

        try await coordinator.toggle(.ordinary)
        do {
            try await coordinator.toggle(.ordinary)
            XCTFail("Expected error to be thrown")
        } catch {}
        assertErrorState(coordinator.state)

        liveRecognition.finishError = nil
        try await coordinator.toggle(.ordinary)

        XCTAssertEqual(liveRecognition.startCallCount, 2)
        XCTAssertEqual(liveRecognition.finishCallCount, 1)
        XCTAssertEqual(coordinator.state, .previewing(.ordinary, text: ""))
    }

    func testRecognitionCancellationReturnsToIdleWithoutError() async throws {
        let liveRecognition = FakeLiveRecognitionService(finalText: "恢复后继续", finishError: CancellationError())
        let coordinator = VoiceSessionCoordinator(
            preferencesStore: makePreferencesStore("Coordinator.recognitionCancellation"),
            liveRecognition: liveRecognition,
            postProcessor: TextPostProcessor(),
            noteStructuring: LocalNoteStructuringService(),
            textEnhancement: LocalTextEnhancementService(),
            textInsertion: FakeTextInsertionService()
        )

        try await coordinator.toggle(.ordinary)
        try await coordinator.commitCurrent()

        XCTAssertEqual(coordinator.state, .idle)
    }

    func testNoteStructuringFailureLeavesCoordinatorRecoverable() async throws {
        let noteStructuring = FakeNoteStructuringService(error: TestError.structuringFailed)
        let coordinator = VoiceSessionCoordinator(
            preferencesStore: makePreferencesStore("Coordinator.structuringFailure"),
            liveRecognition: FakeLiveRecognitionService(finalText: "先做普通模式"),
            postProcessor: TextPostProcessor(),
            noteStructuring: noteStructuring,
            textEnhancement: LocalTextEnhancementService(),
            textInsertion: FakeTextInsertionService()
        )

        try await coordinator.toggle(.structured)
        do {
            try await coordinator.toggle(.structured)
            XCTFail("Expected error to be thrown")
        } catch {}
        assertErrorState(coordinator.state)

        noteStructuring.error = nil
        try await coordinator.toggle(.structured)

        XCTAssertEqual(coordinator.state, .previewing(.structured, text: ""))
    }

    func testInsertionFailureLeavesCoordinatorRecoverable() async throws {
        let insertion = FakeTextInsertionService(error: TestError.insertionFailed)
        let coordinator = VoiceSessionCoordinator(
            preferencesStore: makePreferencesStore("Coordinator.insertionFailure"),
            liveRecognition: FakeLiveRecognitionService(finalText: "恢复后继续"),
            postProcessor: TextPostProcessor(),
            noteStructuring: LocalNoteStructuringService(),
            textEnhancement: LocalTextEnhancementService(),
            textInsertion: insertion
        )

        try await coordinator.toggle(.ordinary)
        do {
            try await coordinator.toggle(.ordinary)
            XCTFail("Expected error to be thrown")
        } catch {}
        assertErrorState(coordinator.state)

        insertion.error = nil
        try await coordinator.toggle(.ordinary)

        XCTAssertEqual(coordinator.state, .previewing(.ordinary, text: ""))
    }

    private func makePreferencesStore(_ suiteName: String) -> PreferencesStore {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return PreferencesStore(defaults: defaults, apiKeyStore: InMemoryAPIKeyStore())
    }

    private func assertErrorState(_ state: AppState, file: StaticString = #filePath, line: UInt = #line) {
        guard case let .error(message) = state else {
            XCTFail("Expected error state, got \(state)", file: file, line: line)
            return
        }
        XCTAssertFalse(message.isEmpty, file: file, line: line)
    }

}

@MainActor
private final class FakeLiveRecognitionService: LiveRecognitionServing {
    let finalText: String
    let previews: [String]
    let audioURL: URL?
    var startError: Error?
    var finishError: Error?
    private(set) var startCallCount = 0
    private(set) var finishCallCount = 0
    private(set) var cancelCallCount = 0

    init(
        finalText: String,
        previews: [String] = [],
        audioURL: URL? = nil,
        startError: Error? = nil,
        finishError: Error? = nil
    ) {
        self.finalText = finalText
        self.previews = previews
        self.audioURL = audioURL
        self.startError = startError
        self.finishError = finishError
    }

    func start(languageMode: LanguageMode, capturesAudio: Bool, onPreview: @escaping @MainActor @Sendable (String) -> Void) async throws {
        startCallCount += 1
        if let startError {
            throw startError
        }
        for preview in previews {
            onPreview(preview)
        }
    }

    func finish() async throws -> RecognitionResult {
        finishCallCount += 1
        if let finishError {
            throw finishError
        }
        return RecognitionResult(finalText: finalText, previews: previews, audioURL: audioURL)
    }

    func cancel() async {
        cancelCallCount += 1
    }
}

private final class FakeNoteStructuringService: NoteStructuringService, @unchecked Sendable {
    var error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func structure(_ text: String, preferences: Preferences) async throws -> String {
        if let error {
            throw error
        }
        return "- \(text)"
    }
}

private struct LocalTextEnhancementService: TextEnhancementService {
    private let processor = TextPostProcessor()

    func enhance(_ text: String, preferences: Preferences) async throws -> String {
        processor.process(text, preferences: preferences)
    }
}

private struct TraditionalTextEnhancementService: TextEnhancementService {
    func enhance(_ text: String, preferences: Preferences) async throws -> String {
        "這個語音識別輸出繁體中文"
    }
}

private final class FakeAudioTranscriptionService: AudioTranscriptionServing, @unchecked Sendable {
    let text: String
    var requestedAudioURL: URL?

    init(text: String) {
        self.text = text
    }

    func transcribe(audioURL: URL, languageMode: LanguageMode) async throws -> String {
        requestedAudioURL = audioURL
        return text
    }
}

private struct FailingAudioTranscriptionService: AudioTranscriptionServing {
    func transcribe(audioURL: URL, languageMode: LanguageMode) async throws -> String {
        throw TestError.recognitionFailed
    }
}

private final class FakeTextInsertionService: TextInsertionServing {
    var insertedText: String?
    var error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func insert(_ text: String) async throws {
        if let error {
            throw error
        }
        insertedText = text
    }
}

private final class InMemoryAPIKeyStore: APIKeyStoring, @unchecked Sendable {
    func loadAPIKey() -> String { "" }
    func saveAPIKey(_ apiKey: String) {}
    func loadAPIKey(for scope: ModelConfigurationScope) -> String { "" }
    func saveAPIKey(_ apiKey: String, for scope: ModelConfigurationScope) {}
}

private enum TestError: Error, LocalizedError {
    case startFailed
    case recognitionFailed
    case structuringFailed
    case insertionFailed

    var errorDescription: String? {
        switch self {
        case .startFailed:
            "Start failed"
        case .recognitionFailed:
            "Recognition failed"
        case .structuringFailed:
            "Structuring failed"
        case .insertionFailed:
            "Insertion failed"
        }
    }
}
