import XCTest
@testable import VoiceInputApp

@MainActor
final class TextInsertionServiceTests: XCTestCase {
    func testInsertTypesTextWithoutUsingPasteboardPath() async throws {
        let typer = RecordingTextTyper()
        let service = TextInsertionService(
            accessibilityPermission: { true },
            textTyper: typer
        )

        try await service.insert("直接输入到当前对话框")

        XCTAssertEqual(typer.typedTexts, ["直接输入到当前对话框"])
    }

    func testInsertDoesNotTypeWhenAccessibilityPermissionMissing() async {
        let typer = RecordingTextTyper()
        let service = TextInsertionService(
            accessibilityPermission: { false },
            textTyper: typer
        )

        do {
            try await service.insert("不会进剪贴板")
            XCTFail("Expected permission error")
        } catch TextInsertionError.accessibilityPermissionMissing {
            XCTAssertTrue(typer.typedTexts.isEmpty)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

@MainActor
private final class RecordingTextTyper: TextTyping {
    private(set) var typedTexts: [String] = []

    func type(_ text: String) async throws {
        typedTexts.append(text)
    }
}
