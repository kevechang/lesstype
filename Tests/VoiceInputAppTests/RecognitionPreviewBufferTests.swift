import XCTest
@testable import VoiceInputApp

final class RecognitionPreviewBufferTests: XCTestCase {
    func testKeepsOnlyMostRecentPreviews() {
        var buffer = RecognitionPreviewBuffer(limit: 3)

        buffer.append("一")
        buffer.append("二")
        buffer.append("三")
        buffer.append("四")

        XCTAssertEqual(buffer.values, ["二", "三", "四"])
    }
}
