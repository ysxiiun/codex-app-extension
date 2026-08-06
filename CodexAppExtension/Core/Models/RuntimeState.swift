import Foundation

public enum RuntimeHealth: String, Codable, Sendable {
    case inactive
    case ready
    case degraded
    case failed
}

public struct RuntimeState: Codable, Equatable, Sendable {
    public var health: RuntimeHealth
    public var isExtensionEnabled: Bool
    public var activeFeatureCount: Int
    public var lastConfigurationLoad: Date?
    public var lastErrorDescription: String?

    public init(
        health: RuntimeHealth = .inactive,
        isExtensionEnabled: Bool = true,
        activeFeatureCount: Int = 0,
        lastConfigurationLoad: Date? = nil,
        lastErrorDescription: String? = nil
    ) {
        self.health = health
        self.isExtensionEnabled = isExtensionEnabled
        self.activeFeatureCount = activeFeatureCount
        self.lastConfigurationLoad = lastConfigurationLoad
        self.lastErrorDescription = lastErrorDescription
    }
}
