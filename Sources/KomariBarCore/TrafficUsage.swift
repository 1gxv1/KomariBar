import Foundation

/// A display-ready interpretation of the Agent's counters. This never derives
/// billed bytes from chart samples, which may be downsampled by the server.
public struct TrafficUsage: Equatable, Sendable {
    public let uploadedBytes: Double
    public let downloadedBytes: Double
    public let usedBytes: Double
    public let quotaBytes: Double?
    public let remainingBytes: Double?
    public let fractionUsed: Double?
    public let period: DateInterval?
    public let label: String
    public let configurationIssue: String?

    public static func calculate(
        snapshot: ServerSnapshot,
        settings: TrafficSettings,
        now: Date = Date()
    ) -> TrafficUsage {
        let uploaded = nonnegativeFinite(snapshot.uploadedBytes)
        let downloaded = nonnegativeFinite(snapshot.downloadedBytes)
        let used: Double
        switch settings.accounting {
        case .sum:
            let sum = uploaded + downloaded
            used = sum.isFinite ? sum : Double.greatestFiniteMagnitude
        case .max:
            used = Swift.max(uploaded, downloaded)
        case .min:
            used = Swift.min(uploaded, downloaded)
        case .upload:
            used = uploaded
        case .download:
            used = downloaded
        }

        func cumulative(_ issue: String) -> TrafficUsage {
            TrafficUsage(
                uploadedBytes: uploaded, downloadedBytes: downloaded,
                usedBytes: used, quotaBytes: nil, remainingBytes: nil,
                fractionUsed: nil, period: nil, label: "累计流量",
                configurationIssue: issue
            )
        }

        guard settings.monthlyRotationConfirmed else {
            return cumulative("尚未确认 Agent 的每月流量重置设置，当前仅展示累计值。")
        }
        guard (1...31).contains(settings.resetDay) else {
            return cumulative("流量重置日应为每月 1～31 日。")
        }
        guard let timeZone = TimeZone(identifier: settings.timeZoneIdentifier) else {
            return cumulative("账期时区无效，请选择与 Agent 一致的时区。")
        }
        guard let interval = billingPeriod(containing: now, resetDay: settings.resetDay, timeZone: timeZone) else {
            return cumulative("无法计算当前账期，请检查重置日和时区。")
        }
        guard snapshot.timestamp >= interval.start && snapshot.timestamp < interval.end else {
            return cumulative("最新上报不在当前账期内，请刷新后再查看本期用量。")
        }

        func incomplete(_ issue: String) -> TrafficUsage {
            TrafficUsage(
                uploadedBytes: uploaded, downloadedBytes: downloaded,
                usedBytes: used, quotaBytes: nil, remainingBytes: nil,
                fractionUsed: nil, period: interval, label: "本期已记录",
                configurationIssue: issue
            )
        }
        guard let startedAt = settings.statisticsStartedAt else {
            return incomplete("尚未确认 Agent 的统计开始时间，本期数据可能不完整，暂不估算剩余额度。")
        }
        guard startedAt.timeIntervalSince1970.isFinite, startedAt <= snapshot.timestamp else {
            return incomplete("统计开始时间晚于最新上报或时间无效，请检查设置；暂不估算剩余额度。")
        }
        guard startedAt <= interval.start else {
            return incomplete("Agent 在本期中途开始统计，本期数据不完整；下一次重置后才会显示完整账期预算。")
        }

        let quota = settings.quotaBytes.flatMap { value in
            value.isFinite && value > 0 ? value : nil
        }
        let ratio = quota.map { used / $0 }.map { $0.isFinite ? $0 : Double.greatestFiniteMagnitude }
        return TrafficUsage(
            uploadedBytes: uploaded,
            downloadedBytes: downloaded,
            usedBytes: used,
            quotaBytes: quota,
            remainingBytes: quota.map { Swift.max(0, $0 - used) },
            fractionUsed: ratio,
            period: interval,
            label: "本期流量",
            configurationIssue: nil
        )
    }

    private static func nonnegativeFinite(_ value: Double) -> Double {
        value.isFinite ? Swift.max(0, value) : 0
    }

    /// Match Komari Agent 1.5.11: an unavailable day (e.g. February 31)
    /// rotates on the first day of the next month, not February's last day.
    private static func billingPeriod(containing now: Date, resetDay: Int, timeZone: TimeZone) -> DateInterval? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let currentMonth = calendar.dateInterval(of: .month, for: now)?.start else { return nil }
        let boundaries = (-2...2).compactMap { offset -> Date? in
            guard let month = calendar.date(byAdding: .month, value: offset, to: currentMonth),
                  let days = calendar.range(of: .day, in: .month, for: month) else { return nil }
            if resetDay > days.count {
                return calendar.date(byAdding: .month, value: 1, to: month)
            }
            var components = calendar.dateComponents([.year, .month], from: month)
            components.day = resetDay
            components.hour = 0
            components.minute = 0
            components.second = 0
            return calendar.date(from: components)
        }.sorted()
        guard let start = boundaries.last(where: { $0 <= now }),
              let end = boundaries.first(where: { $0 > now }) else { return nil }
        return DateInterval(start: start, end: end)
    }
}
