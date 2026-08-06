import Foundation

public struct ConfigurationPaths: Equatable, Sendable {
    public let directory: URL
    public let current: URL
    public let lastKnownGood: URL
    public let migrationReport: URL

    public init(applicationSupportDirectory: URL) {
        directory = applicationSupportDirectory.appendingPathComponent("Codex App Extension", isDirectory: true)
        current = directory.appendingPathComponent("config.json")
        lastKnownGood = directory.appendingPathComponent("config.last-known-good.json")
        migrationReport = directory.appendingPathComponent("migration-report.json")
    }
}

public enum ConfigStoreError: Error, Equatable, Sendable, LocalizedError {
    case cannotCreateDirectory(path: String, reason: String)
    case cannotRead(path: String, reason: String)
    case cannotDecode(path: String, reason: String)
    case noUsableConfiguration(current: String, lastKnownGood: String?)
    case cannotPersist(path: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case let .cannotCreateDirectory(path, reason):
            return "无法创建配置目录 \(path): \(reason)"
        case let .cannotRead(path, reason):
            return "无法读取配置 \(path): \(reason)"
        case let .cannotDecode(path, reason):
            return "无法解析配置 \(path): \(reason)"
        case let .noUsableConfiguration(current, lastKnownGood):
            return "当前配置不可用: \(current); 最后可用配置: \(lastKnownGood ?? "不存在")"
        case let .cannotPersist(path, reason):
            return "无法原子写入配置 \(path): \(reason)"
        }
    }
}

public actor ConfigStore {
    public nonisolated let paths: ConfigurationPaths

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(applicationSupportDirectory: URL? = nil) {
        let root = applicationSupportDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        paths = ConfigurationPaths(applicationSupportDirectory: root)

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        decoder = JSONDecoder()
    }

    public func load() throws -> AppConfiguration {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: paths.current.path) else {
            return .defaultConfiguration
        }

        do {
            return try decodeValidatedConfiguration(at: paths.current)
        } catch {
            guard fileManager.fileExists(atPath: paths.lastKnownGood.path) else {
                throw ConfigStoreError.noUsableConfiguration(
                    current: String(describing: error),
                    lastKnownGood: nil
                )
            }
            do {
                return try decodeValidatedConfiguration(at: paths.lastKnownGood)
            } catch let fallbackError {
                throw ConfigStoreError.noUsableConfiguration(
                    current: String(describing: error),
                    lastKnownGood: String(describing: fallbackError)
                )
            }
        }
    }

    public func save(_ configuration: AppConfiguration) throws {
        let validConfiguration = try configuration.validated()
        try createDirectoryIfNeeded()

        let encoded: Data
        do {
            encoded = try encoder.encode(validConfiguration)
        } catch {
            throw ConfigStoreError.cannotPersist(path: paths.current.path, reason: String(describing: error))
        }

        let fileManager = FileManager.default
        var previousUsableData: Data?
        if fileManager.fileExists(atPath: paths.current.path),
           let existingData = try? Data(contentsOf: paths.current),
           (try? decoder.decode(AppConfiguration.self, from: existingData).validated()) != nil {
            previousUsableData = existingData
        }

        // 先保存旧的可用版本；即使新文件落盘失败，也不会破坏回退点。
        if let previousUsableData {
            try writeAtomically(previousUsableData, to: paths.lastKnownGood)
            try writeAtomically(encoded, to: paths.current)
        } else {
            // 首次保存先建立回退基线，避免 LKG 落盘失败却留下孤立的 current。
            try writeAtomically(encoded, to: paths.lastKnownGood)
            try writeAtomically(encoded, to: paths.current)
        }
    }

    public func restoreLastKnownGood() throws -> AppConfiguration {
        let configuration = try decodeValidatedConfiguration(at: paths.lastKnownGood)
        let data = try encoder.encode(configuration)
        try writeAtomically(data, to: paths.current)
        return configuration
    }

    public func writeMigrationReport(_ report: LegacyMigrationReport) throws {
        try createDirectoryIfNeeded()
        do {
            try writeAtomically(encoder.encode(report), to: paths.migrationReport)
        } catch let error as ConfigStoreError {
            throw error
        } catch {
            throw ConfigStoreError.cannotPersist(
                path: paths.migrationReport.path,
                reason: String(describing: error)
            )
        }
    }

    private func decodeValidatedConfiguration(at url: URL) throws -> AppConfiguration {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ConfigStoreError.cannotRead(path: url.path, reason: String(describing: error))
        }
        do {
            return try decoder.decode(AppConfiguration.self, from: data).validated()
        } catch {
            throw ConfigStoreError.cannotDecode(path: url.path, reason: String(describing: error))
        }
    }

    private func createDirectoryIfNeeded() throws {
        do {
            try FileManager.default.createDirectory(
                at: paths.directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw ConfigStoreError.cannotCreateDirectory(
                path: paths.directory.path,
                reason: String(describing: error)
            )
        }
    }

    private func writeAtomically(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            throw ConfigStoreError.cannotPersist(path: url.path, reason: String(describing: error))
        }
    }
}
