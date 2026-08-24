import Foundation
import JavaScriptCore
import XCTest
@testable import ExtensionCore

final class PageRuntimeTests: XCTestCase {
    func testHandshakeUsesSingleGlobalAndFixedEnvelope() throws {
        let harness = try JSRuntimeHarness(fixture: "current-surface")
        let runtime = try harness.runtime()
        let response = try XCTUnwrap(runtime.invokeMethod("handshake", withArguments: [77]).toDictionary())

        XCTAssertEqual(response["runtimeVersion"] as? Int, 2)
        XCTAssertEqual(response["requestId"] as? Int, 77)
        XCTAssertEqual(response["adapterId"] as? String, "runtime")
        XCTAssertEqual(response["operation"] as? String, "handshake")
        XCTAssertTrue(response.keys.contains("config"))
        XCTAssertTrue(response.keys.contains("result"))
        XCTAssertTrue(response.keys.contains("error"))
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["implementationRevision"] as? Int, CDPPageRuntimeBridge.implementationRevision)
        XCTAssertEqual(result["rehydrationRequired"] as? Bool, true)
        XCTAssertEqual(result["hydrated"] as? Bool, false)
        let hydrationState = try XCTUnwrap(runtime.invokeMethod("hydrationState", withArguments: []).toDictionary())
        XCTAssertEqual(hydrationState["rehydrationRequired"] as? Bool, true)
        XCTAssertEqual(hydrationState["hydrated"] as? Bool, false)
        XCTAssertEqual(try harness.string("Object.getOwnPropertyNames(window).filter((name) => name.startsWith('__codex')).join(',')"), "__codexAppExtensionV2")
    }

    func testImplementationRevisionUpgradeCleansRetiredFocusEffectsAndSameRevisionReloadIsNoOp() throws {
        let harness = try JSRuntimeHarness(fixture: "current-surface")
        try harness.evaluate("""
        (() => {
          const runtime = window.__codexAppExtensionV2;
          const layout = document.querySelector('[data-app-shell-main-content-layout]');
          const editor = document.querySelector(".ProseMirror[contenteditable='true']");
          const style = document.createElement('style');
          style.id = 'legacy-focus-style';
          document.head.appendChild(style);
          layout.setAttribute('data-legacy-focus', 'true');
          editor.setAttribute('data-legacy-focus', 'true');
          window.__oldRuntimeIdentity = runtime;
          window.__oldCleanupCalls = [];
          Object.assign(runtime, {
            implementationRevision: 5,
            execute(request) {
              window.__oldCleanupCalls.push(request.adapterId);
              if (request.adapterId === 'focus-ring') {
                layout.removeAttribute('data-legacy-focus');
                editor.removeAttribute('data-legacy-focus');
                document.getElementById('legacy-focus-style')?.remove();
              }
              return {
                runtimeVersion: 2,
                requestId: request.requestId,
                adapterId: request.adapterId,
                operation: request.operation,
                config: request.config,
                result: { changed: true },
                error: null
              };
            }
          });
        })();
        """)

        try harness.loadBootstrap()

        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2 === window.__oldRuntimeIdentity"))
        XCTAssertEqual(try harness.int("window.__codexAppExtensionV2.implementationRevision"), CDPPageRuntimeBridge.implementationRevision)
        XCTAssertEqual(try harness.int("window.__oldCleanupCalls.length"), 5)
        XCTAssertEqual(try harness.string("window.__oldCleanupCalls.join(',')"), "wide-layout,header-offset,ime-enter-guard,focus-ring,markdown-semantic-theme")
        XCTAssertFalse(try harness.bool("document.querySelector('[data-app-shell-main-content-layout]').hasAttribute('data-legacy-focus')"))
        XCTAssertFalse(try harness.bool("document.querySelector(\".ProseMirror[contenteditable='true']\").hasAttribute('data-legacy-focus')"))
        XCTAssertTrue(try harness.value("document.getElementById('legacy-focus-style')").isNull)

        for adapter in ["wide-layout", "header-offset", "ime-enter-guard", "markdown-semantic-theme"] {
            try harness.loadAdapter(adapter)
            let response = try harness.invoke("diagnose", request: harness.request(
                id: 100,
                adapterId: adapter,
                operation: "diagnose",
                config: harness.defaultConfig(adapterId: adapter)
            ))
            XCTAssertNotEqual((response["error"] as? [String: Any])?["code"] as? String, "adapter-not-registered", adapter)
        }

        let cleanupCount = try harness.int("window.__oldCleanupCalls.length")
        let observerCount = try harness.int("window.__mutationObservers.length")
        let rafCount = try harness.int("window.__rafQueue.length")
        let timerCount = try harness.int("window.__timerQueue.length")
        try harness.loadBootstrap()
        XCTAssertEqual(try harness.int("window.__oldCleanupCalls.length"), cleanupCount)
        XCTAssertEqual(try harness.int("window.__mutationObservers.length"), observerCount)
        XCTAssertEqual(try harness.int("window.__rafQueue.length"), rafCount)
        XCTAssertEqual(try harness.int("window.__timerQueue.length"), timerCount)
    }

    func testSurfaceUsesStableLayoutIdentityAndTreatsEditorAsOptionalCapability() throws {
        let harness = try JSRuntimeHarness(fixture: "current-surface")
        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.surface().qualified"))
        XCTAssertEqual(try harness.string("window.__codexAppExtensionV2.surface().kind"), "thread")
        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.surface().composer === window.__codexAppExtensionV2.surface().editor"))
        XCTAssertEqual(try harness.string("window.__codexAppExtensionV2.surface().composerSignal"), "true")

        let legacy = try JSRuntimeHarness(fixture: "legacy-fictional-surface")
        XCTAssertFalse(try legacy.bool("window.__codexAppExtensionV2.surface().qualified"))
        XCTAssertTrue(try legacy.value("window.__codexAppExtensionV2.surface().layoutRoot").isNull)

        let unmarked = try JSRuntimeHarness(fixture: "current-surface")
        try unmarked.evaluate("""
        (() => {
          const editor = document.querySelector(".ProseMirror[contenteditable='true']");
          editor.removeAttribute('data-codex-composer');
          document.__registerAll(".ProseMirror[data-codex-composer='true'][contenteditable='true'], .ProseMirror[data-codex-composer='true'][contenteditable='plaintext-only']", []);
        })();
        """)
        XCTAssertTrue(try unmarked.bool("window.__codexAppExtensionV2.surface().qualified"))
        XCTAssertTrue(try unmarked.value("window.__codexAppExtensionV2.surface().editor").isNull)

        let emptyMarked = try JSRuntimeHarness(fixture: "current-surface")
        try emptyMarked.evaluate("document.__loadFixture('<main data-app-shell-main-content-layout data-empty-task></main>')")
        XCTAssertTrue(try emptyMarked.bool("window.__codexAppExtensionV2.surface().qualified"))
        XCTAssertEqual(try emptyMarked.string("window.__codexAppExtensionV2.surface().kind"), "empty-composer")
        XCTAssertEqual(try emptyMarked.string("window.__codexAppExtensionV2.surface().editorSignal"), "marked")

        let emptyFallback = try JSRuntimeHarness(fixture: "current-surface")
        try emptyFallback.evaluate("""
        (() => {
          document.__loadFixture('<main data-app-shell-main-content-layout data-empty-task></main>');
          const editor = document.querySelector(".ProseMirror[contenteditable='true']");
          editor.removeAttribute('data-codex-composer');
          document.__registerAll(".ProseMirror[data-codex-composer='true'][contenteditable='true'], .ProseMirror[data-codex-composer='true'][contenteditable='plaintext-only']", []);
          document.__registerAll('[data-codex-composer]', []);
        })();
        """)
        XCTAssertTrue(try emptyFallback.bool("window.__codexAppExtensionV2.surface().qualified"))
        XCTAssertEqual(try emptyFallback.string("window.__codexAppExtensionV2.surface().kind"), "empty-composer")
        XCTAssertEqual(try emptyFallback.string("window.__codexAppExtensionV2.surface().editorSignal"), "fallback")
        XCTAssertFalse(try emptyFallback.value("window.__codexAppExtensionV2.surface().editor").isNull)

        let hiddenFallback = try JSRuntimeHarness(fixture: "current-surface")
        try hiddenFallback.evaluate("""
        (() => {
          document.__loadFixture('<main data-app-shell-main-content-layout data-empty-task></main>');
          const editor = document.querySelector(".ProseMirror[contenteditable='true']");
          editor.removeAttribute('data-codex-composer');
          editor.setAttribute('aria-hidden', 'true');
          document.__registerAll(".ProseMirror[data-codex-composer='true'][contenteditable='true'], .ProseMirror[data-codex-composer='true'][contenteditable='plaintext-only']", []);
          document.__registerAll('[data-codex-composer]', []);
        })();
        """)
        XCTAssertFalse(try hiddenFallback.bool("window.__codexAppExtensionV2.surface().qualified"))
        XCTAssertEqual(try hiddenFallback.int("window.__codexAppExtensionV2.surface().editorCount"), 0)
        XCTAssertTrue(try hiddenFallback.value("window.__codexAppExtensionV2.surface().editor").isNull)

        try harness.evaluate("document.__loadFixture('<main data-app-shell-main-content-layout data-duplicate-editor></main>')")
        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.surface().qualified"))
        XCTAssertTrue(try harness.value("window.__codexAppExtensionV2.surface().editor").isNull)

        try harness.evaluate("""
        (() => {
          document.__loadFixture('<main data-app-shell-main-content-layout></main>');
          const editor = document.querySelector(".ProseMirror[contenteditable='true']");
          editor.remove();
          document.body.appendChild(editor);
        })();
        """)
        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.surface().qualified"))
        XCTAssertTrue(try harness.value("window.__codexAppExtensionV2.surface().editor").isNull)
        try harness.loadAdapter("wide-layout")
        let installed = try harness.invoke("install", request: harness.request(
            id: 1,
            adapterId: "wide-layout",
            operation: "install",
            config: ["maximumContentWidth": 1_300, "minimumSidePadding": 0]
        ))
        XCTAssertNil(harness.nonNullError(installed))
        XCTAssertEqual((installed["result"] as? [String: Any])?["qualified"] as? Bool, true)
        XCTAssertEqual(try harness.string("document.querySelector('.thread-scroll-container').getAttribute('data-cae-wide-layout')"), "true")
    }

    func testSwiftEnvelopeAlwaysEncodesAllContractKeys() throws {
        let envelope = PageRuntimeEnvelope(
            requestId: 9,
            adapterId: "wide-layout",
            operation: .install,
            config: .object(["maximumContentWidth": .number(1_600)])
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(envelope)) as? [String: Any])

        XCTAssertEqual(Set(object.keys), ["runtimeVersion", "requestId", "adapterId", "operation", "config", "result", "error"])
        XCTAssertTrue(object["result"] is NSNull)
        XCTAssertTrue(object["error"] is NSNull)
    }

    func testFeatureRegistryMapsSortsAndLoadsExactlyFourAdapters() throws {
        let registry = FeatureRegistry()
        let configuration = AppConfiguration.defaultConfiguration
        let registrations = registry.registrations(for: configuration)

        XCTAssertEqual(registrations.map(\.identifier), [.wideLayout, .headerOffset, .imeEnterGuard, .markdownSemanticTheme])
        XCTAssertEqual(registrations.map(\.order), registrations.map(\.order).sorted())
        XCTAssertFalse(registrations.map { $0.identifier.rawValue }.contains("focus-ring"))

        let encoded = try JSONEncoder().encode(configuration)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let features = try XCTUnwrap(object["features"] as? [String: Any])
        XCTAssertNil(features["focusRing"])

        let bundle = Bundle(for: Self.self)
        let scripts = try registry.loadScripts(for: configuration, from: bundle)
        XCTAssertEqual(scripts.map(\.adapterId), ["runtime", "wide-layout", "header-offset", "ime-enter-guard", "markdown-semantic-theme"])
        XCTAssertTrue(scripts.allSatisfy { !$0.source.isEmpty })
        XCTAssertNil(bundle.url(forResource: "focus-ring", withExtension: "js"))

        let envelopes = registry.envelopes(for: configuration, operation: .install, startingRequestId: 100)
        XCTAssertEqual(envelopes.map(\.requestId), [100, 101, 102, 103])
        guard case let .object(wideConfig)? = envelopes.first?.config else {
            return XCTFail("wide-layout 配置片段缺失")
        }
        XCTAssertEqual(Set(wideConfig.keys), ["maximumContentWidth", "minimumSidePadding"])
    }

    func testRepeatedInstallAndConfigurationDiffAreIdempotent() throws {
        let harness = try JSRuntimeHarness(fixture: "current-surface")
        try harness.loadAdapter("wide-layout")
        let firstRequest = harness.request(
            id: 1,
            adapterId: "wide-layout",
            operation: "install",
            config: ["maximumContentWidth": 1_600, "minimumSidePadding": 24]
        )
        let first = try harness.invoke("install", request: firstRequest)
        let repeated = try harness.invoke("install", request: firstRequest)
        let changed = try harness.invoke("update", request: harness.request(
            id: 2,
            adapterId: "wide-layout",
            operation: "update",
            config: ["maximumContentWidth": 1_800, "minimumSidePadding": 32]
        ))

        XCTAssertNil(harness.nonNullError(first))
        XCTAssertEqual((repeated["result"] as? [String: Any])?["idempotent"] as? Bool, true)
        XCTAssertEqual((changed["result"] as? [String: Any])?["changed"] as? Bool, true)
        XCTAssertEqual(try harness.string("document.querySelector('.thread-scroll-container').style.getPropertyValue('--thread-content-max-width')"), "min(1800px, max(1px, calc(100% - 64px)))")
        XCTAssertEqual(try harness.string("document.querySelector('.thread-scroll-container').style.getPropertyValue('--markdown-wide-block-max-width')"), "min(1800px, max(1px, calc(100% - 64px)))")
        XCTAssertEqual(try harness.string("document.querySelector('.thread-scroll-container').style.getPropertyValue('--thread-composer-max-width')"), "min(1800px, max(1px, calc(100% - 64px)))")
        XCTAssertEqual(try harness.string("document.querySelector('.thread-scroll-container').style.getPropertyValue('--cae-wide-layout-content-offset-x')"), "0px")
    }

    func testAdapterFailureIsIsolatedWithinBatch() throws {
        let harness = try JSRuntimeHarness(fixture: "current-surface")
        try harness.evaluate("""
        (() => {
          const runtime = window.__codexAppExtensionV2;
          const common = { probe() { return { qualified: true }; }, update() {}, diagnose() {}, uninstall() {} };
          runtime.register({ adapterId: 'thrower', ...common, install() { throw new Error('fictional failure'); } });
          runtime.register({ adapterId: 'healthy', ...common, install() { return { installed: true }; } });
        })();
        """)
        let runtime = try harness.runtime()
        let requests = [
            harness.request(id: 1, adapterId: "thrower", operation: "install", config: [:]),
            harness.request(id: 2, adapterId: "healthy", operation: "install", config: [:])
        ]
        let responses = try XCTUnwrap(runtime.invokeMethod("installAll", withArguments: [requests]).toArray())
        let first = try XCTUnwrap(responses[0] as? [String: Any])
        let second = try XCTUnwrap(responses[1] as? [String: Any])

        XCTAssertEqual((first["error"] as? [String: Any])?["code"] as? String, "adapter-operation-failed")
        XCTAssertTrue(second["error"] is NSNull)
        XCTAssertEqual((second["result"] as? [String: Any])?["installed"] as? Bool, true)
    }

    func testOperationFailureImmediatelyMarksObserverHardFailedUntilSuccessfulReconcile() throws {
        let harness = try JSRuntimeHarness(fixture: "current-surface")
        try harness.evaluate("""
        (() => {
          const runtime = window.__codexAppExtensionV2;
          window.__recoveringAdapterShouldThrow = false;
          window.__recoveringAdapterUpdateCount = 0;
          runtime.register({
            adapterId: 'recovering-operation',
            probe() { return { qualified: true }; },
            install() { return { changed: true, qualified: true }; },
            update() {
              window.__recoveringAdapterUpdateCount += 1;
              if (window.__recoveringAdapterShouldThrow) throw new Error('operation exploded');
              return { changed: true, qualified: true };
            },
            diagnose() { return { qualified: true }; },
            uninstall() { return { changed: true }; }
          });
          runtime.observe('recovering-operation', () => ({ qualified: true, recoverable: false }));
        })();
        """)
        _ = try harness.invoke("install", request: harness.request(
            id: 1, adapterId: "recovering-operation", operation: "install", config: ["revision": 1]
        ))
        try harness.evaluate("window.__recoveringAdapterShouldThrow = true")
        let failed = try harness.invoke("update", request: harness.request(
            id: 2, adapterId: "recovering-operation", operation: "update", config: ["revision": 2]
        ))

        XCTAssertEqual((failed["error"] as? [String: Any])?["code"] as? String, "adapter-operation-failed")
        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.performanceSnapshot().observers.find((item) => item.adapterId === 'recovering-operation').qualified === false"))
        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.performanceSnapshot().observers.find((item) => item.adapterId === 'recovering-operation').recoverable === false"))
        XCTAssertEqual(try harness.string("window.__codexAppExtensionV2.performanceSnapshot().observers.find((item) => item.adapterId === 'recovering-operation').failureReason"), "adapter-operation-failed")

        try harness.evaluate("window.__triggerMutation(1); window.__flushRAF(); window.__flushTimers();")
        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.performanceSnapshot().observers.find((item) => item.adapterId === 'recovering-operation').qualified === true"))
        XCTAssertTrue(try harness.value("window.__codexAppExtensionV2.performanceSnapshot().observers.find((item) => item.adapterId === 'recovering-operation').failureReason").isNull)

        try harness.evaluate("window.__recoveringAdapterShouldThrow = false")
        let rolledBack = try harness.invoke("update", request: harness.request(
            id: 3, adapterId: "recovering-operation", operation: "update", config: ["revision": 1]
        ))
        XCTAssertNil(harness.nonNullError(rolledBack))
        XCTAssertEqual((rolledBack["result"] as? [String: Any])?["changed"] as? Bool, true)
        XCTAssertEqual(try harness.int("window.__recoveringAdapterUpdateCount"), 2)

        let repeatedRollback = try harness.invoke("update", request: harness.request(
            id: 4, adapterId: "recovering-operation", operation: "update", config: ["revision": 1]
        ))
        XCTAssertEqual((repeatedRollback["result"] as? [String: Any])?["idempotent"] as? Bool, true)
        XCTAssertEqual(try harness.int("window.__recoveringAdapterUpdateCount"), 2)
    }

    func testUnsupportedAndLegacyFictionalDOMFailOpenForEveryAdapter() throws {
        for fixture in ["unsupported-surface", "legacy-fictional-surface"] {
            let harness = try JSRuntimeHarness(fixture: fixture)
            for adapter in ["wide-layout", "header-offset", "ime-enter-guard", "markdown-semantic-theme"] {
                try harness.loadAdapter(adapter)
                let response = try harness.invoke("install", request: harness.request(
                    id: 10,
                    adapterId: adapter,
                    operation: "install",
                    config: harness.defaultConfig(adapterId: adapter)
                ))
                XCTAssertNil(harness.nonNullError(response), "\(fixture)/\(adapter) 不应抛错")
                XCTAssertEqual((response["result"] as? [String: Any])?["qualified"] as? Bool, false)
            }
            XCTAssertEqual(try harness.int("window.__codexAppExtensionV2.observerCount()"), 4)
        }
    }

    func testFailOpenInstallIsNotCachedAsInstalled() throws {
        let harness = try JSRuntimeHarness(fixture: "unsupported-surface")
        try harness.loadAdapter("wide-layout")
        let request = harness.request(
            id: 1,
            adapterId: "wide-layout",
            operation: "install",
            config: harness.defaultConfig(adapterId: "wide-layout")
        )
        let unsupported = try harness.invoke("install", request: request)
        XCTAssertEqual((unsupported["result"] as? [String: Any])?["qualified"] as? Bool, false)

        try harness.evaluate("document.__loadFixture('<main data-app-shell-main-content-layout></main>')")
        let qualified = try harness.invoke("install", request: request)
        XCTAssertEqual((qualified["result"] as? [String: Any])?["qualified"] as? Bool, true)
        XCTAssertNotEqual((qualified["result"] as? [String: Any])?["idempotent"] as? Bool, true)
        XCTAssertEqual(try harness.string("document.querySelector('.thread-scroll-container').getAttribute('data-cae-wide-layout')"), "true")
    }

    func testDiagnoseStaysUnqualifiedAfterFailedInstallUntilSuccessfulReinstall() throws {
        let harness = try JSRuntimeHarness(fixture: "unsupported-surface")
        try harness.loadAdapter("wide-layout")
        let config = harness.defaultConfig(adapterId: "wide-layout")
        let installRequest = harness.request(id: 1, adapterId: "wide-layout", operation: "install", config: config)
        let failedInstall = try harness.invoke("install", request: installRequest)
        XCTAssertEqual((failedInstall["result"] as? [String: Any])?["qualified"] as? Bool, false)

        try harness.evaluate("document.__loadFixture('<main data-app-shell-main-content-layout></main>')")
        let stateBeforeDiagnose = try harness.string(Self.hostStateExpression)
        let diagnoseBeforeReinstall = try harness.invoke("diagnose", request: harness.request(
            id: 2, adapterId: "wide-layout", operation: "diagnose", config: config
        ))
        XCTAssertEqual((diagnoseBeforeReinstall["result"] as? [String: Any])?["qualified"] as? Bool, false)
        XCTAssertEqual((diagnoseBeforeReinstall["result"] as? [String: Any])?["reason"] as? String, "adapter-not-installed")
        XCTAssertEqual(try harness.string(Self.hostStateExpression), stateBeforeDiagnose)

        let reinstall = try harness.invoke("install", request: installRequest)
        XCTAssertEqual((reinstall["result"] as? [String: Any])?["qualified"] as? Bool, true)
        let diagnoseAfterReinstall = try harness.invoke("diagnose", request: harness.request(
            id: 3, adapterId: "wide-layout", operation: "diagnose", config: config
        ))
        XCTAssertEqual((diagnoseAfterReinstall["result"] as? [String: Any])?["qualified"] as? Bool, true)
    }

    func testEveryAdapterDiagnoseIsReadOnlyAndUninstallNeverReportsHealthy() throws {
        let adapters = ["wide-layout", "header-offset", "ime-enter-guard", "markdown-semantic-theme"]
        for adapter in adapters {
            let harness = try JSRuntimeHarness(fixture: "current-surface")
            try harness.loadAdapter(adapter)
            let config = harness.defaultConfig(adapterId: adapter)
            _ = try harness.invoke("install", request: harness.request(
                id: 1, adapterId: adapter, operation: "install", config: config
            ))

            let installedState = try harness.string(Self.hostStateExpression)
            let healthy = try harness.invoke("diagnose", request: harness.request(
                id: 2, adapterId: adapter, operation: "diagnose", config: config
            ))
            XCTAssertEqual((healthy["result"] as? [String: Any])?["qualified"] as? Bool, true, adapter)
            XCTAssertEqual(try harness.string(Self.hostStateExpression), installedState, adapter)

            _ = try harness.invoke("uninstall", request: harness.request(
                id: 3, adapterId: adapter, operation: "uninstall", config: config
            ))
            let uninstalledState = try harness.string(Self.hostStateExpression)
            let afterUninstall = try harness.invoke("diagnose", request: harness.request(
                id: 4, adapterId: adapter, operation: "diagnose", config: config
            ))
            XCTAssertEqual((afterUninstall["result"] as? [String: Any])?["qualified"] as? Bool, false, adapter)
            XCTAssertEqual((afterUninstall["result"] as? [String: Any])?["reason"] as? String, "adapter-not-installed", adapter)
            XCTAssertEqual(try harness.string(Self.hostStateExpression), uninstalledState, adapter)
        }
    }

    private static let hostStateExpression = #"""
    (() => {
      const layout = document.querySelector('[data-app-shell-main-content-layout]');
      const scroller = document.querySelector('.thread-scroll-container');
      const editor = document.querySelector(".ProseMirror[contenteditable='true']");
      const snapshot = (node) => node ? {
        attributes: { ...node.attributes },
        style: { ...node.style.values },
        listeners: Object.fromEntries(Object.keys(node.listeners).sort().map((name) => [name, node.listenerCount(name)]))
      } : null;
      return JSON.stringify({
        observerCount: window.__codexAppExtensionV2.observerCount(),
        layout: snapshot(layout),
        scroller: snapshot(scroller),
        editor: snapshot(editor),
        styles: document.head.children.map((node) => ({ id: node.id, text: node.textContent }))
      });
    })()
    """#
}

enum JSRuntimeHarnessError: Error {
    case missingResource(String)
    case contextCreationFailed
    case evaluationFailed(String)
    case invalidResponse
}

final class JSRuntimeHarness {
    let context: JSContext
    let fixtureHTML: String

    init(fixture: String) throws {
        guard let context = JSContext() else { throw JSRuntimeHarnessError.contextCreationFailed }
        self.context = context
        let bundle = Bundle(for: PageRuntimeTests.self)
        guard let fixtureURL = bundle.url(forResource: fixture, withExtension: "html") else {
            throw JSRuntimeHarnessError.missingResource(fixture)
        }
        fixtureHTML = try String(contentsOf: fixtureURL, encoding: .utf8)
        try evaluate(Self.fakeDOMSource)
        context.setObject(fixtureHTML, forKeyedSubscript: "__fixtureHTML" as NSString)
        try evaluate("document.__loadFixture(__fixtureHTML)")
        try loadScript(resource: "bootstrap")
    }

    func runtime() throws -> JSValue {
        let runtime = context.objectForKeyedSubscript("window")?.forProperty("__codexAppExtensionV2")
        guard let runtime, !runtime.isUndefined else { throw JSRuntimeHarnessError.invalidResponse }
        return runtime
    }

    func loadAdapter(_ adapterId: String) throws { try loadScript(resource: adapterId) }

    func loadBootstrap() throws { try loadScript(resource: "bootstrap") }

    func request(id: Int, adapterId: String, operation: String, config: [String: Any]) -> [String: Any] {
        [
            "runtimeVersion": 2,
            "requestId": id,
            "adapterId": adapterId,
            "operation": operation,
            "config": config,
            "result": NSNull(),
            "error": NSNull()
        ]
    }

    func invoke(_ method: String, request: [String: Any]) throws -> [String: Any] {
        guard let response = try runtime().invokeMethod(method, withArguments: [request]).toDictionary() else {
            throw JSRuntimeHarnessError.invalidResponse
        }
        return Dictionary(uniqueKeysWithValues: response.compactMap { key, value in
            guard let key = key as? String else { return nil }
            return (key, value)
        })
    }

    func nonNullError(_ response: [String: Any]) -> Any? {
        guard let error = response["error"], !(error is NSNull) else { return nil }
        return error
    }

    func defaultConfig(adapterId: String) -> [String: Any] {
        switch adapterId {
        case "wide-layout": return ["maximumContentWidth": 1_800, "minimumSidePadding": 24]
        case "header-offset": return ["mode": "automatic", "customOffset": 46]
        case "ime-enter-guard": return ["protectCompositionEnter": true]
        case "markdown-semantic-theme":
            return [
                "heading": ["enabled": true, "color": "#F2C94C"],
                "strongText": ["enabled": true, "color": "#F2C94C", "fontWeight": 800],
                "inlineCode": ["textColor": "#DF3079", "backgroundColor": "transparent", "borderColor": "#DF3079"],
                "blockquote": ["borderColor": "#DF3079", "textColor": "inherit", "backgroundColor": "transparent"]
            ]
        default: return [:]
        }
    }

    @discardableResult
    func evaluate(_ source: String) throws -> JSValue {
        context.exception = nil
        let value = context.evaluateScript(source)
        if let exception = context.exception {
            throw JSRuntimeHarnessError.evaluationFailed(exception.toString())
        }
        guard let value else { throw JSRuntimeHarnessError.evaluationFailed("no value") }
        return value
    }

    func value(_ expression: String) throws -> JSValue { try evaluate(expression) }
    func string(_ expression: String) throws -> String { try evaluate(expression).toString() }
    func int(_ expression: String) throws -> Int { Int(try evaluate(expression).toInt32()) }
    func bool(_ expression: String) throws -> Bool { try evaluate(expression).toBool() }

    private func loadScript(resource: String) throws {
        let bundle = Bundle(for: PageRuntimeTests.self)
        guard let url = bundle.url(forResource: resource, withExtension: "js") else {
            throw JSRuntimeHarnessError.missingResource(resource)
        }
        try evaluate(String(contentsOf: url, encoding: .utf8))
    }

    private static let fakeDOMSource = #"""
    var window = this;
    window.CSS = { supports: function() { return true; } };
    (function installFakeDOM() {
      function FakeStyle(owner) { this.owner = owner; this.values = {}; this.priorities = {}; this.writeCounts = {}; }
      FakeStyle.prototype.setProperty = function(name, value, priority) {
        this.values[name] = String(value);
        this.priorities[name] = priority ? String(priority) : '';
        this.writeCounts[name] = (this.writeCounts[name] || 0) + 1;
        if (window.__autoStyleMutation && this.owner) window.__triggerMutation(1);
      };
      FakeStyle.prototype.removeProperty = function(name) {
        const previous = this.values[name] || '';
        delete this.values[name];
        delete this.priorities[name];
        return previous;
      };
      FakeStyle.prototype.getPropertyValue = function(name) { return this.values[name] || ''; };
      FakeStyle.prototype.getPropertyPriority = function(name) { return this.priorities[name] || ''; };
      FakeStyle.prototype.writeCount = function(name) { return this.writeCounts[name] || 0; };

      function FakeNode(name) {
        this.name = name;
        this.attributes = {};
        this.children = [];
        this.parentElement = null;
        this.style = new FakeStyle(this);
        this.listeners = {};
        this.queries = {};
        this.id = '';
        this.textContent = '';
      }
      FakeNode.prototype.setAttribute = function(name, value) { this.attributes[name] = String(value); };
      FakeNode.prototype.getAttribute = function(name) { return Object.prototype.hasOwnProperty.call(this.attributes, name) ? this.attributes[name] : null; };
      FakeNode.prototype.hasAttribute = function(name) { return Object.prototype.hasOwnProperty.call(this.attributes, name); };
      FakeNode.prototype.removeAttribute = function(name) { delete this.attributes[name]; };
      FakeNode.prototype.appendChild = function(node) { node.parentElement = this; this.children.push(node); return node; };
      FakeNode.prototype.remove = function() {
        if (!this.parentElement) return;
        this.parentElement.children = this.parentElement.children.filter((node) => node !== this);
        this.parentElement = null;
      };
      FakeNode.prototype.contains = function(node) {
        if (node === this) return true;
        return this.children.some((child) => child.contains(node));
      };
      FakeNode.prototype.querySelectorAll = function(selector) { return (this.queries[selector] || []).slice(); };
      FakeNode.prototype.querySelector = function(selector) { return this.querySelectorAll(selector)[0] || null; };
      FakeNode.prototype.registerAll = function(selector, nodes) { this.queries[selector] = nodes.slice(); };
      FakeNode.prototype.addEventListener = function(type, callback) { (this.listeners[type] ||= []).push(callback); };
      FakeNode.prototype.removeEventListener = function(type, callback) {
        this.listeners[type] = (this.listeners[type] || []).filter((item) => item !== callback);
      };
      FakeNode.prototype.dispatchEvent = function(event) {
        event.currentTarget = this;
        for (const callback of (this.listeners[event.type] || []).slice()) callback(event);
        return !event.defaultPrevented;
      };
      FakeNode.prototype.listenerCount = function(type) { return (this.listeners[type] || []).length; };

      const document = {
        nodes: {},
        documentElement: new FakeNode('documentElement'),
        head: new FakeNode('head'),
        body: new FakeNode('body'),
        createElement: function(name) { return new FakeNode(name); },
        querySelectorAll: function(selector) { return (this.nodes[selector] || []).slice(); },
        querySelector: function(selector) { return this.querySelectorAll(selector)[0] || null; },
        getElementById: function(id) { return this.head.children.find((node) => node.id === id) || null; },
        __registerAll: function(selector, nodes) { this.nodes[selector] = nodes.slice(); },
        __loadFixture: function(html) {
          this.nodes = {};
          this.documentElement = new FakeNode('documentElement');
          this.head = new FakeNode('head');
          this.body = new FakeNode('body');
          this.documentElement.appendChild(this.head);
          this.documentElement.appendChild(this.body);
          if (!html.includes('data-app-shell-main-content-layout')) return;

          const layout = new FakeNode('layout');
          const scroller = new FakeNode('scroller');
          const markdownOne = new FakeNode('markdownOne');
          const markdownTwo = new FakeNode('markdownTwo');
          const heading = new FakeNode('heading');
          const paragraph = new FakeNode('paragraph');
          const quote = new FakeNode('quote');
          const wideOwner = new FakeNode('wideOwner');
          const composerOwner = new FakeNode('composerOwner');
          const editor = new FakeNode('editor');
          const editorChild = new FakeNode('editorChild');
          const rail = new FakeNode('rail');
          const menu = new FakeNode('menu');
          const requestInput = new FakeNode('requestInput');

          layout.setAttribute('data-app-shell-main-content-layout', '');
          layout.style.setProperty('--app-shell-main-content-frame-top-offset', '46px');
          layout.style.setProperty('--inset-toolbar', '46px');
          layout.style.setProperty('--height-toolbar', '46px');
          editor.setAttribute('class', 'ProseMirror');
          editor.setAttribute('contenteditable', 'true');
          editor.setAttribute('data-codex-composer', 'true');
          wideOwner.setAttribute('class', 'mx-auto max-w-(--thread-content-max-width)');
          composerOwner.setAttribute('class', 'mx-auto max-w-(--thread-composer-max-width)');
          scroller.appendChild(markdownOne);
          scroller.appendChild(markdownTwo);
          scroller.appendChild(wideOwner);
          scroller.registerAll("[class*='thread-content-max-width']", [wideOwner]);
          scroller.registerAll("[class*='thread-composer-max-width']", []);
          markdownOne.appendChild(heading);
          markdownOne.appendChild(paragraph);
          markdownOne.appendChild(quote);
          editor.appendChild(editorChild);
          const emptyTask = html.includes('data-empty-task');
          if (emptyTask) {
            composerOwner.appendChild(editor);
            layout.appendChild(composerOwner);
            layout.registerAll("[class*='thread-content-max-width']", []);
            layout.registerAll("[class*='thread-composer-max-width']", [composerOwner]);
          } else {
            layout.appendChild(scroller);
            layout.appendChild(editor);
          }
          layout.appendChild(rail);
          layout.appendChild(requestInput);
          layout.appendChild(menu);
          this.body.appendChild(layout);

          const editorMatches = [editor];
          if (html.includes('data-duplicate-editor')) {
            const duplicate = new FakeNode('duplicateEditor');
            duplicate.setAttribute('class', 'ProseMirror');
            duplicate.setAttribute('contenteditable', 'true');
            duplicate.setAttribute('data-codex-composer', 'true');
            layout.appendChild(duplicate);
            editorMatches.push(duplicate);
          }

          scroller.registerAll('[data-selected-text-overlay-target]', [markdownOne, markdownTwo]);
          this.__registerAll('[data-app-shell-main-content-layout]', [layout]);
          this.__registerAll('.thread-scroll-container', emptyTask ? [] : [scroller]);
          this.__registerAll(".ProseMirror[data-codex-composer='true'][contenteditable='true'], .ProseMirror[data-codex-composer='true'][contenteditable='plaintext-only']", editorMatches);
          this.__registerAll(".ProseMirror[contenteditable='true'], .ProseMirror[contenteditable='plaintext-only']", editorMatches);
          this.__registerAll('.ProseMirror', editorMatches);
          this.__registerAll(".ProseMirror[contenteditable='true']", editorMatches);
          this.__registerAll(".ProseMirror[contenteditable='plaintext-only']", []);
          this.__registerAll('[data-codex-composer]', [editor]);
          this.__registerAll('[data-selected-text-overlay-target]', emptyTask ? [] : [markdownOne, markdownTwo]);
          this.__registerAll('[data-editor-child]', [editorChild]);
          this.__registerAll('[data-testid="right-rail"]', [rail]);
          this.__registerAll("[role='menu']", [menu]);
          this.__registerAll('[data-request-input]', [requestInput]);
        },
        __setSurfaceMode: function(mode) {
          const layout = this.querySelector('[data-app-shell-main-content-layout]');
          const editor = this.querySelector(".ProseMirror[data-codex-composer='true'][contenteditable='true'], .ProseMirror[data-codex-composer='true'][contenteditable='plaintext-only']");
          const currentScroller = this.querySelector('.thread-scroll-container');
          if (!layout || !editor) return;

          if (mode === 'empty-task') {
            currentScroller?.remove();
            const composerOwner = new FakeNode('composerOwner-transition');
            composerOwner.setAttribute('class', 'mx-auto max-w-(--thread-composer-max-width)');
            editor.remove();
            composerOwner.appendChild(editor);
            layout.appendChild(composerOwner);
            layout.registerAll("[class*='thread-content-max-width']", []);
            layout.registerAll("[class*='thread-composer-max-width']", [composerOwner]);
            this.__registerAll('.thread-scroll-container', []);
            this.__registerAll('[data-selected-text-overlay-target]', []);
            return;
          }

          if (mode === 'session' && !currentScroller) {
            const composerOwner = editor.parentElement;
            editor.remove();
            composerOwner?.remove();
            const scroller = new FakeNode('scroller-transition');
            const markdownOne = new FakeNode('scroller-transition-markdownOne');
            const markdownTwo = new FakeNode('scroller-transition-markdownTwo');
            const wideOwner = new FakeNode('scroller-transition-wideOwner');
            wideOwner.setAttribute('class', 'mx-auto max-w-(--thread-content-max-width)');
            scroller.appendChild(markdownOne);
            scroller.appendChild(markdownTwo);
            scroller.appendChild(wideOwner);
            scroller.registerAll('[data-selected-text-overlay-target]', [markdownOne, markdownTwo]);
            scroller.registerAll("[class*='thread-content-max-width']", [wideOwner]);
            scroller.registerAll("[class*='thread-composer-max-width']", []);
            layout.registerAll("[class*='thread-content-max-width']", []);
            layout.registerAll("[class*='thread-composer-max-width']", []);
            layout.appendChild(scroller);
            layout.appendChild(editor);
            this.__registerAll('.thread-scroll-container', [scroller]);
            this.__registerAll('[data-selected-text-overlay-target]', [markdownOne, markdownTwo]);
          }
        },
        __replaceSurface: function(part) {
          const currentLayout = this.querySelector('[data-app-shell-main-content-layout]');
          const currentScroller = this.querySelector('.thread-scroll-container');
          const currentEditor = this.querySelector(".ProseMirror[contenteditable='true'], .ProseMirror[contenteditable='plaintext-only']");
          const makeScroller = function(name) {
            const scroller = new FakeNode(name);
            const markdownOne = new FakeNode(name + '-markdownOne');
            const markdownTwo = new FakeNode(name + '-markdownTwo');
            const wideOwner = new FakeNode(name + '-wideOwner');
            wideOwner.setAttribute('class', 'mx-auto max-w-(--thread-content-max-width)');
            scroller.appendChild(markdownOne);
            scroller.appendChild(markdownTwo);
            scroller.appendChild(wideOwner);
            scroller.registerAll('[data-selected-text-overlay-target]', [markdownOne, markdownTwo]);
            scroller.registerAll("[class*='thread-content-max-width']", [wideOwner]);
            scroller.registerAll("[class*='thread-composer-max-width']", []);
            return { scroller, markdown: [markdownOne, markdownTwo] };
          };
          const makeEditor = function(name) {
            const editor = new FakeNode(name);
            const child = new FakeNode(name + '-child');
            editor.setAttribute('class', 'ProseMirror');
            editor.setAttribute('contenteditable', 'true');
            editor.setAttribute('data-codex-composer', 'true');
            editor.appendChild(child);
            return { editor, child };
          };

          let nextLayout = currentLayout;
          let nextScroller = currentScroller;
          let nextEditor = currentEditor;
          let markdown = currentScroller?.querySelectorAll('[data-selected-text-overlay-target]') ?? [];
          let editorChild = currentEditor?.children[0] ?? null;
          if (part === 'layout') {
            nextLayout = new FakeNode('layout-replacement');
            nextLayout.setAttribute('data-app-shell-main-content-layout', '');
            nextLayout.style.setProperty('--app-shell-main-content-frame-top-offset', '46px');
            const madeScroller = makeScroller('scroller-replacement');
            const madeEditor = makeEditor('editor-replacement');
            nextScroller = madeScroller.scroller;
            markdown = madeScroller.markdown;
            nextEditor = madeEditor.editor;
            editorChild = madeEditor.child;
            nextLayout.appendChild(nextScroller);
            nextLayout.appendChild(nextEditor);
            currentLayout?.remove();
            this.body.appendChild(nextLayout);
          } else if (part === 'scroller') {
            const madeScroller = makeScroller('scroller-replacement');
            nextScroller = madeScroller.scroller;
            markdown = madeScroller.markdown;
            currentScroller?.remove();
            currentLayout.appendChild(nextScroller);
          } else if (part === 'editor') {
            const madeEditor = makeEditor('editor-replacement');
            nextEditor = madeEditor.editor;
            editorChild = madeEditor.child;
            currentEditor?.remove();
            currentLayout.appendChild(nextEditor);
          }

          this.__registerAll('[data-app-shell-main-content-layout]', [nextLayout]);
          this.__registerAll('.thread-scroll-container', [nextScroller]);
          this.__registerAll(".ProseMirror[data-codex-composer='true'][contenteditable='true'], .ProseMirror[data-codex-composer='true'][contenteditable='plaintext-only']", [nextEditor]);
          this.__registerAll(".ProseMirror[contenteditable='true'], .ProseMirror[contenteditable='plaintext-only']", [nextEditor]);
          this.__registerAll('.ProseMirror', [nextEditor]);
          this.__registerAll(".ProseMirror[contenteditable='true']", [nextEditor]);
          this.__registerAll(".ProseMirror[contenteditable='plaintext-only']", []);
          this.__registerAll('[data-codex-composer]', [nextEditor]);
          this.__registerAll('[data-selected-text-overlay-target]', markdown);
          this.__registerAll('[data-editor-child]', editorChild ? [editorChild] : []);
        },
        __event: function(type, target, values) {
          return Object.assign({
            type: type,
            target: target,
            key: '',
            keyCode: 0,
            isComposing: false,
            defaultPrevented: false,
            immediatePropagationStopped: false,
            preventDefault: function() { this.defaultPrevented = true; },
            stopImmediatePropagation: function() { this.immediatePropagationStopped = true; }
          }, values || {});
        }
      };
      window.document = document;
      window.getComputedStyle = function(node) { return node.style; };
      window.__FakeNode = FakeNode;
      window.__autoStyleMutation = false;
      window.__now = 1_000;
      Date.now = function() { return window.__now; };
      window.__rafQueue = [];
      window.__timerQueue = [];
      window.__nextScheduleId = 1;
      window.requestAnimationFrame = function(callback) {
        const item = { id: window.__nextScheduleId++, callback: callback };
        window.__rafQueue.push(item);
        return item.id;
      };
      window.cancelAnimationFrame = function(id) { window.__rafQueue = window.__rafQueue.filter((item) => item.id !== id); };
      window.setTimeout = function(callback) {
        const item = { id: window.__nextScheduleId++, callback: callback };
        window.__timerQueue.push(item);
        return item.id;
      };
      window.clearTimeout = function(id) { window.__timerQueue = window.__timerQueue.filter((item) => item.id !== id); };
      window.__flushRAF = function() { const queue = window.__rafQueue.splice(0); queue.forEach((item) => item.callback()); };
      window.__flushTimers = function() { const queue = window.__timerQueue.splice(0); queue.forEach((item) => item.callback()); };
      window.__mutationObservers = [];
      window.MutationObserver = function(callback) {
        this.callback = callback;
        this.targets = [];
        this.disconnected = false;
        window.__mutationObservers.push(this);
      };
      window.MutationObserver.prototype.observe = function(target, options) {
        this.disconnected = false;
        this.targets.push(target);
        (this.options ||= []).push(options || {});
      };
      window.MutationObserver.prototype.disconnect = function() { this.disconnected = true; this.targets = []; };
      window.__dispatchObservedAttribute = function(node, attributeName) {
        window.__mutationObservers
          .filter((observer) => !observer.disconnected)
          .forEach((observer) => observer.targets.forEach((target, index) => {
            const optionOffset = Math.max(0, (observer.options?.length || 0) - observer.targets.length);
            const options = observer.options?.[optionOffset + index] || {};
            const inScope = target === node || (options.subtree === true && target.contains(node));
            const attributeAllowed = !Array.isArray(options.attributeFilter) ||
              options.attributeFilter.includes(attributeName);
            if (options.attributes === true && inScope && attributeAllowed) {
              observer.callback([{ type: 'attributes', target: node, attributeName }]);
            }
          }));
      };
      window.__triggerMutation = function(count) {
        for (let index = 0; index < count; index += 1) {
          window.__mutationObservers
            .filter((item) => !item.disconnected && item.targets.some((target) =>
              target === document.documentElement || target?.name === 'documentElement'))
            .forEach((item) => item.callback([{ type: 'childList', target: document.body }]));
        }
      };
    })();
    """#
}
