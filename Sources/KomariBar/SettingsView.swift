import KomariBarCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppState
    @LocalState private var tab = 0
    @LocalState private var baseURL = ""
    @LocalState private var apiKey = ""
    @LocalState private var keepSavedKey = true
    @LocalState private var isSaving = false
    @LocalState private var connectionMessage: String?
    @LocalState private var rotationConfirmed = false
    @LocalState private var resetDay = 1
    @LocalState private var timeZoneIdentifier = "UTC"
    @LocalState private var quotaGB = ""
    @LocalState private var accounting: TrafficAccounting = .max
    @LocalState private var statisticsStartConfirmed = false
    @LocalState private var statisticsStartedAt = Date()
    @LocalState private var trafficMessage: String?

    var body: some View {
        TabView(selection: $tab) {
            connectionForm.tabItem { Label("连接面板", systemImage: "network") }.tag(0)
            trafficForm.tabItem { Label("流量账期", systemImage: "chart.pie") }.tag(1)
            aboutView.tabItem { Label("关于", systemImage: "info.circle") }.tag(2)
        }
        .padding(18)
        .frame(width: 550, height: 620)
        .preferredColorScheme(.dark)
        .onAppear {
            baseURL = model.configuredURLString
            loadTrafficSettings()
        }
        .onChange(of: model.selectedNodeID) { _ in loadTrafficSettings() }
        .onChange(of: model.isDemoMode) { _ in loadTrafficSettings() }
        .onChange(of: model.configuredURLString) { _ in loadTrafficSettings() }
    }

    private var connectionForm: some View {
        Form {
            Section {
                TextField("面板地址", text: $baseURL, prompt: Text("https://komari.example.com"))
                    .autocorrectionDisabled()
                SecureField("管理员 API Key（可选）", text: $apiKey)
                    .disabled(keepSavedKey && model.hasSavedAPIKey && baseURL == model.configuredURLString)
                    .privacySensitive()
                if model.hasSavedAPIKey {
                    Toggle("使用已保存在钥匙串中的 API Key", isOn: $keepSavedKey)
                }
                Text("公开面板可留空。私有面板需要管理员 API Key；该 Key 拥有管理员权限，本客户端仅调用监控接口。")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("API Key 保存到这台 Mac 的钥匙串。使用 Key 时请连接 HTTPS，或通过 SSH 隧道使用本机地址。")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Komari 连接")
            }
            Section {
                Picker("刷新间隔", selection: Binding(get: { model.refreshIntervalSeconds }, set: { model.setRefreshInterval($0) })) {
                    ForEach(ClientPreferences.supportedRefreshIntervals, id: \.self) { interval in
                        Text("每 \(Int(interval)) 秒").tag(interval)
                    }
                }
                .disabled(isSaving)
                Text("修改后立即生效并保存。仅调整这台 Mac 更新服务器状态的频率，服务器端仍按原频率采集。")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("自动刷新")
            }
            if let error = model.lastError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.callout)
                }
            }
            if let connectionMessage {
                Text(connectionMessage).foregroundStyle(.green).font(.callout)
            }
            Section {
                HStack {
                    Button(isSaving ? "正在连接…" : "连接并保存") {
                        Task {
                            isSaving = true
                            connectionMessage = nil
                            if await model.saveConnection(baseURL: baseURL, apiKey: apiKey, keepSavedKey: keepSavedKey) {
                                apiKey = ""
                                keepSavedKey = true
                                baseURL = model.configuredURLString
                                connectionMessage = model.lastError == nil ? "已连接，可以关闭设置查看监控。" : "配置已保存，首轮监控同步尚未完成。"
                            }
                            isSaving = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving || baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if isSaving { ProgressView().controlSize(.small) }
                    Spacer()
                }
                if model.isConfigured && !model.isDemoMode {
                    Button("打开监控窗口") { AppWindows.shared.showDashboard(model: model) }
                }
                Button("查看示例界面") { model.useDemo(); connectionMessage = "当前显示示例数据。" }
                    .disabled(isSaving)
                if !model.configuredURLString.isEmpty {
                    if model.isDemoMode {
                        Button("恢复已保存的面板连接") {
                            Task {
                                isSaving = true
                                connectionMessage = nil
                                await model.resumeSavedConnection()
                                if !model.isDemoMode {
                                    connectionMessage = model.lastError == nil ? "已恢复面板连接。" : "已恢复配置，监控同步尚未完成。"
                                }
                                isSaving = false
                            }
                        }.disabled(isSaving)
                    }
                    Button("移除已保存的连接", role: .destructive) {
                        model.clearConnection()
                        baseURL = model.configuredURLString
                        connectionMessage = model.configuredURLString.isEmpty ? "已移除连接和对应认证凭据。" : nil
                    }.disabled(isSaving)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var trafficForm: some View {
        Form {
            Section {
                Picker("服务器", selection: Binding(get: { model.selectedNodeID ?? "" }, set: { model.selectNode($0) })) {
                    ForEach(model.nodes) { Text($0.name).tag($0.id) }
                }
                if model.isDemoMode {
                    Label("这里修改的是示例节点的设置。", systemImage: "sparkles")
                        .font(.caption).foregroundStyle(.purple)
                }
            }
            Section {
                Toggle("我已确认 Agent 启用了按月重置流量", isOn: $rotationConfirmed)
                Text("未确认时仅显示累计流量，不把服务器启动以来的累计量标成本期用量。这里的设置不会修改服务器上的 Agent。")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Picker("每月重置日", selection: $resetDay) {
                    ForEach(1...31, id: \.self) { Text("每月 \($0) 日").tag($0) }
                }
                TextField("Agent 所用时区", text: $timeZoneIdentifier, prompt: Text("UTC 或 Asia/Shanghai"))
                    .autocorrectionDisabled()
                Text("重置日在该时区的 00:00 生效。当月没有所选日期时，按 Komari 的行为顺延到次月 1 日。时区和日期应与 Agent 一致。")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("账期口径")
            }
            Section {
                Toggle("已确认 Agent 的统计开始时间", isOn: $statisticsStartConfirmed)
                if statisticsStartConfirmed {
                    DatePicker("开始统计时间", selection: $statisticsStartedAt, displayedComponents: [.date, .hourAndMinute])
                        .environment(\.timeZone, TimeZone(identifier: timeZoneIdentifier) ?? .current)
                }
                Text("填写 Agent 启用月重置或重新开始统计的实际时间，日期按上方 Agent 时区显示。未确认时不估算剩余额度；账期中途开始的首期只显示已记录用量，下一次重置后再显示完整账期预算。")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("数据完整性")
            }
            Section {
                TextField("流量额度（GB，留空为不设置）", text: $quotaGB)
                Picker("计量方式", selection: $accounting) {
                    ForEach(TrafficAccounting.allCases) { Text($0.title).tag($0) }
                }
                Text("1 GB = 1,000,000,000 字节。额度进度为参考值，供应商后台是最终依据。")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("套餐额度")
            }
            if let trafficMessage {
                Text(trafficMessage).font(.callout).foregroundStyle(.secondary)
            }
            Button("保存当前服务器的设置", action: saveTrafficSettings)
                .buttonStyle(.borderedProminent)
                .disabled(model.selectedNode == nil)
        }
        .formStyle(.grouped)
    }

    private var aboutView: some View {
        VStack(spacing: 18) {
            Image(systemName: "server.rack").font(.system(size: 44)).foregroundStyle(.purple)
            Text("KomariBar").font(.largeTitle.bold())
            Text("原生 macOS 菜单栏服务器监控").foregroundStyle(.secondary)
            Text("版本 0.1.0 · 开发预览").font(.callout).foregroundStyle(.secondary)
            Divider()
            Text("连接独立部署的 Komari，通过官方接口查看多台服务器的资源状态、历史曲线和流量用量。Mac 关机期间，数据采集仍由服务器端的 Komari 负责。")
                .font(.callout).multilineTextAlignment(.center)
            Text("KomariBar 是独立的第三方开源客户端，与 Komari 官方没有隶属关系。")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Link("项目源码与反馈", destination: URL(string: "https://github.com/1gxv1/KomariBar")!)
            Spacer()
        }
        .padding(30)
    }

    private func loadTrafficSettings() {
        let value = model.trafficSettings
        rotationConfirmed = value.monthlyRotationConfirmed
        resetDay = min(31, max(1, value.resetDay))
        timeZoneIdentifier = value.timeZoneIdentifier
        quotaGB = value.quotaBytes.map { String(format: "%g", $0 / 1_000_000_000) } ?? ""
        accounting = value.accounting
        statisticsStartConfirmed = value.statisticsStartedAt != nil
        statisticsStartedAt = value.statisticsStartedAt ?? Date()
        trafficMessage = nil
    }

    private func saveTrafficSettings() {
        let zone = timeZoneIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TimeZone(identifier: zone) != nil else {
            trafficMessage = "时区无效，请填写 UTC 或 Asia/Shanghai 这样的时区名称。"
            return
        }
        guard !statisticsStartConfirmed || statisticsStartedAt <= Date() else {
            trafficMessage = "统计开始时间不能晚于当前时间。"
            return
        }
        let quotaText = quotaGB.trimmingCharacters(in: .whitespacesAndNewlines)
        var bytes: Double?
        if !quotaText.isEmpty {
            guard let amount = Double(quotaText), amount.isFinite, amount > 0,
                  (amount * 1_000_000_000).isFinite else {
                trafficMessage = "额度请输入大于 0 的 GB 数值，或留空。"
                return
            }
            bytes = amount * 1_000_000_000
        }
        model.updateTrafficSettings(TrafficSettings(monthlyRotationConfirmed: rotationConfirmed, resetDay: resetDay, timeZoneIdentifier: zone, quotaBytes: bytes, accounting: accounting, statisticsStartedAt: statisticsStartConfirmed ? statisticsStartedAt : nil))
        trafficMessage = "已保存。请确保这些设置与 Agent 和供应商的统计口径一致。"
    }
}
