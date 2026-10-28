import AppKit
import Charts
import KomariBarCore
import SwiftUI

@MainActor
struct DashboardView: View {
    @ObservedObject var model: AppState
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !model.nodes.isEmpty {
                        ServerPicker(
                            nodes: model.nodes,
                            snapshots: model.snapshots,
                            selectedID: model.selectedNodeID,
                            isSnapshotFresh: model.isSnapshotFresh,
                            select: model.selectNode
                        )
                    }

                    if let message = model.lastError {
                        NoticeView(symbol: "exclamationmark.arrow.triangle.2.circlepath", title: "同步未完成", message: message, color: Palette.amber)
                    }

                    if let node = model.selectedNode {
                        serverHeading(node)
                        resourceCards(node)
                        HistoryCard(points: model.history, errorMessage: model.historyError)
                        networkCards
                        if let usage = model.selectedTraffic {
                            TrafficCard(usage: usage, settings: model.trafficSettings, openSettings: openSettings)
                        } else {
                            NoticeView(symbol: "arrow.up.arrow.down", title: "等待流量记录", message: "节点上报网络累计用量后，会在这里展示。", color: Palette.secondary)
                        }
                        if model.isDemoMode {
                            Text("当前为示例数据，不代表真实服务器状态。")
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 10)
                .padding(.bottom, 20)
            }
            footer
        }
        .frame(width: 580, height: min(780, max(460, (NSScreen.main?.visibleFrame.height ?? 900) - 100)))
        .background(Palette.background)
        .preferredColorScheme(.dark)
        .environment(\.locale, Locale(identifier: "zh_CN"))
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: "server.rack")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Palette.lavender)
                .frame(width: 37, height: 37)
                .background(Palette.lavender.opacity(0.13), in: RoundedRectangle(cornerRadius: 11))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("KomariBar")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.primary)
                Text("服务器监控")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.secondary)
            }
            if model.isDemoMode {
                Text("示例模式")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.amber)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Palette.amber.opacity(0.10), in: Capsule())
            }
            Spacer(minLength: 8)
            Button {
                Task { await model.refresh() }
            } label: {
                if model.isRefreshing {
                    ProgressView().controlSize(.small).frame(width: 17, height: 17)
                } else {
                    Image(systemName: "arrow.clockwise").frame(width: 17, height: 17)
                }
            }
            .buttonStyle(HeaderButtonStyle())
            .disabled(model.isRefreshing || (!model.isConfigured && !model.isDemoMode))
            .help("刷新服务器状态")
            .accessibilityLabel("刷新服务器状态")
            .keyboardShortcut("r", modifiers: .command)
            Button(action: openSettings) {
                Image(systemName: "slider.horizontal.3").frame(width: 17, height: 17)
            }
            .buttonStyle(HeaderButtonStyle())
            .help("面板连接与流量设置")
            .accessibilityLabel("打开设置")
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    private func serverHeading(_ node: ServerNode) -> some View {
        let snapshot = model.selectedSnapshot
        let fresh = snapshot.map { model.isSnapshotFresh($0.timestamp) } ?? false
        let active = snapshot?.isOnline == true && fresh
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(node.name).font(.system(size: 17, weight: .semibold))
                    HStack(spacing: 4) {
                        Circle().fill(active ? Palette.mint : Palette.secondary).frame(width: 5, height: 5)
                        Text(snapshot == nil ? "等待上报" : (active ? "在线" : (snapshot?.isOnline == true ? "数据过期" : "离线")))
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(active ? Palette.mint : Palette.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background((active ? Palette.mint : Palette.secondary).opacity(0.09), in: Capsule())
                }
                Text(UIFormat.serverDescription(node))
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let snapshot, snapshot.uptime > 0 {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("运行时间").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                    Text(UIFormat.uptime(snapshot.uptime)).font(.system(size: 11, weight: .medium, design: .monospaced))
                }
            }
        }
        .foregroundStyle(Palette.primary)
        .padding(.top, 1)
    }

    private func resourceCards(_ node: ServerNode) -> some View {
        let snapshot = model.selectedSnapshot
        let stale = snapshot.map { !$0.isOnline || !model.isSnapshotFresh($0.timestamp) } ?? false
        return HStack(spacing: 10) {
            MetricCard(title: "CPU", symbol: "cpu", value: snapshot.map { UIFormat.percent($0.cpuPercent) } ?? "—", detail: stale ? "最后记录" : (node.cpuCores > 0 ? "\(node.cpuCores) 核处理器" : "使用率"), fraction: snapshot.map { $0.cpuPercent / 100 }, accent: Palette.lavender)
            MetricCard(title: "内存", symbol: "memorychip", value: snapshot.flatMap { $0.memoryTotalBytes > 0 ? UIFormat.percent($0.memoryPercent) : nil } ?? "—", detail: snapshot.flatMap { $0.memoryTotalBytes > 0 ? "\(UIFormat.memory($0.memoryUsedBytes)) / \(UIFormat.memory($0.memoryTotalBytes))" : nil } ?? "等待内存信息", fraction: snapshot.flatMap { $0.memoryTotalBytes > 0 ? $0.memoryPercent / 100 : nil }, accent: Palette.blue)
            MetricCard(title: "磁盘", symbol: "internaldrive", value: snapshot.flatMap { $0.diskTotalBytes > 0 ? UIFormat.percent($0.diskPercent) : nil } ?? "—", detail: snapshot.flatMap { $0.diskTotalBytes > 0 ? "\(UIFormat.memory($0.diskUsedBytes)) / \(UIFormat.memory($0.diskTotalBytes))" : nil } ?? "等待磁盘信息", fraction: snapshot.flatMap { $0.diskTotalBytes > 0 ? $0.diskPercent / 100 : nil }, accent: Palette.mint)
        }
        .opacity(stale ? 0.68 : 1)
    }

    private var networkCards: some View {
        let snapshot = model.selectedSnapshot
        let live = snapshot.map { $0.isOnline && model.isSnapshotFresh($0.timestamp) } ?? false
        return HStack(spacing: 10) {
            NetworkCard(title: "上传速度", symbol: "arrow.up.right", value: live ? UIFormat.speed(snapshot?.uploadBytesPerSecond ?? 0) : "—", accent: Palette.mint)
            NetworkCard(title: "下载速度", symbol: "arrow.down.left", value: live ? UIFormat.speed(snapshot?.downloadBytesPerSecond ?? 0) : "—", accent: Palette.blue)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: model.isConfigured ? "server.rack" : "network")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Palette.lavender)
                .padding(20)
                .background(Palette.lavender.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
            Text(model.isConfigured ? "还没有可见的服务器" : "让你的服务器，出现在菜单栏")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Palette.primary)
            Text(model.isConfigured ? "请确认面板中已有节点，并检查当前连接是否有权查看。" : "连接自己的 Komari 面板，查看多台服务器的资源、历史和流量。")
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            Button(action: openSettings) {
                Label(model.isConfigured ? "检查面板连接" : "连接 Komari 面板", systemImage: "plus.circle.fill")
                    .padding(.horizontal, 15)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.lavender)
            if !model.isDemoMode {
                Button("先看看示例", action: model.useDemo)
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Palette.border).frame(height: 1)
            HStack(spacing: 7) {
                Circle()
                    .fill(footerStatusColor)
                    .frame(width: 5, height: 5)
                Text(model.isDemoMode ? "示例数据" : model.selectedSnapshot.map { "更新于 \(UIFormat.clock($0.timestamp))" } ?? "等待首次同步")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.secondary)
                Spacer()
                if let url = model.panelURL {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("打开面板", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.secondary)
                    .font(.system(size: 11))
                }
                Button("退出") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondary)
                    .padding(.leading, 12)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
    }

    private var footerStatusColor: Color {
        if model.lastError != nil { return Palette.amber }
        guard let snapshot = model.selectedSnapshot else { return Palette.secondary }
        return snapshot.isOnline && model.isSnapshotFresh(snapshot.timestamp) ? Palette.mint.opacity(0.7) : Palette.secondary
    }
}

private struct ServerPicker: View {
    let nodes: [ServerNode]
    let snapshots: [String: ServerSnapshot]
    let selectedID: String?
    let isSnapshotFresh: (Date) -> Bool
    let select: (String) -> Void

    private var onlineCount: Int {
        nodes.filter { node in
            guard let snapshot = snapshots[node.id] else { return false }
            return snapshot.isOnline && isSnapshotFresh(snapshot.timestamp)
        }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("我的服务器").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.secondary)
                Spacer()
                Text("\(onlineCount) / \(nodes.count) 在线").font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(nodes) { node in
                        Button { select(node.id) } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "server.rack").font(.system(size: 10))
                                Text(node.name).lineLimit(1)
                            }
                            .font(.system(size: 11, weight: selectedID == node.id ? .semibold : .regular))
                            .foregroundStyle(selectedID == node.id ? Palette.primary : Palette.secondary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 9)
                            .background(selectedID == node.id ? Palette.lavender.opacity(0.17) : Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(selectedID == node.id ? Palette.lavender.opacity(0.28) : Palette.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .help(node.name)
                        .accessibilityLabel("查看\(node.name)")
                        .accessibilityAddTraits(selectedID == node.id ? .isSelected : [])
                    }
                }
                .padding(1)
            }
        }
    }
}

private struct MetricCard: View {
    let title: String
    let symbol: String
    let value: String
    let detail: String
    let fraction: Double?
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(accent).font(.system(size: 12))
                Text(title).foregroundStyle(Palette.secondary).font(.system(size: 11, weight: .medium))
            }
            Text(value)
                .font(.system(size: 25, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Palette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            UsageBar(fraction: fraction, accent: accent)
            Text(detail)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .panelSurface()
        .accessibilityElement(children: .combine)
    }
}

private struct NetworkCard: View {
    let title: String
    let symbol: String
    let value: String
    let accent: Color

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: 31, height: 31)
                .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 10)).foregroundStyle(Palette.secondary)
                Text(value).font(.system(size: 19, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(Palette.primary)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity)
        .panelSurface()
        .accessibilityElement(children: .combine)
    }
}

private enum HistoryMetric: String, CaseIterable, Identifiable {
    case cpu = "CPU", memory = "内存", network = "网速"
    var id: String { rawValue }
}

private struct HistoryCard: View {
    let points: [HistoryPoint]
    let errorMessage: String?
    @LocalState private var metric: HistoryMetric = .cpu

    private var validPoints: [HistoryPoint] {
        points.filter { $0.cpuPercent.isFinite && $0.memoryPercent.isFinite && $0.uploadBytesPerSecond.isFinite && $0.downloadBytesPerSecond.isFinite }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private var chartColor: Color { metric == .memory ? Palette.blue : Palette.lavender }
    private var yMaximum: Double {
        guard metric == .network else { return 100 }
        return max(1, (validPoints.map { max($0.uploadBytesPerSecond, $0.downloadBytesPerSecond) }.max() ?? 0) / 1_000_000 * 1.15)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("资源趋势").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.primary)
                    Text("最近 1 小时").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                }
                Spacer()
                Picker("图表指标", selection: $metric) {
                    ForEach(HistoryMetric.allCases) { item in Text(item.rawValue).tag(item) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 174)
            }

            if validPoints.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: errorMessage == nil ? "chart.xyaxis.line" : "exclamationmark.circle").font(.system(size: 25, weight: .light))
                    Text(errorMessage == nil ? "暂无历史记录" : "历史记录暂不可用").font(.system(size: 12))
                    Text(errorMessage ?? "历史数据由 Komari 持续采集和保存。")
                        .font(.system(size: 10)).foregroundStyle(Palette.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
                .foregroundStyle(Palette.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 145)
            } else {
                chart
                    .frame(height: 145)
                    .accessibilityLabel(metric == .network ? "最近一小时上传与下载速度曲线" : "最近一小时\(metric.rawValue)使用率曲线")
                if errorMessage != nil {
                    Text("历史同步暂时失败，当前展示上一次成功获取的记录。")
                        .font(.system(size: 10)).foregroundStyle(Palette.amber)
                }
            }
        }
        .padding(16)
        .panelSurface()
    }

    private var chart: some View {
        Chart {
            ForEach(validPoints) { point in
                if metric == .network {
                    LineMark(x: .value("时间", point.timestamp), y: .value("速度", max(0, point.uploadBytesPerSecond) / 1_000_000), series: .value("方向", "上传"))
                        .foregroundStyle(by: .value("方向", "上传"))
                        .interpolationMethod(.linear)
                        .lineStyle(StrokeStyle(lineWidth: 1.8))
                    LineMark(x: .value("时间", point.timestamp), y: .value("速度", max(0, point.downloadBytesPerSecond) / 1_000_000), series: .value("方向", "下载"))
                        .foregroundStyle(by: .value("方向", "下载"))
                        .interpolationMethod(.linear)
                        .lineStyle(StrokeStyle(lineWidth: 1.8))
                } else {
                    let value = metric == .cpu ? point.cpuPercent : point.memoryPercent
                    AreaMark(x: .value("时间", point.timestamp), y: .value("使用率", min(100, max(0, value))))
                        .foregroundStyle(LinearGradient(colors: [chartColor.opacity(0.23), chartColor.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.linear)
                    LineMark(x: .value("时间", point.timestamp), y: .value("使用率", min(100, max(0, value))))
                        .foregroundStyle(chartColor)
                        .interpolationMethod(.linear)
                        .lineStyle(StrokeStyle(lineWidth: 1.8))
                }
            }
        }
        .chartYScale(domain: 0...yMaximum)
        .chartForegroundStyleScale(["上传": Palette.mint, "下载": Palette.blue])
        .chartLegend(metric == .network ? .visible : .hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.hour().minute())
                    .foregroundStyle(Palette.secondary)
                    .font(.system(size: 9))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4])).foregroundStyle(Palette.border)
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(metric == .network ? "\(UIFormat.compact(amount)) MB/s" : "\(Int(amount))%")
                            .foregroundStyle(Palette.secondary)
                            .font(.system(size: 9, design: .monospaced))
                    }
                }
            }
        }
    }
}

private struct TrafficCard: View {
    let usage: TrafficUsage
    let settings: TrafficSettings
    let openSettings: () -> Void

    private var periodConfirmed: Bool { settings.monthlyRotationConfirmed && usage.period != nil && usage.configurationIssue == nil }
    private var accent: Color {
        guard let fraction = usage.fractionUsed, periodConfirmed else { return Palette.lavender }
        return fraction >= 1 ? Palette.red : (fraction >= 0.8 ? Palette.amber : Palette.lavender)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "chart.pie").foregroundStyle(accent)
                    Text(usage.label).foregroundStyle(Palette.primary)
                }
                .font(.system(size: 12, weight: .semibold))
                Spacer()
                if let fraction = usage.fractionUsed, periodConfirmed {
                    Text(UIFormat.percent(fraction * 100))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(accent)
                } else {
                    Button("设置账期", action: openSettings)
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.lavender)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(UIFormat.traffic(usage.usedBytes))
                    .font(.system(size: 25, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Palette.primary)
                if let quota = usage.quotaBytes, periodConfirmed {
                    Text("/ \(UIFormat.traffic(quota))")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Palette.secondary)
                }
                Spacer()
                if let remaining = usage.remainingBytes, periodConfirmed {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("剩余额度").font(.system(size: 9)).foregroundStyle(Palette.secondary)
                        Text(UIFormat.traffic(remaining)).font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(Palette.mint)
                    }
                }
            }
            HStack(spacing: 14) {
                Label("上传 \(UIFormat.traffic(usage.uploadedBytes))", systemImage: "arrow.up")
                Label("下载 \(UIFormat.traffic(usage.downloadedBytes))", systemImage: "arrow.down")
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(Palette.secondary)
            if periodConfirmed {
                UsageBar(fraction: usage.fractionUsed, accent: accent, height: 7)
                HStack {
                    Text(settings.accounting.title)
                    Spacer()
                    if let period = usage.period {
                        Text("\(UIFormat.cycleDate(period.start, zone: settings.timeZoneIdentifier)) 起 · \(UIFormat.cycleDate(period.end, zone: settings.timeZoneIdentifier)) 重置")
                    }
                }
                .font(.system(size: 9))
                .foregroundStyle(Palette.secondary)
                Text("账期时区：\(settings.timeZoneIdentifier) · 用量以服务商账单为准")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.secondary.opacity(0.8))
            } else {
                Text(usage.configurationIssue ?? "确认 Agent 的每月流量重置日后，才会展示账期用量和剩余额度。")
                    .font(.system(size: 10))
                    .foregroundStyle(usage.configurationIssue == nil ? Palette.secondary : Palette.amber)
                    .fixedSize(horizontal: false, vertical: true)
                if let period = usage.period {
                    HStack {
                        Text(settings.accounting.title)
                        Spacer()
                        Text("\(UIFormat.cycleDate(period.end, zone: settings.timeZoneIdentifier)) 重置 · \(settings.timeZoneIdentifier)")
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.secondary)
                }
            }
        }
        .padding(16)
        .panelSurface()
    }
}

private struct UsageBar: View {
    let fraction: Double?
    let accent: Color
    var height: CGFloat = 4

    private var safeFraction: Double {
        guard let fraction, fraction.isFinite else { return 0 }
        return min(1, max(0, fraction))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.06))
                Capsule()
                    .fill(LinearGradient(colors: [accent.opacity(0.7), accent], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, geometry.size.width * safeFraction))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

private struct NoticeView: View {
    let symbol: String
    let title: String
    let message: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(color).padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.primary)
                Text(message).font(.system(size: 10)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .background(color.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.13), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

private struct HeaderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(configuration.isPressed ? Palette.primary : Palette.secondary)
            .padding(8)
            .background(configuration.isPressed ? Color.white.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct PanelSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Palette.border, lineWidth: 1))
    }
}

private extension View {
    func panelSurface() -> some View { modifier(PanelSurface()) }
}
