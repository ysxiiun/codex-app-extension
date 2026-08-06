import Foundation
import XCTest
@testable import ExtensionCore

final class RuntimeControllerTests: XCTestCase {
    func testConfigurationPreapplySuccessPersistsAndFailureRollsBack() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RuntimeControllerTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConfigStore(applicationSupportDirectory: root)
        try await store.save(.defaultConfiguration)
        let pipeline = RuntimePipelineDouble()
        await pipeline.setReady(true)
        let controller = makeController(store: store, pipeline: pipeline)

        var accepted = AppConfiguration.defaultConfiguration
        accepted.features.wideLayout.maximumContentWidth = 1_640
        try await controller.apply(configuration: accepted)
        let persistedAccepted = try await store.load()
        XCTAssertEqual(persistedAccepted, accepted)

        await pipeline.rejectWidth(1_777)
        var rejected = accepted
        rejected.features.wideLayout.maximumContentWidth = 1_777
        do {
            try await controller.apply(configuration: rejected)
            XCTFail("预应用失败不得持久化")
        } catch is RuntimeControllerError {}
        let persistedAfterRollback = try await store.load()
        XCTAssertEqual(persistedAfterRollback, accepted)
        let applied = await pipeline.appliedWidths()
        XCTAssertEqual(applied, [1_640, 1_777, 1_640])
        let selections = await pipeline.appliedSelections()
        XCTAssertEqual(selections.count, 3)
        XCTAssertEqual(selections[0], [.wideLayout])
        XCTAssertEqual(selections[1], [.wideLayout])
        XCTAssertEqual(selections[2], [.wideLayout])
    }

    func testConfigurationDiffAppliesOnlyAffectedAdaptersAndGlobalChangeAppliesAll() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RuntimeControllerAdapterSelection-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConfigStore(applicationSupportDirectory: root)
        try await store.save(.defaultConfiguration)
        let pipeline = RuntimePipelineDouble()
        await pipeline.setReady(true)
        let controller = makeController(store: store, pipeline: pipeline)

        var widthOnly = AppConfiguration.defaultConfiguration
        widthOnly.features.wideLayout.minimumSidePadding = 44
        try await controller.apply(configuration: widthOnly)

        var markdownOnly = widthOnly
        markdownOnly.features.markdownAppearance.heading.color = "#ABCDEF"
        try await controller.apply(configuration: markdownOnly)

        var global = markdownOnly
        global.global.isEnabled = false
        try await controller.apply(configuration: global)

        let selections = await pipeline.appliedSelections()
        XCTAssertEqual(selections.count, 3)
        XCTAssertEqual(selections[0], [.wideLayout])
        XCTAssertEqual(selections[1], [.markdownSemanticTheme])
        XCTAssertNil(selections[2])
    }

    func testWideLayoutUpdateIsNotBlockedByUnrelatedIMEAdapterFailure() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RuntimeControllerUnrelatedIME-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConfigStore(applicationSupportDirectory: root)
        try await store.save(.defaultConfiguration)
        let pipeline = RuntimePipelineDouble()
        await pipeline.setReady(true)
        await pipeline.rejectAdapters([.imeEnterGuard])
        let controller = makeController(store: store, pipeline: pipeline)

        var widthOnly = AppConfiguration.defaultConfiguration
        widthOnly.features.wideLayout.maximumContentWidth = 1_744
        try await controller.apply(configuration: widthOnly)

        let persisted = try await store.load()
        XCTAssertEqual(persisted, widthOnly)
        let selections = await pipeline.appliedSelections()
        XCTAssertEqual(selections.count, 1)
        XCTAssertEqual(selections[0], [.wideLayout])
    }

    func testValidationFailureNeverIssuesPagePreapplyOrRollback() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RuntimeControllerValidationRollback-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let pipeline = RuntimePipelineDouble()
        let controller = makeController(store: ConfigStore(applicationSupportDirectory: root), pipeline: pipeline)
        var invalid = AppConfiguration.defaultConfiguration
        invalid.features.wideLayout.maximumContentWidth = 100

        do {
            try await controller.apply(configuration: invalid)
            XCTFail("验证失败必须中止事务")
        } catch is RuntimeControllerError {}

        let applied = await pipeline.appliedWidths()
        XCTAssertTrue(applied.isEmpty)
    }

    func testLocalOnlyPersistenceFailureNeverIssuesPageRollback() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RuntimeControllerLocalSaveRollback-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConfigStore(applicationSupportDirectory: root)
        try await store.save(.defaultConfiguration)
        try makeCurrentConfigPathRejectWrites(store)
        let pipeline = RuntimePipelineDouble()
        await pipeline.setReady(true)
        let controller = makeController(store: store, pipeline: pipeline)
        var local = AppConfiguration.defaultConfiguration
        local.startup.openSettingsOnLaunch = true

        do {
            try await controller.apply(configuration: local)
            XCTFail("持久化失败必须暴露")
        } catch is RuntimeControllerError {}

        let applied = await pipeline.appliedWidths()
        XCTAssertTrue(applied.isEmpty)
    }

    func testPagePreapplySuccessThenPersistenceFailureRollsBackPage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RuntimeControllerPageSaveRollback-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConfigStore(applicationSupportDirectory: root)
        try await store.save(.defaultConfiguration)
        try makeCurrentConfigPathRejectWrites(store)
        let pipeline = RuntimePipelineDouble()
        await pipeline.setReady(true)
        let controller = makeController(store: store, pipeline: pipeline)
        var candidate = AppConfiguration.defaultConfiguration
        candidate.features.wideLayout.maximumContentWidth = 1_640

        do {
            try await controller.apply(configuration: candidate)
            XCTFail("持久化失败必须触发页面回滚")
        } catch is RuntimeControllerError {}

        let applied = await pipeline.appliedWidths()
        XCTAssertEqual(applied, [1_640, AppConfiguration.defaultConfiguration.features.wideLayout.maximumContentWidth])
    }

    func testExistingProcessPublishesRestartConfirmationWithoutAction() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RuntimeControllerRestart-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConfigStore(applicationSupportDirectory: root)
        let applications = RuntimeApplicationDouble(pid: 700)
        let lifecycle = AppLifecycleMonitor(inspector: applications)
        let process = RuntimeProcessDouble()
        let manager = DebugSessionManager(portAllocator: RuntimePortDouble(), processController: process)
        let health = HealthCenter()
        let controller = RuntimeController(
            store: store,
            migrator: LegacyConfigMigrator(legacyDirectory: root.appendingPathComponent("legacy")),
            applications: applications,
            lifecycle: lifecycle,
            sessionManager: manager,
            pipeline: RuntimePipelineDouble(),
            healthCenter: health,
            launchAtLoginController: RuntimeLoginDouble(),
            monitorPolicy: .disabled
        )

        await controller.start()
        let snapshotBeforeConfirmation = await controller.snapshot()
        XCTAssertTrue(snapshotBeforeConfirmation.pendingRestartConfirmation)
        let actionsBeforeConfirmation = await process.actions()
        XCTAssertTrue(actionsBeforeConfirmation.isEmpty)
        await controller.confirmRestart()
        let actionsAfterConfirmation = await process.actions()
        XCTAssertEqual(actionsAfterConfirmation, ["terminate:700", "launch"])
    }

    func testLocalOnlyConfigurationPersistsOfflineWithoutPageApply() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RuntimeControllerLocal-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConfigStore(applicationSupportDirectory: root)
        let pipeline = RuntimePipelineDouble()
        let controller = makeController(store: store, pipeline: pipeline)
        await controller.start()

        var local = (await controller.snapshot()).configuration
        local.startup.openSettingsOnLaunch = true
        local.diagnostics.logLevel = .debug
        local.diagnostics.retentionDays = 30
        try await controller.apply(configuration: local)

        let stored = try await store.load()
        let applyCount = await pipeline.applyCount()
        XCTAssertEqual(stored, local)
        XCTAssertEqual(applyCount, 0)
    }

    func testPageConfigurationPersistsOfflineAndInstallsWhenTargetLaterConnects() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RuntimeControllerOfflinePage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConfigStore(applicationSupportDirectory: root)
        let pipeline = RuntimePipelineDouble()
        let applications = RuntimeApplicationDouble(pid: nil)
        let controller = makeController(store: store, pipeline: pipeline, applications: applications)
        await controller.start()

        var offline = (await controller.snapshot()).configuration
        offline.global.isEnabled = false
        offline.features.wideLayout.maximumContentWidth = 1_888
        try await controller.apply(configuration: offline)

        let persistedOffline = try await store.load()
        let offlineApplyCount = await pipeline.applyCount()
        XCTAssertEqual(persistedOffline, offline)
        XCTAssertEqual(offlineApplyCount, 0)

        await applications.set(pid: 888, debugPort: 55_888)
        await controller.runMonitorCycle()

        let connectedWidths = await pipeline.connectedWidths()
        let connectedSnapshot = await controller.snapshot()
        XCTAssertEqual(connectedWidths, [1_888])
        XCTAssertEqual(connectedSnapshot.activeTargetIdentifier, "fixture-target")
    }

    func testLaunchAtLoginPersistsOfflineAndRequiresApprovalIsExplicit() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RuntimeControllerLogin-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConfigStore(applicationSupportDirectory: root)
        let pipeline = RuntimePipelineDouble()
        let login = RuntimeLoginDouble(setStatus: .requiresApproval)
        let applications = RuntimeApplicationDouble(pid: nil)
        let controller = makeController(store: store, pipeline: pipeline, applications: applications, login: login)
        await controller.start()

        await controller.setLaunchAtLogin(true)

        let snapshot = await controller.snapshot()
        XCTAssertTrue(snapshot.configuration.startup.launchAtLogin)
        XCTAssertEqual(snapshot.launchAtLogin, .requiresApproval)
        let stored = try await store.load()
        let applyCount = await pipeline.applyCount()
        XCTAssertEqual(stored.startup.launchAtLogin, true)
        XCTAssertEqual(applyCount, 0)
    }

    func testRepeatedRefreshDoesNotReconnectWhenSameProcessIsReady() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RuntimeControllerNoop-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let applications = RuntimeApplicationDouble(pid: 801, debugPort: 55_801)
        let pipeline = RuntimePipelineDouble()
        let controller = makeController(store: ConfigStore(applicationSupportDirectory: root), pipeline: pipeline, applications: applications)
        await controller.start()
        await controller.runMonitorCycle()

        let counts = await pipeline.counts()
        XCTAssertEqual(counts.connect, 1)
        XCTAssertEqual(counts.reconnect, 0)
    }

    func testProcessStopCleansPipelineAndPublishesGrayHealth() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RuntimeControllerStop-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let applications = RuntimeApplicationDouble(pid: 802, debugPort: 55_802)
        let pipeline = RuntimePipelineDouble()
        let controller = makeController(store: ConfigStore(applicationSupportDirectory: root), pipeline: pipeline, applications: applications)
        await controller.start()
        await applications.set(pid: nil, debugPort: nil)
        await controller.runMonitorCycle()

        let snapshot = await controller.snapshot()
        let counts = await pipeline.counts()
        XCTAssertEqual(counts.stop, 1)
        XCTAssertEqual(snapshot.runtime.process, .notRunning)
        XCTAssertEqual(snapshot.runtime.connection, .disconnected)
    }

    func testShutdownStopsPipelineAndClearsRuntimeState() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RuntimeControllerShutdown-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let applications = RuntimeApplicationDouble(pid: 812, debugPort: 55_812)
        let pipeline = RuntimePipelineDouble()
        let controller = makeController(store: ConfigStore(applicationSupportDirectory: root), pipeline: pipeline, applications: applications)
        await controller.start()

        await controller.shutdown()

        let counts = await pipeline.counts()
        let snapshot = await controller.snapshot()
        XCTAssertEqual(counts.stop, 1)
        let isReady = await pipeline.isReady()
        XCTAssertFalse(isReady)
        XCTAssertNil(snapshot.activeTargetIdentifier)
        XCTAssertEqual(snapshot.runtime.process, .notRunning)
        XCTAssertEqual(snapshot.runtime.connection, .disconnected)
    }

    func testReinjectUsesNonTransactionalInstallAndDoesNotPublishUpdateFailureAsGlobalError() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RuntimeControllerReconnect-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let applications = RuntimeApplicationDouble(pid: 803, debugPort: 55_803)
        let pipeline = RuntimePipelineDouble()
        let controller = makeController(store: ConfigStore(applicationSupportDirectory: root), pipeline: pipeline, applications: applications)
        await controller.start()
        await pipeline.setFailingOperation(.update)

        await controller.reinject()

        let reinjectedSnapshot = await controller.snapshot()
        let operations = await pipeline.appliedOperations()
        XCTAssertEqual(operations, [.install])
        XCTAssertNil(reinjectedSnapshot.lastError)

        await pipeline.setReady(false)
        await controller.runMonitorCycle()
        await controller.diagnose()

        let counts = await pipeline.counts()
        let recoveredSnapshot = await controller.snapshot()
        XCTAssertEqual(counts.reconnect, 1)
        XCTAssertNil(recoveredSnapshot.lastError)
    }

    func testDirtyDraftSurvivesHealthOnlySnapshotAndApplyCompletionSynchronizes() {
        let persisted = AppConfiguration.defaultConfiguration
        var dirty = persisted
        dirty.features.wideLayout.maximumContentWidth = 1_999

        XCTAssertEqual(
            ConfigurationDraftSync.resolve(draft: dirty, previousPersisted: persisted, nextPersisted: persisted, isApplying: false),
            dirty
        )
        var accepted = persisted
        accepted.features.wideLayout.maximumContentWidth = 1_640
        XCTAssertEqual(
            ConfigurationDraftSync.resolve(draft: dirty, previousPersisted: persisted, nextPersisted: accepted, isApplying: true),
            accepted
        )
    }

    func testStatusToneSeparatesDisabledPartialDegradationAndCoreErrors() {
        let activeRuntime = RuntimeSnapshot(
            process: .running(processIdentifier: 900),
            lifecycle: .active(processIdentifier: 900, targetCount: 1),
            connection: .connected(generation: 1, webSocketURL: URL(string: "ws://127.0.0.1:55900")!)
        )
        var disabledConfiguration = AppConfiguration.defaultConfiguration
        disabledConfiguration.global.isEnabled = false
        XCTAssertEqual(
            ExtensionStatusResolver.tone(for: .init(runtime: activeRuntime, configuration: disabledConfiguration)),
            .gray
        )

        let partialRuntime = RuntimeSnapshot(
            process: .running(processIdentifier: 900),
            lifecycle: .active(processIdentifier: 900, targetCount: 1),
            connection: .connected(generation: 1, webSocketURL: URL(string: "ws://127.0.0.1:55900")!),
            targets: [.init(targetIdentifier: "target", adapterIdentifier: "markdown", state: .degraded(reason: "fixture"))]
        )
        XCTAssertEqual(ExtensionStatusResolver.tone(for: .init(runtime: partialRuntime)), .yellow)

        let waitingRuntime = RuntimeSnapshot(
            process: .running(processIdentifier: 900),
            lifecycle: .active(processIdentifier: 900, targetCount: 1),
            connection: .connected(generation: 1, webSocketURL: URL(string: "ws://127.0.0.1:55900")!),
            targets: [.init(targetIdentifier: "target", adapterIdentifier: "markdown", state: .waiting(reason: "page-not-ready"))]
        )
        XCTAssertEqual(ExtensionStatusResolver.tone(for: .init(runtime: waitingRuntime)), .yellow)

        let degradedRuntime = RuntimeSnapshot(
            process: .running(processIdentifier: 900),
            lifecycle: .degraded(processIdentifier: 900, reason: "runtime"),
            connection: .disconnected
        )
        XCTAssertEqual(ExtensionStatusResolver.tone(for: .init(runtime: degradedRuntime)), .red)
        XCTAssertEqual(ExtensionStatusResolver.tone(for: .init(runtime: activeRuntime, lastError: "config")), .red)
    }

    private func makeController(
        store: ConfigStore,
        pipeline: RuntimePipelineDouble,
        applications: RuntimeApplicationDouble = RuntimeApplicationDouble(pid: nil),
        login: RuntimeLoginDouble = RuntimeLoginDouble()
    ) -> RuntimeController {
        return RuntimeController(
            store: store,
            migrator: LegacyConfigMigrator(legacyDirectory: store.paths.directory.appendingPathComponent("legacy")),
            applications: applications,
            lifecycle: AppLifecycleMonitor(inspector: applications),
            sessionManager: DebugSessionManager(portAllocator: RuntimePortDouble(), processController: RuntimeProcessDouble()),
            pipeline: pipeline,
            healthCenter: HealthCenter(),
            launchAtLoginController: login,
            monitorPolicy: .disabled
        )
    }

    private func makeCurrentConfigPathRejectWrites(_ store: ConfigStore) throws {
        try FileManager.default.removeItem(at: store.paths.current)
        try FileManager.default.createDirectory(at: store.paths.current, withIntermediateDirectories: false)
    }
}

private actor RuntimePipelineDouble: RuntimePipelining {
    private var widths: [Int] = []
    private var selections: [Set<FeatureIdentifier>?] = []
    private var connectWidths: [Int] = []
    private var rejected: Int?
    private var rejectedAdapters: Set<FeatureIdentifier> = []
    private var connectCalls = 0
    private var reconnectCalls = 0
    private var stopCalls = 0
    private var ready = false
    private var failingOperation: PageRuntimeOperation?
    private var operations: [PageRuntimeOperation] = []
    func rejectWidth(_ width: Int) { rejected = width }
    func rejectAdapters(_ identifiers: Set<FeatureIdentifier>) { rejectedAdapters = identifiers }
    func setReady(_ value: Bool) { ready = value }
    func setFailingOperation(_ operation: PageRuntimeOperation?) { failingOperation = operation }
    func connect(port: UInt16, configuration: AppConfiguration) {
        connectCalls += 1
        connectWidths.append(configuration.features.wideLayout.maximumContentWidth)
        ready = true
    }
    func apply(configuration: AppConfiguration, operation: PageRuntimeOperation) throws {
        try recordApply(configuration: configuration, operation: operation, selectedIDs: nil)
    }
    func apply(
        configuration: AppConfiguration,
        operation: PageRuntimeOperation,
        selectedIDs: Set<FeatureIdentifier>?
    ) throws {
        try recordApply(configuration: configuration, operation: operation, selectedIDs: selectedIDs)
    }
    private func recordApply(
        configuration: AppConfiguration,
        operation: PageRuntimeOperation,
        selectedIDs: Set<FeatureIdentifier>?
    ) throws {
        operations.append(operation)
        selections.append(selectedIDs)
        let width = configuration.features.wideLayout.maximumContentWidth
        widths.append(width)
        if operation == failingOperation { throw RuntimeControllerError.configurationRejected("fixture-apply") }
        if !rejectedAdapters.isEmpty,
           selectedIDs == nil || !rejectedAdapters.isDisjoint(with: selectedIDs ?? []) {
            throw RuntimeControllerError.configurationRejected("fixture-adapter")
        }
        if width == rejected { throw RuntimeControllerError.configurationRejected("fixture") }
    }
    func reconnect(configuration: AppConfiguration) { reconnectCalls += 1; ready = true }
    func stop() { stopCalls += 1; ready = false }
    func isReady() -> Bool { ready }
    func activeTargetIdentifier() -> String? { ready ? "fixture-target" : nil }
    func appliedWidths() -> [Int] { widths }
    func appliedSelections() -> [Set<FeatureIdentifier>?] { selections }
    func connectedWidths() -> [Int] { connectWidths }
    func appliedOperations() -> [PageRuntimeOperation] { operations }
    func applyCount() -> Int { widths.count }
    func counts() -> (connect: Int, reconnect: Int, stop: Int) { (connectCalls, reconnectCalls, stopCalls) }
}

private actor RuntimeApplicationDouble: ApplicationServicing {
    private var pid: Int32?
    private var debugPort: UInt16?
    init(pid: Int32?, debugPort: UInt16? = nil) { self.pid = pid; self.debugPort = debugPort }
    func set(pid: Int32?, debugPort: UInt16?) { self.pid = pid; self.debugPort = debugPort }
    func runningApplications() -> [RunningApplicationDescriptor] {
        guard let pid else { return [] }
        return [.init(processIdentifier: pid, bundleIdentifier: "com.openai.codex", executableURL: AppLifecycleMonitor.expectedExecutableURL, debugPort: debugPort)]
    }
    func terminate(processIdentifier: Int32) {}
    func launch(applicationURL: URL, arguments: [String]) -> Int32 { pid ?? 701 }
    func openOfficialSettings() {}
}

private actor RuntimeProcessDouble: DebugProcessControlling {
    private var recorded: [String] = []
    func terminate(processIdentifier: Int32) { recorded.append("terminate:\(processIdentifier)") }
    func launch(applicationURL: URL, arguments: [String]) -> Int32 { recorded.append("launch"); return 701 }
    func actions() -> [String] { recorded }
}

private actor RuntimePortDouble: LoopbackPortAllocating {
    func allocate() -> UInt16 { 55_700 }
}

private actor RuntimeLoginDouble: LaunchAtLoginControlling {
    private let setStatus: LaunchAtLoginStatus
    init(setStatus: LaunchAtLoginStatus = .enabled) { self.setStatus = setStatus }
    func status() -> LaunchAtLoginStatus { .notRegistered }
    func setEnabled(_ enabled: Bool) -> LaunchAtLoginStatus { enabled ? setStatus : .notRegistered }
}
