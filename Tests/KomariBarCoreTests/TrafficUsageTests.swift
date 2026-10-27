import XCTest
@testable import KomariBarCore

final class TrafficUsageTests: XCTestCase {
    private let now = iso("2026-10-27T12:00:00Z")

    func testUnconfirmedCountersAreNeverPresentedAsMonthlyQuota() {
        let result = TrafficUsage.calculate(snapshot: snapshot(upload: 800, download: 500), settings: TrafficSettings(quotaBytes: 1_000), now: now)
        XCTAssertEqual(result.label, "累计流量")
        XCTAssertEqual(result.usedBytes, 800)
        XCTAssertNil(result.period)
        XCTAssertNil(result.quotaBytes)
        XCTAssertNil(result.remainingBytes)
        XCTAssertNil(result.fractionUsed)
        XCTAssertNotNil(result.configurationIssue)
    }

    func testAccountingUsesWholePeriodCounters() {
        let expectations: [(TrafficAccounting, Double)] = [(.sum, 1_300), (.max, 800), (.min, 500), (.upload, 800), (.download, 500)]
        for (accounting, expected) in expectations {
            let result = TrafficUsage.calculate(snapshot: snapshot(upload: 800, download: 500), settings: configured(accounting: accounting), now: now)
            XCTAssertEqual(result.usedBytes, expected, accounting.rawValue)
        }
    }

    func testMonthlyBoundaryUsesAgentTimeZone() {
        let before = iso("2026-10-14T15:59:59Z")
        let reset = iso("2026-10-14T16:00:00Z")
        let settings = TrafficSettings(monthlyRotationConfirmed: true, resetDay: 15, timeZoneIdentifier: "Asia/Shanghai", quotaBytes: 1_000)
        let previous = TrafficUsage.calculate(snapshot: snapshot(at: before), settings: settings, now: before)
        XCTAssertEqual(previous.period?.start, iso("2026-09-14T16:00:00Z"))
        XCTAssertEqual(previous.period?.end, reset)
        let current = TrafficUsage.calculate(snapshot: snapshot(at: reset), settings: settings, now: reset)
        XCTAssertEqual(current.period?.start, reset)
        XCTAssertEqual(current.period?.end, iso("2026-11-14T16:00:00Z"))
    }

    func testMissingDayThirtyOneRotatesOnNextMonthFirst() {
        let february = iso("2026-02-28T23:59:59Z")
        let settings = configured(resetDay: 31)
        let previous = TrafficUsage.calculate(snapshot: snapshot(at: february), settings: settings, now: february)
        XCTAssertEqual(previous.period?.start, iso("2026-01-31T00:00:00Z"))
        XCTAssertEqual(previous.period?.end, iso("2026-03-01T00:00:00Z"))
        let march = iso("2026-03-01T00:00:00Z")
        let next = TrafficUsage.calculate(snapshot: snapshot(at: march), settings: settings, now: march)
        XCTAssertEqual(next.period?.start, march)
        XCTAssertEqual(next.period?.end, iso("2026-03-31T00:00:00Z"))
    }

    func testLeapDayIsARealResetBoundary() {
        let leap = iso("2028-02-29T00:00:00Z")
        let result = TrafficUsage.calculate(snapshot: snapshot(at: leap), settings: configured(resetDay: 29), now: leap)
        XCTAssertEqual(result.period?.start, leap)
        XCTAssertEqual(result.period?.end, iso("2028-03-29T00:00:00Z"))
    }

    func testYearBoundaryAndExactResetMidnight() {
        let date = iso("2027-01-01T00:00:00Z")
        let result = TrafficUsage.calculate(snapshot: snapshot(at: date), settings: configured(), now: date)
        XCTAssertEqual(result.period?.start, date)
        XCTAssertEqual(result.period?.end, iso("2027-02-01T00:00:00Z"))
    }

    func testLastPeriodSnapshotIsNotShownAsCurrentPeriodUsage() {
        let stale = snapshot(at: iso("2026-09-30T23:59:59Z"), upload: 700, download: 200)
        let result = TrafficUsage.calculate(snapshot: stale, settings: configured(), now: now)
        XCTAssertEqual(result.label, "累计流量")
        XCTAssertNil(result.period)
        XCTAssertNil(result.remainingBytes)
        XCTAssertTrue(result.configurationIssue?.contains("当前账期") == true)
    }

    func testInvalidResetDayAndTimeZoneFallBackToCumulative() {
        for day in [0, 32, -1] {
            let result = TrafficUsage.calculate(snapshot: snapshot(), settings: configured(resetDay: day), now: now)
            XCTAssertNil(result.period)
            XCTAssertEqual(result.label, "累计流量")
            XCTAssertNotNil(result.configurationIssue)
        }
        var settings = configured()
        settings.timeZoneIdentifier = "A/Nonexistent_TimeZone"
        XCTAssertNil(TrafficUsage.calculate(snapshot: snapshot(), settings: settings, now: now).period)
    }

    func testOverageKeepsTrueFractionAndClampsRemainingAtZero() {
        let result = TrafficUsage.calculate(snapshot: snapshot(upload: 1_500, download: 200), settings: configured(), now: now)
        XCTAssertEqual(result.usedBytes, 1_500)
        XCTAssertEqual(result.fractionUsed, 1.5)
        XCTAssertEqual(result.remainingBytes, 0)
    }

    func testNoQuotaOrInvalidQuotaDoesNotInventRemainingAllowance() {
        for quota in [nil, 0, -1, Double.nan, Double.infinity] as [Double?] {
            var settings = configured()
            settings.quotaBytes = quota
            let result = TrafficUsage.calculate(snapshot: snapshot(), settings: settings, now: now)
            XCTAssertEqual(result.label, "本期流量")
            XCTAssertNotNil(result.period)
            XCTAssertNil(result.quotaBytes)
            XCTAssertNil(result.remainingBytes)
            XCTAssertNil(result.fractionUsed)
        }
    }

    func testNegativeAndNonfiniteCountersCannotCreateNegativeUsage() {
        let result = TrafficUsage.calculate(snapshot: snapshot(upload: .nan, download: -50), settings: configured(accounting: .sum), now: now)
        XCTAssertEqual(result.usedBytes, 0)
        XCTAssertEqual(result.remainingBytes, 1_000)
    }

    private func configured(resetDay: Int = 1, accounting: TrafficAccounting = .max) -> TrafficSettings {
        TrafficSettings(monthlyRotationConfirmed: true, resetDay: resetDay, timeZoneIdentifier: "UTC", quotaBytes: 1_000, accounting: accounting)
    }

    private func snapshot(at date: Date? = nil, upload: Double = 200, download: Double = 100) -> ServerSnapshot {
        ServerSnapshot(nodeID: "fixture-node", timestamp: date ?? now, isOnline: true, cpuPercent: 12, memoryUsedBytes: 400, memoryTotalBytes: 2_000, diskUsedBytes: 4_000, diskTotalBytes: 20_000, uploadBytesPerSecond: 3, downloadBytesPerSecond: 4, uploadedBytes: upload, downloadedBytes: download, uptime: 100)
    }
}

private func iso(_ value: String) -> Date {
    ISO8601DateFormatter().date(from: value)!
}
