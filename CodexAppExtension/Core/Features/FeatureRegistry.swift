import Foundation

public enum PageRuntimeOperation: String, Codable, Equatable, Sendable {
    case handshake
    case register
    case install
    case update
    case diagnose
    case uninstall
}

public struct PageRuntimeError: Codable, Equatable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public struct PageRuntimeEnvelope: Codable, Equatable, Sendable {
    public let runtimeVersion: Int
    public let requestId: UInt64
    public let adapterId: String
    public let operation: PageRuntimeOperation
    public let config: JSONValue?
    public let result: JSONValue?
    public let error: PageRuntimeError?

    public init(
        runtimeVersion: Int = 2,
        requestId: UInt64,
        adapterId: String,
        operation: PageRuntimeOperation,
        config: JSONValue?,
        result: JSONValue? = nil,
        error: PageRuntimeError? = nil
    ) {
        self.runtimeVersion = runtimeVersion
        self.requestId = requestId
        self.adapterId = adapterId
        self.operation = operation
        self.config = config
        self.result = result
        self.error = error
    }

    private enum CodingKeys: String, CodingKey {
        case runtimeVersion
        case requestId
        case adapterId
        case operation
        case config
        case result
        case error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        runtimeVersion = try container.decode(Int.self, forKey: .runtimeVersion)
        requestId = try container.decode(UInt64.self, forKey: .requestId)
        adapterId = try container.decode(String.self, forKey: .adapterId)
        operation = try container.decode(PageRuntimeOperation.self, forKey: .operation)
        config = try container.decodeIfPresent(JSONValue.self, forKey: .config)
        result = try container.decodeIfPresent(JSONValue.self, forKey: .result)
        error = try container.decodeIfPresent(PageRuntimeError.self, forKey: .error)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(runtimeVersion, forKey: .runtimeVersion)
        try container.encode(requestId, forKey: .requestId)
        try container.encode(adapterId, forKey: .adapterId)
        try container.encode(operation, forKey: .operation)
        if let config { try container.encode(config, forKey: .config) }
        else { try container.encodeNil(forKey: .config) }
        if let result { try container.encode(result, forKey: .result) }
        else { try container.encodeNil(forKey: .result) }
        if let error { try container.encode(error, forKey: .error) }
        else { try container.encodeNil(forKey: .error) }
    }
}

public enum FeatureIdentifier: String, CaseIterable, Codable, Sendable {
    case wideLayout = "wide-layout"
    case headerOffset = "header-offset"
    case imeEnterGuard = "ime-enter-guard"
    case markdownSemanticTheme = "markdown-semantic-theme"
}

public struct FeatureRegistration: Equatable, Sendable {
    public let identifier: FeatureIdentifier
    public let resourcePath: String
    public let order: Int
    public let isEnabled: Bool
    public let config: JSONValue

    public init(
        identifier: FeatureIdentifier,
        resourcePath: String,
        order: Int,
        isEnabled: Bool,
        config: JSONValue
    ) {
        self.identifier = identifier
        self.resourcePath = resourcePath
        self.order = order
        self.isEnabled = isEnabled
        self.config = config
    }
}

public struct LoadedFeatureScript: Equatable, Sendable {
    public let adapterId: String
    public let source: String

    public init(adapterId: String, source: String) {
        self.adapterId = adapterId
        self.source = source
    }
}

public protocol PageRuntimeScriptLoading: Sendable {
    func loadBootstrapScript(from bundle: Bundle) throws -> LoadedFeatureScript
    func loadAdapterScript(for registration: FeatureRegistration, from bundle: Bundle) throws -> LoadedFeatureScript
}

public enum FeatureResourceError: Error, Equatable, Sendable, LocalizedError {
    case missingResource(String)
    case unreadableResource(String, reason: String)

    public var errorDescription: String? {
        switch self {
        case let .missingResource(resource): return "缺少 PageRuntime 资源: \(resource)"
        case let .unreadableResource(resource, reason): return "无法读取 PageRuntime 资源 \(resource): \(reason)"
        }
    }
}

public enum FeatureExecutionStatus: String, Equatable, Sendable {
    case installed
    case updated
    case diagnosed
    case uninstalled
    case waiting
    case degraded
}

public struct FeatureExecutionResult: Equatable, Sendable {
    public let adapterId: String
    public let status: FeatureExecutionStatus
    public let error: PageRuntimeError?

    public init(adapterId: String, status: FeatureExecutionStatus, error: PageRuntimeError?) {
        self.adapterId = adapterId
        self.status = status
        self.error = error
    }
}

public struct FeatureRegistry: Sendable, PageRuntimeScriptLoading {
    public static let runtimeVersion = 2

    public init() {}

    public func registrations(
        for configuration: AppConfiguration,
        selectedIDs: Set<FeatureIdentifier>? = nil
    ) -> [FeatureRegistration] {
        let features = configuration.features
        return [
            .init(
                identifier: .wideLayout,
                resourcePath: "Adapters/wide-layout.js",
                order: 10,
                isEnabled: features.wideLayout.isEnabled,
                config: .object([
                    "maximumContentWidth": .number(Double(features.wideLayout.maximumContentWidth)),
                    "minimumSidePadding": .number(Double(features.wideLayout.minimumSidePadding))
                ])
            ),
            .init(
                identifier: .headerOffset,
                resourcePath: "Adapters/header-offset.js",
                order: 20,
                isEnabled: features.headerAvoidance.isEnabled,
                config: .object([
                    "mode": .string(features.headerAvoidance.mode.rawValue),
                    "customOffset": .number(Double(features.headerAvoidance.customOffset))
                ])
            ),
            .init(
                identifier: .imeEnterGuard,
                resourcePath: "Adapters/ime-enter-guard.js",
                order: 30,
                isEnabled: features.ime.protectCompositionEnter,
                config: .object(["protectCompositionEnter": .bool(features.ime.protectCompositionEnter)])
            ),
            .init(
                identifier: .markdownSemanticTheme,
                resourcePath: "Adapters/markdown-semantic-theme.js",
                order: 40,
                isEnabled: features.markdownAppearance.isEnabled,
                config: markdownConfig(features.markdownAppearance)
            )
        ]
        .filter { selectedIDs?.contains($0.identifier) ?? true }
        .sorted { ($0.order, $0.identifier.rawValue) < ($1.order, $1.identifier.rawValue) }
    }

    public func envelopes(
        for configuration: AppConfiguration,
        operation: PageRuntimeOperation,
        startingRequestId: UInt64,
        selectedIDs: Set<FeatureIdentifier>? = nil
    ) -> [PageRuntimeEnvelope] {
        registrations(for: configuration, selectedIDs: selectedIDs).enumerated().map { index, registration in
            let effectiveOperation: PageRuntimeOperation = registration.isEnabled ? operation : .uninstall
            return PageRuntimeEnvelope(
                requestId: startingRequestId + UInt64(index),
                adapterId: registration.identifier.rawValue,
                operation: effectiveOperation,
                config: registration.config
            )
        }
    }

    public func loadScripts(
        for configuration: AppConfiguration,
        from bundle: Bundle,
        selectedIDs: Set<FeatureIdentifier>? = nil
    ) throws -> [LoadedFeatureScript] {
        var scripts = [try loadBootstrapScript(from: bundle)]
        for registration in registrations(for: configuration, selectedIDs: selectedIDs) {
            scripts.append(try loadAdapterScript(for: registration, from: bundle))
        }
        return scripts
    }

    public func loadBootstrapScript(from bundle: Bundle) throws -> LoadedFeatureScript {
        try loadScript(adapterId: "runtime", resourcePath: "PageRuntime/bootstrap.js", from: bundle)
    }

    public func loadAdapterScript(
        for registration: FeatureRegistration,
        from bundle: Bundle
    ) throws -> LoadedFeatureScript {
        try loadScript(
            adapterId: registration.identifier.rawValue,
            resourcePath: registration.resourcePath,
            from: bundle
        )
    }

    public func executionResults(from envelopes: [PageRuntimeEnvelope]) -> [FeatureExecutionResult] {
        envelopes.map { envelope in
            let status: FeatureExecutionStatus
            if envelope.error != nil { status = .degraded }
            else if envelope.result?["qualified"] == .bool(false),
                    envelope.result?["recoverable"] == .bool(true) {
                status = .waiting
            }
            else {
                switch envelope.operation {
                case .install: status = .installed
                case .update: status = .updated
                case .diagnose, .handshake, .register: status = .diagnosed
                case .uninstall: status = .uninstalled
                }
            }
            return .init(adapterId: envelope.adapterId, status: status, error: envelope.error)
        }
    }

    private func markdownConfig(_ appearance: AppConfiguration.MarkdownAppearance) -> JSONValue {
        .object([
            "heading": .object([
                "enabled": .bool(appearance.heading.isEnabled),
                "color": .string(appearance.heading.color)
            ]),
            "strongText": .object([
                "enabled": .bool(appearance.strongText.isEnabled),
                "color": .string(appearance.strongText.color),
                "fontWeight": .number(Double(appearance.strongText.fontWeight))
            ]),
            "inlineCode": .object([
                "textColor": .string(appearance.inlineCode.textColor),
                "backgroundColor": .string(appearance.inlineCode.backgroundColor),
                "borderColor": .string(appearance.inlineCode.borderColor)
            ]),
            "blockquote": .object([
                "borderColor": .string(appearance.blockquote.borderColor),
                "textColor": .string(appearance.blockquote.textColor),
                "backgroundColor": .string(appearance.blockquote.backgroundColor)
            ])
        ])
    }

    private func loadScript(
        adapterId: String,
        resourcePath: String,
        from bundle: Bundle
    ) throws -> LoadedFeatureScript {
        let filename = URL(fileURLWithPath: resourcePath).deletingPathExtension().lastPathComponent
        guard let url = bundle.url(forResource: filename, withExtension: "js") else {
            throw FeatureResourceError.missingResource(resourcePath)
        }
        do {
            return LoadedFeatureScript(adapterId: adapterId, source: try String(contentsOf: url, encoding: .utf8))
        } catch {
            throw FeatureResourceError.unreadableResource(resourcePath, reason: String(describing: error))
        }
    }
}
