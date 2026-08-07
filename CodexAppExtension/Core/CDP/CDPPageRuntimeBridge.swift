import Foundation

public protocol CDPCommanding: Sendable {
    func request(
        method: String,
        params: JSONValue?,
        sessionIdentifier: String?,
        timeout: Duration?
    ) async throws -> JSONValue?
}

extension CDPClient: CDPCommanding {}

protocol PageRuntimeHealthReporting: Sendable {
    func beginTarget(identifier: String, generation: UInt64) async
    func updateTarget(_ target: TargetRuntimeHealth, generation: UInt64) async
    func removeTarget(identifier: String, generation: UInt64) async
}

extension HealthCenter: PageRuntimeHealthReporting {}

public enum PageRuntimeBridgeError: Error, Equatable, Sendable, LocalizedError {
    case missingSession(String)
    case invalidResponse(String)
    case staleRevision(String)
    case adapterFailures([String])

    public var errorDescription: String? {
        switch self {
        case let .missingSession(target): return "Target \(target) 未返回 flattened sessionId"
        case let .invalidResponse(context): return "CDP Runtime 响应无效: \(context)"
        case let .staleRevision(target): return "Target \(target) 的旧 revision 结果已丢弃"
        case let .adapterFailures(adapters): return "以下增强未通过健康检查: \(adapters.joined(separator: ", "))"
        }
    }
}

public protocol PageRuntimeBridging: Sendable {
    func probe(target: CDPTarget, requiredAnchors: Set<CodexSurfaceAnchor>) async throws -> CodexSurfaceProbeResult
    func apply(configuration: AppConfiguration, to target: CDPTarget, operation: PageRuntimeOperation) async throws -> [FeatureExecutionResult]
    func apply(
        configuration: AppConfiguration,
        to target: CDPTarget,
        operation: PageRuntimeOperation,
        selectedIDs: Set<FeatureIdentifier>?
    ) async throws -> [FeatureExecutionResult]
    func invalidate(targetIdentifier: String) async
    func pollPerformance(target: CDPTarget) async throws -> [AdapterPerformanceMeasurement]
}

public extension PageRuntimeBridging {
    func apply(
        configuration: AppConfiguration,
        to target: CDPTarget,
        operation: PageRuntimeOperation,
        selectedIDs: Set<FeatureIdentifier>?
    ) async throws -> [FeatureExecutionResult] {
        try await apply(configuration: configuration, to: target, operation: operation)
    }

    func pollPerformance(target: CDPTarget) async throws -> [AdapterPerformanceMeasurement] { [] }
}

public struct AdapterPerformanceMeasurement: Equatable, Sendable {
    public let adapterIdentifier: FeatureIdentifier
    public let strikeCount: Int
    public let durationMilliseconds: Int
    public let isDegraded: Bool
    public let isQualified: Bool
    public let isRecoverable: Bool

    public init(
        adapterIdentifier: FeatureIdentifier,
        strikeCount: Int,
        durationMilliseconds: Int,
        isDegraded: Bool,
        isQualified: Bool = true,
        isRecoverable: Bool = false
    ) {
        self.adapterIdentifier = adapterIdentifier
        self.strikeCount = max(0, strikeCount)
        self.durationMilliseconds = max(0, durationMilliseconds)
        self.isDegraded = isDegraded
        self.isQualified = isQualified
        self.isRecoverable = isRecoverable
    }
}

public actor CDPPageRuntimeBridge: PageRuntimeBridging, CodexSurfaceProbing {
    static let implementationRevision = 11

    private struct SessionState: Sendable, Equatable {
        let identifier: String
        let revision: UInt64
        let targetIdentifier: String
    }

    private let client: any CDPCommanding
    private let registry: FeatureRegistry
    private let scriptLoader: any PageRuntimeScriptLoading
    private let healthReporter: any PageRuntimeHealthReporting
    private let bundle: Bundle
    private var sessions: [String: SessionState] = [:]
    private var revisions: [String: UInt64] = [:]

    public init(
        client: any CDPCommanding,
        registry: FeatureRegistry = .init(),
        scriptLoader: (any PageRuntimeScriptLoading)? = nil,
        healthCenter: HealthCenter,
        bundle: Bundle
    ) {
        self.client = client
        self.registry = registry
        if let scriptLoader {
            self.scriptLoader = scriptLoader
        } else {
            self.scriptLoader = registry
        }
        self.healthReporter = healthCenter
        self.bundle = bundle
    }

    init(
        client: any CDPCommanding,
        registry: FeatureRegistry = .init(),
        scriptLoader: (any PageRuntimeScriptLoading)? = nil,
        healthReporter: any PageRuntimeHealthReporting,
        bundle: Bundle
    ) {
        self.client = client
        self.registry = registry
        if let scriptLoader {
            self.scriptLoader = scriptLoader
        } else {
            self.scriptLoader = registry
        }
        self.healthReporter = healthReporter
        self.bundle = bundle
    }

    public func probe(
        target: CDPTarget,
        requiredAnchors: Set<CodexSurfaceAnchor>
    ) async throws -> CodexSurfaceProbeResult {
        let session = try await ensureSession(for: target)
        let expression = #"""
        (() => {
          const layoutRoots = Array.from(document.querySelectorAll('[data-app-shell-main-content-layout]'));
          const layout = layoutRoots.length === 1 ? layoutRoots[0] : null;
          const countWithinLayout = (selector) => layout
            ? Array.from(document.querySelectorAll(selector)).filter((node) => layout.contains(node)).length
            : 0;
          const layoutRoot = layoutRoots.length;
          const threadScroller = countWithinLayout('.thread-scroll-container');
          const composer = countWithinLayout(".ProseMirror[data-codex-composer='true'][contenteditable='true'], .ProseMirror[data-codex-composer='true'][contenteditable='plaintext-only']");
          return { layoutRoot, threadScroller, composer };
        })()
        """#
        let value = try await evaluateRequiringValue(expression, session: session)
        try assertCurrent(session, targetIdentifier: target.identifier)
        guard case let .object(object) = value else {
            throw PageRuntimeBridgeError.invalidResponse("surface-probe")
        }
        let counts: [CodexSurfaceAnchor: Int] = [
            .layoutRoot: Self.integer(object["layoutRoot"]),
            .threadScroller: Self.integer(object["threadScroller"]),
            .composer: Self.integer(object["composer"])
        ]
        let matched = Set(counts.compactMap { $0.value == 1 ? $0.key : nil })
        return .init(matchedAnchors: matched.intersection(requiredAnchors), counts: counts)
    }

    public func apply(
        configuration: AppConfiguration,
        to target: CDPTarget,
        operation: PageRuntimeOperation
    ) async throws -> [FeatureExecutionResult] {
        try await apply(
            configuration: configuration,
            to: target,
            operation: operation,
            selectedIDs: nil
        )
    }

    public func apply(
        configuration: AppConfiguration,
        to target: CDPTarget,
        operation: PageRuntimeOperation,
        selectedIDs: Set<FeatureIdentifier>?
    ) async throws -> [FeatureExecutionResult] {
        let session = try await ensureSession(for: target)
        let bootstrap = try scriptLoader.loadBootstrapScript(from: bundle)
        try await evaluateForSideEffect(bootstrap.source, session: session)
        try assertCurrent(session, targetIdentifier: target.identifier)
        let handshakeValue = try await evaluateRequiringValue("window.__codexAppExtensionV2.handshake(0)", session: session)
        try assertCurrent(session, targetIdentifier: target.identifier)
        let handshake = try Self.decodeEnvelope(handshakeValue, context: "runtime-handshake")
        guard handshake.runtimeVersion == FeatureRegistry.runtimeVersion,
              handshake.adapterId == "runtime",
              handshake.operation == .handshake,
              handshake.result?["implementationRevision"] == .number(Double(Self.implementationRevision)),
              handshake.error == nil else {
            throw PageRuntimeBridgeError.invalidResponse("runtime-handshake")
        }

        let requiresRehydration = handshake.result?["rehydrationRequired"] == .bool(true)
        if requiresRehydration, selectedIDs != nil {
            let hydrationOutcome = try await executeAdapterPass(
                configuration: configuration,
                target: target,
                operation: .install,
                selectedIDs: nil,
                startingRequestId: 1,
                session: session
            )
            if hydrationOutcome.failedAdapters.isEmpty {
                try await markHydrated(session: session, targetIdentifier: target.identifier)
            }
        }

        let outcome = try await executeAdapterPass(
            configuration: configuration,
            target: target,
            operation: operation,
            selectedIDs: selectedIDs,
            startingRequestId: selectedIDs == nil ? 1 : 10_000,
            session: session
        )
        if requiresRehydration, selectedIDs == nil, outcome.failedAdapters.isEmpty {
            try await markHydrated(session: session, targetIdentifier: target.identifier)
        }
        try assertCurrent(session, targetIdentifier: target.identifier)
        if !outcome.failedAdapters.isEmpty, operation == .update {
            throw PageRuntimeBridgeError.adapterFailures(outcome.failedAdapters)
        }
        return registry.executionResults(from: outcome.responseEnvelopes)
    }

    private func executeAdapterPass(
        configuration: AppConfiguration,
        target: CDPTarget,
        operation: PageRuntimeOperation,
        selectedIDs: Set<FeatureIdentifier>?,
        startingRequestId: UInt64,
        session: SessionState
    ) async throws -> (responseEnvelopes: [PageRuntimeEnvelope], failedAdapters: [String]) {
        let effectiveOperation: PageRuntimeOperation = configuration.global.isEnabled ? operation : .uninstall
        let registrations = registry.registrations(for: configuration, selectedIDs: selectedIDs)
        let envelopes = registry.envelopes(
            for: configuration,
            operation: effectiveOperation,
            startingRequestId: startingRequestId,
            selectedIDs: selectedIDs
        )
        var responseEnvelopes: [PageRuntimeEnvelope] = []
        var failedAdapters: [String] = []
        for (registration, envelope) in zip(registrations, envelopes) {
            let adapterScript: LoadedFeatureScript
            do {
                adapterScript = try scriptLoader.loadAdapterScript(for: registration, from: bundle)
            } catch {
                failedAdapters.append(envelope.adapterId)
                responseEnvelopes.append(Self.failureEnvelope(for: envelope, reason: "adapter-source-load-failed"))
                await healthReporter.updateTarget(.init(
                    targetIdentifier: target.identifier,
                    adapterIdentifier: envelope.adapterId,
                    state: .degraded(reason: "adapter-source-load-failed")
                ), generation: session.revision)
                continue
            }
            do {
                try await evaluateForSideEffect(adapterScript.source, session: session)
                try assertCurrent(session, targetIdentifier: target.identifier)
            } catch let error as PageRuntimeBridgeError {
                if case .staleRevision = error { throw error }
                failedAdapters.append(envelope.adapterId)
                responseEnvelopes.append(Self.failureEnvelope(for: envelope, reason: "adapter-script-evaluation-failed"))
                await healthReporter.updateTarget(.init(
                    targetIdentifier: target.identifier,
                    adapterIdentifier: envelope.adapterId,
                    state: .degraded(reason: "adapter-script-evaluation-failed")
                ), generation: session.revision)
                continue
            } catch {
                failedAdapters.append(envelope.adapterId)
                responseEnvelopes.append(Self.failureEnvelope(for: envelope, reason: "adapter-script-evaluation-failed"))
                await healthReporter.updateTarget(.init(
                    targetIdentifier: target.identifier,
                    adapterIdentifier: envelope.adapterId,
                    state: .degraded(reason: "adapter-script-evaluation-failed")
                ), generation: session.revision)
                continue
            }
            do {
                let data = try JSONEncoder().encode(envelope)
                guard let json = String(data: data, encoding: .utf8) else {
                    throw PageRuntimeBridgeError.invalidResponse(envelope.adapterId)
                }
                let value = try await evaluateRequiringValue("window.__codexAppExtensionV2.execute(\(json))", session: session)
                try assertCurrent(session, targetIdentifier: target.identifier)
                let responseData = try JSONEncoder().encode(value)
                let response = try JSONDecoder().decode(PageRuntimeEnvelope.self, from: responseData)
                let isQualified: Bool
                if case let .bool(qualified)? = response.result?["qualified"] {
                    isQualified = qualified
                } else {
                    isQualified = true
                }
                let isRecoverable = response.result?["recoverable"] == .bool(true)
                let qualificationReason = response.result?["reason"]?.stringValue ?? "adapter-unqualified"
                let acceptedResponse = response.error == nil && !isQualified && !isRecoverable
                    ? Self.failureEnvelope(for: envelope, reason: qualificationReason)
                    : response
                responseEnvelopes.append(acceptedResponse)
                let state: TargetAdapterState
                if let error = acceptedResponse.error {
                    state = .degraded(reason: error.code)
                } else if !isQualified, isRecoverable {
                    state = .waiting(reason: qualificationReason)
                } else {
                    state = .healthy
                }
                await healthReporter.updateTarget(.init(
                    targetIdentifier: target.identifier,
                    adapterIdentifier: envelope.adapterId,
                    state: state
                ), generation: session.revision)
                if acceptedResponse.error != nil { failedAdapters.append(envelope.adapterId) }
            } catch let error as PageRuntimeBridgeError {
                if case .staleRevision = error { throw error }
                failedAdapters.append(envelope.adapterId)
                responseEnvelopes.append(Self.failureEnvelope(for: envelope, reason: "bridge-operation-failed"))
                await healthReporter.updateTarget(.init(
                    targetIdentifier: target.identifier,
                    adapterIdentifier: envelope.adapterId,
                    state: .degraded(reason: "bridge-operation-failed")
                ), generation: session.revision)
            } catch {
                failedAdapters.append(envelope.adapterId)
                responseEnvelopes.append(Self.failureEnvelope(for: envelope, reason: "bridge-operation-failed"))
                await healthReporter.updateTarget(.init(
                    targetIdentifier: target.identifier,
                    adapterIdentifier: envelope.adapterId,
                    state: .degraded(reason: "bridge-operation-failed")
                ), generation: session.revision)
            }
        }
        try assertCurrent(session, targetIdentifier: target.identifier)
        return (responseEnvelopes, failedAdapters)
    }

    private func markHydrated(session: SessionState, targetIdentifier: String) async throws {
        let value = try await evaluateRequiringValue(
            "window.__codexAppExtensionV2.markHydrated()",
            session: session
        )
        try assertCurrent(session, targetIdentifier: targetIdentifier)
        guard value["runtimeVersion"] == .number(Double(FeatureRegistry.runtimeVersion)),
              value["implementationRevision"] == .number(Double(Self.implementationRevision)),
              value["hydrated"] == .bool(true) else {
            throw PageRuntimeBridgeError.invalidResponse("runtime-hydration")
        }
    }

    public func invalidate(targetIdentifier: String) async {
        let invalidatedRevision = sessions[targetIdentifier]?.revision ?? revisions[targetIdentifier, default: 0]
        revisions[targetIdentifier, default: 0] &+= 1
        let session = sessions.removeValue(forKey: targetIdentifier)
        if let session {
            await uninstallAllAdapters(session: session)
        }
        await healthReporter.removeTarget(identifier: targetIdentifier, generation: invalidatedRevision)
        if let session {
            _ = try? await client.request(
                method: "Target.detachFromTarget",
                params: .object(["sessionId": .string(session.identifier)]),
                sessionIdentifier: nil,
                timeout: .seconds(2)
            )
        }
    }

    public func pollPerformance(target: CDPTarget) async throws -> [AdapterPerformanceMeasurement] {
        let session = try await ensureSession(for: target)
        let expression = #"""
        (() => window.__codexAppExtensionV2.performanceSnapshot().observers.map((item) => ({
          adapterId: item.adapterId,
          strikeCount: item.strikeCount,
          durationMilliseconds: Math.ceil(item.lastDurationMilliseconds),
          degraded: item.degraded,
          qualified: item.qualified,
          recoverable: item.recoverable
        })))()
        """#
        let value = try await evaluateRequiringValue(expression, session: session)
        try assertCurrent(session, targetIdentifier: target.identifier)
        guard case let .array(items) = value else {
            throw PageRuntimeBridgeError.invalidResponse("performance-snapshot")
        }
        let measurements = items.compactMap(Self.decodePerformanceMeasurement)
        for measurement in measurements {
            let state: TargetAdapterState
            if measurement.isDegraded {
                state = .degraded(reason: DiagnosticErrorCode.adapterPerformanceBudgetExceeded.rawValue)
            } else if !measurement.isQualified {
                state = measurement.isRecoverable
                    ? .waiting(reason: "adapter-reconcile-waiting")
                    : .degraded(reason: "adapter-reconcile-unqualified")
            } else {
                state = .healthy
            }
            await healthReporter.updateTarget(.init(
                targetIdentifier: target.identifier,
                adapterIdentifier: measurement.adapterIdentifier.rawValue,
                state: state
            ), generation: session.revision)
        }
        try assertCurrent(session, targetIdentifier: target.identifier)
        return measurements
    }

    private func ensureSession(for target: CDPTarget) async throws -> SessionState {
        if let session = sessions[target.identifier] {
            await healthReporter.beginTarget(identifier: target.identifier, generation: session.revision)
            try assertCurrent(session, targetIdentifier: target.identifier)
            return session
        }
        revisions[target.identifier, default: 0] &+= 1
        let revision = revisions[target.identifier]!
        let result: JSONValue?
        do {
            result = try await client.request(
                method: "Target.attachToTarget",
                params: .object(["targetId": .string(target.identifier), "flatten": .bool(true)]),
                sessionIdentifier: nil,
                timeout: .seconds(5)
            )
        } catch {
            guard revisions[target.identifier] == revision else {
                throw PageRuntimeBridgeError.staleRevision(target.identifier)
            }
            throw error
        }
        let identifier = result?["sessionId"]?.stringValue
        guard revisions[target.identifier] == revision else {
            if let identifier {
                _ = try? await client.request(
                    method: "Target.detachFromTarget",
                    params: .object(["sessionId": .string(identifier)]),
                    sessionIdentifier: nil,
                    timeout: .seconds(2)
                )
            }
            throw PageRuntimeBridgeError.staleRevision(target.identifier)
        }
        guard let identifier else {
            throw PageRuntimeBridgeError.missingSession(target.identifier)
        }
        let session = SessionState(identifier: identifier, revision: revision, targetIdentifier: target.identifier)
        sessions[target.identifier] = session
        await healthReporter.beginTarget(identifier: target.identifier, generation: revision)
        try assertCurrent(session, targetIdentifier: target.identifier)
        return session
    }

    private func evaluateForSideEffect(
        _ expression: String,
        session: SessionState,
        timeout: Duration = .seconds(5)
    ) async throws {
        let remoteObject = try await evaluateRemoteObject(expression, session: session, timeout: timeout)
        guard remoteObject["value"] != nil || remoteObject["type"] == .string("undefined") else {
            throw PageRuntimeBridgeError.invalidResponse("Runtime.evaluate")
        }
    }

    private func evaluateRequiringValue(
        _ expression: String,
        session: SessionState,
        timeout: Duration = .seconds(5)
    ) async throws -> JSONValue {
        let remoteObject = try await evaluateRemoteObject(expression, session: session, timeout: timeout)
        guard let value = remoteObject["value"] else {
            throw PageRuntimeBridgeError.invalidResponse("Runtime.evaluate")
        }
        return value
    }

    private func evaluateRemoteObject(
        _ expression: String,
        session: SessionState,
        timeout: Duration
    ) async throws -> [String: JSONValue] {
        let result: JSONValue?
        do {
            result = try await client.request(
                method: "Runtime.evaluate",
                params: .object([
                    "expression": .string(expression),
                    "returnByValue": .bool(true),
                    "awaitPromise": .bool(false),
                    "includeCommandLineAPI": .bool(false)
                ]),
                sessionIdentifier: session.identifier,
                timeout: timeout
            )
        } catch {
            guard isCurrent(session) else {
                throw PageRuntimeBridgeError.staleRevision(session.targetIdentifier)
            }
            throw error
        }
        try assertCurrent(session, targetIdentifier: session.targetIdentifier)
        guard result?["exceptionDetails"] == nil,
              case let .object(remoteObject)? = result?["result"] else {
            throw PageRuntimeBridgeError.invalidResponse("Runtime.evaluate")
        }
        return remoteObject
    }

    private func assertCurrent(_ session: SessionState, targetIdentifier: String) throws {
        guard revisions[targetIdentifier] == session.revision,
              sessions[targetIdentifier] == session else {
            throw PageRuntimeBridgeError.staleRevision(targetIdentifier)
        }
    }

    private func isCurrent(_ session: SessionState) -> Bool {
        revisions[session.targetIdentifier] == session.revision
            && sessions[session.targetIdentifier] == session
    }

    private static func integer(_ value: JSONValue?) -> Int {
        guard case let .number(number)? = value else { return 0 }
        return Int(number)
    }

    private static func decodeEnvelope(_ value: JSONValue, context: String) throws -> PageRuntimeEnvelope {
        do {
            return try JSONDecoder().decode(PageRuntimeEnvelope.self, from: JSONEncoder().encode(value))
        } catch {
            throw PageRuntimeBridgeError.invalidResponse(context)
        }
    }

    private static func decodePerformanceMeasurement(_ value: JSONValue) -> AdapterPerformanceMeasurement? {
        guard case let .object(object) = value,
              let rawIdentifier = object["adapterId"]?.stringValue,
              let identifier = FeatureIdentifier(rawValue: rawIdentifier),
              case let .number(strikeCount)? = object["strikeCount"],
              case let .number(duration)? = object["durationMilliseconds"],
              case let .bool(isDegraded)? = object["degraded"],
              case let .bool(isQualified)? = object["qualified"] else { return nil }
        let isRecoverable = object["recoverable"] == .bool(true)
        return .init(
            adapterIdentifier: identifier,
            strikeCount: Int(strikeCount),
            durationMilliseconds: Int(duration),
            isDegraded: isDegraded,
            isQualified: isQualified,
            isRecoverable: isRecoverable
        )
    }

    private func uninstallAllAdapters(session: SessionState) async {
        for (index, identifier) in FeatureIdentifier.allCases.enumerated() {
            let envelope = PageRuntimeEnvelope(
                requestId: 10_000 + UInt64(index),
                adapterId: identifier.rawValue,
                operation: .uninstall,
                config: nil
            )
            guard let data = try? JSONEncoder().encode(envelope),
                  let json = String(data: data, encoding: .utf8) else { continue }
            _ = try? await evaluateRequiringValue(
                "window.__codexAppExtensionV2.execute(\(json))",
                session: session,
                timeout: .milliseconds(400)
            )
        }
    }

    private static func failureEnvelope(for envelope: PageRuntimeEnvelope, reason: String) -> PageRuntimeEnvelope {
        .init(
            requestId: envelope.requestId,
            adapterId: envelope.adapterId,
            operation: envelope.operation,
            config: envelope.config,
            error: .init(code: reason, message: reason)
        )
    }
}
