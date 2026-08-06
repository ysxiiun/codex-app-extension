import Foundation
import XCTest
@testable import ExtensionCore

final class CDPClientTests: XCTestCase {
    private let baseURL = URL(string: "http://127.0.0.1:55123")!
    private let socketURL = URL(string: "ws://127.0.0.1:55123/devtools/browser/test")!

    func testReadinessWebSocketAndRequestSuccess() async throws {
        let transport = TestCDPTransport(readinessURL: socketURL)
        let client = CDPClient(transport: transport)
        try await client.connect(to: baseURL)

        let request = Task { try await client.request(method: "Runtime.enable") }
        try await waitUntil { await transport.sentMessages().count == 1 }
        await transport.push(#"{"id":1,"result":{"enabled":true}}"#)

        let result = try await request.value
        XCTAssertEqual(result?["enabled"], .bool(true))
        let snapshot = await client.snapshot()
        guard case let .connected(generation, webSocketURL) = snapshot.state else {
            return XCTFail("连接状态不正确")
        }
        XCTAssertEqual(generation, 1)
        XCTAssertEqual(webSocketURL, socketURL)
    }

    func testFlattenedSessionIdentifierIsEncodedAtTopLevel() async throws {
        let transport = TestCDPTransport(readinessURL: socketURL)
        let client = CDPClient(transport: transport)
        try await client.connect(to: baseURL)

        let request = Task {
            try await client.request(
                method: "Runtime.evaluate",
                params: .object(["expression": .string("1")]),
                sessionIdentifier: "session-7"
            )
        }
        try await waitUntil { await transport.sentMessages().count == 1 }
        let sentMessages = await transport.sentMessages()
        let message = try XCTUnwrap(sentMessages.first)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(message.utf8)) as? [String: Any])
        XCTAssertEqual(object["sessionId"] as? String, "session-7")
        XCTAssertEqual(object["method"] as? String, "Runtime.evaluate")
        await transport.push(#"{"id":1,"result":{"value":1}}"#)
        _ = try await request.value
    }

    func testTimeoutAndCancellationAreObservable() async throws {
        let transport = TestCDPTransport(readinessURL: socketURL)
        let clock = ManualCDPClock()
        let client = CDPClient(transport: transport, clock: clock, defaultTimeout: .seconds(30))
        try await client.connect(to: baseURL)

        let timedRequest = Task { try await client.request(method: "Page.enable") }
        try await waitUntil { await clock.waiterCount() == 1 }
        await clock.fireAll()
        do {
            _ = try await timedRequest.value
            XCTFail("请求应超时")
        } catch let error as CDPClientError {
            XCTAssertEqual(error, .timedOut(requestID: 1, generation: 1))
        }

        let cancelledRequest = Task { try await client.request(method: "DOM.enable") }
        try await waitUntil { await transport.sentMessages().count == 2 }
        cancelledRequest.cancel()
        do {
            _ = try await cancelledRequest.value
            XCTFail("请求应取消")
        } catch let error as CDPClientError {
            XCTAssertEqual(error, .cancelled(requestID: 2, generation: 1))
        }
    }

    func testDisconnectFailsPendingRequestAndPublishesBackoff() async throws {
        let transport = TestCDPTransport(readinessURL: socketURL)
        let client = CDPClient(transport: transport)
        try await client.connect(to: baseURL)
        let request = Task { try await client.request(method: "Target.setDiscoverTargets") }
        try await waitUntil { await transport.sentMessages().count == 1 }

        await client.disconnect(unexpected: true)

        do {
            _ = try await request.value
            XCTFail("断开后请求应失败")
        } catch let error as CDPClientError {
            XCTAssertEqual(error, .disconnected(generation: 1))
        }
        let snapshot = await client.snapshot()
        XCTAssertEqual(snapshot.state, .backingOff(attempt: 1, delay: .seconds(1)))
    }

    func testLateResponseFromOldGenerationCannotCompleteNewRequest() async throws {
        let transport = TestCDPTransport(readinessURL: socketURL)
        let client = CDPClient(transport: transport)
        try await client.connect(to: baseURL)
        try await waitUntil { await transport.receiveWaiterCount() == 1 }
        await client.disconnect()
        try await client.connect(to: baseURL)
        try await waitUntil { await transport.receiveWaiterCount() == 2 }

        let request = Task { try await client.request(method: "Runtime.evaluate") }
        try await waitUntil { await transport.sentMessages().count == 1 }
        await transport.pushToOldest(#"{"id":1,"result":{"source":"old"}}"#)
        try await Task.sleep(for: .milliseconds(20))
        let pendingSnapshot = await client.snapshot()
        XCTAssertEqual(pendingSnapshot.pendingRequestCount, 1)

        await transport.pushToOldest(#"{"id":1,"result":{"source":"new"}}"#)
        let result = try await request.value
        XCTAssertEqual(result?["source"], .string("new"))
        let reconnectedSnapshot = await client.snapshot()
        XCTAssertEqual(reconnectedSnapshot.generation, 2)
    }

    func testRejectsNonLoopbackEndpointAndReadinessFailureBacksOff() async throws {
        let transport = TestCDPTransport(readinessURL: socketURL)
        let client = CDPClient(transport: transport)

        do {
            try await client.connect(to: URL(string: "http://0.0.0.0:55123")!)
            XCTFail("非显式回环地址必须拒绝")
        } catch let error as CDPClientError {
            XCTAssertEqual(error, .unsafeEndpoint("http://0.0.0.0:55123"))
        }

        await transport.setReadinessError(.readinessFailed(statusCode: 503))
        do {
            try await client.connect(to: baseURL)
            XCTFail("readiness 失败必须向上传播")
        } catch let error as CDPClientError {
            XCTAssertEqual(error, .readinessFailed(statusCode: 503))
        }
        let failedReadinessSnapshot = await client.snapshot()
        XCTAssertEqual(failedReadinessSnapshot.state, .backingOff(attempt: 1, delay: .seconds(1)))
    }

    private func waitUntil(
        attempts: Int = 2_000,
        condition: @escaping @Sendable () async -> Bool
    ) async throws {
        for _ in 0..<attempts {
            if await condition() { return }
            await Task.yield()
        }
        XCTFail("等待异步条件超时")
    }
}

private actor ManualCDPClock: CDPClock {
    private var waiters: [CheckedContinuation<Void, any Error>] = []

    func sleep(for duration: Duration) async throws {
        try await withCheckedThrowingContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func waiterCount() -> Int { waiters.count }

    func fireAll() {
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

private actor TestCDPTransport: CDPTransport {
    private let readinessURL: URL
    private var readinessError: CDPClientError?
    private var messages: [String] = []
    private var receiveWaiters: [CheckedContinuation<String, any Error>] = []

    init(readinessURL: URL) {
        self.readinessURL = readinessURL
    }

    func setReadinessError(_ error: CDPClientError?) {
        readinessError = error
    }

    func checkReadiness(at baseURL: URL) throws -> URL {
        if let readinessError { throw readinessError }
        return readinessURL
    }

    func connect(to webSocketURL: URL) {}

    func send(_ message: String) {
        messages.append(message)
    }

    func receive() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            receiveWaiters.append(continuation)
        }
    }

    func disconnect() {}

    func sentMessages() -> [String] { messages }
    func receiveWaiterCount() -> Int { receiveWaiters.count }

    func push(_ message: String) {
        pushToOldest(message)
    }

    func pushToOldest(_ message: String) {
        guard !receiveWaiters.isEmpty else { return }
        receiveWaiters.removeFirst().resume(returning: message)
    }
}
