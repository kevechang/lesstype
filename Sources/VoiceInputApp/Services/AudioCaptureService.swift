import AVFoundation
import Foundation

public actor AudioCaptureService: AudioCaptureServing {
    private var recorder: AVAudioRecorder?
    private var currentURL: URL?

    public init() {}

    public func startRecording() async throws {
        guard recorder == nil else {
            throw AudioCaptureError.alreadyRecording
        }

        let directory = FileManager.default.temporaryDirectory
        let url = directory.appendingPathComponent("VoiceInput-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            guard recorder.record() else {
                try? FileManager.default.removeItem(at: url)
                throw AudioCaptureError.failedToStart
            }
            self.recorder = recorder
            self.currentURL = url
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    public func stopRecording() async throws -> RecordedAudio {
        guard let recorder, let currentURL else {
            throw AudioCaptureError.notRecording
        }
        recorder.stop()
        self.recorder = nil
        self.currentURL = nil
        return RecordedAudio(url: currentURL)
    }

    public func cancelRecording() async {
        recorder?.stop()
        if let currentURL {
            try? FileManager.default.removeItem(at: currentURL)
        }
        recorder = nil
        currentURL = nil
    }
}

public enum AudioCaptureError: LocalizedError {
    case alreadyRecording
    case failedToStart
    case notRecording

    public var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            "正在录音中。"
        case .failedToStart:
            "录音无法启动，请检查麦克风权限。"
        case .notRecording:
            "当前没有正在进行的录音。"
        }
    }
}
