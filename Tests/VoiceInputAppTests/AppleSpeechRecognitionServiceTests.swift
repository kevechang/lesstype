import XCTest
@testable import VoiceInputApp

final class AppleSpeechRecognitionServiceTests: XCTestCase {
    func testLiveResultResolverAllowsAudioOnlyResultWhenCaptureExists() {
        let audioURL = URL(fileURLWithPath: "/tmp/live-audio-only.wav")

        let result = LiveRecognitionFinalResultResolver.resolve(
            latestText: "",
            previews: [],
            audioURL: audioURL
        )

        XCTAssertEqual(result, RecognitionResult(finalText: "", previews: [], audioURL: audioURL))
    }

    func testLiveResultResolverFinishesImmediatelyWhenCapturedAudioExists() {
        let audioURL = URL(fileURLWithPath: "/tmp/live-audio-for-asr.wav")

        XCTAssertTrue(LiveRecognitionFinalResultResolver.shouldFinishImmediately(audioURL: audioURL))
    }

    func testLiveResultResolverDoesNotFinishImmediatelyWithoutCapturedAudio() {
        XCTAssertFalse(LiveRecognitionFinalResultResolver.shouldFinishImmediately(audioURL: nil))
    }

    func testLiveResultResolverRejectsEmptyTextWithoutAudio() {
        let result = LiveRecognitionFinalResultResolver.resolve(
            latestText: "",
            previews: [],
            audioURL: nil
        )

        XCTAssertNil(result)
    }
}
