import AppKit
import Foundation

public protocol ApplicationServicing: RunningApplicationInspecting, DebugProcessControlling {
    func openOfficialSettings() async throws
}

public enum SystemApplicationServiceError: Error, LocalizedError, Sendable {
    case processNotFound(Int32)
    case terminateTimedOut(Int32)
    case invalidLaunchResult
    case commandInspectionFailed(Int32)
    case officialSettingsUnavailable

    public var errorDescription: String? {
        switch self {
        case let .processNotFound(pid): return "未找到 ChatGPT 主进程 \(pid)"
        case let .terminateTimedOut(pid): return "等待 ChatGPT 进程 \(pid) 退出超时"
        case .invalidLaunchResult: return "ChatGPT 启动后未返回有效进程"
        case let .commandInspectionFailed(pid): return "无法读取 ChatGPT 进程 \(pid) 的启动参数"
        case .officialSettingsUnavailable: return "无法打开 Codex 官方设置"
        }
    }
}

public actor SystemApplicationServices: ApplicationServicing {
    private let terminationTimeout: Duration

    public init(terminationTimeout: Duration = .seconds(5)) {
        self.terminationTimeout = terminationTimeout
    }

    public func runningApplications() async -> [RunningApplicationDescriptor] {
        let candidates = await MainActor.run {
            NSWorkspace.shared.runningApplications.compactMap { application -> RunningApplicationDescriptor? in
                guard application.bundleIdentifier == AppLifecycleMonitor.expectedBundleIdentifier,
                      application.executableURL?.standardizedFileURL == AppLifecycleMonitor.expectedExecutableURL.standardizedFileURL,
                      application.processIdentifier > 0 else { return nil }
                return .init(
                    processIdentifier: application.processIdentifier,
                    bundleIdentifier: application.bundleIdentifier,
                    executableURL: application.executableURL
                )
            }
        }
        var inspected: [RunningApplicationDescriptor] = []
        for candidate in candidates {
            inspected.append(.init(
                processIdentifier: candidate.processIdentifier,
                bundleIdentifier: candidate.bundleIdentifier,
                executableURL: candidate.executableURL,
                debugPort: try? Self.debugPort(processIdentifier: candidate.processIdentifier)
            ))
        }
        return inspected
    }

    public func terminate(processIdentifier: Int32) async throws {
        let terminated = await MainActor.run { () -> Bool in
            guard let application = NSWorkspace.shared.runningApplications.first(where: {
                $0.processIdentifier == processIdentifier
                    && $0.bundleIdentifier == AppLifecycleMonitor.expectedBundleIdentifier
                    && $0.executableURL?.standardizedFileURL == AppLifecycleMonitor.expectedExecutableURL.standardizedFileURL
            }) else { return false }
            return application.terminate()
        }
        guard terminated else { throw SystemApplicationServiceError.processNotFound(processIdentifier) }
        let deadline = ContinuousClock.now.advanced(by: terminationTimeout)
        while ContinuousClock.now < deadline {
            let remains = await MainActor.run {
                NSWorkspace.shared.runningApplications.contains { $0.processIdentifier == processIdentifier }
            }
            if !remains { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw SystemApplicationServiceError.terminateTimedOut(processIdentifier)
    }

    public func launch(applicationURL: URL, arguments: [String]) async throws -> Int32 {
        try await Self.launchApplication(at: applicationURL, arguments: arguments)
    }

    public func openOfficialSettings() async throws {
        guard let url = URL(string: "codex://settings") else { return }
        let opened = await MainActor.run { NSWorkspace.shared.open(url) }
        guard opened else { throw SystemApplicationServiceError.officialSettingsUnavailable }
    }

    public static func parseDebugPort(command: String) -> UInt16? {
        let tokens = command.split(whereSeparator: \Character.isWhitespace).map(String.init)
        let addressPrefix = "--remote-debugging-address="
        let portPrefix = "--remote-debugging-port="
        let addresses = tokens.compactMap { token in
            token.hasPrefix(addressPrefix) ? String(token.dropFirst(addressPrefix.count)) : nil
        }
        let ports = tokens.compactMap { token in
            token.hasPrefix(portPrefix) ? String(token.dropFirst(portPrefix.count)) : nil
        }
        guard addresses == ["127.0.0.1"],
              ports.count == 1,
              let port = UInt16(ports[0]),
              port > 0 else { return nil }
        return port
    }

    private static func debugPort(processIdentifier: Int32) throws -> UInt16? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", String(processIdentifier), "-o", "command="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SystemApplicationServiceError.commandInspectionFailed(processIdentifier)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let command = String(data: data, encoding: .utf8) else {
            throw SystemApplicationServiceError.commandInspectionFailed(processIdentifier)
        }
        return parseDebugPort(command: command)
    }

    @MainActor
    private static func launchApplication(at applicationURL: URL, arguments: [String]) async throws -> Int32 {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = arguments
        configuration.activates = true
        return try await NSWorkspace.shared
            .openApplication(at: applicationURL, configuration: configuration)
            .processIdentifier
    }
}
