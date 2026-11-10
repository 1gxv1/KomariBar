import Combine
import Foundation
import KomariBarCore

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var nodes: [ServerNode] = []
    @Published private(set) var snapshots: [String: ServerSnapshot] = [:]
    @Published private(set) var history: [HistoryPoint] = []
    @Published private(set) var selectedNodeID: String?
    @Published private(set) var isDemoMode = true
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?
    @Published private(set) var historyError: String?
    @Published private(set) var lastSuccessfulRefresh: Date?
    @Published private(set) var configuredURLString: String
    @Published private(set) var hasSavedAPIKey = false
    @Published private(set) var refreshIntervalSeconds: TimeInterval
    @Published private var savedTrafficSettings: [String: TrafficSettings] = [:]

    private let defaults: UserDefaults
    private var client: KomariClient?
    private var pollingTask: Task<Void, Never>?
    private var historyTask: Task<Void, Never>?
    private var generation = 0
    private var lastHistoryRefresh = Date.distantPast
    private var lastNodesRefresh = Date.distantPast

    var selectedNode: ServerNode? { nodes.first { $0.id == selectedNodeID } }
    var selectedSnapshot: ServerSnapshot? { selectedNodeID.flatMap { snapshots[$0] } }
    var panelURL: URL? { isDemoMode ? nil : Self.validatedURL(configuredURLString) }
    var isConfigured: Bool { client != nil }
    var trafficSettings: TrafficSettings {
        if let value = savedTrafficSettings[trafficSettingsKey] { return value }
        return TrafficSettings(
            monthlyRotationConfirmed: isDemoMode,
            resetDay: 15,
            timeZoneIdentifier: "UTC",
            quotaBytes: selectedNode?.trafficQuotaBytes,
            accounting: selectedNode?.trafficAccounting ?? .max,
            statisticsStartedAt: isDemoMode ? Date(timeIntervalSince1970: 0) : nil
        )
    }
    var selectedTraffic: TrafficUsage? {
        guard let snapshot = selectedSnapshot else { return nil }
        return TrafficUsage.calculate(snapshot: snapshot, settings: trafficSettings)
    }
    var menuBarText: String {
        guard let snapshot = selectedSnapshot else { return "KomariBar" }
        if isDemoMode { return "示例 \(Int(snapshot.cpuPercent))%" }
        if !snapshot.isOnline { return "节点离线" }
        if !isSnapshotFresh(snapshot.timestamp) { return "数据过期" }
        return "CPU \(Int(snapshot.cpuPercent))%"
    }
    private var trafficSettingsKey: String {
        "\(isDemoMode ? "demo" : configuredURLString)|\(selectedNodeID ?? "")"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        configuredURLString = defaults.string(forKey: "panelURL") ?? ""
        refreshIntervalSeconds = ClientPreferences(refreshIntervalSeconds: defaults.double(forKey: "refreshIntervalSeconds")).refreshIntervalSeconds
        if let data = defaults.data(forKey: "trafficSettings"),
           let settings = try? JSONDecoder().decode([String: TrafficSettings].self, from: data) {
            savedTrafficSettings = settings
        }
        if !CommandLine.arguments.contains("--demo"), let url = Self.validatedURL(configuredURLString) {
            do {
                let key = try CredentialStore.read(account: url.absoluteString)
                hasSavedAPIKey = !(key ?? "").isEmpty
                client = KomariClient(connection: KomariConnection(baseURL: url, apiKey: key))
                isDemoMode = false
                selectedNodeID = defaults.string(forKey: "selectedNodeID")
            } catch {
                loadDemo()
                lastError = error.localizedDescription
            }
        } else {
            loadDemo()
        }
    }

    func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                guard let interval = self?.refreshIntervalSeconds else { break }
                do { try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000)) } catch { break }
            }
        }
    }

    func setRefreshInterval(_ seconds: TimeInterval) {
        let interval = ClientPreferences(refreshIntervalSeconds: seconds).refreshIntervalSeconds
        guard refreshIntervalSeconds != interval else { return }
        refreshIntervalSeconds = interval
        defaults.set(interval, forKey: "refreshIntervalSeconds")
        guard pollingTask != nil else { return }
        // Invalidate any old request before immediately starting the new schedule.
        generation += 1
        pollingTask?.cancel()
        pollingTask = nil
        historyTask?.cancel()
        lastHistoryRefresh = .distantPast
        isRefreshing = false
        startPolling()
    }

    func isSnapshotFresh(_ timestamp: Date) -> Bool {
        ClientPreferences(refreshIntervalSeconds: refreshIntervalSeconds).isSnapshotFresh(timestamp)
    }

    func refresh() async {
        guard !isRefreshing else { return }
        if isDemoMode {
            snapshots = DemoData.snapshots()
            history = DemoData.history(for: selectedNodeID ?? DemoData.nodes[0].id)
            lastSuccessfulRefresh = Date()
            return
        }
        guard let client else { return }
        isRefreshing = true
        let requestGeneration = generation
        defer { if generation == requestGeneration { isRefreshing = false } }
        do {
            if nodes.isEmpty || Date().timeIntervalSince(lastNodesRefresh) > 60 {
                let fetchedNodes = try await client.fetchNodes()
                guard generation == requestGeneration else { return }
                nodes = fetchedNodes
                lastNodesRefresh = Date()
                if !nodes.contains(where: { $0.id == selectedNodeID }) {
                    selectedNodeID = nodes.first?.id
                    history = []
                    lastHistoryRefresh = .distantPast
                }
            }
            if nodes.isEmpty {
                snapshots = [:]
                history = []
                lastError = nil
                lastSuccessfulRefresh = Date()
                return
            }
            let latest = try await client.fetchSnapshots(nodeIDs: nodes.map(\.id))
            guard generation == requestGeneration else { return }
            invalidateRegressedCalibrations(latest: latest)
            snapshots = latest
            lastError = nil
            lastSuccessfulRefresh = Date()
            if Date().timeIntervalSince(lastHistoryRefresh) > 60 {
                requestHistory()
            }
        } catch {
            guard generation == requestGeneration else { return }
            lastError = Self.safeError(error)
        }
    }

    func selectNode(_ id: String) {
        guard nodes.contains(where: { $0.id == id }), selectedNodeID != id else { return }
        selectedNodeID = id
        history = []
        historyError = nil
        lastHistoryRefresh = .distantPast
        if isDemoMode {
            history = DemoData.history(for: id)
        } else {
            defaults.set(id, forKey: "selectedNodeID")
            requestHistory()
        }
    }

    func useDemo() {
        generation += 1
        historyTask?.cancel()
        isRefreshing = false
        loadDemo()
    }

    func saveConnection(baseURL: String, apiKey: String, keepSavedKey: Bool) async -> Bool {
        guard let url = Self.validatedURL(baseURL) else {
            lastError = "请输入完整的 HTTP 或 HTTPS 面板地址，地址中不要包含账号、令牌、查询参数或片段。"
            return false
        }
        let requestGeneration = generation
        do {
            let key: String
            if keepSavedKey, apiKey.isEmpty, url.absoluteString == configuredURLString {
                key = try CredentialStore.read(account: url.absoluteString) ?? ""
            } else {
                key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let loopback = ["localhost", "127.0.0.1", "::1"].contains(url.host?.lowercased() ?? "")
            if !key.isEmpty, url.scheme?.lowercased() != "https", !loopback {
                lastError = "使用 API Key 时，请使用 HTTPS 面板地址，或通过 SSH 隧道连接本机地址。"
                return false
            }
            let candidate = KomariClient(connection: KomariConnection(baseURL: url, apiKey: key.isEmpty ? nil : key))
            let fetchedNodes = try await candidate.fetchNodes()
            guard generation == requestGeneration else { return false }
            try CredentialStore.save(key, account: url.absoluteString)
            generation += 1
            historyTask?.cancel()
            client = candidate
            configuredURLString = url.absoluteString
            hasSavedAPIKey = !key.isEmpty
            defaults.set(configuredURLString, forKey: "panelURL")
            isDemoMode = false
            nodes = fetchedNodes
            selectedNodeID = fetchedNodes.first?.id
            snapshots = [:]
            history = []
            lastError = nil
            historyError = nil
            lastSuccessfulRefresh = nil
            lastHistoryRefresh = .distantPast
            lastNodesRefresh = Date()
            isRefreshing = false
            await refresh()
            return true
        } catch {
            guard generation == requestGeneration else { return false }
            lastError = Self.safeError(error)
            return false
        }
    }

    func resumeSavedConnection() async {
        _ = await saveConnection(baseURL: configuredURLString, apiKey: "", keepSavedKey: true)
    }

    func updateTrafficSettings(_ settings: TrafficSettings) {
        savedTrafficSettings[trafficSettingsKey] = settings
        if let data = try? JSONEncoder().encode(savedTrafficSettings) {
            defaults.set(data, forKey: "trafficSettings")
        }
    }

    func createTrafficCalibration(providerUsedBytes: Double, providerUploadedBytes: Double, providerDownloadedBytes: Double, source: String) throws {
        guard isConfigured, !isDemoMode, let snapshot = selectedSnapshot else {
            throw TrafficCalibrationError.snapshotUnavailable
        }
        var settings = trafficSettings
        settings.calibration = try TrafficCalibration.create(
            snapshot: snapshot, settings: settings,
            providerUsedBytes: providerUsedBytes,
            providerUploadedBytes: providerUploadedBytes,
            providerDownloadedBytes: providerDownloadedBytes,
            source: source,
            maximumSnapshotAge: ClientPreferences(refreshIntervalSeconds: refreshIntervalSeconds).staleDataThreshold
        )
        updateTrafficSettings(settings)
    }

    func removeTrafficCalibration() {
        var settings = trafficSettings
        settings.calibration = nil
        updateTrafficSettings(settings)
    }

    private func invalidateRegressedCalibrations(latest: [String: ServerSnapshot]) {
        var changed = false
        for (nodeID, snapshot) in latest {
            let key = "\(configuredURLString)|\(nodeID)"
            guard var settings = savedTrafficSettings[key], var calibration = settings.calibration else { continue }
            if calibration.invalidateIfCountersRegressed(snapshot: snapshot, previousSnapshot: snapshots[nodeID]) {
                settings.calibration = calibration
                savedTrafficSettings[key] = settings
                changed = true
            }
        }
        if changed, let data = try? JSONEncoder().encode(savedTrafficSettings) {
            defaults.set(data, forKey: "trafficSettings")
        }
    }

    func clearConnection() {
        do {
            if let url = Self.validatedURL(configuredURLString) {
                try CredentialStore.save("", account: url.absoluteString)
            }
            defaults.removeObject(forKey: "panelURL")
            defaults.removeObject(forKey: "selectedNodeID")
            configuredURLString = ""
            hasSavedAPIKey = false
            client = nil
            useDemo()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func requestHistory() {
        guard let client, let id = selectedNodeID else { return }
        historyTask?.cancel()
        let requestGeneration = generation
        // Failed history calls use the same retry interval as successful calls.
        lastHistoryRefresh = Date()
        historyTask = Task { [weak self] in
            do {
                let points = try await client.fetchHistory(nodeID: id, hours: 1)
                guard let self, !Task.isCancelled, self.generation == requestGeneration, self.selectedNodeID == id else { return }
                self.history = points
                self.historyError = nil
            } catch {
                guard let self, !Task.isCancelled, self.generation == requestGeneration, self.selectedNodeID == id else { return }
                self.historyError = "历史记录暂不可用：\(Self.safeError(error))"
            }
        }
    }

    private func loadDemo() {
        isDemoMode = true
        nodes = DemoData.nodes
        selectedNodeID = DemoData.nodes[0].id
        snapshots = DemoData.snapshots()
        history = DemoData.history(for: DemoData.nodes[0].id)
        lastError = nil
        historyError = nil
        lastSuccessfulRefresh = Date()
    }

    private static func validatedURL(_ value: String) -> URL? {
        guard var components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else { return nil }
        components.scheme = components.scheme?.lowercased()
        components.host = host.lowercased()
        while components.path.hasSuffix("/") { components.path.removeLast() }
        return components.url
    }

    private static func safeError(_ error: Error) -> String {
        if let value = error as? LocalizedError, let description = value.errorDescription { return description }
        return "连接失败，请检查面板地址、网络和认证设置。"
    }
}
