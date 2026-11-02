import Foundation
import XCTest
@testable import KomariBarCore

final class TrafficCalibrationTests: XCTestCase {
    private let anchorTime = calibrationDate("2026-10-27T12:00:00Z")
    private let agentUpload = 100_000_000.0
    private let agentDownload = 200_000_000.0
    private let providerUpload = 4_000_000_000.0
    private let providerDownload = 6_000_000_000.0
    private let quota = 20_000_000_000.0

    func testSumAddsAgentDeltasAndPreservesProviderRoundingOffset() throws {
        var settings = configured(accounting: .sum)
        let providerUsed = 10_012_000_000.0
        settings.calibration = try calibration(settings: settings, used: providerUsed)

        let usage = TrafficUsage.calculate(
            snapshot: snapshot(at: anchorTime.addingTimeInterval(60), upload: 150_000_000, download: 270_000_000),
            settings: settings,
            now: anchorTime.addingTimeInterval(60)
        )

        XCTAssertEqual(usage.label, "本期估算")
        XCTAssertEqual(usage.uploadedBytes, 4_050_000_000)
        XCTAssertEqual(usage.downloadedBytes, 6_070_000_000)
        XCTAssertEqual(usage.usedBytes, providerUsed + 120_000_000)
        XCTAssertEqual(usage.quotaBytes, quota)
        XCTAssertEqual(usage.remainingBytes, quota - usage.usedBytes)
        XCTAssertEqual(usage.fractionUsed, usage.usedBytes / quota)
        XCTAssertEqual(usage.appliedCalibration, settings.calibration)
    }

    func testMaxUsesEstimatedDirectionTotalsWhenTheLargerDirectionChanges() throws {
        var settings = configured(accounting: .max)
        settings.calibration = try calibration(settings: settings, used: providerDownload)
        let later = anchorTime.addingTimeInterval(60)

        let usage = TrafficUsage.calculate(
            snapshot: snapshot(at: later, upload: agentUpload + 3_000_000_000, download: agentDownload + 100_000_000),
            settings: settings, now: later
        )

        XCTAssertEqual(usage.uploadedBytes, 7_000_000_000)
        XCTAssertEqual(usage.downloadedBytes, 6_100_000_000)
        XCTAssertEqual(usage.usedBytes, 7_000_000_000)
        XCTAssertEqual(usage.label, "本期估算")
        XCTAssertNotNil(usage.appliedCalibration)
    }

    func testMinUsesEstimatedDirectionTotalsWhenTheSmallerDirectionChanges() throws {
        var settings = configured(accounting: .min)
        settings.calibration = try calibration(settings: settings, used: providerUpload)
        let later = anchorTime.addingTimeInterval(60)

        let usage = TrafficUsage.calculate(
            snapshot: snapshot(at: later, upload: agentUpload + 3_000_000_000, download: agentDownload + 100_000_000),
            settings: settings, now: later
        )

        XCTAssertEqual(usage.uploadedBytes, 7_000_000_000)
        XCTAssertEqual(usage.downloadedBytes, 6_100_000_000)
        XCTAssertEqual(usage.usedBytes, 6_100_000_000)
        XCTAssertEqual(usage.label, "本期估算")
        XCTAssertNotNil(usage.appliedCalibration)
    }

    func testUploadAndDownloadModesCountOnlyTheirSelectedDirection() throws {
        let cases: [(TrafficAccounting, Double, Double)] = [
            (.upload, providerUpload, 4_100_000_000),
            (.download, providerDownload, 6_300_000_000)
        ]
        let later = anchorTime.addingTimeInterval(60)
        for (accounting, baseline, expected) in cases {
            var settings = configured(accounting: accounting)
            settings.calibration = try calibration(settings: settings, used: baseline)
            let usage = TrafficUsage.calculate(
                snapshot: snapshot(at: later, upload: agentUpload + 100_000_000, download: agentDownload + 300_000_000),
                settings: settings, now: later
            )

            XCTAssertEqual(usage.usedBytes, expected, accounting.rawValue)
            XCTAssertEqual(usage.uploadedBytes, 4_100_000_000, accounting.rawValue)
            XCTAssertEqual(usage.downloadedBytes, 6_300_000_000, accounting.rawValue)
            XCTAssertNotNil(usage.appliedCalibration, accounting.rawValue)
        }
    }

    func testZeroProviderBaselineAndZeroAgentDeltaAreValid() throws {
        var settings = configured(accounting: .sum)
        settings.calibration = try TrafficCalibration.create(
            snapshot: snapshot(), settings: settings,
            providerUsedBytes: 0, providerUploadedBytes: 0, providerDownloadedBytes: 0,
            observedAt: anchorTime
        )

        let usage = TrafficUsage.calculate(snapshot: snapshot(), settings: settings, now: anchorTime)

        XCTAssertEqual(usage.label, "本期估算")
        XCTAssertEqual(usage.uploadedBytes, 0)
        XCTAssertEqual(usage.downloadedBytes, 0)
        XCTAssertEqual(usage.usedBytes, 0)
        XCTAssertEqual(usage.remainingBytes, quota)
        XCTAssertEqual(usage.fractionUsed, 0)
        XCTAssertNotNil(usage.appliedCalibration)
    }

    func testCountersBelowEitherAnchorDisableTheEstimateAndBudget() throws {
        var settings = configured(accounting: .sum)
        settings.calibration = try calibration(settings: settings, used: providerUpload + providerDownload)
        let later = anchorTime.addingTimeInterval(60)
        for (upload, download) in [(agentUpload - 1, agentDownload + 1), (agentUpload + 1, agentDownload - 1)] {
            let usage = TrafficUsage.calculate(
                snapshot: snapshot(at: later, upload: upload, download: download), settings: settings, now: later
            )
            assertRecordedWithoutBudget(usage)
            XCTAssertEqual(usage.uploadedBytes, upload)
            XCTAssertEqual(usage.downloadedBytes, download)
        }
    }

    func testSnapshotBeforeAnchorCannotApplyCalibration() throws {
        var settings = configured(accounting: .sum)
        settings.calibration = try calibration(settings: settings, used: providerUpload + providerDownload)
        let earlier = anchorTime.addingTimeInterval(-1)

        let usage = TrafficUsage.calculate(
            snapshot: snapshot(at: earlier, upload: agentUpload + 1, download: agentDownload + 1),
            settings: settings, now: anchorTime
        )

        assertRecordedWithoutBudget(usage)
    }

    func testSnapshotFromAnotherNodeCannotApplyCalibration() throws {
        var settings = configured(accounting: .sum)
        settings.calibration = try calibration(settings: settings, used: providerUpload + providerDownload)

        let usage = TrafficUsage.calculate(
            snapshot: snapshot(nodeID: "another-fixture-node"), settings: settings, now: anchorTime
        )

        assertRecordedWithoutBudget(usage)
        XCTAssertEqual(usage.usedBytes, agentUpload + agentDownload)
    }

    func testUnknownStatisticsStartCanBeCalibratedWithoutInventingHistory() throws {
        var settings = configured(accounting: .sum)
        settings.statisticsStartedAt = nil
        settings.calibration = try calibration(settings: settings, used: providerUpload + providerDownload)

        let usage = TrafficUsage.calculate(snapshot: snapshot(), settings: settings, now: anchorTime)

        XCTAssertNil(settings.statisticsStartedAt)
        XCTAssertNil(settings.calibration?.statisticsStartedAt)
        XCTAssertEqual(usage.label, "本期估算")
        XCTAssertEqual(usage.usedBytes, providerUpload + providerDownload)
        XCTAssertEqual(usage.remainingBytes, quota - usage.usedBytes)
        XCTAssertEqual(usage.appliedCalibration, settings.calibration)
    }

    func testChangingAnyCalibrationFingerprintSettingDisablesEstimate() throws {
        var original = configured(accounting: .sum)
        original.calibration = try calibration(settings: original, used: providerUpload + providerDownload)
        let changes: [(inout TrafficSettings) -> Void] = [
            { $0.resetDay = 11 },
            { $0.timeZoneIdentifier = "Asia/Shanghai" },
            { $0.accounting = .max },
            { $0.statisticsStartedAt = calibrationDate("2026-10-21T00:00:00Z") }
        ]

        for change in changes {
            var settings = original
            change(&settings)
            let usage = TrafficUsage.calculate(snapshot: snapshot(), settings: settings, now: anchorTime)
            assertRecordedWithoutBudget(usage)
        }
    }

    func testQuotaChangeKeepsCalibrationAndRecalculatesBudget() throws {
        var settings = configured(accounting: .sum)
        settings.calibration = try calibration(settings: settings, used: providerUpload + providerDownload)
        settings.quotaBytes = 30_000_000_000

        let usage = TrafficUsage.calculate(snapshot: snapshot(), settings: settings, now: anchorTime)

        XCTAssertEqual(usage.label, "本期估算")
        XCTAssertEqual(usage.usedBytes, 10_000_000_000)
        XCTAssertEqual(usage.quotaBytes, 30_000_000_000)
        XCTAssertEqual(usage.remainingBytes, 20_000_000_000)
        XCTAssertEqual(usage.fractionUsed, 1.0 / 3)
        XCTAssertEqual(usage.appliedCalibration, settings.calibration)
    }

    func testCalibrationExpiresAtNextResetAndFullPeriodBudgetResumes() throws {
        var settings = configured(accounting: .sum)
        settings.calibration = try calibration(settings: settings, used: providerUpload + providerDownload)
        let reset = calibrationDate("2026-11-10T00:00:00Z")

        let usage = TrafficUsage.calculate(
            snapshot: snapshot(at: reset, upload: 20, download: 10), settings: settings, now: reset
        )

        XCTAssertEqual(usage.label, "本期流量")
        XCTAssertEqual(usage.period?.start, reset)
        XCTAssertEqual(usage.usedBytes, 30)
        XCTAssertEqual(usage.quotaBytes, quota)
        XCTAssertEqual(usage.remainingBytes, quota - 30)
        XCTAssertNil(usage.appliedCalibration)
        XCTAssertNil(usage.configurationIssue)
    }

    func testCounterResetLatchesAndLaterGrowthCannotReviveCalibration() throws {
        var settings = configured(accounting: .sum)
        var value = try calibration(settings: settings, used: providerUpload + providerDownload)
        XCTAssertNil(value.invalidatedAt)
        let reset = snapshot(at: anchorTime.addingTimeInterval(60), upload: agentUpload - 1)
        XCTAssertTrue(value.invalidateIfCountersRegressed(snapshot: reset))
        XCTAssertEqual(value.invalidatedAt, reset.timestamp)

        let grown = snapshot(at: anchorTime.addingTimeInterval(120), upload: agentUpload + 50, download: agentDownload + 50)
        XCTAssertFalse(value.invalidateIfCountersRegressed(snapshot: grown, previousSnapshot: reset))
        XCTAssertEqual(value.invalidatedAt, reset.timestamp)
        settings.calibration = value

        assertRecordedWithoutBudget(TrafficUsage.calculate(snapshot: grown, settings: settings, now: grown.timestamp))
    }

    func testInvalidationMarkerSurvivesSettingsJSONRoundTrip() throws {
        var settings = configured(accounting: .sum)
        var value = try calibration(settings: settings, used: providerUpload + providerDownload)
        let reset = snapshot(at: anchorTime.addingTimeInterval(60), download: agentDownload - 1)
        XCTAssertTrue(value.invalidateIfCountersRegressed(snapshot: reset))
        settings.calibration = value

        let restored = try JSONDecoder().decode(TrafficSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored.calibration?.invalidatedAt, reset.timestamp)
        XCTAssertEqual(restored, settings)
        let grown = snapshot(at: anchorTime.addingTimeInterval(120), upload: agentUpload + 50, download: agentDownload + 50)
        assertRecordedWithoutBudget(TrafficUsage.calculate(snapshot: grown, settings: restored, now: grown.timestamp))
    }

    func testRegressionAgainstPreviousSnapshotLatchesEvenAboveAnchor() throws {
        let settings = configured(accounting: .sum)
        var value = try calibration(settings: settings, used: providerUpload + providerDownload)
        let previous = snapshot(at: anchorTime.addingTimeInterval(60), upload: agentUpload + 200, download: agentDownload + 100)
        let current = snapshot(at: anchorTime.addingTimeInterval(120), upload: agentUpload + 100, download: agentDownload + 200)

        XCTAssertTrue(value.invalidateIfCountersRegressed(snapshot: current, previousSnapshot: previous))
        XCTAssertEqual(value.invalidatedAt, current.timestamp)
        XCTAssertFalse(value.invalidateIfCountersRegressed(snapshot: current, previousSnapshot: previous))
    }

    func testNextPeriodResetDoesNotInvalidateExpiredCalibration() throws {
        var settings = configured(accounting: .sum)
        var value = try calibration(settings: settings, used: providerUpload + providerDownload)
        let nextPeriod = snapshot(at: calibrationDate("2026-11-10T00:00:00Z"), upload: 20, download: 10)

        XCTAssertFalse(value.invalidateIfCountersRegressed(snapshot: nextPeriod, previousSnapshot: snapshot()))
        XCTAssertNil(value.invalidatedAt)
        settings.calibration = value
        let usage = TrafficUsage.calculate(snapshot: nextPeriod, settings: settings, now: nextPeriod.timestamp)
        XCTAssertEqual(usage.label, "本期流量")
        XCTAssertEqual(usage.usedBytes, 30)
        XCTAssertEqual(usage.remainingBytes, quota - 30)
        XCTAssertNil(usage.appliedCalibration)
    }

    func testInvalidationIgnoresOfflineAndOtherNodeSnapshots() throws {
        let settings = configured(accounting: .sum)
        for current in [
            snapshot(at: anchorTime.addingTimeInterval(60), upload: 0, download: 0, isOnline: false),
            snapshot(at: anchorTime.addingTimeInterval(60), upload: 0, download: 0, nodeID: "another-fixture-node")
        ] {
            var value = try calibration(settings: settings, used: providerUpload + providerDownload)
            XCTAssertFalse(value.invalidateIfCountersRegressed(snapshot: current))
            XCTAssertNil(value.invalidatedAt)
        }
    }

    func testInvalidationIgnoresIrrelevantPreviousSnapshots() throws {
        let settings = configured(accounting: .sum)
        let current = snapshot(at: anchorTime.addingTimeInterval(120), upload: agentUpload + 100, download: agentDownload + 100)
        let previousTime = anchorTime.addingTimeInterval(60)
        for previous in [
            snapshot(at: previousTime, upload: agentUpload + 200, isOnline: false),
            snapshot(at: previousTime, upload: agentUpload + 200, nodeID: "another-fixture-node"),
            snapshot(at: current.timestamp.addingTimeInterval(1), upload: agentUpload + 200),
            snapshot(at: calibrationDate("2026-10-09T23:59:59Z"), upload: agentUpload + 200)
        ] {
            var value = try calibration(settings: settings, used: providerUpload + providerDownload)
            XCTAssertFalse(value.invalidateIfCountersRegressed(snapshot: current, previousSnapshot: previous))
            XCTAssertNil(value.invalidatedAt)
        }
    }

    func testFactoryRejectsNegativeAndNonfiniteProviderReadings() {
        let settings = configured(accounting: .sum)
        for invalid in [-1, Double.nan, Double.infinity, -Double.infinity] {
            for field in 0..<3 {
                var values = [providerUpload + providerDownload, providerUpload, providerDownload]
                values[field] = invalid
                XCTAssertThrowsError(try TrafficCalibration.create(
                    snapshot: snapshot(), settings: settings,
                    providerUsedBytes: values[0], providerUploadedBytes: values[1], providerDownloadedBytes: values[2],
                    observedAt: anchorTime
                ), "provider field \(field): \(invalid)")
            }
        }
    }

    func testFactoryRejectsNegativeAndNonfiniteAgentAnchors() {
        let settings = configured(accounting: .sum)
        for invalid in [-1, Double.nan, Double.infinity, -Double.infinity] {
            for (upload, download) in [(invalid, agentDownload), (agentUpload, invalid)] {
                XCTAssertThrowsError(try calibration(
                    settings: settings, used: providerUpload + providerDownload,
                    anchor: snapshot(upload: upload, download: download)
                ))
            }
        }
    }

    func testFactoryRejectsOfflineAndStaleAnchors() throws {
        let settings = configured(accounting: .sum)
        XCTAssertThrowsError(try calibration(
            settings: settings, used: providerUpload + providerDownload, anchor: snapshot(isOnline: false)
        ))
        XCTAssertThrowsError(try calibration(
            settings: settings, used: providerUpload + providerDownload,
            anchor: snapshot(at: anchorTime.addingTimeInterval(-31))
        ))
        XCTAssertNoThrow(try calibration(
            settings: settings, used: providerUpload + providerDownload,
            anchor: snapshot(at: anchorTime.addingTimeInterval(-30))
        ))
        XCTAssertNoThrow(try TrafficCalibration.create(
            snapshot: snapshot(at: anchorTime.addingTimeInterval(-31)), settings: settings,
            providerUsedBytes: providerUpload + providerDownload,
            providerUploadedBytes: providerUpload, providerDownloadedBytes: providerDownload,
            observedAt: anchorTime, maximumSnapshotAge: 60
        ))
    }

    func testFactoryRejectsUnconfirmedOrInvalidMonthlyConfiguration() {
        let changes: [(inout TrafficSettings) -> Void] = [
            { $0.monthlyRotationConfirmed = false },
            { $0.resetDay = 0 },
            { $0.resetDay = 32 },
            { $0.timeZoneIdentifier = "Fixture/Invalid_Zone" }
        ]
        for change in changes {
            var settings = configured(accounting: .sum)
            change(&settings)
            XCTAssertThrowsError(try calibration(settings: settings, used: providerUpload + providerDownload))
        }
    }

    func testFactoryRejectsInvalidStatisticsStartAndSource() {
        for start in [anchorTime.addingTimeInterval(1), Date(timeIntervalSince1970: .nan), Date(timeIntervalSince1970: .infinity)] {
            var settings = configured(accounting: .sum)
            settings.statisticsStartedAt = start
            XCTAssertThrowsError(try calibration(settings: settings, used: providerUpload + providerDownload))
        }
        let settings = configured(accounting: .sum)
        for source in ["", " \n\t ", "示例\n来源", String(repeating: "x", count: 65)] {
            XCTAssertThrowsError(try TrafficCalibration.create(
                snapshot: snapshot(), settings: settings,
                providerUsedBytes: providerUpload + providerDownload,
                providerUploadedBytes: providerUpload, providerDownloadedBytes: providerDownload,
                source: source, observedAt: anchorTime
            ))
        }
    }

    func testProviderUsedValidationUsesSelectedAccountingAndAllowsRounding() throws {
        let cases: [(TrafficAccounting, Double)] = [
            (.sum, providerUpload + providerDownload), (.max, providerDownload),
            (.min, providerUpload), (.upload, providerUpload), (.download, providerDownload)
        ]
        for (accounting, expected) in cases {
            let settings = configured(accounting: accounting)
            XCTAssertNoThrow(try calibration(settings: settings, used: expected), accounting.rawValue)
            XCTAssertNoThrow(try calibration(settings: settings, used: expected + 30_000_000), accounting.rawValue)
            XCTAssertNoThrow(try calibration(settings: settings, used: expected - 30_000_000), accounting.rawValue)
            XCTAssertThrowsError(try calibration(settings: settings, used: expected + 31_000_000), accounting.rawValue)
            XCTAssertThrowsError(try calibration(settings: settings, used: expected - 31_000_000), accounting.rawValue)
        }
    }

    func testCalibrationSurvivesSettingsJSONRoundTripAndStillApplies() throws {
        var settings = configured(accounting: .sum)
        settings.calibration = try calibration(settings: settings, used: providerUpload + providerDownload)
        let data = try JSONEncoder().encode(settings)
        let restored = try JSONDecoder().decode(TrafficSettings.self, from: data)

        XCTAssertEqual(restored, settings)
        let usage = TrafficUsage.calculate(snapshot: snapshot(), settings: restored, now: anchorTime)
        XCTAssertEqual(usage.appliedCalibration, settings.calibration)
        XCTAssertEqual(usage.label, "本期估算")
        XCTAssertEqual(usage.usedBytes, 10_000_000_000)
    }

    func testOlderSettingsJSONWithoutCalibrationKeepsUnknownCoverage() throws {
        let data = Data(#"{"monthlyRotationConfirmed":true,"resetDay":10,"timeZoneIdentifier":"UTC","quotaBytes":20000000000,"accounting":"sum"}"#.utf8)
        let settings = try JSONDecoder().decode(TrafficSettings.self, from: data)

        XCTAssertNil(settings.calibration)
        XCTAssertNil(settings.statisticsStartedAt)
        let usage = TrafficUsage.calculate(snapshot: snapshot(), settings: settings, now: anchorTime)
        assertRecordedWithoutBudget(usage)
        XCTAssertEqual(usage.usedBytes, agentUpload + agentDownload)
    }

    private func configured(accounting: TrafficAccounting) -> TrafficSettings {
        TrafficSettings(
            monthlyRotationConfirmed: true, resetDay: 10, timeZoneIdentifier: "UTC",
            quotaBytes: quota, accounting: accounting,
            statisticsStartedAt: calibrationDate("2026-10-20T00:00:00Z")
        )
    }

    private func calibration(settings: TrafficSettings, used: Double, anchor: ServerSnapshot? = nil) throws -> TrafficCalibration {
        try TrafficCalibration.create(
            snapshot: anchor ?? snapshot(), settings: settings,
            providerUsedBytes: used, providerUploadedBytes: providerUpload, providerDownloadedBytes: providerDownload,
            source: "示例服务商后台", observedAt: anchorTime
        )
    }

    private func snapshot(at date: Date? = nil, upload: Double? = nil, download: Double? = nil, isOnline: Bool = true, nodeID: String = "calibration-fixture-node") -> ServerSnapshot {
        ServerSnapshot(
            nodeID: nodeID, timestamp: date ?? anchorTime, isOnline: isOnline,
            cpuPercent: 12, memoryUsedBytes: 400, memoryTotalBytes: 2_000,
            diskUsedBytes: 4_000, diskTotalBytes: 20_000,
            uploadBytesPerSecond: 3, downloadBytesPerSecond: 4,
            uploadedBytes: upload ?? agentUpload, downloadedBytes: download ?? agentDownload, uptime: 100
        )
    }

    private func assertRecordedWithoutBudget(_ usage: TrafficUsage, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(usage.label, "本期已记录", file: file, line: line)
        XCTAssertNotNil(usage.period, file: file, line: line)
        XCTAssertNil(usage.appliedCalibration, file: file, line: line)
        XCTAssertNil(usage.quotaBytes, file: file, line: line)
        XCTAssertNil(usage.remainingBytes, file: file, line: line)
        XCTAssertNil(usage.fractionUsed, file: file, line: line)
        XCTAssertNotNil(usage.configurationIssue, file: file, line: line)
    }
}

private func calibrationDate(_ value: String) -> Date {
    ISO8601DateFormatter().date(from: value)!
}
