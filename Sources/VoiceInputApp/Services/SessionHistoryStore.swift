import Foundation
import Observation

public enum VoiceSessionHistoryOutcome: String, Codable, Equatable, Sendable {
    case inserted
    case failed
}

public struct VoiceSessionHistoryEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let mode: AppMode
    public let recognizedText: String
    public let outputText: String
    public let outcome: VoiceSessionHistoryOutcome

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        mode: AppMode,
        recognizedText: String,
        outputText: String,
        outcome: VoiceSessionHistoryOutcome
    ) {
        self.id = id
        self.timestamp = timestamp
        self.mode = mode
        self.recognizedText = recognizedText
        self.outputText = outputText
        self.outcome = outcome
    }
}

@Observable
@MainActor
public final class SessionHistoryStore {
    private let limit: Int

    public private(set) var entries: [VoiceSessionHistoryEntry] = []

    public init(limit: Int = 30) {
        self.limit = max(1, limit)
    }

    public func record(_ entry: VoiceSessionHistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > limit {
            entries.removeLast(entries.count - limit)
        }
    }

    public func clear() {
        entries.removeAll()
    }
}
