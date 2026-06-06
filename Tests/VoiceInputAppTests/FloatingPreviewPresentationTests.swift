import XCTest
@testable import VoiceInputApp

final class FloatingPreviewPresentationTests: XCTestCase {
    func testMinimalModeUsesCapsuleForNormalActivity() {
        XCTAssertEqual(
            FloatingPreviewPresentation.style(
                state: .previewing(.ordinary, text: "这是一段正在识别的文本"),
                showsTextPreview: false
            ),
            .capsule
        )
    }

    func testTextModeKeepsFullCardForPreviewText() {
        XCTAssertEqual(
            FloatingPreviewPresentation.style(
                state: .previewing(.ordinary, text: "这是一段需要完整显示的文本"),
                showsTextPreview: true
            ),
            .textCard
        )
    }

    func testErrorsUseFullCardEvenWhenTextPreviewIsDisabled() {
        XCTAssertEqual(
            FloatingPreviewPresentation.style(
                state: .error(message: "需要展示完整错误"),
                showsTextPreview: false
            ),
            .textCard
        )
    }
}
