import Foundation

public struct RunningApplicationDescriptor: Equatable, Sendable {
    public let processIdentifier: Int32
    public let bundleIdentifier: String?
    public let executableURL: URL?
    public let debugPort: UInt16?

    public init(
        processIdentifier: Int32,
        bundleIdentifier: String?,
        executableURL: URL?,
        debugPort: UInt16? = nil
    ) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.executableURL = executableURL
        self.debugPort = debugPort
    }
}

public protocol RunningApplicationInspecting: Sendable {
    func runningApplications() async -> [RunningApplicationDescriptor]
}

public enum AppLifecyclePhase: Equatable, Sendable {
    case notRunning
    case runningWithoutCDP(processIdentifier: Int32)
    case awaitingRestartConfirmation(processIdentifier: Int32)
    case launching(port: UInt16)
    case connecting(processIdentifier: Int32, port: UInt16)
    case probing(processIdentifier: Int32)
    case active(processIdentifier: Int32, targetCount: Int)
    case degraded(processIdentifier: Int32?, reason: String)
    case backingOff(attempt: Int, delay: Duration)
}

public struct LifecycleTransitionError: Error, Equatable, Sendable, LocalizedError {
    public let from: AppLifecyclePhase
    public let to: AppLifecyclePhase

    public init(from: AppLifecyclePhase, to: AppLifecyclePhase) {
        self.from = from
        self.to = to
    }

    public var errorDescription: String? {
        "非法生命周期迁移: \(String(describing: from)) -> \(String(describing: to))"
    }
}

public actor AppLifecycleMonitor {
    public static let expectedBundleIdentifier = "com.openai.codex"
    public static let expectedExecutableURL = URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT")

    private let inspector: any RunningApplicationInspecting
    private var phase: AppLifecyclePhase = .notRunning
    private var observers: [UUID: AsyncStream<AppLifecyclePhase>.Continuation] = [:]

    public init(inspector: any RunningApplicationInspecting) {
        self.inspector = inspector
    }

    public func currentPhase() -> AppLifecyclePhase {
        phase
    }

    public func updates() -> AsyncStream<AppLifecyclePhase> {
        let identifier = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(RuntimeStreamBufferLimits.latestState)) { continuation in
            observers[identifier] = continuation
            continuation.yield(phase)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeObserver(identifier) }
            }
        }
    }

    @discardableResult
    public func refreshProcess() async -> RunningApplicationDescriptor? {
        let applications = await inspector.runningApplications()
        guard let application = Self.matchMainApplication(in: applications) else {
            setObservedPhase(.notRunning)
            return nil
        }

        if let port = application.debugPort {
            setObservedPhase(.connecting(processIdentifier: application.processIdentifier, port: port))
        } else {
            setObservedPhase(.runningWithoutCDP(processIdentifier: application.processIdentifier))
        }
        return application
    }

    public func transition(to next: AppLifecyclePhase) throws {
        guard Self.isLegalTransition(from: phase, to: next) else {
            throw LifecycleTransitionError(from: phase, to: next)
        }
        publish(next)
    }

    public static func matchMainApplication(
        in applications: [RunningApplicationDescriptor]
    ) -> RunningApplicationDescriptor? {
        applications.first {
            $0.bundleIdentifier == expectedBundleIdentifier
                && $0.executableURL?.standardizedFileURL == expectedExecutableURL.standardizedFileURL
                && $0.processIdentifier > 0
        }
    }

    public static func isLegalTransition(from: AppLifecyclePhase, to: AppLifecyclePhase) -> Bool {
        if from == to { return true }
        if case .notRunning = to { return true }

        switch (from, to) {
        case (.notRunning, .launching),
             (.notRunning, .runningWithoutCDP),
             (.runningWithoutCDP, .awaitingRestartConfirmation),
             (.awaitingRestartConfirmation, .launching),
             (.awaitingRestartConfirmation, .runningWithoutCDP),
             (.launching, .connecting),
             (.launching, .degraded),
             (.connecting, .probing),
             (.connecting, .degraded),
             (.connecting, .backingOff),
             (.probing, .active),
             (.probing, .degraded),
             (.probing, .backingOff),
             (.active, .probing),
             (.active, .degraded),
             (.active, .backingOff),
             (.degraded, .connecting),
             (.degraded, .backingOff),
             (.backingOff, .connecting):
            return true
        default:
            return false
        }
    }

    private func setObservedPhase(_ next: AppLifecyclePhase) {
        // 系统进程事实优先于内部状态机，因此进程刷新可以直接收敛到观测状态。
        publish(next)
    }

    private func publish(_ next: AppLifecyclePhase) {
        phase = next
        for observer in observers.values {
            observer.yield(next)
        }
    }

    private func removeObserver(_ identifier: UUID) {
        observers.removeValue(forKey: identifier)
    }
}
