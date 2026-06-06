import Foundation

public struct TextPostProcessor: Sendable {
    private let phraseCorrection: PhraseCorrectionService

    public init(phraseCorrection: PhraseCorrectionService = PhraseCorrectionService()) {
        self.phraseCorrection = phraseCorrection
    }

    public func process(_ input: String, preferences: Preferences) -> String {
        var text = normalizeWhitespace(input)
        if text.isEmpty {
            return ""
        }

        text = phraseCorrection.apply(text, preferences: preferences)
        text = applyTermCorrections(text, terms: preferences.terms)

        if preferences.mixedLanguageSpacingEnabled {
            text = addMixedLanguageSpacing(text)
        }

        if preferences.chinesePunctuationEnabled {
            text = applyChinesePunctuation(text, commaStyle: preferences.commaStyle)
        } else {
            text = replaceChinesePunctuationWithSpaces(text, commaStyle: preferences.commaStyle)
        }

        return text
    }

    private func normalizeWhitespace(_ input: String) -> String {
        Self.simplifiedChinese(input)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func simplifiedChinese(_ input: String) -> String {
        let mutable = NSMutableString(string: input)
        CFStringTransform(mutable, nil, "Hant-Hans" as CFString, false)
        return mutable as String
    }

    private func applyTermCorrections(_ input: String, terms: [String]) -> String {
        var text = input
        let builtIns = [
            ("swift ui", "SwiftUI"),
            ("mac os", "macOS"),
            ("open ai", "OpenAI"),
            ("api", "API")
        ]
        for (spoken, written) in builtIns {
            text = replaceASCIIToken(spoken, with: written, in: text)
        }
        for term in terms.sorted(by: { $0.count > $1.count }) {
            text = replaceASCIIToken(term.lowercased(), with: term, in: text)
        }
        return text
    }

    private func replaceASCIIToken(_ spoken: String, with written: String, in input: String) -> String {
        let components = spoken.split(whereSeparator: { $0.isWhitespace })
        if components.isEmpty {
            return input
        }

        let patternBody = components
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
            .joined(separator: "\\s+")
        let pattern = "(^|[^A-Za-z0-9])\(patternBody)(?=$|[^A-Za-z0-9])"
        let replacement = "$1" + NSRegularExpression.escapedTemplate(for: written)

        return input.replacingOccurrences(
            of: pattern,
            with: replacement,
            options: [.regularExpression, .caseInsensitive]
        )
    }

    private func addMixedLanguageSpacing(_ input: String) -> String {
        var text = input
        text = text.replacingOccurrences(of: "([\\p{Han}])([A-Za-z0-9])", with: "$1 $2", options: .regularExpression)
        text = text.replacingOccurrences(of: "([A-Za-z0-9])([\\p{Han}])", with: "$1 $2", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return text
    }

    private func applyChinesePunctuation(_ input: String, commaStyle: CommaStyle) -> String {
        var text = input
        if commaStyle != .off {
            text = separateConnectors(text, separator: "，")
        }
        if !hasTerminalPunctuation(text) {
            text += "。"
        }
        return text
    }

    private func replaceChinesePunctuationWithSpaces(_ input: String, commaStyle: CommaStyle) -> String {
        var text = input
        if commaStyle != .off {
            text = separateConnectors(text, separator: "  ")
        }
        text = text.replacingOccurrences(of: "[，。！？；：、,.!?;:]+", with: "  ", options: .regularExpression)
        text = text.replacingOccurrences(of: "[\\t\\n\\r]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: " {3,}", with: "  ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func separateConnectors(_ input: String, separator: String) -> String {
        input.replacingOccurrences(
            of: "([^，。！？?!.\\s])\\s*(然后|但是|所以|接着)",
            with: "$1\(separator)$2",
            options: .regularExpression
        )
    }

    private func hasTerminalPunctuation(_ input: String) -> Bool {
        input.hasSuffix("。")
            || input.hasSuffix("！")
            || input.hasSuffix("？")
            || input.hasSuffix(".")
            || input.hasSuffix("!")
            || input.hasSuffix("?")
    }
}
