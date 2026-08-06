import Foundation

public enum RuntimeStreamBufferLimits {
    public static let latestState = 1
    public static let lossSensitiveEvents = 64
}

public struct DiagnosticVersion: Codable, Equatable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let build: Int

    public init(major: Int, minor: Int, patch: Int, build: Int = 0) {
        self.major = max(0, major)
        self.minor = max(0, minor)
        self.patch = max(0, patch)
        self.build = max(0, build)
    }

    public static func from(bundle: Bundle) -> DiagnosticVersion {
        let components = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")
            .split(separator: ".")
            .compactMap { Int($0) }
        let build = Int(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
        return .init(
            major: components.indices.contains(0) ? components[0] : 0,
            minor: components.indices.contains(1) ? components[1] : 0,
            patch: components.indices.contains(2) ? components[2] : 0,
            build: build
        )
    }
}

public enum DiagnosticEventKind: String, Codable, CaseIterable, Sendable {
    case startup
    case lifecycle
    case connection
    case selectorProbe
    case adapterOperation
    case performanceBudget
    case configurationRecovery
    case export
}

public enum DiagnosticState: String, Codable, CaseIterable, Sendable {
    case inactive
    case waitingForConfirmation
    case connecting
    case active
    case healthy
    case degraded
    case recovered
    case failed
}

public enum DiagnosticErrorCode: String, Codable, CaseIterable, Sendable {
    case applicationNotRunning
    case cdpUnavailable
    case cdpConnectionFailed
    case noQualifiedTarget
    case selectorMismatch
    case adapterOperationFailed
    case adapterPerformanceBudgetExceeded
    case configurationInvalid
    case lastKnownGoodUnavailable
    case persistenceFailed
    case diagnosticStorageUnavailable
    case diagnosticExportFailed
}

public struct DiagnosticSelectorCounts: Codable, Equatable, Sendable {
    public let layoutRoot: Int
    public let threadScroller: Int
    public let composer: Int

    public init(layoutRoot: Int, threadScroller: Int, composer: Int) {
        self.layoutRoot = max(0, layoutRoot)
        self.threadScroller = max(0, threadScroller)
        self.composer = max(0, composer)
    }
}

/// Privacy-safe by construction: every stored property is a fixed enum, a number, or a timestamp.
/// Conversation text, input, cookies, DOM, CDP payloads, URLs, target IDs, and arbitrary strings
/// have no representable field in this type.
public struct DiagnosticEvent: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let runtimeVersion: Int
    public let appVersion: DiagnosticVersion
    public let kind: DiagnosticEventKind
    public let state: DiagnosticState
    public let errorCode: DiagnosticErrorCode?
    public let selectorCounts: DiagnosticSelectorCounts?
    public let count: Int?
    public let durationMilliseconds: Int?

    public init(
        timestamp: Date = Date(),
        runtimeVersion: Int = 2,
        appVersion: DiagnosticVersion,
        kind: DiagnosticEventKind,
        state: DiagnosticState,
        errorCode: DiagnosticErrorCode? = nil,
        selectorCounts: DiagnosticSelectorCounts? = nil,
        count: Int? = nil,
        durationMilliseconds: Int? = nil
    ) {
        self.timestamp = timestamp
        self.runtimeVersion = max(0, runtimeVersion)
        self.appVersion = appVersion
        self.kind = kind
        self.state = state
        self.errorCode = errorCode
        self.selectorCounts = selectorCounts
        self.count = count.map { max(0, $0) }
        self.durationMilliseconds = durationMilliseconds.map { max(0, $0) }
    }
}
