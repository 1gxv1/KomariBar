import Foundation

public enum KomariClientError: Error, LocalizedError, Equatable, Sendable {
    case invalidURL
    case insecureCredentialTransport
    case invalidCredential
    case authenticationRequired
    case permissionDenied
    case unsupportedInterface
    case unexpectedHTTPStatus(Int)
    case invalidResponse
    case remoteFailure(Int)
    case connectionFailed
    case timedOut
    case redirectRejected

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "面板地址无效，请填写不含账号、查询参数或片段的 HTTP(S) 地址。"
        case .insecureCredentialTransport: return "带认证凭据的远程连接需要使用 HTTPS。"
        case .invalidCredential: return "认证凭据格式无效。"
        case .authenticationRequired: return "面板要求登录，请检查 API Key 或站点访问设置。"
        case .permissionDenied: return "当前身份没有读取此监控数据的权限。"
        case .unsupportedInterface: return "此 Komari 版本不支持所需监控接口，请使用兼容版本。"
        case .unexpectedHTTPStatus(let code): return "面板返回 HTTP \(code)，请检查地址和反向代理设置。"
        case .invalidResponse: return "面板返回的数据格式不符合 Komari 监控接口约定。"
        case .remoteFailure(let code): return "Komari 监控请求失败（错误代码 \(code)）。"
        case .connectionFailed: return "无法连接 Komari 面板，请检查网络和面板地址。"
        case .timedOut: return "连接 Komari 面板超时，请稍后重试。"
        case .redirectRejected: return "面板请求跳转到了其他地址，请直接填写最终面板地址。"
        }
    }
}

/// Read-only Komari 1.6.1 JSON-RPC client. Credentials are never placed in
/// query strings or echoed in errors; each request rejects cross-origin redirects.
public struct KomariClient: Sendable {
    private let connection: KomariConnection
    private let session: URLSession

    public init(connection: KomariConnection, session: URLSession = .shared) {
        self.connection = connection
        self.session = session
    }

    public func fetchNodes() async throws -> [ServerNode] {
        let collection: NodeCollection = try await call("common:getNodes", params: EmptyParams())
        return collection.nodes.sorted { lhs, rhs in
            if lhs.group != rhs.group { return lhs.group.localizedStandardCompare(rhs.group) == .orderedAscending }
            if lhs.name != rhs.name { return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending }
            return lhs.id < rhs.id
        }
    }

    public func fetchSnapshots(nodeIDs: [String]) async throws -> [String: ServerSnapshot] {
        guard !nodeIDs.isEmpty else { return [:] }
        let records: [String: RecordDTO] = try await call("common:getNodesLatestStatus", params: NodesParams(uuids: nodeIDs))
        let requested = Set(nodeIDs)
        return records.reduce(into: [:]) { result, item in
            guard requested.contains(item.key) else { return }
            result[item.key] = item.value.snapshot(nodeID: item.key)
        }
    }

    public func fetchHistory(nodeID: String, hours: Int = 1) async throws -> [HistoryPoint] {
        let response: HistoryResponse = try await call(
            "common:getRecords",
            params: HistoryParams(uuid: nodeID, hours: Swift.max(1, Swift.min(hours, 168)))
        )
        let points = (response.records?[nodeID] ?? []).compactMap { record -> HistoryPoint? in
            guard record.client == nil || record.client == nodeID,
                  let timestamp = record.validTimestamp else { return nil }
            let memoryTotal = clean(record.ramTotal)
            return HistoryPoint(
                timestamp: timestamp,
                cpuPercent: Swift.min(100, clean(record.cpu)),
                memoryPercent: memoryTotal > 0 ? Swift.min(100, clean(record.ram) / memoryTotal * 100) : 0,
                uploadBytesPerSecond: clean(record.netOut),
                downloadBytesPerSecond: clean(record.netIn)
            )
        }
        // A date is the public HistoryPoint identity; collapse duplicate buckets.
        return Dictionary(points.map { ($0.timestamp, $0) }, uniquingKeysWith: { _, newest in newest })
            .values.sorted { $0.timestamp < $1.timestamp }
    }

    public func fetchVersion() async throws -> String {
        let info: VersionInfo = try await call("common:getVersion", params: EmptyParams())
        guard !info.version.isEmpty else { throw KomariClientError.invalidResponse }
        return info.version
    }

    private func call<Params: Encodable, Result: Decodable>(_ method: String, params: Params) async throws -> Result {
        let endpoint = try validatedEndpoint()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let key = trimmedKey { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONEncoder().encode(RPCRequest(method: method, params: params))

        let redirectGuard = SameOriginRedirectGuard(origin: endpoint)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: redirectGuard)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw error.code == .timedOut ? KomariClientError.timedOut : KomariClientError.connectionFailed
        } catch {
            throw KomariClientError.connectionFailed
        }
        if redirectGuard.didRejectRedirect { throw KomariClientError.redirectRejected }
        guard let http = response as? HTTPURLResponse else { throw KomariClientError.invalidResponse }
        switch http.statusCode {
        case 200..<300: break
        case 401: throw KomariClientError.authenticationRequired
        case 403: throw KomariClientError.permissionDenied
        case 404: throw KomariClientError.unsupportedInterface
        case 300..<400: throw KomariClientError.redirectRejected
        default: throw KomariClientError.unexpectedHTTPStatus(http.statusCode)
        }
        let envelope: RPCEnvelope<Result>
        do { envelope = try JSONDecoder().decode(RPCEnvelope<Result>.self, from: data) }
        catch { throw KomariClientError.invalidResponse }
        guard envelope.jsonrpc == "2.0" else { throw KomariClientError.invalidResponse }
        if let error = envelope.error {
            switch error.code {
            case -32601, -32050: throw KomariClientError.unsupportedInterface
            case -32040: throw KomariClientError.authenticationRequired
            case -32041: throw KomariClientError.permissionDenied
            default: throw KomariClientError.remoteFailure(error.code)
            }
        }
        guard let result = envelope.result else { throw KomariClientError.invalidResponse }
        return result
    }

    private var trimmedKey: String? {
        guard let key = connection.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return nil }
        return key
    }

    private func validatedEndpoint() throws -> URL {
        let url = connection.baseURL
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.port.map({ (1...65535).contains($0) }) ?? true else {
            throw KomariClientError.invalidURL
        }
        if let key = trimmedKey {
            guard !key.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw KomariClientError.invalidCredential
            }
            let normalizedHost = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            let isLoopback = ["localhost", "127.0.0.1", "::1"].contains(normalizedHost)
            guard scheme == "https" || isLoopback else { throw KomariClientError.insecureCredentialTransport }
        }
        return url.appendingPathComponent("api").appendingPathComponent("rpc2")
    }
}

private struct RPCRequest<Params: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let id = 1
    let method: String
    let params: Params
}

private struct RPCEnvelope<Result: Decodable>: Decodable {
    let jsonrpc: String?
    let result: Result?
    let error: RPCFailure?
}

private struct RPCFailure: Decodable { let code: Int }
private struct EmptyParams: Encodable {}
private struct NodesParams: Encodable { let uuids: [String] }
private struct VersionInfo: Decodable { let version: String }
private struct HistoryParams: Encodable {
    let uuid: String
    let hours: Int
    let type = "load"
    let load_type = "all"
    let maxCount = 240
}
private struct HistoryResponse: Decodable { let records: [String: [RecordDTO]]? }

private struct NodeCollection: Decodable {
    let nodes: [ServerNode]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let map = try container.decode([String: NodeDTO].self)
        nodes = map.compactMap { key, value in
            let id = value.uuid.flatMap { $0.isEmpty ? nil : $0 } ?? key
            guard !id.isEmpty else { return nil }
            return value.node(id: id)
        }
    }
}

private struct NodeDTO: Decodable {
    let uuid: String?
    let name: String?
    let group: String?
    let region: String?
    let cpuName: String?
    let cpuCores: Int?
    let os: String?
    let memTotal: Double?
    let diskTotal: Double?
    let trafficLimit: Double?
    let trafficLimitType: String?

    enum CodingKeys: String, CodingKey {
        case uuid, name, group, region, os
        case cpuName = "cpu_name", cpuCores = "cpu_cores", memTotal = "mem_total", diskTotal = "disk_total"
        case trafficLimit = "traffic_limit", trafficLimitType = "traffic_limit_type"
    }

    func node(id: String) -> ServerNode {
        let accounting: TrafficAccounting
        switch trafficLimitType {
        case "sum": accounting = .sum
        case "min": accounting = .min
        case "up": accounting = .upload
        case "down": accounting = .download
        default: accounting = .max
        }
        let quota = trafficLimit.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        return ServerNode(
            id: id, name: name.flatMap { $0.isEmpty ? nil : $0 } ?? "未命名服务器",
            group: group ?? "", region: region ?? "", cpuName: cpuName ?? "", cpuCores: Swift.max(0, cpuCores ?? 0),
            os: os ?? "", memoryTotalBytes: clean(memTotal), diskTotalBytes: clean(diskTotal),
            trafficQuotaBytes: quota, trafficAccounting: accounting
        )
    }
}

private struct RecordDTO: Decodable {
    let client: String?
    let time: String?
    let online: Bool?
    let cpu: Double?
    let ram: Double?
    let ramTotal: Double?
    let disk: Double?
    let diskTotal: Double?
    let netIn: Double?
    let netOut: Double?
    let netTotalUp: Double?
    let netTotalDown: Double?
    let uptime: Double?

    enum CodingKeys: String, CodingKey {
        case client, time, online, cpu, ram, disk, uptime
        case ramTotal = "ram_total", diskTotal = "disk_total", netIn = "net_in", netOut = "net_out"
        case netTotalUp = "net_total_up", netTotalDown = "net_total_down"
    }

    var validTimestamp: Date? {
        guard let time else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let simple = ISO8601DateFormatter()
        guard let date = fractional.date(from: time) ?? simple.date(from: time), date.timeIntervalSince1970 > 0 else { return nil }
        return date
    }

    func snapshot(nodeID: String) -> ServerSnapshot {
        let timestamp = validTimestamp
        return ServerSnapshot(
            nodeID: nodeID, timestamp: timestamp ?? .distantPast,
            isOnline: online == true && timestamp != nil,
            cpuPercent: Swift.min(100, clean(cpu)), memoryUsedBytes: clean(ram), memoryTotalBytes: clean(ramTotal),
            diskUsedBytes: clean(disk), diskTotalBytes: clean(diskTotal),
            uploadBytesPerSecond: clean(netOut), downloadBytesPerSecond: clean(netIn),
            uploadedBytes: clean(netTotalUp), downloadedBytes: clean(netTotalDown), uptime: clean(uptime)
        )
    }
}

private func clean(_ number: Double?) -> Double {
    guard let number, number.isFinite else { return 0 }
    return Swift.max(0, number)
}

private final class SameOriginRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let origin: URL
    private let lock = NSLock()
    private var rejected = false

    init(origin: URL) { self.origin = origin }

    var didRejectRedirect: Bool {
        lock.lock()
        defer { lock.unlock() }
        return rejected
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let target = request.url, Self.hasSameOrigin(origin, target), target.user == nil, target.password == nil else {
            lock.lock()
            rejected = true
            lock.unlock()
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    private static func hasSameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        func port(_ url: URL) -> Int? { url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80) }
        return lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && port(lhs) == port(rhs)
    }
}
