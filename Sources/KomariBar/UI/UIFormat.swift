import Foundation
import KomariBarCore
import SwiftUI

enum Palette {
    static let background = Color(red: 0.075, green: 0.083, blue: 0.105)
    static let surface = Color(red: 0.103, green: 0.113, blue: 0.138)
    static let primary = Color(red: 0.92, green: 0.93, blue: 0.97)
    static let secondary = Color(red: 0.51, green: 0.55, blue: 0.63)
    static let border = Color.white.opacity(0.055)
    static let lavender = Color(red: 0.66, green: 0.65, blue: 0.98)
    static let blue = Color(red: 0.37, green: 0.71, blue: 0.97)
    static let mint = Color(red: 0.36, green: 0.83, blue: 0.66)
    static let amber = Color(red: 0.96, green: 0.72, blue: 0.40)
    static let red = Color(red: 0.98, green: 0.43, blue: 0.48)
}

enum UIFormat {
    static func isFresh(_ date: Date, now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(date)
        return age >= -30 && age <= 30
    }

    static func percent(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        return String(format: "%.1f%%", max(0, value))
    }

    static func compact(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        return value >= 10 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    static func memory(_ bytes: Double) -> String {
        size(bytes, base: 1024, units: ["B", "KiB", "MiB", "GiB", "TiB", "PiB"])
    }

    static func traffic(_ bytes: Double) -> String {
        size(bytes, base: 1000, units: ["B", "KB", "MB", "GB", "TB", "PB"])
    }

    static func speed(_ bytes: Double) -> String { traffic(bytes) + "/s" }

    private static func size(_ bytes: Double, base: Double, units: [String]) -> String {
        guard bytes.isFinite, bytes >= 0 else { return "—" }
        guard bytes > 0 else { return "0 B" }
        let exponent = min(units.count - 1, max(0, Int(log(bytes) / log(base))))
        let value = bytes / pow(base, Double(exponent))
        return String(format: exponent == 0 ? "%.0f %@" : "%.1f %@", value, units[exponent])
    }

    static func uptime(_ duration: TimeInterval) -> String {
        guard duration.isFinite, duration >= 0 else { return "—" }
        let minutes = Int(min(duration / 60, Double(Int.max / 2)))
        if minutes >= 1440 { return "\(minutes / 1440) 天 \((minutes % 1440) / 60) 小时" }
        if minutes >= 60 { return "\(minutes / 60) 小时 \(minutes % 60) 分钟" }
        return "\(minutes) 分钟"
    }

    static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm:ss" : "M/d HH:mm"
        return formatter.string(from: date)
    }

    static func cycleDate(_ date: Date, zone: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: zone) ?? TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "M 月 d 日"
        return formatter.string(from: date)
    }

    static func serverDescription(_ node: ServerNode) -> String {
        let values = [node.region, node.os, node.cpuName].filter { !$0.isEmpty }
        return values.isEmpty ? "等待主机信息" : values.joined(separator: " · ")
    }
}
