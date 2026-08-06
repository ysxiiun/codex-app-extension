import AppKit
import SwiftUI

@main
struct CodexAppExtensionApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var applicationDelegate
    @StateObject private var model: AppModel
    private let settingsWindowCoordinator: SettingsWindowCoordinator

    init() {
        let settingsWindowCoordinator = SettingsWindowCoordinator()
        let model = AppModel.makeForCurrentProcess { [weak settingsWindowCoordinator] in
            settingsWindowCoordinator?.show()
        }
        settingsWindowCoordinator.model = model
        self.settingsWindowCoordinator = settingsWindowCoordinator
        _model = StateObject(wrappedValue: model)
        applicationDelegate.configure(model: model)
    }

    var body: some Scene {
        MenuBarExtra {
            StatusMenuView(model: model)
        } label: {
            Label(model.statusText, systemImage: model.statusTone.symbol)
                .accessibilityIdentifier("menuBar.status")
                .accessibilityLabel("Codex App Extension：\(model.statusText)")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
private final class SettingsWindowCoordinator {
    weak var model: AppModel? {
        didSet {
            guard model != nil, pendingShow else { return }
            pendingShow = false
            show()
        }
    }
    private var window: NSWindow?
    private var pendingShow = false

    func show() {
        guard let model else {
            pendingShow = true
            return
        }
        let settingsWindow: NSWindow
        if let window {
            settingsWindow = window
        } else {
            let controller = NSHostingController(rootView: SettingsRootView(model: model).tint(.accentColor))
            let created = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            created.title = "Codex App Extension 设置"
            created.identifier = NSUserInterfaceItemIdentifier("settings.window")
            created.contentViewController = controller
            created.isReleasedWhenClosed = false
            created.center()
#if DEBUG
            if !ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                created.setFrameAutosaveName("CodexAppExtension.SettingsWindow")
            }
#else
            created.setFrameAutosaveName("CodexAppExtension.SettingsWindow")
#endif
            window = created
            settingsWindow = created
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        settingsWindow.makeKeyAndOrderFront(nil)
    }
}

@MainActor
private final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    var shutdownAction: (() async -> Void)?
    private var isTerminating = false
#if DEBUG
    private weak var model: AppModel?
    private var uiTestingWindow: NSWindow?
#endif

    func configure(model: AppModel) {
        shutdownAction = { await model.shutdown() }
#if DEBUG
        self.model = model
#endif
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--ui-testing"),
              !arguments.contains("--ui-open-settings-on-launch"),
              !arguments.contains("--ui-test-real-menu"),
              let model else { return }
        let controller = NSHostingController(rootView: StatusMenuView(model: model))
        let testingWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 680),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        testingWindow.title = "Codex App Extension 状态"
        testingWindow.identifier = NSUserInterfaceItemIdentifier("uiTesting.statusWindow")
        testingWindow.contentViewController = controller
        testingWindow.isReleasedWhenClosed = false
        testingWindow.center()
        uiTestingWindow = testingWindow
        NSApplication.shared.activate(ignoringOtherApps: true)
        testingWindow.makeKeyAndOrderFront(nil)
#endif
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isTerminating else { return .terminateLater }
        isTerminating = true
        Task {
            await shutdownAction?()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
