import Foundation
import JavaScriptCore
import XCTest
@testable import ExtensionCore

final class CDPPageRuntimeBridgeTests: XCTestCase {
    func testUndefinedSideEffectResultsContinueThroughHandshakeAndAdapterExecution() async throws {
        XCTAssertEqual(CDPPageRuntimeBridge.implementationRevision, 15)
        let cdp = BridgeCDPDouble(sideEffectsReturnUndefined: true)
        let bridge = CDPPageRuntimeBridge(
            client: cdp,
            healthCenter: HealthCenter(),
            bundle: Bundle(for: Self.self)
        )
        let target = CDPTarget(identifier: "target-undefined-side-effects", url: TargetCoordinator.codexSurfaceURL)

        let results = try await bridge.apply(configuration: .defaultConfiguration, to: target, operation: .install)

        XCTAssertEqual(results.count, 4)
        XCTAssertTrue(results.allSatisfy { $0.status == .installed && $0.error == nil })
        let expressions = await cdp.evaluateExpressions()
        XCTAssertTrue(expressions.contains { $0.contains("handshake(0)") })
        XCTAssertEqual(expressions.filter { $0.contains(".execute(") }.count, 4)
    }

    func testFreshRuntimeFullInstallRunsOnePassAndAcknowledgesHydration() async throws {
        let cdp = BridgeCDPDouble(rehydrationRequired: true)
        let bridge = CDPPageRuntimeBridge(
            client: cdp,
            healthCenter: HealthCenter(),
            bundle: Bundle(for: Self.self)
        )
        let target = CDPTarget(identifier: "target-full-rehydrate", url: TargetCoordinator.codexSurfaceURL)

        let results = try await bridge.apply(configuration: .defaultConfiguration, to: target, operation: .install)

        XCTAssertEqual(results.count, 4)
        let expressions = await cdp.evaluateExpressions()
        XCTAssertEqual(expressions.filter { $0.contains(".execute(") }.count, 4)
        XCTAssertEqual(expressions.filter { $0.contains("window.__codexAppExtensionV2.markHydrated()") }.count, 1)
    }

    func testProbeWithoutRemoteValueFailsValueRequiredEvaluation() async throws {
        let cdp = BridgeCDPDouble(missingProbeValue: true)
        let bridge = CDPPageRuntimeBridge(
            client: cdp,
            healthCenter: HealthCenter(),
            bundle: Bundle(for: Self.self)
        )
        let target = CDPTarget(identifier: "target-probe-missing-value", url: TargetCoordinator.codexSurfaceURL)

        do {
            _ = try await bridge.probe(target: target, requiredAnchors: TargetCoordinator.requiredAnchors)
            XCTFail("probe 必须要求 Runtime.evaluate result.value")
        } catch let error as PageRuntimeBridgeError {
            XCTAssertEqual(error, .invalidResponse("Runtime.evaluate"))
        }
    }

    func testSideEffectWithoutValueRejectsNonUndefinedRemoteObject() async throws {
        let cdp = BridgeCDPDouble(sideEffectsReturnTypeWithoutValue: "object")
        let bridge = CDPPageRuntimeBridge(
            client: cdp,
            healthCenter: HealthCenter(),
            bundle: Bundle(for: Self.self)
        )
        let target = CDPTarget(identifier: "target-side-effect-object", url: TargetCoordinator.codexSurfaceURL)

        do {
            _ = try await bridge.apply(configuration: .defaultConfiguration, to: target, operation: .install)
            XCTFail("side-effect 缺失 value 时只允许 undefined RemoteObject")
        } catch let error as PageRuntimeBridgeError {
            XCTAssertEqual(error, .invalidResponse("Runtime.evaluate"))
        }
        let expressions = await cdp.evaluateExpressions()
        XCTAssertFalse(expressions.contains { $0.contains("handshake(0)") })
    }

    func testExceptionDetailsRejectsSideEffectEvaluationAndStopsPipeline() async throws {
        let cdp = BridgeCDPDouble(exceptionExpressionMarker: "bootstrapCodexAppExtensionV2")
        let bridge = CDPPageRuntimeBridge(
            client: cdp,
            healthCenter: HealthCenter(),
            bundle: Bundle(for: Self.self)
        )
        let target = CDPTarget(identifier: "target-bootstrap-exception", url: TargetCoordinator.codexSurfaceURL)

        do {
            _ = try await bridge.apply(configuration: .defaultConfiguration, to: target, operation: .install)
            XCTFail("exceptionDetails 必须阻断 side-effect evaluation")
        } catch let error as PageRuntimeBridgeError {
            XCTAssertEqual(error, .invalidResponse("Runtime.evaluate"))
        }
        let expressions = await cdp.evaluateExpressions()
        XCTAssertFalse(expressions.contains { $0.contains("handshake(0)") })
        XCTAssertFalse(expressions.contains { $0.contains(".execute(") })
    }

    func testFlattenedAttachProbeIsCountOnlyAndScriptsPrecedeHandshakeAndEnvelopes() async throws {
        let cdp = BridgeCDPDouble()
        let health = HealthCenter()
        let bridge = CDPPageRuntimeBridge(client: cdp, healthCenter: health, bundle: Bundle(for: Self.self))
        let target = CDPTarget(identifier: "target-1", url: TargetCoordinator.codexSurfaceURL)

        let probe = try await bridge.probe(target: target, requiredAnchors: TargetCoordinator.requiredAnchors)
        XCTAssertTrue(probe.isCodexSurface)
        XCTAssertEqual(probe.counts, [.layoutRoot: 1, .threadScroller: 1, .composer: 1])
        _ = try await bridge.apply(configuration: .defaultConfiguration, to: target, operation: .install)

        let commands = await cdp.commands()
        let attach = try XCTUnwrap(commands.first)
        XCTAssertEqual(attach.method, "Target.attachToTarget")
        XCTAssertEqual(attach.params?["flatten"], .bool(true))
        XCTAssertNil(attach.session)
        let evaluations = commands.filter { $0.method == "Runtime.evaluate" }
        XCTAssertTrue(evaluations.allSatisfy { $0.session == "session-1" })
        let probeExpression = try XCTUnwrap(evaluations.first?.params?["expression"]?.stringValue)
        XCTAssertTrue(probeExpression.contains("querySelectorAll"))
        XCTAssertTrue(probeExpression.contains("markedComposerSelector"))
        XCTAssertTrue(probeExpression.contains("fallbackComposerSelector"))
        XCTAssertTrue(probeExpression.contains("threadScroller === 0"))
        XCTAssertTrue(probeExpression.contains("aria-hidden"))
        XCTAssertTrue(probeExpression.contains("getComputedStyle"))
        XCTAssertFalse(probeExpression.contains("innerText"))
        XCTAssertFalse(probeExpression.contains("textContent"))
        XCTAssertFalse(probeExpression.contains("innerHTML"))
        XCTAssertFalse(probeExpression.contains("outerHTML"))
        XCTAssertFalse(probeExpression.lowercased().contains("draft"))
        XCTAssertFalse(probeExpression.lowercased().contains("cookie"))
        XCTAssertFalse(probeExpression.contains("value"))
        XCTAssertFalse(probeExpression.contains("qualified"))

        let expressions = evaluations.compactMap { $0.params?["expression"]?.stringValue }
        let bootstrap = try XCTUnwrap(expressions.firstIndex { $0.contains("bootstrapCodexAppExtensionV2") })
        let handshake = try XCTUnwrap(expressions.firstIndex { $0.contains("handshake(0)") })
        let wideAdapter = try XCTUnwrap(expressions.firstIndex { $0.contains("registerWideLayout") })
        let firstEnvelope = try XCTUnwrap(expressions.firstIndex { $0.contains(".execute(") })
        XCTAssertLessThan(bootstrap, handshake)
        XCTAssertLessThan(handshake, wideAdapter)
        XCTAssertLessThan(wideAdapter, firstEnvelope)

        for adapter in ["wide-layout", "header-offset", "ime-enter-guard", "markdown-semantic-theme"] {
            let scriptIndex = try XCTUnwrap(expressions.firstIndex { expression in
                expression.contains(Self.registrationMarker(for: adapter))
            })
            let envelopeIndex = try XCTUnwrap(expressions.firstIndex { expression in
                expression.contains(".execute(") && expression.contains(#""adapterId":"\#(adapter)""#)
            })
            XCTAssertLessThan(scriptIndex, envelopeIndex, adapter)
        }
    }

    func testProbePreservesComposerOnlySurfaceCountsAndRejectsDuplicateAnchors() async throws {
        let emptyCDP = BridgeCDPDouble(probeCounts: [.layoutRoot: 1, .threadScroller: 0, .composer: 1])
        let emptyBridge = CDPPageRuntimeBridge(
            client: emptyCDP,
            healthCenter: HealthCenter(),
            bundle: Bundle(for: Self.self)
        )
        let target = CDPTarget(identifier: "target-empty-composer", url: TargetCoordinator.codexSurfaceURL)

        let emptyProbe = try await emptyBridge.probe(
            target: target,
            requiredAnchors: TargetCoordinator.requiredAnchors
        )

        XCTAssertEqual(emptyProbe.counts, [.layoutRoot: 1, .threadScroller: 0, .composer: 1])
        XCTAssertEqual(emptyProbe.matchedAnchors, [.layoutRoot, .composer])
        XCTAssertTrue(emptyProbe.isCodexSurface)

        let duplicateCDP = BridgeCDPDouble(probeCounts: [.layoutRoot: 1, .threadScroller: 0, .composer: 2])
        let duplicateBridge = CDPPageRuntimeBridge(
            client: duplicateCDP,
            healthCenter: HealthCenter(),
            bundle: Bundle(for: Self.self)
        )
        let duplicateProbe = try await duplicateBridge.probe(
            target: .init(identifier: "target-duplicate-composer", url: TargetCoordinator.codexSurfaceURL),
            requiredAnchors: TargetCoordinator.requiredAnchors
        )

        XCTAssertEqual(duplicateProbe.counts, [.layoutRoot: 1, .threadScroller: 0, .composer: 2])
        XCTAssertFalse(duplicateProbe.isCodexSurface)
    }

    func testProbeExpressionExecutesFallbackPriorityVisibilityAndContainmentRules() async throws {
        let cdp = BridgeCDPDouble()
        let bridge = CDPPageRuntimeBridge(
            client: cdp,
            healthCenter: HealthCenter(),
            bundle: Bundle(for: Self.self)
        )
        _ = try await bridge.probe(
            target: .init(identifier: "target-probe-expression", url: TargetCoordinator.codexSurfaceURL),
            requiredAnchors: TargetCoordinator.requiredAnchors
        )
        let expressions = await cdp.evaluateExpressions()
        let expression = try XCTUnwrap(expressions.first)
        let context = try XCTUnwrap(JSContext())
        context.exceptionHandler = { _, exception in
            XCTFail("probe expression JavaScript exception: \(exception?.toString() ?? "unknown")")
        }
        context.evaluateScript(Self.probeExpressionDOM)

        func counts(_ setup: String) throws -> [String: Int] {
            context.evaluateScript(setup)
            let object = try XCTUnwrap(context.evaluateScript(expression)?.toDictionary() as? [String: Any])
            return [
                "layoutRoot": try XCTUnwrap(object["layoutRoot"] as? Int),
                "threadScroller": try XCTUnwrap(object["threadScroller"] as? Int),
                "composer": try XCTUnwrap(object["composer"] as? Int)
            ]
        }

        XCTAssertEqual(
            try counts("__setProbeNodes([], [__visibleFallback]);"),
            ["layoutRoot": 1, "threadScroller": 0, "composer": 1]
        )
        XCTAssertEqual(
            try counts("__setProbeNodes([], [__hiddenFallback]);"),
            ["layoutRoot": 1, "threadScroller": 0, "composer": 0]
        )
        XCTAssertEqual(
            try counts("__setProbeNodes([], [__outsideFallback]);"),
            ["layoutRoot": 1, "threadScroller": 0, "composer": 0]
        )
        XCTAssertEqual(
            try counts("__setProbeNodes([], [__visibleFallback, __secondVisibleFallback]);"),
            ["layoutRoot": 1, "threadScroller": 0, "composer": 2]
        )
        XCTAssertEqual(
            try counts("__setProbeNodes([__visibleMarked], [__visibleMarked, __visibleFallback, __secondVisibleFallback]);"),
            ["layoutRoot": 1, "threadScroller": 0, "composer": 1]
        )
        XCTAssertEqual(
            try counts("__setProbeNodes([__hiddenMarked], [__hiddenMarked, __visibleFallback]);"),
            ["layoutRoot": 1, "threadScroller": 0, "composer": 1]
        )
    }

    func testMissingAdapterSourceDegradesOnlyThatAdapterSkipsExecuteAndUpdateStillThrows() async throws {
        let cdp = BridgeCDPDouble()
        let health = HealthCenter()
        let bridge = CDPPageRuntimeBridge(
            client: cdp,
            scriptLoader: BridgeScriptLoaderDouble(missingAdapter: .headerOffset),
            healthCenter: health,
            bundle: Bundle(for: Self.self)
        )
        let target = CDPTarget(identifier: "target-source-missing", url: TargetCoordinator.codexSurfaceURL)

        let installResults = try await bridge.apply(configuration: .defaultConfiguration, to: target, operation: .install)

        XCTAssertEqual(installResults.count, 4)
        XCTAssertEqual(installResults.first { $0.adapterId == "header-offset" }?.status, .degraded)
        XCTAssertEqual(installResults.first { $0.adapterId == "header-offset" }?.error?.code, "adapter-source-load-failed")
        let installExpressions = await cdp.evaluateExpressions()
        XCTAssertFalse(installExpressions.contains { $0.contains(".execute(") && $0.contains(#""adapterId":"header-offset""#) })
        for sibling in ["wide-layout", "ime-enter-guard", "markdown-semantic-theme"] {
            XCTAssertTrue(installExpressions.contains { $0.contains(".execute(") && $0.contains(#""adapterId":"\#(sibling)""#) }, sibling)
        }

        do {
            _ = try await bridge.apply(configuration: .defaultConfiguration, to: target, operation: .update)
            XCTFail("事务 update 的 adapter source 缺失必须触发回滚")
        } catch let error as PageRuntimeBridgeError {
            XCTAssertEqual(error, .adapterFailures(["header-offset"]))
        }
        let snapshot = await health.snapshot()
        XCTAssertEqual(snapshot.targets.first { $0.adapterIdentifier == "header-offset" }?.state, .degraded(reason: "adapter-source-load-failed"))
        XCTAssertTrue(snapshot.targets.filter { $0.adapterIdentifier != "header-offset" }.allSatisfy { $0.state == .healthy })
    }

    func testAdapterScriptEvaluationExceptionDegradesOnlyThatAdapterAndContinuesSiblings() async throws {
        let cdp = BridgeCDPDouble()
        let health = HealthCenter()
        let bridge = CDPPageRuntimeBridge(
            client: cdp,
            scriptLoader: BridgeScriptLoaderDouble(evaluationFailureAdapter: .imeEnterGuard),
            healthCenter: health,
            bundle: Bundle(for: Self.self)
        )
        let target = CDPTarget(identifier: "target-script-evaluation", url: TargetCoordinator.codexSurfaceURL)

        let results = try await bridge.apply(configuration: .defaultConfiguration, to: target, operation: .install)

        XCTAssertEqual(results.count, 4)
        XCTAssertEqual(results.first { $0.adapterId == "ime-enter-guard" }?.status, .degraded)
        XCTAssertEqual(results.first { $0.adapterId == "ime-enter-guard" }?.error?.code, "adapter-script-evaluation-failed")
        let expressions = await cdp.evaluateExpressions()
        XCTAssertTrue(expressions.contains { $0.contains("fixture-script-evaluation-failure:ime-enter-guard") })
        XCTAssertFalse(expressions.contains { $0.contains(".execute(") && $0.contains(#""adapterId":"ime-enter-guard""#) })
        XCTAssertTrue(expressions.contains { $0.contains(".execute(") && $0.contains(#""adapterId":"markdown-semantic-theme""#) })
        let snapshot = await health.snapshot()
        XCTAssertEqual(snapshot.targets.first { $0.adapterIdentifier == "ime-enter-guard" }?.state, .degraded(reason: "adapter-script-evaluation-failed"))
        XCTAssertTrue(snapshot.targets.filter { $0.adapterIdentifier != "ime-enter-guard" }.allSatisfy { $0.state == .healthy })
    }

    func testBootstrapSourceFailureBlocksHandshakeAndEveryAdapter() async throws {
        let cdp = BridgeCDPDouble()
        let bridge = CDPPageRuntimeBridge(
            client: cdp,
            scriptLoader: BridgeScriptLoaderDouble(failsBootstrap: true),
            healthCenter: HealthCenter(),
            bundle: Bundle(for: Self.self)
        )
        let target = CDPTarget(identifier: "target-bootstrap-missing", url: TargetCoordinator.codexSurfaceURL)

        do {
            _ = try await bridge.apply(configuration: .defaultConfiguration, to: target, operation: .install)
            XCTFail("bootstrap 资源失败必须整体阻断")
        } catch let error as FeatureResourceError {
            XCTAssertEqual(error, .missingResource("PageRuntime/bootstrap.js"))
        }
        let expressions = await cdp.evaluateExpressions()
        XCTAssertTrue(expressions.isEmpty)
    }

    func testSingleAdapterFailureDegradesOnlyThatAdapterAndContinues() async throws {
        let cdp = BridgeCDPDouble(failingAdapter: "header-offset")
        let health = HealthCenter()
        let bridge = CDPPageRuntimeBridge(client: cdp, healthCenter: health, bundle: Bundle(for: Self.self))
        let target = CDPTarget(identifier: "target-2", url: TargetCoordinator.codexSurfaceURL)

        let results = try await bridge.apply(configuration: .defaultConfiguration, to: target, operation: .install)
        XCTAssertEqual(results.count, 4)
        XCTAssertEqual(results.first { $0.adapterId == "header-offset" }?.status, .degraded)
        XCTAssertEqual(results.first { $0.adapterId == "header-offset" }?.error?.code, "fixture-failure")
        let snapshot = await health.snapshot()
        XCTAssertEqual(snapshot.targets.count, 4)
        XCTAssertEqual(snapshot.targets.first { $0.adapterIdentifier == "header-offset" }?.state, .degraded(reason: "fixture-failure"))
        XCTAssertTrue(snapshot.targets.filter { $0.adapterIdentifier != "header-offset" }.allSatisfy { $0.state == .healthy })
    }

    func testCandidateUpdateFailureThrowsAfterPreservingSuccessfulAdapters() async throws {
        let cdp = BridgeCDPDouble(failingAdapter: "header-offset", failingOperation: "update")
        let health = HealthCenter()
        let bridge = CDPPageRuntimeBridge(client: cdp, healthCenter: health, bundle: Bundle(for: Self.self))
        let target = CDPTarget(identifier: "target-update", url: TargetCoordinator.codexSurfaceURL)
        _ = try await bridge.apply(configuration: .defaultConfiguration, to: target, operation: .install)

        do {
            _ = try await bridge.apply(configuration: .defaultConfiguration, to: target, operation: .update)
            XCTFail("在线 candidate update 单项失败必须触发事务回滚")
        } catch let error as PageRuntimeBridgeError {
            XCTAssertEqual(error, .adapterFailures(["header-offset"]))
        }
        let snapshot = await health.snapshot()
        XCTAssertEqual(snapshot.targets.first { $0.adapterIdentifier == "header-offset" }?.state, .degraded(reason: "fixture-failure"))
        XCTAssertTrue(snapshot.targets.filter { $0.adapterIdentifier != "header-offset" }.allSatisfy { $0.state == .healthy })
    }

    func testFreshRuntimeSelectedUpdateRetriesIncompleteHydrationWithoutBlockingSelectedTransaction() async throws {
        let cdp = BridgeCDPDouble(
            failingAdapter: "ime-enter-guard",
            failingOperation: "install",
            failingRequestCount: 1,
            rehydrationRequired: true
        )
        let health = HealthCenter()
        let bridge = CDPPageRuntimeBridge(client: cdp, healthCenter: health, bundle: Bundle(for: Self.self))
        let target = CDPTarget(identifier: "target-selected-rehydrate", url: TargetCoordinator.codexSurfaceURL)

        let results = try await bridge.apply(
            configuration: .defaultConfiguration,
            to: target,
            operation: .update,
            selectedIDs: [.wideLayout]
        )

        XCTAssertEqual(results.map(\.adapterId), ["wide-layout"])
        XCTAssertEqual(results.first?.status, .updated)
        var expressions = await cdp.evaluateExpressions()
        var installExpressions = expressions.filter { $0.contains(".execute(") && $0.contains(#""operation":"install""#) }
        XCTAssertEqual(installExpressions.count, 4)
        XCTAssertTrue(["wide-layout", "header-offset", "ime-enter-guard", "markdown-semantic-theme"].allSatisfy { adapter in
            installExpressions.contains { $0.contains(#""adapterId":"\#(adapter)""#) }
        })
        XCTAssertEqual(expressions.filter { $0.contains("window.__codexAppExtensionV2.markHydrated()") }.count, 0)
        let selectedUpdateIndex = try XCTUnwrap(expressions.firstIndex {
            $0.contains(".execute(")
                && $0.contains(#""adapterId":"wide-layout""#)
                && $0.contains(#""operation":"update""#)
        })
        XCTAssertTrue(expressions.indices.filter { expressions[$0].contains(#""operation":"install""#) }.allSatisfy { $0 < selectedUpdateIndex })
        let snapshot = await health.snapshot()
        XCTAssertEqual(snapshot.targets.first { $0.adapterIdentifier == "ime-enter-guard" }?.state, .degraded(reason: "fixture-failure"))
        XCTAssertEqual(snapshot.targets.first { $0.adapterIdentifier == "wide-layout" }?.state, .healthy)

        let retriedResults = try await bridge.apply(
            configuration: .defaultConfiguration,
            to: target,
            operation: .update,
            selectedIDs: [.wideLayout]
        )
        XCTAssertEqual(retriedResults.map(\.adapterId), ["wide-layout"])
        XCTAssertEqual(retriedResults.first?.status, .updated)
        expressions = await cdp.evaluateExpressions()
        installExpressions = expressions.filter { $0.contains(".execute(") && $0.contains(#""operation":"install""#) }
        XCTAssertEqual(installExpressions.count, 8)
        XCTAssertEqual(expressions.filter { $0.contains("window.__codexAppExtensionV2.markHydrated()") }.count, 1)
        XCTAssertEqual(expressions.filter {
            $0.contains(#""adapterId":"wide-layout""#) && $0.contains(#""operation":"update""#)
        }.count, 2)
        let hydratedSnapshot = await health.snapshot()
        XCTAssertEqual(hydratedSnapshot.targets.first { $0.adapterIdentifier == "ime-enter-guard" }?.state, .healthy)
    }

    func testFreshRuntimeSelectedUpdateStillThrowsForSelectedAdapterFailure() async throws {
        let cdp = BridgeCDPDouble(
            failingAdapter: "wide-layout",
            failingOperation: "update",
            rehydrationRequired: true
        )
        let bridge = CDPPageRuntimeBridge(client: cdp, healthCenter: HealthCenter(), bundle: Bundle(for: Self.self))
        let target = CDPTarget(identifier: "target-selected-rehydrate-failure", url: TargetCoordinator.codexSurfaceURL)

        do {
            _ = try await bridge.apply(
                configuration: .defaultConfiguration,
                to: target,
                operation: .update,
                selectedIDs: [.wideLayout]
            )
            XCTFail("补水成功后，所选 adapter 的 update 失败仍必须触发事务失败")
        } catch let error as PageRuntimeBridgeError {
            XCTAssertEqual(error, .adapterFailures(["wide-layout"]))
        }
        let expressions = await cdp.evaluateExpressions()
        XCTAssertEqual(expressions.filter { $0.contains("window.__codexAppExtensionV2.markHydrated()") }.count, 1)
        XCTAssertEqual(expressions.filter {
            $0.contains(#""adapterId":"wide-layout""#) && $0.contains(#""operation":"update""#)
        }.count, 1)
    }

    func testDiagnoseFailureReturnsPartialResultsAndKeepsOnlyFailedAdapterDegraded() async throws {
        let cdp = BridgeCDPDouble(failingAdapter: "header-offset", failingOperation: "diagnose")
        let health = HealthCenter()
        let bridge = CDPPageRuntimeBridge(client: cdp, healthCenter: health, bundle: Bundle(for: Self.self))
        let target = CDPTarget(identifier: "target-diagnose", url: TargetCoordinator.codexSurfaceURL)
        _ = try await bridge.apply(configuration: .defaultConfiguration, to: target, operation: .install)

        let results = try await bridge.apply(configuration: .defaultConfiguration, to: target, operation: .diagnose)

        XCTAssertEqual(results.count, 4)
        XCTAssertEqual(results.first { $0.adapterId == "header-offset" }?.status, .degraded)
        XCTAssertEqual(results.first { $0.adapterId == "header-offset" }?.error?.code, "fixture-failure")
        let snapshot = await health.snapshot()
        XCTAssertEqual(snapshot.targets.first { $0.adapterIdentifier == "header-offset" }?.state, .degraded(reason: "fixture-failure"))
        XCTAssertTrue(snapshot.targets.filter { $0.adapterIdentifier != "header-offset" }.allSatisfy { $0.state == .healthy })
    }

    func testInitialUnqualifiedAdapterDegradesWithoutBlockingTargetActivation() async throws {
        let cdp = BridgeCDPDouble(unqualifiedAdapter: "markdown-semantic-theme")
        let health = HealthCenter()
        let bridge = CDPPageRuntimeBridge(client: cdp, healthCenter: health, bundle: Bundle(for: Self.self))
        let target = CDPTarget(identifier: "target-unqualified", url: TargetCoordinator.codexSurfaceURL)

        let results = try await bridge.apply(configuration: .defaultConfiguration, to: target, operation: .install)

        XCTAssertEqual(results.count, 4)
        XCTAssertEqual(results.first { $0.adapterId == "markdown-semantic-theme" }?.status, .degraded)
        XCTAssertEqual(results.first { $0.adapterId == "markdown-semantic-theme" }?.error?.code, "markdown-candidate-missing")
        let snapshot = await health.snapshot()
        XCTAssertEqual(
            snapshot.targets.first { $0.adapterIdentifier == "markdown-semantic-theme" }?.state,
            .degraded(reason: "markdown-candidate-missing")
        )
        XCTAssertTrue(snapshot.targets.filter { $0.adapterIdentifier != "markdown-semantic-theme" }.allSatisfy { $0.state == .healthy })
    }

    func testRecoverableUnqualifiedUpdateWaitsWithoutRollbackAndExecutesOnlySelectedAdapter() async throws {
        let cdp = BridgeCDPDouble(recoverableAdapter: "markdown-semantic-theme")
        let health = HealthCenter()
        let bridge = CDPPageRuntimeBridge(client: cdp, healthCenter: health, bundle: Bundle(for: Self.self))
        let target = CDPTarget(identifier: "target-recoverable", url: TargetCoordinator.codexSurfaceURL)

        let results = try await bridge.apply(
            configuration: .defaultConfiguration,
            to: target,
            operation: .update,
            selectedIDs: [.markdownSemanticTheme]
        )

        XCTAssertEqual(results, [
            .init(adapterId: "markdown-semantic-theme", status: .waiting, error: nil)
        ])
        let snapshot = await health.snapshot()
        XCTAssertEqual(snapshot.targets, [
            .init(
                targetIdentifier: target.identifier,
                adapterIdentifier: "markdown-semantic-theme",
                state: .waiting(reason: "markdown-candidate-missing")
            )
        ])
        let expressions = await cdp.evaluateExpressions()
        let executedAdapters = ["wide-layout", "header-offset", "ime-enter-guard", "markdown-semantic-theme"].filter { adapter in
            expressions.contains { $0.contains(".execute(") && $0.contains(#""adapterId":"\#(adapter)""#) }
        }
        XCTAssertEqual(executedAdapters, ["markdown-semantic-theme"])
        XCTAssertFalse(expressions.contains { $0.contains("registerWideLayout") })
        XCTAssertFalse(expressions.contains { $0.contains("registerHeaderOffset") })
        XCTAssertFalse(expressions.contains { $0.contains("registerIMEEnterGuard") })
        XCTAssertTrue(expressions.contains { $0.contains("registerMarkdownSemanticTheme") })
    }

    func testInvalidateClearsHealthAndDetachesSession() async throws {
        let cdp = BridgeCDPDouble(failingAdapter: "ime-enter-guard", failingOperation: "uninstall")
        let health = HealthCenter()
        let bridge = CDPPageRuntimeBridge(client: cdp, healthCenter: health, bundle: Bundle(for: Self.self))
        let target = CDPTarget(identifier: "target-3", url: TargetCoordinator.codexSurfaceURL)
        _ = try await bridge.apply(configuration: .defaultConfiguration, to: target, operation: .install)

        await bridge.invalidate(targetIdentifier: target.identifier)
        let snapshotAfterInvalidation = await health.snapshot()
        XCTAssertTrue(snapshotAfterInvalidation.targets.isEmpty)
        let commands = await cdp.commands()
        let detachIndex = try XCTUnwrap(commands.firstIndex { $0.method == "Target.detachFromTarget" })
        let uninstallIndices = commands.indices.filter {
            commands[$0].params?["expression"]?.stringValue?.contains(#""operation":"uninstall""#) == true
        }
        XCTAssertEqual(uninstallIndices.count, 4)
        XCTAssertTrue(uninstallIndices.allSatisfy { $0 < detachIndex })
    }

    func testDelayedOldRevisionCleanupCannotRemoveNewRevisionHealth() async throws {
        let cdp = RevisionRaceBridgeCDPDouble()
        let health = HealthCenter()
        let bridge = CDPPageRuntimeBridge(client: cdp, healthCenter: health, bundle: Bundle(for: Self.self))
        let target = CDPTarget(identifier: "target-revision-cleanup-race", url: TargetCoordinator.codexSurfaceURL)

        _ = try await bridge.apply(configuration: .defaultConfiguration, to: target, operation: .install)
        let oldSnapshot = await health.snapshot()
        XCTAssertEqual(
            oldSnapshot.targets.first { $0.adapterIdentifier == "wide-layout" }?.state,
            .degraded(reason: "old-revision")
        )

        let invalidationTask = Task {
            await bridge.invalidate(targetIdentifier: target.identifier)
        }
        await cdp.waitUntilOldUninstallBlocked()

        let newResults = try await bridge.apply(
            configuration: .defaultConfiguration,
            to: target,
            operation: .install
        )
        XCTAssertEqual(newResults.count, 4)
        XCTAssertTrue(newResults.allSatisfy { $0.error == nil })
        let newSnapshot = await health.snapshot()
        XCTAssertEqual(newSnapshot.targets.count, 4)
        XCTAssertTrue(newSnapshot.targets.allSatisfy { $0.state == .healthy })

        await cdp.releaseOldUninstall()
        await invalidationTask.value

        let finalSnapshot = await health.snapshot()
        XCTAssertEqual(finalSnapshot.targets.count, 4)
        XCTAssertTrue(finalSnapshot.targets.allSatisfy { $0.state == .healthy })
        let attachedSessions = await cdp.attachedSessionIdentifiers()
        XCTAssertEqual(attachedSessions, ["old-session", "new-session"])
    }

    func testHandshakeMismatchStopsBeforeAdapterEnvelopes() async throws {
        let cdp = BridgeCDPDouble(invalidHandshake: true)
        let bridge = CDPPageRuntimeBridge(client: cdp, healthCenter: HealthCenter(), bundle: Bundle(for: Self.self))
        let target = CDPTarget(identifier: "target-handshake", url: TargetCoordinator.codexSurfaceURL)

        do {
            _ = try await bridge.apply(configuration: .defaultConfiguration, to: target, operation: .install)
            XCTFail("握手不匹配必须阻止 adapter envelope")
        } catch let error as PageRuntimeBridgeError {
            XCTAssertEqual(error, .invalidResponse("runtime-handshake"))
        }
        let commands = await cdp.commands()
        XCTAssertFalse(commands.contains { $0.params?["expression"]?.stringValue?.contains(".execute(") == true })
        XCTAssertFalse(commands.contains { command in
            let expression = command.params?["expression"]?.stringValue ?? ""
            return ["registerWideLayout", "registerHeaderOffset", "registerIMEEnterGuard", "registerMarkdownSemanticTheme"]
                .contains { expression.contains($0) }
        })
    }

    func testLateAttachResponseDetachesReturnedSessionAndThrowsStaleRevision() async throws {
        let cdp = ControlledBridgeCDPDouble(mode: .lateAttach)
        let bridge = CDPPageRuntimeBridge(
            client: cdp,
            healthCenter: HealthCenter(),
            bundle: Bundle(for: Self.self)
        )
        let target = CDPTarget(identifier: "target-late-attach", url: TargetCoordinator.codexSurfaceURL)
        let probeTask = Task {
            try await bridge.probe(target: target, requiredAnchors: TargetCoordinator.requiredAnchors)
        }

        await cdp.waitUntilBlocked()
        await bridge.invalidate(targetIdentifier: target.identifier)
        await cdp.release()

        do {
            _ = try await probeTask.value
            XCTFail("迟到的 attach 响应必须按 stale revision 丢弃")
        } catch let error as PageRuntimeBridgeError {
            XCTAssertEqual(error, .staleRevision(target.identifier))
        }
        let commands = await cdp.commands()
        XCTAssertTrue(commands.contains {
            $0.method == "Target.detachFromTarget"
                && $0.params?["sessionId"] == .string("late-session")
        })
    }

    func testDelayedAttachErrorBecomesStaleAfterInvalidation() async throws {
        let cdp = ControlledBridgeCDPDouble(mode: .attachFailure)
        let bridge = CDPPageRuntimeBridge(
            client: cdp,
            healthCenter: HealthCenter(),
            bundle: Bundle(for: Self.self)
        )
        let target = CDPTarget(identifier: "target-stale-attach-error", url: TargetCoordinator.codexSurfaceURL)
        let probeTask = Task {
            try await bridge.probe(target: target, requiredAnchors: TargetCoordinator.requiredAnchors)
        }

        await cdp.waitUntilBlocked()
        await bridge.invalidate(targetIdentifier: target.identifier)
        await cdp.release()

        do {
            _ = try await probeTask.value
            XCTFail("失效 revision 的 attach error 必须重分类为 stale revision")
        } catch let error as PageRuntimeBridgeError {
            XCTAssertEqual(error, .staleRevision(target.identifier))
        }
    }

    func testDelayedEvaluateErrorBecomesStaleAfterInvalidation() async throws {
        let cdp = ControlledBridgeCDPDouble(mode: .probeFailure)
        let bridge = CDPPageRuntimeBridge(
            client: cdp,
            healthCenter: HealthCenter(),
            bundle: Bundle(for: Self.self)
        )
        let target = CDPTarget(identifier: "target-stale-evaluate-error", url: TargetCoordinator.codexSurfaceURL)
        let probeTask = Task {
            try await bridge.probe(target: target, requiredAnchors: TargetCoordinator.requiredAnchors)
        }

        await cdp.waitUntilBlocked()
        await bridge.invalidate(targetIdentifier: target.identifier)
        await cdp.release()

        do {
            _ = try await probeTask.value
            XCTFail("失效 session 的 Runtime.evaluate error 必须重分类为 stale revision")
        } catch let error as PageRuntimeBridgeError {
            XCTAssertEqual(error, .staleRevision(target.identifier))
        }
    }

    func testDelayedEvaluateErrorRemainsVisibleForCurrentRevision() async throws {
        let cdp = ControlledBridgeCDPDouble(mode: .probeFailure)
        let bridge = CDPPageRuntimeBridge(
            client: cdp,
            healthCenter: HealthCenter(),
            bundle: Bundle(for: Self.self)
        )
        let target = CDPTarget(identifier: "target-current-evaluate-error", url: TargetCoordinator.codexSurfaceURL)
        let probeTask = Task {
            try await bridge.probe(target: target, requiredAnchors: TargetCoordinator.requiredAnchors)
        }

        await cdp.waitUntilBlocked()
        await cdp.release()

        do {
            _ = try await probeTask.value
            XCTFail("当前 revision 的 Runtime.evaluate error 不应被覆盖")
        } catch let error as ControlledBridgeError {
            XCTAssertEqual(error, .requestFailure)
        }
    }

    func testApplyInvalidatedDuringHealthAwaitThrowsStaleAndLeavesNoHealth() async throws {
        let cdp = BridgeCDPDouble()
        let health = GatedBridgeHealthReporter()
        let bridge = CDPPageRuntimeBridge(
            client: cdp,
            healthReporter: health,
            bundle: Bundle(for: Self.self)
        )
        let target = CDPTarget(identifier: "target-apply-health-race", url: TargetCoordinator.codexSurfaceURL)
        let applyTask = Task {
            try await bridge.apply(configuration: .defaultConfiguration, to: target, operation: .install)
        }

        await health.waitUntilUpdateSuspended()
        await bridge.invalidate(targetIdentifier: target.identifier)
        await health.releaseUpdate()

        do {
            _ = try await applyTask.value
            XCTFail("invalidate 后 apply 不得继续或返回结果")
        } catch let error as PageRuntimeBridgeError {
            XCTAssertEqual(error, .staleRevision(target.identifier))
        }
        let targets = await health.targets()
        XCTAssertTrue(targets.isEmpty)
    }

    func testPollPerformanceInvalidatedDuringHealthAwaitThrowsStaleAndLeavesNoHealth() async throws {
        let cdp = BridgeCDPDouble()
        let health = GatedBridgeHealthReporter()
        let bridge = CDPPageRuntimeBridge(
            client: cdp,
            healthReporter: health,
            bundle: Bundle(for: Self.self)
        )
        let target = CDPTarget(identifier: "target-performance-health-race", url: TargetCoordinator.codexSurfaceURL)
        let pollTask = Task { try await bridge.pollPerformance(target: target) }

        await health.waitUntilUpdateSuspended()
        await bridge.invalidate(targetIdentifier: target.identifier)
        await health.releaseUpdate()

        do {
            _ = try await pollTask.value
            XCTFail("invalidate 后 pollPerformance 不得返回旧 measurements")
        } catch let error as PageRuntimeBridgeError {
            XCTAssertEqual(error, .staleRevision(target.identifier))
        }
        let targets = await health.targets()
        XCTAssertTrue(targets.isEmpty)
    }

    func testPollPerformanceDistinguishesMissingRuntimeFromMalformedSnapshot() async throws {
        let target = CDPTarget(identifier: "target-performance-envelope", url: TargetCoordinator.codexSurfaceURL)
        let missingBridge = CDPPageRuntimeBridge(
            client: BridgeCDPDouble(performanceRuntimeMissing: true),
            healthCenter: HealthCenter(),
            bundle: Bundle(for: Self.self)
        )
        do {
            _ = try await missingBridge.pollPerformance(target: target)
            XCTFail("PageRuntime 缺失必须返回专用恢复信号")
        } catch let error as PageRuntimeBridgeError {
            XCTAssertEqual(error, .runtimeUnavailable(target.identifier))
        }

        let malformedBridge = CDPPageRuntimeBridge(
            client: BridgeCDPDouble(malformedPerformanceSnapshot: true),
            healthCenter: HealthCenter(),
            bundle: Bundle(for: Self.self)
        )
        do {
            _ = try await malformedBridge.pollPerformance(target: target)
            XCTFail("已存在 runtime 的畸形 snapshot 不得伪装成可恢复缺失")
        } catch let error as PageRuntimeBridgeError {
            XCTAssertEqual(error, .invalidResponse("performance-snapshot"))
        }
    }

    private static let probeExpressionDOM = #"""
    var window = this;
    (function installProbeDOM() {
      function node(name, parent, attributes, style) {
        return {
          name: name,
          parentElement: parent || null,
          hidden: false,
          attributes: attributes || {},
          style: Object.assign({ display: 'block', visibility: 'visible', opacity: '1' }, style || {}),
          getAttribute: function(key) {
            return Object.prototype.hasOwnProperty.call(this.attributes, key) ? this.attributes[key] : null;
          },
          contains: function(candidate) {
            for (let current = candidate; current; current = current.parentElement) {
              if (current === this) return true;
            }
            return false;
          }
        };
      }
      window.__probeLayout = node('layout', null);
      window.__probeOwner = node('owner', window.__probeLayout);
      window.__hiddenOwner = node('hidden-owner', window.__probeLayout, { 'aria-hidden': 'true' });
      window.__visibleFallback = node('visible-fallback', window.__probeOwner);
      window.__secondVisibleFallback = node('second-visible-fallback', window.__probeOwner);
      window.__hiddenFallback = node('hidden-fallback', window.__hiddenOwner);
      window.__outsideFallback = node('outside-fallback', null);
      window.__visibleMarked = node('visible-marked', window.__probeOwner);
      window.__hiddenMarked = node('hidden-marked', window.__hiddenOwner);
      window.__probeMarked = [];
      window.__probeFallback = [];
      window.__setProbeNodes = function(marked, fallback) {
        window.__probeMarked = marked;
        window.__probeFallback = fallback;
      };
      window.getComputedStyle = function(candidate) { return candidate.style; };
      window.document = {
        querySelectorAll: function(selector) {
          if (selector === '[data-app-shell-main-content-layout]') return [window.__probeLayout];
          if (selector === '.thread-scroll-container') return [];
          if (selector.includes('data-codex-composer')) return window.__probeMarked;
          if (selector.includes('.ProseMirror[contenteditable')) return window.__probeFallback;
          return [];
        }
      };
    })();
    """#

    private static func registrationMarker(for adapter: String) -> String {
        switch adapter {
        case "wide-layout": return "registerWideLayout"
        case "header-offset": return "registerHeaderOffset"
        case "ime-enter-guard": return "registerIMEEnterGuard"
        case "markdown-semantic-theme": return "registerMarkdownSemanticTheme"
        default: return ""
        }
    }
}

private struct RecordedBridgeCommand: Sendable {
    let method: String
    let params: JSONValue?
    let session: String?
}

private actor BridgeCDPDouble: CDPCommanding {
    private var recorded: [RecordedBridgeCommand] = []
    private let failingAdapter: String?
    private let failingOperation: String?
    private var remainingFailureCount: Int?
    private let unqualifiedAdapter: String?
    private let recoverableAdapter: String?
    private let invalidHandshake: Bool
    private let sideEffectsReturnUndefined: Bool
    private let sideEffectsReturnTypeWithoutValue: String?
    private let missingProbeValue: Bool
    private let exceptionExpressionMarker: String?
    private let rehydrationRequired: Bool
    private let probeCounts: [CodexSurfaceAnchor: Int]
    private let performanceRuntimeMissing: Bool
    private let malformedPerformanceSnapshot: Bool

    init(
        failingAdapter: String? = nil,
        failingOperation: String? = nil,
        failingRequestCount: Int? = nil,
        unqualifiedAdapter: String? = nil,
        recoverableAdapter: String? = nil,
        invalidHandshake: Bool = false,
        sideEffectsReturnUndefined: Bool = false,
        sideEffectsReturnTypeWithoutValue: String? = nil,
        missingProbeValue: Bool = false,
        exceptionExpressionMarker: String? = nil,
        rehydrationRequired: Bool = false,
        performanceRuntimeMissing: Bool = false,
        malformedPerformanceSnapshot: Bool = false,
        probeCounts: [CodexSurfaceAnchor: Int] = [.layoutRoot: 1, .threadScroller: 1, .composer: 1]
    ) {
        self.failingAdapter = failingAdapter
        self.failingOperation = failingOperation
        self.remainingFailureCount = failingRequestCount
        self.unqualifiedAdapter = unqualifiedAdapter
        self.recoverableAdapter = recoverableAdapter
        self.invalidHandshake = invalidHandshake
        self.sideEffectsReturnUndefined = sideEffectsReturnUndefined
        self.sideEffectsReturnTypeWithoutValue = sideEffectsReturnTypeWithoutValue
        self.missingProbeValue = missingProbeValue
        self.exceptionExpressionMarker = exceptionExpressionMarker
        self.rehydrationRequired = rehydrationRequired
        self.performanceRuntimeMissing = performanceRuntimeMissing
        self.malformedPerformanceSnapshot = malformedPerformanceSnapshot
        self.probeCounts = probeCounts
    }

    func request(method: String, params: JSONValue?, sessionIdentifier: String?, timeout: Duration?) throws -> JSONValue? {
        recorded.append(.init(method: method, params: params, session: sessionIdentifier))
        if method == "Target.attachToTarget" { return .object(["sessionId": .string("session-1")]) }
        if method == "Target.detachFromTarget" { return .object([:]) }
        guard method == "Runtime.evaluate", let expression = params?["expression"]?.stringValue else { return .object([:]) }
        if expression.contains("fixture-script-evaluation-failure:") {
            throw BridgeFixtureError.scriptEvaluation
        }
        if let exceptionExpressionMarker, expression.contains(exceptionExpressionMarker) {
            return .object([
                "result": .object(["type": .string("undefined")]),
                "exceptionDetails": .object(["text": .string("fixture-exception")])
            ])
        }
        if expression.contains("const countWithinLayout = (selector)") {
            if missingProbeValue {
                return .object(["result": .object(["type": .string("object")])])
            }
            return remoteValue(.object([
                "layoutRoot": .number(Double(probeCounts[.layoutRoot] ?? 0)),
                "threadScroller": .number(Double(probeCounts[.threadScroller] ?? 0)),
                "composer": .number(Double(probeCounts[.composer] ?? 0))
            ]))
        }
        if expression.contains("handshake(0)") {
            return remoteValue(.object([
                "runtimeVersion": .number(invalidHandshake ? 1 : 2),
                "requestId": .number(0),
                "adapterId": .string("runtime"),
                "operation": .string("handshake"),
                "config": .null,
                "result": .object([
                    "runtimeVersion": .number(2),
                    "implementationRevision": .number(Double(CDPPageRuntimeBridge.implementationRevision)),
                    "rehydrationRequired": .bool(rehydrationRequired),
                    "hydrated": .bool(!rehydrationRequired)
                ]),
                "error": .null
            ]))
        }
        if expression.contains("window.__codexAppExtensionV2.markHydrated()") {
            return remoteValue(.object([
                "runtimeVersion": .number(2),
                "implementationRevision": .number(Double(CDPPageRuntimeBridge.implementationRevision)),
                "hydrated": .bool(true)
            ]))
        }
        if expression.contains("const runtime = window.__codexAppExtensionV2") {
            if performanceRuntimeMissing {
                return remoteValue(.object([
                    "runtimeMissing": .bool(true),
                    "observers": .null
                ]))
            }
            let observers: JSONValue = malformedPerformanceSnapshot
                ? .null
                : .array([
                    .object([
                        "adapterId": .string("wide-layout"),
                        "strikeCount": .number(0),
                        "durationMilliseconds": .number(1),
                        "degraded": .bool(false),
                        "qualified": .bool(true)
                    ])
                ])
            return remoteValue(.object([
                "runtimeMissing": .bool(false),
                "observers": observers
            ]))
        }
        if expression.contains(".execute("), let adapter = adapterIdentifier(in: expression) {
            let operation = operationName(in: expression)
            let matchesFailure = adapter == failingAdapter && (failingOperation == nil || failingOperation == operation)
            let shouldFail = matchesFailure && (remainingFailureCount == nil || remainingFailureCount! > 0)
            if shouldFail, let remainingFailureCount {
                self.remainingFailureCount = remainingFailureCount - 1
            }
            let error: JSONValue = shouldFail
                ? .object(["code": .string("fixture-failure"), "message": .string("fixture")])
                : .null
            let result: JSONValue
            if adapter == recoverableAdapter {
                result = .object([
                    "changed": .bool(false),
                    "qualified": .bool(false),
                    "recoverable": .bool(true),
                    "reason": .string("markdown-candidate-missing")
                ])
            } else if adapter == unqualifiedAdapter {
                result = .object([
                    "changed": .bool(false),
                    "qualified": .bool(false),
                    "recoverable": .bool(false),
                    "reason": .string("markdown-candidate-missing")
                ])
            } else {
                result = .object(["changed": .bool(true), "qualified": .bool(true), "recoverable": .bool(false)])
            }
            return remoteValue(.object([
                "runtimeVersion": .number(2), "requestId": .number(1), "adapterId": .string(adapter),
                "operation": .string(operation), "config": .null, "result": result, "error": error
            ]))
        }
        if let remoteType = sideEffectsReturnTypeWithoutValue {
            return .object(["result": .object(["type": .string(remoteType)])])
        }
        if sideEffectsReturnUndefined {
            return .object(["result": .object(["type": .string("undefined")])])
        }
        return remoteValue(.null)
    }

    func commands() -> [RecordedBridgeCommand] { recorded }
    func evaluateExpressions() -> [String] {
        recorded.compactMap { command in
            guard command.method == "Runtime.evaluate" else { return nil }
            return command.params?["expression"]?.stringValue
        }
    }

    private func remoteValue(_ value: JSONValue) -> JSONValue {
        .object(["result": .object(["value": value])])
    }

    private func adapterIdentifier(in expression: String) -> String? {
        ["wide-layout", "header-offset", "ime-enter-guard", "markdown-semantic-theme"]
            .first { expression.contains(#""adapterId":"\#($0)""#) }
    }

    private func operationName(in expression: String) -> String {
        ["install", "update", "diagnose", "uninstall"]
            .first { expression.contains(#""operation":"\#($0)""#) } ?? "install"
    }

}

private actor RevisionRaceBridgeCDPDouble: CDPCommanding {
    private var attachedSessions: [String] = []
    private var didBlockOldUninstall = false
    private var oldUninstallIsBlocked = false
    private var blockedWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func request(
        method: String,
        params: JSONValue?,
        sessionIdentifier: String?,
        timeout: Duration?
    ) async throws -> JSONValue? {
        if method == "Target.attachToTarget" {
            let session = attachedSessions.isEmpty ? "old-session" : "new-session"
            attachedSessions.append(session)
            return .object(["sessionId": .string(session)])
        }
        if method == "Target.detachFromTarget" {
            return .object([:])
        }
        guard method == "Runtime.evaluate",
              let expression = params?["expression"]?.stringValue else {
            return .object([:])
        }
        if expression.contains("handshake(0)") {
            return remoteValue(.object([
                "runtimeVersion": .number(2),
                "requestId": .number(0),
                "adapterId": .string("runtime"),
                "operation": .string("handshake"),
                "config": .null,
                "result": .object([
                    "runtimeVersion": .number(2),
                    "implementationRevision": .number(Double(CDPPageRuntimeBridge.implementationRevision)),
                    "rehydrationRequired": .bool(false),
                    "hydrated": .bool(true)
                ]),
                "error": .null
            ]))
        }
        if expression.contains(".execute("), let adapter = adapterIdentifier(in: expression) {
            let operation = operationName(in: expression)
            if sessionIdentifier == "old-session", operation == "uninstall", !didBlockOldUninstall {
                didBlockOldUninstall = true
                await suspendOldUninstall()
            }
            let isOldFailure = sessionIdentifier == "old-session"
                && operation == "install"
                && adapter == "wide-layout"
            let error: JSONValue = isOldFailure
                ? .object(["code": .string("old-revision"), "message": .string("old revision")])
                : .null
            return remoteValue(.object([
                "runtimeVersion": .number(2),
                "requestId": .number(1),
                "adapterId": .string(adapter),
                "operation": .string(operation),
                "config": .null,
                "result": .object(["changed": .bool(true), "qualified": .bool(true)]),
                "error": error
            ]))
        }
        return .object(["result": .object(["type": .string("undefined")])])
    }

    func waitUntilOldUninstallBlocked() async {
        if oldUninstallIsBlocked { return }
        await withCheckedContinuation { continuation in
            blockedWaiters.append(continuation)
        }
    }

    func releaseOldUninstall() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func attachedSessionIdentifiers() -> [String] {
        attachedSessions
    }

    private func suspendOldUninstall() async {
        oldUninstallIsBlocked = true
        let waiters = blockedWaiters
        blockedWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
        oldUninstallIsBlocked = false
    }

    private func remoteValue(_ value: JSONValue) -> JSONValue {
        .object(["result": .object(["value": value])])
    }

    private func adapterIdentifier(in expression: String) -> String? {
        ["wide-layout", "header-offset", "ime-enter-guard", "markdown-semantic-theme"]
            .first { expression.contains(#""adapterId":"\#($0)""#) }
    }

    private func operationName(in expression: String) -> String {
        ["install", "update", "diagnose", "uninstall"]
            .first { expression.contains(#""operation":"\#($0)""#) } ?? "install"
    }
}

private enum ControlledBridgeError: Error, Equatable {
    case requestFailure
}

private actor ControlledBridgeCDPDouble: CDPCommanding {
    enum Mode: Equatable {
        case lateAttach
        case attachFailure
        case probeFailure
    }

    private let mode: Mode
    private var recorded: [RecordedBridgeCommand] = []
    private var isBlocked = false
    private var didBlockProbeEvaluate = false
    private var blockedWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(mode: Mode) {
        self.mode = mode
    }

    func request(
        method: String,
        params: JSONValue?,
        sessionIdentifier: String?,
        timeout: Duration?
    ) async throws -> JSONValue? {
        recorded.append(.init(method: method, params: params, session: sessionIdentifier))
        if method == "Target.attachToTarget" {
            if mode == .lateAttach {
                await suspendRequest()
                return .object(["sessionId": .string("late-session")])
            }
            if mode == .attachFailure {
                await suspendRequest()
                throw ControlledBridgeError.requestFailure
            }
            return .object(["sessionId": .string("controlled-session")])
        }
        if method == "Target.detachFromTarget" {
            return .object([:])
        }
        if mode == .probeFailure, method == "Runtime.evaluate", !didBlockProbeEvaluate {
            didBlockProbeEvaluate = true
            await suspendRequest()
            throw ControlledBridgeError.requestFailure
        }
        guard method == "Runtime.evaluate" else {
            return .object([:])
        }
        return .object(["result": .object(["value": .null])])
    }

    func waitUntilBlocked() async {
        if isBlocked { return }
        await withCheckedContinuation { continuation in
            blockedWaiters.append(continuation)
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func commands() -> [RecordedBridgeCommand] {
        recorded
    }

    private func suspendRequest() async {
        isBlocked = true
        let waiters = blockedWaiters
        blockedWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
        isBlocked = false
    }
}

private actor GatedBridgeHealthReporter: PageRuntimeHealthReporting {
    private var storedTargets: [String: TargetRuntimeHealth] = [:]
    private var activeGenerations: [String: (generation: UInt64, isRemoved: Bool)] = [:]
    private var shouldSuspendNextUpdate = true
    private var updateIsSuspended = false
    private var updateWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func beginTarget(identifier: String, generation: UInt64) {
        if let active = activeGenerations[identifier], generation <= active.generation { return }
        activeGenerations[identifier] = (generation, false)
        storedTargets = storedTargets.filter { $0.value.targetIdentifier != identifier }
    }

    func updateTarget(_ target: TargetRuntimeHealth, generation: UInt64) async {
        guard let active = activeGenerations[target.targetIdentifier],
              active.generation == generation,
              !active.isRemoved else { return }
        storedTargets[key(for: target)] = target
        guard shouldSuspendNextUpdate else { return }
        shouldSuspendNextUpdate = false
        updateIsSuspended = true
        let waiters = updateWaiters
        updateWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
        updateIsSuspended = false
    }

    func removeTarget(identifier: String, generation: UInt64) {
        guard let active = activeGenerations[identifier],
              active.generation == generation,
              !active.isRemoved else { return }
        activeGenerations[identifier] = (generation, true)
        storedTargets = storedTargets.filter { $0.value.targetIdentifier != identifier }
    }

    func waitUntilUpdateSuspended() async {
        if updateIsSuspended { return }
        await withCheckedContinuation { continuation in
            updateWaiters.append(continuation)
        }
    }

    func releaseUpdate() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func targets() -> [TargetRuntimeHealth] {
        Array(storedTargets.values)
    }

    private func key(for target: TargetRuntimeHealth) -> String {
        "\(target.targetIdentifier)\u{0}\(target.adapterIdentifier)"
    }
}

private enum BridgeFixtureError: Error {
    case scriptEvaluation
}

private struct BridgeScriptLoaderDouble: PageRuntimeScriptLoading {
    let missingAdapter: FeatureIdentifier?
    let evaluationFailureAdapter: FeatureIdentifier?
    let failsBootstrap: Bool
    private let registry = FeatureRegistry()

    init(
        missingAdapter: FeatureIdentifier? = nil,
        evaluationFailureAdapter: FeatureIdentifier? = nil,
        failsBootstrap: Bool = false
    ) {
        self.missingAdapter = missingAdapter
        self.evaluationFailureAdapter = evaluationFailureAdapter
        self.failsBootstrap = failsBootstrap
    }

    func loadBootstrapScript(from bundle: Bundle) throws -> LoadedFeatureScript {
        if failsBootstrap { throw FeatureResourceError.missingResource("PageRuntime/bootstrap.js") }
        return try registry.loadBootstrapScript(from: bundle)
    }

    func loadAdapterScript(for registration: FeatureRegistration, from bundle: Bundle) throws -> LoadedFeatureScript {
        if registration.identifier == missingAdapter {
            throw FeatureResourceError.missingResource(registration.resourcePath)
        }
        if registration.identifier == evaluationFailureAdapter {
            return .init(
                adapterId: registration.identifier.rawValue,
                source: "fixture-script-evaluation-failure:\(registration.identifier.rawValue)"
            )
        }
        return try registry.loadAdapterScript(for: registration, from: bundle)
    }
}
