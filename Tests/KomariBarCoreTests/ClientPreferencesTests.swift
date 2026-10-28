import XCTest
@testable import KomariBarCore

final class ClientPreferencesTests: XCTestCase {
    func testSupportedRefreshIntervalsArePreserved() {
        for interval in [5.0, 10, 15, 30, 60] {
            XCTAssertEqual(ClientPreferences(refreshIntervalSeconds: interval).refreshIntervalSeconds, interval)
        }
    }

    func testMissingInvalidAndNonfiniteIntervalsUseSafeDefault() {
        XCTAssertEqual(ClientPreferences().refreshIntervalSeconds, 5)
        for interval in [0, -1, 4, 6, 61, Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertEqual(ClientPreferences(refreshIntervalSeconds: interval).refreshIntervalSeconds, 5)
        }
    }

    func testStalenessAllowanceScalesWithClientRefresh() {
        XCTAssertEqual(ClientPreferences(refreshIntervalSeconds: 5).staleDataThreshold, 30)
        XCTAssertEqual(ClientPreferences(refreshIntervalSeconds: 15).staleDataThreshold, 35)
        XCTAssertEqual(ClientPreferences(refreshIntervalSeconds: 60).staleDataThreshold, 125)
    }

    func testSlowerRefreshDoesNotMarkExpectedSnapshotAgeAsStale() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let preferences = ClientPreferences(refreshIntervalSeconds: 60)
        XCTAssertTrue(preferences.isSnapshotFresh(now.addingTimeInterval(-90), now: now))
        XCTAssertTrue(preferences.isSnapshotFresh(now.addingTimeInterval(-125), now: now))
        XCTAssertFalse(preferences.isSnapshotFresh(now.addingTimeInterval(-126), now: now))
        XCTAssertFalse(ClientPreferences().isSnapshotFresh(now.addingTimeInterval(-90), now: now))
    }

    func testFutureClockSkewIsNotHiddenBySlowerRefresh() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let preferences = ClientPreferences(refreshIntervalSeconds: 60)
        XCTAssertTrue(preferences.isSnapshotFresh(now.addingTimeInterval(30), now: now))
        XCTAssertFalse(preferences.isSnapshotFresh(now.addingTimeInterval(31), now: now))
        XCTAssertFalse(preferences.isSnapshotFresh(Date(timeIntervalSince1970: .nan), now: now))
    }
}
