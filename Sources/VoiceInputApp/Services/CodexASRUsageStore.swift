import Foundation

public enum CodexASRUsageOutcome: String, Codable, Equatable, Sendable {
    case success
    case timeout
    case failure
    case quotaLimited
}

public struct CodexASRUsageEvent: Codable, Equatable, Sendable {
    public let outcome: CodexASRUsageOutcome
    public let timestamp: Date

    public init(outcome: CodexASRUsageOutcome, timestamp: Date) {
        self.outcome = outcome
        self.timestamp = timestamp
    }
}

public struct CodexASRUsageSnapshot: Equatable, Sendable {
    public let totalCount: Int
    public let successCount: Int
    public let failureCount: Int
    public let timeoutCount: Int
    public let quotaLimitedCount: Int
    public let todayCount: Int
    public let lastSevenDaysCount: Int
    public let lastOutcome: CodexASRUsageOutcome?
    public let lastStatusText: String

    public var isLastQuotaLimited: Bool {
        lastOutcome == .quotaLimited
    }

    public var summaryText: String {
        "今日 \(todayCount) 次｜近 7 天 \(lastSevenDaysCount) 次｜总计 \(totalCount) 次"
    }

    public var detailText: String {
        "成功 \(successCount) 次，失败 \(failureCount) 次，超时 \(timeoutCount) 次，受限 \(quotaLimitedCount) 次"
    }

    public static let empty = CodexASRUsageSnapshot(
        totalCount: 0,
        successCount: 0,
        failureCount: 0,
        timeoutCount: 0,
        quotaLimitedCount: 0,
        todayCount: 0,
        lastSevenDaysCount: 0,
        lastOutcome: nil,
        lastStatusText: "尚未调用"
    )
}

public struct CodexASRUsageLedger: Codable, Equatable, Sendable {
    private var events: [CodexASRUsageEvent] = []

    public init(events: [CodexASRUsageEvent] = []) {
        self.events = events
    }

    public mutating func record(_ outcome: CodexASRUsageOutcome, at date: Date = Date()) {
        events.append(CodexASRUsageEvent(outcome: outcome, timestamp: date))
        if events.count > 500 {
            events.removeFirst(events.count - 500)
        }
    }

    public func snapshot(now: Date = Date(), calendar: Calendar = .current) -> CodexASRUsageSnapshot {
        guard !events.isEmpty else {
            return .empty
        }

        let todayStart = calendar.startOfDay(for: now)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now
        let sevenDaysStart = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
        let lastEvent = events.max { $0.timestamp < $1.timestamp }

        return CodexASRUsageSnapshot(
            totalCount: events.count,
            successCount: events.count { $0.outcome == .success },
            failureCount: events.count { $0.outcome == .failure },
            timeoutCount: events.count { $0.outcome == .timeout },
            quotaLimitedCount: events.count { $0.outcome == .quotaLimited },
            todayCount: events.count { $0.timestamp >= todayStart && $0.timestamp < tomorrowStart },
            lastSevenDaysCount: events.count { $0.timestamp >= sevenDaysStart && $0.timestamp < tomorrowStart },
            lastOutcome: lastEvent?.outcome,
            lastStatusText: Self.statusText(for: lastEvent?.outcome)
        )
    }

    private static func statusText(for outcome: CodexASRUsageOutcome?) -> String {
        switch outcome {
        case .success:
            "上次 Codex ASR 调用成功。"
        case .timeout:
            "上次 Codex ASR 等待较久，已改用 Apple 识别。"
        case .failure:
            "上次 Codex ASR 暂时不可用，已改用 Apple 识别。"
        case .quotaLimited:
            "上次 Codex ASR 暂时不可用，已改用 Apple 识别。可能是账号额度或频率限制，稍后再试即可。"
        case nil:
            "尚未调用"
        }
    }
}

@MainActor
public final class CodexASRUsageStore {
    private static let storageKey = "codexASRUsageLedger"

    private let defaults: UserDefaults
    private var ledger: CodexASRUsageLedger

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(CodexASRUsageLedger.self, from: data) {
            ledger = decoded
        } else {
            ledger = CodexASRUsageLedger()
        }
    }

    public var snapshot: CodexASRUsageSnapshot {
        ledger.snapshot()
    }

    @discardableResult
    public func record(_ outcome: CodexASRUsageOutcome, at date: Date = Date()) -> CodexASRUsageSnapshot {
        ledger.record(outcome, at: date)
        persist()
        return ledger.snapshot(now: date)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(ledger) else {
            return
        }
        defaults.set(data, forKey: Self.storageKey)
    }
}
