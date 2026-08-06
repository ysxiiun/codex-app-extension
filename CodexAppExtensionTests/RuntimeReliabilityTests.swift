import Foundation
import XCTest
@testable import ExtensionCore

final class RuntimeReliabilityTests: XCTestCase {
    func testConnectionAndTargetRetryEventuallySucceedsWithoutRealSleep() async throws {
        let client = PipelineCDPDouble(connectionFailures: 2, targetBatches: [[], [Self.targetInfo("target-1")]])
        let bridge = PipelineBridgeDouble()
        let clock = RecordingRuntimeClock()
        let pipeline = CDPRuntimePipeline(
            client: client,
            bridge: bridge,
            healthCenter: HealthCenter(),
            clock: clock,
            retryPolicy: .init(connectionAttempts: 3, targetAttempts: 2, delay: .milliseconds(1))
        )

        try await pipeline.connect(port: 55_100, configuration: .defaultConfiguration)

        let ready = await pipeline.isReady()
        let connectCount = await client.connectCount()
        let sleepCount = await clock.sleepCount()
        XCTAssertTrue(ready)
        XCTAssertEqual(connectCount, 3)
        XCTAssertEqual(sleepCount, 3)
        let trace = await client.trace()
        XCTAssertLessThan(try XCTUnwrap(trace.firstIndex(of: "events")), try XCTUnwrap(trace.firstIndex(of: "Target.setDiscoverTargets")))
    }

    func testTargetWaitTimesOutAtPolicyBoundary() async throws {
        let client = PipelineCDPDouble(targetBatches: [[], []])
        let clock = RecordingRuntimeClock()
        let pipeline = CDPRuntimePipeline(
            client: client,
            bridge: PipelineBridgeDouble(),
            healthCenter: HealthCenter(),
            clock: clock,
            retryPolicy: .init(connectionAttempts: 1, targetAttempts: 2, delay: .milliseconds(1))
        )

        do {
            try await pipeline.connect(port: 55_101, configuration: .defaultConfiguration)
            XCTFail("没有合格 target 时必须按边界超时")
        } catch RuntimeControllerError.noQualifiedTarget {}

        let ready = await pipeline.isReady()
        let getTargetsCount = await client.getTargetsCount()
        let sleepCount = await clock.sleepCount()
        XCTAssertFalse(ready)
        XCTAssertEqual(getTargetsCount, 2)
        XCTAssertEqual(sleepCount, 1)
    }

    func testStaleRevisionDuringTargetWaitRetriesAndActivatesCurrentRevision() async throws {
        let client = PipelineCDPDouble(targetBatches: [[Self.targetInfo("target-stale")], [Self.targetInfo("target-stale")]])
        let bridge = PipelineBridgeDouble()
        await bridge.staleProbeOnce(targetIdentifier: "target-stale")
        let health = HealthCenter()
        let pipeline = CDPRuntimePipeline(
            client: client,
            bridge: bridge,
            healthCenter: health,
            clock: RecordingRuntimeClock(),
            retryPolicy: .init(connectionAttempts: 1, targetAttempts: 2, delay: .milliseconds(1))
        )

        try await pipeline.connect(port: 55_105, configuration: .defaultConfiguration)

        let probed = await bridge.probedTargets()
        let snapshot = await health.snapshot()
        let activeTargetIdentifier = await pipeline.activeTargetIdentifier()
        XCTAssertEqual(probed, ["target-stale", "target-stale"])
        XCTAssertEqual(activeTargetIdentifier, "target-stale")
        XCTAssertFalse(snapshot.targets.contains {
            $0.targetIdentifier == "target-stale" && $0.adapterIdentifier == "runtime"
        })
    }

    func testStaleRevisionFromTargetEventIsDroppedAndLaterTargetStillActivates() async throws {
        let client = PipelineCDPDouble(targetBatches: [[Self.targetInfo("target-initial")]])
        let bridge = PipelineBridgeDouble()
        let health = HealthCenter()
        let pipeline = CDPRuntimePipeline(
            client: client,
            bridge: bridge,
            healthCenter: health,
            clock: RecordingRuntimeClock(),
            retryPolicy: .init(connectionAttempts: 1, targetAttempts: 1)
        )
        try await pipeline.connect(port: 55_106, configuration: .defaultConfiguration)
        await client.emit(.init(method: "Target.targetDestroyed", params: .object(["targetId": .string("target-initial")])))
        await eventually { !(await pipeline.isReady()) }
        await bridge.staleProbeOnce(targetIdentifier: "target-event-stale")

        await client.emit(.init(method: "Target.targetCreated", params: .object([
            "targetInfo": Self.targetInfo("target-event-stale")
        ])))
        await client.emit(.init(method: "Target.targetCreated", params: .object([
            "targetInfo": Self.targetInfo("target-event-current")
        ])))
        await eventually { await pipeline.activeTargetIdentifier() == "target-event-current" }

        let snapshot = await health.snapshot()
        let probed = await bridge.probedTargets()
        XCTAssertTrue(probed.contains("target-event-stale"))
        XCTAssertTrue(probed.contains("target-event-current"))
        XCTAssertFalse(snapshot.targets.contains {
            $0.targetIdentifier == "target-event-stale" && $0.adapterIdentifier == "runtime"
        })
    }

    func testTargetCreatedIsAppliedAndFailureIsPublishedToHealth() async throws {
        let client = PipelineCDPDouble(targetBatches: [[Self.targetInfo("target-1")]])
        let bridge = PipelineBridgeDouble()
        let health = HealthCenter()
        let pipeline = CDPRuntimePipeline(
            client: client,
            bridge: bridge,
            healthCenter: health,
            clock: RecordingRuntimeClock(),
            retryPolicy: .init(connectionAttempts: 1, targetAttempts: 1)
        )
        try await pipeline.connect(port: 55_102, configuration: .defaultConfiguration)

        await client.emit(.init(method: "Target.targetDestroyed", params: .object(["targetId": .string("target-1")])))
        await bridge.fail(targetIdentifier: "target-2")
        await client.emit(.init(method: "Target.targetCreated", params: .object(["targetInfo": Self.targetInfo("target-2")])))
        await eventually {
            let snapshot = await health.snapshot()
            return snapshot.targets.contains {
                $0.targetIdentifier == "target-2" && $0.adapterIdentifier == "runtime"
            }
        }

        let snapshot = await health.snapshot()
        let appliedTargets = await bridge.appliedTargets()
        XCTAssertTrue(appliedTargets.contains("target-2"))
        let state = snapshot.targets.first { $0.targetIdentifier == "target-2" && $0.adapterIdentifier == "runtime" }?.state
        guard case let .degraded(reason)? = state else { return XCTFail("targetCreated 失败未进入 HealthCenter") }
        XCTAssertTrue(reason.contains("fixture-target-failure"))
    }

    func testSameTargetInfoChangeRefreshesInPlaceWithoutClearingActiveTarget() async throws {
        let client = PipelineCDPDouble(targetBatches: [[Self.targetInfo("target-1")]])
        let bridge = PipelineBridgeDouble()
        let pipeline = CDPRuntimePipeline(
            client: client,
            bridge: bridge,
            healthCenter: HealthCenter(),
            clock: RecordingRuntimeClock(),
            retryPolicy: .init(connectionAttempts: 1, targetAttempts: 1)
        )
        try await pipeline.connect(port: 55_103, configuration: .defaultConfiguration)

        await bridge.pauseNextProbe(targetIdentifier: "target-1")
        await client.emit(.init(method: "Target.targetInfoChanged", params: .object(["targetInfo": Self.targetInfo("target-1")])))
        await eventually { await bridge.hasPausedProbe(targetIdentifier: "target-1") }

        let activeWhileRefreshing = await pipeline.activeTargetIdentifier()
        let invalidatedWhileRefreshing = await bridge.invalidatedTargets()
        XCTAssertEqual(activeWhileRefreshing, "target-1")
        XCTAssertTrue(invalidatedWhileRefreshing.isEmpty)

        await bridge.resumeProbe(targetIdentifier: "target-1")
        await eventually { await bridge.appliedTargets().count == 2 }
        let activeAfterRefresh = await pipeline.activeTargetIdentifier()
        let probedAfterRefresh = await bridge.probedTargets()
        let invalidatedAfterRefresh = await bridge.invalidatedTargets()
        XCTAssertEqual(activeAfterRefresh, "target-1")
        XCTAssertEqual(probedAfterRefresh, ["target-1", "target-1"])
        XCTAssertTrue(invalidatedAfterRefresh.isEmpty)
    }

    func testSameTargetInfoChangeBurstReprobesWithoutStaleRuntimeHealth() async throws {
        let client = PipelineCDPDouble(targetBatches: [[Self.targetInfo("target-1")]])
        let bridge = PipelineBridgeDouble()
        let health = HealthCenter()
        let pipeline = CDPRuntimePipeline(
            client: client,
            bridge: bridge,
            healthCenter: health,
            clock: RecordingRuntimeClock(),
            retryPolicy: .init(connectionAttempts: 1, targetAttempts: 1)
        )
        try await pipeline.connect(port: 55_107, configuration: .defaultConfiguration)

        for _ in 0..<5 {
            await client.emit(.init(method: "Target.targetInfoChanged", params: .object([
                "targetInfo": Self.targetInfo("target-1")
            ])))
        }
        await eventually { await bridge.appliedTargets().count == 6 }

        let activeAfterBurst = await pipeline.activeTargetIdentifier()
        let probeCountAfterBurst = await bridge.probedTargets().count
        let invalidatedAfterBurst = await bridge.invalidatedTargets()
        XCTAssertEqual(activeAfterBurst, "target-1")
        XCTAssertEqual(probeCountAfterBurst, 6)
        XCTAssertTrue(invalidatedAfterBurst.isEmpty)
        let snapshot = await health.snapshot()
        XCTAssertFalse(snapshot.targets.contains {
            $0.targetIdentifier == "target-1" && $0.adapterIdentifier == "runtime"
        })
    }

    func testDifferentTargetIdentityChangeSwitchesAtomicallyAndInvalidatesOnlyOldTarget() async throws {
        let client = PipelineCDPDouble(targetBatches: [[Self.targetInfo("target-1")]])
        let bridge = PipelineBridgeDouble()
        let pipeline = CDPRuntimePipeline(
            client: client,
            bridge: bridge,
            healthCenter: HealthCenter(),
            clock: RecordingRuntimeClock(),
            retryPolicy: .init(connectionAttempts: 1, targetAttempts: 1)
        )
        try await pipeline.connect(port: 55_110, configuration: .defaultConfiguration)

        await bridge.pauseNextProbe(targetIdentifier: "target-2")
        await client.emit(.init(method: "Target.targetInfoChanged", params: .object([
            "targetInfo": Self.targetInfo("target-2")
        ])))
        await eventually { await bridge.hasPausedProbe(targetIdentifier: "target-2") }
        let activeWhileQualifying = await pipeline.activeTargetIdentifier()
        let invalidatedWhileQualifying = await bridge.invalidatedTargets()
        XCTAssertEqual(activeWhileQualifying, "target-1")
        XCTAssertTrue(invalidatedWhileQualifying.isEmpty)

        await bridge.resumeProbe(targetIdentifier: "target-2")
        await eventually { await pipeline.activeTargetIdentifier() == "target-2" }
        await eventually { await bridge.invalidatedTargets().contains("target-1") }

        let invalidated = await bridge.invalidatedTargets()
        let probed = await bridge.probedTargets()
        let applied = await bridge.appliedTargets()
        XCTAssertEqual(invalidated.filter { $0 == "target-1" }.count, 1)
        XCTAssertFalse(invalidated.contains("target-2"))
        XCTAssertTrue(probed.contains("target-2"))
        XCTAssertTrue(applied.contains("target-2"))
    }

    func testTargetCreatedSwitchesToQualifiedNewIdentityBeforeOldTargetIsDestroyed() async throws {
        let client = PipelineCDPDouble(targetBatches: [[Self.targetInfo("target-old")]])
        let bridge = PipelineBridgeDouble()
        let pipeline = CDPRuntimePipeline(
            client: client,
            bridge: bridge,
            healthCenter: HealthCenter(),
            clock: RecordingRuntimeClock(),
            retryPolicy: .init(connectionAttempts: 1, targetAttempts: 1)
        )
        try await pipeline.connect(port: 55_113, configuration: .defaultConfiguration)

        await bridge.pauseNextProbe(targetIdentifier: "target-new")
        await client.emit(.init(method: "Target.targetCreated", params: .object([
            "targetInfo": Self.targetInfo("target-new")
        ])))
        await eventually { await bridge.hasPausedProbe(targetIdentifier: "target-new") }
        let activeWhileQualifying = await pipeline.activeTargetIdentifier()
        XCTAssertEqual(activeWhileQualifying, "target-old")

        await bridge.resumeProbe(targetIdentifier: "target-new")
        await eventually { await pipeline.activeTargetIdentifier() == "target-new" }
        await eventually { await bridge.invalidatedTargets().filter { $0 == "target-old" }.count == 1 }

        await client.emit(.init(method: "Target.targetDestroyed", params: .object([
            "targetId": .string("target-old")
        ])))
        try? await Task.sleep(for: .milliseconds(25))

        let activeAfterOldDestroyed = await pipeline.activeTargetIdentifier()
        let invalidated = await bridge.invalidatedTargets()
        XCTAssertEqual(activeAfterOldDestroyed, "target-new")
        XCTAssertEqual(invalidated.filter { $0 == "target-old" }.count, 1)
        XCTAssertFalse(invalidated.contains("target-new"))
    }

    func testBlockedOldRefreshCannotWriteRuntimeHealthAfterStopAndReconnect() async throws {
        let client = PipelineCDPDouble(targetBatches: [
            [Self.targetInfo("target-old")],
            [Self.targetInfo("target-new")]
        ])
        let bridge = PipelineBridgeDouble()
        let health = HealthCenter()
        let pipeline = CDPRuntimePipeline(
            client: client,
            bridge: bridge,
            healthCenter: health,
            clock: RecordingRuntimeClock(),
            retryPolicy: .init(connectionAttempts: 1, targetAttempts: 1)
        )
        try await pipeline.connect(port: 55_114, configuration: .defaultConfiguration)
        await bridge.unqualifyProbeOnce(targetIdentifier: "target-old")
        await bridge.pauseNextProbe(targetIdentifier: "target-old")
        await client.emit(.init(method: "Target.targetInfoChanged", params: .object([
            "targetInfo": Self.targetInfo("target-old")
        ])))
        await eventually { await bridge.hasPausedProbe(targetIdentifier: "target-old") }

        await pipeline.stop()
        try await pipeline.connect(port: 55_115, configuration: .defaultConfiguration)
        let activeAfterReconnect = await pipeline.activeTargetIdentifier()
        XCTAssertEqual(activeAfterReconnect, "target-new")

        await bridge.resumeProbe(targetIdentifier: "target-old")
        await eventually {
            await bridge.completedProbeTargets().filter { $0 == "target-old" }.count == 2
        }

        let activeAfterOldRefreshReleased = await pipeline.activeTargetIdentifier()
        let snapshot = await health.snapshot()
        XCTAssertEqual(activeAfterOldRefreshReleased, "target-new")
        XCTAssertFalse(snapshot.targets.contains {
            $0.targetIdentifier == "target-old" && $0.adapterIdentifier == "runtime"
        })
    }

    func testBlockedRefreshReleasedAfterTargetInvalidationCannotReactivateOrRestoreHealth() async throws {
        let client = PipelineCDPDouble(targetBatches: [[Self.targetInfo("target-1")]])
        let health = HealthCenter()
        let bridge = PipelineBridgeDouble(healthCenter: health)
        let pipeline = CDPRuntimePipeline(
            client: client,
            bridge: bridge,
            healthCenter: health,
            clock: RecordingRuntimeClock(),
            retryPolicy: .init(connectionAttempts: 1, targetAttempts: 1)
        )
        try await pipeline.connect(port: 55_116, configuration: .defaultConfiguration)
        await health.updateTarget(.init(
            targetIdentifier: "target-1",
            adapterIdentifier: "wide-layout",
            state: .healthy
        ))
        await bridge.unqualifyProbeOnce(targetIdentifier: "target-1")
        await bridge.pauseNextProbe(targetIdentifier: "target-1")
        await client.emit(.init(method: "Target.targetInfoChanged", params: .object([
            "targetInfo": Self.targetInfo("target-1")
        ])))
        await eventually { await bridge.hasPausedProbe(targetIdentifier: "target-1") }

        await pipeline.invalidateTarget(identifier: "target-1")
        await bridge.resumeProbe(targetIdentifier: "target-1")
        await eventually {
            await bridge.completedProbeTargets().filter { $0 == "target-1" }.count == 2
        }

        let active = await pipeline.activeTargetIdentifier()
        let applied = await bridge.appliedTargets()
        let invalidated = await bridge.invalidatedTargets()
        let snapshot = await health.snapshot()
        XCTAssertNil(active)
        XCTAssertEqual(applied, ["target-1"])
        XCTAssertEqual(invalidated.filter { $0 == "target-1" }.count, 1)
        XCTAssertFalse(snapshot.targets.contains { $0.targetIdentifier == "target-1" })
    }

    func testSameTargetUnqualifiedRefreshRetainsActiveTargetAndPublishesDegradation() async throws {
        let client = PipelineCDPDouble(targetBatches: [[Self.targetInfo("target-1")]])
        let bridge = PipelineBridgeDouble()
        let health = HealthCenter()
        let pipeline = CDPRuntimePipeline(
            client: client,
            bridge: bridge,
            healthCenter: health,
            clock: RecordingRuntimeClock(),
            retryPolicy: .init(connectionAttempts: 1, targetAttempts: 1)
        )
        try await pipeline.connect(port: 55_111, configuration: .defaultConfiguration)
        await bridge.unqualifyProbeOnce(targetIdentifier: "target-1")

        await client.emit(.init(method: "Target.targetInfoChanged", params: .object([
            "targetInfo": Self.targetInfo("target-1")
        ])))
        await eventually {
            let snapshot = await health.snapshot()
            guard case let .degraded(reason)? = snapshot.targets.first(where: {
                $0.targetIdentifier == "target-1" && $0.adapterIdentifier == "runtime"
            })?.state else { return false }
            return reason == "surface-probe-unqualified"
        }

        let active = await pipeline.activeTargetIdentifier()
        let invalidated = await bridge.invalidatedTargets()
        let applied = await bridge.appliedTargets()
        XCTAssertEqual(active, "target-1")
        XCTAssertTrue(invalidated.isEmpty)
        XCTAssertEqual(applied, ["target-1"])
    }

    func testSameTargetFailureAndUnqualifiedDegradationRecoverAfterSuccessfulRefresh() async throws {
        let client = PipelineCDPDouble(targetBatches: [[Self.targetInfo("target-1")]])
        let bridge = PipelineBridgeDouble()
        let health = HealthCenter()
        let pipeline = CDPRuntimePipeline(
            client: client,
            bridge: bridge,
            healthCenter: health,
            clock: RecordingRuntimeClock(),
            retryPolicy: .init(connectionAttempts: 1, targetAttempts: 1)
        )
        try await pipeline.connect(port: 55_112, configuration: .defaultConfiguration)

        await bridge.fail(targetIdentifier: "target-1")
        await client.emit(.init(method: "Target.targetInfoChanged", params: .object([
            "targetInfo": Self.targetInfo("target-1")
        ])))
        await eventually { await Self.runtimeState(in: health, targetIdentifier: "target-1") == .degraded }

        await bridge.fail(targetIdentifier: nil)
        await client.emit(.init(method: "Target.targetInfoChanged", params: .object([
            "targetInfo": Self.targetInfo("target-1")
        ])))
        await eventually { await Self.runtimeState(in: health, targetIdentifier: "target-1") == .missing }

        await bridge.unqualifyProbeOnce(targetIdentifier: "target-1")
        await client.emit(.init(method: "Target.targetInfoChanged", params: .object([
            "targetInfo": Self.targetInfo("target-1")
        ])))
        await eventually { await Self.runtimeState(in: health, targetIdentifier: "target-1") == .degraded }

        await client.emit(.init(method: "Target.targetInfoChanged", params: .object([
            "targetInfo": Self.targetInfo("target-1")
        ])))
        await eventually { await Self.runtimeState(in: health, targetIdentifier: "target-1") == .missing }

        let activeAfterRecoveries = await pipeline.activeTargetIdentifier()
        let invalidatedAfterRecoveries = await bridge.invalidatedTargets()
        XCTAssertEqual(activeAfterRecoveries, "target-1")
        XCTAssertTrue(invalidatedAfterRecoveries.isEmpty)
    }

    func testDegradedTargetURLChangeWithoutDestroyClearsRuntimeAndAdapterHealth() async throws {
        let client = PipelineCDPDouble(targetBatches: [[Self.targetInfo("target-1")]])
        let health = HealthCenter()
        let bridge = PipelineBridgeDouble(healthCenter: health)
        let pipeline = CDPRuntimePipeline(
            client: client,
            bridge: bridge,
            healthCenter: health,
            clock: RecordingRuntimeClock(),
            retryPolicy: .init(connectionAttempts: 1, targetAttempts: 1)
        )
        try await pipeline.connect(port: 55_108, configuration: .defaultConfiguration)
        await health.updateTarget(.init(
            targetIdentifier: "target-1",
            adapterIdentifier: "wide-layout",
            state: .degraded(reason: "fixture-adapter-degraded")
        ))
        await bridge.fail(targetIdentifier: "target-1")
        await client.emit(.init(method: "Target.targetInfoChanged", params: .object([
            "targetInfo": Self.targetInfo("target-1")
        ])))
        await eventually { await Self.runtimeState(in: health, targetIdentifier: "target-1") == .degraded }

        await client.emit(.init(method: "Target.targetInfoChanged", params: .object([
            "targetInfo": Self.targetInfo("target-1", url: "app://-/different.html")
        ])))
        await eventually {
            let activeTargetIdentifier = await pipeline.activeTargetIdentifier()
            let snapshot = await health.snapshot()
            return activeTargetIdentifier == nil
                && !snapshot.targets.contains { $0.targetIdentifier == "target-1" }
        }
        let invalidatedAfterChange = await bridge.invalidatedTargets()
        XCTAssertEqual(invalidatedAfterChange.filter { $0 == "target-1" }.count, 1)

        await client.emit(.init(method: "Target.targetDestroyed", params: .object(["targetId": .string("target-1")])))
        try? await Task.sleep(for: .milliseconds(25))
        let invalidatedAfterDestroy = await bridge.invalidatedTargets()
        let healthAfterDestroy = await health.snapshot()
        XCTAssertEqual(invalidatedAfterDestroy.filter { $0 == "target-1" }.count, 1)
        XCTAssertTrue(healthAfterDestroy.targets.isEmpty)
    }

    func testSameTargetRefreshFailureRemainsVisibleWithoutClearingActiveTarget() async throws {
        let client = PipelineCDPDouble(targetBatches: [[Self.targetInfo("target-1")]])
        let bridge = PipelineBridgeDouble()
        let health = HealthCenter()
        let pipeline = CDPRuntimePipeline(
            client: client,
            bridge: bridge,
            healthCenter: health,
            clock: RecordingRuntimeClock(),
            retryPolicy: .init(connectionAttempts: 1, targetAttempts: 1)
        )
        try await pipeline.connect(port: 55_109, configuration: .defaultConfiguration)
        await bridge.fail(targetIdentifier: "target-1")

        await client.emit(.init(method: "Target.targetInfoChanged", params: .object([
            "targetInfo": Self.targetInfo("target-1")
        ])))
        await eventually { await bridge.appliedTargets().count == 2 }
        await eventually {
            let snapshot = await health.snapshot()
            return snapshot.targets.contains {
                $0.targetIdentifier == "target-1" && $0.adapterIdentifier == "runtime"
            }
        }

        let activeAfterFailure = await pipeline.activeTargetIdentifier()
        let invalidatedAfterFailure = await bridge.invalidatedTargets()
        XCTAssertEqual(activeAfterFailure, "target-1")
        XCTAssertTrue(invalidatedAfterFailure.isEmpty)
        let snapshot = await health.snapshot()
        guard case let .degraded(reason)? = snapshot.targets.first(where: {
            $0.targetIdentifier == "target-1" && $0.adapterIdentifier == "runtime"
        })?.state else { return XCTFail("原位刷新失败必须进入 HealthCenter") }
        XCTAssertTrue(reason.contains("fixture-target-failure"))
    }

    func testStopInvalidatesKnownTargetsAndDisconnectsClient() async throws {
        let client = PipelineCDPDouble(targetBatches: [[Self.targetInfo("target-1")]])
        let bridge = PipelineBridgeDouble()
        let pipeline = CDPRuntimePipeline(
            client: client,
            bridge: bridge,
            healthCenter: HealthCenter(),
            clock: RecordingRuntimeClock(),
            retryPolicy: .init(connectionAttempts: 1, targetAttempts: 1)
        )
        try await pipeline.connect(port: 55_104, configuration: .defaultConfiguration)

        await pipeline.stop()

        let ready = await pipeline.isReady()
        let disconnects = await client.disconnectCount()
        let invalidated = await bridge.invalidatedTargets()
        XCTAssertFalse(ready)
        XCTAssertGreaterThanOrEqual(disconnects, 2)
        XCTAssertTrue(invalidated.contains("target-1"))
    }

    private static func targetInfo(
        _ identifier: String,
        url: String = TargetCoordinator.codexSurfaceURL.absoluteString
    ) -> JSONValue {
        .object(["targetId": .string(identifier), "url": .string(url)])
    }

    private enum RuntimeHealthState: Equatable {
        case missing
        case healthy
        case degraded
    }

    private static func runtimeState(
        in health: HealthCenter,
        targetIdentifier: String
    ) async -> RuntimeHealthState {
        let state = (await health.snapshot()).targets.first {
            $0.targetIdentifier == targetIdentifier && $0.adapterIdentifier == "runtime"
        }?.state
        switch state {
        case .healthy?: return .healthy
        case .degraded?: return .degraded
        case .waiting?: return .degraded
        case nil: return .missing
        }
    }

    private func eventually(_ predicate: @escaping @Sendable () async -> Bool) async {
        for _ in 0..<200 {
            if await predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("异步条件未收敛")
    }
}

private actor RecordingRuntimeClock: RuntimeClock {
    private var sleeps = 0
    func sleep(for duration: Duration) { sleeps += 1 }
    func sleepCount() -> Int { sleeps }
}

private actor PipelineCDPDouble: CDPRuntimeClient {
    private var failuresRemaining: Int
    private var batches: [[JSONValue]]
    private var state: CDPConnectionState = .disconnected
    private var connects = 0
    private var disconnects = 0
    private var getTargetsCalls = 0
    private var eventContinuations: [AsyncStream<CDPEvent>.Continuation] = []
    private var recordedTrace: [String] = []

    init(connectionFailures: Int = 0, targetBatches: [[JSONValue]]) {
        failuresRemaining = connectionFailures
        batches = targetBatches
    }

    func connect(to baseURL: URL) throws {
        connects += 1
        recordedTrace.append("connect")
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            state = .backingOff(attempt: connects, delay: .milliseconds(1))
            throw CDPClientError.transport("fixture-connect")
        }
        state = .connected(generation: UInt64(connects), webSocketURL: URL(string: "ws://127.0.0.1:55100/devtools/browser")!)
    }

    func disconnect(unexpected: Bool) { disconnects += 1; state = .disconnected }
    func snapshot() -> CDPClientSnapshot { .init(state: state, generation: UInt64(connects), pendingRequestCount: 0) }
    func events() -> AsyncStream<CDPEvent> {
        recordedTrace.append("events")
        return AsyncStream { eventContinuations.append($0) }
    }
    func request(method: String, params: JSONValue?, sessionIdentifier: String?, timeout: Duration?) throws -> JSONValue? {
        recordedTrace.append(method)
        if method == "Target.setDiscoverTargets" { return .object([:]) }
        if method == "Target.getTargets" {
            getTargetsCalls += 1
            let batch = batches.isEmpty ? [] : batches.removeFirst()
            return .object(["targetInfos": .array(batch)])
        }
        return .object([:])
    }
    func emit(_ event: CDPEvent) { for continuation in eventContinuations { continuation.yield(event) } }
    func connectCount() -> Int { connects }
    func disconnectCount() -> Int { disconnects }
    func getTargetsCount() -> Int { getTargetsCalls }
    func trace() -> [String] { recordedTrace }
}

private actor PipelineBridgeDouble: PageRuntimeBridging {
    private let healthCenter: HealthCenter?
    private var failingTarget: String?
    private var staleProbeTargets: Set<String> = []
    private var unqualifiedProbeTargets: Set<String> = []
    private var probesToPause: Set<String> = []
    private var pausedProbeContinuations: [String: CheckedContinuation<Void, Never>] = [:]
    private var probed: [String] = []
    private var completedProbes: [String] = []
    private var applied: [String] = []
    private var invalidated: [String] = []

    init(healthCenter: HealthCenter? = nil) {
        self.healthCenter = healthCenter
    }

    func fail(targetIdentifier: String?) { failingTarget = targetIdentifier }
    func staleProbeOnce(targetIdentifier: String) { staleProbeTargets.insert(targetIdentifier) }
    func unqualifyProbeOnce(targetIdentifier: String) { unqualifiedProbeTargets.insert(targetIdentifier) }
    func pauseNextProbe(targetIdentifier: String) { probesToPause.insert(targetIdentifier) }
    func hasPausedProbe(targetIdentifier: String) -> Bool { pausedProbeContinuations[targetIdentifier] != nil }
    func resumeProbe(targetIdentifier: String) {
        pausedProbeContinuations.removeValue(forKey: targetIdentifier)?.resume()
    }
    func probe(target: CDPTarget, requiredAnchors: Set<CodexSurfaceAnchor>) async throws -> CodexSurfaceProbeResult {
        probed.append(target.identifier)
        if probesToPause.remove(target.identifier) != nil {
            await withCheckedContinuation { continuation in
                pausedProbeContinuations[target.identifier] = continuation
            }
        }
        if staleProbeTargets.remove(target.identifier) != nil {
            completedProbes.append(target.identifier)
            throw PageRuntimeBridgeError.staleRevision(target.identifier)
        }
        if unqualifiedProbeTargets.remove(target.identifier) != nil {
            completedProbes.append(target.identifier)
            return .init(matchedAnchors: [], counts: Dictionary(
                uniqueKeysWithValues: requiredAnchors.map { ($0, 0) }
            ))
        }
        completedProbes.append(target.identifier)
        return .init(matchedAnchors: requiredAnchors, counts: Dictionary(uniqueKeysWithValues: requiredAnchors.map { ($0, 1) }))
    }
    func apply(configuration: AppConfiguration, to target: CDPTarget, operation: PageRuntimeOperation) throws -> [FeatureExecutionResult] {
        applied.append(target.identifier)
        if failingTarget == target.identifier { throw RuntimeControllerError.configurationRejected("fixture-target-failure") }
        return []
    }
    func invalidate(targetIdentifier: String) async {
        invalidated.append(targetIdentifier)
        await healthCenter?.removeTarget(identifier: targetIdentifier)
    }
    func probedTargets() -> [String] { probed }
    func completedProbeTargets() -> [String] { completedProbes }
    func appliedTargets() -> [String] { applied }
    func invalidatedTargets() -> [String] { invalidated }
}
