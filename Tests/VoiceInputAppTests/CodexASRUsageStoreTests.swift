import XCTest
@testable import VoiceInputApp

final class CodexASRUsageStoreTests: XCTestCase {
    func testLedgerSummarizesTodayLastSevenDaysAndOutcomes() {
        var ledger = CodexASRUsageLedger()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        ledger.record(.success, at: now)
        ledger.record(.quotaLimited, at: now.addingTimeInterval(-60))
        ledger.record(.failure, at: now.addingTimeInterval(-86_400 * 3))
        ledger.record(.success, at: now.addingTimeInterval(-86_400 * 8))

        let snapshot = ledger.snapshot(now: now, calendar: .gregorianUTC)

        XCTAssertEqual(snapshot.totalCount, 4)
        XCTAssertEqual(snapshot.successCount, 2)
        XCTAssertEqual(snapshot.failureCount, 1)
        XCTAssertEqual(snapshot.quotaLimitedCount, 1)
        XCTAssertEqual(snapshot.todayCount, 2)
        XCTAssertEqual(snapshot.lastSevenDaysCount, 3)
        XCTAssertEqual(snapshot.lastOutcome, .success)
    }

    func testQuotaLimitedSnapshotUsesGentleReminder() {
        var ledger = CodexASRUsageLedger()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        ledger.record(.quotaLimited, at: now)

        let snapshot = ledger.snapshot(now: now, calendar: .gregorianUTC)

        XCTAssertEqual(snapshot.lastStatusText, "上次 Codex ASR 暂时不可用，已改用 Apple 识别。可能是账号额度或频率限制，稍后再试即可。")
        XCTAssertTrue(snapshot.isLastQuotaLimited)
    }
}

private extension Calendar {
    static var gregorianUTC: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
