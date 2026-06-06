import XCTest
@testable import VoiceInputApp

final class TextPostProcessorTests: XCTestCase {
    func testAddsChineseCommaConservatively() {
        let processor = TextPostProcessor()
        var preferences = Preferences.defaults
        preferences.commaStyle = .conservative

        let result = processor.process("我想先做语音输入 然后再做分点记录", preferences: preferences)

        XCTAssertEqual(result, "我想先做语音输入，然后再做分点记录。")
    }

    func testKeepsMixedEnglishReadable() {
        let processor = TextPostProcessor()
        var preferences = Preferences.defaults
        preferences.terms = ["SwiftUI", "macOS", "API"]

        let result = processor.process("我想用 swift ui 做一个 mac os app 然后接 api", preferences: preferences)

        XCTAssertEqual(result, "我想用 SwiftUI 做一个 macOS app，然后接 API。")
    }

    func testAppliesHighFrequencyPhraseCorrectionsBeforeFormatting() {
        let processor = TextPostProcessor()
        var preferences = Preferences.defaults
        preferences.phraseCorrectionsText = """
        语音输入 App = 语音输入爱屁屁, 语音输入app
        OpenAI 兼容接口 = open ai 兼容接口
        """

        let result = processor.process("我想做语音输入爱屁屁 然后接 open ai 兼容接口", preferences: preferences)

        XCTAssertEqual(result, "我想做语音输入 App，然后接 OpenAI 兼容接口。")
    }

    func testHighFrequencyPhraseCorrectionsIgnoreCommentsAndLimitVariants() {
        let processor = TextPostProcessor()
        var preferences = Preferences.defaults
        preferences.phraseCorrectionsText = """
        # 每行格式：正确词组 = 误识别1, 误识别2
        语音识别 = 语音十倍, 语音识别
        无效规则 =
        """

        let result = processor.process("这个语音十倍要更准", preferences: preferences)

        XCTAssertEqual(result, "这个语音识别要更准。")
    }

    func testCommaSeparatedHighFrequencyWordsAreIndependentEntries() {
        let processor = TextPostProcessor()
        var preferences = Preferences.defaults
        preferences.phraseCorrectionsText = "claude, 猪咪, 巧克力可乐"

        let result = processor.process("我想让克劳德识别猪咪", preferences: preferences)

        XCTAssertEqual(result, "我想让 Claude 识别猪咪。")
    }

    func testStructuredHighFrequencyPhraseEntryAppliesCustomVariants() {
        let processor = TextPostProcessor()
        var preferences = Preferences.defaults
        preferences.phraseCorrectionEntries = [
            PhraseCorrectionEntry(phrase: "Claude", variants: ["克劳德", "cloud"])
        ]

        let result = processor.process("我想用 cloud 改提示词", preferences: preferences)

        XCTAssertEqual(result, "我想用 Claude 改提示词。")
    }

    func testConvertsTraditionalChineseToSimplifiedChinese() {
        let processor = TextPostProcessor()

        let result = processor.process("這個語音識別軟體輸出繁體中文", preferences: .defaults)

        XCTAssertEqual(result, "这个语音识别软体输出繁体中文。")
    }

    func testAddsChineseCommaWithoutRequiringSpacesAroundConnector() {
        let processor = TextPostProcessor()
        var preferences = Preferences.defaults
        preferences.commaStyle = .conservative

        let result = processor.process("我先记录想法然后整理重点", preferences: preferences)

        XCTAssertEqual(result, "我先记录想法，然后整理重点。")
    }

    func testCommaOffDoesNotInsertComma() {
        let processor = TextPostProcessor()
        var preferences = Preferences.defaults
        preferences.commaStyle = .off

        let result = processor.process("我先记录想法 然后整理", preferences: preferences)

        XCTAssertEqual(result, "我先记录想法 然后整理。")
    }

    func testPunctuationOffUsesSpacesWhereChinesePunctuationWouldAppear() {
        let processor = TextPostProcessor()
        var preferences = Preferences.defaults
        preferences.chinesePunctuationEnabled = false

        let result = processor.process("我先记录想法然后整理重点", preferences: preferences)

        XCTAssertEqual(result, "我先记录想法  然后整理重点")
    }

    func testPunctuationOffReplacesRecognizedPunctuationWithSpaces() {
        let processor = TextPostProcessor()
        var preferences = Preferences.defaults
        preferences.chinesePunctuationEnabled = false

        let result = processor.process("我先记录想法，然后整理重点。", preferences: preferences)

        XCTAssertEqual(result, "我先记录想法  然后整理重点")
    }

    func testDoesNotReplaceAcronymInsideLongerEnglishWords() {
        let processor = TextPostProcessor()

        let result = processor.process("rapid capital api", preferences: .defaults)

        XCTAssertEqual(result, "rapid capital API。")
    }

    func testDoesNotAppendChinesePeriodAfterAsciiTerminalPunctuation() {
        let processor = TextPostProcessor()

        let result = processor.process("我已经记录好了.", preferences: .defaults)

        XCTAssertEqual(result, "我已经记录好了.")
    }

    func testWhitespaceOnlyInputReturnsEmptyString() {
        let processor = TextPostProcessor()

        let result = processor.process(" \n\t ", preferences: .defaults)

        XCTAssertEqual(result, "")
    }
}
