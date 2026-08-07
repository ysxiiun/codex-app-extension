import Foundation

public struct CDPTarget: Equatable, Sendable {
    public let identifier: String
    public let url: URL

    public init(identifier: String, url: URL) {
        self.identifier = identifier
        self.url = url
    }
}

public enum TargetEvent: Equatable, Sendable {
    case created(CDPTarget)
    case reloaded(CDPTarget)
    case destroyed(identifier: String)
}

public enum CodexSurfaceAnchor: String, CaseIterable, Hashable, Sendable {
    case layoutRoot
    case composer
    case threadScroller

    public static let identityAnchors: Set<Self> = [.layoutRoot, .composer, .threadScroller]
}

public struct CodexSurfaceProbeResult: Equatable, Sendable {
    public let matchedAnchors: Set<CodexSurfaceAnchor>
    public let counts: [CodexSurfaceAnchor: Int]

    public init(matchedAnchors: Set<CodexSurfaceAnchor>, counts: [CodexSurfaceAnchor: Int] = [:]) {
        self.matchedAnchors = matchedAnchors
        self.counts = counts
    }

    public var isCodexSurface: Bool {
        if counts.isEmpty {
            return matchedAnchors.contains(.layoutRoot)
                && (matchedAnchors.contains(.threadScroller) || matchedAnchors.contains(.composer))
        }

        let threadScrollerCount = counts[.threadScroller] ?? 0
        let composerCount = counts[.composer] ?? 0
        guard counts[.layoutRoot] == 1 else { return false }
        if threadScrollerCount == 1 { return true }
        if threadScrollerCount == 0 { return composerCount == 1 }
        return false
    }
}

public protocol CodexSurfaceProbing: Sendable {
    func probe(target: CDPTarget, requiredAnchors: Set<CodexSurfaceAnchor>) async throws -> CodexSurfaceProbeResult
}

public enum TargetDelivery: Equatable, Sendable {
    case available(CDPTarget)
    case removed(identifier: String)
    case degraded(identifier: String, reason: String)
}

public struct TargetCoordinatorSnapshot: Equatable, Sendable {
    public let knownTargets: [CDPTarget]
    public let eligibleTargetIdentifiers: Set<String>

    public init(knownTargets: [CDPTarget], eligibleTargetIdentifiers: Set<String>) {
        self.knownTargets = knownTargets
        self.eligibleTargetIdentifiers = eligibleTargetIdentifiers
    }
}

public actor TargetCoordinator {
    public static let codexSurfaceURL = URL(string: "app://-/index.html")!
    public static let requiredAnchors = CodexSurfaceAnchor.identityAnchors

    private let probe: any CodexSurfaceProbing
    private var targets: [String: CDPTarget] = [:]
    private var revisions: [String: UInt64] = [:]
    private var eligibleTargetIdentifiers: Set<String> = []
    private var deliveryObservers: [UUID: AsyncStream<TargetDelivery>.Continuation] = [:]
    private var subscriptionTask: Task<Void, Never>?

    public init(probe: any CodexSurfaceProbing) {
        self.probe = probe
    }

    public func snapshot() -> TargetCoordinatorSnapshot {
        .init(
            knownTargets: targets.values.sorted { $0.identifier < $1.identifier },
            eligibleTargetIdentifiers: eligibleTargetIdentifiers
        )
    }

    public func deliveries() -> AsyncStream<TargetDelivery> {
        let identifier = UUID()
        // Target events are loss-sensitive, but must never grow memory without bound.
        // Keeping the newest window preserves the most recent reload/destroy convergence facts.
        return AsyncStream(bufferingPolicy: .bufferingNewest(RuntimeStreamBufferLimits.lossSensitiveEvents)) { continuation in
            deliveryObservers[identifier] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeDeliveryObserver(identifier) }
            }
        }
    }

    public func subscribe(to events: AsyncStream<TargetEvent>) {
        subscriptionTask?.cancel()
        subscriptionTask = Task {
            for await event in events {
                if Task.isCancelled { break }
                await self.handle(event)
            }
        }
    }

    public func subscribe(to cdpEvents: AsyncStream<CDPEvent>) {
        subscriptionTask?.cancel()
        subscriptionTask = Task {
            for await event in cdpEvents {
                if Task.isCancelled { break }
                guard let targetEvent = Self.targetEvent(from: event) else { continue }
                await self.handle(targetEvent)
            }
        }
    }

    public func handle(_ event: TargetEvent) async {
        switch event {
        case let .created(target), let .reloaded(target):
            await evaluate(target)
        case let .destroyed(identifier):
            targets.removeValue(forKey: identifier)
            revisions[identifier, default: 0] &+= 1
            if eligibleTargetIdentifiers.remove(identifier) != nil {
                publish(.removed(identifier: identifier))
            }
        }
    }

    private func evaluate(_ target: CDPTarget) async {
        targets[target.identifier] = target
        revisions[target.identifier, default: 0] &+= 1
        let revision = revisions[target.identifier]!

        if eligibleTargetIdentifiers.remove(target.identifier) != nil {
            publish(.removed(identifier: target.identifier))
        }
        guard target.url == Self.codexSurfaceURL else { return }

        do {
            let result = try await probe.probe(target: target, requiredAnchors: Self.requiredAnchors)
            guard revisions[target.identifier] == revision,
                  targets[target.identifier] == target else { return }
            guard result.isCodexSurface else { return }
            eligibleTargetIdentifiers.insert(target.identifier)
            publish(.available(target))
        } catch {
            guard revisions[target.identifier] == revision,
                  targets[target.identifier] == target else { return }
            publish(.degraded(identifier: target.identifier, reason: "surface-probe-failed"))
        }
    }

    private func publish(_ delivery: TargetDelivery) {
        for observer in deliveryObservers.values {
            observer.yield(delivery)
        }
    }

    private func removeDeliveryObserver(_ identifier: UUID) {
        deliveryObservers.removeValue(forKey: identifier)
    }

    private static func targetEvent(from event: CDPEvent) -> TargetEvent? {
        switch event.method {
        case "Target.targetCreated":
            guard let target = decodeTarget(event.params?["targetInfo"]) else { return nil }
            return .created(target)
        case "Target.targetInfoChanged":
            guard let target = decodeTarget(event.params?["targetInfo"]) else { return nil }
            return .reloaded(target)
        case "Target.targetDestroyed":
            guard let identifier = event.params?["targetId"]?.stringValue else { return nil }
            return .destroyed(identifier: identifier)
        default:
            return nil
        }
    }

    private static func decodeTarget(_ value: JSONValue?) -> CDPTarget? {
        guard let identifier = value?["targetId"]?.stringValue,
              let rawURL = value?["url"]?.stringValue,
              let url = URL(string: rawURL) else { return nil }
        return CDPTarget(identifier: identifier, url: url)
    }
}
