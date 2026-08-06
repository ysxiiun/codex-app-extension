import Foundation

public enum ChatGPTProcessHealth: Equatable, Sendable {
    case notRunning
    case running(processIdentifier: Int32)
}

public enum TargetAdapterState: Equatable, Sendable {
    case healthy
    case waiting(reason: String)
    case degraded(reason: String)
}

public struct TargetRuntimeHealth: Equatable, Sendable {
    public let targetIdentifier: String
    public let adapterIdentifier: String
    public let state: TargetAdapterState

    public init(targetIdentifier: String, adapterIdentifier: String, state: TargetAdapterState) {
        self.targetIdentifier = targetIdentifier
        self.adapterIdentifier = adapterIdentifier
        self.state = state
    }
}

public struct RuntimeSnapshot: Equatable, Sendable {
    public let process: ChatGPTProcessHealth
    public let lifecycle: AppLifecyclePhase
    public let connection: CDPConnectionState
    public let targets: [TargetRuntimeHealth]

    public init(
        process: ChatGPTProcessHealth = .notRunning,
        lifecycle: AppLifecyclePhase = .notRunning,
        connection: CDPConnectionState = .disconnected,
        targets: [TargetRuntimeHealth] = []
    ) {
        self.process = process
        self.lifecycle = lifecycle
        self.connection = connection
        self.targets = targets
    }
}

public actor HealthCenter {
    private struct TargetGenerationState: Sendable {
        let generation: UInt64
        let isRemoved: Bool
    }

    private struct RuntimeGenerationState: Sendable {
        let generation: UInt64
        let isEnded: Bool
    }

    private struct RuntimeTargetRevisionState: Sendable {
        let lifecycleGeneration: UInt64
        let targetRevision: UInt64
        let isInvalidated: Bool
    }

    private var process: ChatGPTProcessHealth = .notRunning
    private var lifecycle: AppLifecyclePhase = .notRunning
    private var connection: CDPConnectionState = .disconnected
    private var targets: [String: TargetRuntimeHealth] = [:]
    private var targetGenerations: [String: TargetGenerationState] = [:]
    private var runtimeGeneration: RuntimeGenerationState?
    private var runtimeTargetRevisions: [String: RuntimeTargetRevisionState] = [:]
    private var observers: [UUID: AsyncStream<RuntimeSnapshot>.Continuation] = [:]

    public init() {}

    public func snapshot() -> RuntimeSnapshot {
        makeSnapshot()
    }

    public func updates() -> AsyncStream<RuntimeSnapshot> {
        let identifier = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(RuntimeStreamBufferLimits.latestState)) { continuation in
            observers[identifier] = continuation
            continuation.yield(makeSnapshot())
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeObserver(identifier) }
            }
        }
    }

    public func updateProcess(_ next: ChatGPTProcessHealth) {
        process = next
        publish()
    }

    public func updateLifecycle(_ next: AppLifecyclePhase) {
        lifecycle = next
        publish()
    }

    public func updateConnection(_ next: CDPConnectionState) {
        connection = next
        publish()
    }

    public func updateTarget(_ target: TargetRuntimeHealth) {
        guard target.adapterIdentifier != "runtime" else { return }
        targets[targetKey(targetIdentifier: target.targetIdentifier, adapterIdentifier: target.adapterIdentifier)] = target
        publish()
    }

    public func removeTarget(identifier: String) {
        if let current = targetGenerations[identifier] {
            targetGenerations[identifier] = .init(generation: current.generation, isRemoved: true)
        }
        targets = targets.filter {
            $0.value.targetIdentifier != identifier || $0.value.adapterIdentifier == "runtime"
        }
        publish()
    }

    public func beginTarget(identifier: String, generation: UInt64) {
        if let current = targetGenerations[identifier], generation <= current.generation {
            return
        }
        targetGenerations[identifier] = .init(generation: generation, isRemoved: false)
        targets = targets.filter {
            $0.value.targetIdentifier != identifier || $0.value.adapterIdentifier == "runtime"
        }
        publish()
    }

    public func updateTarget(_ target: TargetRuntimeHealth, generation: UInt64) {
        guard target.adapterIdentifier != "runtime" else { return }
        guard let current = targetGenerations[target.targetIdentifier],
              current.generation == generation,
              !current.isRemoved else { return }
        targets[targetKey(
            targetIdentifier: target.targetIdentifier,
            adapterIdentifier: target.adapterIdentifier
        )] = target
        publish()
    }

    public func removeTarget(identifier: String, generation: UInt64) {
        guard let current = targetGenerations[identifier],
              current.generation == generation,
              !current.isRemoved else { return }
        targetGenerations[identifier] = .init(generation: generation, isRemoved: true)
        targets = targets.filter {
            $0.value.targetIdentifier != identifier || $0.value.adapterIdentifier == "runtime"
        }
        publish()
    }

    public func beginRuntime(generation: UInt64) {
        if let current = runtimeGeneration, generation <= current.generation { return }
        runtimeGeneration = .init(generation: generation, isEnded: false)
        runtimeTargetRevisions.removeAll()
        targets = targets.filter { $0.value.adapterIdentifier != "runtime" }
        publish()
    }

    public func beginRuntimeTarget(
        targetIdentifier: String,
        lifecycleGeneration: UInt64,
        targetRevision: UInt64
    ) {
        guard acceptsRuntimeLifecycle(lifecycleGeneration) else { return }
        if let current = runtimeTargetRevisions[targetIdentifier],
           current.lifecycleGeneration == lifecycleGeneration,
           targetRevision <= current.targetRevision { return }
        runtimeTargetRevisions[targetIdentifier] = .init(
            lifecycleGeneration: lifecycleGeneration,
            targetRevision: targetRevision,
            isInvalidated: false
        )
        targets.removeValue(forKey: targetKey(
            targetIdentifier: targetIdentifier,
            adapterIdentifier: "runtime"
        ))
        publish()
    }

    public func degradeRuntime(
        targetIdentifier: String,
        reason: String,
        lifecycleGeneration: UInt64,
        targetRevision: UInt64
    ) {
        guard acceptsRuntimeTarget(
            targetIdentifier: targetIdentifier,
            lifecycleGeneration: lifecycleGeneration,
            targetRevision: targetRevision
        ) else { return }
        let target = TargetRuntimeHealth(
            targetIdentifier: targetIdentifier,
            adapterIdentifier: "runtime",
            state: .degraded(reason: reason)
        )
        targets[targetKey(targetIdentifier: targetIdentifier, adapterIdentifier: "runtime")] = target
        publish()
    }

    public func clearRuntime(
        targetIdentifier: String,
        lifecycleGeneration: UInt64,
        targetRevision: UInt64
    ) {
        guard acceptsRuntimeTarget(
            targetIdentifier: targetIdentifier,
            lifecycleGeneration: lifecycleGeneration,
            targetRevision: targetRevision
        ) else { return }
        targets.removeValue(forKey: targetKey(
            targetIdentifier: targetIdentifier,
            adapterIdentifier: "runtime"
        ))
        publish()
    }

    public func invalidateRuntimeTarget(
        targetIdentifier: String,
        lifecycleGeneration: UInt64,
        targetRevision: UInt64
    ) {
        guard acceptsRuntimeTarget(
            targetIdentifier: targetIdentifier,
            lifecycleGeneration: lifecycleGeneration,
            targetRevision: targetRevision
        ) else { return }
        runtimeTargetRevisions[targetIdentifier] = .init(
            lifecycleGeneration: lifecycleGeneration,
            targetRevision: targetRevision,
            isInvalidated: true
        )
        targets.removeValue(forKey: targetKey(
            targetIdentifier: targetIdentifier,
            adapterIdentifier: "runtime"
        ))
        publish()
    }

    public func endRuntime(generation: UInt64) {
        guard let current = runtimeGeneration,
              current.generation == generation,
              !current.isEnded else { return }
        runtimeGeneration = .init(generation: generation, isEnded: true)
        runtimeTargetRevisions.removeAll()
        targets = targets.filter { $0.value.adapterIdentifier != "runtime" }
        publish()
    }

    private func acceptsRuntimeLifecycle(_ generation: UInt64) -> Bool {
        guard let current = runtimeGeneration else { return false }
        return current.generation == generation && !current.isEnded
    }

    private func acceptsRuntimeTarget(
        targetIdentifier: String,
        lifecycleGeneration: UInt64,
        targetRevision: UInt64
    ) -> Bool {
        guard acceptsRuntimeLifecycle(lifecycleGeneration),
              let current = runtimeTargetRevisions[targetIdentifier] else { return false }
        return current.lifecycleGeneration == lifecycleGeneration
            && current.targetRevision == targetRevision
            && !current.isInvalidated
    }

    private func makeSnapshot() -> RuntimeSnapshot {
        RuntimeSnapshot(
            process: process,
            lifecycle: lifecycle,
            connection: connection,
            targets: targets.values.sorted {
                ($0.targetIdentifier, $0.adapterIdentifier) < ($1.targetIdentifier, $1.adapterIdentifier)
            }
        )
    }

    private func publish() {
        let snapshot = makeSnapshot()
        for observer in observers.values {
            observer.yield(snapshot)
        }
    }

    private func removeObserver(_ identifier: UUID) {
        observers.removeValue(forKey: identifier)
    }

    private func targetKey(targetIdentifier: String, adapterIdentifier: String) -> String {
        "\(targetIdentifier)\u{0}\(adapterIdentifier)"
    }
}
