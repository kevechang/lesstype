import XCTest
@testable import VoiceInputApp

final class ServerSentEventTextParserTests: XCTestCase {
    func testParsesOpenAIChatDeltaText() throws {
        let parser = ServerSentEventTextParser()
        let text = try parser.parse(
            """
            data: {"choices":[{"delta":{"content":"你好"}}]}

            data: {"choices":[{"delta":{"content":"世界"}}]}

            data: [DONE]

            """.data(using: .utf8)!
        )

        XCTAssertEqual(text, "你好世界")
    }

    func testParsesOpenAIResponsesOutputTextDelta() throws {
        let parser = ServerSentEventTextParser()
        let text = try parser.parse(
            """
            event: response.output_text.delta
            data: {"delta":"第一段"}

            event: response.output_text.delta
            data: {"delta":"第二段"}

            """.data(using: .utf8)!
        )

        XCTAssertEqual(text, "第一段第二段")
    }

    func testParsesAnthropicContentBlockDelta() throws {
        let parser = ServerSentEventTextParser()
        let text = try parser.parse(
            """
            event: content_block_delta
            data: {"delta":{"type":"text_delta","text":"Claude"}}

            """.data(using: .utf8)!
        )

        XCTAssertEqual(text, "Claude")
    }
}
