import Foundation

public protocol NoteStructuringService: Sendable {
    func structure(_ text: String, preferences: Preferences) async throws -> String
}

public struct LocalNoteStructuringService: NoteStructuringService {
    private let postProcessor: TextPostProcessor

    public init(postProcessor: TextPostProcessor = TextPostProcessor()) {
        self.postProcessor = postProcessor
    }

    public func structure(_ text: String, preferences: Preferences) async throws -> String {
        let cleaned = removeFillers(text)
        let parts = splitIntoPoints(cleaned)
        let bullets = parts.prefix(8).enumerated().map { index, part in
            let processed = postProcessor.process(part, preferences: preferences)
            return "\(index + 1). \(processed)"
        }
        return bullets.joined(separator: "\n")
    }

    private func removeFillers(_ input: String) -> String {
        var text = input
        for filler in ["嗯", "呃", "那个"] {
            let escapedFiller = NSRegularExpression.escapedPattern(for: filler)
            text = text.replacingOccurrences(
                of: "(^|\\s)\(escapedFiller)(?=\\s|$)",
                with: "$1",
                options: .regularExpression
            )
        }
        return text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func splitIntoPoints(_ input: String) -> [String] {
        let numberedMarker = "第[一二三四五六七八九十0-9]+(?:(?:个)?(?:问题|点|条)(?:是|就是|：|:)?|(?:是|就是|：|:))"
        let spokenMarkers = [
            "首先(?:是|就是|：|:)?",
            "其次(?:是|就是|：|:)?",
            "接下来(?:是|就是|：|:)?",
            "然后(?:是|就是|：|:)?",
            "接着(?:是|就是|：|:)?",
            "另外(?:是|就是|：|:)?",
            "最后(?:是|就是|：|:)?",
            "还有一点(?:是|就是|：|:)?",
            "还有一个点(?:是|就是|：|:)?",
            "还有一个问题(?:是|就是|：|:)?",
            numberedMarker
        ]
        let markerPattern = "(^|\\s)(?:\(spokenMarkers.joined(separator: "|")))"
        let normalized = input
            .replacingOccurrences(
                of: markerPattern,
                with: "$1|",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "(^|\\|\\s*)\(numberedMarker)",
                with: "$1",
                options: .regularExpression
            )
        return normalized
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
