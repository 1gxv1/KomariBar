import Foundation
import KomariBarCore

enum DemoData {
    static let nodes: [ServerNode] = [
        ServerNode(id: "demo-tokyo", name: "东京 · 主力节点", group: "个人服务器", region: "JP", cpuName: "AMD EPYC", cpuCores: 2, os: "Ubuntu 24.04", memoryTotalBytes: 2_147_483_648, diskTotalBytes: 42_949_672_960, trafficQuotaBytes: 1_000_000_000_000, trafficAccounting: .max),
        ServerNode(id: "demo-singapore", name: "新加坡 · 备用节点", group: "个人服务器", region: "SG", cpuName: "AMD EPYC", cpuCores: 2, os: "Debian 12", memoryTotalBytes: 4_294_967_296, diskTotalBytes: 85_899_345_920, trafficQuotaBytes: 2_000_000_000_000, trafficAccounting: .sum),
        ServerNode(id: "demo-losangeles", name: "洛杉矶 · 实验节点", group: "实验环境", region: "US", cpuName: "Intel Xeon", cpuCores: 1, os: "Debian 12", memoryTotalBytes: 1_073_741_824, diskTotalBytes: 21_474_836_480, trafficQuotaBytes: 500_000_000_000, trafficAccounting: .upload)
    ]

    static func snapshots(at now: Date = Date()) -> [String: ServerSnapshot] {
        Dictionary(uniqueKeysWithValues: nodes.enumerated().map { index, node in
            let online = index < 2
            return (node.id, ServerSnapshot(
                nodeID: node.id,
                timestamp: online ? now : now.addingTimeInterval(-3_600),
                isOnline: online,
                cpuPercent: online ? (index == 0 ? 14.8 : 6.2) : 0,
                memoryUsedBytes: index == 0 ? 401_604_608 : 912_680_550,
                memoryTotalBytes: node.memoryTotalBytes,
                diskUsedBytes: index == 0 ? 8_589_934_592 : 12_884_901_888,
                diskTotalBytes: node.diskTotalBytes,
                uploadBytesPerSecond: online ? (index == 0 ? 2_410_000 : 520_000) : 0,
                downloadBytesPerSecond: online ? (index == 0 ? 8_230_000 : 780_000) : 0,
                uploadedBytes: index == 0 ? 326_400_000_000 : 142_000_000_000,
                downloadedBytes: index == 0 ? 279_100_000_000 : 186_000_000_000,
                uptime: 9_247_380
            ))
        })
    }

    static func history(for nodeID: String, at now: Date = Date()) -> [HistoryPoint] {
        guard nodeID != "demo-losangeles" else { return [] }
        let offset = nodeID == "demo-tokyo" ? 0.0 : 4.0
        return (0..<61).map { index in
            let t = Double(index)
            return HistoryPoint(
                timestamp: now.addingTimeInterval(Double(index - 60) * 60),
                cpuPercent: max(2, 14 + sin(t * 0.32 + offset) * 6 + cos(t * 0.73) * 3),
                memoryPercent: 18.7 + sin(t * 0.12 + offset) * 2,
                uploadBytesPerSecond: max(0, 2_410_000 + sin(t * 0.23) * 1_200_000),
                downloadBytesPerSecond: max(0, 7_200_000 + sin(t * 0.27 + offset) * 3_100_000)
            )
        }
    }
}
