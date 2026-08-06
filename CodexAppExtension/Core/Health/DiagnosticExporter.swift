import Foundation

public struct DiagnosticConfigurationSummary: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let extensionEnabled: Bool
    public let enabledFeatureCount: Int
    public let launchAtLoginEnabled: Bool
    public let openSettingsOnLaunch: Bool
    public let diagnosticsLevel: AppConfiguration.Diagnostics.LogLevel
    public let retentionDayCount: Int

    public init(configuration: AppConfiguration) {
        schemaVersion = configuration.schemaVersion
        extensionEnabled = configuration.global.isEnabled
        enabledFeatureCount = [
            configuration.features.wideLayout.isEnabled,
            configuration.features.headerAvoidance.isEnabled,
            configuration.features.ime.protectCompositionEnter,
            configuration.features.markdownAppearance.isEnabled
        ].filter { $0 }.count
        launchAtLoginEnabled = configuration.startup.launchAtLogin
        openSettingsOnLaunch = configuration.startup.openSettingsOnLaunch
        diagnosticsLevel = configuration.diagnostics.logLevel
        retentionDayCount = configuration.diagnostics.retentionDays
    }
}

public struct DiagnosticHealthSummary: Codable, Equatable, Sendable {
    public let state: DiagnosticState
    public let processCount: Int
    public let connectedCount: Int
    public let targetCount: Int
    public let healthyAdapterCount: Int
    public let waitingAdapterCount: Int
    public let degradedAdapterCount: Int
    public let pendingConfirmationCount: Int
    public let migrationEntryCount: Int

    public init(snapshot: RuntimeControllerSnapshot) {
        switch snapshot.runtime.lifecycle {
        case .notRunning: state = .inactive
        case .runningWithoutCDP, .awaitingRestartConfirmation: state = .waitingForConfirmation
        case .launching, .connecting, .probing, .backingOff: state = .connecting
        case .active:
            if snapshot.runtime.targets.contains(where: Self.isDegraded) { state = .degraded }
            else if snapshot.runtime.targets.contains(where: Self.isWaiting) { state = .connecting }
            else { state = .active }
        case .degraded: state = .failed
        }
        if case .running = snapshot.runtime.process { processCount = 1 } else { processCount = 0 }
        if case .connected = snapshot.runtime.connection { connectedCount = 1 } else { connectedCount = 0 }
        targetCount = Set(snapshot.runtime.targets.map(\.targetIdentifier)).count
        healthyAdapterCount = snapshot.runtime.targets.filter {
            if case .healthy = $0.state { return true }
            return false
        }.count
        waitingAdapterCount = snapshot.runtime.targets.filter(Self.isWaiting).count
        degradedAdapterCount = snapshot.runtime.targets.filter(Self.isDegraded).count
        pendingConfirmationCount = snapshot.pendingRestartConfirmation ? 1 : 0
        migrationEntryCount = snapshot.migrationReport?.entries.count ?? 0
    }

    private static func isDegraded(_ target: TargetRuntimeHealth) -> Bool {
        if case .degraded = target.state { return true }
        return false
    }

    private static func isWaiting(_ target: TargetRuntimeHealth) -> Bool {
        if case .waiting = target.state { return true }
        return false
    }
}

public struct DiagnosticExportManifest: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let runtimeVersion: Int
    public let appVersion: DiagnosticVersion
    public let eventCount: Int
    public let fileCount: Int
}

public enum DiagnosticExportError: Error, Equatable, Sendable, LocalizedError {
    case destinationUnavailable
    case writeFailed

    public var errorDescription: String? {
        switch self {
        case .destinationUnavailable: return "无法创建诊断导出目录"
        case .writeFailed: return "无法写入诊断导出文件"
        }
    }
}

public struct DiagnosticExporter {
    private let fileManager: FileManager
    private let encoder: JSONEncoder

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    }

    public func export(
        configuration: AppConfiguration,
        snapshot: RuntimeControllerSnapshot,
        logStore: DiagnosticLogStore,
        appVersion: DiagnosticVersion,
        timestamp: Date = Date(),
        to parentDirectory: URL
    ) async throws -> URL {
        let events = await logStore.events()
        let package = parentDirectory.appendingPathComponent(packageName(timestamp: timestamp), isDirectory: true)
        do {
            try fileManager.createDirectory(at: package, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        } catch {
            throw DiagnosticExportError.destinationUnavailable
        }

        do {
            try write(DiagnosticConfigurationSummary(configuration: configuration), to: package.appendingPathComponent("configuration-summary.json"))
            try write(DiagnosticHealthSummary(snapshot: snapshot), to: package.appendingPathComponent("health-summary.json"))
            try write(events, to: package.appendingPathComponent("diagnostic-events.json"))
            try write(
                DiagnosticExportManifest(
                    timestamp: timestamp,
                    runtimeVersion: FeatureRegistry.runtimeVersion,
                    appVersion: appVersion,
                    eventCount: events.count,
                    fileCount: 4
                ),
                to: package.appendingPathComponent("manifest.json")
            )
        } catch {
            try? fileManager.removeItem(at: package)
            throw DiagnosticExportError.writeFailed
        }
        return package
    }

    public func textSummary(
        configuration: AppConfiguration,
        snapshot: RuntimeControllerSnapshot,
        appVersion: DiagnosticVersion
    ) -> String {
        let config = DiagnosticConfigurationSummary(configuration: configuration)
        let health = DiagnosticHealthSummary(snapshot: snapshot)
        return [
            "Codex App Extension diagnostics",
            "app_version=\(appVersion.major).\(appVersion.minor).\(appVersion.patch) build=\(appVersion.build)",
            "runtime_version=\(FeatureRegistry.runtimeVersion)",
            "state=\(health.state.rawValue)",
            "process_count=\(health.processCount) connected_count=\(health.connectedCount) target_count=\(health.targetCount)",
            "healthy_adapter_count=\(health.healthyAdapterCount) waiting_adapter_count=\(health.waitingAdapterCount) degraded_adapter_count=\(health.degradedAdapterCount)",
            "schema_version=\(config.schemaVersion) extension_enabled=\(config.extensionEnabled) enabled_feature_count=\(config.enabledFeatureCount)",
            "pending_confirmation_count=\(health.pendingConfirmationCount) migration_entry_count=\(health.migrationEntryCount)"
        ].joined(separator: "\n")
    }

    private func write<Value: Encodable>(_ value: Value, to url: URL) throws {
        try encoder.encode(value).write(to: url, options: [.atomic])
    }

    private func packageName(timestamp: Date) -> String {
        let milliseconds = Int(timestamp.timeIntervalSince1970 * 1_000)
        return "Codex-App-Extension-Diagnostics-\(milliseconds)"
    }
}
