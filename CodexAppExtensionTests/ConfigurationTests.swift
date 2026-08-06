import Foundation
import XCTest
@testable import ExtensionCore

final class ConfigurationTests: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDownWithError() throws {
        for root in temporaryRoots {
            try? FileManager.default.removeItem(at: root)
        }
        temporaryRoots.removeAll()
        try super.tearDownWithError()
    }

    func testCodableRoundTripAndDefaults() throws {
        let configuration = AppConfiguration.defaultConfiguration
        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: data)

        XCTAssertEqual(decoded, configuration)
        XCTAssertEqual(decoded.schemaVersion, 2)
        XCTAssertTrue(decoded.features.wideLayout.isEnabled)
        XCTAssertEqual(decoded.features.headerAvoidance.mode, .automatic)
        XCTAssertTrue(decoded.features.ime.protectCompositionEnter)
        XCTAssertTrue(decoded.features.markdownAppearance.isEnabled)
        XCTAssertNoThrow(try decoded.validated())
    }

    func testValidationReportsEveryInvalidField() throws {
        var configuration = AppConfiguration.defaultConfiguration
        configuration.schemaVersion = 1
        configuration.features.wideLayout.maximumContentWidth = 100
        configuration.features.headerAvoidance.mode = .custom
        configuration.features.headerAvoidance.customOffset = 300
        configuration.features.markdownAppearance.heading.color = "javascript:alert(1)"
        configuration.diagnostics.retentionDays = 0

        XCTAssertThrowsError(try configuration.validated()) { error in
            guard let validation = error as? ConfigurationValidationError else {
                return XCTFail("错误类型不正确: \(error)")
            }
            let paths = Set(validation.failures.map(\.path))
            XCTAssertTrue(paths.contains("schemaVersion"))
            XCTAssertTrue(paths.contains("features.wideLayout.maximumContentWidth"))
            XCTAssertTrue(paths.contains("features.headerAvoidance.customOffset"))
            XCTAssertTrue(paths.contains("features.markdownAppearance.heading.color"))
            XCTAssertTrue(paths.contains("diagnostics.retentionDays"))
        }
    }

    func testAtomicPersistenceRejectsInvalidUpdateAndFallsBackToLastKnownGood() async throws {
        let root = try makeTemporaryRoot()
        let store = ConfigStore(applicationSupportDirectory: root)

        var first = AppConfiguration.defaultConfiguration
        first.features.wideLayout.maximumContentWidth = 1_200
        try await store.save(first)

        var second = first
        second.features.wideLayout.maximumContentWidth = 1_600
        try await store.save(second)

        var invalid = second
        invalid.features.wideLayout.maximumContentWidth = 10
        do {
            try await store.save(invalid)
            XCTFail("非法配置不应写入")
        } catch is ConfigurationValidationError {
            // 预期：验证失败发生在任何文件变更之前。
        }
        let unchanged = try await store.load()
        XCTAssertEqual(unchanged, second)

        try Data("{broken".utf8).write(to: store.paths.current, options: .atomic)
        let fallback = try await store.load()
        XCTAssertEqual(fallback, first)

        let restored = try await store.restoreLastKnownGood()
        XCTAssertEqual(restored, first)
        let loadedAfterRestore = try await store.load()
        XCTAssertEqual(loadedAfterRestore, first)
    }

    func testAtomicPersistenceDoesNotCommitCurrentWhenLastKnownGoodWriteFails() async throws {
        let root = try makeTemporaryRoot()
        let store = ConfigStore(applicationSupportDirectory: root)
        try FileManager.default.createDirectory(at: store.paths.directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: store.paths.lastKnownGood, withIntermediateDirectories: false)

        var first = AppConfiguration.defaultConfiguration
        first.features.wideLayout.maximumContentWidth = 1_234
        do {
            try await store.save(first)
            XCTFail("首次保存的 LKG 失败时不得提交 current")
        } catch is ConfigStoreError {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.paths.current.path))

        try FileManager.default.removeItem(at: store.paths.lastKnownGood)
        try await store.save(first)
        try FileManager.default.removeItem(at: store.paths.lastKnownGood)
        try FileManager.default.createDirectory(at: store.paths.lastKnownGood, withIntermediateDirectories: false)

        var second = first
        second.features.wideLayout.maximumContentWidth = 1_678
        do {
            try await store.save(second)
            XCTFail("更新保存的 LKG 失败时不得覆盖旧 current")
        } catch is ConfigStoreError {}
        let persistedAfterFailedUpdate = try await store.load()
        XCTAssertEqual(persistedAfterFailedUpdate, first)
    }

    func testMigratesV1AndCreatesBackupAndReportRepeatably() async throws {
        let root = try makeTemporaryRoot()
        let legacyDirectory = root.appendingPathComponent("legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)

        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "config-v1", withExtension: "json"))
        let sourceData = try Data(contentsOf: fixture)
        try sourceData.write(to: legacyDirectory.appendingPathComponent("config.json"))

        let store = ConfigStore(applicationSupportDirectory: root.appendingPathComponent("support"))
        let migrator = LegacyConfigMigrator(legacyDirectory: legacyDirectory)
        let report = try await migrator.migrateIfNeeded(using: store)

        XCTAssertEqual(report.status, .migrated)
        let migrated = try await store.load()
        XCTAssertEqual(migrated.features.wideLayout.maximumContentWidth, 1_800)
        XCTAssertEqual(migrated.features.headerAvoidance.mode, .custom)
        XCTAssertEqual(migrated.features.headerAvoidance.customOffset, 46)
        XCTAssertEqual(migrated.features.markdownAppearance.strongText.fontWeight, 800)
        XCTAssertTrue(report.entries.contains { $0.field == "layoutFocusRingFix" && $0.disposition == .deprecated })
        XCTAssertTrue(report.entries.contains { $0.field == "longTextSendEnhancement" && $0.disposition == .nativeReplacement })
        XCTAssertTrue(report.entries.contains { $0.field == "cdpPort" && $0.disposition == .deprecated })
        XCTAssertTrue(report.entries.contains { $0.field == "futureExperimentalFlag" && $0.disposition == .unknown })
        XCTAssertEqual(try Data(contentsOf: migrator.legacyBackup), sourceData)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.paths.migrationReport.path))

        let repeated = try await migrator.migrateIfNeeded(using: store)
        XCTAssertEqual(repeated.status, .alreadyMigrated)
        let loadedAfterRepeat = try await store.load()
        XCTAssertEqual(loadedAfterRepeat, migrated)
        XCTAssertEqual(try Data(contentsOf: migrator.legacyBackup), sourceData)
    }

    func testMissingAndInvalidV1FieldsUseDefaultsAndAreReported() async throws {
        let root = try makeTemporaryRoot()
        let legacyDirectory = root.appendingPathComponent("legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        let invalidV1: [String: Any] = [
            "wideLayoutEnhancement": "yes",
            "contentMaxWidth": "99999px",
            "themeEnhancementColors": ["inlineCodeText": "not-a-color"],
            "unknownNestedShape": ["value": true]
        ]
        try JSONSerialization.data(withJSONObject: invalidV1).write(
            to: legacyDirectory.appendingPathComponent("config.json")
        )

        let store = ConfigStore(applicationSupportDirectory: root.appendingPathComponent("support"))
        let report = try await LegacyConfigMigrator(legacyDirectory: legacyDirectory).migrateIfNeeded(using: store)
        let migrated = try await store.load()

        XCTAssertEqual(migrated.features.wideLayout.maximumContentWidth, AppConfiguration.defaultConfiguration.features.wideLayout.maximumContentWidth)
        XCTAssertEqual(migrated.features.wideLayout.isEnabled, AppConfiguration.defaultConfiguration.features.wideLayout.isEnabled)
        XCTAssertTrue(report.entries.contains { $0.field == "wideLayoutEnhancement" && $0.disposition == .invalid })
        XCTAssertTrue(report.entries.contains { $0.field == "contentMaxWidth" && $0.disposition == .invalid })
        XCTAssertTrue(report.entries.contains { $0.field == "themeEnhancementColors.inlineCodeText" && $0.disposition == .invalid })
        XCTAssertTrue(report.entries.contains { $0.field == "imeEnterGuard" && $0.disposition == .missingDefaultUsed })
    }

    func testAppearancePresetsAndGroupResetsMutateOnlyDraftConfiguration() throws {
        var configuration = AppConfiguration.defaultConfiguration
        configuration.startup.openSettingsOnLaunch = true

        ConfigurationDraftMutations.applyAppearancePreset(.highContrast, to: &configuration)
        XCTAssertEqual(ConfigurationDraftMutations.appearancePreset(matching: configuration), .highContrast)
        XCTAssertEqual(configuration.features.markdownAppearance.strongText.fontWeight, 900)
        XCTAssertEqual(configuration.features.markdownAppearance.blockquote.textColor, "#FFFFFF")
        XCTAssertTrue(configuration.startup.openSettingsOnLaunch)
        XCTAssertNoThrow(try configuration.validated())

        configuration.features.markdownAppearance.heading.color = "#123456"
        XCTAssertEqual(ConfigurationDraftMutations.appearancePreset(matching: configuration), .custom)
        ConfigurationDraftMutations.resetMarkdown(in: &configuration)
        XCTAssertEqual(configuration.features.markdownAppearance, AppConfiguration.defaultConfiguration.features.markdownAppearance)
        ConfigurationDraftMutations.applyAppearancePreset(.highContrast, to: &configuration)
        XCTAssertEqual(configuration.features.markdownAppearance.strongText.fontWeight, 900)

        ConfigurationDraftMutations.resetAppearance(in: &configuration)
        XCTAssertEqual(ConfigurationDraftMutations.appearancePreset(matching: configuration), .defaultStyle)
        XCTAssertTrue(configuration.startup.openSettingsOnLaunch)
    }

    func testLegacySchemaTwoFocusRingKeyIsIgnoredAndNotReencoded() throws {
        let encoded = try JSONEncoder().encode(AppConfiguration.defaultConfiguration)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var features = try XCTUnwrap(object["features"] as? [String: Any])
        features["focusRing"] = ["isEnabled": true, "color": "#FF00FF"]
        object["features"] = features

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: legacyData)
        XCTAssertNoThrow(try decoded.validated())

        let reencoded = try JSONEncoder().encode(decoded)
        let reencodedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: reencoded) as? [String: Any])
        let reencodedFeatures = try XCTUnwrap(reencodedObject["features"] as? [String: Any])
        XCTAssertNil(reencodedFeatures["focusRing"])
    }

    func testCSSColorValidationRejectsOutOfRangeFunctionalColors() throws {
        var configuration = AppConfiguration.defaultConfiguration
        for invalid in ["rgb(256, 0, 0)", "rgb(1, 2, 3, 4)", "rgba(1, 2, 3, 1.2)"] {
            configuration.features.markdownAppearance.heading.color = invalid
            XCTAssertThrowsError(try configuration.validated(), invalid)
        }
        for valid in ["rgb(0, 128, 255)", "rgba(223, 48, 121, 0.10)", "inherit", "currentColor"] {
            configuration.features.markdownAppearance.heading.color = valid
            XCTAssertNoThrow(try configuration.validated(), valid)
        }
    }

    func testClassicMarkdownPaletteMatchesLegacyAuthorConfigurationExactly() throws {
        let markdown = AppConfiguration.defaultConfiguration.features.markdownAppearance

        XCTAssertTrue(markdown.isEnabled)
        XCTAssertEqual(markdown.heading, .init(isEnabled: true, color: "#F2C94C"))
        XCTAssertEqual(markdown.strongText, .init(isEnabled: true, color: "#F2C94C", fontWeight: 800))
        XCTAssertEqual(markdown.inlineCode, .init(
            textColor: "#df3079",
            backgroundColor: "rgba(223, 48, 121, 0.10)",
            borderColor: "rgba(223, 48, 121, 0.18)"
        ))
        XCTAssertEqual(markdown.blockquote, .init(
            borderColor: "#df3079",
            textColor: "inherit",
            backgroundColor: "rgba(223, 48, 121, 0.06)"
        ))
        XCTAssertNoThrow(try AppConfiguration.defaultConfiguration.validated())
    }

    func testMarkdownResetChangesOnlyMarkdownPartitionAndPresetMatching() throws {
        var configuration = AppConfiguration.defaultConfiguration
        configuration.startup.openSettingsOnLaunch = true
        configuration.features.wideLayout.maximumContentWidth = 1_234
        configuration.appearance.accentColor = "#123456"
        configuration.features.markdownAppearance.inlineCode.textColor = "#ABCDEF"
        configuration.features.markdownAppearance.blockquote.backgroundColor = "rgba(1, 2, 3, 0.40)"

        let encoded = try JSONEncoder().encode(configuration)
        var decoded = try JSONDecoder().decode(AppConfiguration.self, from: encoded)
        XCTAssertEqual(decoded.features.markdownAppearance.inlineCode.textColor, "#ABCDEF")
        XCTAssertEqual(decoded.features.markdownAppearance.blockquote.backgroundColor, "rgba(1, 2, 3, 0.40)")
        XCTAssertEqual(ConfigurationDraftMutations.appearancePreset(matching: decoded), .custom)

        ConfigurationDraftMutations.resetMarkdown(in: &decoded)
        XCTAssertEqual(decoded.features.markdownAppearance, AppConfiguration.defaultConfiguration.features.markdownAppearance)
        XCTAssertEqual(decoded.features.wideLayout.maximumContentWidth, 1_234)
        XCTAssertTrue(decoded.startup.openSettingsOnLaunch)
        XCTAssertEqual(decoded.appearance.accentColor, "#123456")
        XCTAssertEqual(ConfigurationDraftMutations.appearancePreset(matching: decoded), .defaultStyle)
    }

    func testLayoutSectionResetsAndQuickTransactionGuard() {
        var configuration = AppConfiguration.defaultConfiguration
        configuration.features.wideLayout.maximumContentWidth = 2_400
        configuration.features.headerAvoidance.mode = .custom
        configuration.features.headerAvoidance.customOffset = 120

        ConfigurationDraftMutations.resetWideLayout(in: &configuration)
        XCTAssertEqual(configuration.features.wideLayout, AppConfiguration.defaultConfiguration.features.wideLayout)
        XCTAssertEqual(configuration.features.headerAvoidance.customOffset, 120)
        ConfigurationDraftMutations.resetHeaderAvoidance(in: &configuration)
        XCTAssertEqual(configuration.features.headerAvoidance, AppConfiguration.defaultConfiguration.features.headerAvoidance)
        XCTAssertTrue(ConfigurationDraftMutations.canBeginQuickTransaction(isApplying: false))
        XCTAssertFalse(ConfigurationDraftMutations.canBeginQuickTransaction(isApplying: true))
    }

    private func makeTemporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexAppExtensionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        temporaryRoots.append(root)
        return root
    }
}
