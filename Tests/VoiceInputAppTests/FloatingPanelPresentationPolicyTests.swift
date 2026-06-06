import XCTest
@testable import VoiceInputApp

final class FloatingPanelPresentationPolicyTests: XCTestCase {
    func testTextModeShowsLivePreviewStates() {
        XCTAssertTrue(FloatingPanelPresentationPolicy.shouldShow(.previewing(.ordinary, text: "第一句"), mode: .text))
        XCTAssertTrue(FloatingPanelPresentationPolicy.shouldShow(.recognizing(.ordinary), mode: .text))
        XCTAssertTrue(FloatingPanelPresentationPolicy.shouldShow(.structuring(text: "第一句"), mode: .text))
        XCTAssertTrue(FloatingPanelPresentationPolicy.shouldShow(.inserting(text: "第一句"), mode: .text))
    }

    func testHiddenModeHidesNonErrorStates() {
        XCTAssertFalse(FloatingPanelPresentationPolicy.shouldShow(.previewing(.ordinary, text: "第一句"), mode: .hidden))
        XCTAssertFalse(FloatingPanelPresentationPolicy.shouldShow(.recognizing(.ordinary), mode: .hidden))
        XCTAssertTrue(FloatingPanelPresentationPolicy.shouldShow(.error(message: "需要处理"), mode: .hidden))
    }

    func testMinimalModeShowsActivityWithoutTextPreview() {
        XCTAssertTrue(FloatingPanelPresentationPolicy.shouldShow(.previewing(.ordinary, text: "第一句"), mode: .minimal))
        XCTAssertFalse(FloatingPanelPresentationPolicy.shouldUseTextPreview(mode: .minimal))
        XCTAssertTrue(FloatingPanelPresentationPolicy.shouldUseTextPreview(mode: .text))
    }

    func testCompletedStateHidesPanelInsteadOfStayingVisible() {
        XCTAssertFalse(FloatingPanelPresentationPolicy.shouldShow(.completed(text: "完成文本"), mode: .text))
    }

    func testErrorStateStillShowsPanel() {
        XCTAssertTrue(FloatingPanelPresentationPolicy.shouldShow(.error(message: "需要处理"), mode: .text))
    }
}
