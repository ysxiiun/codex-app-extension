import Foundation
import XCTest
@testable import ExtensionCore

final class PerformanceBudgetTests: XCTestCase {
    func testRuntimeStreamBuffersHaveExplicitFiniteCapacities() {
        XCTAssertEqual(RuntimeStreamBufferLimits.latestState, 1)
        XCTAssertEqual(RuntimeStreamBufferLimits.lossSensitiveEvents, 64)
    }

    func testHealthStreamDropsIntermediateSnapshotsAndRetainsNewestState() async {
        let health = HealthCenter()
        let stream = await health.updates()
        for index in 1...100 {
            await health.updateTarget(.init(
                targetIdentifier: "target",
                adapterIdentifier: "wide-layout",
                state: index == 100 ? .degraded(reason: "latest") : .healthy
            ))
        }
        var iterator = stream.makeAsyncIterator()

        let newest = await iterator.next()

        XCTAssertEqual(newest?.targets.count, 1)
        XCTAssertEqual(newest?.targets.first?.state, .degraded(reason: "latest"))
    }

    func testTypedBridgePollDegradesOnlyKnownOverBudgetAdapter() async throws {
        let cdp = PerformanceCDPDouble()
        let health = HealthCenter()
        await health.updateTarget(.init(targetIdentifier: "target", adapterIdentifier: "wide-layout", state: .healthy))
        await health.updateTarget(.init(targetIdentifier: "target", adapterIdentifier: "markdown-semantic-theme", state: .healthy))
        let bridge = CDPPageRuntimeBridge(client: cdp, healthCenter: health, bundle: Bundle(for: Self.self))
        let target = CDPTarget(identifier: "target", url: TargetCoordinator.codexSurfaceURL)

        let measurements = try await bridge.pollPerformance(target: target)
        let snapshot = await health.snapshot()

        XCTAssertEqual(measurements.map(\.adapterIdentifier), [.wideLayout, .markdownSemanticTheme])
        XCTAssertEqual(
            snapshot.targets.first { $0.adapterIdentifier == "wide-layout" }?.state,
            .degraded(reason: DiagnosticErrorCode.adapterPerformanceBudgetExceeded.rawValue)
        )
        XCTAssertEqual(snapshot.targets.first { $0.adapterIdentifier == "markdown-semantic-theme" }?.state, .healthy)
        XCTAssertEqual(snapshot.targets.count, 2)
        let expressions = await cdp.expressions()
        XCTAssertEqual(expressions.count, 1)
        XCTAssertTrue(expressions[0].contains("performanceSnapshot"))
        XCTAssertFalse(expressions[0].contains("innerText"))
        XCTAssertFalse(expressions[0].lowercased().contains("cookie"))
        XCTAssertFalse(expressions[0].contains("outerHTML"))
    }

    func testTypedBridgePollTransitionsRecoverableWaitingBackToHealthy() async throws {
        let cdp = SequencedPerformanceCDPDouble()
        let health = HealthCenter()
        let bridge = CDPPageRuntimeBridge(client: cdp, healthCenter: health, bundle: Bundle(for: Self.self))
        let target = CDPTarget(identifier: "target-recovering", url: TargetCoordinator.codexSurfaceURL)

        let waitingMeasurements = try await bridge.pollPerformance(target: target)
        XCTAssertEqual(waitingMeasurements.first?.adapterIdentifier, .markdownSemanticTheme)
        XCTAssertEqual(waitingMeasurements.first?.isQualified, false)
        XCTAssertEqual(waitingMeasurements.first?.isRecoverable, true)
        var snapshot = await health.snapshot()
        XCTAssertEqual(
            snapshot.targets.first?.state,
            .waiting(reason: "adapter-reconcile-waiting")
        )

        let healthyMeasurements = try await bridge.pollPerformance(target: target)
        XCTAssertEqual(healthyMeasurements.first?.isQualified, true)
        XCTAssertEqual(healthyMeasurements.first?.isRecoverable, false)
        snapshot = await health.snapshot()
        XCTAssertEqual(snapshot.targets.first?.state, .healthy)
    }

    func testHealthSummaryCountsDegradedAdapterWithoutFailingHealthySibling() {
        let snapshot = RuntimeControllerSnapshot(
            runtime: .init(
                process: .running(processIdentifier: 91),
                lifecycle: .active(processIdentifier: 91, targetCount: 1),
                connection: .connected(generation: 4, webSocketURL: URL(string: "ws://127.0.0.1:5591")!),
                targets: [
                    .init(targetIdentifier: "same-target", adapterIdentifier: "slow-layout", state: .degraded(reason: "fixed-code")),
                    .init(targetIdentifier: "same-target", adapterIdentifier: "markdown", state: .healthy)
                ]
            ),
            isInitialized: true
        )

        let summary = DiagnosticHealthSummary(snapshot: snapshot)

        XCTAssertEqual(summary.state, .degraded)
        XCTAssertEqual(summary.targetCount, 1)
        XCTAssertEqual(summary.degradedAdapterCount, 1)
        XCTAssertEqual(summary.healthyAdapterCount, 1)
        XCTAssertEqual(summary.processCount, 1)
        XCTAssertEqual(summary.connectedCount, 1)
    }

    func testHealthSummaryReportsRecoverableWaitingSeparatelyFromDegradation() {
        let snapshot = RuntimeControllerSnapshot(
            runtime: .init(
                process: .running(processIdentifier: 92),
                lifecycle: .active(processIdentifier: 92, targetCount: 1),
                connection: .connected(generation: 5, webSocketURL: URL(string: "ws://127.0.0.1:5592")!),
                targets: [
                    .init(targetIdentifier: "same-target", adapterIdentifier: "wide-layout", state: .healthy),
                    .init(targetIdentifier: "same-target", adapterIdentifier: "markdown-semantic-theme", state: .waiting(reason: "page-not-ready"))
                ]
            ),
            isInitialized: true
        )

        let summary = DiagnosticHealthSummary(snapshot: snapshot)

        XCTAssertEqual(summary.state, .connecting)
        XCTAssertEqual(summary.healthyAdapterCount, 1)
        XCTAssertEqual(summary.waitingAdapterCount, 1)
        XCTAssertEqual(summary.degradedAdapterCount, 0)
    }

    func testHealthCenterKeepsOneBoundedEntryPerTargetAdapterKey() async {
        let health = HealthCenter()
        for index in 0..<1_000 {
            await health.updateTarget(.init(
                targetIdentifier: "target",
                adapterIdentifier: "wide-layout",
                state: index == 999 ? .degraded(reason: "budget") : .healthy
            ))
        }

        let snapshot = await health.snapshot()

        XCTAssertEqual(snapshot.targets.count, 1)
        XCTAssertEqual(snapshot.targets.first?.adapterIdentifier, "wide-layout")
        XCTAssertEqual(snapshot.targets.first?.state, .degraded(reason: "budget"))
    }

    func testHealthCenterHigherGenerationClearsOldStateAndRejectsOldMutations() async {
        let health = HealthCenter()
        await health.beginTarget(identifier: "target", generation: 10)
        await health.updateTarget(.init(
            targetIdentifier: "target",
            adapterIdentifier: "wide-layout",
            state: .degraded(reason: "old")
        ), generation: 10)

        await health.beginTarget(identifier: "target", generation: 11)
        await health.updateTarget(.init(
            targetIdentifier: "target",
            adapterIdentifier: "wide-layout",
            state: .healthy
        ), generation: 11)
        await health.updateTarget(.init(
            targetIdentifier: "target",
            adapterIdentifier: "wide-layout",
            state: .degraded(reason: "late-old-update")
        ), generation: 10)
        await health.removeTarget(identifier: "target", generation: 10)

        let snapshot = await health.snapshot()
        XCTAssertEqual(snapshot.targets, [
            .init(targetIdentifier: "target", adapterIdentifier: "wide-layout", state: .healthy)
        ])
    }

    func testHealthCenterSameGenerationRemoveLeavesTombstoneUntilNewerBegin() async {
        let health = HealthCenter()
        await health.beginTarget(identifier: "target", generation: 20)
        await health.updateTarget(.init(
            targetIdentifier: "target",
            adapterIdentifier: "wide-layout",
            state: .healthy
        ), generation: 20)
        await health.removeTarget(identifier: "target", generation: 20)
        await health.updateTarget(.init(
            targetIdentifier: "target",
            adapterIdentifier: "wide-layout",
            state: .degraded(reason: "late-same-generation")
        ), generation: 20)
        await health.beginTarget(identifier: "target", generation: 20)
        await health.updateTarget(.init(
            targetIdentifier: "target",
            adapterIdentifier: "wide-layout",
            state: .degraded(reason: "reopened-same-generation")
        ), generation: 20)

        let removedSnapshot = await health.snapshot()
        XCTAssertTrue(removedSnapshot.targets.isEmpty)

        await health.beginTarget(identifier: "target", generation: 21)
        await health.updateTarget(.init(
            targetIdentifier: "target",
            adapterIdentifier: "wide-layout",
            state: .healthy
        ), generation: 21)
        let newerSnapshot = await health.snapshot()
        XCTAssertEqual(newerSnapshot.targets.count, 1)
    }

    func testHealthCenterRuntimeGenerationAcceptsOnlyCurrentNonEndedMutations() async {
        let health = HealthCenter()
        await health.beginRuntime(generation: 10)
        await health.beginRuntimeTarget(
            targetIdentifier: "old-target",
            lifecycleGeneration: 10,
            targetRevision: 1
        )
        await health.degradeRuntime(
            targetIdentifier: "old-target",
            reason: "current",
            lifecycleGeneration: 10,
            targetRevision: 1
        )
        await health.clearRuntime(
            targetIdentifier: "old-target",
            lifecycleGeneration: 10,
            targetRevision: 0
        )
        await health.endRuntime(generation: 9)
        await health.beginRuntimeTarget(
            targetIdentifier: "future-target",
            lifecycleGeneration: 11,
            targetRevision: 1
        )
        await health.degradeRuntime(
            targetIdentifier: "future-target",
            reason: "not-begun",
            lifecycleGeneration: 11,
            targetRevision: 1
        )

        var snapshot = await health.snapshot()
        XCTAssertEqual(snapshot.targets, [
            .init(targetIdentifier: "old-target", adapterIdentifier: "runtime", state: .degraded(reason: "current"))
        ])

        await health.invalidateRuntimeTarget(
            targetIdentifier: "old-target",
            lifecycleGeneration: 10,
            targetRevision: 1
        )
        await health.degradeRuntime(
            targetIdentifier: "old-target",
            reason: "late-after-tombstone",
            lifecycleGeneration: 10,
            targetRevision: 1
        )
        await health.clearRuntime(
            targetIdentifier: "old-target",
            lifecycleGeneration: 10,
            targetRevision: 1
        )
        snapshot = await health.snapshot()
        XCTAssertTrue(snapshot.targets.isEmpty)

        await health.beginRuntimeTarget(
            targetIdentifier: "old-target",
            lifecycleGeneration: 10,
            targetRevision: 1
        )
        await health.degradeRuntime(
            targetIdentifier: "old-target",
            reason: "same-revision-reopen",
            lifecycleGeneration: 10,
            targetRevision: 1
        )
        snapshot = await health.snapshot()
        XCTAssertTrue(snapshot.targets.isEmpty)

        await health.beginRuntimeTarget(
            targetIdentifier: "old-target",
            lifecycleGeneration: 10,
            targetRevision: 2
        )
        await health.degradeRuntime(
            targetIdentifier: "old-target",
            reason: "newer-revision-reopened",
            lifecycleGeneration: 10,
            targetRevision: 2
        )
        snapshot = await health.snapshot()
        XCTAssertEqual(snapshot.targets, [
            .init(
                targetIdentifier: "old-target",
                adapterIdentifier: "runtime",
                state: .degraded(reason: "newer-revision-reopened")
            )
        ])

        await health.endRuntime(generation: 10)
        await health.degradeRuntime(
            targetIdentifier: "old-target",
            reason: "late-after-end",
            lifecycleGeneration: 10,
            targetRevision: 2
        )
        await health.beginRuntime(generation: 10)
        await health.beginRuntimeTarget(
            targetIdentifier: "old-target",
            lifecycleGeneration: 10,
            targetRevision: 3
        )
        await health.degradeRuntime(
            targetIdentifier: "old-target",
            reason: "same-generation-reopen",
            lifecycleGeneration: 10,
            targetRevision: 3
        )
        snapshot = await health.snapshot()
        XCTAssertTrue(snapshot.targets.isEmpty)

        await health.beginRuntime(generation: 11)
        await health.beginRuntimeTarget(
            targetIdentifier: "new-target",
            lifecycleGeneration: 11,
            targetRevision: 1
        )
        await health.degradeRuntime(
            targetIdentifier: "new-target",
            reason: "new-current",
            lifecycleGeneration: 11,
            targetRevision: 1
        )
        snapshot = await health.snapshot()
        XCTAssertEqual(snapshot.targets, [
            .init(targetIdentifier: "new-target", adapterIdentifier: "runtime", state: .degraded(reason: "new-current"))
        ])
    }

    func testHealthCenterRuntimeLifecycleDoesNotMutateBridgeHealthOrGeneration() async {
        let health = HealthCenter()
        await health.beginTarget(identifier: "shared-target", generation: 40)
        await health.updateTarget(.init(
            targetIdentifier: "shared-target",
            adapterIdentifier: "wide-layout",
            state: .healthy
        ), generation: 40)

        await health.beginRuntime(generation: 100)
        await health.beginRuntimeTarget(
            targetIdentifier: "shared-target",
            lifecycleGeneration: 100,
            targetRevision: 1
        )
        await health.degradeRuntime(
            targetIdentifier: "shared-target",
            reason: "runtime-failure",
            lifecycleGeneration: 100,
            targetRevision: 1
        )
        await health.beginRuntime(generation: 101)
        await health.beginRuntimeTarget(
            targetIdentifier: "replacement-target",
            lifecycleGeneration: 101,
            targetRevision: 1
        )
        await health.degradeRuntime(
            targetIdentifier: "replacement-target",
            reason: "new-runtime",
            lifecycleGeneration: 101,
            targetRevision: 1
        )
        await health.clearRuntime(
            targetIdentifier: "replacement-target",
            lifecycleGeneration: 101,
            targetRevision: 1
        )
        await health.endRuntime(generation: 101)

        await health.updateTarget(.init(
            targetIdentifier: "shared-target",
            adapterIdentifier: "wide-layout",
            state: .degraded(reason: "bridge-generation-still-current")
        ), generation: 40)
        await health.updateTarget(.init(
            targetIdentifier: "shared-target",
            adapterIdentifier: "runtime",
            state: .degraded(reason: "unversioned-bypass")
        ))
        await health.updateTarget(.init(
            targetIdentifier: "shared-target",
            adapterIdentifier: "runtime",
            state: .degraded(reason: "bridge-generation-bypass")
        ), generation: 40)

        let snapshot = await health.snapshot()
        XCTAssertEqual(snapshot.targets, [
            .init(
                targetIdentifier: "shared-target",
                adapterIdentifier: "wide-layout",
                state: .degraded(reason: "bridge-generation-still-current")
            )
        ])
    }

    func testHealthCenterLegacyCallsPreserveVersionOrderingMetadata() async {
        let health = HealthCenter()
        await health.beginTarget(identifier: "target", generation: 30)
        await health.updateTarget(.init(
            targetIdentifier: "target",
            adapterIdentifier: "wide-layout",
            state: .healthy
        ))
        await health.updateTarget(.init(
            targetIdentifier: "target",
            adapterIdentifier: "wide-layout",
            state: .degraded(reason: "versioned-update-still-active")
        ), generation: 30)

        var snapshot = await health.snapshot()
        XCTAssertEqual(snapshot.targets.first?.state, .degraded(reason: "versioned-update-still-active"))

        await health.removeTarget(identifier: "target")
        await health.updateTarget(.init(
            targetIdentifier: "target",
            adapterIdentifier: "wide-layout",
            state: .degraded(reason: "late-versioned-update")
        ), generation: 30)
        snapshot = await health.snapshot()
        XCTAssertTrue(snapshot.targets.isEmpty)

        await health.updateTarget(.init(
            targetIdentifier: "target",
            adapterIdentifier: "legacy-adapter",
            state: .healthy
        ))
        await health.updateTarget(.init(
            targetIdentifier: "target",
            adapterIdentifier: "wide-layout",
            state: .degraded(reason: "still-tombstoned")
        ), generation: 30)
        snapshot = await health.snapshot()
        XCTAssertEqual(snapshot.targets.map(\.adapterIdentifier), ["legacy-adapter"])

        await health.beginTarget(identifier: "target", generation: 31)
        await health.updateTarget(.init(
            targetIdentifier: "target",
            adapterIdentifier: "wide-layout",
            state: .healthy
        ), generation: 31)
        snapshot = await health.snapshot()
        XCTAssertEqual(snapshot.targets.map(\.adapterIdentifier), ["wide-layout"])
    }
}

private actor PerformanceCDPDouble: CDPCommanding {
    private var recordedExpressions: [String] = []

    func request(method: String, params: JSONValue?, sessionIdentifier: String?, timeout: Duration?) -> JSONValue? {
        if method == "Target.attachToTarget" {
            return .object(["sessionId": .string("performance-session")])
        }
        guard method == "Runtime.evaluate", let expression = params?["expression"]?.stringValue else {
            return .object([:])
        }
        recordedExpressions.append(expression)
        return .object(["result": .object(["value": .array([
            .object([
                "adapterId": .string("wide-layout"),
                "strikeCount": .number(3),
                "durationMilliseconds": .number(9),
                "degraded": .bool(true),
                "qualified": .bool(true)
            ]),
            .object([
                "adapterId": .string("markdown-semantic-theme"),
                "strikeCount": .number(0),
                "durationMilliseconds": .number(2),
                "degraded": .bool(false),
                "qualified": .bool(true)
            ]),
            .object([
                "adapterId": .string("PRIVATE_CONVERSATION_TEXT"),
                "strikeCount": .number(99),
                "durationMilliseconds": .number(99),
                "degraded": .bool(true),
                "qualified": .bool(true)
            ])
        ])])])
    }

    func expressions() -> [String] { recordedExpressions }
}

private actor SequencedPerformanceCDPDouble: CDPCommanding {
    private var pollCount = 0

    func request(method: String, params: JSONValue?, sessionIdentifier: String?, timeout: Duration?) -> JSONValue? {
        if method == "Target.attachToTarget" {
            return .object(["sessionId": .string("recovering-performance-session")])
        }
        guard method == "Runtime.evaluate" else { return .object([:]) }
        pollCount += 1
        let isWaiting = pollCount == 1
        return .object(["result": .object(["value": .array([
            .object([
                "adapterId": .string("markdown-semantic-theme"),
                "strikeCount": .number(0),
                "durationMilliseconds": .number(2),
                "degraded": .bool(false),
                "qualified": .bool(!isWaiting),
                "recoverable": .bool(isWaiting)
            ])
        ])])])
    }
}
