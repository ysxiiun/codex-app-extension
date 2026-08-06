import SwiftUI

struct SettingsRootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: $model.selectedSettingsPage) { page in
                Label(page.rawValue, systemImage: page.symbol)
                    .tag(page)
                    .accessibilityIdentifier("settings.sidebar.\(page.id)")
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            Group {
                switch model.selectedSettingsPage {
                case .general: GeneralSettingsView(model: model)
                case .layout: LayoutSettingsView(model: model)
                case .input: InputSettingsView(model: model)
                case .appearance: AppearanceSettingsView(model: model)
                case .diagnostics: DiagnosticsSettingsView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityIdentifier("settings.root")
        .frame(minWidth: 760, minHeight: 540)
        .safeAreaInset(edge: .bottom) {
            Divider()
            HStack {
                if let error = model.presentedError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).lineLimit(2).accessibilityIdentifier("settings.error")
                }
                Spacer()
                Button("恢复默认", action: model.restoreDefaults).accessibilityIdentifier("settings.restoreDefaults")
                Button("放弃", action: model.discardDraft).disabled(!model.isDraftDirty).accessibilityIdentifier("settings.discard")
                Button("应用", action: model.applyDraft).buttonStyle(.borderedProminent).disabled(!model.isDraftDirty || model.isApplying).accessibilityIdentifier("settings.apply")
            }
            .padding(12)
            .background(.bar)
        }
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    let detail: String?
    let content: Content
    init(_ title: String, detail: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.detail = detail; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            if let detail { Text(detail).font(.callout).foregroundStyle(.secondary) }
            content
        }
        .padding(.vertical, 8)
    }
}
