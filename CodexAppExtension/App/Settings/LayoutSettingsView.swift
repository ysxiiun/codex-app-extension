import ExtensionCore
import SwiftUI

struct LayoutSettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Form {
            SettingsSection("宽屏布局", detail: "最大内容宽度是配置上限；实际宽度会按当前可用区域和最小侧边距自动收窄，不改变输入框、右侧栏或菜单。") {
                HStack {
                    Toggle("启用宽屏布局", isOn: $model.draft.features.wideLayout.isEnabled)
                        .accessibilityIdentifier("settings.layout.wideEnabled")
                    Spacer()
                    Button("重置本节", action: model.resetWideLayoutDraft)
                        .controlSize(.small)
                        .accessibilityIdentifier("settings.layout.reset.wide")
                }
                LabeledContent("最大内容宽度") {
                    Slider(
                        value: integerBinding(\.features.wideLayout.maximumContentWidth),
                        in: 480...4_096,
                        step: 8
                    )
                    .frame(width: 220)
                    .accessibilityIdentifier("settings.layout.maximumWidth.slider")
                    TextField("480–4096", value: $model.draft.features.wideLayout.maximumContentWidth, format: .number)
                        .frame(width: 82)
                        .accessibilityIdentifier("settings.layout.maximumWidth")
                    Text("px").foregroundStyle(.secondary)
                }
                LabeledContent("最小侧边距") {
                    Slider(
                        value: integerBinding(\.features.wideLayout.minimumSidePadding),
                        in: 0...160,
                        step: 2
                    )
                    .frame(width: 220)
                    .accessibilityIdentifier("settings.layout.sidePadding.slider")
                    TextField("0–160", value: $model.draft.features.wideLayout.minimumSidePadding, format: .number)
                        .frame(width: 82)
                        .accessibilityIdentifier("settings.layout.sidePadding")
                    Text("px").foregroundStyle(.secondary)
                }
                LabeledContent("当前值") {
                    Text("内容上限 \(model.draft.features.wideLayout.maximumContentWidth) px · 两侧 ≥ \(model.draft.features.wideLayout.minimumSidePadding) px")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.layout.preview")
                }
            }
            Divider()
            SettingsSection("顶部栏避让") {
                HStack {
                    Toggle("启用顶部栏避让", isOn: $model.draft.features.headerAvoidance.isEnabled)
                        .accessibilityIdentifier("settings.layout.headerEnabled")
                    Spacer()
                    Button("重置本节", action: model.resetHeaderAvoidanceDraft)
                        .controlSize(.small)
                        .accessibilityIdentifier("settings.layout.reset.header")
                }
                Picker("偏移模式", selection: $model.draft.features.headerAvoidance.mode) {
                    Text("自动读取原生工具栏").tag(AppConfiguration.HeaderAvoidance.Mode.automatic)
                    Text("自定义").tag(AppConfiguration.HeaderAvoidance.Mode.custom)
                }.accessibilityIdentifier("settings.layout.headerMode")
                if model.draft.features.headerAvoidance.mode == .custom {
                    LabeledContent("顶部偏移") {
                        Slider(
                            value: integerBinding(\.features.headerAvoidance.customOffset),
                            in: 0...200,
                            step: 1
                        )
                        .frame(width: 220)
                        .accessibilityIdentifier("settings.layout.headerOffset.slider")
                        TextField("0–200", value: $model.draft.features.headerAvoidance.customOffset, format: .number)
                            .frame(width: 82)
                            .accessibilityIdentifier("settings.layout.headerOffset")
                        Text("px").foregroundStyle(.secondary)
                    }
                }
            }
        }.formStyle(.grouped).navigationTitle("布局")
    }

    private func integerBinding(_ keyPath: WritableKeyPath<AppConfiguration, Int>) -> Binding<Double> {
        Binding(
            get: { Double(model.draft[keyPath: keyPath]) },
            set: { model.draft[keyPath: keyPath] = Int($0.rounded()) }
        )
    }
}
