import AppKit
import ExtensionCore
import SwiftUI

struct StatusMenuView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: model.statusTone.symbol)
                    .foregroundStyle(model.statusTone.color)
                    .accessibilityIdentifier("status.icon")
                    .accessibilityLabel(model.statusText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.statusText).font(.headline)
                    Text(statusDetail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                statusRow("ChatGPT", value: processText, identifier: "status.process")
                statusRow("CDP", value: connectionText, identifier: "status.cdp")
                statusRow("合格 Target", value: model.snapshot.activeTargetIdentifier ?? "无", identifier: "status.target")
                statusRow("增强", value: adapterText, identifier: "status.adapters")
#if DEBUG
                if model.exposesRestartUITestState {
                    Text("重启确认次数：\(model.restartConfirmationCountForUITesting)")
                        .font(.caption)
                        .accessibilityIdentifier("ui.restart.confirmationCount")
                }
#endif
            }
            .padding(16)

            Divider()

            VStack(spacing: 8) {
                quickToggle("启用扩展", isOn: model.snapshot.configuration.global.isEnabled, identifier: "quick.global", action: model.toggleGlobal)
                quickToggle("宽屏布局", isOn: model.snapshot.configuration.features.wideLayout.isEnabled, identifier: "quick.wide", action: model.toggleWideLayout)
                quickToggle("中文输入保护", isOn: model.snapshot.configuration.features.ime.protectCompositionEnter, identifier: "quick.ime", action: model.toggleIME)
                quickToggle("Markdown 外观", isOn: model.snapshot.configuration.features.markdownAppearance.isEnabled, identifier: "quick.markdown", action: model.toggleMarkdown)
            }
            .padding(16)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                if case .notRunning = model.snapshot.runtime.process {
                    actionButton("启动 ChatGPT", systemImage: "play.fill", identifier: "action.start", action: model.startChatGPT)
                }
                if model.snapshot.pendingRestartConfirmation {
                    actionButton("确认重启 ChatGPT…", systemImage: "arrow.clockwise", identifier: "action.confirmRestart", action: model.requestRestartConfirmation)
                }
                actionButton("重新连接", systemImage: "network", identifier: "action.reconnect", action: model.reconnect)
                actionButton("重新注入", systemImage: "syringe", identifier: "action.reinject", action: model.reinject)
                actionButton("运行健康检查", systemImage: "stethoscope", identifier: "action.diagnose", action: model.diagnose)
                Divider().padding(.vertical, 4)
                settingsButton
                actionButton("退出", systemImage: "power", identifier: "action.quit") { NSApplication.shared.terminate(nil) }
            }
            .padding(12)
        }
        .frame(width: 340)
    }

    private var statusDetail: String {
        model.snapshot.lastError ?? "运行时状态由本地 CDP 健康检查提供"
    }
    private var processText: String {
        if case let .running(pid) = model.snapshot.runtime.process { return "运行中 · PID \(pid)" }
        return "未运行"
    }
    private var connectionText: String {
        switch model.snapshot.runtime.connection {
        case .connected: return "已连接"
        case .backingOff: return "退避重连"
        case .checkingReadiness, .connecting: return "连接中"
        case .disconnected: return "未连接"
        }
    }
    private var adapterText: String {
        let degraded = model.snapshot.runtime.targets.filter { if case .degraded = $0.state { return true }; return false }.count
        let waiting = model.snapshot.runtime.targets.filter { if case .waiting = $0.state { return true }; return false }.count
        if degraded > 0, waiting > 0 { return "\(degraded) 项降级 · \(waiting) 项等待" }
        if degraded > 0 { return "\(degraded) 项降级" }
        if waiting > 0 { return "\(waiting) 项等待" }
        return "\(model.snapshot.runtime.targets.count) 项正常"
    }

    private func statusRow(_ label: String, value: String, identifier: String) -> some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value) }
            .font(.callout).accessibilityIdentifier(identifier)
    }
    private func quickToggle(_ title: String, isOn: Bool, identifier: String, action: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 12)
            Toggle("", isOn: Binding(get: { isOn }, set: { newValue in action(newValue) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(quickTogglesDisabled)
                .accessibilityLabel(title)
                .accessibilityIdentifier(identifier)
        }
        .frame(maxWidth: .infinity)
    }
    private var quickTogglesDisabled: Bool {
        if model.isApplying { return true }
#if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--ui-is-applying")
#else
        return false
#endif
    }
    private func actionButton(_ title: String, systemImage: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: systemImage).frame(maxWidth: .infinity, alignment: .leading) }
            .buttonStyle(.plain).padding(.vertical, 4).accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private var settingsButton: some View {
        actionButton(
            "打开设置…",
            systemImage: "gearshape",
            identifier: "action.settings",
            action: model.requestSettingsWindow
        )
    }

}
