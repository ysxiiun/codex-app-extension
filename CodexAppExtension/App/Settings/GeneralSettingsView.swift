import ExtensionCore
import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Form {
            SettingsSection("扩展") {
                Toggle("启用 Codex App Extension", isOn: $model.draft.global.isEnabled)
                    .accessibilityIdentifier("settings.general.enabled")
            }
            Divider()
            SettingsSection("登录与启动", detail: loginDetail) {
                Toggle("登录时启动", isOn: Binding(
                    get: { model.snapshot.configuration.startup.launchAtLogin },
                    set: { enabled in model.setLaunchAtLogin(enabled) }
                )).accessibilityIdentifier("settings.general.launchAtLogin")
                Toggle("启动后打开设置", isOn: $model.draft.startup.openSettingsOnLaunch)
                    .accessibilityIdentifier("settings.general.openSettingsOnLaunch")
            }
        }
        .formStyle(.grouped).navigationTitle("通用")
    }
    private var loginDetail: String {
        switch model.snapshot.launchAtLogin {
        case .requiresApproval: return "需要在“系统设置 > 通用 > 登录项”中批准。"
        case .error: return "开机启动授权失败，未伪装为已启用。"
        case .unavailable: return "当前系统不支持此能力。"
        default: return "使用 macOS 登录项服务管理。"
        }
    }
}
