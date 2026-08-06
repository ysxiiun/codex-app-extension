import Foundation

public enum RuntimeControllerError: Error, LocalizedError, Sendable {
    case noQualifiedTarget
    case restartConfirmationUnavailable
    case configurationRejected(String)

    public var errorDescription: String? {
        switch self {
        case .noQualifiedTarget: return "当前没有通过资格检查的 ChatGPT target"
        case .restartConfirmationUnavailable: return "当前没有待确认的重启计划"
        case let .configurationRejected(reason): return "配置未应用，已恢复上一版本：\(reason)"
        }
    }
}

public struct RuntimeControllerSnapshot: Equatable, Sendable {
    public let runtime: RuntimeSnapshot
    public let configuration: AppConfiguration
    public let migrationReport: LegacyMigrationReport?
    public let launchAtLogin: LaunchAtLoginStatus
    public let pendingRestartConfirmation: Bool
    public let activeTargetIdentifier: String?
    public let lastError: String?
    public let isInitialized: Bool

    public init(
        runtime: RuntimeSnapshot = .init(),
        configuration: AppConfiguration = .defaultConfiguration,
        migrationReport: LegacyMigrationReport? = nil,
        launchAtLogin: LaunchAtLoginStatus = .notRegistered,
        pendingRestartConfirmation: Bool = false,
        activeTargetIdentifier: String? = nil,
        lastError: String? = nil,
        isInitialized: Bool = false
    ) {
        self.runtime = runtime
        self.configuration = configuration
        self.migrationReport = migrationReport
        self.launchAtLogin = launchAtLogin
        self.pendingRestartConfirmation = pendingRestartConfirmation
        self.activeTargetIdentifier = activeTargetIdentifier
        self.lastError = lastError
        self.isInitialized = isInitialized
    }
}

public enum ExtensionStatusTone: String, Equatable, Sendable {
    case green
    case yellow
    case red
    case gray
}

public enum ExtensionStatusResolver {
    public static func tone(for snapshot: RuntimeControllerSnapshot) -> ExtensionStatusTone {
        guard snapshot.configuration.global.isEnabled else { return .gray }
        if snapshot.lastError != nil { return .red }
        if case .degraded = snapshot.runtime.lifecycle { return .red }
        if case .notRunning = snapshot.runtime.process { return .gray }
        if snapshot.runtime.targets.contains(where: {
            if case .degraded = $0.state { return true }
            return false
        }) { return .yellow }
        if snapshot.runtime.targets.contains(where: {
            if case .waiting = $0.state { return true }
            return false
        }) { return .yellow }
        if case .active = snapshot.runtime.lifecycle { return .green }
        return .yellow
    }
}

public enum ConfigurationDraftSync {
    public static func resolve(
        draft: AppConfiguration,
        previousPersisted: AppConfiguration,
        nextPersisted: AppConfiguration,
        isApplying: Bool
    ) -> AppConfiguration {
        let wasClean = draft == previousPersisted
        let applyCompleted = isApplying && previousPersisted != nextPersisted
        return wasClean || applyCompleted ? nextPersisted : draft
    }
}

public protocol RuntimeControlling: Sendable {
    func snapshot() async -> RuntimeControllerSnapshot
    func updates() async -> AsyncStream<RuntimeControllerSnapshot>
    func start() async
    func refresh() async
    func startChatGPT() async
    func confirmRestart() async
    func reconnect() async
    func reinject() async
    func diagnose() async
    func apply(configuration: AppConfiguration) async throws
    func shutdown() async
    func setLaunchAtLogin(_ enabled: Bool) async
    func openOfficialSettings() async
    func diagnosticsTextSummary() async -> String
    func exportDiagnostics(to parentDirectory: URL) async throws -> URL
}

public extension RuntimeControlling {
    func shutdown() async {}
    func diagnosticsTextSummary() async -> String { "Codex App Extension diagnostics unavailable" }
    func exportDiagnostics(to parentDirectory: URL) async throws -> URL {
        throw DiagnosticExportError.destinationUnavailable
    }
}

public protocol RuntimePipelining: Sendable {
    func connect(port: UInt16, configuration: AppConfiguration) async throws
    func apply(configuration: AppConfiguration, operation: PageRuntimeOperation) async throws
    func apply(
        configuration: AppConfiguration,
        operation: PageRuntimeOperation,
        selectedIDs: Set<FeatureIdentifier>?
    ) async throws
    func reconnect(configuration: AppConfiguration) async throws
    func stop() async
    func isReady() async -> Bool
    func activeTargetIdentifier() async -> String?
    func pollHealth() async -> RuntimePerformancePollSummary?
}

public extension RuntimePipelining {
    func apply(
        configuration: AppConfiguration,
        operation: PageRuntimeOperation,
        selectedIDs: Set<FeatureIdentifier>?
    ) async throws {
        try await apply(configuration: configuration, operation: operation)
    }

    func pollHealth() async -> RuntimePerformancePollSummary? { nil }
}

public struct RuntimePerformancePollSummary: Equatable, Sendable {
    public let degradedAdapterCount: Int
    public let maximumDurationMilliseconds: Int

    public init(degradedAdapterCount: Int, maximumDurationMilliseconds: Int) {
        self.degradedAdapterCount = max(0, degradedAdapterCount)
        self.maximumDurationMilliseconds = max(0, maximumDurationMilliseconds)
    }
}

public protocol RuntimeClock: Sendable {
    func sleep(for duration: Duration) async throws
}

public struct SystemRuntimeClock: RuntimeClock {
    public init() {}
    public func sleep(for duration: Duration) async throws { try await Task.sleep(for: duration) }
}

public struct RuntimeRetryPolicy: Equatable, Sendable {
    public let connectionAttempts: Int
    public let targetAttempts: Int
    public let delay: Duration

    public init(connectionAttempts: Int = 12, targetAttempts: Int = 20, delay: Duration = .milliseconds(250)) {
        self.connectionAttempts = max(1, connectionAttempts)
        self.targetAttempts = max(1, targetAttempts)
        self.delay = delay
    }
}

public protocol CDPRuntimeClient: CDPCommanding {
    func connect(to baseURL: URL) async throws
    func disconnect(unexpected: Bool) async
    func snapshot() async -> CDPClientSnapshot
    func events() async -> AsyncStream<CDPEvent>
}

extension CDPClient: CDPRuntimeClient {}

public actor CDPRuntimePipeline: RuntimePipelining {
    private struct TargetActivation: Hashable {
        let targetIdentifier: String
        let runtimeGeneration: UInt64
        let targetRevision: UInt64
    }

    private struct RuntimeTargetRevision: Equatable {
        let revision: UInt64
        let isInvalidated: Bool
    }

    private let client: any CDPRuntimeClient
    private let bridge: any PageRuntimeBridging
    private let healthCenter: HealthCenter
    private let clock: any RuntimeClock
    private let retryPolicy: RuntimeRetryPolicy
    private var activeTarget: CDPTarget?
    private var knownTargetIdentifiers: Set<String> = []
    private var targetActivations: Set<TargetActivation> = []
    private var targetInvalidationTasks: [TargetActivation: Task<Void, Never>] = [:]
    private var lastPort: UInt16?
    private var latestConfiguration = AppConfiguration.defaultConfiguration
    private var eventTask: Task<Void, Never>?
    private var nextRuntimeGeneration: UInt64 = 0
    private var activeRuntimeGeneration: UInt64?
    private var nextTargetRevisions: [String: UInt64] = [:]
    private var runtimeTargetRevisions: [String: RuntimeTargetRevision] = [:]

    public init(
        client: any CDPRuntimeClient,
        bridge: any PageRuntimeBridging,
        healthCenter: HealthCenter,
        clock: any RuntimeClock = SystemRuntimeClock(),
        retryPolicy: RuntimeRetryPolicy = .init()
    ) {
        self.client = client
        self.bridge = bridge
        self.healthCenter = healthCenter
        self.clock = clock
        self.retryPolicy = retryPolicy
    }

    public func connect(port: UInt16, configuration: AppConfiguration) async throws {
        await tearDown(clearPort: false)
        nextRuntimeGeneration &+= 1
        let runtimeGeneration = nextRuntimeGeneration
        activeRuntimeGeneration = runtimeGeneration
        await healthCenter.beginRuntime(generation: runtimeGeneration)
        lastPort = port
        latestConfiguration = configuration
        let baseURL = URL(string: "http://127.0.0.1:\(port)")!
        do {
            var connected = false
            var lastConnectionError: Error = CDPClientError.notConnected
            for attempt in 1...retryPolicy.connectionAttempts {
                do {
                    try await client.connect(to: baseURL)
                    connected = true
                    break
                } catch {
                    lastConnectionError = error
                    await synchronizeConnectionHealth()
                    guard attempt < retryPolicy.connectionAttempts else { break }
                    await client.disconnect(unexpected: false)
                    try await clock.sleep(for: retryPolicy.delay)
                }
            }
            guard connected else { throw lastConnectionError }

            await synchronizeConnectionHealth()
            let events = await client.events()
            startEventLoop(events, generation: runtimeGeneration)
            _ = try await client.request(
                method: "Target.setDiscoverTargets",
                params: .object(["discover": .bool(true)]),
                sessionIdentifier: nil,
                timeout: .seconds(5)
            )
            try await waitForQualifiedTarget(configuration: configuration, generation: runtimeGeneration)
        } catch {
            await synchronizeConnectionHealth()
            await healthCenter.updateLifecycle(.degraded(processIdentifier: nil, reason: error.localizedDescription))
            throw error
        }
    }

    public func apply(configuration: AppConfiguration, operation: PageRuntimeOperation) async throws {
        try await apply(configuration: configuration, operation: operation, selectedIDs: nil)
    }

    public func apply(
        configuration: AppConfiguration,
        operation: PageRuntimeOperation,
        selectedIDs: Set<FeatureIdentifier>?
    ) async throws {
        guard let activeTarget else { throw RuntimeControllerError.noQualifiedTarget }
        latestConfiguration = configuration
        _ = try await bridge.apply(
            configuration: configuration,
            to: activeTarget,
            operation: operation,
            selectedIDs: selectedIDs
        )
    }

    public func reconnect(configuration: AppConfiguration) async throws {
        guard let lastPort else { throw RuntimeControllerError.noQualifiedTarget }
        try await connect(port: lastPort, configuration: configuration)
    }

    public func stop() async {
        await tearDown(clearPort: true)
        await healthCenter.updateConnection(.disconnected)
    }

    public func isReady() async -> Bool {
        guard activeTarget != nil else { return false }
        if case .connected = (await client.snapshot()).state { return true }
        return false
    }

    public func activeTargetIdentifier() -> String? { activeTarget?.identifier }

    func invalidateTarget(identifier: String) async {
        guard let generation = activeRuntimeGeneration else { return }
        await invalidateTarget(identifier: identifier, lifecycleGeneration: generation)
    }

    public func pollHealth() async -> RuntimePerformancePollSummary? {
        guard let activeTarget,
              let measurements = try? await bridge.pollPerformance(target: activeTarget) else { return nil }
        let degraded = measurements.filter(\.isDegraded)
        return .init(
            degradedAdapterCount: degraded.count,
            maximumDurationMilliseconds: degraded.map(\.durationMilliseconds).max() ?? 0
        )
    }

    private func startEventLoop(_ events: AsyncStream<CDPEvent>, generation: UInt64) {
        eventTask?.cancel()
        eventTask = Task {
            for await event in events {
                if Task.isCancelled { break }
                await self.handle(event, generation: generation)
            }
        }
    }

    private func handle(_ event: CDPEvent, generation: UInt64) async {
        guard activeRuntimeGeneration == generation else { return }
        switch event.method {
        case "Target.targetCreated":
            guard let target = Self.decodeTarget(event.params?["targetInfo"]) else { return }
            await activateEventTarget(
                target,
                replacing: activeTarget?.identifier == target.identifier ? nil : activeTarget,
                generation: generation
            )
        case "Target.targetDestroyed":
            guard let identifier = event.params?["targetId"]?.stringValue else { return }
            await invalidateTarget(identifier: identifier, lifecycleGeneration: generation)
        case "Target.targetInfoChanged":
            guard let target = Self.decodeTarget(event.params?["targetInfo"]) else { return }
            if let activeTarget,
               activeTarget.identifier == target.identifier,
               activeTarget.url == target.url {
                // Chrome emits metadata-only targetInfoChanged events for the active page.
                // Refresh the runtime in place so a reloaded JS context is reinjected without
                // publishing a transient "no active target" state to menu/status consumers.
                await activateEventTarget(target, generation: generation)
                return
            }
            if let activeTarget, activeTarget.identifier != target.identifier {
                // Qualify and install the replacement before publishing it as active. The old
                // target remains available throughout probing and is invalidated only after the
                // replacement has atomically taken ownership of activeTarget.
                await activateEventTarget(target, replacing: activeTarget, generation: generation)
                return
            }
            await invalidateTarget(identifier: target.identifier, lifecycleGeneration: generation)
            guard target.url == TargetCoordinator.codexSurfaceURL else { return }
            await activateEventTarget(target, generation: generation)
        default:
            break
        }
    }

    private func waitForQualifiedTarget(configuration: AppConfiguration, generation: UInt64) async throws {
        var lastError: Error = RuntimeControllerError.noQualifiedTarget
        for attempt in 1...retryPolicy.targetAttempts {
            if activeTarget != nil { return }
            do {
                let result = try await client.request(
                    method: "Target.getTargets",
                    params: nil,
                    sessionIdentifier: nil,
                    timeout: .seconds(5)
                )
                guard case let .array(infos)? = result?["targetInfos"] else {
                    throw RuntimeControllerError.noQualifiedTarget
                }
                for info in infos {
                    guard let target = Self.decodeTarget(info) else { continue }
                    do {
                        let targetRevision = try await beginTargetRevision(
                            targetIdentifier: target.identifier,
                            lifecycleGeneration: generation
                        )
                        if try await qualifyAndActivate(
                            target,
                            configuration: configuration,
                            generation: generation,
                            targetRevision: targetRevision
                        ) { return }
                    } catch {
                        if !Self.isStaleRevision(error) {
                            lastError = error
                        }
                    }
                }
            } catch {
                if !Self.isStaleRevision(error) {
                    lastError = error
                }
            }
            if activeTarget != nil { return }
            guard attempt < retryPolicy.targetAttempts else { break }
            try await clock.sleep(for: retryPolicy.delay)
        }
        throw lastError
    }

    private func activateEventTarget(
        _ target: CDPTarget,
        replacing previousTarget: CDPTarget? = nil,
        generation: UInt64
    ) async {
        guard activeRuntimeGeneration == generation else { return }
        let refreshesActiveTarget = previousTarget == nil
            && activeTarget?.identifier == target.identifier
            && activeTarget?.url == target.url
        let targetRevision: UInt64
        do {
            targetRevision = try await beginTargetRevision(
                targetIdentifier: target.identifier,
                lifecycleGeneration: generation
            )
        } catch {
            return
        }
        do {
            let activated = try await qualifyAndActivate(
                target,
                configuration: latestConfiguration,
                allowsActiveTargetReplacement: previousTarget != nil,
                generation: generation,
                targetRevision: targetRevision
            )
            guard activated else {
                if refreshesActiveTarget {
                    await healthCenter.degradeRuntime(
                        targetIdentifier: target.identifier,
                        reason: "surface-probe-unqualified",
                        lifecycleGeneration: generation,
                        targetRevision: targetRevision
                    )
                }
                return
            }
            if let previousTarget, previousTarget.identifier != target.identifier {
                await invalidateTarget(
                    identifier: previousTarget.identifier,
                    lifecycleGeneration: generation
                )
            }
            await healthCenter.clearRuntime(
                targetIdentifier: target.identifier,
                lifecycleGeneration: generation,
                targetRevision: targetRevision
            )
        } catch {
            if Self.isStaleRevision(error) { return }
            await healthCenter.degradeRuntime(
                targetIdentifier: target.identifier,
                reason: error.localizedDescription,
                lifecycleGeneration: generation,
                targetRevision: targetRevision
            )
        }
    }

    private func qualifyAndActivate(
        _ target: CDPTarget,
        configuration: AppConfiguration,
        allowsActiveTargetReplacement: Bool = false,
        generation: UInt64,
        targetRevision: UInt64
    ) async throws -> Bool {
        guard isCurrentTargetRevision(
            targetIdentifier: target.identifier,
            lifecycleGeneration: generation,
            targetRevision: targetRevision
        ) else {
            throw PageRuntimeBridgeError.staleRevision(target.identifier)
        }
        guard target.url == TargetCoordinator.codexSurfaceURL else { return false }
        if !allowsActiveTargetReplacement,
           let activeTarget,
           activeTarget.identifier != target.identifier { return false }
        let activation = TargetActivation(
            targetIdentifier: target.identifier,
            runtimeGeneration: generation,
            targetRevision: targetRevision
        )
        guard targetActivations.insert(activation).inserted else { return false }
        defer { targetActivations.remove(activation) }
        knownTargetIdentifiers.insert(target.identifier)
        let result = try await bridge.probe(target: target, requiredAnchors: TargetCoordinator.requiredAnchors)
        guard isCurrentTargetRevision(
            targetIdentifier: target.identifier,
            lifecycleGeneration: generation,
            targetRevision: targetRevision
        ) else {
            throw PageRuntimeBridgeError.staleRevision(target.identifier)
        }
        guard result.isCodexSurface else { return false }
        _ = try await bridge.apply(configuration: configuration, to: target, operation: .install)
        guard isCurrentTargetRevision(
            targetIdentifier: target.identifier,
            lifecycleGeneration: generation,
            targetRevision: targetRevision
        ) else {
            throw PageRuntimeBridgeError.staleRevision(target.identifier)
        }
        activeTarget = target
        return true
    }

    private func beginTargetRevision(
        targetIdentifier: String,
        lifecycleGeneration: UInt64
    ) async throws -> UInt64 {
        await waitForPendingInvalidations(targetIdentifier: targetIdentifier)
        guard activeRuntimeGeneration == lifecycleGeneration else {
            throw PageRuntimeBridgeError.staleRevision(targetIdentifier)
        }
        let revision = (nextTargetRevisions[targetIdentifier] ?? 0) &+ 1
        nextTargetRevisions[targetIdentifier] = revision
        runtimeTargetRevisions[targetIdentifier] = .init(revision: revision, isInvalidated: false)
        await healthCenter.beginRuntimeTarget(
            targetIdentifier: targetIdentifier,
            lifecycleGeneration: lifecycleGeneration,
            targetRevision: revision
        )
        guard isCurrentTargetRevision(
            targetIdentifier: targetIdentifier,
            lifecycleGeneration: lifecycleGeneration,
            targetRevision: revision
        ) else {
            throw PageRuntimeBridgeError.staleRevision(targetIdentifier)
        }
        return revision
    }

    private func currentTargetRevision(
        targetIdentifier: String,
        lifecycleGeneration: UInt64
    ) -> UInt64? {
        guard activeRuntimeGeneration == lifecycleGeneration,
              let state = runtimeTargetRevisions[targetIdentifier],
              !state.isInvalidated else { return nil }
        return state.revision
    }

    private func isCurrentTargetRevision(
        targetIdentifier: String,
        lifecycleGeneration: UInt64,
        targetRevision: UInt64
    ) -> Bool {
        currentTargetRevision(
            targetIdentifier: targetIdentifier,
            lifecycleGeneration: lifecycleGeneration
        ) == targetRevision
    }

    private func invalidateTarget(
        identifier: String,
        lifecycleGeneration: UInt64
    ) async {
        guard activeRuntimeGeneration == lifecycleGeneration,
              let current = runtimeTargetRevisions[identifier] else { return }

        let targetRevision = current.revision
        let invalidation = TargetActivation(
            targetIdentifier: identifier,
            runtimeGeneration: lifecycleGeneration,
            targetRevision: targetRevision
        )
        if current.isInvalidated {
            if let task = targetInvalidationTasks[invalidation] {
                await task.value
                targetInvalidationTasks.removeValue(forKey: invalidation)
            }
            return
        }

        runtimeTargetRevisions[identifier] = .init(
            revision: targetRevision,
            isInvalidated: true
        )
        knownTargetIdentifiers.remove(identifier)
        if activeTarget?.identifier == identifier { activeTarget = nil }

        let healthCenter = healthCenter
        let bridge = bridge
        let task = Task {
            await healthCenter.invalidateRuntimeTarget(
                targetIdentifier: identifier,
                lifecycleGeneration: lifecycleGeneration,
                targetRevision: targetRevision
            )
            await bridge.invalidate(targetIdentifier: identifier)
        }
        targetInvalidationTasks[invalidation] = task
        await task.value
        targetInvalidationTasks.removeValue(forKey: invalidation)
    }

    private func waitForPendingInvalidations(targetIdentifier: String) async {
        let pending = targetInvalidationTasks.filter {
            $0.key.targetIdentifier == targetIdentifier
        }
        for (invalidation, task) in pending {
            await task.value
            targetInvalidationTasks.removeValue(forKey: invalidation)
        }
    }

    private func tearDown(clearPort: Bool) async {
        eventTask?.cancel()
        eventTask = nil
        let endingRuntimeGeneration = activeRuntimeGeneration
        if let endingRuntimeGeneration {
            var identifiers = Set(runtimeTargetRevisions.keys)
            identifiers.formUnion(knownTargetIdentifiers)
            if let activeTarget { identifiers.insert(activeTarget.identifier) }
            for identifier in identifiers {
                await invalidateTarget(
                    identifier: identifier,
                    lifecycleGeneration: endingRuntimeGeneration
                )
            }
            activeRuntimeGeneration = nil
            await healthCenter.endRuntime(generation: endingRuntimeGeneration)
        }
        knownTargetIdentifiers.removeAll()
        runtimeTargetRevisions.removeAll()
        targetActivations.removeAll()
        targetInvalidationTasks.removeAll()
        activeTarget = nil
        await client.disconnect(unexpected: false)
        if clearPort { lastPort = nil }
    }

    private func synchronizeConnectionHealth() async {
        await healthCenter.updateConnection((await client.snapshot()).state)
    }

    private static func decodeTarget(_ value: JSONValue?) -> CDPTarget? {
        guard let identifier = value?["targetId"]?.stringValue,
              let rawURL = value?["url"]?.stringValue,
              let url = URL(string: rawURL) else { return nil }
        return .init(identifier: identifier, url: url)
    }

    private static func isStaleRevision(_ error: Error) -> Bool {
        guard let bridgeError = error as? PageRuntimeBridgeError else { return false }
        if case .staleRevision = bridgeError { return true }
        return false
    }
}

public struct RuntimeMonitorPolicy: Equatable, Sendable {
    public let isEnabled: Bool
    public let interval: Duration

    public init(isEnabled: Bool = true, interval: Duration = .seconds(2)) {
        self.isEnabled = isEnabled
        self.interval = interval
    }

    public static let disabled = RuntimeMonitorPolicy(isEnabled: false)
}

public actor RuntimeController: RuntimeControlling {
    private let store: ConfigStore
    private let migrator: LegacyConfigMigrator
    private let applications: any ApplicationServicing
    private let lifecycle: AppLifecycleMonitor
    private let sessionManager: DebugSessionManager
    private let pipeline: any RuntimePipelining
    private let healthCenter: HealthCenter
    private let launchAtLoginController: any LaunchAtLoginControlling
    private let clock: any RuntimeClock
    private let monitorPolicy: RuntimeMonitorPolicy
    private let diagnosticLogStore: DiagnosticLogStore?
    private let diagnosticAppVersion: DiagnosticVersion
    private var current = RuntimeControllerSnapshot()
    private var pendingPlan: DebugSessionPlan?
    private var observedProcessIdentifier: Int32?
    private var observedDebugPort: UInt16?
    private var observers: [UUID: AsyncStream<RuntimeControllerSnapshot>.Continuation] = [:]
    private var healthTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?
    private var lastDiagnosticFingerprint: DiagnosticFingerprint?

    private struct DiagnosticFingerprint: Equatable {
        let kind: DiagnosticEventKind
        let state: DiagnosticState
        let errorCode: DiagnosticErrorCode?
        let count: Int?
    }

    public init(
        store: ConfigStore,
        migrator: LegacyConfigMigrator,
        applications: any ApplicationServicing,
        lifecycle: AppLifecycleMonitor,
        sessionManager: DebugSessionManager,
        pipeline: any RuntimePipelining,
        healthCenter: HealthCenter,
        launchAtLoginController: any LaunchAtLoginControlling,
        clock: any RuntimeClock = SystemRuntimeClock(),
        monitorPolicy: RuntimeMonitorPolicy = .init(),
        diagnosticLogStore: DiagnosticLogStore? = nil,
        diagnosticAppVersion: DiagnosticVersion = .init(major: 0, minor: 0, patch: 0)
    ) {
        self.store = store
        self.migrator = migrator
        self.applications = applications
        self.lifecycle = lifecycle
        self.sessionManager = sessionManager
        self.pipeline = pipeline
        self.healthCenter = healthCenter
        self.launchAtLoginController = launchAtLoginController
        self.clock = clock
        self.monitorPolicy = monitorPolicy
        self.diagnosticLogStore = diagnosticLogStore
        self.diagnosticAppVersion = diagnosticAppVersion
    }

    public func snapshot() -> RuntimeControllerSnapshot { current }

    public func updates() -> AsyncStream<RuntimeControllerSnapshot> {
        let identifier = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            observers[identifier] = continuation
            continuation.yield(current)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeObserver(identifier) }
            }
        }
    }

    public func start() async {
        startHealthSubscription()
        do {
            let report = try await migrator.migrateIfNeeded(using: store)
            let configuration = try await store.load()
            let loginStatus = await launchAtLoginController.status()
            current = .init(
                runtime: await healthCenter.snapshot(),
                configuration: configuration,
                migrationReport: report,
                launchAtLogin: loginStatus,
                isInitialized: true
            )
            publish()
            await recordDiagnostic(kind: .startup, state: .healthy)
            await refresh()
            startProcessMonitor()
        } catch {
            await setError(error)
        }
    }

    public func refresh() async {
        let application = await lifecycle.refreshProcess()
        guard let application else {
            let pipelineReady = await pipeline.isReady()
            let requiresCleanup = observedProcessIdentifier != nil || pipelineReady
            pendingPlan = nil
            observedProcessIdentifier = nil
            observedDebugPort = nil
            if requiresCleanup { await pipeline.stop() }
            await healthCenter.updateProcess(.notRunning)
            await healthCenter.updateConnection(.disconnected)
            await healthCenter.updateLifecycle(.notRunning)
            await synchronizeRuntimeFromHealth()
            publish(pendingRestart: false, clearingError: true)
            await recordDiagnostic(kind: .lifecycle, state: .inactive, errorCode: .applicationNotRunning)
            return
        }
        await healthCenter.updateProcess(.running(processIdentifier: application.processIdentifier))

        let sameProcess = observedProcessIdentifier == application.processIdentifier
        let samePort = observedDebugPort == application.debugPort
        if sameProcess, samePort {
            if application.debugPort != nil {
                if await pipeline.isReady() {
                    let performance = await pipeline.pollHealth()
                    await synchronizeRuntimeFromHealth()
                    publish(clearingError: true)
                    await recordPerformanceDegradationIfNeeded(performance)
                    return
                }
                do {
                    try await pipeline.reconnect(configuration: current.configuration)
                    await healthCenter.updateLifecycle(.active(processIdentifier: application.processIdentifier, targetCount: 1))
                    await synchronizeRuntimeFromHealth()
                    publish(clearingError: true)
                    return
                } catch {
                    await healthCenter.updateLifecycle(.degraded(processIdentifier: application.processIdentifier, reason: error.localizedDescription))
                    await synchronizeRuntimeFromHealth()
                    await setError(error)
                    return
                }
            }
            await synchronizeRuntimeFromHealth()
            publish(clearingError: true)
            return
        }

        if observedProcessIdentifier != nil {
            await pipeline.stop()
        }
        observedProcessIdentifier = application.processIdentifier
        observedDebugPort = application.debugPort
        do {
            let plan = try await sessionManager.makePlan(for: application)
            switch plan {
            case let .connect(pid, port):
                pendingPlan = nil
                await healthCenter.updateLifecycle(.connecting(processIdentifier: pid, port: port))
                try await pipeline.connect(port: port, configuration: current.configuration)
                await healthCenter.updateLifecycle(.active(processIdentifier: pid, targetCount: 1))
                await synchronizeRuntimeFromHealth()
                publish(pendingRestart: false, clearingError: true)
            case .restartAfterConfirmation:
                pendingPlan = plan
                try? await lifecycle.transition(to: .awaitingRestartConfirmation(processIdentifier: application.processIdentifier))
                await healthCenter.updateLifecycle(.awaitingRestartConfirmation(processIdentifier: application.processIdentifier))
                await synchronizeRuntimeFromHealth()
                publish(pendingRestart: true)
            case .launch:
                break
            }
        } catch {
            await healthCenter.updateLifecycle(.degraded(processIdentifier: application.processIdentifier, reason: error.localizedDescription))
            await synchronizeRuntimeFromHealth()
            await setError(error)
        }
    }

    public func startChatGPT() async {
        do {
            let plan = try await sessionManager.makePlan(for: nil)
            let result = try await sessionManager.execute(plan)
            observedProcessIdentifier = result.processIdentifier
            observedDebugPort = result.port
            try await pipeline.connect(port: result.port, configuration: current.configuration)
            await healthCenter.updateProcess(.running(processIdentifier: result.processIdentifier))
            await healthCenter.updateLifecycle(.active(processIdentifier: result.processIdentifier, targetCount: 1))
            await synchronizeRuntimeFromHealth()
            publish(clearingError: true)
        } catch { await setError(error) }
    }

    public func confirmRestart() async {
        guard let pendingPlan else {
            await setError(RuntimeControllerError.restartConfirmationUnavailable)
            return
        }
        do {
            let result = try await sessionManager.execute(pendingPlan, restartConfirmed: true)
            self.pendingPlan = nil
            observedProcessIdentifier = result.processIdentifier
            observedDebugPort = result.port
            try await pipeline.connect(port: result.port, configuration: current.configuration)
            await healthCenter.updateProcess(.running(processIdentifier: result.processIdentifier))
            await healthCenter.updateLifecycle(.active(processIdentifier: result.processIdentifier, targetCount: 1))
            await synchronizeRuntimeFromHealth()
            publish(pendingRestart: false, clearingError: true)
        } catch { await setError(error) }
    }

    public func reconnect() async {
        do {
            try await pipeline.reconnect(configuration: current.configuration)
            if let pid = observedProcessIdentifier {
                await healthCenter.updateLifecycle(.active(processIdentifier: pid, targetCount: 1))
            }
            await synchronizeRuntimeFromHealth()
            publish(clearingError: true)
        }
        catch { await setError(error) }
    }

    public func reinject() async {
        do {
            try await pipeline.apply(configuration: current.configuration, operation: .install)
            publish(clearingError: true)
        }
        catch { await setError(error) }
    }

    public func diagnose() async {
        do {
            try await pipeline.apply(configuration: current.configuration, operation: .diagnose)
            publish(clearingError: true)
        }
        catch { await setError(error) }
    }

    public func apply(configuration candidate: AppConfiguration) async throws {
        let previous = current.configuration
        var pagePreapplyAttempted = false
        var pagePreapplySelectedIDs: Set<FeatureIdentifier>?
        do {
            let validated = try candidate.validated()
            let pageSelection = Self.pageAdapterSelection(from: previous, to: validated)
            if pageSelection.requiresApply, await pipeline.isReady() {
                pagePreapplyAttempted = true
                pagePreapplySelectedIDs = pageSelection.selectedIDs
                try await pipeline.apply(
                    configuration: validated,
                    operation: .update,
                    selectedIDs: pageSelection.selectedIDs
                )
            }
            try await store.save(validated)
            current = replacingCurrent(configuration: validated, lastError: nil)
            publish()
        } catch let transactionError {
            if pagePreapplyAttempted {
                do {
                    try await pipeline.apply(
                        configuration: previous,
                        operation: .update,
                        selectedIDs: pagePreapplySelectedIDs
                    )
                } catch {
                    if let fallback = try? await store.restoreLastKnownGood() {
                        try? await pipeline.apply(
                            configuration: fallback,
                            operation: .update,
                            selectedIDs: pagePreapplySelectedIDs
                        )
                        current = replacingCurrent(configuration: fallback, lastError: transactionError.localizedDescription)
                    }
                }
            }
            publish()
            await recordDiagnostic(
                kind: .configurationRecovery,
                state: .failed,
                errorCode: Self.diagnosticErrorCode(for: transactionError)
            )
            throw RuntimeControllerError.configurationRejected(transactionError.localizedDescription)
        }
    }

    public func setLaunchAtLogin(_ enabled: Bool) async {
        do {
            let status = try await launchAtLoginController.setEnabled(enabled)
            var configuration = current.configuration
            switch status {
            case .enabled, .requiresApproval:
                configuration.startup.launchAtLogin = enabled
            case .notRegistered, .unavailable, .error:
                configuration.startup.launchAtLogin = false
            }
            let validated = try configuration.validated()
            try await store.save(validated)
            current = RuntimeControllerSnapshot(
                runtime: current.runtime,
                configuration: validated,
                migrationReport: current.migrationReport,
                launchAtLogin: status,
                pendingRestartConfirmation: current.pendingRestartConfirmation,
                activeTargetIdentifier: await pipeline.activeTargetIdentifier(),
                lastError: status == .error || status == .unavailable ? "开机启动授权失败" : nil,
                isInitialized: current.isInitialized
            )
            publish()
        } catch { await setError(error) }
    }

    public func openOfficialSettings() async {
        do {
            try await applications.openOfficialSettings()
            publish(clearingError: true)
        }
        catch { await setError(error) }
    }

    public func diagnosticsTextSummary() -> String {
        DiagnosticExporter().textSummary(
            configuration: current.configuration,
            snapshot: current,
            appVersion: diagnosticAppVersion
        )
    }

    public func exportDiagnostics(to parentDirectory: URL) async throws -> URL {
        guard let diagnosticLogStore else { throw DiagnosticExportError.destinationUnavailable }
        do {
            let url = try await DiagnosticExporter().export(
                configuration: current.configuration,
                snapshot: current,
                logStore: diagnosticLogStore,
                appVersion: diagnosticAppVersion,
                to: parentDirectory
            )
            await recordDiagnostic(kind: .export, state: .healthy)
            return url
        } catch {
            await recordDiagnostic(kind: .export, state: .failed, errorCode: .diagnosticExportFailed)
            throw error
        }
    }

    public func runMonitorCycle() async { await refresh() }

    public func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    public func shutdown() async {
        monitorTask?.cancel()
        monitorTask = nil
        healthTask?.cancel()
        healthTask = nil
        pendingPlan = nil
        observedProcessIdentifier = nil
        observedDebugPort = nil
        await pipeline.stop()
        await healthCenter.updateProcess(.notRunning)
        await healthCenter.updateConnection(.disconnected)
        await healthCenter.updateLifecycle(.notRunning)
        await synchronizeRuntimeFromHealth()
        publish(pendingRestart: false, clearingError: true)
    }

    private func startHealthSubscription() {
        healthTask?.cancel()
        healthTask = Task {
            let updates = await healthCenter.updates()
            for await runtime in updates {
                if Task.isCancelled { break }
                await self.consume(runtime)
            }
        }
    }

    private func startProcessMonitor() {
        monitorTask?.cancel()
        guard monitorPolicy.isEnabled else { return }
        let interval = monitorPolicy.interval
        monitorTask = Task { [clock] in
            while !Task.isCancelled {
                do { try await clock.sleep(for: interval) }
                catch { return }
                if Task.isCancelled { return }
                await self.refresh()
            }
        }
    }

    private func consume(_ runtime: RuntimeSnapshot) async {
        current = RuntimeControllerSnapshot(
            runtime: runtime,
            configuration: current.configuration,
            migrationReport: current.migrationReport,
            launchAtLogin: current.launchAtLogin,
            pendingRestartConfirmation: current.pendingRestartConfirmation,
            activeTargetIdentifier: await pipeline.activeTargetIdentifier(),
            lastError: current.lastError,
            isInitialized: current.isInitialized
        )
        publish()
    }

    private func synchronizeRuntimeFromHealth() async {
        current = RuntimeControllerSnapshot(
            runtime: await healthCenter.snapshot(),
            configuration: current.configuration,
            migrationReport: current.migrationReport,
            launchAtLogin: current.launchAtLogin,
            pendingRestartConfirmation: current.pendingRestartConfirmation,
            activeTargetIdentifier: await pipeline.activeTargetIdentifier(),
            lastError: current.lastError,
            isInitialized: current.isInitialized
        )
    }

    private func publish(pendingRestart: Bool? = nil, clearingError: Bool = false) {
        if pendingRestart != nil || clearingError {
            current = RuntimeControllerSnapshot(
                runtime: current.runtime,
                configuration: current.configuration,
                migrationReport: current.migrationReport,
                launchAtLogin: current.launchAtLogin,
                pendingRestartConfirmation: pendingRestart ?? current.pendingRestartConfirmation,
                activeTargetIdentifier: current.activeTargetIdentifier,
                lastError: clearingError ? nil : current.lastError,
                isInitialized: current.isInitialized
            )
        }
        for observer in observers.values { observer.yield(current) }
    }

    private func setError(_ error: Error) async {
        current = replacingCurrent(configuration: current.configuration, lastError: error.localizedDescription)
        publish()
        await recordDiagnostic(kind: .lifecycle, state: .failed, errorCode: Self.diagnosticErrorCode(for: error))
    }

    private func recordPerformanceDegradationIfNeeded(_ summary: RuntimePerformancePollSummary?) async {
        guard let summary, summary.degradedAdapterCount > 0 else { return }
        await recordDiagnostic(
            kind: .performanceBudget,
            state: .degraded,
            errorCode: .adapterPerformanceBudgetExceeded,
            count: summary.degradedAdapterCount,
            durationMilliseconds: summary.maximumDurationMilliseconds
        )
    }

    private func recordDiagnostic(
        kind: DiagnosticEventKind,
        state: DiagnosticState,
        errorCode: DiagnosticErrorCode? = nil,
        count: Int? = nil,
        durationMilliseconds: Int? = nil
    ) async {
        guard let diagnosticLogStore else { return }
        let fingerprint = DiagnosticFingerprint(kind: kind, state: state, errorCode: errorCode, count: count)
        if lastDiagnosticFingerprint == fingerprint { return }
        lastDiagnosticFingerprint = fingerprint
        _ = await diagnosticLogStore.append(.init(
            appVersion: diagnosticAppVersion,
            kind: kind,
            state: state,
            errorCode: errorCode,
            count: count,
            durationMilliseconds: durationMilliseconds
        ))
    }

    private static func diagnosticErrorCode(for error: Error) -> DiagnosticErrorCode {
        switch error {
        case RuntimeControllerError.noQualifiedTarget: return .noQualifiedTarget
        case RuntimeControllerError.restartConfirmationUnavailable: return .cdpUnavailable
        case RuntimeControllerError.configurationRejected: return .configurationInvalid
        case is ConfigurationValidationError: return .configurationInvalid
        case is ConfigStoreError: return .persistenceFailed
        case is CDPClientError: return .cdpConnectionFailed
        case is PageRuntimeBridgeError: return .adapterOperationFailed
        default: return .cdpUnavailable
        }
    }

    private func replacingCurrent(configuration: AppConfiguration, lastError: String?) -> RuntimeControllerSnapshot {
        .init(
            runtime: current.runtime,
            configuration: configuration,
            migrationReport: current.migrationReport,
            launchAtLogin: current.launchAtLogin,
            pendingRestartConfirmation: current.pendingRestartConfirmation,
            activeTargetIdentifier: current.activeTargetIdentifier,
            lastError: lastError,
            isInitialized: current.isInitialized
        )
    }

    private struct PageAdapterSelection {
        let requiresApply: Bool
        let selectedIDs: Set<FeatureIdentifier>?
    }

    private static func pageAdapterSelection(
        from previous: AppConfiguration,
        to next: AppConfiguration
    ) -> PageAdapterSelection {
        if previous.global != next.global {
            return .init(requiresApply: true, selectedIDs: nil)
        }
        var identifiers: Set<FeatureIdentifier> = []
        if previous.features.wideLayout != next.features.wideLayout { identifiers.insert(.wideLayout) }
        if previous.features.headerAvoidance != next.features.headerAvoidance { identifiers.insert(.headerOffset) }
        if previous.features.ime != next.features.ime { identifiers.insert(.imeEnterGuard) }
        if previous.features.markdownAppearance != next.features.markdownAppearance {
            identifiers.insert(.markdownSemanticTheme)
        }
        return .init(
            requiresApply: !identifiers.isEmpty,
            selectedIDs: identifiers.isEmpty ? nil : identifiers
        )
    }

    private func removeObserver(_ identifier: UUID) { observers.removeValue(forKey: identifier) }
}
