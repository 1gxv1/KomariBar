import Foundation

/// Local client behavior; these preferences never change the Agent's collection cadence.
public struct ClientPreferences: Equatable, Sendable {
    public static let supportedRefreshIntervals: [TimeInterval] = [5, 10, 15, 30, 60]
    public static let defaultRefreshInterval: TimeInterval = 5

    public let refreshIntervalSeconds: TimeInterval

    public init(refreshIntervalSeconds: TimeInterval = defaultRefreshInterval) {
        self.refreshIntervalSeconds = Self.supportedRefreshIntervals.contains(refreshIntervalSeconds)
            ? refreshIntervalSeconds : Self.defaultRefreshInterval
    }

    /// Allow two polling intervals plus a small response/Agent-reporting margin.
    public var staleDataThreshold: TimeInterval { max(30, refreshIntervalSeconds * 2 + 5) }

    public func isSnapshotFresh(_ timestamp: Date, now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(timestamp)
        // A slower client refresh cannot explain a substantially future-dated report.
        return age >= -30 && age <= staleDataThreshold
    }
}
