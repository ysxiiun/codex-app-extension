import Foundation
import XCTest
@testable import ExtensionCore

final class TargetCoordinatorTests: XCTestCase {
    func testSurfaceIdentityAcceptsThreadAndEmptyComposerShapesButRejectsAmbiguity() {
        let threadSurface = CodexSurfaceProbeResult(
            matchedAnchors: [.layoutRoot, .threadScroller],
            counts: [.layoutRoot: 1, .threadScroller: 1, .composer: 0]
        )
        let emptyComposerSurface = CodexSurfaceProbeResult(
            matchedAnchors: [.layoutRoot, .composer],
            counts: [.layoutRoot: 1, .threadScroller: 0, .composer: 1]
        )
        let layoutOnly = CodexSurfaceProbeResult(
            matchedAnchors: [.layoutRoot],
            counts: [.layoutRoot: 1, .threadScroller: 0, .composer: 0]
        )
        let duplicateLayout = CodexSurfaceProbeResult(
            matchedAnchors: [.threadScroller],
            counts: [.layoutRoot: 2, .threadScroller: 1, .composer: 0]
        )
        let threadSurfaceWithMultipleComposers = CodexSurfaceProbeResult(
            matchedAnchors: [.layoutRoot, .threadScroller],
            counts: [.layoutRoot: 1, .threadScroller: 1, .composer: 2]
        )
        let emptySurfaceWithMultipleComposers = CodexSurfaceProbeResult(
            matchedAnchors: [.layoutRoot],
            counts: [.layoutRoot: 1, .threadScroller: 0, .composer: 2]
        )
        let duplicateScroller = CodexSurfaceProbeResult(
            matchedAnchors: [.layoutRoot, .composer],
            counts: [.layoutRoot: 1, .threadScroller: 2, .composer: 1]
        )

        XCTAssertTrue(threadSurface.isCodexSurface)
        XCTAssertTrue(emptyComposerSurface.isCodexSurface)
        XCTAssertTrue(threadSurfaceWithMultipleComposers.isCodexSurface)
        XCTAssertFalse(layoutOnly.isCodexSurface)
        XCTAssertFalse(duplicateLayout.isCodexSurface)
        XCTAssertFalse(emptySurfaceWithMultipleComposers.isCodexSurface)
        XCTAssertFalse(duplicateScroller.isCodexSurface)
    }

    func testURLAndSurfaceProbeAreBothRequired() async {
        let probe = StubSurfaceProbe(results: [
            "layout-only": .init(matchedAnchors: [.layoutRoot]),
            "empty-composer": .init(matchedAnchors: [.layoutRoot, .composer]),
            "thread": .init(matchedAnchors: [.layoutRoot, .threadScroller])
        ])
        let coordinator = TargetCoordinator(probe: probe)

        await coordinator.handle(.created(.init(
            identifier: "wrong-url",
            url: URL(string: "app://-/settings.html")!
        )))
        await coordinator.handle(.created(.init(identifier: "layout-only", url: TargetCoordinator.codexSurfaceURL)))
        await coordinator.handle(.created(.init(identifier: "empty-composer", url: TargetCoordinator.codexSurfaceURL)))
        await coordinator.handle(.created(.init(identifier: "thread", url: TargetCoordinator.codexSurfaceURL)))

        let snapshot = await coordinator.snapshot()
        XCTAssertEqual(snapshot.eligibleTargetIdentifiers, ["empty-composer", "thread"])
        let probedIdentifiers = await probe.probedIdentifiers()
        let requiredAnchorSets = await probe.requiredAnchorSets()
        XCTAssertEqual(probedIdentifiers, ["layout-only", "empty-composer", "thread"])
        XCTAssertTrue(requiredAnchorSets.allSatisfy {
            $0 == CodexSurfaceAnchor.identityAnchors
        })
    }

    func testReloadReprobesAndDestroyRemovesEligibility() async {
        let probe = StubSurfaceProbe(results: [
            "target": .init(matchedAnchors: Set(CodexSurfaceAnchor.allCases))
        ])
        let coordinator = TargetCoordinator(probe: probe)
        let target = CDPTarget(identifier: "target", url: TargetCoordinator.codexSurfaceURL)
        await coordinator.handle(.created(target))
        let createdSnapshot = await coordinator.snapshot()
        XCTAssertEqual(createdSnapshot.eligibleTargetIdentifiers, ["target"])

        await probe.setResult(.init(matchedAnchors: [.layoutRoot]), for: "target")
        await coordinator.handle(.reloaded(target))
        let failedReloadSnapshot = await coordinator.snapshot()
        XCTAssertEqual(failedReloadSnapshot.eligibleTargetIdentifiers, [])

        await probe.setResult(.init(matchedAnchors: Set(CodexSurfaceAnchor.allCases)), for: "target")
        await coordinator.handle(.reloaded(target))
        let successfulReloadSnapshot = await coordinator.snapshot()
        XCTAssertEqual(successfulReloadSnapshot.eligibleTargetIdentifiers, ["target"])

        await coordinator.handle(.destroyed(identifier: "target"))
        let destroyed = await coordinator.snapshot()
        XCTAssertEqual(destroyed.eligibleTargetIdentifiers, [])
        XCTAssertFalse(destroyed.knownTargets.contains { $0.identifier == "target" })
    }

    func testCDPTargetEventsDriveCreateReloadAndDestroy() async throws {
        let probe = StubSurfaceProbe(results: [
            "streamed": .init(matchedAnchors: Set(CodexSurfaceAnchor.allCases))
        ])
        let coordinator = TargetCoordinator(probe: probe)
        let (stream, continuation) = AsyncStream<CDPEvent>.makeStream()
        await coordinator.subscribe(to: stream)

        continuation.yield(.init(
            method: "Target.targetCreated",
            params: .object(["targetInfo": .object([
                "targetId": .string("streamed"),
                "url": .string("app://-/index.html")
            ])])
        ))
        try await waitUntil {
            await coordinator.snapshot().eligibleTargetIdentifiers == ["streamed"]
        }

        continuation.yield(.init(
            method: "Target.targetInfoChanged",
            params: .object(["targetInfo": .object([
                "targetId": .string("streamed"),
                "url": .string("app://-/other.html")
            ])])
        ))
        try await waitUntil {
            await coordinator.snapshot().eligibleTargetIdentifiers.isEmpty
        }

        continuation.yield(.init(
            method: "Target.targetDestroyed",
            params: .object(["targetId": .string("streamed")])
        ))
        try await waitUntil {
            await coordinator.snapshot().knownTargets.isEmpty
        }
        continuation.finish()
    }

    private func waitUntil(
        attempts: Int = 2_000,
        condition: @escaping @Sendable () async -> Bool
    ) async throws {
        for _ in 0..<attempts {
            if await condition() { return }
            await Task.yield()
        }
        XCTFail("等待 target 状态超时")
    }
}

private actor StubSurfaceProbe: CodexSurfaceProbing {
    private var results: [String: CodexSurfaceProbeResult]
    private var identifiers: [String] = []
    private var anchors: [Set<CodexSurfaceAnchor>] = []

    init(results: [String: CodexSurfaceProbeResult]) {
        self.results = results
    }

    func setResult(_ result: CodexSurfaceProbeResult, for identifier: String) {
        results[identifier] = result
    }

    func probe(
        target: CDPTarget,
        requiredAnchors: Set<CodexSurfaceAnchor>
    ) throws -> CodexSurfaceProbeResult {
        identifiers.append(target.identifier)
        anchors.append(requiredAnchors)
        return results[target.identifier] ?? .init(matchedAnchors: [])
    }

    func probedIdentifiers() -> [String] { identifiers }
    func requiredAnchorSets() -> [Set<CodexSurfaceAnchor>] { anchors }
}
