import Darwin
import Foundation

public protocol LoopbackPortAllocating: Sendable {
    func allocate() async throws -> UInt16
}

public protocol DebugProcessControlling: Sendable {
    func terminate(processIdentifier: Int32) async throws
    func launch(applicationURL: URL, arguments: [String]) async throws -> Int32
}

public enum DebugSessionPlan: Equatable, Sendable {
    case connect(processIdentifier: Int32, port: UInt16)
    case launch(port: UInt16, arguments: [String])
    case restartAfterConfirmation(processIdentifier: Int32, port: UInt16, arguments: [String])
}

public struct DebugSessionLaunchResult: Equatable, Sendable {
    public let processIdentifier: Int32
    public let port: UInt16

    public init(processIdentifier: Int32, port: UInt16) {
        self.processIdentifier = processIdentifier
        self.port = port
    }
}

public enum DebugSessionError: Error, Equatable, Sendable, LocalizedError {
    case restartConfirmationRequired(processIdentifier: Int32)
    case invalidApplication(processIdentifier: Int32)
    case noAvailableLoopbackPort
    case socketFailure(code: Int32)

    public var errorDescription: String? {
        switch self {
        case let .restartConfirmationRequired(processIdentifier):
            return "ChatGPT 进程 \(processIdentifier) 需要用户确认后才能重启"
        case let .invalidApplication(processIdentifier):
            return "拒绝为非 ChatGPT 主进程创建调试会话: \(processIdentifier)"
        case .noAvailableLoopbackPort:
            return "未找到可用的回环高位端口"
        case let .socketFailure(code):
            return "端口探测失败，errno=\(code)"
        }
    }
}

public actor DebugSessionManager {
    public static let chatGPTApplicationURL = URL(fileURLWithPath: "/Applications/ChatGPT.app")

    private let portAllocator: any LoopbackPortAllocating
    private let processController: any DebugProcessControlling

    public init(
        portAllocator: any LoopbackPortAllocating,
        processController: any DebugProcessControlling
    ) {
        self.portAllocator = portAllocator
        self.processController = processController
    }

    public func makePlan(for application: RunningApplicationDescriptor?) async throws -> DebugSessionPlan {
        if let application,
           AppLifecycleMonitor.matchMainApplication(in: [application]) == nil {
            throw DebugSessionError.invalidApplication(processIdentifier: application.processIdentifier)
        }
        if let application, let port = application.debugPort {
            return .connect(processIdentifier: application.processIdentifier, port: port)
        }

        let port = try await portAllocator.allocate()
        let arguments = Self.debugArguments(port: port)
        if let application {
            return .restartAfterConfirmation(
                processIdentifier: application.processIdentifier,
                port: port,
                arguments: arguments
            )
        }
        return .launch(port: port, arguments: arguments)
    }

    public func execute(
        _ plan: DebugSessionPlan,
        restartConfirmed: Bool = false
    ) async throws -> DebugSessionLaunchResult {
        switch plan {
        case let .connect(processIdentifier, port):
            return .init(processIdentifier: processIdentifier, port: port)
        case let .launch(port, arguments):
            let processIdentifier = try await processController.launch(
                applicationURL: Self.chatGPTApplicationURL,
                arguments: arguments
            )
            return .init(processIdentifier: processIdentifier, port: port)
        case let .restartAfterConfirmation(processIdentifier, port, arguments):
            guard restartConfirmed else {
                throw DebugSessionError.restartConfirmationRequired(processIdentifier: processIdentifier)
            }
            try await processController.terminate(processIdentifier: processIdentifier)
            let launchedProcessIdentifier = try await processController.launch(
                applicationURL: Self.chatGPTApplicationURL,
                arguments: arguments
            )
            return .init(processIdentifier: launchedProcessIdentifier, port: port)
        }
    }

    public static func debugArguments(port: UInt16) -> [String] {
        [
            "--remote-debugging-address=127.0.0.1",
            "--remote-debugging-port=\(port)"
        ]
    }
}

public actor SystemLoopbackPortAllocator: LoopbackPortAllocating {
    private let attempts: Int
    private var candidatePorts: [UInt16]
    private let availabilityProbe: @Sendable (UInt16) throws -> Bool

    public init(attempts: Int = 128) {
        self.attempts = attempts
        candidatePorts = []
        availabilityProbe = Self.systemIsAvailable
    }

    init(
        candidatePorts: [UInt16],
        availabilityProbe: @escaping @Sendable (UInt16) throws -> Bool
    ) {
        attempts = candidatePorts.count
        self.candidatePorts = candidatePorts
        self.availabilityProbe = availabilityProbe
    }

    public func allocate() throws -> UInt16 {
        for _ in 0..<attempts {
            let candidate = candidatePorts.isEmpty
                ? UInt16.random(in: 49_152...65_535)
                : candidatePorts.removeFirst()
            guard (49_152...65_535).contains(candidate) else { continue }
            if try availabilityProbe(candidate) {
                return candidate
            }
        }
        throw DebugSessionError.noAvailableLoopbackPort
    }

    private static func systemIsAvailable(_ port: UInt16) throws -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw DebugSessionError.socketFailure(code: errno)
        }
        defer { close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if result == 0 { return true }
        if errno == EADDRINUSE { return false }
        throw DebugSessionError.socketFailure(code: errno)
    }
}
