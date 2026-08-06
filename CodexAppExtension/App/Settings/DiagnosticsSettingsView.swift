import Foundation
import SwiftUI

struct DiagnosticsSettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Form {
            SettingsSection("运行时") {
                row("版本", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—", "settings.diagnostics.version")
                row("ChatGPT", process, "settings.diagnostics.process")
                row("CDP", connection, "settings.diagnostics.cdp")
                row("Target", model.snapshot.activeTargetIdentifier ?? "无", "settings.diagnostics.target")
                row("Adapter", "\(model.snapshot.runtime.targets.count) 项", "settings.diagnostics.adapters")
            }
            Divider()
            SettingsSection("迁移报告") {
                Text(migrationText).font(.callout).foregroundStyle(.secondary).textSelection(.enabled).accessibilityIdentifier("settings.diagnostics.migration")
            }
            Divider()
            SettingsSection("操作") {
                HStack {
                    Button("重新连接", action: model.reconnect).accessibilityIdentifier("settings.diagnostics.reconnect")
                    Button("重新注入", action: model.reinject).accessibilityIdentifier("settings.diagnostics.reinject")
                    Button("健康检查", action: model.diagnose).accessibilityIdentifier("settings.diagnostics.health")
                }
                HStack {
                    Button("导出诊断", action: model.exportDiagnostics).accessibilityIdentifier("settings.diagnostics.export")
                    Button("复制摘要", action: model.copyDiagnosticsSummary).accessibilityIdentifier("settings.diagnostics.copySummary")
                }
                if let message = model.diagnosticActionMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .accessibilityLabel(message)
                        .accessibilityIdentifier("settings.diagnostics.actionStatus")
                }
                Button("打开 Codex 官方设置", action: model.openOfficialSettings).accessibilityIdentifier("settings.diagnostics.officialSettings")
            }
        }.formStyle(.grouped).navigationTitle("兼容与诊断")
    }
    private var process: String { if case let .running(pid) = model.snapshot.runtime.process { return "PID \(pid)" }; return "未运行" }
    private var connection: String { if case .connected = model.snapshot.runtime.connection { return "已连接" }; return "未连接" }
    private var migrationText: String { model.snapshot.migrationReport.map { "\($0.status.rawValue) · \($0.entries.count) 项" } ?? "没有迁移报告" }
    private func row(_ name: String, _ value: String, _ id: String) -> some View { LabeledContent(name, value: value).accessibilityIdentifier(id) }
}
