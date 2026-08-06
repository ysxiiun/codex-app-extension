import CoreFoundation
import Foundation

public struct LegacyMigrationReport: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case migrated
        case alreadyMigrated
        case noLegacyConfiguration
    }

    public enum Disposition: String, Codable, Sendable {
        case migrated
        case missingDefaultUsed
        case nativeReplacement
        case unknown
        case deprecated
        case invalid
    }

    public struct Entry: Codable, Equatable, Sendable {
        public let field: String
        public let disposition: Disposition
        public let detail: String

        public init(field: String, disposition: Disposition, detail: String) {
            self.field = field
            self.disposition = disposition
            self.detail = detail
        }
    }

    public let status: Status
    public let sourcePath: String
    public let destinationPath: String
    public let backupPath: String?
    public let entries: [Entry]

    public init(
        status: Status,
        sourcePath: String,
        destinationPath: String,
        backupPath: String?,
        entries: [Entry]
    ) {
        self.status = status
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.backupPath = backupPath
        self.entries = entries
    }
}

public enum LegacyMigrationError: Error, Equatable, Sendable, LocalizedError {
    case cannotRead(path: String, reason: String)
    case invalidRoot(path: String)
    case cannotBackup(path: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case let .cannotRead(path, reason): return "无法读取 V1 配置 \(path): \(reason)"
        case let .invalidRoot(path): return "V1 配置根节点必须是 JSON 对象: \(path)"
        case let .cannotBackup(path, reason): return "无法备份 V1 配置 \(path): \(reason)"
        }
    }
}

public struct LegacyConfigMigrator: Sendable {
    public let legacyConfiguration: URL
    public let legacyBackup: URL

    private static let activeTopLevelFields: Set<String> = [
        "wideLayoutEnhancement",
        "contentMaxWidth",
        "fullscreenHeaderOffset",
        "imeEnterGuard",
        "headingTextEnhancement",
        "headingTextEnhancementStyle",
        "strongTextEnhancement",
        "strongTextEnhancementStyle",
        "themeEnhancement",
        "themeEnhancementColors"
    ]
    private static let nativeReplacementFields: Set<String> = ["longTextSendEnhancement"]
    private static let deprecatedFields: Set<String> = [
        "cdpPort",
        "debugDOMSnapshots",
        "legacySelectorOverrides",
        "layoutFocusRingFix",
        "strongTextColorPreview"
    ]

    public init(legacyDirectory: URL? = nil) {
        let directory = legacyDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex-app-extension", isDirectory: true)
        legacyConfiguration = directory.appendingPathComponent("config.json")
        legacyBackup = directory.appendingPathComponent("config.v1.backup.json")
    }

    public func migrateIfNeeded(using store: ConfigStore) async throws -> LegacyMigrationReport {
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: store.paths.current.path) {
            let report = LegacyMigrationReport(
                status: .alreadyMigrated,
                sourcePath: legacyConfiguration.path,
                destinationPath: store.paths.current.path,
                backupPath: fileManager.fileExists(atPath: legacyBackup.path) ? legacyBackup.path : nil,
                entries: []
            )
            try await store.writeMigrationReport(report)
            return report
        }

        guard fileManager.fileExists(atPath: legacyConfiguration.path) else {
            let report = LegacyMigrationReport(
                status: .noLegacyConfiguration,
                sourcePath: legacyConfiguration.path,
                destinationPath: store.paths.current.path,
                backupPath: nil,
                entries: []
            )
            try await store.writeMigrationReport(report)
            return report
        }

        let legacyData: Data
        do {
            legacyData = try Data(contentsOf: legacyConfiguration)
        } catch {
            throw LegacyMigrationError.cannotRead(
                path: legacyConfiguration.path,
                reason: String(describing: error)
            )
        }

        let rawObject: Any
        do {
            rawObject = try JSONSerialization.jsonObject(with: legacyData)
        } catch {
            throw LegacyMigrationError.cannotRead(
                path: legacyConfiguration.path,
                reason: String(describing: error)
            )
        }
        guard let source = rawObject as? [String: Any] else {
            throw LegacyMigrationError.invalidRoot(path: legacyConfiguration.path)
        }

        var configuration = AppConfiguration.defaultConfiguration
        var entries: [LegacyMigrationReport.Entry] = []
        migrateKnownFields(from: source, into: &configuration, entries: &entries)

        let recognized = Self.activeTopLevelFields
            .union(Self.nativeReplacementFields)
            .union(Self.deprecatedFields)
        for field in source.keys.sorted() where !recognized.contains(field) {
            entries.append(.init(field: field, disposition: .unknown, detail: "未复制到 V2 运行时配置"))
        }
        for field in Self.nativeReplacementFields.sorted() where source[field] != nil {
            entries.append(.init(field: field, disposition: .nativeReplacement, detail: "V2 使用原生发送能力，不再注入长文本脚本"))
        }
        for field in Self.deprecatedFields.sorted() where source[field] != nil {
            entries.append(.init(field: field, disposition: .deprecated, detail: "字段已废弃，未复制到 V2"))
        }
        for field in Self.activeTopLevelFields.sorted() where source[field] == nil {
            entries.append(.init(field: field, disposition: .missingDefaultUsed, detail: "V1 未提供，使用 V2 默认值"))
        }

        do {
            if !fileManager.fileExists(atPath: legacyBackup.path) {
                try legacyData.write(to: legacyBackup, options: [.atomic])
            }
        } catch {
            throw LegacyMigrationError.cannotBackup(path: legacyBackup.path, reason: String(describing: error))
        }

        try await store.save(configuration)
        let report = LegacyMigrationReport(
            status: .migrated,
            sourcePath: legacyConfiguration.path,
            destinationPath: store.paths.current.path,
            backupPath: legacyBackup.path,
            entries: entries.sorted { ($0.field, $0.disposition.rawValue) < ($1.field, $1.disposition.rawValue) }
        )
        try await store.writeMigrationReport(report)
        return report
    }

    private func migrateKnownFields(
        from source: [String: Any],
        into configuration: inout AppConfiguration,
        entries: inout [LegacyMigrationReport.Entry]
    ) {
        migrateBool("wideLayoutEnhancement", from: source, entries: &entries) {
            configuration.features.wideLayout.isEnabled = $0
        }
        migratePixels("contentMaxWidth", range: 480...4_096, from: source, entries: &entries) {
            configuration.features.wideLayout.maximumContentWidth = $0
        }
        migratePixels("fullscreenHeaderOffset", range: 0...200, from: source, entries: &entries) {
            configuration.features.headerAvoidance.mode = .custom
            configuration.features.headerAvoidance.customOffset = $0
        }
        migrateBool("imeEnterGuard", from: source, entries: &entries) {
            configuration.features.ime.protectCompositionEnter = $0
        }
        migrateBool("headingTextEnhancement", from: source, entries: &entries) {
            configuration.features.markdownAppearance.heading.isEnabled = $0
        }
        migrateBool("strongTextEnhancement", from: source, entries: &entries) {
            configuration.features.markdownAppearance.strongText.isEnabled = $0
        }
        migrateBool("themeEnhancement", from: source, entries: &entries) {
            configuration.features.markdownAppearance.isEnabled = $0
        }

        migrateStyleColor(
            topLevelField: "headingTextEnhancementStyle",
            colorField: "color",
            from: source,
            entries: &entries
        ) { configuration.features.markdownAppearance.heading.color = $0 }

        if let raw = source["strongTextEnhancementStyle"] {
            guard let style = raw as? [String: Any] else {
                appendInvalid("strongTextEnhancementStyle", entries: &entries)
                return
            }
            var migratedAny = false
            if let color = style["color"] as? String, Self.isMigratableColor(color) {
                configuration.features.markdownAppearance.strongText.color = color
                migratedAny = true
            } else if style["color"] != nil {
                appendInvalid("strongTextEnhancementStyle.color", entries: &entries)
            }
            if let weight = Self.exactInteger(style["fontWeight"]), (100...900).contains(weight) {
                configuration.features.markdownAppearance.strongText.fontWeight = weight
                migratedAny = true
            } else if style["fontWeight"] != nil {
                appendInvalid("strongTextEnhancementStyle.fontWeight", entries: &entries)
            }
            if migratedAny {
                entries.append(.init(field: "strongTextEnhancementStyle", disposition: .migrated, detail: "映射到 Markdown 强调文本样式"))
            }
        }

        if let raw = source["themeEnhancementColors"] {
            guard let colors = raw as? [String: Any] else {
                appendInvalid("themeEnhancementColors", entries: &entries)
                return
            }
            let mappedFields = [
                "inlineCodeText",
                "inlineCodeBackground",
                "inlineCodeBorder",
                "blockquoteBorder",
                "blockquoteText",
                "blockquoteBackground"
            ]
            var migratedAny = false
            for field in mappedFields {
                guard let rawColor = colors[field] else { continue }
                if let color = rawColor as? String, Self.isMigratableColor(color) {
                    switch field {
                    case "inlineCodeText": configuration.features.markdownAppearance.inlineCode.textColor = color
                    case "inlineCodeBackground": configuration.features.markdownAppearance.inlineCode.backgroundColor = color
                    case "inlineCodeBorder": configuration.features.markdownAppearance.inlineCode.borderColor = color
                    case "blockquoteBorder": configuration.features.markdownAppearance.blockquote.borderColor = color
                    case "blockquoteText": configuration.features.markdownAppearance.blockquote.textColor = color
                    case "blockquoteBackground": configuration.features.markdownAppearance.blockquote.backgroundColor = color
                    default: break
                    }
                    migratedAny = true
                } else {
                    appendInvalid("themeEnhancementColors.\(field)", entries: &entries)
                }
            }
            for field in colors.keys where !Set(mappedFields).contains(field) {
                entries.append(.init(field: "themeEnhancementColors.\(field)", disposition: .unknown, detail: "未复制到 V2 运行时配置"))
            }
            if migratedAny {
                entries.append(.init(field: "themeEnhancementColors", disposition: .migrated, detail: "映射到 Markdown 语义外观"))
            }
        }
    }

    private func migrateBool(
        _ field: String,
        from source: [String: Any],
        entries: inout [LegacyMigrationReport.Entry],
        apply: (Bool) -> Void
    ) {
        guard let raw = source[field] else { return }
        guard let value = Self.exactBool(raw) else {
            appendInvalid(field, entries: &entries)
            return
        }
        apply(value)
        entries.append(.init(field: field, disposition: .migrated, detail: "已映射到 V2"))
    }

    private func migratePixels(
        _ field: String,
        range: ClosedRange<Int>,
        from source: [String: Any],
        entries: inout [LegacyMigrationReport.Entry],
        apply: (Int) -> Void
    ) {
        guard let raw = source[field] else { return }
        let value: Int?
        if let integer = Self.exactInteger(raw) {
            value = integer
        } else if let string = raw as? String,
                  let match = string.range(of: #"^[0-9]+px$"#, options: .regularExpression) {
            value = Int(string[match].dropLast(2))
        } else {
            value = nil
        }
        guard let value, range.contains(value) else {
            appendInvalid(field, entries: &entries)
            return
        }
        apply(value)
        entries.append(.init(field: field, disposition: .migrated, detail: "已移除 px 单位并映射到 V2"))
    }

    private func migrateStyleColor(
        topLevelField: String,
        colorField: String,
        from source: [String: Any],
        entries: inout [LegacyMigrationReport.Entry],
        apply: (String) -> Void
    ) {
        guard let raw = source[topLevelField] else { return }
        guard let style = raw as? [String: Any],
              let color = style[colorField] as? String,
              Self.isMigratableColor(color) else {
            appendInvalid(topLevelField, entries: &entries)
            return
        }
        apply(color)
        entries.append(.init(field: topLevelField, disposition: .migrated, detail: "已映射到 Markdown 语义外观"))
    }

    private func appendInvalid(_ field: String, entries: inout [LegacyMigrationReport.Entry]) {
        entries.append(.init(field: field, disposition: .invalid, detail: "类型或取值非法，使用 V2 默认值"))
    }

    private static func exactBool(_ value: Any) -> Bool? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    private static func exactInteger(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.rounded() == number.doubleValue else { return nil }
        return number.intValue
    }

    private static func isMigratableColor(_ value: String) -> Bool {
        AppConfiguration.isSupportedCSSColor(value)
    }
}
