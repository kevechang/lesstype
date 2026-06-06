import XCTest
@testable import VoiceInputApp

final class NoteStructuringServiceTests: XCTestCase {
    func testRemovesFillerAndBuildsBullets() async throws {
        let service = LocalNoteStructuringService()
        let result = try await service.structure(
            "嗯 我想先做一个轻量的 macOS app 然后它有普通模式 然后还有分点模式",
            preferences: .defaults
        )

        XCTAssertEqual(result, "1. 我想先做一个轻量的 macOS app。\n2. 它有普通模式。\n3. 还有分点模式。")
    }

    func testSplitsSpokenChineseStructureMarkers() async throws {
        let service = LocalNoteStructuringService()
        let result = try await service.structure(
            "首先我想改默认快捷键 其次分点模式要更忠实 第二个问题是本地兜底要识别口语边界 还有一点不要扩写",
            preferences: .defaults
        )

        XCTAssertEqual(
            result,
            "1. 我想改默认快捷键。\n2. 分点模式要更忠实。\n3. 本地兜底要识别口语边界。\n4. 不要扩写。"
        )
    }

    func testDoesNotTreatOrdinalWordsInsideSentenceAsStructureMarkers() async throws {
        let service = LocalNoteStructuringService()
        let result = try await service.structure(
            "第一印象很重要 然后第一个版本先保持简单",
            preferences: .defaults
        )

        XCTAssertEqual(result, "1. 第一印象很重要。\n2. 第一个版本先保持简单。")
    }

    func testDoesNotInventFacts() async throws {
        let service = LocalNoteStructuringService()
        let result = try await service.structure("先本地识别 然后可选云端整理", preferences: .defaults)

        XCTAssertFalse(result.contains("会议"))
        XCTAssertFalse(result.contains("多人"))
    }

    func testPreservesMeaningfulFillerLikeWords() async throws {
        let service = LocalNoteStructuringService()
        let result = try await service.structure("那个项目就是语音输入", preferences: .defaults)

        XCTAssertEqual(result, "1. 那个项目就是语音输入。")
    }

    func testWhitespaceOnlyInputReturnsEmptyString() async throws {
        let service = LocalNoteStructuringService()
        let result = try await service.structure(" \n\t ", preferences: .defaults)

        XCTAssertEqual(result, "")
    }

    func testCapsStructuredOutputAtEightBullets() async throws {
        let service = LocalNoteStructuringService()
        let result = try await service.structure(
            "内容一 然后内容二 然后内容三 然后内容四 然后内容五 然后内容六 然后内容七 然后内容八 然后内容九",
            preferences: .defaults
        )

        XCTAssertEqual(result.split(separator: "\n").count, 8)
        XCTAssertFalse(result.contains("内容九"))
    }
}
