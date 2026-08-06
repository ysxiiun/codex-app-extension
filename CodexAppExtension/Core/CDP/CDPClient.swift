import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public subscript(key: String) -> JSONValue? {
        guard case let .object(object) = self else { return nil }
        return object[key]
    }

    public var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }
}

public struct CDPEvent: Equatable, Sendable {
    public let method: String
    public let params: JSONValue?
    public let sessionIdentifier: String?

    public init(method: String, params: JSONValue?, sessionIdentifier: String? = nil) {
        self.method = method
        self.params = params
        self.sessionIdentifier = sessionIdentifier
    }
}

public enum CDPConnectionState: Equatable, Sendable {
    case disconnected
    case checkingReadiness(URL)
    case connecting(URL)
    case connected(generation: UInt64, webSocketURL: URL)
    case backingOff(attempt: Int, delay: Duration)
}

public struct CDPClientSnapshot: Equatable, Sendable {
    public let state: CDPConnectionState
    public let generation: UInt64
    public let pendingRequestCount: Int

    public init(state: CDPConnectionState, generation: UInt64, pendingRequestCount: Int) {
        self.state = state
        self.generation = generation
        self.pendingRequestCount = pendingRequestCount
    }
}

public enum CDPClientError: Error, Equatable, Sendable, LocalizedError {
    case unsafeEndpoint(String)
    case readinessFailed(statusCode: Int)
    case invalidReadinessResponse
    case notConnected
    case timedOut(requestID: UInt64, generation: UInt64)
    case cancelled(requestID: UInt64, generation: UInt64)
    case disconnected(generation: UInt64)
    case remote(code: Int, message: String)
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case let .unsafeEndpoint(endpoint): return "拒绝非回环 CDP 地址: \(endpoint)"
        case let .readinessFailed(statusCode): return "CDP readiness HTTP 状态异常: \(statusCode)"
        case .invalidReadinessResponse: return "CDP readiness 响应无有效 WebSocket 地址"
        case .notConnected: return "CDP 尚未连接"
        case let .timedOut(requestID, generation): return "CDP 请求超时: \(generation)/\(requestID)"
        case let .cancelled(requestID, generation): return "CDP 请求已取消: \(generation)/\(requestID)"
        case let .disconnected(generation): return "CDP 连接已断开: generation=\(generation)"
        case let .remote(code, message): return "CDP 远端错误 \(code): \(message)"
        case let .transport(message): return "CDP 传输错误: \(message)"
        }
    }
}

public protocol CDPTransport: Sendable {
    func checkReadiness(at baseURL: URL) async throws -> URL
    func connect(to webSocketURL: URL) async throws
    func send(_ message: String) async throws
    func receive() async throws -> String
    func disconnect() async
}

public protocol CDPClock: Sendable {
    func sleep(for duration: Duration) async throws
}

public struct SystemCDPClock: CDPClock {
    public init() {}

    public func sleep(for duration: Duration) async throws {
        try await ContinuousClock().sleep(for: duration)
    }
}

public actor CDPClient {
    private struct RequestToken: Hashable, Sendable {
        let requestID: UInt64
        let generation: UInt64
    }

    private struct PendingRequest {
        let continuation: CheckedContinuation<JSONValue?, any Error>
        let timeoutTask: Task<Void, Never>
    }

    private let transport: any CDPTransport
    private let clock: any CDPClock
    private let defaultTimeout: Duration
    private let maximumBackoff: Duration
    private var state: CDPConnectionState = .disconnected
    private var generation: UInt64 = 0
    private var nextRequestID: UInt64 = 0
    private var reconnectAttempt = 0
    private var pending: [RequestToken: PendingRequest] = [:]
    private var receiverTask: Task<Void, Never>?
    private var eventObservers: [UUID: AsyncStream<CDPEvent>.Continuation] = [:]

    public init(
        transport: any CDPTransport,
        clock: any CDPClock = SystemCDPClock(),
        defaultTimeout: Duration = .seconds(5),
        maximumBackoff: Duration = .seconds(30)
    ) {
        self.transport = transport
        self.clock = clock
        self.defaultTimeout = defaultTimeout
        self.maximumBackoff = maximumBackoff
    }

    public func snapshot() -> CDPClientSnapshot {
        .init(state: state, generation: generation, pendingRequestCount: pending.count)
    }

    public func events() -> AsyncStream<CDPEvent> {
        let identifier = UUID()
        // Browser target traffic is loss-sensitive; a finite newest window bounds memory while
        // retaining the latest lifecycle facts needed to converge after target reloads.
        return AsyncStream(bufferingPolicy: .bufferingNewest(RuntimeStreamBufferLimits.lossSensitiveEvents)) { continuation in
            eventObservers[identifier] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeEventObserver(identifier) }
            }
        }
    }

    public func connect(to baseURL: URL) async throws {
        guard Self.isExplicitLoopback(baseURL) else {
            throw CDPClientError.unsafeEndpoint(baseURL.absoluteString)
        }

        state = .checkingReadiness(baseURL)
        do {
            let webSocketURL = try await transport.checkReadiness(at: baseURL)
            guard Self.isExplicitLoopback(webSocketURL) else {
                throw CDPClientError.unsafeEndpoint(webSocketURL.absoluteString)
            }
            state = .connecting(webSocketURL)
            generation &+= 1
            let connectionGeneration = generation
            try await transport.connect(to: webSocketURL)
            reconnectAttempt = 0
            state = .connected(generation: connectionGeneration, webSocketURL: webSocketURL)
            startReceiver(generation: connectionGeneration)
        } catch let error as CDPClientError {
            scheduleBackoff()
            throw error
        } catch {
            scheduleBackoff()
            throw CDPClientError.transport(String(describing: error))
        }
    }

    public func request(
        method: String,
        params: JSONValue? = nil,
        sessionIdentifier: String? = nil,
        timeout: Duration? = nil
    ) async throws -> JSONValue? {
        guard case let .connected(connectionGeneration, _) = state,
              connectionGeneration == generation else {
            throw CDPClientError.notConnected
        }

        nextRequestID &+= 1
        let token = RequestToken(requestID: nextRequestID, generation: connectionGeneration)
        let message = try Self.encodeRequest(
            id: token.requestID,
            method: method,
            params: params,
            sessionIdentifier: sessionIdentifier
        )
        let requestTimeout = timeout ?? defaultTimeout

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let timeoutTask = Task { [clock] in
                    do {
                        try await clock.sleep(for: requestTimeout)
                        self.timeout(token)
                    } catch {
                        // 计时任务取消表示请求已通过其他路径完成。
                    }
                }
                pending[token] = PendingRequest(continuation: continuation, timeoutTask: timeoutTask)
                Task {
                    do {
                        try await transport.send(message)
                    } catch {
                        self.fail(token, error: .transport(String(describing: error)))
                    }
                }
            }
        } onCancel: {
            Task { await self.cancel(token) }
        }
    }

    public func disconnect(unexpected: Bool = false) async {
        let disconnectedGeneration = generation
        receiverTask?.cancel()
        receiverTask = nil
        await transport.disconnect()
        failAllPending(error: .disconnected(generation: disconnectedGeneration))
        if unexpected {
            scheduleBackoff()
        } else {
            state = .disconnected
        }
    }

    private func startReceiver(generation connectionGeneration: UInt64) {
        receiverTask?.cancel()
        receiverTask = Task {
            do {
                while !Task.isCancelled {
                    let message = try await transport.receive()
                    self.handleIncoming(message, generation: connectionGeneration)
                }
            } catch {
                self.receiverFailed(generation: connectionGeneration)
            }
        }
    }

    private func handleIncoming(_ message: String, generation incomingGeneration: UInt64) {
        // WebSocket 旧世代的迟到响应必须在解析前丢弃。
        guard incomingGeneration == generation,
              case let .connected(activeGeneration, _) = state,
              activeGeneration == incomingGeneration else { return }
        guard let data = message.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(JSONValue.self, from: data),
              case let .object(object) = envelope else { return }

        if case let .number(rawID)? = object["id"] {
            guard let requestID = UInt64(exactly: rawID) else { return }
            let token = RequestToken(requestID: requestID, generation: incomingGeneration)
            guard let request = pending.removeValue(forKey: token) else { return }
            request.timeoutTask.cancel()

            if case let .object(errorObject)? = object["error"] {
                let code: Int
                if case let .number(value)? = errorObject["code"] { code = Int(value) } else { code = -1 }
                let message: String
                if case let .string(value)? = errorObject["message"] { message = value } else { message = "未知错误" }
                request.continuation.resume(throwing: CDPClientError.remote(code: code, message: message))
            } else {
                request.continuation.resume(returning: object["result"])
            }
            return
        }

        if case let .string(method)? = object["method"] {
            let event = CDPEvent(
                method: method,
                params: object["params"],
                sessionIdentifier: object["sessionId"]?.stringValue
            )
            for observer in eventObservers.values {
                observer.yield(event)
            }
        }
    }

    private func receiverFailed(generation failedGeneration: UInt64) {
        guard failedGeneration == generation else { return }
        failAllPending(error: .disconnected(generation: failedGeneration))
        scheduleBackoff()
    }

    private func timeout(_ token: RequestToken) {
        guard let request = pending.removeValue(forKey: token) else { return }
        request.continuation.resume(
            throwing: CDPClientError.timedOut(requestID: token.requestID, generation: token.generation)
        )
    }

    private func cancel(_ token: RequestToken) {
        guard let request = pending.removeValue(forKey: token) else { return }
        request.timeoutTask.cancel()
        request.continuation.resume(
            throwing: CDPClientError.cancelled(requestID: token.requestID, generation: token.generation)
        )
    }

    private func fail(_ token: RequestToken, error: CDPClientError) {
        guard let request = pending.removeValue(forKey: token) else { return }
        request.timeoutTask.cancel()
        request.continuation.resume(throwing: error)
    }

    private func failAllPending(error: CDPClientError) {
        let requests = pending.values
        pending.removeAll()
        for request in requests {
            request.timeoutTask.cancel()
            request.continuation.resume(throwing: error)
        }
    }

    private func scheduleBackoff() {
        reconnectAttempt += 1
        let exponent = min(reconnectAttempt - 1, 10)
        let proposed = Duration.seconds(1 << exponent)
        let delay = min(proposed, maximumBackoff)
        state = .backingOff(attempt: reconnectAttempt, delay: delay)
    }

    private func removeEventObserver(_ identifier: UUID) {
        eventObservers.removeValue(forKey: identifier)
    }

    private static func isExplicitLoopback(_ url: URL) -> Bool {
        url.host == "127.0.0.1"
    }

    private static func encodeRequest(
        id: UInt64,
        method: String,
        params: JSONValue?,
        sessionIdentifier: String?
    ) throws -> String {
        var object: [String: JSONValue] = [
            "id": .number(Double(id)),
            "method": .string(method)
        ]
        if let params { object["params"] = params }
        if let sessionIdentifier { object["sessionId"] = .string(sessionIdentifier) }
        let data = try JSONEncoder().encode(JSONValue.object(object))
        guard let message = String(data: data, encoding: .utf8) else {
            throw CDPClientError.transport("请求编码失败")
        }
        return message
    }
}

public actor URLSessionCDPTransport: CDPTransport {
    private let session: URLSession
    private var webSocketTask: URLSessionWebSocketTask?

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func checkReadiness(at baseURL: URL) async throws -> URL {
        let readinessURL = baseURL.appendingPathComponent("json/version")
        let (data, response) = try await session.data(from: readinessURL)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CDPClientError.invalidReadinessResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw CDPClientError.readinessFailed(statusCode: httpResponse.statusCode)
        }
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any],
              let rawURL = dictionary["webSocketDebuggerUrl"] as? String,
              let webSocketURL = URL(string: rawURL) else {
            throw CDPClientError.invalidReadinessResponse
        }
        return webSocketURL
    }

    public func connect(to webSocketURL: URL) {
        let task = session.webSocketTask(with: webSocketURL)
        webSocketTask = task
        task.resume()
    }

    public func send(_ message: String) async throws {
        guard let webSocketTask else { throw CDPClientError.notConnected }
        try await webSocketTask.send(.string(message))
    }

    public func receive() async throws -> String {
        guard let webSocketTask else { throw CDPClientError.notConnected }
        switch try await webSocketTask.receive() {
        case let .string(message): return message
        case let .data(data):
            guard let message = String(data: data, encoding: .utf8) else {
                throw CDPClientError.transport("WebSocket 二进制消息不是 UTF-8")
            }
            return message
        @unknown default:
            throw CDPClientError.transport("未知 WebSocket 消息类型")
        }
    }

    public func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }
}
