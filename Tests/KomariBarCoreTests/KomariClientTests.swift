import Foundation
import Network
import XCTest
@testable import KomariBarCore

final class KomariClientTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RPCURLProtocol.self]
        session = URLSession(configuration: configuration)
    }

    override func tearDown() {
        session.invalidateAndCancel()
        RPCURLProtocol.setHandler(nil)
        super.tearDown()
    }

    func testNodesDecodeOfficialMapShapeAndPreservePanelSubpath() async throws {
        RPCURLProtocol.setHandler { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.invalid/monitor/api/rpc2")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertEqual(try rpcBody(request)["method"] as? String, "common:getNodes")
            return .json(#"{"jsonrpc":"2.0","id":1,"result":{"node-a":{"uuid":"node-a","name":"东京","group":"生产","cpu_cores":2,"mem_total":2147483648,"disk_total":20000000000,"traffic_limit":1000000000000,"traffic_limit_type":"sum"},"node-b":{"name":"备用","cpu_name":null,"cpu_cores":null,"mem_total":null,"traffic_limit":0,"traffic_limit_type":"min"}}}"#)
        }
        let nodes = try await makeClient(path: "/monitor/").fetchNodes()
        let nodeA = try XCTUnwrap(nodes.first { $0.id == "node-a" })
        XCTAssertEqual(nodeA.memoryTotalBytes, 2_147_483_648)
        XCTAssertEqual(nodeA.trafficQuotaBytes, 1_000_000_000_000)
        XCTAssertEqual(nodeA.trafficAccounting, .sum)
        let nodeB = try XCTUnwrap(nodes.first { $0.id == "node-b" })
        XCTAssertEqual(nodeB.cpuCores, 0)
        XCTAssertEqual(nodeB.cpuName, "")
        XCTAssertNil(nodeB.trafficQuotaBytes)
        XCTAssertEqual(nodeB.trafficAccounting, .min)
    }

    func testSnapshotMapsUnitsAndExplicitOfflineState() async throws {
        RPCURLProtocol.setHandler { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-key")
            let body = try rpcBody(request)
            XCTAssertEqual(body["method"] as? String, "common:getNodesLatestStatus")
            XCTAssertEqual((body["params"] as? [String: Any])?["uuids"] as? [String], ["node-a", "node-b"])
            return .json(#"{"jsonrpc":"2.0","id":1,"result":{"node-a":{"client":"node-a","time":"2026-10-27T12:00:00.123456Z","online":true,"cpu":12.5,"ram":400,"ram_total":2000,"disk":4000,"disk_total":20000,"net_in":300,"net_out":200,"net_total_up":900,"net_total_down":500,"uptime":86400},"node-b":{"time":"2026-10-27T11:00:00Z","online":false,"cpu":null,"ram":null},"unrequested":{"time":"2026-10-27T12:00:00Z","online":true}}}"#)
        }
        let snapshots = try await makeClient(key: "fixture-key").fetchSnapshots(nodeIDs: ["node-a", "node-b"])
        XCTAssertEqual(snapshots.count, 2)
        let online = try XCTUnwrap(snapshots["node-a"])
        XCTAssertTrue(online.isOnline)
        XCTAssertEqual(online.cpuPercent, 12.5)
        XCTAssertEqual(online.memoryPercent, 20)
        XCTAssertEqual(online.uploadBytesPerSecond, 200)
        XCTAssertEqual(online.downloadBytesPerSecond, 300)
        XCTAssertEqual(online.uploadedBytes, 900)
        XCTAssertEqual(online.downloadedBytes, 500)
        XCTAssertEqual(online.uptime, 86_400)
        let offline = try XCTUnwrap(snapshots["node-b"])
        XCTAssertFalse(offline.isOnline)
        XCTAssertEqual(offline.cpuPercent, 0)
    }

    func testMissingOrZeroTimeCannotAppearFreshAndOnline() async throws {
        RPCURLProtocol.setHandler { _ in
            .json(#"{"jsonrpc":"2.0","id":1,"result":{"node-a":{"online":true},"node-b":{"online":true,"time":"0001-01-01T00:00:00Z"}}}"#)
        }
        let records = try await makeClient().fetchSnapshots(nodeIDs: ["node-a", "node-b"])
        for record in records.values {
            XCTAssertFalse(record.isOnline)
            XCTAssertEqual(record.timestamp, .distantPast)
        }
    }

    func testEmptyNodeSelectionDoesNotRequestAllServerData() async throws {
        RPCURLProtocol.setHandler { _ in
            XCTFail("空选择不应发起全量请求")
            return .json("{}")
        }
        let records = try await makeClient().fetchSnapshots(nodeIDs: [])
        XCTAssertTrue(records.isEmpty)
    }

    func testHistoryUsesGroupedOfficialShapeAndIgnoresInvalidDates() async throws {
        RPCURLProtocol.setHandler { request in
            let body = try rpcBody(request)
            XCTAssertEqual(body["method"] as? String, "common:getRecords")
            let params = try XCTUnwrap(body["params"] as? [String: Any])
            XCTAssertEqual(params["uuid"] as? String, "node-a")
            XCTAssertEqual(params["type"] as? String, "load")
            XCTAssertEqual(params["load_type"] as? String, "all")
            XCTAssertEqual(params["maxCount"] as? Int, 240)
            return .json(#"{"jsonrpc":"2.0","id":1,"result":{"records":{"node-a":[{"client":"node-a","time":"2026-10-27T12:01:00Z","cpu":30,"ram":500,"ram_total":1000,"net_out":20,"net_in":50},{"client":"node-a","time":"2026-10-27T12:00:00Z","cpu":10,"ram":250,"ram_total":1000},{"client":"node-a","time":"not-a-date","cpu":90},{"client":"other-node","time":"2026-10-27T12:02:00Z","cpu":90}],"node-b":[]},"count":4}}"#)
        }
        let points = try await makeClient().fetchHistory(nodeID: "node-a")
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points.map(\.cpuPercent), [10, 30])
        XCTAssertEqual(points.map(\.memoryPercent), [25, 50])
        XCTAssertEqual(points.last?.uploadBytesPerSecond, 20)
        XCTAssertEqual(points.last?.downloadBytesPerSecond, 50)
    }

    func testEmptyHistoryIsEmptyRatherThanInventedData() async throws {
        RPCURLProtocol.setHandler { _ in .json(#"{"jsonrpc":"2.0","id":1,"result":{"records":null,"count":0}}"#) }
        let history = try await makeClient().fetchHistory(nodeID: "node-a")
        XCTAssertTrue(history.isEmpty)
    }

    func testHTTPFailuresHaveTypedSanitizedErrors() async throws {
        let expected: [(Int, KomariClientError)] = [(401, .authenticationRequired), (403, .permissionDenied), (404, .unsupportedInterface), (503, .unexpectedHTTPStatus(503))]
        for (status, error) in expected {
            RPCURLProtocol.setHandler { _ in .http(status, "fixture-key / private server details") }
            await assertError(error) { try await self.makeClient(key: "fixture-key").fetchNodes() }
            XCTAssertFalse(error.localizedDescription.contains("fixture-key"))
        }
    }

    func testRPCFailuresUseOfficialCodesAndNeverEchoRemoteMessages() async throws {
        let expected: [(Int, KomariClientError)] = [(-32040, .authenticationRequired), (-32041, .permissionDenied), (-32601, .unsupportedInterface), (-32603, .remoteFailure(-32603))]
        for (code, error) in expected {
            RPCURLProtocol.setHandler { _ in .json("{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":\(code),\"message\":\"fixture-key secret server details\"}}") }
            await assertError(error) { try await self.makeClient().fetchNodes() }
            XCTAssertFalse(error.localizedDescription.contains("fixture-key"))
        }
    }

    func testMalformedJSONAndWrongProtocolAreRejectedWithoutEchoingBody() async throws {
        for data in ["fixture-key", #"{"jsonrpc":"1.0","result":{}}"#, #"{"jsonrpc":"2.0","result":null}"#] {
            RPCURLProtocol.setHandler { _ in .json(data) }
            await assertError(.invalidResponse) { try await self.makeClient().fetchNodes() }
        }
    }

    func testVersionUsesReadOnlyRPC() async throws {
        RPCURLProtocol.setHandler { request in
            XCTAssertEqual(try rpcBody(request)["method"] as? String, "common:getVersion")
            return .json(#"{"jsonrpc":"2.0","id":1,"result":{"version":"1.6.1","hash":"fixture"}}"#)
        }
        let version = try await makeClient().fetchVersion()
        XCTAssertEqual(version, "1.6.1")
    }

    func testInvalidBaseURLsAndPlaintextRemoteKeyNeverReachTransport() async throws {
        RPCURLProtocol.setHandler { _ in
            XCTFail("无效连接配置不应进入网络传输")
            return .json("{}")
        }
        for value in ["ftp://example.invalid", "https://user:password@example.invalid", "https://example.invalid?token=value", "https://example.invalid#token"] {
            let client = KomariClient(connection: .init(baseURL: URL(string: value)!), session: session)
            await assertError(.invalidURL) { try await client.fetchNodes() }
        }
        let client = KomariClient(connection: .init(baseURL: URL(string: "http://example.invalid")!, apiKey: "fixture-key"), session: session)
        await assertError(.insecureCredentialTransport) { try await client.fetchNodes() }
    }

    func testCrossOriginRedirectIsBlockedBeforeSendingKeyToTarget() async throws {
        let target = try LocalHTTPFixture { _ in
            .json(#"{"jsonrpc":"2.0","id":1,"result":{"version":"1.6.1"}}"#)
        }
        defer { target.stop() }
        let redirector = try LocalHTTPFixture { request in
            XCTAssertTrue(request.lowercased().contains("authorization: bearer fixture-key"))
            return .redirectToURL(target.url)
        }
        defer { redirector.stop() }
        let client = KomariClient(connection: .init(baseURL: redirector.url, apiKey: "fixture-key"))
        await assertError(.redirectRejected) { try await client.fetchVersion() }
        XCTAssertEqual(redirector.requestCount, 1)
        XCTAssertEqual(target.requestCount, 0, "跨端口重定向不能接收到请求或认证凭据")
    }

    func testSameOriginRedirectCanReachCanonicalRPCPath() async throws {
        let server = try LocalHTTPFixture { request in
            if request.hasPrefix("POST /api/rpc2 ") {
                return .redirectToPath("/canonical")
            }
            return .json(#"{"jsonrpc":"2.0","id":1,"result":{"version":"1.6.1"}}"#)
        }
        defer { server.stop() }
        let client = KomariClient(connection: .init(baseURL: server.url))
        let version = try await client.fetchVersion()
        XCTAssertEqual(version, "1.6.1")
        XCTAssertEqual(server.requestCount, 2)
    }

    private func makeClient(path: String = "", key: String? = nil) -> KomariClient {
        KomariClient(connection: .init(baseURL: URL(string: "https://example.invalid\(path)")!, apiKey: key), session: session)
    }

    private func assertError<T>(_ expected: KomariClientError, operation: () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await operation()
            XCTFail("预期请求失败", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? KomariClientError, expected, file: file, line: line)
        }
    }
}

private func rpcBody(_ request: URLRequest) throws -> [String: Any] {
    let data: Data
    if let body = request.httpBody { data = body }
    else if let stream = request.httpBodyStream {
        stream.open()
        defer { stream.close() }
        var contents = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            contents.append(contentsOf: buffer.prefix(count))
        }
        data = contents
    } else { throw KomariClientError.invalidResponse }
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private final class RPCURLProtocol: URLProtocol {
    struct Reply {
        let status: Int
        let body: String
        static func json(_ body: String) -> Reply { Reply(status: 200, body: body) }
        static func http(_ status: Int, _ body: String) -> Reply { Reply(status: status, body: body) }
    }
    private static let lock = NSLock()
    private static var handler: ((URLRequest) throws -> Reply)?

    static func setHandler(_ handler: ((URLRequest) throws -> Reply)?) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handler
        Self.lock.unlock()
        do {
            let result = try XCTUnwrap(handler)(request)
            let response = try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: result.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(result.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// A loopback-only real HTTP fixture verifies Foundation redirect handling,
/// rather than assuming a mocked transport invokes URLSessionTaskDelegate.
private final class LocalHTTPFixture: @unchecked Sendable {
    enum Reply {
        case json(String)
        case redirectToURL(URL)
        case redirectToPath(String)

        var bytes: Data {
            let text: String
            switch self {
            case .json(let body):
                text = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            case .redirectToURL(let url):
                text = "HTTP/1.1 307 Temporary Redirect\r\nLocation: \(url.absoluteString)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            case .redirectToPath(let path):
                text = "HTTP/1.1 307 Temporary Redirect\r\nLocation: \(path)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            }
            return Data(text.utf8)
        }
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "KomariBar.Tests.HTTP")
    private let lock = NSLock()
    private var count = 0
    private let respond: (String) -> Reply

    init(respond: @escaping (String) -> Reply) throws {
        self.respond = respond
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready, .failed: ready.signal()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success, listener.port != nil else {
            listener.cancel()
            throw KomariClientError.connectionFailed
        }
    }

    var url: URL { URL(string: "http://127.0.0.1:\(listener.port!.rawValue)")! }
    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
    func stop() { listener.cancel() }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 32_768) { [weak self] data, _, _, _ in
            guard let self, let data else { connection.cancel(); return }
            self.lock.lock()
            self.count += 1
            self.lock.unlock()
            let response = self.respond(String(decoding: data, as: UTF8.self))
            connection.send(content: response.bytes, completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}
