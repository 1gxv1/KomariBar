import Foundation

/// A single provider reading anchored to contemporaneous Agent counters.
/// It estimates subsequent usage; it does not add missing monitoring history.
public struct TrafficCalibration: Codable, Equatable, Sendable {
    public let nodeID: String
    public let source: String
    public let providerUsedBytes: Double
    public let providerUploadedBytes: Double
    public let providerDownloadedBytes: Double
    public let agentUploadedBytes: Double
    public let agentDownloadedBytes: Double
    public let agentSnapshotAt: Date
    public let calibratedAt: Date
    public let periodStart: Date
    public let periodEnd: Date
    public let resetDay: Int
    public let timeZoneIdentifier: String
    public let accounting: TrafficAccounting
    public let statisticsStartedAt: Date?
    /// Once an observed regression breaks the anchor, only a new calibration may replace it.
    public private(set) var invalidatedAt: Date?

    // Provider dashboards often round total and directional GB figures separately.
    private static let roundingToleranceBytes: Double = 30_000_000

    public static func create(
        snapshot: ServerSnapshot,
        settings: TrafficSettings,
        providerUsedBytes: Double,
        providerUploadedBytes: Double,
        providerDownloadedBytes: Double,
        source: String = "服务商后台",
        observedAt: Date = Date(),
        maximumSnapshotAge: TimeInterval = 30
    ) throws -> TrafficCalibration {
        guard settings.monthlyRotationConfirmed, (1...31).contains(settings.resetDay),
              observedAt.timeIntervalSince1970.isFinite,
              let timeZone = TimeZone(identifier: settings.timeZoneIdentifier),
              let period = TrafficUsage.billingPeriod(containing: observedAt, resetDay: settings.resetDay, timeZone: timeZone) else {
            throw TrafficCalibrationError.invalidSettings
        }
        guard snapshot.isOnline, !snapshot.nodeID.isEmpty else { throw TrafficCalibrationError.snapshotUnavailable }
        let age = observedAt.timeIntervalSince(snapshot.timestamp)
        guard maximumSnapshotAge.isFinite, maximumSnapshotAge >= 0,
              age.isFinite, age >= -30, age <= maximumSnapshotAge,
              snapshot.timestamp >= period.start, snapshot.timestamp < period.end else {
            throw TrafficCalibrationError.snapshotNotFresh
        }
        if let startedAt = settings.statisticsStartedAt {
            guard startedAt.timeIntervalSince1970.isFinite, startedAt <= snapshot.timestamp else {
                throw TrafficCalibrationError.invalidSettings
            }
        }
        let name = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validSource(name) else { throw TrafficCalibrationError.invalidSource }
        guard [providerUsedBytes, providerUploadedBytes, providerDownloadedBytes, snapshot.uploadedBytes, snapshot.downloadedBytes].allSatisfy(validCounter) else {
            throw TrafficCalibrationError.invalidCounter
        }
        guard providerValuesMatch(used: providerUsedBytes, uploaded: providerUploadedBytes, downloaded: providerDownloadedBytes, accounting: settings.accounting) else {
            throw TrafficCalibrationError.inconsistentProviderValues
        }
        return TrafficCalibration(
            nodeID: snapshot.nodeID,
            source: name,
            providerUsedBytes: providerUsedBytes,
            providerUploadedBytes: providerUploadedBytes,
            providerDownloadedBytes: providerDownloadedBytes,
            agentUploadedBytes: snapshot.uploadedBytes,
            agentDownloadedBytes: snapshot.downloadedBytes,
            agentSnapshotAt: snapshot.timestamp,
            calibratedAt: observedAt,
            periodStart: period.start,
            periodEnd: period.end,
            resetDay: settings.resetDay,
            timeZoneIdentifier: settings.timeZoneIdentifier,
            accounting: settings.accounting,
            statisticsStartedAt: settings.statisticsStartedAt,
            invalidatedAt: nil
        )
    }

    /// Latch a real counter regression before replacing an older online sample.
    /// The normal next-period reset and offline placeholders must not invalidate this period.
    @discardableResult
    public mutating func invalidateIfCountersRegressed(snapshot: ServerSnapshot, previousSnapshot: ServerSnapshot? = nil) -> Bool {
        guard invalidatedAt == nil, snapshot.isOnline, snapshot.nodeID == nodeID,
              snapshot.timestamp >= agentSnapshotAt, snapshot.timestamp >= periodStart,
              snapshot.timestamp < periodEnd else { return false }
        var regressed = !Self.validCounter(snapshot.uploadedBytes) || !Self.validCounter(snapshot.downloadedBytes)
            || snapshot.uploadedBytes < agentUploadedBytes || snapshot.downloadedBytes < agentDownloadedBytes
        if let previous = previousSnapshot, previous.isOnline, previous.nodeID == nodeID,
           previous.timestamp >= agentSnapshotAt, previous.timestamp >= periodStart,
           previous.timestamp < periodEnd, previous.timestamp <= snapshot.timestamp,
           Self.validCounter(previous.uploadedBytes), Self.validCounter(previous.downloadedBytes) {
            regressed = regressed || snapshot.uploadedBytes < previous.uploadedBytes || snapshot.downloadedBytes < previous.downloadedBytes
        }
        guard regressed else { return false }
        invalidatedAt = snapshot.timestamp
        return true
    }

    func isExpired(in period: DateInterval) -> Bool {
        periodStart.timeIntervalSince1970.isFinite && periodEnd.timeIntervalSince1970.isFinite
            && periodStart < periodEnd && periodEnd <= period.start
    }

    func validationIssue(snapshot: ServerSnapshot, settings: TrafficSettings, period: DateInterval, now: Date) -> String? {
        guard !nodeID.isEmpty, Self.validSource(source),
              [providerUsedBytes, providerUploadedBytes, providerDownloadedBytes, agentUploadedBytes, agentDownloadedBytes].allSatisfy(Self.validCounter),
              [agentSnapshotAt, calibratedAt, periodStart, periodEnd].allSatisfy({ $0.timeIntervalSince1970.isFinite }),
              periodStart < periodEnd, agentSnapshotAt >= periodStart, agentSnapshotAt < periodEnd,
              calibratedAt >= periodStart, calibratedAt < periodEnd,
              calibratedAt <= now.addingTimeInterval(30),
              Self.providerValuesMatch(used: providerUsedBytes, uploaded: providerUploadedBytes, downloaded: providerDownloadedBytes, accounting: accounting) else {
            return "本期校准数据无效，请重新校准；暂不估算剩余额度。"
        }
        guard nodeID == snapshot.nodeID else {
            return "校准记录不属于当前节点，请重新校准；暂不估算剩余额度。"
        }
        guard invalidatedAt == nil else {
            return "已检测到 Agent 计数回退，本期校准已停用；请重新校准，暂不估算剩余额度。"
        }
        guard resetDay == settings.resetDay, timeZoneIdentifier == settings.timeZoneIdentifier,
              accounting == settings.accounting, statisticsStartedAt == settings.statisticsStartedAt,
              periodStart == period.start, periodEnd == period.end else {
            return "账期、计量方式或统计开始时间已改变，请重新校准；暂不估算剩余额度。"
        }
        guard snapshot.timestamp >= agentSnapshotAt else {
            return "最新上报早于校准时的记录，请刷新后再查看估算用量。"
        }
        guard Self.validCounter(snapshot.uploadedBytes), Self.validCounter(snapshot.downloadedBytes),
              snapshot.uploadedBytes >= agentUploadedBytes, snapshot.downloadedBytes >= agentDownloadedBytes else {
            return "Agent 计数低于校准记录或数据无效，可能已重置；请重新校准，暂不估算剩余额度。"
        }
        return nil
    }

    func estimate(snapshot: ServerSnapshot) -> (uploaded: Double, downloaded: Double, used: Double)? {
        let uploaded = providerUploadedBytes + (snapshot.uploadedBytes - agentUploadedBytes)
        let downloaded = providerDownloadedBytes + (snapshot.downloadedBytes - agentDownloadedBytes)
        let initial = accounting.amount(uploaded: providerUploadedBytes, downloaded: providerDownloadedBytes)
        let current = accounting.amount(uploaded: uploaded, downloaded: downloaded)
        let used = providerUsedBytes + (current - initial)
        guard [uploaded, downloaded, current, used].allSatisfy(Self.validCounter) else { return nil }
        return (uploaded, downloaded, used)
    }

    private static func validCounter(_ value: Double) -> Bool { value.isFinite && value >= 0 }

    private static func validSource(_ source: String) -> Bool {
        !source.isEmpty && source.count <= 64 && source.rangeOfCharacter(from: .controlCharacters) == nil
    }

    private static func providerValuesMatch(used: Double, uploaded: Double, downloaded: Double, accounting: TrafficAccounting) -> Bool {
        let amount = accounting.amount(uploaded: uploaded, downloaded: downloaded)
        return amount.isFinite && abs(used - amount) <= roundingToleranceBytes
    }
}

public enum TrafficCalibrationError: Error, LocalizedError {
    case invalidSettings, snapshotUnavailable, snapshotNotFresh, invalidCounter, invalidSource, inconsistentProviderValues

    public var errorDescription: String? {
        switch self {
        case .invalidSettings: return "请先保存正确的月重置日、时区与统计开始时间，再创建校准。"
        case .snapshotUnavailable: return "校准需要已连接且在线的真实服务器，请先等待有效上报。"
        case .snapshotNotFresh: return "校准需要当前账期内的新鲜上报，请刷新服务器状态后重试。"
        case .invalidCounter: return "已用、上传和下载量必须是大于或等于 0 的有限数值。"
        case .invalidSource: return "请填写 1～64 字的来源名称，不要包含换行。"
        case .inconsistentProviderValues: return "已用合计与所选计量方式不一致，请核对上传、下载和计量方式；允许少量显示取整差异。"
        }
    }
}
