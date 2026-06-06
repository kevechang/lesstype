import Foundation
import AVFoundation
import Speech

public struct AppleSpeechRecognitionService: RecognitionServing {
    public init() {}

    public func recognize(audio: RecordedAudio, languageMode: LanguageMode) async throws -> RecognitionResult {
        let locale = locale(for: languageMode)
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw SpeechRecognitionError.recognizerUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: audio.url)
        request.shouldReportPartialResults = true
        request.contextualStrings = ["SwiftUI", "macOS", "OpenAI", "API"]

        let state = SpeechRecognitionState()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.setContinuation(continuation)
                let task = recognizer.recognitionTask(with: request) { result, error in
                    state.handle(result: result, error: error)
                }
                state.setTask(task)
            }
        } onCancel: {
            state.cancel()
        }
    }

    private func locale(for languageMode: LanguageMode) -> Locale {
        switch languageMode {
        case .chineseFirst:
            Locale(identifier: "zh-CN")
        case .englishFirst:
            Locale(identifier: "en-US")
        case .automatic:
            Locale(identifier: "zh-CN")
        }
    }
}

@MainActor
public final class AppleLiveSpeechRecognitionService: LiveRecognitionServing {
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latestText = ""
    private var previews = RecognitionPreviewBuffer()
    private var previewHandler: (@MainActor @Sendable (String) -> Void)?
    private var finishContinuation: CheckedContinuation<RecognitionResult, Error>?
    private var finishTimeoutTask: Task<Void, Never>?
    private var audioFile: AVAudioFile?
    private var audioURL: URL?

    public init() {}

    public func start(
        languageMode: LanguageMode,
        capturesAudio: Bool = false,
        onPreview: @escaping @MainActor @Sendable (String) -> Void
    ) async throws {
        await cancel()

        guard let recognizer = SFSpeechRecognizer(locale: locale(for: languageMode)), recognizer.isAvailable else {
            throw SpeechRecognitionError.recognizerUnavailable
        }

        let audioEngine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.contextualStrings = ["SwiftUI", "macOS", "OpenAI", "API", "ChatGPT", "Claude", "Gemini"]

        latestText = ""
        previews.removeAll()
        previewHandler = onPreview
        self.audioEngine = audioEngine
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        if capturesAudio {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("VoiceInput-live-\(UUID().uuidString).wav")
            do {
                audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
                audioURL = url
            } catch {
                audioFile = nil
                audioURL = nil
            }
        }
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: format,
            block: Self.makeAudioTapBlock(request: request, audioFile: audioFile)
        )

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            resetSession(cancelTask: true, removeAudioFile: true)
            throw error
        }

        task = recognizer.recognitionTask(with: request, resultHandler: Self.makeRecognitionHandler(self))
    }

    public func finish() async throws -> RecognitionResult {
        stopAudio()
        request?.endAudio()

        return try await withCheckedThrowingContinuation { continuation in
            finishContinuation = continuation
            finishTimeoutTask?.cancel()
            if LiveRecognitionFinalResultResolver.shouldFinishImmediately(audioURL: audioURL),
               let result = resultFromLatestText() {
                finish(with: .success(result))
                return
            }
            let timeout: Duration = resultFromLatestText() == nil ? .milliseconds(1200) : .milliseconds(700)
            finishTimeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                guard let self, self.finishContinuation != nil else {
                    return
                }
                if let result = self.resultFromLatestText() {
                    self.finish(with: .success(result))
                } else {
                    self.finish(with: .failure(SpeechRecognitionError.noResult))
                }
            }
        }
    }

    public func cancel() async {
        stopAudio()
        request?.endAudio()
        finishTimeoutTask?.cancel()
        finishTimeoutTask = nil
        finishContinuation?.resume(throwing: CancellationError())
        finishContinuation = nil
        resetSession(cancelTask: true, removeAudioFile: true)
    }

    private func locale(for languageMode: LanguageMode) -> Locale {
        switch languageMode {
        case .chineseFirst:
            Locale(identifier: "zh-CN")
        case .englishFirst:
            Locale(identifier: "en-US")
        case .automatic:
            Locale(identifier: "zh-CN")
        }
    }

    private nonisolated static func makeAudioTapBlock(
        request: SFSpeechAudioBufferRecognitionRequest,
        audioFile: AVAudioFile?
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            request.append(buffer)
            try? audioFile?.write(from: buffer)
        }
    }

    private nonisolated static func makeRecognitionHandler(
        _ service: AppleLiveSpeechRecognitionService
    ) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { [weak service] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal == true
            let errorMessage = error?.localizedDescription

            Task { @MainActor [weak service] in
                service?.handleRecognitionUpdate(text: text, isFinal: isFinal, errorMessage: errorMessage)
            }
        }
    }

    private func handleRecognitionUpdate(text: String?, isFinal: Bool, errorMessage: String?) {
        if let text {
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedText.isEmpty {
                latestText = text
                previews.append(text)
                previewHandler?(text)
            }
        }

        if isFinal, let result = resultFromLatestText() {
            finish(with: .success(result))
        } else if let errorMessage, finishContinuation != nil {
            if let result = resultFromLatestText() {
                finish(with: .success(result))
            } else {
                finish(with: .failure(SpeechRecognitionError.recognitionFailed(errorMessage)))
            }
        }
    }

    private func resultFromLatestText() -> RecognitionResult? {
        LiveRecognitionFinalResultResolver.resolve(
            latestText: latestText,
            previews: previews.values,
            audioURL: audioURL
        )
    }

    private func stopAudio() {
        if let audioEngine {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
    }

    private func finish(with completion: Result<RecognitionResult, Error>) {
        guard let continuation = finishContinuation else {
            resetSession(cancelTask: false, removeAudioFile: true)
            return
        }

        finishContinuation = nil
        finishTimeoutTask?.cancel()
        finishTimeoutTask = nil
        let shouldRemoveAudioFile: Bool
        switch completion {
        case .success:
            shouldRemoveAudioFile = false
        case .failure:
            shouldRemoveAudioFile = true
        }
        resetSession(cancelTask: false, removeAudioFile: shouldRemoveAudioFile)

        switch completion {
        case .success(let result):
            continuation.resume(returning: result)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    private func resetSession(cancelTask: Bool, removeAudioFile: Bool) {
        if cancelTask {
            task?.cancel()
        } else {
            task?.finish()
        }
        let currentAudioURL = audioURL
        task = nil
        request = nil
        audioEngine = nil
        audioFile = nil
        audioURL = nil
        previewHandler = nil
        if removeAudioFile, let currentAudioURL {
            try? FileManager.default.removeItem(at: currentAudioURL)
        }
    }
}

struct LiveRecognitionFinalResultResolver {
    static func resolve(latestText: String, previews: [String], audioURL: URL?) -> RecognitionResult? {
        let text = latestText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            return RecognitionResult(finalText: latestText, previews: previews, audioURL: audioURL)
        }
        guard let audioURL else {
            return nil
        }
        return RecognitionResult(finalText: "", previews: previews, audioURL: audioURL)
    }

    static func shouldFinishImmediately(audioURL: URL?) -> Bool {
        audioURL != nil
    }
}

public enum SpeechRecognitionError: LocalizedError {
    case recognizerUnavailable
    case noResult
    case recognitionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            "当前语言的语音识别不可用。"
        case .noResult:
            "语音识别没有返回可用结果。"
        case .recognitionFailed(let message):
            message
        }
    }
}

private final class SpeechRecognitionState: @unchecked Sendable {
    private enum Completion {
        case success(RecognitionResult)
        case failure(Error)
    }

    private let lock = NSLock()
    private var previews = RecognitionPreviewBuffer()
    private var completed = false
    private var task: SFSpeechRecognitionTask?
    private var continuation: CheckedContinuation<RecognitionResult, Error>?

    func setContinuation(_ continuation: CheckedContinuation<RecognitionResult, Error>) {
        var completion: Completion?

        lock.lock()
        if completed {
            completion = .failure(CancellationError())
        } else {
            self.continuation = continuation
        }
        lock.unlock()

        if let completion {
            resume(continuation, with: completion)
        }
    }

    func setTask(_ task: SFSpeechRecognitionTask) {
        var shouldCancel = false

        lock.lock()
        if completed {
            shouldCancel = true
        } else {
            self.task = task
        }
        lock.unlock()

        if shouldCancel {
            task.cancel()
        }
    }

    func handle(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            let text = result.bestTranscription.formattedString
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

            lock.lock()
            if !completed, !trimmedText.isEmpty {
                previews.append(text)
            }
            let currentPreviews = previews.values
            lock.unlock()

            if result.isFinal {
                let finalText = !trimmedText.isEmpty ? text : currentPreviews.last ?? ""
                finish(with: finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? .failure(SpeechRecognitionError.noResult)
                    : .success(RecognitionResult(finalText: finalText, previews: currentPreviews)))
                return
            }
        }

        if let error {
            finish(with: .failure(error))
        }
    }

    func cancel() {
        var taskToCancel: SFSpeechRecognitionTask?
        var continuationToResume: CheckedContinuation<RecognitionResult, Error>?

        lock.lock()
        if !completed {
            completed = true
            taskToCancel = task
            continuationToResume = continuation
            task = nil
            continuation = nil
        }
        lock.unlock()

        taskToCancel?.cancel()
        if let continuationToResume {
            continuationToResume.resume(throwing: CancellationError())
        }
    }

    private func finish(with completion: Completion) {
        var continuationToResume: CheckedContinuation<RecognitionResult, Error>?

        lock.lock()
        if !completed {
            completed = true
            continuationToResume = continuation
            task = nil
            continuation = nil
        }
        lock.unlock()

        if let continuationToResume {
            resume(continuationToResume, with: completion)
        }
    }

    private func resume(_ continuation: CheckedContinuation<RecognitionResult, Error>, with completion: Completion) {
        switch completion {
        case .success(let result):
            continuation.resume(returning: result)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
