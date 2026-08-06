import Foundation

public struct AppConfiguration: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var global: Global
    public var startup: Startup
    public var features: Features
    public var appearance: Appearance
    public var diagnostics: Diagnostics

    public init(
        schemaVersion: Int = AppConfiguration.currentSchemaVersion,
        global: Global = .init(),
        startup: Startup = .init(),
        features: Features = .init(),
        appearance: Appearance = .init(),
        diagnostics: Diagnostics = .init()
    ) {
        self.schemaVersion = schemaVersion
        self.global = global
        self.startup = startup
        self.features = features
        self.appearance = appearance
        self.diagnostics = diagnostics
    }

    public static let defaultConfiguration = AppConfiguration()

    public func validated() throws -> AppConfiguration {
        var failures: [ConfigurationValidationFailure] = []

        if schemaVersion != Self.currentSchemaVersion {
            failures.append(.init(path: "schemaVersion", reason: "必须为 \(Self.currentSchemaVersion)"))
        }
        if !(480...4_096).contains(features.wideLayout.maximumContentWidth) {
            failures.append(.init(path: "features.wideLayout.maximumContentWidth", reason: "必须在 480...4096 之间"))
        }
        if !(0...160).contains(features.wideLayout.minimumSidePadding) {
            failures.append(.init(path: "features.wideLayout.minimumSidePadding", reason: "必须在 0...160 之间"))
        }
        if features.headerAvoidance.mode == .custom,
           !(0...200).contains(features.headerAvoidance.customOffset) {
            failures.append(.init(path: "features.headerAvoidance.customOffset", reason: "自定义模式下必须在 0...200 之间"))
        }
        if !(100...900).contains(features.markdownAppearance.strongText.fontWeight) {
            failures.append(.init(path: "features.markdownAppearance.strongText.fontWeight", reason: "必须在 100...900 之间"))
        }
        if !(1...90).contains(diagnostics.retentionDays) {
            failures.append(.init(path: "diagnostics.retentionDays", reason: "必须在 1...90 之间"))
        }

        let colors: [(String, String)] = [
            ("features.markdownAppearance.heading.color", features.markdownAppearance.heading.color),
            ("features.markdownAppearance.strongText.color", features.markdownAppearance.strongText.color),
            ("features.markdownAppearance.inlineCode.textColor", features.markdownAppearance.inlineCode.textColor),
            ("features.markdownAppearance.inlineCode.backgroundColor", features.markdownAppearance.inlineCode.backgroundColor),
            ("features.markdownAppearance.inlineCode.borderColor", features.markdownAppearance.inlineCode.borderColor),
            ("features.markdownAppearance.blockquote.borderColor", features.markdownAppearance.blockquote.borderColor),
            ("features.markdownAppearance.blockquote.textColor", features.markdownAppearance.blockquote.textColor),
            ("features.markdownAppearance.blockquote.backgroundColor", features.markdownAppearance.blockquote.backgroundColor),
            ("appearance.accentColor", appearance.accentColor)
        ]
        for (path, value) in colors where !Self.isSupportedCSSColor(value) {
            failures.append(.init(path: path, reason: "必须是十六进制、rgb/rgba、inherit 或 currentColor"))
        }

        guard failures.isEmpty else {
            throw ConfigurationValidationError(failures: failures)
        }
        return self
    }

    static func isSupportedCSSColor(_ value: String) -> Bool {
        if value == "inherit" || value == "currentColor" { return true }
        if value.range(of: #"^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$"#, options: .regularExpression) != nil {
            return true
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let isRGBA = trimmed.hasPrefix("rgba(")
        let isRGB = !isRGBA && trimmed.hasPrefix("rgb(")
        guard (isRGB || isRGBA), trimmed.hasSuffix(")") else { return false }
        let prefixCount = isRGBA ? 5 : 4
        let components = trimmed.dropFirst(prefixCount).dropLast().split(separator: ",", omittingEmptySubsequences: false)
        guard components.count == (isRGBA ? 4 : 3) else { return false }
        let values = components.compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard values.count == components.count,
              values.allSatisfy(\.isFinite),
              values.prefix(3).allSatisfy({ (0...255).contains($0) }) else { return false }
        return !isRGBA || (0...1).contains(values[3])
    }
}

public extension AppConfiguration {
    struct Global: Codable, Equatable, Sendable {
        public var isEnabled: Bool

        public init(isEnabled: Bool = true) {
            self.isEnabled = isEnabled
        }
    }

    struct Startup: Codable, Equatable, Sendable {
        public var launchAtLogin: Bool
        public var openSettingsOnLaunch: Bool

        public init(launchAtLogin: Bool = false, openSettingsOnLaunch: Bool = false) {
            self.launchAtLogin = launchAtLogin
            self.openSettingsOnLaunch = openSettingsOnLaunch
        }
    }

    struct Features: Codable, Equatable, Sendable {
        public var wideLayout: WideLayout
        public var headerAvoidance: HeaderAvoidance
        public var ime: IME
        public var markdownAppearance: MarkdownAppearance

        public init(
            wideLayout: WideLayout = .init(),
            headerAvoidance: HeaderAvoidance = .init(),
            ime: IME = .init(),
            markdownAppearance: MarkdownAppearance = .init()
        ) {
            self.wideLayout = wideLayout
            self.headerAvoidance = headerAvoidance
            self.ime = ime
            self.markdownAppearance = markdownAppearance
        }
    }

    struct WideLayout: Codable, Equatable, Sendable {
        public var isEnabled: Bool
        public var maximumContentWidth: Int
        public var minimumSidePadding: Int

        public init(isEnabled: Bool = true, maximumContentWidth: Int = 1_800, minimumSidePadding: Int = 24) {
            self.isEnabled = isEnabled
            self.maximumContentWidth = maximumContentWidth
            self.minimumSidePadding = minimumSidePadding
        }
    }

    struct HeaderAvoidance: Codable, Equatable, Sendable {
        public enum Mode: String, Codable, Sendable { case automatic, custom }

        public var isEnabled: Bool
        public var mode: Mode
        public var customOffset: Int

        public init(isEnabled: Bool = true, mode: Mode = .automatic, customOffset: Int = 46) {
            self.isEnabled = isEnabled
            self.mode = mode
            self.customOffset = customOffset
        }
    }

    struct IME: Codable, Equatable, Sendable {
        public var protectCompositionEnter: Bool

        public init(protectCompositionEnter: Bool = true) {
            self.protectCompositionEnter = protectCompositionEnter
        }
    }

    struct MarkdownAppearance: Codable, Equatable, Sendable {
        public var isEnabled: Bool
        public var heading: TextStyle
        public var strongText: StrongTextStyle
        public var inlineCode: InlineCodeStyle
        public var blockquote: BlockquoteStyle

        public init(
            isEnabled: Bool = true,
            heading: TextStyle = .init(),
            strongText: StrongTextStyle = .init(),
            inlineCode: InlineCodeStyle = .init(),
            blockquote: BlockquoteStyle = .init()
        ) {
            self.isEnabled = isEnabled
            self.heading = heading
            self.strongText = strongText
            self.inlineCode = inlineCode
            self.blockquote = blockquote
        }
    }

    struct TextStyle: Codable, Equatable, Sendable {
        public var isEnabled: Bool
        public var color: String

        public init(isEnabled: Bool = true, color: String = "#F2C94C") {
            self.isEnabled = isEnabled
            self.color = color
        }
    }

    struct StrongTextStyle: Codable, Equatable, Sendable {
        public var isEnabled: Bool
        public var color: String
        public var fontWeight: Int

        public init(isEnabled: Bool = true, color: String = "#F2C94C", fontWeight: Int = 800) {
            self.isEnabled = isEnabled
            self.color = color
            self.fontWeight = fontWeight
        }
    }

    struct InlineCodeStyle: Codable, Equatable, Sendable {
        public var textColor: String
        public var backgroundColor: String
        public var borderColor: String

        public init(
            textColor: String = "#df3079",
            backgroundColor: String = "rgba(223, 48, 121, 0.10)",
            borderColor: String = "rgba(223, 48, 121, 0.18)"
        ) {
            self.textColor = textColor
            self.backgroundColor = backgroundColor
            self.borderColor = borderColor
        }
    }

    struct BlockquoteStyle: Codable, Equatable, Sendable {
        public var borderColor: String
        public var textColor: String
        public var backgroundColor: String

        public init(
            borderColor: String = "#df3079",
            textColor: String = "inherit",
            backgroundColor: String = "rgba(223, 48, 121, 0.06)"
        ) {
            self.borderColor = borderColor
            self.textColor = textColor
            self.backgroundColor = backgroundColor
        }
    }

    struct Appearance: Codable, Equatable, Sendable {
        public enum ColorScheme: String, Codable, Sendable { case system, light, dark }

        public var colorScheme: ColorScheme
        public var accentColor: String

        public init(colorScheme: ColorScheme = .system, accentColor: String = "#0A84FF") {
            self.colorScheme = colorScheme
            self.accentColor = accentColor
        }
    }

    struct Diagnostics: Codable, Equatable, Sendable {
        public enum LogLevel: String, Codable, Sendable { case error, warning, info, debug }

        public var logLevel: LogLevel
        public var retentionDays: Int

        public init(logLevel: LogLevel = .warning, retentionDays: Int = 14) {
            self.logLevel = logLevel
            self.retentionDays = retentionDays
        }
    }
}

public struct ConfigurationValidationFailure: Codable, Equatable, Sendable {
    public let path: String
    public let reason: String

    public init(path: String, reason: String) {
        self.path = path
        self.reason = reason
    }
}

public struct ConfigurationValidationError: Error, Codable, Equatable, Sendable, LocalizedError {
    public let failures: [ConfigurationValidationFailure]

    public init(failures: [ConfigurationValidationFailure]) {
        self.failures = failures
    }

    public var errorDescription: String? {
        failures.map { "\($0.path): \($0.reason)" }.joined(separator: "; ")
    }
}

public enum AppearancePreset: String, CaseIterable, Equatable, Sendable {
    case defaultStyle
    case highContrast
    case custom
}

public enum ConfigurationDraftMutations {
    public static func appearancePreset(matching configuration: AppConfiguration) -> AppearancePreset {
        let defaults = AppConfiguration.defaultConfiguration
        if configuration.features.markdownAppearance == defaults.features.markdownAppearance {
            return .defaultStyle
        }
        var highContrast = defaults
        applyAppearancePreset(.highContrast, to: &highContrast)
        if configuration.features.markdownAppearance == highContrast.features.markdownAppearance {
            return .highContrast
        }
        return .custom
    }

    public static func applyAppearancePreset(_ preset: AppearancePreset, to configuration: inout AppConfiguration) {
        switch preset {
        case .defaultStyle:
            resetAppearance(in: &configuration)
        case .highContrast:
            configuration.features.markdownAppearance = .init(
                isEnabled: true,
                heading: .init(isEnabled: true, color: "#FFD60A"),
                strongText: .init(isEnabled: true, color: "#FFFFFF", fontWeight: 900),
                inlineCode: .init(
                    textColor: "#FF375F",
                    backgroundColor: "rgba(255, 55, 95, 0.20)",
                    borderColor: "#FF375F"
                ),
                blockquote: .init(
                    borderColor: "#FFD60A",
                    textColor: "#FFFFFF",
                    backgroundColor: "rgba(255, 214, 10, 0.12)"
                )
            )
        case .custom:
            break
        }
    }

    public static func resetWideLayout(in configuration: inout AppConfiguration) {
        configuration.features.wideLayout = AppConfiguration.defaultConfiguration.features.wideLayout
    }

    public static func resetHeaderAvoidance(in configuration: inout AppConfiguration) {
        configuration.features.headerAvoidance = AppConfiguration.defaultConfiguration.features.headerAvoidance
    }

    public static func resetMarkdown(in configuration: inout AppConfiguration) {
        configuration.features.markdownAppearance = AppConfiguration.defaultConfiguration.features.markdownAppearance
    }

    public static func resetAppearance(in configuration: inout AppConfiguration) {
        resetMarkdown(in: &configuration)
        configuration.appearance = AppConfiguration.defaultConfiguration.appearance
    }

    public static func canBeginQuickTransaction(isApplying: Bool) -> Bool { !isApplying }
}
