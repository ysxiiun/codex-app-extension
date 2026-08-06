import Foundation
import XCTest
@testable import ExtensionCore

final class DiagnosticPrivacyTests: XCTestCase {
    private let version = DiagnosticVersion(major: 2, minor: 1, patch: 0, build: 42)

    func testDiagnosticEventSchemaHasOnlyAllowlistedFields() throws {
        let event = DiagnosticEvent(
            timestamp: Date(timeIntervalSince1970: 1_234),
            appVersion: version,
            kind: .selectorProbe,
            state: .healthy,
            errorCode: .selectorMismatch,
            selectorCounts: .init(layoutRoot: 1, threadScroller: 1, composer: 1),
            count: 3,
            durationMilliseconds: 7
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as? [String: Any])

        XCTAssertEqual(Set(object.keys), [
            "timestamp", "runtimeVersion", "appVersion", "kind", "state", "errorCode",
            "selectorCounts", "count", "durationMilliseconds"
        ])
        XCTAssertFalse(object.keys.contains("payload"))
        XCTAssertFalse(object.keys.contains("message"))
        XCTAssertFalse(object.keys.contains("url"))
        XCTAssertFalse(object.keys.contains("targetIdentifier"))
    }

    func testActorStoreRotatesDeterministicallyUnderConcurrentAppends() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DiagnosticRotation-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DiagnosticLogStore(directory: root, maximumFileBytes: 700, maximumFileCount: 3)

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<40 {
                group.addTask { [version] in
                    _ = await store.append(.init(
                        timestamp: Date(timeIntervalSince1970: Double(index)),
                        appVersion: version,
                        kind: .adapterOperation,
                        state: .healthy,
                        count: index,
                        durationMilliseconds: index % 9
                    ))
                }
            }
        }

        let files = await store.fileURLsNewestFirst()
        XCTAssertEqual(files.count, 3)
        for file in files {
            let size = try XCTUnwrap((try FileManager.default.attributesOfItem(atPath: file.path)[.size]) as? NSNumber).intValue
            XCTAssertLessThanOrEqual(size, 700)
        }
        let events = await store.events()
        XCTAssertFalse(events.isEmpty)
        XCTAssertLessThan(events.count, 40)
        let retainedCounts = events.compactMap(\.count)
        XCTAssertEqual(Set(retainedCounts).count, retainedCounts.count)
        XCTAssertTrue(retainedCounts.allSatisfy { (0..<40).contains($0) })
    }

    func testDiskFailureDropsDiagnosticWithoutBreakingCaller() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DiagnosticFailure-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("not-a-directory".utf8).write(to: root)
        let store = DiagnosticLogStore(directory: root)

        let appended = await store.append(.init(appVersion: version, kind: .startup, state: .active))
        let events = await store.events()

        XCTAssertFalse(appended)
        XCTAssertTrue(events.isEmpty)
    }

    func testExporterReencodesTypedEventsAndExcludesEverySensitiveSource() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DiagnosticExport-\(UUID().uuidString)")
        let logs = root.appendingPathComponent("logs", isDirectory: true)
        let exports = root.appendingPathComponent("exports", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
        let store = DiagnosticLogStore(directory: logs, maximumFileBytes: 800, maximumFileCount: 2)
        _ = await store.append(.init(appVersion: version, kind: .connection, state: .degraded, errorCode: .cdpConnectionFailed))

        let sentinels = [
            "PRIVATE_CONVERSATION_TEXT", "UNSENT_INPUT_TEXT", "Cookie: secret=1",
            "<html>FULL_DOM</html>", "CDP_PAYLOAD_SECRET", "WEBSOCKET_CONTENT_SECRET"
        ]
        var configuration = AppConfiguration.defaultConfiguration
        configuration.appearance.accentColor = sentinels[0]
        configuration.features.markdownAppearance.strongText.color = sentinels[1]
        configuration.features.markdownAppearance.heading.color = sentinels[2]
        let migration = LegacyMigrationReport(
            status: .migrated,
            sourcePath: sentinels[3],
            destinationPath: sentinels[4],
            backupPath: sentinels[5],
            entries: [.init(field: sentinels[0], disposition: .unknown, detail: sentinels[1])]
        )
        let snapshot = RuntimeControllerSnapshot(
            runtime: .init(
                process: .running(processIdentifier: 7),
                lifecycle: .active(processIdentifier: 7, targetCount: 1),
                connection: .connected(generation: 3, webSocketURL: URL(string: "ws://127.0.0.1:5555/\(sentinels[5])")!),
                targets: [
                    .init(targetIdentifier: sentinels[4], adapterIdentifier: sentinels[3], state: .degraded(reason: sentinels[2])),
                    .init(targetIdentifier: sentinels[4], adapterIdentifier: "markdown-semantic-theme", state: .waiting(reason: sentinels[0]))
                ]
            ),
            configuration: configuration,
            migrationReport: migration,
            activeTargetIdentifier: sentinels[4],
            lastError: sentinels[0],
            isInitialized: true
        )

        let package = try await DiagnosticExporter().export(
            configuration: configuration,
            snapshot: snapshot,
            logStore: store,
            appVersion: version,
            timestamp: Date(timeIntervalSince1970: 1_000),
            to: exports
        )
        let files = try FileManager.default.contentsOfDirectory(at: package, includingPropertiesForKeys: nil).sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertEqual(files.map(\.lastPathComponent), [
            "configuration-summary.json", "diagnostic-events.json", "health-summary.json", "manifest.json"
        ])
        let exported = try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
        let stored = try await store.fileURLsNewestFirst().map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
        for sentinel in sentinels {
            XCTAssertFalse(exported.contains(sentinel), "导出包泄露了敏感来源: \(sentinel)")
            XCTAssertFalse(stored.contains(sentinel), "存储日志泄露了敏感来源: \(sentinel)")
        }
        XCTAssertFalse(exported.contains("lastError"))
        XCTAssertFalse(exported.contains("targetIdentifier"))
        XCTAssertFalse(exported.contains("webSocket"))
        XCTAssertFalse(exported.contains("accentColor"))
        let healthURL = package.appendingPathComponent("health-summary.json")
        let healthSummary = try JSONDecoder().decode(DiagnosticHealthSummary.self, from: Data(contentsOf: healthURL))
        XCTAssertEqual(healthSummary.waitingAdapterCount, 1)
        XCTAssertEqual(healthSummary.degradedAdapterCount, 1)
    }

    func testConfigurationSummaryCountsFourRuntimeFeatureToggles() {
        let defaults = DiagnosticConfigurationSummary(configuration: .defaultConfiguration)
        XCTAssertEqual(defaults.enabledFeatureCount, 4)

        var configuration = AppConfiguration.defaultConfiguration
        configuration.features.wideLayout.isEnabled = false
        configuration.features.headerAvoidance.isEnabled = false
        configuration.features.ime.protectCompositionEnter = false
        configuration.features.markdownAppearance.isEnabled = false
        XCTAssertEqual(DiagnosticConfigurationSummary(configuration: configuration).enabledFeatureCount, 0)
    }

    func testCorruptCurrentConfigurationRecoversLastKnownGoodWithoutOverwritingEvidence() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DiagnosticLKG-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConfigStore(applicationSupportDirectory: root)
        var baseline = AppConfiguration.defaultConfiguration
        baseline.features.wideLayout.maximumContentWidth = 1_704
        try await store.save(baseline)
        let corruptEvidence = Data("{\"conversation\":\"PRIVATE_CONVERSATION_TEXT\"".utf8)
        try corruptEvidence.write(to: store.paths.current, options: [.atomic])

        let recovered = try await store.load()
        let stillCorrupt = try Data(contentsOf: store.paths.current)
        let explicitlyRestored = try await store.restoreLastKnownGood()

        XCTAssertEqual(recovered, baseline)
        XCTAssertEqual(stillCorrupt, corruptEvidence)
        XCTAssertEqual(explicitlyRestored, baseline)
    }
}
