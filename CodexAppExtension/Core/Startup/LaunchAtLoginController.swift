import Foundation
import ServiceManagement

public enum LaunchAtLoginStatus: String, Equatable, Sendable {
    case enabled
    case notRegistered
    case requiresApproval
    case unavailable
    case error
}

public protocol LaunchAtLoginControlling: Sendable {
    func status() async -> LaunchAtLoginStatus
    func setEnabled(_ enabled: Bool) async throws -> LaunchAtLoginStatus
}

public actor LaunchAtLoginController: LaunchAtLoginControlling {
    public init() {}

    public func status() -> LaunchAtLoginStatus {
        guard #available(macOS 13.0, *) else { return .unavailable }
        return Self.map(SMAppService.mainApp.status)
    }

    public func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus {
        guard #available(macOS 13.0, *) else { return .unavailable }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            return Self.map(SMAppService.mainApp.status)
        } catch {
            return .error
        }
    }

    @available(macOS 13.0, *)
    private static func map(_ status: SMAppService.Status) -> LaunchAtLoginStatus {
        switch status {
        case .enabled: return .enabled
        case .notRegistered: return .notRegistered
        case .requiresApproval: return .requiresApproval
        case .notFound: return .unavailable
        @unknown default: return .error
        }
    }
}
