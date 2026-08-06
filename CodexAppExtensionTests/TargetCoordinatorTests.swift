import Foundation
import XCTest
@testable import ExtensionCore

final class TargetCoordinatorTests: XCTestCase {
    func testSurfaceIdentityRequiresStableLayoutAndScrollerButNotTransientComposer() {
        let noComposer = CodexSurfaceProbeResult(
            matchedAnchors: CodexSurfaceAnchor.identityAnchors,
            counts: [.layoutRoot: 1, .threadScroller: 1, .composer: 0]
        )
        let floatingOrAmbiguousComposer = CodexSurfaceProbeResult(
            matchedAnchors: CodexSurfaceAnchor.identityAnchors,
            counts: [.layoutRoot: 1, .threadScroller: 1, .composer: 2]
        )
        let missingScroller = CodexSurfaceProbeResult(
            matchedAnchors: [.layoutRoot],
            counts: [.layoutRoot: 1, .threadScroller: 0, .composer: 1]
        )

        XCTAssertTrue(noComposer.isCodexSurface)
        XCTAssertTrue(floatingOrAmbiguousComposer.isCodexSurface)
        XCTAssertFalse(missingScroller.isCodexSurface)
    }

    func testURLAndSurfaceProbeAreBothRequired() async {
        let probe = StubSurfaceProbe(results: [
            "partial": .init(matchedAnchors: [.layoutRoot, .composer]),
            "layout-only": .init(matchedAnchors: [.layoutRoot, .threadScroller]),
            "codex": .init(matchedAnchors: Set(CodexSurfaceAnchor.allCases))
        ])
        let coordinator = TargetCoordinator(probe: probe)

        await coordinator.handle(.created(.init(
            identifier: "wrong-url",
            url: URL(string: "app://-/settings.html")!
        )))
        await coordinator.handle(.created(.init(identifier: "partial", url: TargetCoordinator.codexSurfaceURL)))
        await coordinator.handle(.created(.init(identifier: "layout-only", url: TargetCoordinator.codexSurfaceURL)))
        await coordinator.handle(.created(.init(identifier: "codex", url: TargetCoordinator.codexSurfaceURL)))

        let snapshot = await coordinator.snapshot()
        XCTAssertEqual(snapshot.eligibleTargetIdentifiers, ["codex", "layout-only"])
        let probedIdentifiers = await probe.probedIdentifiers()
        let requiredAnchorSets = await probe.requiredAnchorSets()
        XCTAssertEqual(probedIdentifiers, ["partial", "layout-only", "codex"])
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
