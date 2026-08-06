import SwiftUI

struct InputSettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Form {
            SettingsSection("中文输入保护", detail: "仅在输入法组合态拦截 Enter，普通 Enter 保持原生行为。") {
                Toggle("保护组合输入期间的 Enter", isOn: $model.draft.features.ime.protectCompositionEnter)
                    .accessibilityIdentifier("settings.input.imeGuard")
            }
        }.formStyle(.grouped).navigationTitle("输入")
    }
}
