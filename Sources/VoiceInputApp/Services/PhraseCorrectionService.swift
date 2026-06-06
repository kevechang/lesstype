import Foundation

public struct PhraseCorrectionService: Sendable {
    public struct Rule: Equatable, Sendable {
        public let target: String
        public let variants: [String]

        public init(target: String, variants: [String]) {
            self.target = target
            self.variants = variants
        }
    }

    public static let maxRules = 200
    public static let maxVariantsPerRule = 5

    public init() {}

    public func apply(_ input: String, preferences: Preferences) -> String {
        apply(input, rules: rules(from: preferences))
    }

    public func apply(_ input: String, rulesText: String?) -> String {
        apply(input, rules: parseRules(rulesText))
    }

    public func entries(from preferences: Preferences) -> [PhraseCorrectionEntry] {
        let structured = preferences.phraseCorrectionEntries ?? []
        let legacy = parseEntries(preferences.phraseCorrectionsText)
        return normalizeEntries(structured + legacy)
    }

    public func promptGlossary(from preferences: Preferences) -> String? {
        promptGlossary(from: rules(from: preferences))
    }

    public func promptGlossary(from rulesText: String?) -> String? {
        promptGlossary(from: parseRules(rulesText))
    }

    public func parseRules(_ rulesText: String?) -> [Rule] {
        parseEntries(rulesText).map { entry in
            Rule(target: entry.phrase, variants: entry.variants)
        }
    }

    private func apply(_ input: String, rules: [Rule]) -> String {
        guard !rules.isEmpty else {
            return input
        }

        var text = input
        for rule in rules.sorted(by: { $0.target.count > $1.target.count }) {
            for variant in rule.variants.sorted(by: { $0.count > $1.count }) {
                text = replace(variant, with: rule.target, in: text)
            }
        }
        return text
    }

    private func promptGlossary(from rules: [Rule]) -> String? {
        guard !rules.isEmpty else {
            return nil
        }

        let lines = rules.map { rule in
            if rule.variants.isEmpty {
                return "- \(rule.target)"
            }
            return "- \(rule.target)：常见误识别为 \(rule.variants.joined(separator: "、"))"
        }
        .joined(separator: "\n")

        return """

        高频词组：
        请优先保持以下写法；如果原文中出现常见误识别，请按上下文纠正为对应词组，不要因此扩写或改变原意。
        \(lines)
        """
    }

    private func rules(from preferences: Preferences) -> [Rule] {
        entries(from: preferences).map { entry in
            Rule(target: entry.phrase, variants: entry.variants)
        }
    }

    private func parseEntries(_ rulesText: String?) -> [PhraseCorrectionEntry] {
        guard let rulesText else {
            return []
        }

        var entries: [PhraseCorrectionEntry] = []
        for rawLine in rulesText.components(separatedBy: .newlines) {
            guard entries.count < Self.maxRules else {
                break
            }

            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else {
                continue
            }

            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 1 {
                entries.append(contentsOf: commaSeparatedEntries(from: line, remainingLimit: Self.maxRules - entries.count))
                continue
            }

            let rawTarget = String(parts.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let target = canonicalPhrase(rawTarget)
            guard !target.isEmpty else {
                continue
            }
            let variantText = parts.count > 1 ? String(parts[1]) : ""
            let explicitVariants = variantText
                .replacingOccurrences(of: "，", with: ",")
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0 != target }
                .prefix(Self.maxVariantsPerRule)
            let variants = mergedVariants(for: target, rawPhrase: rawTarget, explicitVariants: Array(explicitVariants))

            entries.append(PhraseCorrectionEntry(phrase: target, variants: variants))
        }
        return normalizeEntries(entries)
    }

    private func commaSeparatedEntries(from line: String, remainingLimit: Int) -> [PhraseCorrectionEntry] {
        line
            .replacingOccurrences(of: "，", with: ",")
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(remainingLimit)
            .map { rawPhrase in
                let phrase = canonicalPhrase(rawPhrase)
                return PhraseCorrectionEntry(
                    phrase: phrase,
                    variants: mergedVariants(for: phrase, rawPhrase: rawPhrase, explicitVariants: [])
                )
            }
    }

    private func normalizeEntries(_ entries: [PhraseCorrectionEntry]) -> [PhraseCorrectionEntry] {
        var result: [PhraseCorrectionEntry] = []
        var seenPhrases: Set<String> = []

        for entry in entries {
            guard result.count < Self.maxRules else {
                break
            }
            let phrase = canonicalPhrase(entry.phrase)
            guard !phrase.isEmpty else {
                continue
            }
            let key = normalizedKey(phrase)
            guard !seenPhrases.contains(key) else {
                continue
            }
            seenPhrases.insert(key)
            let variants = mergedVariants(for: phrase, rawPhrase: entry.phrase, explicitVariants: entry.variants)
            result.append(PhraseCorrectionEntry(id: entry.id, phrase: phrase, variants: variants))
        }
        return result
    }

    private func mergedVariants(for phrase: String, rawPhrase: String, explicitVariants: [String]) -> [String] {
        var variants: [String] = []
        for variant in automaticVariants(for: phrase, rawPhrase: rawPhrase) + explicitVariants {
            let trimmed = variant.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != phrase else {
                continue
            }
            if !variants.contains(where: { normalizedKey($0) == normalizedKey(trimmed) }) {
                variants.append(trimmed)
            }
            if variants.count >= Self.maxVariantsPerRule {
                break
            }
        }
        return variants
    }

    private func canonicalPhrase(_ rawPhrase: String) -> String {
        let trimmed = rawPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = normalizedKey(trimmed)
        switch key {
        case "claude":
            return "Claude"
        case "openai":
            return "OpenAI"
        case "swiftui":
            return "SwiftUI"
        case "chatgpt":
            return "ChatGPT"
        default:
            return trimmed
        }
    }

    private func automaticVariants(for phrase: String, rawPhrase: String) -> [String] {
        var variants: [String] = []
        let trimmedRaw = rawPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedRaw.isEmpty, trimmedRaw != phrase {
            variants.append(trimmedRaw)
        }

        switch normalizedKey(phrase) {
        case "claude":
            variants.append(contentsOf: ["claude", "克劳德", "cloud"])
        case "openai":
            variants.append(contentsOf: ["open ai", "欧喷 ai"])
        case "swiftui":
            variants.append(contentsOf: ["swift ui", "swift u i"])
        case "chatgpt":
            variants.append(contentsOf: ["chat gpt", "chat gp t"])
        default:
            break
        }
        return variants
    }

    private func normalizedKey(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }

    private func replace(_ variant: String, with target: String, in input: String) -> String {
        let components = variant.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !components.isEmpty else {
            return input
        }

        let patternBody = components
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "\\s+")
        let replacement = NSRegularExpression.escapedTemplate(for: target)

        if isASCIITokenPhrase(variant) {
            let pattern = "(^|[^A-Za-z0-9])\(patternBody)(?=$|[^A-Za-z0-9])"
            return input.replacingOccurrences(
                of: pattern,
                with: "$1" + replacement,
                options: [.regularExpression, .caseInsensitive]
            )
        }

        return input.replacingOccurrences(
            of: patternBody,
            with: replacement,
            options: [.regularExpression, .caseInsensitive]
        )
    }

    private func isASCIITokenPhrase(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) || CharacterSet.whitespaces.contains(scalar)
        }
    }
}
