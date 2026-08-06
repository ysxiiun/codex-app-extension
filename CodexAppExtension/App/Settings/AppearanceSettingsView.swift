import AppKit
import ExtensionCore
import SwiftUI

struct AppearanceSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var previewScheme: ColorScheme = .dark

    var body: some View {
        GeometryReader { geometry in
            if usesWideLayout(for: geometry.size.width) {
                HStack(alignment: .top, spacing: 18) {
                    ScrollView {
                        editor
                            .padding(.bottom, 16)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("settings.appearance.editor.scroll")

                    preview
                        .frame(minWidth: 280, idealWidth: 320, maxWidth: 360, alignment: .top)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("settings.appearance.layout.wide")
                .padding(20)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        preview
                        editor
                    }
                    .padding(20)
                    .padding(.bottom, 16)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("settings.appearance.layout.narrow")
            }
        }
        .navigationTitle("外观")
    }

    private func usesWideLayout(for width: CGFloat) -> Bool {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-appearance-layout=wide") { return true }
        if arguments.contains("--ui-appearance-layout=narrow") { return false }
#endif
        return width >= 760
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 14) {
            AppearanceEditorCard("外观预设", detail: "修改只写入当前草稿，点击应用后才会保存。") {
                Picker("预设", selection: presetBinding) {
                    Text("经典").tag(AppearancePreset.defaultStyle)
                    Text("高对比度").tag(AppearancePreset.highContrast)
                    Text("自定义").tag(AppearancePreset.custom)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settings.appearance.preset")

                HStack {
                    Toggle("启用 Markdown 外观", isOn: $model.draft.features.markdownAppearance.isEnabled)
                        .accessibilityIdentifier("settings.appearance.markdown")
                    Spacer(minLength: 12)
                    Button("恢复经典外观", action: model.resetAppearanceDraft)
                        .controlSize(.small)
                        .accessibilityIdentifier("settings.appearance.reset.all")
                }
            }

            AppearanceEditorCard("标题与强调", detail: "标题和强调文本可独立启用；强调字重范围为 100–900。") {
                Toggle("标题颜色", isOn: $model.draft.features.markdownAppearance.heading.isEnabled)
                    .accessibilityIdentifier("settings.appearance.heading.enabled")
                CSSColorEditorRow(
                    "标题颜色",
                    value: $model.draft.features.markdownAppearance.heading.color,
                    identifier: "settings.appearance.heading.color"
                )

                Divider()
                Toggle("强调文本", isOn: $model.draft.features.markdownAppearance.strongText.isEnabled)
                    .accessibilityIdentifier("settings.appearance.strong.enabled")
                CSSColorEditorRow(
                    "强调颜色",
                    value: $model.draft.features.markdownAppearance.strongText.color,
                    identifier: "settings.appearance.strong.color"
                )
                VStack(alignment: .leading, spacing: 6) {
                    Text("强调字重").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Slider(
                            value: Binding(
                                get: { Double(model.draft.features.markdownAppearance.strongText.fontWeight) },
                                set: { model.draft.features.markdownAppearance.strongText.fontWeight = Int($0.rounded()) }
                            ),
                            in: 100...900,
                            step: 100
                        )
                        .accessibilityIdentifier("settings.appearance.strong.fontWeight.slider")
                        TextField(
                            "100–900",
                            value: $model.draft.features.markdownAppearance.strongText.fontWeight,
                            format: .number
                        )
                        .frame(minWidth: 64, idealWidth: 72, maxWidth: 90)
                        .accessibilityIdentifier("settings.appearance.strong.fontWeight")
                    }
                }
            }

            AppearanceEditorCard("行内代码", detail: "颜色、半透明背景和边框会共同显示在行内代码上。") {
                CSSColorEditorRow(
                    "文字",
                    value: $model.draft.features.markdownAppearance.inlineCode.textColor,
                    identifier: "settings.appearance.inlineCode.text"
                )
                CSSColorEditorRow(
                    "背景",
                    value: $model.draft.features.markdownAppearance.inlineCode.backgroundColor,
                    identifier: "settings.appearance.inlineCode.background"
                )
                CSSColorEditorRow(
                    "边框",
                    value: $model.draft.features.markdownAppearance.inlineCode.borderColor,
                    identifier: "settings.appearance.inlineCode.border"
                )
            }

            AppearanceEditorCard("引用", detail: "正文可使用 inherit/currentColor；嵌套引用不会重复叠加背景和边框。") {
                CSSColorEditorRow(
                    "边线",
                    value: $model.draft.features.markdownAppearance.blockquote.borderColor,
                    identifier: "settings.appearance.blockquote.border"
                )
                CSSColorEditorRow(
                    "文字",
                    value: $model.draft.features.markdownAppearance.blockquote.textColor,
                    identifier: "settings.appearance.blockquote.text"
                )
                CSSColorEditorRow(
                    "背景",
                    value: $model.draft.features.markdownAppearance.blockquote.backgroundColor,
                    identifier: "settings.appearance.blockquote.background"
                )
                HStack {
                    Spacer()
                    Button("重置 Markdown", action: model.resetMarkdownDraft)
                        .controlSize(.small)
                        .accessibilityIdentifier("settings.appearance.reset.markdown")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.appearance.editor")
    }

    private var preview: some View {
        MarkdownAppearancePreview(
            appearance: model.draft.features.markdownAppearance,
            scheme: $previewScheme
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.appearance.preview")
    }

    private var presetBinding: Binding<AppearancePreset> {
        Binding(
            get: { ConfigurationDraftMutations.appearancePreset(matching: model.draft) },
            set: { model.applyAppearancePreset($0) }
        )
    }
}

private struct AppearanceEditorCard<Content: View>: View {
    let title: String
    let detail: String?
    let content: Content

    init(_ title: String, detail: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            if let detail {
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct CSSColorEditorRow: View {
    let label: String
    @Binding var value: String
    let identifier: String

    init(_ label: String, value: Binding<String>, identifier: String) {
        self.label = label
        _value = value
        self.identifier = identifier
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            CSSColorField(value: $value, identifier: identifier)
        }
    }
}

private struct CSSColorField: View {
    @Binding var value: String
    let identifier: String

    private var interpretation: CSSColorInterpretation {
        CSSColorInterpretation(value)
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField("#RRGGBB、rgb/rgba、inherit", text: $value)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier(identifier)

            status
                .accessibilityIdentifier("\(identifier).status")

            if case let .color(nsColor, syntax) = interpretation {
                ColorPicker(
                    "选择颜色",
                    selection: Binding(
                        get: { Color(nsColor: nsColor) },
                        set: { value = syntax.string(from: NSColor($0)) }
                    ),
                    supportsOpacity: syntax.supportsOpacity
                )
                .labelsHidden()
                .accessibilityIdentifier("\(identifier).picker")
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch interpretation {
        case let .color(color, _):
            ZStack {
                HStack(spacing: 0) {
                    Color.white
                    Color.black.opacity(0.28)
                }
                Color(nsColor: color)
            }
            .frame(width: 32, height: 22)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay { RoundedRectangle(cornerRadius: 5).stroke(.secondary.opacity(0.35)) }
            .accessibilityLabel("有效颜色")
        case let .semantic(name):
            Text(name)
                .font(.caption2.monospaced())
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("语义颜色 \(name)")
        case .invalid:
            Label("无效", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("无效")
        }
    }
}

private enum CSSColorSyntax {
    case hex(includeAlpha: Bool)
    case rgb
    case rgba

    var supportsOpacity: Bool {
        switch self {
        case .hex(let includeAlpha): includeAlpha
        case .rgb: false
        case .rgba: true
        }
    }

    func string(from source: NSColor) -> String {
        let color = source.usingColorSpace(.sRGB) ?? source
        let red = Int((color.redComponent * 255).rounded())
        let green = Int((color.greenComponent * 255).rounded())
        let blue = Int((color.blueComponent * 255).rounded())
        switch self {
        case .hex(false):
            return String(format: "#%02X%02X%02X", red, green, blue)
        case .hex(true):
            let alpha = Int((color.alphaComponent * 255).rounded())
            return String(format: "#%02X%02X%02X%02X", red, green, blue, alpha)
        case .rgb:
            return "rgb(\(red), \(green), \(blue))"
        case .rgba:
            return String(format: "rgba(%d, %d, %d, %.2f)", red, green, blue, color.alphaComponent)
        }
    }
}

private enum CSSColorInterpretation {
    case color(NSColor, CSSColorSyntax)
    case semantic(String)
    case invalid

    init(_ source: String) {
        let value = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if value == "inherit" || value == "currentColor" {
            self = .semantic(value)
            return
        }
        if value.hasPrefix("#"), value.count == 7 || value.count == 9,
           let raw = UInt64(value.dropFirst(), radix: 16) {
            if value.count == 7 {
                self = .color(NSColor(
                    srgbRed: CGFloat((raw >> 16) & 0xFF) / 255,
                    green: CGFloat((raw >> 8) & 0xFF) / 255,
                    blue: CGFloat(raw & 0xFF) / 255,
                    alpha: 1
                ), .hex(includeAlpha: false))
            } else {
                self = .color(NSColor(
                    srgbRed: CGFloat((raw >> 24) & 0xFF) / 255,
                    green: CGFloat((raw >> 16) & 0xFF) / 255,
                    blue: CGFloat((raw >> 8) & 0xFF) / 255,
                    alpha: CGFloat(raw & 0xFF) / 255
                ), .hex(includeAlpha: true))
            }
            return
        }

        let isRGBA = value.hasPrefix("rgba(")
        let isRGB = !isRGBA && value.hasPrefix("rgb(")
        guard (isRGB || isRGBA), value.hasSuffix(")") else {
            self = .invalid
            return
        }
        let prefixCount = isRGBA ? 5 : 4
        let parts = value.dropFirst(prefixCount).dropLast().split(separator: ",", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == (isRGBA ? 4 : 3), numbers.count == parts.count,
              numbers.allSatisfy(\.isFinite),
              numbers.prefix(3).allSatisfy({ (0...255).contains($0) }),
              !isRGBA || (0...1).contains(numbers[3]) else {
            self = .invalid
            return
        }
        self = .color(NSColor(
            srgbRed: CGFloat(numbers[0] / 255),
            green: CGFloat(numbers[1] / 255),
            blue: CGFloat(numbers[2] / 255),
            alpha: CGFloat(isRGBA ? numbers[3] : 1)
        ), isRGBA ? .rgba : .rgb)
    }
}

private struct MarkdownAppearancePreview: View {
    let appearance: AppConfiguration.MarkdownAppearance
    @Binding var scheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("实时预览").font(.headline)
                Spacer()
                Picker("预览主题", selection: $scheme) {
                    Text("浅色").tag(ColorScheme.light)
                    Text("深色").tag(ColorScheme.dark)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settings.appearance.preview.scheme")
            }

            VStack(alignment: .leading, spacing: 14) {
                Text("Markdown 标题")
                    .font(.title2.bold())
                    .foregroundColor(headingColor)
                    .accessibilityIdentifier("settings.appearance.preview.heading")

                bodyText
                    .accessibilityIdentifier("settings.appearance.preview.body")

                Text("inlineCode()")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(inlineTextColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(inlineBackgroundColor)
                    .overlay { RoundedRectangle(cornerRadius: 6).stroke(inlineBorderColor, lineWidth: 1) }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .accessibilityIdentifier("settings.appearance.preview.inlineCode")

                VStack(alignment: .leading, spacing: 10) {
                    Text("顶层引用使用当前草稿中的文字、背景和边线。")
                    Text("嵌套引用继承正文，但不会再次绘制边框或背景。")
                        .padding(.leading, 12)
                        .accessibilityIdentifier("settings.appearance.preview.nestedQuote")
                }
                .foregroundColor(quoteTextColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(quoteBackgroundColor)
                .overlay(alignment: .leading) { Rectangle().fill(quoteBorderColor).frame(width: 3) }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("settings.appearance.preview.quote")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(previewBackground, in: RoundedRectangle(cornerRadius: 12))
            .foregroundColor(previewForeground)
            .environment(\.colorScheme, scheme)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08)) }
    }

    private var bodyText: Text {
        Text("这是一段正文，包含 ").foregroundColor(previewForeground)
            + Text("强调文本").foregroundColor(strongColor).fontWeight(strongWeight)
            + Text("，颜色变化会立即出现在这里。").foregroundColor(previewForeground)
    }

    private var previewForeground: Color { scheme == .dark ? Color.white.opacity(0.88) : Color.black.opacity(0.82) }
    private var previewBackground: Color { scheme == .dark ? Color(red: 0.055, green: 0.075, blue: 0.11) : Color.white }
    private var enabled: Bool { appearance.isEnabled }
    private var headingColor: Color {
        enabled && appearance.heading.isEnabled ? resolved(appearance.heading.color, fallback: previewForeground) : previewForeground
    }
    private var strongColor: Color {
        enabled && appearance.strongText.isEnabled ? resolved(appearance.strongText.color, fallback: previewForeground) : previewForeground
    }
    private var strongWeight: Font.Weight {
        guard enabled && appearance.strongText.isEnabled else { return .bold }
        switch appearance.strongText.fontWeight {
        case ..<250: return .ultraLight
        case ..<350: return .light
        case ..<450: return .regular
        case ..<550: return .medium
        case ..<650: return .semibold
        case ..<750: return .bold
        case ..<850: return .heavy
        default: return .black
        }
    }
    private var inlineTextColor: Color { enabled ? resolved(appearance.inlineCode.textColor, fallback: previewForeground) : previewForeground }
    private var inlineBackgroundColor: Color { enabled ? resolved(appearance.inlineCode.backgroundColor, fallback: .clear) : .clear }
    private var inlineBorderColor: Color { enabled ? resolved(appearance.inlineCode.borderColor, fallback: .clear) : .clear }
    private var quoteTextColor: Color { enabled ? resolved(appearance.blockquote.textColor, fallback: previewForeground) : previewForeground }
    private var quoteBackgroundColor: Color { enabled ? resolved(appearance.blockquote.backgroundColor, fallback: .clear) : .clear }
    private var quoteBorderColor: Color { enabled ? resolved(appearance.blockquote.borderColor, fallback: .clear) : .clear }

    private func resolved(_ source: String, fallback: Color) -> Color {
        switch CSSColorInterpretation(source) {
        case let .color(color, _): return Color(nsColor: color)
        case .semantic: return previewForeground
        case .invalid: return fallback
        }
    }
}
