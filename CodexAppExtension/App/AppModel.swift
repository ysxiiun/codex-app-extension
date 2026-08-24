import AppKit
import ExtensionCore
import Foundation
import SwiftUI

extension ExtensionStatusTone {
    var symbol: String {
        switch self {
        case .green: return "checkmark.circle.fill"
        case .yellow: return "clock.badge.exclamationmark.fill"
        case .red: return "exclamationmark.triangle.fill"
        case .gray: return "circle.dashed"
        }
    }

    var color: Color {
        switch self {
        case .green: return .green
        case .yellow: return .yellow
        case .red: return .red
        case .gray: return .secondary
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot = RuntimeControllerSnapshot()
    @Published var draft = AppConfiguration.defaultConfiguration
    @Published var presentedError: String?
    @Published var selectedSettingsPage: SettingsPage = .general
    @Published private(set) var isApplying = false
    /// 仅在用户已确认的重启请求执行期间为 true；失败后必须释放以允许再次确认。
    @Published private(set) var isRestartConfirmationInFlight = false
    @Published private(set) var diagnosticActionMessage: String?
    @Published private(set) var settingsRequestID = 0

    private let runtime: any RuntimeControlling
    private let settingsOpener: () -> Void
    private let restartConfirmationPresenter = RestartConfirmationPresenter()
    private var updatesTask: Task<Void, Never>?
    private var handledStartupSettings = false
#if DEBUG
    private let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
    let exposesRestartUITestState = ProcessInfo.processInfo.arguments.contains("--ui-test-real-menu")
    var restartConfirmationCountForUITesting: Int {
        let prefix = "ui-restart-confirmations-"
        guard exposesRestartUITestState,
              let identifier = snapshot.activeTargetIdentifier,
              identifier.hasPrefix(prefix) else { return 0 }
        return Int(identifier.dropFirst(prefix.count)) ?? 0
    }
#endif

    init(runtime: any RuntimeControlling, settingsOpener: (() -> Void)? = nil) {
        self.runtime = runtime
        self.settingsOpener = settingsOpener ?? {}
#if DEBUG
        if exposesRestartUITestState { NSMenu.setMenuBarVisible(true) }
#endif
        updatesTask = Task {
            let updates = await runtime.updates()
            for await next in updates {
                if Task.isCancelled { return }
                let previousPersisted = snapshot.configuration
                let nextDraft = ConfigurationDraftSync.resolve(
                    draft: draft,
                    previousPersisted: previousPersisted,
                    nextPersisted: next.configuration,
                    isApplying: isApplying
                )
                snapshot = next
                draft = nextDraft
                presentedError = next.lastError
                if next.isInitialized, !handledStartupSettings {
                    handledStartupSettings = true
                    if next.configuration.startup.openSettingsOnLaunch { self.requestSettingsWindow() }
                }
            }
        }
        Task { await runtime.start() }
    }

    deinit { updatesTask?.cancel() }

    func shutdown() async {
        updatesTask?.cancel()
        updatesTask = nil
        await runtime.shutdown()
    }

    static func makeForCurrentProcess(settingsOpener: (() -> Void)? = nil) -> AppModel {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            return AppModel(
                runtime: UITestingRuntimeController(arguments: ProcessInfo.processInfo.arguments),
                settingsOpener: settingsOpener
            )
        }
#endif
        let health = HealthCenter()
        let services = SystemApplicationServices()
        let lifecycle = AppLifecycleMonitor(inspector: services)
        let sessionManager = DebugSessionManager(
            portAllocator: SystemLoopbackPortAllocator(),
            processController: services
        )
        let client = CDPClient(transport: URLSessionCDPTransport())
        let bridge = CDPPageRuntimeBridge(client: client, healthCenter: health, bundle: .main)
        let pipeline = CDPRuntimePipeline(client: client, bridge: bridge, healthCenter: health)
        let store = ConfigStore()
        let diagnosticStore = DiagnosticLogStore()
        let runtime = RuntimeController(
            store: store,
            migrator: LegacyConfigMigrator(),
            applications: services,
            lifecycle: lifecycle,
            sessionManager: sessionManager,
            pipeline: pipeline,
            healthCenter: health,
            launchAtLoginController: LaunchAtLoginController(),
            diagnosticLogStore: diagnosticStore,
            diagnosticAppVersion: .from(bundle: .main)
        )
        return AppModel(runtime: runtime, settingsOpener: settingsOpener)
    }

    var statusTone: ExtensionStatusTone { ExtensionStatusResolver.tone(for: snapshot) }

    var statusText: String {
        if isRestartConfirmationInFlight { return "正在重启 ChatGPT" }
        if snapshot.pendingRestartConfirmation { return "等待重启确认" }
        switch statusTone {
        case .green: return "运行正常"
        case .yellow:
            if snapshot.runtime.targets.contains(where: {
                if case .degraded = $0.state { return true }
                return false
            }) { return "增强降级" }
            if snapshot.runtime.targets.contains(where: {
                if case .waiting = $0.state { return true }
                return false
            }) { return "等待页面就绪" }
            return "正在连接"
        case .red: return "增强降级"
        case .gray:
            return snapshot.configuration.global.isEnabled ? "ChatGPT 未运行" : "扩展已停用"
        }
    }

    var isDraftDirty: Bool { draft != snapshot.configuration }

    func toggleGlobal(_ enabled: Bool) { transact { $0.global.isEnabled = enabled } }
    func toggleWideLayout(_ enabled: Bool) { transact { $0.features.wideLayout.isEnabled = enabled } }
    func toggleIME(_ enabled: Bool) { transact { $0.features.ime.protectCompositionEnter = enabled } }
    func toggleMarkdown(_ enabled: Bool) { transact { $0.features.markdownAppearance.isEnabled = enabled } }

    func resetWideLayoutDraft() { ConfigurationDraftMutations.resetWideLayout(in: &draft) }
    func resetHeaderAvoidanceDraft() { ConfigurationDraftMutations.resetHeaderAvoidance(in: &draft) }
    func resetMarkdownDraft() { ConfigurationDraftMutations.resetMarkdown(in: &draft) }
    func resetAppearanceDraft() { ConfigurationDraftMutations.resetAppearance(in: &draft) }
    func applyAppearancePreset(_ preset: AppearancePreset) {
        ConfigurationDraftMutations.applyAppearancePreset(preset, to: &draft)
    }

    func applyDraft() {
        guard !isApplying else { return }
        do { _ = try draft.validated() }
        catch {
            presentedError = error.localizedDescription
            draft = snapshot.configuration
            return
        }
        isApplying = true
        let candidate = draft
        Task {
            do {
                try await runtime.apply(configuration: candidate)
                presentedError = nil
                let persisted = await runtime.snapshot()
                snapshot = persisted
                draft = persisted.configuration
            }
            catch {
                presentedError = error.localizedDescription
                let persisted = await runtime.snapshot()
                snapshot = persisted
                draft = persisted.configuration
            }
            isApplying = false
        }
    }

    func discardDraft() { draft = snapshot.configuration; presentedError = nil }
    func restoreDefaults() { draft = .defaultConfiguration }
    func refresh() { Task { await runtime.refresh() } }
    func startChatGPT() { Task { await runtime.startChatGPT() } }
    func reconnect() { Task { await runtime.reconnect() } }
    func reinject() { Task { await runtime.reinject() } }
    func diagnose() { Task { await runtime.diagnose() } }
    func requestRestartConfirmation() {
        guard snapshot.pendingRestartConfirmation, !isRestartConfirmationInFlight else { return }
        guard restartConfirmationPresenter.requestConfirmation() else { return }
        isRestartConfirmationInFlight = true
        Task {
            defer { isRestartConfirmationInFlight = false }
            await runtime.confirmRestart()
            let latest = await runtime.snapshot()
            snapshot = latest
            presentedError = latest.lastError
        }
    }
    func setLaunchAtLogin(_ enabled: Bool) { Task { await runtime.setLaunchAtLogin(enabled) } }
    func openOfficialSettings() { Task { await runtime.openOfficialSettings() } }
    func requestSettingsWindow() {
        settingsRequestID &+= 1
        settingsOpener()
    }
    func copyDiagnosticsSummary() {
        Task {
            let summary = await runtime.diagnosticsTextSummary()
            writeDiagnosticsSummaryToPasteboard(summary)
            diagnosticActionMessage = "诊断摘要已复制"
            presentedError = nil
        }
    }
    func exportDiagnostics() {
        Task {
            do {
                let url = try await runtime.exportDiagnostics(to: FileManager.default.temporaryDirectory)
                diagnosticActionMessage = "诊断已导出：\(url.lastPathComponent)"
                presentedError = nil
                revealExportedDiagnostics(url)
            } catch {
                diagnosticActionMessage = nil
                presentedError = "导出诊断失败：\(error.localizedDescription)"
            }
        }
    }

    private func writeDiagnosticsSummaryToPasteboard(_ summary: String) {
#if DEBUG
        guard !isUITesting else { return }
#endif
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
    }

    private func revealExportedDiagnostics(_ url: URL) {
#if DEBUG
        guard !isUITesting else { return }
#endif
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func transact(_ mutation: @escaping (inout AppConfiguration) -> Void) {
        guard ConfigurationDraftMutations.canBeginQuickTransaction(isApplying: isApplying) else { return }
        var candidate = snapshot.configuration
        mutation(&candidate)
        isApplying = true
        Task {
            do {
                try await runtime.apply(configuration: candidate)
                presentedError = nil
            } catch {
                presentedError = error.localizedDescription
                let persisted = await runtime.snapshot()
                snapshot = persisted
                draft = persisted.configuration
            }
            isApplying = false
        }
    }
}

@MainActor
private final class RestartConfirmationPresenter {
    private var isPresenting = false

    func requestConfirmation() -> Bool {
        guard !isPresenting else { return false }
        isPresenting = true
        defer { isPresenting = false }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "重启 ChatGPT？"
        alert.informativeText = "重启可能丢失尚未发送的输入内容。只有确认后扩展才会终止并重新启动 ChatGPT。"

        let cancelButton = alert.addButton(withTitle: "取消")
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.setAccessibilityIdentifier("restart.cancel")

        let restartButton = alert.addButton(withTitle: "重启")
        restartButton.hasDestructiveAction = true
        restartButton.setAccessibilityIdentifier("restart.confirm")

        NSApplication.shared.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertSecondButtonReturn
    }
}

#if DEBUG
private actor UITestingRuntimeController: RuntimeControlling {
    private var current: RuntimeControllerSnapshot
    private var restartConfirmationCount = 0
    private let restartShouldFail: Bool
    private let restartShouldPause: Bool
    private var observers: [UUID: AsyncStream<RuntimeControllerSnapshot>.Continuation] = [:]

    init(arguments: [String]) {
        restartShouldFail = arguments.contains("--ui-restart-fails")
        restartShouldPause = arguments.contains("--ui-restart-pauses")
        let requested = arguments.first(where: { $0.hasPrefix("--ui-status=") })?.split(separator: "=").last.map(String.init) ?? "normal"
        let process: ChatGPTProcessHealth = requested == "offline" ? .notRunning : .running(processIdentifier: 4242)
        let lifecycle: AppLifecyclePhase
        let error: String?
        switch requested {
        case "waiting": lifecycle = .awaitingRestartConfirmation(processIdentifier: 4242); error = nil
        case "degraded", "adapter-failure", "page-waiting": lifecycle = .active(processIdentifier: 4242, targetCount: 1); error = nil
        case "corrupt": lifecycle = .degraded(processIdentifier: 4242, reason: "configuration-invalid"); error = "配置损坏，已使用最后可用配置"
        case "offline": lifecycle = .notRunning; error = nil
        default: lifecycle = .active(processIdentifier: 4242, targetCount: 1); error = nil
        }
        var configuration = AppConfiguration.defaultConfiguration
        configuration.startup.openSettingsOnLaunch = arguments.contains("--ui-open-settings-on-launch")
        current = .init(
            runtime: .init(
                process: process,
                lifecycle: lifecycle,
                connection: ["normal", "degraded", "adapter-failure", "build-change", "page-waiting"].contains(requested) ? .connected(generation: 1, webSocketURL: URL(string: "ws://127.0.0.1:55123")!) : .disconnected,
                targets: ["degraded", "adapter-failure"].contains(requested)
                    ? [.init(targetIdentifier: "ui-target", adapterIdentifier: "markdown", state: .degraded(reason: "ui-test"))]
                    : requested == "page-waiting"
                        ? [.init(targetIdentifier: "ui-target", adapterIdentifier: "markdown", state: .waiting(reason: "ui-test"))]
                        : []
            ),
            configuration: configuration,
            launchAtLogin: .notRegistered,
            pendingRestartConfirmation: requested == "waiting",
            activeTargetIdentifier: ["normal", "degraded", "adapter-failure", "build-change", "page-waiting"].contains(requested) ? "ui-target" : nil,
            lastError: error,
            isInitialized: true
        )
    }

    func snapshot() -> RuntimeControllerSnapshot { current }
    func updates() -> AsyncStream<RuntimeControllerSnapshot> {
        let id = UUID()
        return AsyncStream { continuation in
            observers[id] = continuation
            continuation.yield(current)
        }
    }
    func start() {}
    func refresh() {}
    func startChatGPT() {}
    func confirmRestart() async {
        restartConfirmationCount &+= 1
        if restartShouldPause { try? await Task.sleep(for: .seconds(3)) }
        current = restartShouldFail
            ? replacing(
                lifecycle: .awaitingRestartConfirmation(processIdentifier: 4242),
                pending: true,
                activeTargetIdentifier: "ui-restart-confirmations-\(restartConfirmationCount)"
            )
            : replacing(
                lifecycle: .active(processIdentifier: 4242, targetCount: 1),
                pending: false,
                activeTargetIdentifier: "ui-restart-confirmations-\(restartConfirmationCount)"
            )
        publish()
    }
    func reconnect() {
        current = RuntimeControllerSnapshot(
            runtime: .init(
                process: .running(processIdentifier: 4242),
                lifecycle: .active(processIdentifier: 4242, targetCount: 1),
                connection: .connected(generation: 2, webSocketURL: URL(string: "ws://127.0.0.1:55124")!),
                targets: current.runtime.targets
            ),
            configuration: current.configuration,
            launchAtLogin: current.launchAtLogin,
            activeTargetIdentifier: "ui-target-reloaded",
            isInitialized: true
        )
        publish()
    }
    func reinject() {}
    func diagnose() {
        current = RuntimeControllerSnapshot(
            runtime: .init(
                process: .running(processIdentifier: 4242),
                lifecycle: .active(processIdentifier: 4242, targetCount: 1),
                connection: .connected(generation: 2, webSocketURL: URL(string: "ws://127.0.0.1:55124")!),
                targets: [.init(targetIdentifier: "ui-target", adapterIdentifier: "markdown", state: .healthy)]
            ),
            configuration: current.configuration,
            launchAtLogin: current.launchAtLogin,
            activeTargetIdentifier: "ui-target",
            isInitialized: true
        )
        publish()
    }
    func apply(configuration: AppConfiguration) throws {
        if configuration.features.wideLayout.maximumContentWidth == 666 {
            throw RuntimeControllerError.configurationRejected("UI 测试预应用失败")
        }
        current = RuntimeControllerSnapshot(
            runtime: current.runtime,
            configuration: configuration,
            migrationReport: current.migrationReport,
            launchAtLogin: current.launchAtLogin,
            pendingRestartConfirmation: current.pendingRestartConfirmation,
            activeTargetIdentifier: current.activeTargetIdentifier,
            isInitialized: true
        )
        publish()
    }
    func setLaunchAtLogin(_ enabled: Bool) {
        var configuration = current.configuration
        configuration.startup.launchAtLogin = enabled
        current = RuntimeControllerSnapshot(
            runtime: current.runtime,
            configuration: configuration,
            launchAtLogin: enabled ? .enabled : .notRegistered,
            activeTargetIdentifier: current.activeTargetIdentifier,
            isInitialized: true
        )
        publish()
    }
    func openOfficialSettings() {}
    func diagnosticsTextSummary() -> String { "Codex App Extension diagnostics\nruntime_version=2\nstate=healthy" }
    func exportDiagnostics(to parentDirectory: URL) -> URL {
        parentDirectory.appendingPathComponent("Codex-App-Extension-Diagnostics-UI-Test", isDirectory: true)
    }

    private func replacing(
        lifecycle: AppLifecyclePhase,
        pending: Bool,
        activeTargetIdentifier: String? = nil
    ) -> RuntimeControllerSnapshot {
        .init(
            runtime: .init(
                process: .running(processIdentifier: 4242),
                lifecycle: lifecycle,
                connection: current.runtime.connection
            ),
            configuration: current.configuration,
            launchAtLogin: current.launchAtLogin,
            pendingRestartConfirmation: pending,
            activeTargetIdentifier: activeTargetIdentifier ?? current.activeTargetIdentifier,
            isInitialized: true
        )
    }
    private func publish() { for observer in observers.values { observer.yield(current) } }
}
#endif

enum SettingsPage: String, CaseIterable, Identifiable {
    case general = "通用"
    case layout = "布局"
    case input = "输入"
    case appearance = "外观"
    case diagnostics = "兼容与诊断"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .layout: return "rectangle.split.3x1"
        case .input: return "keyboard"
        case .appearance: return "paintbrush"
        case .diagnostics: return "stethoscope"
        }
    }
}
