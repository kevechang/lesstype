import AppKit
import SwiftUI
import XCTest
@testable import VoiceInputApp

@MainActor
final class FloatingPreviewViewLayoutTests: XCTestCase {
    func testMinimalCapsuleUsesCompactFittingSize() {
        let view = FloatingPreviewView(
            state: .previewing(.ordinary, text: ""),
            stop: {},
            cancel: {},
            showsTextPreview: false,
            actionHint: "Space 完成   Esc 放弃"
        )

        let size = NSHostingView(rootView: view).fittingSize

        XCTAssertEqual(size.width, 252, accuracy: 0.5)
        XCTAssertEqual(size.height, 40, accuracy: 0.5)
    }

    func testTextCardGrowsVerticallyForLongPreviewText() {
        let longText = Array(repeating: "这是一段用于预览的长文本", count: 12).joined(separator: " ")
        let view = FloatingPreviewView(
            state: .previewing(.ordinary, text: longText),
            stop: {},
            cancel: {},
            showsTextPreview: true,
            actionHint: "Space 完成   Esc 放弃"
        )

        let size = NSHostingView(rootView: view).fittingSize

        XCTAssertEqual(size.width, 420, accuracy: 0.5)
        XCTAssertGreaterThan(size.height, 80)
    }
}
