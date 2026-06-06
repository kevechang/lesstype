import Foundation

public struct RecordedAudio: Equatable, Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }
}

public struct RecognitionResult: Equatable, Sendable {
    public let finalText: String
    public let previews: [String]
    public let audioURL: URL?

    public init(finalText: String, previews: [String], audioURL: URL? = nil) {
        self.finalText = finalText
        self.previews = previews
        self.audioURL = audioURL
    }
}

public protocol AudioCaptureServing: Sendable {
    func startRecording() async throws
    func stopRecording() async throws -> RecordedAudio
    func cancelRecording() async
}

public protocol RecognitionServing: Sendable {
    func recognize(audio: RecordedAudio, languageMode: LanguageMode) async throws -> RecognitionResult
}

@MainActor
public protocol LiveRecognitionServing: AnyObject {
    func start(
        languageMode: LanguageMode,
        capturesAudio: Bool,
        onPreview: @escaping @MainActor @Sendable (String) -> Void
    ) async throws
    func finish() async throws -> RecognitionResult
    func cancel() async
}

@MainActor
public protocol TextInsertionServing: AnyObject {
    func insert(_ text: String) async throws
}
