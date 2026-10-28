import Foundation

public enum TrafficAccounting: String, Codable, CaseIterable, Identifiable, Sendable {
    case sum, max, min, upload, download

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .sum: return "上传＋下载"
        case .max: return "上传、下载取较大值"
        case .min: return "上传、下载取较小值"
        case .upload: return "仅上传"
        case .download: return "仅下载"
        }
    }

    func amount(uploaded: Double, downloaded: Double) -> Double {
        switch self {
        case .sum: return uploaded + downloaded
        case .max: return Swift.max(uploaded, downloaded)
        case .min: return Swift.min(uploaded, downloaded)
        case .upload: return uploaded
        case .download: return downloaded
        }
    }
}

public struct ServerNode: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let group: String
    public let region: String
    public let cpuName: String
    public let cpuCores: Int
    public let os: String
    public let memoryTotalBytes: Double
    public let diskTotalBytes: Double
    public let trafficQuotaBytes: Double?
    public let trafficAccounting: TrafficAccounting

    public init(id: String, name: String, group: String = "", region: String = "", cpuName: String = "", cpuCores: Int = 0, os: String = "", memoryTotalBytes: Double = 0, diskTotalBytes: Double = 0, trafficQuotaBytes: Double? = nil, trafficAccounting: TrafficAccounting = .max) {
        self.id = id
        self.name = name
        self.group = group
        self.region = region
        self.cpuName = cpuName
        self.cpuCores = cpuCores
        self.os = os
        self.memoryTotalBytes = memoryTotalBytes
        self.diskTotalBytes = diskTotalBytes
        self.trafficQuotaBytes = trafficQuotaBytes
        self.trafficAccounting = trafficAccounting
    }
}

public struct ServerSnapshot: Equatable, Sendable {
    public let nodeID: String
    public let timestamp: Date
    public let isOnline: Bool
    public let cpuPercent: Double
    public let memoryUsedBytes: Double
    public let memoryTotalBytes: Double
    public let diskUsedBytes: Double
    public let diskTotalBytes: Double
    public let uploadBytesPerSecond: Double
    public let downloadBytesPerSecond: Double
    public let uploadedBytes: Double
    public let downloadedBytes: Double
    public let uptime: TimeInterval

    public init(nodeID: String, timestamp: Date, isOnline: Bool, cpuPercent: Double, memoryUsedBytes: Double, memoryTotalBytes: Double, diskUsedBytes: Double, diskTotalBytes: Double, uploadBytesPerSecond: Double, downloadBytesPerSecond: Double, uploadedBytes: Double, downloadedBytes: Double, uptime: TimeInterval) {
        self.nodeID = nodeID
        self.timestamp = timestamp
        self.isOnline = isOnline
        self.cpuPercent = cpuPercent
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
        self.diskUsedBytes = diskUsedBytes
        self.diskTotalBytes = diskTotalBytes
        self.uploadBytesPerSecond = uploadBytesPerSecond
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadedBytes = uploadedBytes
        self.downloadedBytes = downloadedBytes
        self.uptime = uptime
    }

    public var memoryPercent: Double { memoryTotalBytes > 0 ? memoryUsedBytes / memoryTotalBytes * 100 : 0 }
    public var diskPercent: Double { diskTotalBytes > 0 ? diskUsedBytes / diskTotalBytes * 100 : 0 }
}

public struct HistoryPoint: Identifiable, Equatable, Sendable {
    public var id: Date { timestamp }
    public let timestamp: Date
    public let cpuPercent: Double
    public let memoryPercent: Double
    public let uploadBytesPerSecond: Double
    public let downloadBytesPerSecond: Double

    public init(timestamp: Date, cpuPercent: Double, memoryPercent: Double, uploadBytesPerSecond: Double, downloadBytesPerSecond: Double) {
        self.timestamp = timestamp
        self.cpuPercent = cpuPercent
        self.memoryPercent = memoryPercent
        self.uploadBytesPerSecond = uploadBytesPerSecond
        self.downloadBytesPerSecond = downloadBytesPerSecond
    }
}

public struct KomariConnection: Sendable {
    public let baseURL: URL
    public let apiKey: String?

    public init(baseURL: URL, apiKey: String? = nil) {
        self.baseURL = baseURL
        self.apiKey = apiKey
    }
}

public struct TrafficSettings: Codable, Equatable, Sendable {
    public var monthlyRotationConfirmed: Bool
    public var resetDay: Int
    public var timeZoneIdentifier: String
    public var quotaBytes: Double?
    public var accounting: TrafficAccounting
    /// The actual time the Agent began this continuous set of counters.
    /// Missing values preserve older settings while treating coverage as unknown.
    public var statisticsStartedAt: Date?
    public var calibration: TrafficCalibration?

    public init(monthlyRotationConfirmed: Bool = false, resetDay: Int = 1, timeZoneIdentifier: String = "UTC", quotaBytes: Double? = nil, accounting: TrafficAccounting = .max, statisticsStartedAt: Date? = nil, calibration: TrafficCalibration? = nil) {
        self.monthlyRotationConfirmed = monthlyRotationConfirmed
        self.resetDay = resetDay
        self.timeZoneIdentifier = timeZoneIdentifier
        self.quotaBytes = quotaBytes
        self.accounting = accounting
        self.statisticsStartedAt = statisticsStartedAt
        self.calibration = calibration
    }
}
