import AppKit
import Foundation
import WebKit
import XCTest
@testable import ExtensionCore

private final class WebKitFixtureNavigationDelegate: NSObject, WKNavigationDelegate {
    let expectation: XCTestExpectation
    private(set) var error: Error?

    init(expectation: XCTestExpectation) {
        self.expectation = expectation
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        expectation.fulfill()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.error = error
        expectation.fulfill()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        self.error = error
        expectation.fulfill()
    }
}

final class AdapterFixtureTests: XCTestCase {
    func testWideLayoutPrimesScrollerWhileWidthOwnersAreTemporarilyMissing() throws {
        let harness = try JSRuntimeHarness(fixture: "current-surface")
        try harness.evaluate("""
        (() => {
          const scroller = document.querySelector('.thread-scroll-container');
          const selector = "[class*='thread-content-max-width']";
          const owner = scroller.querySelectorAll(selector)[0];
          window.__pendingWideOwner = owner;
          owner.remove();
          scroller.registerAll(selector, []);
          scroller.registerAll("[class*='thread-composer-max-width']", []);
        })();
        """)
        try harness.loadAdapter("wide-layout")

        let installed = try harness.invoke("install", request: harness.request(
            id: 1,
            adapterId: "wide-layout",
            operation: "install",
            config: harness.defaultConfig(adapterId: "wide-layout")
        ))
        let installedResult = try XCTUnwrap(installed["result"] as? [String: Any])
        XCTAssertEqual(installedResult["qualified"] as? Bool, false)
        XCTAssertEqual(installedResult["recoverable"] as? Bool, true)
        XCTAssertEqual(
            try harness.string("document.querySelector('.thread-scroll-container').getAttribute('data-cae-wide-layout')"),
            "true"
        )
        XCTAssertEqual(
            try harness.string("document.querySelector('.thread-scroll-container').style.getPropertyValue('--thread-content-max-width')"),
            "min(1800px, max(1px, calc(100% - 48px)))"
        )
        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.performanceSnapshot().observers.find((item) => item.adapterId === 'wide-layout').qualified === false"))
        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.performanceSnapshot().observers.find((item) => item.adapterId === 'wide-layout').recoverable === true"))

        let primedDiagnosis = try harness.invoke("diagnose", request: harness.request(
            id: 2, adapterId: "wide-layout", operation: "diagnose", config: [:]
        ))
        XCTAssertEqual((primedDiagnosis["result"] as? [String: Any])?["qualified"] as? Bool, false)
        XCTAssertEqual((primedDiagnosis["result"] as? [String: Any])?["recoverable"] as? Bool, true)

        try harness.evaluate("""
        window.__triggerMutation(1);
        window.__flushRAF();
        window.__flushTimers();
        window.__triggerMutation(1);
        window.__flushRAF();
        window.__flushTimers();
        """)
        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.performanceSnapshot().observers.find((item) => item.adapterId === 'wide-layout').qualified === false"))
        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.performanceSnapshot().observers.find((item) => item.adapterId === 'wide-layout').recoverable === true"))
        XCTAssertEqual(
            try harness.string("document.querySelector('.thread-scroll-container').style.getPropertyValue('--thread-content-max-width')"),
            "min(1800px, max(1px, calc(100% - 48px)))"
        )

        try harness.evaluate("""
        (() => {
          const scroller = document.querySelector('.thread-scroll-container');
          scroller.appendChild(window.__pendingWideOwner);
          scroller.registerAll("[class*='thread-content-max-width']", [window.__pendingWideOwner]);
          window.__triggerMutation(1);
          window.__flushRAF();
          window.__flushTimers();
        })();
        """)
        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.performanceSnapshot().observers.find((item) => item.adapterId === 'wide-layout').qualified === true"))
        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.performanceSnapshot().observers.find((item) => item.adapterId === 'wide-layout').recoverable === false"))
        XCTAssertEqual(
            try harness.string("document.querySelector('.thread-scroll-container').style.getPropertyValue('--thread-content-max-width')"),
            "min(1800px, max(1px, calc(100% - 48px)))"
        )

        _ = try harness.invoke("uninstall", request: harness.request(
            id: 3, adapterId: "wide-layout", operation: "uninstall", config: [:]
        ))
        XCTAssertTrue(try harness.value("document.querySelector('.thread-scroll-container').getAttribute('data-cae-wide-layout')").isNull)
        XCTAssertEqual(try harness.string("document.querySelector('.thread-scroll-container').style.getPropertyValue('--thread-content-max-width')"), "")
    }

    func testWideLayoutRecognizesReusedOwnerWhenOnlyItsClassChanges() throws {
        let harness = try JSRuntimeHarness(fixture: "current-surface")
        try harness.evaluate("""
        (() => {
          const scroller = document.querySelector('.thread-scroll-container');
          const owner = scroller.querySelectorAll("[class*='thread-content-max-width']")[0];
          const editor = document.querySelector(".ProseMirror[contenteditable='true']");
          owner.setAttribute('class', 'pending-composer-shell');
          editor.remove();
          owner.appendChild(editor);
          scroller.registerAll("[class*='thread-content-max-width']", []);
          scroller.registerAll("[class*='thread-composer-max-width']", []);
          window.__reusedPendingOwner = owner;
          window.__dispatchObservedAttribute = (node, attributeName) => {
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
        })();
        """)
        try harness.loadAdapter("wide-layout")

        let installed = try harness.invoke("install", request: harness.request(
            id: 1,
            adapterId: "wide-layout",
            operation: "install",
            config: harness.defaultConfig(adapterId: "wide-layout")
        ))
        let installedResult = try XCTUnwrap(installed["result"] as? [String: Any])
        XCTAssertEqual(installedResult["qualified"] as? Bool, false)
        XCTAssertEqual(installedResult["recoverable"] as? Bool, true)
        XCTAssertEqual(installedResult["reason"] as? String, "wide-content-candidate-pending")
        XCTAssertEqual(
            try harness.string("document.querySelector('.thread-scroll-container').style.getPropertyValue('--thread-content-max-width')"),
            "min(1800px, max(1px, calc(100% - 48px)))"
        )
        XCTAssertTrue(try harness.bool("window.__mutationObservers.some((observer) => !observer.disconnected && observer.targets.includes(window.__reusedPendingOwner))"))
        XCTAssertTrue(try harness.bool("""
        window.__mutationObservers.some((observer) => {
          if (observer.disconnected) return false;
          const index = observer.targets.indexOf(window.__reusedPendingOwner);
          if (index < 0) return false;
          const optionOffset = Math.max(0, (observer.options?.length || 0) - observer.targets.length);
          const options = observer.options?.[optionOffset + index] || {};
          return options.attributes === true &&
            options.subtree !== true &&
            JSON.stringify(options.attributeFilter) === JSON.stringify(['class']);
        })
        """))

        try harness.evaluate("""
        (() => {
          const scroller = document.querySelector('.thread-scroll-container');
          window.__reusedPendingOwner.setAttribute('class', 'mx-auto max-w-(--thread-composer-max-width)');
          scroller.registerAll("[class*='thread-composer-max-width']", [window.__reusedPendingOwner]);
          window.__dispatchObservedAttribute(window.__reusedPendingOwner, 'class');
        })();
        """)
        XCTAssertEqual(try harness.int("window.__rafQueue.length"), 1)
        try harness.evaluate("window.__flushRAF(); window.__flushTimers();")

        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.performanceSnapshot().observers.find((item) => item.adapterId === 'wide-layout').qualified === true"))
        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.performanceSnapshot().observers.find((item) => item.adapterId === 'wide-layout').recoverable === false"))
        XCTAssertEqual(
            try harness.string("document.querySelector('.thread-scroll-container').style.getPropertyValue('--thread-composer-max-width')"),
            "min(1800px, max(1px, calc(100% - 48px)))"
        )
        XCTAssertEqual(
            try harness.string("window.__reusedPendingOwner.style.getPropertyValue('--cae-wide-layout-owner-offset-x')"),
            "0px"
        )

        try harness.evaluate("""
        (() => {
          const scroller = document.querySelector('.thread-scroll-container');
          window.__reusedPendingOwner.setAttribute('class', 'pending-composer-shell');
          scroller.registerAll("[class*='thread-composer-max-width']", []);
          window.__dispatchObservedAttribute(window.__reusedPendingOwner, 'class');
        })();
        """)
        XCTAssertEqual(try harness.int("window.__rafQueue.length"), 1)
        try harness.evaluate("window.__flushRAF(); window.__flushTimers();")
        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.performanceSnapshot().observers.find((item) => item.adapterId === 'wide-layout').qualified === false"))
        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.performanceSnapshot().observers.find((item) => item.adapterId === 'wide-layout').recoverable === true"))
        XCTAssertEqual(
            try harness.string("document.querySelector('.thread-scroll-container').style.getPropertyValue('--thread-content-max-width')"),
            "min(1800px, max(1px, calc(100% - 48px)))"
        )
        XCTAssertEqual(try harness.string("window.__reusedPendingOwner.style.getPropertyValue('--cae-wide-layout-owner-offset-x')"), "")

        try harness.evaluate("""
        (() => {
          const scroller = document.querySelector('.thread-scroll-container');
          window.__reusedPendingOwner.setAttribute('class', 'mx-auto max-w-(--thread-composer-max-width)');
          scroller.registerAll("[class*='thread-composer-max-width']", [window.__reusedPendingOwner]);
          window.__dispatchObservedAttribute(window.__reusedPendingOwner, 'class');
        })();
        """)
        XCTAssertEqual(try harness.int("window.__rafQueue.length"), 1)
        try harness.evaluate("window.__flushRAF(); window.__flushTimers();")
        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.performanceSnapshot().observers.find((item) => item.adapterId === 'wide-layout').qualified === true"))
        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.performanceSnapshot().observers.find((item) => item.adapterId === 'wide-layout').recoverable === false"))
        XCTAssertEqual(try harness.string("window.__reusedPendingOwner.style.getPropertyValue('--cae-wide-layout-owner-offset-x')"), "0px")

        _ = try harness.invoke("uninstall", request: harness.request(
            id: 2, adapterId: "wide-layout", operation: "uninstall", config: [:]
        ))
        XCTAssertEqual(try harness.string("window.__reusedPendingOwner.style.getPropertyValue('--cae-wide-layout-owner-offset-x')"), "")
        XCTAssertTrue(try harness.bool("window.__mutationObservers.every((observer) => observer.disconnected)"))
        XCTAssertEqual(try harness.int("window.__rafQueue.length"), 0)
        XCTAssertEqual(try harness.int("window.__timerQueue.length"), 0)
    }

    func testWideLayoutUsesNativeVariablesAndRestoresHostValues() throws {
        let harness = try JSRuntimeHarness(fixture: "current-surface")
        try addSyntheticWideOwner(to: harness)
        XCTAssertTrue(harness.fixtureHTML.contains("thread-scroll-container"))
        XCTAssertTrue(harness.fixtureHTML.contains("data-testid=\"right-rail\""))
        XCTAssertTrue(harness.fixtureHTML.contains("data-markdown-table"))
        try harness.evaluate("""
        (() => {
          const scroller = document.querySelector('.thread-scroll-container');
          scroller.setAttribute('data-cae-wide-layout', 'host-wide');
          scroller.style.setProperty('--thread-content-max-width', '900px', 'important');
          scroller.style.setProperty('--markdown-wide-block-max-width', '880px');
          scroller.style.setProperty('--cae-wide-layout-side-padding', '7px');
          document.querySelector(".ProseMirror[contenteditable='true']").style.setProperty('--thread-composer-max-width', '700px');
          const style = document.createElement('style');
          style.id = 'cae-wide-layout-style';
          style.textContent = 'host-wide-style';
          document.head.appendChild(style);
        })();
        """)
        try harness.loadAdapter("wide-layout")

        let installed = try harness.invoke("install", request: harness.request(
            id: 1,
            adapterId: "wide-layout",
            operation: "install",
            config: ["maximumContentWidth": 1_720, "minimumSidePadding": 28]
        ))
        XCTAssertNil(harness.nonNullError(installed))
        XCTAssertEqual((installed["result"] as? [String: Any])?["changed"] as? Bool, true)
        XCTAssertEqual(
            (installed["result"] as? [String: Any])?["effectiveWidth"] as? String,
            "min(1720px, max(1px, calc(100% - 56px)))"
        )
        XCTAssertEqual(try harness.string("document.querySelector('.thread-scroll-container').getAttribute('data-cae-wide-layout')"), "true")
        XCTAssertEqual(try harness.string("document.querySelector('.thread-scroll-container').style.getPropertyValue('--thread-content-max-width')"), "min(1720px, max(1px, calc(100% - 56px)))")
        XCTAssertEqual(try harness.string("document.querySelector('.thread-scroll-container').style.getPropertyValue('--thread-composer-max-width')"), "min(1720px, max(1px, calc(100% - 56px)))")
        XCTAssertEqual(try harness.string("document.querySelector('.thread-scroll-container').style.getPropertyValue('--markdown-wide-block-max-width')"), "min(1720px, max(1px, calc(100% - 56px)))")
        XCTAssertEqual(try harness.string("document.querySelector('.thread-scroll-container').style.getPropertyValue('--cae-wide-layout-side-padding')"), "28px")
        XCTAssertEqual(try harness.string("document.querySelector('.thread-scroll-container').style.getPropertyValue('--cae-wide-layout-content-offset-x')"), "0px")
        let css = try harness.string("document.getElementById('cae-wide-layout-style').textContent")
        XCTAssertTrue(css.contains(".thread-scroll-container[data-cae-wide-layout='true']"))
        XCTAssertTrue(css.contains("[class*='thread-content-max-width']"))
        XCTAssertTrue(css.contains("[class*='thread-composer-max-width']"))
        XCTAssertTrue(css.contains("[class*='markdown-wide-block-max-width']"))
        XCTAssertTrue(css.contains("[data-selected-text-overlay-target]"))
        XCTAssertTrue(css.contains("[data-selected-text-overlay-target] [data-markdown-table]:not([role='menu']"))
        XCTAssertTrue(css.contains("inline-size: 100% !important"))
        XCTAssertTrue(css.contains("max-inline-size: 100% !important"))
        XCTAssertTrue(css.contains("margin-inline: 0 !important"))
        XCTAssertTrue(css.contains("[data-markdown-table]:not([role='menu']"))
        XCTAssertTrue(css.contains(":has(table:not([role='menu']"))
        XCTAssertTrue(css.contains("[role='listbox'] *"))
        XCTAssertTrue(css.contains("[role='dialog'] *"))
        XCTAssertTrue(css.contains("overflow-x: auto !important"))
        XCTAssertTrue(css.contains("overscroll-behavior-inline: contain"))
        XCTAssertFalse(css.contains("_tableScroller_"))
        XCTAssertFalse(css.contains("[data-selected-text-overlay-target] {"))
        XCTAssertFalse(css.contains("[data-selected-text-overlay-target] {\n  overflow-x:"))
        XCTAssertFalse(css.contains(" table {\n  width:"))
        XCTAssertFalse(css.contains("\n.thread-scroll-container[data-cae-wide-layout='true'] [class*='markdown-wide-block-max-width']"))
        XCTAssertFalse(css.contains("\n.thread-scroll-container[data-cae-wide-layout='true'] [data-selected-text-overlay-target] {"))
        XCTAssertTrue(css.contains("max-width: var(--thread-content-max-width) !important"))
        XCTAssertTrue(css.contains("translate: var(--cae-wide-layout-owner-offset-x, var(--cae-wide-layout-content-offset-x)) 0 !important"))
        XCTAssertTrue(css.contains(".ProseMirror[contenteditable='true'] *"))
        XCTAssertTrue(css.contains("[role='menu'] *"))
        XCTAssertTrue(css.contains("[role='listbox'] *"))
        XCTAssertTrue(css.contains("[class*='thread-floating-content'] *"))
        XCTAssertFalse(css.contains("padding-inline:"))
        XCTAssertEqual(css.components(separatedBy: "margin-inline:").count - 1, 1)
        XCTAssertEqual(try harness.string("document.querySelector(\".ProseMirror[contenteditable='true']\").style.getPropertyValue('--thread-composer-max-width')"), "700px")
        XCTAssertFalse(try harness.bool("document.querySelector('[data-testid=\"right-rail\"]').hasAttribute('data-cae-wide-layout')"))
        XCTAssertFalse(try harness.bool("document.querySelector(\"[role='menu']\").hasAttribute('data-cae-wide-layout')"))

        _ = try harness.invoke("uninstall", request: harness.request(
            id: 2, adapterId: "wide-layout", operation: "uninstall", config: [:]
        ))
        XCTAssertEqual(try harness.string("document.querySelector('.thread-scroll-container').getAttribute('data-cae-wide-layout')"), "host-wide")
        XCTAssertEqual(try harness.string("document.querySelector('.thread-scroll-container').style.getPropertyValue('--thread-content-max-width')"), "900px")
        XCTAssertEqual(try harness.string("document.querySelector('.thread-scroll-container').style.getPropertyPriority('--thread-content-max-width')"), "important")
        XCTAssertEqual(try harness.string("document.querySelector('.thread-scroll-container').style.getPropertyValue('--markdown-wide-block-max-width')"), "880px")
        XCTAssertEqual(try harness.string("document.querySelector('.thread-scroll-container').style.getPropertyValue('--cae-wide-layout-side-padding')"), "7px")
        XCTAssertEqual(try harness.string("document.querySelector('.thread-scroll-container').style.getPropertyValue('--thread-composer-max-width')"), "")
        XCTAssertEqual(try harness.string("document.querySelector('.thread-scroll-container').style.getPropertyValue('--cae-wide-layout-content-offset-x')"), "")
        XCTAssertEqual(try harness.string("document.getElementById('cae-wide-layout-style').textContent"), "host-wide-style")
        XCTAssertEqual(try harness.int("window.__codexAppExtensionV2.observerCount()"), 0)
    }

    @MainActor
    func testWideLayoutMarkdownTableContainmentUsesRealWebKitGeometryAndRestoresNativeLayout() throws {
        let harness = try JSRuntimeHarness(fixture: "current-surface")
        try addSyntheticWideOwner(to: harness)
        try harness.loadAdapter("wide-layout")
        _ = try harness.invoke("install", request: harness.request(
            id: 1,
            adapterId: "wide-layout",
            operation: "install",
            config: ["maximumContentWidth": 560, "minimumSidePadding": 20]
        ))
        let extensionCSS = try harness.string("document.getElementById('cae-wide-layout-style').textContent")
            .replacingOccurrences(of: "</style", with: "<\\/style", options: .caseInsensitive)

        let html = """
        <!doctype html>
        <html>
          <head>
            <meta charset="utf-8">
            <style>
              html, body { margin: 0; padding: 0; width: 100%; }
              body { width: 620px; }
              .thread-scroll-container {
                box-sizing: border-box;
                width: 600px;
                overflow-x: auto;
                --thread-content-max-width: 560px;
                --thread-composer-max-width: 560px;
                --markdown-wide-block-max-width: 560px;
                --cae-wide-layout-content-offset-x: 0px;
              }
              .thread-content-max-width-shell { box-sizing: border-box; width: 560px; margin-inline: auto; }
              [data-selected-text-overlay-target] { box-sizing: border-box; width: 100%; }
              [data-markdown-table] {
                box-sizing: border-box;
                width: calc(100% + 48px);
                max-width: none;
                margin-inline: -24px;
              }
              .native-wide-block {
                box-sizing: border-box;
                width: 900px;
                max-width: none;
                overflow-x: visible;
              }
              .native-narrow-block {
                box-sizing: border-box;
                width: 100%;
                max-width: none;
                overflow-x: visible;
              }
              #wide-table { width: 900px; min-width: 900px; }
              #narrow-table { width: 240px; min-width: 240px; }
              [role='dialog'] { position: fixed; top: 8px; right: 8px; width: 260px; }
            </style>
            <style id="extension-style">\(extensionCSS)</style>
          </head>
          <body>
            <main class="thread-scroll-container" data-cae-wide-layout="true">
              <div id="content" class="thread-content-max-width-shell">
                <article id="markdown" data-selected-text-overlay-target>
                  <div id="wide-shell" data-markdown-table>
                    <div id="wide-scroll" class="native-wide-block">
                      <table id="wide-table"><tr><td>wide</td><td>table</td></tr></table>
                    </div>
                  </div>
                  <div id="narrow-shell" data-markdown-table>
                    <div id="narrow-scroll" class="native-narrow-block">
                      <table id="narrow-table"><tr><td>narrow</td></tr></table>
                    </div>
                  </div>
                  <section role="dialog">
                    <div id="dialog-shell" data-markdown-table>
                      <div id="dialog-table-body" class="native-wide-block">
                        <table><tr><td>dialog</td></tr></table>
                      </div>
                    </div>
                  </section>
                </article>
              </div>
            </main>
          </body>
        </html>
        """

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 640, height: 480))
        let loaded = expectation(description: "WebKit fixture loaded")
        let navigationDelegate = WebKitFixtureNavigationDelegate(expectation: loaded)
        webView.navigationDelegate = navigationDelegate
        webView.loadHTMLString(html, baseURL: nil)
        wait(for: [loaded], timeout: 10)
        if let error = navigationDelegate.error {
            throw error
        }

        let applied = try evaluateWebKitJSON(
            """
            (() => {
              const rect = (id) => document.getElementById(id).getBoundingClientRect();
              const width = (id) => rect(id).width;
              const style = (id) => getComputedStyle(document.getElementById(id));
              const wideScroll = document.getElementById('wide-scroll');
              const narrowScroll = document.getElementById('narrow-scroll');
              const markdown = document.getElementById('markdown');
              const thread = document.querySelector('.thread-scroll-container');
              return JSON.stringify({
                contentWidth: width('content'),
                wideShellWidth: width('wide-shell'),
                wideShellMarginLeft: parseFloat(style('wide-shell').marginLeft),
                wideScrollerClientWidth: wideScroll.clientWidth,
                wideScrollerScrollWidth: wideScroll.scrollWidth,
                wideScrollerOverflowX: style('wide-scroll').overflowX,
                wideTableWidth: width('wide-table'),
                narrowScrollerClientWidth: narrowScroll.clientWidth,
                narrowScrollerScrollWidth: narrowScroll.scrollWidth,
                narrowTableWidth: width('narrow-table'),
                markdownClientWidth: markdown.clientWidth,
                markdownScrollWidth: markdown.scrollWidth,
                threadClientWidth: thread.clientWidth,
                threadScrollWidth: thread.scrollWidth,
                pageClientWidth: document.documentElement.clientWidth,
                pageScrollWidth: document.documentElement.scrollWidth,
                dialogShellWidth: width('dialog-shell'),
                dialogWidth: document.querySelector("[role='dialog']").getBoundingClientRect().width,
                dialogShellMarginLeft: parseFloat(style('dialog-shell').marginLeft),
                dialogBodyOverflowX: style('dialog-table-body').overflowX
              });
            })()
            """,
            in: webView
        )

        XCTAssertEqual(try number("wideShellWidth", in: applied), try number("contentWidth", in: applied), accuracy: 1)
        XCTAssertEqual(try number("wideShellMarginLeft", in: applied), 0, accuracy: 0.1)
        XCTAssertGreaterThan(try number("wideScrollerScrollWidth", in: applied), try number("wideScrollerClientWidth", in: applied))
        XCTAssertEqual(applied["wideScrollerOverflowX"] as? String, "auto")
        XCTAssertEqual(try number("wideTableWidth", in: applied), 900, accuracy: 1)
        XCTAssertEqual(try number("narrowScrollerScrollWidth", in: applied), try number("narrowScrollerClientWidth", in: applied), accuracy: 1)
        XCTAssertEqual(try number("narrowTableWidth", in: applied), 240, accuracy: 1)
        XCTAssertLessThanOrEqual(try number("markdownScrollWidth", in: applied), try number("markdownClientWidth", in: applied) + 1)
        XCTAssertLessThanOrEqual(try number("threadScrollWidth", in: applied), try number("threadClientWidth", in: applied) + 1)
        XCTAssertLessThanOrEqual(try number("pageScrollWidth", in: applied), try number("pageClientWidth", in: applied) + 1)
        XCTAssertGreaterThan(try number("dialogShellWidth", in: applied), try number("dialogWidth", in: applied))
        XCTAssertEqual(try number("dialogShellMarginLeft", in: applied), -24, accuracy: 0.1)
        XCTAssertEqual(applied["dialogBodyOverflowX"] as? String, "visible")

        let restored = try evaluateWebKitJSON(
            """
            (() => {
              document.getElementById('extension-style').remove();
              const rect = (id) => document.getElementById(id).getBoundingClientRect();
              const style = (id) => getComputedStyle(document.getElementById(id));
              return JSON.stringify({
                contentWidth: rect('content').width,
                wideShellWidth: rect('wide-shell').width,
                wideShellMarginLeft: parseFloat(style('wide-shell').marginLeft),
                wideBodyWidth: rect('wide-scroll').width,
                wideBodyOverflowX: style('wide-scroll').overflowX,
                wideTableWidth: rect('wide-table').width
              });
            })()
            """,
            in: webView
        )

        XCTAssertGreaterThan(try number("wideShellWidth", in: restored), try number("contentWidth", in: restored))
        XCTAssertEqual(try number("wideShellMarginLeft", in: restored), -24, accuracy: 0.1)
        XCTAssertEqual(try number("wideBodyWidth", in: restored), 900, accuracy: 1)
        XCTAssertEqual(restored["wideBodyOverflowX"] as? String, "visible")
        XCTAssertEqual(try number("wideTableWidth", in: restored), 900, accuracy: 1)
    }

    @MainActor
    func testWideLayoutFloatingPanelUsesRealWebKitGeometryAcrossHostMarkupChanges() throws {
        let webView = try floatingPanelWebKitFixture(panelHTML: """
        <aside id="panel-host" class="thread-floating-content-top-inset thread-floating-content-bottom-inset">
          <div id="panel" data-pip-obstacle="thread-summary-panel" aria-hidden="true"></div>
          <div id="panel-body" class="painted-panel"></div>
        </aside>
        """)
        let initial = try waitForFloatingPanelGeometry(in: webView, width: 772, right: 916)
        try assertFloatingPanelClearance(initial)
        XCTAssertGreaterThan(try number("referenceTop", in: initial), try number("panelBottom", in: initial))
        XCTAssertEqual(initial["panelBackground"] as? String, "rgba(0, 0, 0, 0)")
        XCTAssertEqual(try number("panelChildren", in: initial), 0)
        XCTAssertEqual(initial["hasHomeSurface"] as? Bool, false)

        try mutateFloatingPanelFixture("""
        document.getElementById('panel').setAttribute('data-pip-obstacle', 'future-renamed-surface');
        document.getElementById('panel-host').className = 'future-floating-wrapper';
        const wrapper = document.createElement('section');
        document.getElementById('panel-host').before(wrapper);
        wrapper.appendChild(document.getElementById('panel-host'));
        """, in: webView)
        let renamed = try waitForFloatingPanelGeometry(in: webView, width: 772, right: 916)
        try assertFloatingPanelClearance(renamed)

        try mutateFloatingPanelFixture("""
        document.getElementById('panel-host').className =
          'thread-floating-content-top-inset thread-floating-content-bottom-inset';
        document.getElementById('panel').setAttribute('data-pip-home-surface', 'unrelated-value');
        document.getElementById('composer-shift').style.transform = 'translateX(-50px)';
        """, in: webView)
        let bothRoutes = try waitForFloatingPanelGeometry(in: webView, width: 772, right: 916)
        try assertFloatingPanelClearance(bothRoutes)
        XCTAssertEqual(try number("contentWidth", in: bothRoutes), try number("contentWidth", in: initial), accuracy: 1)
        XCTAssertEqual(try number("composerRight", in: bothRoutes), try number("contentRight", in: bothRoutes), accuracy: 1)

        let hostWindow = try XCTUnwrap(webView.window)
        hostWindow.setContentSize(NSSize(width: 1_440, height: 800))
        let resized = try waitForFloatingPanelGeometry(in: webView, width: 1_012, right: 1_156)
        try assertFloatingPanelClearance(resized)
    }

    @MainActor
    func testWideLayoutLegacyPaintedTopPanelUsesVisibleThreadHeightAndIgnoresNestedMenu() throws {
        let webView = try floatingPanelWebKitFixture(panelHTML: """
        <aside id="panel-host" class="thread-floating-content-top-inset thread-floating-content-bottom-inset">
          <div id="panel" class="painted-panel">
            <div role="menu" data-pip-obstacle="temporary-menu" style="position: absolute; width: 180px; height: 80px"></div>
          </div>
        </aside>
        """)
        let fullPanel = try waitForFloatingPanelGeometry(in: webView, width: 772, right: 916)
        try assertFloatingPanelClearance(fullPanel)
        XCTAssertGreaterThan(try number("referenceTop", in: fullPanel), try number("panelBottom", in: fullPanel))

        try mutateFloatingPanelFixture("document.getElementById('panel').style.height = '32px';", in: webView)
        let compact = try waitForFloatingPanelGeometry(in: webView, width: 772, right: 916)
        try assertFloatingPanelClearance(compact)
        XCTAssertEqual(try number("panelHeight", in: compact), 32, accuracy: 1)

        try mutateFloatingPanelFixture("document.getElementById('panel-host').style.opacity = '0';", in: webView)
        _ = try waitForFloatingPanelGeometry(in: webView, width: 1_032, right: 1_176)
        try mutateFloatingPanelFixture("document.getElementById('panel-host').style.opacity = '1';", in: webView)
        try assertFloatingPanelClearance(waitForFloatingPanelGeometry(in: webView, width: 772, right: 916))
    }

    @MainActor
    func testWideLayoutSemanticMarkersExcludeContentComposerHeaderAndTransientSurfaces() throws {
        let webView = try floatingPanelWebKitFixture(panelHTML: """
        <header class="negative-panel" data-pip-obstacle="header"></header>
        <div role="banner" class="negative-panel" data-pip-obstacle="banner"></div>
        <div role="menu" class="negative-panel" data-pip-obstacle="menu"></div>
        <div role="listbox" class="negative-panel"><div class="negative-panel" data-pip-obstacle="listbox-child"></div></div>
        <div role="dialog" class="negative-panel" data-pip-obstacle="dialog"></div>
        <div class="negative-panel" data-pip-obstacle="menu-only-wrapper"><div role="menu">Temporary menu.</div></div>
        <div data-selected-text-overlay-target class="negative-panel" data-pip-obstacle="detached-markdown"></div>
        <div class="markdown-wide-block-max-width negative-panel" data-pip-obstacle="markdown-block"></div>
        <div class="thread-composer-max-width-shell negative-panel" data-pip-obstacle="detached-width-owner"></div>
        <div id="initial-transient-scope" role="menu"><div class="negative-panel" data-pip-obstacle="initially-transient"></div></div>
        """)
        try mutateFloatingPanelFixture("""
        for (const id of ['content', 'markdown', 'composer', 'editor', 'scroller', 'layout']) {
          document.getElementById(id).setAttribute('data-pip-obstacle', 'ordinary-' + id);
        }
        for (const id of ['content', 'markdown', 'composer', 'editor']) {
          const child = document.createElement('div');
          child.className = 'negative-panel';
          child.setAttribute('data-pip-obstacle', 'ordinary-child-' + id);
          document.getElementById(id).appendChild(child);
        }
        const outside = document.createElement('aside');
        outside.className = 'negative-panel';
        outside.setAttribute('data-pip-obstacle', 'outside-layout');
        document.body.appendChild(outside);
        """, in: webView)
        let unoccluded = try waitForFloatingPanelGeometry(in: webView, width: 1_032, right: 1_176)
        XCTAssertEqual(try number("contentLeft", in: unoccluded), 144, accuracy: 1)
        XCTAssertEqual(try number("composerRight", in: unoccluded), 1_176, accuracy: 1)
        try mutateFloatingPanelFixture("document.getElementById('initial-transient-scope').removeAttribute('role');", in: webView)
        _ = try waitForFloatingPanelGeometry(in: webView, width: 732, right: 876)
    }

    @MainActor
    func testWideLayoutSemanticPanelMutationLifecycleAndUninstallUseRealWebKitObservers() throws {
        let webView = try floatingPanelWebKitFixture(panelHTML: """
        <section id="visibility-host"><aside id="panel-host"><div id="panel"></div></aside></section>
        """)
        _ = try waitForFloatingPanelGeometry(in: webView, width: 1_032, right: 1_176)

        try mutateFloatingPanelFixture("document.getElementById('panel').setAttribute('data-pip-obstacle', '');", in: webView)
        try assertFloatingPanelClearance(waitForFloatingPanelGeometry(in: webView, width: 772, right: 916))
        for nodeID in ["panel", "visibility-host"] {
            try mutateFloatingPanelFixture("document.getElementById('\(nodeID)').setAttribute('role', 'menu');", in: webView)
            _ = try waitForFloatingPanelGeometry(in: webView, width: 1_032, right: 1_176)
            try mutateFloatingPanelFixture("document.getElementById('\(nodeID)').removeAttribute('role');", in: webView)
            try assertFloatingPanelClearance(waitForFloatingPanelGeometry(in: webView, width: 772, right: 916))
        }
        try mutateFloatingPanelFixture("document.getElementById('panel').removeAttribute('data-pip-obstacle');", in: webView)
        _ = try waitForFloatingPanelGeometry(in: webView, width: 1_032, right: 1_176)

        try mutateFloatingPanelFixture("""
        document.getElementById('visibility-host').style.opacity = '0';
        document.getElementById('panel').setAttribute('data-pip-obstacle', 'restored-while-hidden');
        """, in: webView)
        _ = try waitForFloatingPanelGeometry(in: webView, width: 1_032, right: 1_176)
        try mutateFloatingPanelFixture("document.getElementById('visibility-host').style.opacity = '1';", in: webView)
        try assertFloatingPanelClearance(waitForFloatingPanelGeometry(in: webView, width: 772, right: 916))

        try mutateFloatingPanelFixture("document.getElementById('visibility-host').style.transform = 'translateX(-40px)';", in: webView)
        try assertFloatingPanelClearance(waitForFloatingPanelGeometry(in: webView, width: 732, right: 876))
        try mutateFloatingPanelFixture("document.getElementById('visibility-host').style.transform = 'none';", in: webView)
        _ = try waitForFloatingPanelGeometry(in: webView, width: 772, right: 916)

        try mutateFloatingPanelFixture("""
        const replacement = document.createElement('div');
        replacement.id = 'panel';
        replacement.setAttribute('data-pip-obstacle', 'replacement');
        document.getElementById('panel').replaceWith(replacement);
        document.getElementById('panel-host').style.width = '300px';
        """, in: webView)
        try assertFloatingPanelClearance(waitForFloatingPanelGeometry(in: webView, width: 732, right: 876))
        try mutateFloatingPanelFixture("document.getElementById('panel-host').remove();", in: webView)
        _ = try waitForFloatingPanelGeometry(in: webView, width: 1_032, right: 1_176)

        let removed = try evaluateWebKitJSON("""
        (() => {
          const response = window.__codexAppExtensionV2.uninstall({
            runtimeVersion: 2, requestId: 2, adapterId: 'wide-layout', operation: 'uninstall', config: {}
          });
          return JSON.stringify({
            error: response.error,
            observers: window.__codexAppExtensionV2.observerCount(),
            stylesheet: !!document.getElementById('cae-wide-layout-style'),
            marked: document.querySelectorAll('[data-cae-wide-layout]').length,
            ownerOffset: document.getElementById('content').style.getPropertyValue('--cae-wide-layout-owner-offset-x')
          });
        })()
        """, in: webView)
        XCTAssertTrue(removed["error"] is NSNull)
        XCTAssertEqual(try number("observers", in: removed), 0)
        XCTAssertEqual(removed["stylesheet"] as? Bool, false)
        XCTAssertEqual(try number("marked", in: removed), 0)
        XCTAssertEqual(removed["ownerOffset"] as? String, "")
        try mutateFloatingPanelFixture("""
        const panel = document.createElement('aside');
        panel.id = 'panel-host';
        panel.innerHTML = '<div id="panel" data-pip-obstacle="after-uninstall"></div>';
        document.getElementById('layout').appendChild(panel);
        """, in: webView)
        _ = try waitForFloatingPanelGeometry(in: webView, width: 900, right: 1_110)
    }

    func testWideLayoutReconcileIsDifferenceOnlyAndObserverQueuesConverge() throws {
        let harness = try JSRuntimeHarness(fixture: "current-surface")
        try addSyntheticWideOwner(to: harness)
        try harness.evaluate("""
        (() => {
          Object.defineProperty(window.__FakeNode.prototype, 'textContent', {
            configurable: true,
            get: function() { return this.__textContent || ''; },
            set: function(value) {
              this.__textContent = String(value);
              this.__textContentWriteCount = (this.__textContentWriteCount || 0) + 1;
              if (window.__autoStyleMutation) window.__triggerMutation(1);
            }
          });
          window.__FakeNode.prototype.textContentWriteCount = function() {
            return this.__textContentWriteCount || 0;
          };
        })();
        """)
        try harness.loadAdapter("wide-layout")
        _ = try harness.invoke("install", request: harness.request(
            id: 1,
            adapterId: "wide-layout",
            operation: "install",
            config: ["maximumContentWidth": 1_600, "minimumSidePadding": 30]
        ))

        let scroller = "document.querySelector('.thread-scroll-container')"
        let style = "document.getElementById('cae-wide-layout-style')"
        let initialThreadWrites = try harness.int("\(scroller).style.writeCount('--thread-content-max-width')")
        let initialComposerWrites = try harness.int("\(scroller).style.writeCount('--thread-composer-max-width')")
        let initialMarkdownWrites = try harness.int("\(scroller).style.writeCount('--markdown-wide-block-max-width')")
        let initialPaddingWrites = try harness.int("\(scroller).style.writeCount('--cae-wide-layout-side-padding')")
        let initialOffsetWrites = try harness.int("\(scroller).style.writeCount('--cae-wide-layout-content-offset-x')")
        let initialStyleWrites = try harness.int("\(style).textContentWriteCount()")

        try harness.evaluate("window.__autoStyleMutation = true; window.__triggerMutation(1); window.__flushRAF(); window.__flushTimers();")
        XCTAssertEqual(try harness.int("\(scroller).style.writeCount('--thread-content-max-width')"), initialThreadWrites)
        XCTAssertEqual(try harness.int("\(scroller).style.writeCount('--thread-composer-max-width')"), initialComposerWrites)
        XCTAssertEqual(try harness.int("\(scroller).style.writeCount('--markdown-wide-block-max-width')"), initialMarkdownWrites)
        XCTAssertEqual(try harness.int("\(scroller).style.writeCount('--cae-wide-layout-side-padding')"), initialPaddingWrites)
        XCTAssertEqual(try harness.int("\(scroller).style.writeCount('--cae-wide-layout-content-offset-x')"), initialOffsetWrites)
        XCTAssertEqual(try harness.int("\(style).textContentWriteCount()"), initialStyleWrites)
        XCTAssertEqual(try harness.int("window.__rafQueue.length"), 0)
        XCTAssertEqual(try harness.int("window.__timerQueue.length"), 0)

        try harness.evaluate("""
        window.__autoStyleMutation = false;
        \(scroller).style.setProperty('--thread-content-max-width', 'broken');
        window.__autoStyleMutation = true;
        window.__triggerMutation(1);
        window.__flushRAF();
        window.__flushTimers();
        window.__flushRAF();
        window.__flushTimers();
        """)
        XCTAssertEqual(
            try harness.string("\(scroller).style.getPropertyValue('--thread-content-max-width')"),
            "min(1600px, max(1px, calc(100% - 60px)))"
        )
        XCTAssertEqual(try harness.int("\(scroller).style.writeCount('--thread-content-max-width')"), initialThreadWrites + 2)
        XCTAssertEqual(try harness.int("\(scroller).style.writeCount('--thread-composer-max-width')"), initialComposerWrites)
        XCTAssertEqual(try harness.int("\(scroller).style.writeCount('--markdown-wide-block-max-width')"), initialMarkdownWrites)
        XCTAssertEqual(try harness.int("\(scroller).style.writeCount('--cae-wide-layout-side-padding')"), initialPaddingWrites)
        XCTAssertEqual(try harness.int("\(scroller).style.writeCount('--cae-wide-layout-content-offset-x')"), initialOffsetWrites)
        XCTAssertEqual(try harness.int("\(style).textContentWriteCount()"), initialStyleWrites)
        XCTAssertEqual(try harness.int("window.__rafQueue.length"), 0)
        XCTAssertEqual(try harness.int("window.__timerQueue.length"), 0)
    }

    func testWideLayoutMeasuresPersistentRightRailAndKeepsStreamingLeavesOutOfGeometry() throws {
        let harness = try JSRuntimeHarness(fixture: "current-surface")
        try harness.evaluate("""
        (() => {
          const rect = (left, right, top, bottom) => ({
            left, right, top, bottom,
            width: right - left,
            height: bottom - top
          });
          const scroller = document.querySelector('.thread-scroll-container');
          const inner = new window.__FakeNode('thread-inner-host');
          const nativeShiftHost = new window.__FakeNode('native-thread-shift-host');
          const composerShiftHost = new window.__FakeNode('native-composer-shift-host');
          const canonicalOwner = new window.__FakeNode('canonical-thread-content-owner');
          const composerOwner = new window.__FakeNode('composer-width-owner');
          const rail = document.querySelector('[data-testid="right-rail"]');
          const railBody = new window.__FakeNode('right-rail-rendered-body');
          const shortRailWrapper = new window.__FakeNode('right-rail-short-empty-state-wrapper');
          const shortRailBody = new window.__FakeNode('right-rail-short-empty-state');
          const pipObstacle = new window.__FakeNode('right-rail-pip-obstacle');
          const layoutRoot = document.querySelector('[data-app-shell-main-content-layout]');
          const originalLayoutQuery = layoutRoot.querySelectorAll.bind(layoutRoot);
          // This fixture's selector dictionary must reflect attribute addition/removal.
          layoutRoot.querySelectorAll = (selector) => selector === '[data-pip-obstacle]'
            ? [pipObstacle].filter((node) => node.hasAttribute('data-pip-obstacle') && layoutRoot.contains(node))
            : originalLayoutQuery(selector);
          const childlessMarkerRail = new window.__FakeNode('childless-explicit-marker-rail');
          const latentRailBody = new window.__FakeNode('right-rail-latent-body');
          const showingRailBody = new window.__FakeNode('right-rail-showing-body');
          const churnRailBody = new window.__FakeNode('right-rail-churn-body');
          const transientRail = new window.__FakeNode('transient-menu-rail');
          const transientWrapper = new window.__FakeNode('transient-dialog-wrapper');
          const transientDialog = new window.__FakeNode('transient-dialog');
          const streamingLeaf = document.querySelectorAll('[data-selected-text-overlay-target]')[0];
          window.__wideLayoutGeometryReads = 0;
          const measuredRect = (producer) => () => {
            window.__wideLayoutGeometryReads += 1;
            return producer();
          };
          scroller.getBoundingClientRect = measuredRect(() => rect(282.41, 1920, 46, 1080));
          inner.getBoundingClientRect = measuredRect(() => rect(297.41, 1905, -1000, 1080));
          streamingLeaf.getBoundingClientRect = () => rect(467.2, 1735.2, 700, 760);
          canonicalOwner.setAttribute('class', 'mx-auto max-w-(--thread-content-max-width)');
          canonicalOwner.style.setProperty('--cae-wide-layout-owner-offset-x', 'host-owner-offset', 'important');
          composerOwner.setAttribute('class', 'mx-auto max-w-(--thread-composer-max-width)');
          composerShiftHost.style.transform = 'matrix(1, 0, 0, 1, -50, 0)';
          nativeShiftHost.appendChild(canonicalOwner);
          composerShiftHost.appendChild(composerOwner);
          inner.appendChild(nativeShiftHost);
          inner.appendChild(composerShiftHost);
          rail.setAttribute('class', 'absolute right-0 thread-floating-content-top-inset thread-floating-content-bottom-inset');
          rail.style.position = 'absolute';
          rail.style.pointerEvents = 'none';
          rail.getBoundingClientRect = measuredRect(() => rect(1604, 1920, 104, 1068));
          railBody.style.backgroundColor = 'rgb(24, 24, 27)';
          railBody.getBoundingClientRect = measuredRect(() => rect(1660, 1900, 112, 460));
          shortRailBody.getBoundingClientRect = measuredRect(() => rect(1608, 1908, 112, 172));
          pipObstacle.setAttribute('aria-hidden', 'true');
          pipObstacle.getBoundingClientRect = measuredRect(() => rect(1604, 1904, 104, 1068));
          childlessMarkerRail.setAttribute('data-codex-app-extension-native-floating-panel', 'true');
          childlessMarkerRail.style.backgroundColor = 'rgb(24, 24, 27)';
          childlessMarkerRail.getBoundingClientRect = measuredRect(() => rect(1604, 1920, 104, 1068));
          const nestedRailMenu = new window.__FakeNode('nested-rail-menu');
          nestedRailMenu.setAttribute('role', 'menu');
          nestedRailMenu.style.backgroundColor = 'rgb(39, 39, 42)';
          nestedRailMenu.getBoundingClientRect = () => rect(1680, 1880, 180, 380);
          railBody.appendChild(nestedRailMenu);
          rail.appendChild(pipObstacle);
          rail.appendChild(railBody);
          shortRailWrapper.appendChild(shortRailBody);
          rail.appendChild(shortRailWrapper);
          rail.appendChild(latentRailBody);
          rail.appendChild(showingRailBody);
          rail.appendChild(churnRailBody);
          showingRailBody.getBoundingClientRect = () => rect(1660, 1900, 112, 460);
          churnRailBody.getBoundingClientRect = () => rect(1660, 1900, 112, 460);
          rail.registerAll('*', [pipObstacle, railBody, shortRailWrapper, shortRailBody, nestedRailMenu, latentRailBody, showingRailBody, churnRailBody]);
          transientRail.setAttribute('class', 'absolute thread-floating-content-menu');
          transientRail.setAttribute('role', 'menu');
          transientRail.style.position = 'absolute';
          transientRail.getBoundingClientRect = () => rect(1200, 1920, 120, 900);
          transientWrapper.setAttribute('class', 'absolute thread-floating-content-dialog');
          transientWrapper.style.position = 'absolute';
          transientWrapper.style.pointerEvents = 'none';
          transientWrapper.getBoundingClientRect = () => rect(1100, 1920, 120, 900);
          transientDialog.setAttribute('role', 'dialog');
          transientWrapper.appendChild(transientDialog);
          transientWrapper.registerAll("[role='menu'], [role='listbox'], [role='dialog']", [transientDialog]);
          scroller.appendChild(inner);
          scroller.registerAll("[class*='thread-content-max-width']", [canonicalOwner]);
          scroller.registerAll("[class*='thread-composer-max-width']", [composerOwner]);
          document.body.appendChild(transientRail);
          document.body.appendChild(transientWrapper);
          document.body.appendChild(childlessMarkerRail);
          document.__registerAll(
            "[class*='thread-floating-content-top-inset'][class*='thread-floating-content-bottom-inset'], [data-codex-app-extension-native-floating-panel='true']",
            [transientWrapper, transientRail, childlessMarkerRail, rail]
          );
          window.innerWidth = 1920;
          window.innerHeight = 1080;
          window.__resizeObservers = [];
          window.ResizeObserver = function(callback) {
            this.callback = callback;
            this.observed = [];
            this.disconnected = false;
            this.observe = (node) => {
              this.disconnected = false;
              this.observed.push(node);
            };
            this.disconnect = () => { this.disconnected = true; this.observed = []; };
            window.__resizeObservers.push(this);
          };
          window.__triggerResize = (node) => window.__resizeObservers
            .filter((observer) => !observer.disconnected && observer.observed.includes(node))
            .forEach((observer) => observer.callback([{ target: node }]));
          window.__triggerRailMutation = (node, attributeName = 'style') => window.__mutationObservers
            .filter((observer) => !observer.disconnected && observer.targets.some((target, index) => {
              const optionOffset = Math.max(0, (observer.options?.length || 0) - observer.targets.length);
              const options = observer.options?.[optionOffset + index] || {};
              const observesNode = target === node || (options.subtree && target.contains(node));
              const observesAttribute = !options.attributeFilter || options.attributeFilter.includes(attributeName);
              return options.attributes && observesNode && observesAttribute;
            }))
            .forEach((observer) => observer.callback([{ type: 'attributes', target: node, attributeName }]));
          window.__wideLayoutOwnerMutationCallbacks = 0;
          for (const owner of [canonicalOwner, composerOwner]) {
            const originalSetProperty = owner.style.setProperty.bind(owner.style);
            owner.style.setProperty = (name, value, priority) => {
              const before = owner.style.getPropertyValue(name);
              originalSetProperty(name, value, priority);
              if (name !== '--cae-wide-layout-owner-offset-x' || before === String(value)) return;
              window.__mutationObservers
                .filter((observer) => !observer.disconnected && observer.targets.includes(owner))
                .forEach((observer) => {
                  window.__wideLayoutOwnerMutationCallbacks += 1;
                  observer.callback([{ type: 'attributes', target: owner, attributeName: 'style' }]);
                });
            };
          }
          window.__wideLayoutStreamingLeaf = streamingLeaf;
          window.__wideLayoutInner = inner;
          window.__wideLayoutNativeShiftHost = nativeShiftHost;
          window.__wideLayoutComposerShiftHost = composerShiftHost;
          window.__wideLayoutCanonicalOwner = canonicalOwner;
          window.__wideLayoutComposerOwner = composerOwner;
          window.__wideLayoutRail = rail;
          window.__wideLayoutRailBody = railBody;
          window.__wideLayoutShortRailWrapper = shortRailWrapper;
          window.__wideLayoutShortRailBody = shortRailBody;
          window.__wideLayoutPIPObstacle = pipObstacle;
          window.__wideLayoutChildlessMarkerRail = childlessMarkerRail;
          window.__wideLayoutLatentRailBody = latentRailBody;
          window.__wideLayoutShowingRailBody = showingRailBody;
          window.__wideLayoutChurnRailBody = churnRailBody;
          window.__wideLayoutNestedRailMenu = nestedRailMenu;
        })();
        """)
        try harness.loadAdapter("wide-layout")
        let installed = try harness.invoke("install", request: harness.request(
            id: 1,
            adapterId: "wide-layout",
            operation: "install",
            config: ["maximumContentWidth": 1_300, "minimumSidePadding": 24]
        ))
        let result = try XCTUnwrap(installed["result"] as? [String: Any])
        XCTAssertEqual(result["effectiveWidth"] as? String, "1258px")
        XCTAssertEqual(result["contentOffset"] as? String, "-150px")
        XCTAssertEqual(result["availableWidth"] as? Int, 1_306)
        XCTAssertEqual(result["rightBoundary"] as? Double, 1_604)
        XCTAssertEqual(result["rightRail"] as? Bool, true)
        XCTAssertEqual(try harness.string("window.__wideLayoutCanonicalOwner.style.getPropertyValue('--cae-wide-layout-owner-offset-x')"), "-150px")
        XCTAssertEqual(try harness.string("window.__wideLayoutCanonicalOwner.style.getPropertyPriority('--cae-wide-layout-owner-offset-x')"), "")
        XCTAssertEqual(try harness.string("window.__wideLayoutComposerOwner.style.getPropertyValue('--cae-wide-layout-owner-offset-x')"), "-100px")
        XCTAssertEqual(try harness.int("window.__rafQueue.length"), 1)
        XCTAssertEqual(try harness.int("window.__wideLayoutOwnerMutationCallbacks"), 2)
        try harness.evaluate("window.__flushRAF(); window.__flushTimers();")
        XCTAssertEqual(try harness.int("window.__rafQueue.length"), 0)
        XCTAssertEqual(try harness.int("window.__wideLayoutOwnerMutationCallbacks"), 2)
        XCTAssertTrue(try harness.bool("window.__resizeObservers.some((observer) => observer.observed.includes(window.__wideLayoutCanonicalOwner))"))
        XCTAssertTrue(try harness.bool("window.__resizeObservers.some((observer) => observer.observed.includes(window.__wideLayoutComposerOwner))"))
        XCTAssertTrue(try harness.bool("window.__resizeObservers.some((observer) => observer.observed.includes(window.__wideLayoutRail))"))
        XCTAssertTrue(try harness.bool("window.__resizeObservers.some((observer) => observer.observed.includes(window.__wideLayoutRailBody))"))
        XCTAssertFalse(try harness.bool("window.__resizeObservers.some((observer) => observer.observed.includes(window.__wideLayoutNativeShiftHost))"))
        XCTAssertFalse(try harness.bool("window.__resizeObservers.some((observer) => observer.observed.includes(window.__wideLayoutComposerShiftHost))"))
        XCTAssertFalse(try harness.bool("window.__resizeObservers.some((observer) => observer.observed.includes(window.__wideLayoutLatentRailBody))"))
        XCTAssertFalse(try harness.bool("window.__resizeObservers.some((observer) => observer.observed.some((node) => node.getAttribute?.('role') === 'menu'))"))
        XCTAssertTrue(try harness.bool("window.__mutationObservers.some((observer) => observer.targets.includes(window.__wideLayoutRail))"))
        XCTAssertTrue(try harness.bool("""
        window.__mutationObservers.some((observer) => !observer.disconnected && observer.targets.some((target, index) => {
          const optionOffset = Math.max(0, (observer.options?.length || 0) - observer.targets.length);
          const options = observer.options?.[optionOffset + index] || {};
          return target === document.querySelector('[data-app-shell-main-content-layout]') &&
            options.attributes === true && options.subtree === true &&
            JSON.stringify(options.attributeFilter) === JSON.stringify(['data-pip-obstacle']);
        }))
        """))
        XCTAssertTrue(try harness.bool("window.__mutationObservers.some((observer) => observer.targets.includes(window.__wideLayoutCanonicalOwner))"))
        XCTAssertTrue(try harness.bool("window.__mutationObservers.some((observer) => observer.targets.includes(window.__wideLayoutComposerOwner))"))
        XCTAssertTrue(try harness.bool("window.__mutationObservers.some((observer) => observer.targets.includes(window.__wideLayoutNativeShiftHost))"))
        XCTAssertTrue(try harness.bool("window.__mutationObservers.some((observer) => observer.targets.includes(window.__wideLayoutComposerShiftHost))"))

        let readsAfterInstall = try harness.int("window.__wideLayoutGeometryReads")
        let writesAfterInstall = try harness.int("document.querySelector('.thread-scroll-container').style.writeCount('--thread-content-max-width')")
        try harness.evaluate("""
        for (let index = 0; index < 200; index += 1) {
          window.__mutationObservers
            .filter((observer) => !observer.disconnected && observer.targets.includes(document.documentElement))
            .forEach((observer) => observer.callback([{ type: 'childList', target: document.body }]));
        }
        window.__flushRAF();
        window.__flushTimers();
        """)
        XCTAssertEqual(try harness.int("window.__wideLayoutGeometryReads"), readsAfterInstall)
        XCTAssertEqual(
            try harness.int("document.querySelector('.thread-scroll-container').style.writeCount('--thread-content-max-width')"),
            writesAfterInstall
        )
        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.performanceSnapshot().observers.find((item) => item.adapterId === 'wide-layout').qualified === true"))
        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.performanceSnapshot().observers.find((item) => item.adapterId === 'wide-layout').degraded === false"))
        XCTAssertEqual(try harness.int("window.__codexAppExtensionV2.performanceSnapshot().observers.find((item) => item.adapterId === 'wide-layout').strikeCount"), 0)

        let readsBeforeOwnerAttributes = try harness.int("window.__wideLayoutGeometryReads")
        let ownerMutationCallbacksBeforeTransform = try harness.int("window.__wideLayoutOwnerMutationCallbacks")
        try harness.evaluate("""
        window.__wideLayoutCanonicalOwner.setAttribute('class', 'mx-auto changed max-w-(--thread-content-max-width)');
        window.__triggerRailMutation(window.__wideLayoutCanonicalOwner, 'class');
        window.__flushRAF();
        window.__flushTimers();
        window.__flushRAF();
        window.__flushTimers();
        window.__wideLayoutCanonicalOwner.style.transform = 'matrix(1, 0, 0, 1, -25, 0)';
        // Fake getComputedStyle returns this style object. Mirror the extension-owned
        // computed translate to prove it is excluded from native offset measurement.
        window.__wideLayoutCanonicalOwner.style.translate = '-150px 0px';
        window.__triggerRailMutation(window.__wideLayoutCanonicalOwner);
        window.__flushRAF();
        window.__flushTimers();
        window.__flushRAF();
        window.__flushTimers();
        """)
        XCTAssertGreaterThan(try harness.int("window.__wideLayoutGeometryReads"), readsBeforeOwnerAttributes)
        XCTAssertEqual(try harness.string("window.__wideLayoutCanonicalOwner.style.getPropertyValue('--cae-wide-layout-owner-offset-x')"), "-125px")
        XCTAssertEqual(try harness.string("document.querySelector('.thread-scroll-container').style.getPropertyValue('--cae-wide-layout-content-offset-x')"), "-125px")
        XCTAssertEqual(try harness.int("window.__wideLayoutOwnerMutationCallbacks"), ownerMutationCallbacksBeforeTransform + 1)
        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.performanceSnapshot().observers.find((item) => item.adapterId === 'wide-layout').qualified === true"))
        XCTAssertEqual(try harness.int("window.__rafQueue.length"), 0)
        XCTAssertEqual(try harness.int("window.__timerQueue.length"), 0)

        try harness.evaluate("""
        window.__wideLayoutCanonicalOwner.style.translate = '-125px 0px';
        window.__triggerRailMutation(window.__wideLayoutCanonicalOwner);
        window.__flushRAF();
        window.__flushTimers();
        """)
        XCTAssertEqual(try harness.string("window.__wideLayoutCanonicalOwner.style.getPropertyValue('--cae-wide-layout-owner-offset-x')"), "-125px")
        XCTAssertEqual(try harness.int("window.__wideLayoutOwnerMutationCallbacks"), ownerMutationCallbacksBeforeTransform + 1)
        XCTAssertEqual(try harness.int("window.__rafQueue.length"), 0)
        XCTAssertEqual(try harness.int("window.__timerQueue.length"), 0)

        try harness.evaluate("""
        window.__wideLayoutCanonicalOwner.style.transform = 'none';
        window.__wideLayoutCanonicalOwner.style.translate = 'none';
        window.__triggerRailMutation(window.__wideLayoutCanonicalOwner);
        window.__flushRAF();
        window.__flushTimers();
        window.__flushRAF();
        window.__flushTimers();
        """)
        XCTAssertEqual(try harness.string("window.__wideLayoutCanonicalOwner.style.getPropertyValue('--cae-wide-layout-owner-offset-x')"), "-150px")
        XCTAssertEqual(try harness.int("window.__rafQueue.length"), 0)
        XCTAssertEqual(try harness.int("window.__timerQueue.length"), 0)

        let readsAfterBurst = try harness.int("window.__wideLayoutGeometryReads")
        try harness.evaluate("""
        document.__registerAll(
          "[class*='thread-floating-content-top-inset'][class*='thread-floating-content-bottom-inset'], [data-codex-app-extension-native-floating-panel='true']",
          []
        );
        window.__mutationObservers
          .filter((observer) => !observer.disconnected && observer.targets.includes(document.documentElement))
          .forEach((observer) => observer.callback([{ type: 'childList', target: document.body }]));
        window.__flushRAF();
        window.__flushTimers();
        """)
        XCTAssertGreaterThan(try harness.int("window.__wideLayoutGeometryReads"), readsAfterBurst)
        XCTAssertEqual(try harness.string("document.querySelector('.thread-scroll-container').style.getPropertyValue('--thread-content-max-width')"), "1300px")
        try harness.evaluate("""
        document.__registerAll(
          "[class*='thread-floating-content-top-inset'][class*='thread-floating-content-bottom-inset'], [data-codex-app-extension-native-floating-panel='true']",
          [window.__wideLayoutRail]
        );
        window.__mutationObservers
          .filter((observer) => !observer.disconnected && observer.targets.includes(document.documentElement))
          .forEach((observer) => observer.callback([{ type: 'childList', target: document.body }]));
        window.__flushRAF();
        window.__flushTimers();
        """)
        XCTAssertEqual(try harness.string("document.querySelector('.thread-scroll-container').style.getPropertyValue('--thread-content-max-width')"), "1258px")
        XCTAssertEqual(try harness.string("document.querySelector('.thread-scroll-container').style.getPropertyValue('--cae-wide-layout-content-offset-x')"), "-150px")

        try harness.evaluate("""
        window.__wideLayoutLatentRailBody.style.backgroundColor = 'rgb(24, 24, 27)';
        window.__triggerRailMutation(window.__wideLayoutLatentRailBody);
        window.__flushRAF();
        window.__flushTimers();
        """)
        XCTAssertGreaterThan(try harness.int("window.__wideLayoutGeometryReads"), readsAfterInstall)
        XCTAssertTrue(try harness.bool("window.__resizeObservers.some((observer) => observer.observed.includes(window.__wideLayoutLatentRailBody))"))
        let scroller = "document.querySelector('.thread-scroll-container')"

        try harness.evaluate("""
        window.__wideLayoutRailBody.style.display = 'none';
        window.__wideLayoutRail.dispatchEvent(document.__event('animationstart', window.__wideLayoutShowingRailBody, { animationName: 'rail-show' }));
        window.__wideLayoutShowingRailBody.style.backgroundColor = 'rgb(24, 24, 27)';
        window.__flushRAF();
        """)
        XCTAssertEqual(try harness.int("window.__rafQueue.length"), 1)
        XCTAssertEqual(try harness.string("\(scroller).style.getPropertyValue('--thread-content-max-width')"), "1258px")
        try harness.evaluate("""
        window.__wideLayoutRail.dispatchEvent(document.__event('animationcancel', window.__wideLayoutShowingRailBody, { animationName: 'rail-show' }));
        window.__flushRAF();
        """)
        XCTAssertEqual(try harness.int("window.__rafQueue.length"), 0)
        try harness.evaluate("""
        window.__wideLayoutRail.dispatchEvent(document.__event('transitionstart', window.__wideLayoutNestedRailMenu, { propertyName: 'transform' }));
        window.__wideLayoutNativeShiftHost.dispatchEvent(document.__event('animationstart', window.__wideLayoutStreamingLeaf, { animationName: 'streaming-leaf' }));
        """)
        XCTAssertEqual(try harness.int("window.__rafQueue.length"), 0)
        try harness.evaluate("""
        window.__wideLayoutRailBody.style.display = '';
        window.__wideLayoutShowingRailBody.style.backgroundColor = '';
        window.__triggerRailMutation(window.__wideLayoutShowingRailBody);
        window.__flushRAF();
        """)

        XCTAssertEqual(try harness.string("\(scroller).style.getPropertyValue('--thread-content-max-width')"), "1258px")
        XCTAssertEqual(try harness.string("\(scroller).style.getPropertyValue('--thread-composer-max-width')"), "1258px")
        XCTAssertEqual(try harness.string("\(scroller).style.getPropertyValue('--markdown-wide-block-max-width')"), "1258px")
        XCTAssertEqual(try harness.string("\(scroller).style.getPropertyValue('--cae-wide-layout-side-padding')"), "24px")
        XCTAssertEqual(try harness.string("\(scroller).style.getPropertyValue('--cae-wide-layout-content-offset-x')"), "-150px")
        let initialWidthWrites = try harness.int("\(scroller).style.writeCount('--thread-content-max-width')")

        try harness.evaluate("""
        window.__wideLayoutNativeShiftHost.style.transform = 'matrix(1, 0, 0, 1, -150, 0)';
        window.__triggerRailMutation(window.__wideLayoutNativeShiftHost);
        window.__flushRAF();
        window.__flushTimers();
        """)
        XCTAssertEqual(try harness.string("\(scroller).style.getPropertyValue('--cae-wide-layout-content-offset-x')"), "0px")
        XCTAssertEqual(try harness.string("window.__wideLayoutCanonicalOwner.style.getPropertyValue('--cae-wide-layout-owner-offset-x')"), "0px")
        XCTAssertEqual(try harness.string("window.__wideLayoutComposerOwner.style.getPropertyValue('--cae-wide-layout-owner-offset-x')"), "-100px")

        try harness.evaluate("""
        window.__wideLayoutNativeShiftHost.style.transform = 'matrix(1, 0, 0, 1, -200, 0)';
        window.__triggerRailMutation(window.__wideLayoutNativeShiftHost);
        window.__flushRAF();
        window.__flushTimers();
        """)
        XCTAssertEqual(try harness.string("\(scroller).style.getPropertyValue('--cae-wide-layout-content-offset-x')"), "50px")
        XCTAssertEqual(try harness.string("window.__wideLayoutCanonicalOwner.style.getPropertyValue('--cae-wide-layout-owner-offset-x')"), "50px")

        try harness.evaluate("""
        window.__wideLayoutNativeShiftHost.style.transform = 'none';
        window.__triggerRailMutation(window.__wideLayoutNativeShiftHost);
        window.__flushRAF();
        window.__flushTimers();
        """)
        XCTAssertEqual(try harness.string("\(scroller).style.getPropertyValue('--cae-wide-layout-content-offset-x')"), "-150px")

        try harness.evaluate("""
        window.__wideLayoutNativeShiftHost.style.transform = 'matrix3d(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -100, 0, 0, 1)';
        window.__wideLayoutNativeShiftHost.style.translate = '-50px 0px';
        window.__triggerRailMutation(window.__wideLayoutNativeShiftHost);
        window.__flushRAF();
        window.__flushTimers();
        """)
        XCTAssertEqual(try harness.string("window.__wideLayoutCanonicalOwner.style.getPropertyValue('--cae-wide-layout-owner-offset-x')"), "0px")

        try harness.evaluate("""
        window.__wideLayoutNativeShiftHost.style.transform = 'matrix(2, 0, 0, 2, -150, 0)';
        window.__wideLayoutNativeShiftHost.style.translate = 'none';
        window.__triggerRailMutation(window.__wideLayoutNativeShiftHost);
        window.__flushRAF();
        """)
        XCTAssertEqual(try harness.string("window.__wideLayoutCanonicalOwner.style.getPropertyValue('--cae-wide-layout-owner-offset-x')"), "-150px")

        try harness.evaluate("""
        window.__wideLayoutNativeShiftHost.style.transform = 'none';
        window.__wideLayoutNativeShiftHost.style.translate = 'none';
        window.__wideLayoutNativeShiftHost.dispatchEvent(document.__event('transitionstart', window.__wideLayoutNativeShiftHost, { propertyName: 'transform' }));
        window.__wideLayoutNativeShiftHost.style.transform = 'matrix(1, 0, 0, 1, -75, 0)';
        window.__flushRAF();
        """)
        XCTAssertEqual(try harness.string("window.__wideLayoutCanonicalOwner.style.getPropertyValue('--cae-wide-layout-owner-offset-x')"), "-75px")
        XCTAssertEqual(try harness.int("window.__rafQueue.length"), 1)
        try harness.evaluate("""
        window.__wideLayoutChurnRailBody.style.backgroundColor = 'rgb(24, 24, 27)';
        window.__triggerRailMutation(window.__wideLayoutChurnRailBody);
        window.__flushRAF();
        """)
        XCTAssertEqual(try harness.int("window.__rafQueue.length"), 1)
        try harness.evaluate("""
        window.__wideLayoutNativeShiftHost.style.transform = 'matrix(1, 0, 0, 1, -150, 0)';
        window.__flushRAF();
        """)
        XCTAssertEqual(try harness.string("window.__wideLayoutCanonicalOwner.style.getPropertyValue('--cae-wide-layout-owner-offset-x')"), "0px")
        XCTAssertEqual(try harness.int("window.__rafQueue.length"), 1)
        try harness.evaluate("""
        window.__wideLayoutNativeShiftHost.dispatchEvent(document.__event('transitionend', window.__wideLayoutNativeShiftHost, { propertyName: 'transform' }));
        window.__wideLayoutChurnRailBody.style.backgroundColor = '';
        window.__triggerRailMutation(window.__wideLayoutChurnRailBody);
        window.__flushRAF();
        """)
        XCTAssertEqual(try harness.int("window.__rafQueue.length"), 0)

        try harness.evaluate("""
        (() => {
          const replacement = new window.__FakeNode('replacement-canonical-owner');
          replacement.setAttribute('class', 'mx-auto max-w-(--thread-content-max-width)');
          window.__wideLayoutCanonicalOwner.remove();
          window.__wideLayoutNativeShiftHost.appendChild(replacement);
          document.querySelector('.thread-scroll-container').registerAll("[class*='thread-content-max-width']", [replacement]);
          window.__wideLayoutOldCanonicalOwner = window.__wideLayoutCanonicalOwner;
          window.__wideLayoutCanonicalOwner = replacement;
          window.__triggerMutation(1);
          window.__flushRAF();
          window.__flushTimers();
        })();
        """)
        XCTAssertEqual(try harness.string("window.__wideLayoutOldCanonicalOwner.style.getPropertyValue('--cae-wide-layout-owner-offset-x')"), "host-owner-offset")
        XCTAssertEqual(try harness.string("window.__wideLayoutOldCanonicalOwner.style.getPropertyPriority('--cae-wide-layout-owner-offset-x')"), "important")
        XCTAssertEqual(try harness.string("window.__wideLayoutCanonicalOwner.style.getPropertyValue('--cae-wide-layout-owner-offset-x')"), "0px")
        let initialOffsetWrites = try harness.int("\(scroller).style.writeCount('--cae-wide-layout-content-offset-x')")

        try harness.evaluate("""
        window.__wideLayoutStreamingLeaf.getBoundingClientRect = () => ({
          left: 900, right: 1200, top: 700, bottom: 760, width: 300, height: 60
        });
        window.__triggerMutation(1);
        window.__flushRAF();
        window.__flushTimers();
        """)
        XCTAssertEqual(try harness.int("\(scroller).style.writeCount('--thread-content-max-width')"), initialWidthWrites)
        XCTAssertEqual(try harness.int("\(scroller).style.writeCount('--cae-wide-layout-content-offset-x')"), initialOffsetWrites)

        try harness.evaluate("""
        window.__wideLayoutNativeShiftHost.style.transform = 'matrix(1, 0, 0, 1, -150, 0)';
        window.__wideLayoutRailBody.style.display = 'none';
        window.__triggerRailMutation(window.__wideLayoutRailBody);
        window.__flushRAF();
        window.__flushTimers();
        """)
        XCTAssertEqual(try harness.string("\(scroller).style.getPropertyValue('--thread-content-max-width')"), "1300px")
        XCTAssertEqual(try harness.string("\(scroller).style.getPropertyValue('--cae-wide-layout-content-offset-x')"), "0px")
        XCTAssertEqual(try harness.string("window.__wideLayoutCanonicalOwner.style.getPropertyValue('--cae-wide-layout-owner-offset-x')"), "0px")

        try harness.evaluate("""
        window.__wideLayoutShortRailBody.style.backgroundColor = 'rgb(24, 24, 27)';
        window.__triggerRailMutation(window.__wideLayoutShortRailBody);
        window.__flushRAF();
        window.__flushTimers();
        """)
        XCTAssertEqual(try harness.string("\(scroller).style.getPropertyValue('--thread-content-max-width')"), "1258px")
        XCTAssertEqual(try harness.string("\(scroller).style.getPropertyValue('--cae-wide-layout-content-offset-x')"), "0px")

        try harness.evaluate("""
        window.__wideLayoutRail.style.opacity = '0';
        window.__triggerRailMutation(window.__wideLayoutRail);
        window.__flushRAF();
        window.__flushTimers();
        """)
        XCTAssertEqual(try harness.string("\(scroller).style.getPropertyValue('--thread-content-max-width')"), "1300px")

        try harness.evaluate("""
        window.__wideLayoutRail.style.opacity = '1';
        window.__wideLayoutShortRailWrapper.style.opacity = '0';
        window.__triggerRailMutation(window.__wideLayoutShortRailWrapper);
        window.__flushRAF();
        window.__flushTimers();
        """)
        XCTAssertEqual(try harness.string("\(scroller).style.getPropertyValue('--thread-content-max-width')"), "1300px")

        try harness.evaluate("""
        window.__wideLayoutShortRailWrapper.style.opacity = '1';
        window.__wideLayoutShortRailBody.style.opacity = '0';
        window.__triggerRailMutation(window.__wideLayoutShortRailBody);
        window.__flushRAF();
        window.__flushTimers();
        """)
        XCTAssertEqual(try harness.string("\(scroller).style.getPropertyValue('--thread-content-max-width')"), "1300px")

        try harness.evaluate("""
        window.__wideLayoutShortRailBody.style.opacity = '1';
        window.__triggerRailMutation(window.__wideLayoutShortRailBody);
        window.__flushRAF();
        window.__flushTimers();
        """)
        XCTAssertEqual(try harness.string("\(scroller).style.getPropertyValue('--thread-content-max-width')"), "1258px")

        try harness.evaluate("""
        window.__wideLayoutShortRailBody.style.display = 'none';
        window.__triggerRailMutation(window.__wideLayoutShortRailBody);
        window.__flushRAF();
        window.__flushTimers();
        """)
        XCTAssertEqual(try harness.string("\(scroller).style.getPropertyValue('--thread-content-max-width')"), "1300px")
        XCTAssertEqual(try harness.string("\(scroller).style.getPropertyValue('--cae-wide-layout-content-offset-x')"), "0px")

        try harness.evaluate("""
        window.__wideLayoutShortRailBody.style.display = '';
        window.__wideLayoutShortRailBody.getBoundingClientRect = () => ({
          left: 1608, right: 1608, top: 112, bottom: 112, width: 0, height: 0
        });
        window.__triggerRailMutation(window.__wideLayoutShortRailBody);
        window.__flushRAF();
        window.__flushTimers();
        """)
        XCTAssertEqual(try harness.string("\(scroller).style.getPropertyValue('--thread-content-max-width')"), "1300px")
        XCTAssertEqual(try harness.string("\(scroller).style.getPropertyValue('--cae-wide-layout-content-offset-x')"), "0px")

        try harness.evaluate("""
        window.__wideLayoutRail.registerAll('*', []);
        window.__triggerRailMutation(window.__wideLayoutRail);
        window.__flushRAF();
        window.__flushTimers();
        """)
        XCTAssertEqual(try harness.string("\(scroller).style.getPropertyValue('--thread-content-max-width')"), "1300px")
        XCTAssertEqual(try harness.string("\(scroller).style.getPropertyValue('--cae-wide-layout-content-offset-x')"), "0px")

        try harness.evaluate("""
        window.__wideLayoutInner.getBoundingClientRect = () => ({
          left: 297.41, right: 1905, top: 934, bottom: 1080, width: 1607.59, height: 146
        });
        window.__wideLayoutPIPObstacle.getBoundingClientRect = () => ({
          left: 1604, right: 1904, top: 104, bottom: 460, width: 300, height: 356
        });
        window.__wideLayoutPIPObstacle.setAttribute('data-pip-home-surface', 'thread-summary-panel');
        window.__wideLayoutRail.registerAll('*', [window.__wideLayoutPIPObstacle]);
        window.__triggerRailMutation(window.__wideLayoutPIPObstacle, 'data-pip-home-surface');
        window.__flushRAF();
        window.__flushTimers();
        """)
        XCTAssertEqual(try harness.string("\(scroller).style.getPropertyValue('--thread-content-max-width')"), "1300px")

        try harness.evaluate("""
        window.__wideLayoutPIPObstacle.setAttribute('data-pip-obstacle', 'thread-summary-panel');
        window.__triggerRailMutation(window.__wideLayoutPIPObstacle, 'data-pip-obstacle');
        window.__flushRAF();
        window.__flushTimers();
        """)
        XCTAssertEqual(try harness.string("\(scroller).style.getPropertyValue('--thread-content-max-width')"), "1258px")

        try harness.evaluate("""
        window.__wideLayoutPIPObstacle.removeAttribute('data-pip-home-surface');
        window.__wideLayoutPIPObstacle.setAttribute('data-pip-obstacle', 'renamed-surface');
        window.__triggerRailMutation(window.__wideLayoutPIPObstacle, 'data-pip-obstacle');
        window.__flushRAF();
        window.__flushTimers();
        """)
        XCTAssertEqual(try harness.string("\(scroller).style.getPropertyValue('--thread-content-max-width')"), "1258px")

        try harness.evaluate("""
        window.__wideLayoutPIPObstacle.removeAttribute('data-pip-obstacle');
        window.__wideLayoutInner.getBoundingClientRect = () => ({
          left: 297.41, right: 1905, top: -1000, bottom: 1080, width: 1607.59, height: 2080
        });
        window.__wideLayoutPIPObstacle.getBoundingClientRect = () => ({
          left: 1604, right: 1904, top: 104, bottom: 1068, width: 300, height: 964
        });
        window.__triggerRailMutation(window.__wideLayoutPIPObstacle, 'data-pip-obstacle');
        window.__flushRAF();
        window.__flushTimers();
        """)
        XCTAssertEqual(try harness.string("\(scroller).style.getPropertyValue('--thread-content-max-width')"), "1300px")
        XCTAssertEqual(try harness.string("\(scroller).style.getPropertyValue('--cae-wide-layout-content-offset-x')"), "0px")

        try harness.evaluate("""
        window.__wideLayoutRail.registerAll('*', [
          window.__wideLayoutPIPObstacle,
          window.__wideLayoutRailBody,
          window.__wideLayoutShortRailWrapper,
          window.__wideLayoutShortRailBody,
          window.__wideLayoutNestedRailMenu,
          window.__wideLayoutLatentRailBody,
          window.__wideLayoutShowingRailBody,
          window.__wideLayoutChurnRailBody
        ]);
        window.__wideLayoutShortRailBody.style.backgroundColor = '';
        window.__wideLayoutRailBody.style.display = '';
        window.__wideLayoutRailBody.getBoundingClientRect = () => ({
          left: 1980, right: 2220, top: 112, bottom: 460, width: 240, height: 348
        });
        window.__triggerRailMutation(window.__wideLayoutRail);
        window.__flushRAF();
        window.__flushTimers();
        """)
        XCTAssertEqual(try harness.string("\(scroller).style.getPropertyValue('--thread-content-max-width')"), "1300px")
        XCTAssertEqual(try harness.string("\(scroller).style.getPropertyValue('--cae-wide-layout-content-offset-x')"), "0px")

        try harness.evaluate("""
        window.__wideLayoutNativeShiftHost.style.transform = 'none';
        window.__wideLayoutRailBody.getBoundingClientRect = () => ({
          left: 1660, right: 1900, top: 112, bottom: 460, width: 240, height: 348
        });
        window.__triggerResize(window.__wideLayoutRailBody);
        window.__flushRAF();
        window.__flushTimers();
        """)
        XCTAssertEqual(try harness.string("\(scroller).style.getPropertyValue('--thread-content-max-width')"), "1258px")
        XCTAssertEqual(try harness.string("\(scroller).style.getPropertyValue('--cae-wide-layout-content-offset-x')"), "-150px")

        _ = try harness.invoke("uninstall", request: harness.request(
            id: 2, adapterId: "wide-layout", operation: "uninstall", config: [:]
        ))
        XCTAssertTrue(try harness.bool("window.__resizeObservers.every((observer) => observer.disconnected)"))
        XCTAssertTrue(try harness.bool("window.__mutationObservers.every((observer) => observer.disconnected)"))
        XCTAssertEqual(try harness.string("window.__wideLayoutCanonicalOwner.style.getPropertyValue('--cae-wide-layout-owner-offset-x')"), "")
        XCTAssertEqual(try harness.string("window.__wideLayoutComposerOwner.style.getPropertyValue('--cae-wide-layout-owner-offset-x')"), "")
        XCTAssertTrue(try harness.bool("['transitionrun','transitionstart','transitionend','transitioncancel','animationstart','animationend','animationcancel'].every((type) => window.__wideLayoutNativeShiftHost.listenerCount(type) === 0 && window.__wideLayoutRail.listenerCount(type) === 0 && window.__wideLayoutPIPObstacle.listenerCount(type) === 0)"))
        XCTAssertEqual(try harness.int("window.__rafQueue.length"), 0)
    }

    func testWideLayoutAppliesExactlyOneClampOwnerAcrossNestedAndExcludedFixtures() throws {
        let harness = try JSRuntimeHarness(fixture: "current-surface")
        try addSyntheticWideOwner(to: harness)
        try harness.loadAdapter("wide-layout")
        _ = try harness.invoke("install", request: harness.request(
            id: 1,
            adapterId: "wide-layout",
            operation: "install",
            config: ["maximumContentWidth": 1_600, "minimumSidePadding": 30]
        ))

        try harness.evaluate("""
        (() => {
          const scroller = document.querySelector('.thread-scroll-container');
          const makeNode = (name, attributes, parent) => {
            const node = new window.__FakeNode(name);
            Object.entries(attributes || {}).forEach(([key, value]) => node.setAttribute(key, value));
            (parent || scroller).appendChild(node);
            return node;
          };
          const makeSelected = (name, parent) => makeNode(name, { 'data-selected-text-overlay-target': '' }, parent);

          const candidateAttributes = (kind) => {
            if (kind === 'canonical') return { class: 'mx-auto max-w-(--thread-content-max-width)' };
            if (kind === 'markdown') return { class: 'max-w-[var(--markdown-wide-block-max-width)]' };
            return { 'data-selected-text-overlay-target': '' };
          };
          const makeBranch = (name, kinds) => {
            const nodes = [];
            let parent = scroller;
            kinds.forEach((kind, index) => {
              const node = makeNode(`${name}-${kind}-${index}`, candidateAttributes(kind), parent);
              nodes.push(node);
              parent = node;
            });
            return nodes;
          };
          const branches = {
            canonicalMixed: makeBranch('canonicalMixed', ['canonical', 'markdown', 'selected']),
            markdownMixed: makeBranch('markdownMixed', ['markdown', 'canonical', 'selected']),
            selectedMixed: makeBranch('selectedMixed', ['selected', 'canonical', 'markdown']),
            canonicalSame: makeBranch('canonicalSame', ['canonical', 'canonical']),
            markdownSame: makeBranch('markdownSame', ['markdown', 'markdown']),
            selectedSame: makeBranch('selectedSame', ['selected', 'selected'])
          };
          const dualRoleSelectedOwner = makeNode('dualRoleSelectedOwner', {
            class: 'mx-auto max-w-(--thread-content-max-width)',
            'data-selected-text-overlay-target': ''
          });
          const dualRoleMarkdownOwner = makeNode('dualRoleMarkdownOwner', {
            class: 'max-w-(--thread-content-max-width) max-w-[var(--markdown-wide-block-max-width)]'
          });

          const composer = makeNode('composer', {
            class: 'ProseMirror max-w-[var(--thread-composer-max-width)]',
            contenteditable: 'true',
            'data-codex-composer': 'true'
          });
          const composerSelected = makeSelected('composerSelected', composer);
          const menuSelected = makeSelected('menuSelected', makeNode('menu', { role: 'menu' }));
          const listboxSelected = makeSelected('listboxSelected', makeNode('listbox', { role: 'listbox' }));
          const dialogSelected = makeSelected('dialogSelected', makeNode('dialog', { role: 'dialog' }));
          const floatingSelected = makeSelected('floatingSelected', makeNode('floating', { class: 'thread-floating-content' }));
          const railCanonical = makeNode('railCanonical', { class: 'max-w-(--thread-content-max-width)', 'data-testid': 'right-rail' }, document.body);

          const splitTopLevel = (source) => {
            const parts = [];
            let depth = 0;
            let start = 0;
            for (let index = 0; index < source.length; index += 1) {
              if (source[index] === '(') depth += 1;
              else if (source[index] === ')') depth -= 1;
              else if (source[index] === ',' && depth === 0) {
                parts.push(source.slice(start, index).trim());
                start = index + 1;
              }
            }
            parts.push(source.slice(start).trim());
            return parts.filter(Boolean);
          };
          const classValue = (node) => node.getAttribute('class') || '';
          const matchesAtom = (node, source) => {
            const atom = source.trim();
            if (atom.endsWith(' *')) {
              const ancestorAtom = atom.slice(0, -2).trim();
              for (let ancestor = node.parentElement; ancestor; ancestor = ancestor.parentElement) {
                if (matchesAtom(ancestor, ancestorAtom)) return true;
              }
              return false;
            }
            const proseMirror = /^\\.ProseMirror\\[contenteditable='([^']+)'\\]$/.exec(atom);
            if (proseMirror) {
              return classValue(node).split(/\\s+/).includes('ProseMirror')
                && node.getAttribute('contenteditable') === proseMirror[1];
            }
            const classSubstring = /^\\[class\\*='([^']+)'\\]$/.exec(atom);
            if (classSubstring) return classValue(node).includes(classSubstring[1]);
            const exactAttribute = /^\\[([^=]+)='([^']*)'\\]$/.exec(atom);
            if (exactAttribute) return node.getAttribute(exactAttribute[1]) === exactAttribute[2];
            const presentAttribute = /^\\[([^=]+)\\]$/.exec(atom);
            return Boolean(presentAttribute && node.hasAttribute(presentAttribute[1]));
          };
          const notGroups = (selector) => {
            const groups = [];
            let offset = 0;
            while (true) {
              const opening = selector.indexOf(':not(', offset);
              if (opening < 0) return groups;
              let depth = 1;
              let closing = opening + 5;
              while (closing < selector.length && depth > 0) {
                if (selector[closing] === '(') depth += 1;
                else if (selector[closing] === ')') depth -= 1;
                closing += 1;
              }
              groups.push(selector.slice(opening + 5, closing - 1));
              offset = closing;
            }
          };
          const isWithinScroller = (node) => {
            for (let ancestor = node.parentElement; ancestor; ancestor = ancestor.parentElement) {
              if (ancestor === scroller) return true;
            }
            return false;
          };
          const matchesRule = (node, selector) => {
            if (!isWithinScroller(node) || scroller.getAttribute('data-cae-wide-layout') !== 'true') return false;
            const firstNot = selector.indexOf(':not(');
            const positive = firstNot < 0 ? selector : selector.slice(0, firstNot);
            const positiveMatches = positive.includes("[class*='thread-content-max-width']")
              ? matchesAtom(node, "[class*='thread-content-max-width']")
              : positive.includes("[class*='thread-composer-max-width']")
                ? matchesAtom(node, "[class*='thread-composer-max-width']")
                : false;
            if (!positiveMatches) return false;
            return notGroups(selector).every((group) =>
              splitTopLevel(group).every((excluded) => !matchesAtom(node, excluded))
            );
          };

          const css = document.getElementById('cae-wide-layout-style').textContent;
          const selectorPrelude = css.slice(0, css.indexOf(' {'));
          const rules = splitTopLevel(selectorPrelude);
          window.__wideLayoutCases = {
            dualRoleSelectedOwner,
            dualRoleMarkdownOwner,
            composerSelected,
            menuSelected,
            listboxSelected,
            dialogSelected,
            floatingSelected,
            railCanonical
          };
          const matchCount = (node) => rules.filter((selector) => matchesRule(node, selector)).length;
          window.__wideLayoutMatchCount = (name) => matchCount(window.__wideLayoutCases[name]);
          window.__wideLayoutBranchOwnerCount = (name) =>
            branches[name].reduce((total, node) => total + matchCount(node), 0);
          window.__wideLayoutBranchMatchCounts = (name) => branches[name].map(matchCount).join(',');
        })();
        """)

        let branchExpectations = [
            "canonicalMixed": "1,0,0",
            "markdownMixed": "0,0,0",
            "selectedMixed": "0,0,0",
            "canonicalSame": "1,0",
            "markdownSame": "0,0",
            "selectedSame": "0,0"
        ]
        for (branch, expectedMatches) in branchExpectations {
            let expectedOwners = expectedMatches.split(separator: ",").filter { $0 == "1" }.count
            XCTAssertEqual(try harness.int("window.__wideLayoutBranchOwnerCount('\(branch)')"), expectedOwners, branch)
            XCTAssertEqual(try harness.string("window.__wideLayoutBranchMatchCounts('\(branch)')"), expectedMatches, branch)
        }
        for excluded in ["dualRoleSelectedOwner", "dualRoleMarkdownOwner", "composerSelected", "menuSelected", "listboxSelected", "dialogSelected", "floatingSelected", "railCanonical"] {
            XCTAssertEqual(try harness.int("window.__wideLayoutMatchCount('\(excluded)')"), 0, excluded)
        }
    }

    func testHeaderOffsetReadsNativeVariableSupportsCustomAndRestoresHostValues() throws {
        let harness = try JSRuntimeHarness(fixture: "current-surface")
        try harness.evaluate("""
        (() => {
          const layout = document.querySelector('[data-app-shell-main-content-layout]');
          layout.setAttribute('data-cae-header-offset', 'host-header');
          layout.style.setProperty('--cae-header-offset', '12px', 'important');
        })();
        """)
        try harness.loadAdapter("header-offset")

        let automatic = try harness.invoke("install", request: harness.request(
            id: 1,
            adapterId: "header-offset",
            operation: "install",
            config: ["mode": "automatic", "customOffset": 64]
        ))
        XCTAssertEqual((automatic["result"] as? [String: Any])?["offset"] as? Int, 46)
        XCTAssertEqual(try harness.string("document.querySelector('[data-app-shell-main-content-layout]').style.getPropertyValue('--cae-header-offset')"), "46px")
        let css = try harness.string("document.getElementById('cae-header-offset-style').textContent")
        XCTAssertTrue(css.contains("[data-app-shell-main-content-layout][data-cae-header-offset='true'] {"))
        XCTAssertTrue(css.contains("box-sizing: border-box"))
        XCTAssertTrue(css.contains("padding-top: var(--cae-header-offset) !important"))
        XCTAssertTrue(css.contains("scroll-padding-top: var(--cae-header-offset)"))

        _ = try harness.invoke("update", request: harness.request(
            id: 2,
            adapterId: "header-offset",
            operation: "update",
            config: ["mode": "custom", "customOffset": 64]
        ))
        XCTAssertEqual(try harness.string("document.querySelector('[data-app-shell-main-content-layout]').style.getPropertyValue('--cae-header-offset')"), "64px")
        XCTAssertFalse(try harness.bool("document.querySelector(\".ProseMirror[contenteditable='true']\").hasAttribute('data-cae-header-offset')"))

        _ = try harness.invoke("uninstall", request: harness.request(
            id: 3, adapterId: "header-offset", operation: "uninstall", config: [:]
        ))
        XCTAssertEqual(try harness.string("document.querySelector('[data-app-shell-main-content-layout]').getAttribute('data-cae-header-offset')"), "host-header")
        XCTAssertEqual(try harness.string("document.querySelector('[data-app-shell-main-content-layout]').style.getPropertyValue('--cae-header-offset')"), "12px")
        XCTAssertEqual(try harness.string("document.querySelector('[data-app-shell-main-content-layout]').style.getPropertyPriority('--cae-header-offset')"), "important")
        XCTAssertTrue(try harness.value("document.getElementById('cae-header-offset-style')").isNull)
        XCTAssertEqual(try harness.int("window.__codexAppExtensionV2.observerCount()"), 0)
    }

    func testHeaderRefreshConvergesAndWritesOnlyWhenNativeOffsetChanges() throws {
        let harness = try JSRuntimeHarness(fixture: "current-surface")
        try harness.loadAdapter("header-offset")
        _ = try harness.invoke("install", request: harness.request(
            id: 1,
            adapterId: "header-offset",
            operation: "install",
            config: ["mode": "automatic", "customOffset": 0]
        ))
        let layout = "document.querySelector('[data-app-shell-main-content-layout]')"
        let countExpression = "\(layout).style.writeCount('--cae-header-offset')"
        let initialWrites = try harness.int(countExpression)

        try harness.evaluate("window.__autoStyleMutation = true; window.__triggerMutation(1); window.__flushRAF(); window.__flushTimers();")
        XCTAssertEqual(try harness.int(countExpression), initialWrites)
        XCTAssertEqual(try harness.int("window.__rafQueue.length"), 0)
        XCTAssertEqual(try harness.int("window.__timerQueue.length"), 0)

        try harness.evaluate("window.__autoStyleMutation = false; \(layout).style.setProperty('--app-shell-main-content-frame-top-offset', '52px'); window.__autoStyleMutation = true; window.__triggerMutation(1); window.__flushRAF(); window.__flushTimers();")
        XCTAssertEqual(try harness.string("\(layout).style.getPropertyValue('--cae-header-offset')"), "52px")
        XCTAssertEqual(try harness.int(countExpression), initialWrites + 1)
        try harness.evaluate("window.__flushRAF(); window.__flushTimers();")
        XCTAssertEqual(try harness.int(countExpression), initialWrites + 1)
        XCTAssertEqual(try harness.int("window.__rafQueue.length"), 0)
        XCTAssertEqual(try harness.int("window.__timerQueue.length"), 0)
    }

    func testHeaderAutomaticFallsBackAndFailsOpenWithoutNativePixelVariable() throws {
        let fallback = try JSRuntimeHarness(fixture: "current-surface")
        try fallback.evaluate("""
        (() => {
          const layout = document.querySelector('[data-app-shell-main-content-layout]');
          layout.style.removeProperty('--app-shell-main-content-frame-top-offset');
          layout.style.setProperty('--inset-toolbar', '47px');
        })();
        """)
        try fallback.loadAdapter("header-offset")
        let result = try fallback.invoke("install", request: fallback.request(
            id: 1, adapterId: "header-offset", operation: "install", config: ["mode": "automatic", "customOffset": 0]
        ))
        XCTAssertEqual((result["result"] as? [String: Any])?["offset"] as? Int, 47)

        let unavailable = try JSRuntimeHarness(fixture: "current-surface")
        try unavailable.evaluate("""
        (() => {
          const layout = document.querySelector('[data-app-shell-main-content-layout]');
          layout.style.removeProperty('--app-shell-main-content-frame-top-offset');
          layout.style.removeProperty('--inset-toolbar');
          layout.style.removeProperty('--height-toolbar');
        })();
        """)
        try unavailable.loadAdapter("header-offset")
        let failedOpen = try unavailable.invoke("install", request: unavailable.request(
            id: 2, adapterId: "header-offset", operation: "install", config: ["mode": "automatic", "customOffset": 0]
        ))
        XCTAssertEqual((failedOpen["result"] as? [String: Any])?["qualified"] as? Bool, false)
        XCTAssertEqual((failedOpen["result"] as? [String: Any])?["reason"] as? String, "native-toolbar-offset-unavailable")
        XCTAssertTrue(try unavailable.value("document.getElementById('cae-header-offset-style')").isNull)
    }

    func testIMEGuardHandlesEditorAndDescendantCompositionOnlyThenRestores() throws {
        let harness = try JSRuntimeHarness(fixture: "current-surface")
        try harness.evaluate("""
        (() => {
          document.querySelector(".ProseMirror[contenteditable='true']")
            .setAttribute('data-cae-ime-enter-guard', 'host-ime');
          window.__captureListeners = {};
          window.addEventListener = (type, callback, capture) => {
            if (!capture) return;
            (window.__captureListeners[type] ||= []).push(callback);
          };
          window.removeEventListener = (type, callback, capture) => {
            if (!capture) return;
            window.__captureListeners[type] = (window.__captureListeners[type] || [])
              .filter((item) => item !== callback);
          };
          window.__windowListenerCount = (type) => (window.__captureListeners[type] || []).length;
          window.__dispatchIME = (event) => {
            for (const callback of (window.__captureListeners[event.type] || []).slice()) callback(event);
            return event;
          };
        })();
        """)
        try harness.loadAdapter("ime-enter-guard")
        _ = try harness.invoke("install", request: harness.request(
            id: 1,
            adapterId: "ime-enter-guard",
            operation: "install",
            config: ["protectCompositionEnter": true]
        ))

        let editor = "document.querySelector(\".ProseMirror[contenteditable='true']\")"
        XCTAssertEqual(try harness.int("window.__windowListenerCount('keydown')"), 1)
        XCTAssertEqual(try harness.int("window.__windowListenerCount('compositionstart')"), 1)
        XCTAssertEqual(try harness.int("window.__windowListenerCount('compositionend')"), 1)
        XCTAssertEqual(try harness.int("\(editor).listenerCount('keydown')"), 0)
        XCTAssertTrue(try harness.bool("(() => { const editor = \(editor); const e = document.__event('keydown', editor, { key: 'Enter', isComposing: true }); window.__dispatchIME(e); return e.defaultPrevented && e.immediatePropagationStopped; })()"))
        XCTAssertTrue(try harness.bool("(() => { const e = document.__event('keydown', document.querySelector('[data-editor-child]'), { key: 'Enter', isComposing: true }); window.__dispatchIME(e); return e.defaultPrevented; })()"))
        XCTAssertTrue(try harness.bool("(() => { const e = document.__event('keydown', document.querySelector('[data-editor-child]'), { key: 'Process', code: 'Enter', keyCode: 229 }); window.__dispatchIME(e); return e.defaultPrevented; })()"))
        XCTAssertFalse(try harness.bool("(() => { const e = document.__event('keydown', \(editor), { key: 'Process', code: 'KeyA', keyCode: 229 }); window.__dispatchIME(e); return e.defaultPrevented; })()"))
        XCTAssertTrue(try harness.bool("(() => { const editor = \(editor); window.__dispatchIME(document.__event('compositionstart', editor)); const e = document.__event('keydown', editor, { key: 'Enter' }); window.__dispatchIME(e); return e.defaultPrevented; })()"))
        XCTAssertTrue(try harness.bool("(() => { const editor = \(editor); window.__dispatchIME(document.__event('compositionend', editor)); const e = document.__event('keydown', editor, { key: 'Enter' }); window.__dispatchIME(e); return e.defaultPrevented; })()"))
        try harness.evaluate("window.__now += 121")
        XCTAssertFalse(try harness.bool("(() => { const e = document.__event('keydown', \(editor), { key: 'Enter' }); window.__dispatchIME(e); return e.defaultPrevented; })()"))
        XCTAssertFalse(try harness.bool("(() => { const e = document.__event('keydown', document.querySelector('[data-request-input]'), { key: 'Enter', isComposing: true }); window.__dispatchIME(e); return e.defaultPrevented; })()"))

        _ = try harness.invoke("uninstall", request: harness.request(
            id: 2, adapterId: "ime-enter-guard", operation: "uninstall", config: [:]
        ))
        XCTAssertEqual(try harness.int("window.__windowListenerCount('keydown')"), 0)
        XCTAssertEqual(try harness.int("window.__windowListenerCount('compositionstart')"), 0)
        XCTAssertEqual(try harness.int("window.__windowListenerCount('compositionend')"), 0)
        XCTAssertEqual(try harness.string("\(editor).getAttribute('data-cae-ime-enter-guard')"), "host-ime")
    }

    func testIMEGuardWindowCapturePrecedesSkillHandlerAndConsumesOnlyTerminalEnter() throws {
        let harness = try JSRuntimeHarness(fixture: "current-surface")
        try harness.evaluate("""
        (() => {
          window.__captureListeners = {};
          window.addEventListener = (type, callback, capture) => {
            if (!capture) return;
            (window.__captureListeners[type] ||= []).push(callback);
          };
          window.removeEventListener = (type, callback, capture) => {
            if (!capture) return;
            window.__captureListeners[type] = (window.__captureListeners[type] || [])
              .filter((item) => item !== callback);
          };
          window.__windowListenerCount = (type) => (window.__captureListeners[type] || []).length;
          window.__skillHandlerCalls = 0;
          window.__dispatchBeforeSkill = (event) => {
            for (const callback of (window.__captureListeners[event.type] || []).slice()) {
              callback(event);
              if (event.immediatePropagationStopped) return event;
            }
            if (event.type === 'keydown' && event.key === 'Enter') {
              window.__skillHandlerCalls += 1;
            }
            return event;
          };
        })();
        """)
        try harness.loadAdapter("ime-enter-guard")
        _ = try harness.invoke("install", request: harness.request(
            id: 1,
            adapterId: "ime-enter-guard",
            operation: "install",
            config: ["protectCompositionEnter": true]
        ))

        let editor = "document.querySelector(\".ProseMirror[contenteditable='true']\")"
        XCTAssertEqual(try harness.int("window.__windowListenerCount('keydown')"), 1)
        XCTAssertEqual(try harness.int("window.__windowListenerCount('compositionstart')"), 1)
        XCTAssertEqual(try harness.int("window.__windowListenerCount('compositionend')"), 1)
        XCTAssertEqual(try harness.int("\(editor).listenerCount('keydown')"), 0)

        XCTAssertTrue(try harness.bool("""
        (() => {
          const editor = \(editor);
          window.__dispatchBeforeSkill(document.__event('compositionstart', editor));
          const composingEnter = document.__event('keydown', editor, { key: 'Enter' });
          window.__dispatchBeforeSkill(composingEnter);
          return composingEnter.defaultPrevented && composingEnter.immediatePropagationStopped && window.__skillHandlerCalls === 0;
        })()
        """))
        XCTAssertTrue(try harness.bool("""
        (() => {
          const editor = \(editor);
          window.__dispatchBeforeSkill(document.__event('compositionend', editor));
          const terminalEnter = document.__event('keydown', editor, { key: 'Enter' });
          window.__dispatchBeforeSkill(terminalEnter);
          return terminalEnter.defaultPrevented && terminalEnter.immediatePropagationStopped && window.__skillHandlerCalls === 0;
        })()
        """))
        XCTAssertTrue(try harness.bool("""
        (() => {
          const ordinaryEnter = document.__event('keydown', \(editor), { key: 'Enter' });
          window.__dispatchBeforeSkill(ordinaryEnter);
          return !ordinaryEnter.defaultPrevented && window.__skillHandlerCalls === 1;
        })()
        """))
        XCTAssertTrue(try harness.bool("""
        (() => {
          const outsideEnter = document.__event('keydown', document.querySelector('[data-request-input]'), {
            key: 'Enter',
            isComposing: true
          });
          window.__dispatchBeforeSkill(outsideEnter);
          return !outsideEnter.defaultPrevented && window.__skillHandlerCalls === 2;
        })()
        """))

        try harness.evaluate("""
        window.__oldIMEEditor = \(editor);
        window.__dispatchBeforeSkill(document.__event('compositionstart', window.__oldIMEEditor));
        document.__replaceSurface('editor');
        window.__freshIMEEditor = document.querySelector(".ProseMirror[contenteditable='true']");
        window.__triggerMutation(1);
        window.__flushRAF();
        window.__flushTimers();
        """)
        XCTAssertEqual(try harness.int("window.__windowListenerCount('keydown')"), 1)
        XCTAssertEqual(try harness.int("window.__windowListenerCount('compositionstart')"), 1)
        XCTAssertEqual(try harness.int("window.__windowListenerCount('compositionend')"), 1)
        XCTAssertTrue(try harness.value("window.__oldIMEEditor.getAttribute('data-cae-ime-enter-guard')").isNull)
        XCTAssertEqual(try harness.string("window.__freshIMEEditor.getAttribute('data-cae-ime-enter-guard')"), "true")
        XCTAssertTrue(try harness.bool("""
        (() => {
          const ordinaryEnter = document.__event('keydown', window.__freshIMEEditor, { key: 'Enter' });
          window.__dispatchBeforeSkill(ordinaryEnter);
          return !ordinaryEnter.defaultPrevented && window.__skillHandlerCalls === 3;
        })()
        """))

        _ = try harness.invoke("uninstall", request: harness.request(
            id: 2, adapterId: "ime-enter-guard", operation: "uninstall", config: [:]
        ))
        XCTAssertEqual(try harness.int("window.__windowListenerCount('keydown')"), 0)
        XCTAssertEqual(try harness.int("window.__windowListenerCount('compositionstart')"), 0)
        XCTAssertEqual(try harness.int("window.__windowListenerCount('compositionend')"), 0)
        XCTAssertTrue(try harness.value("window.__freshIMEEditor.getAttribute('data-cae-ime-enter-guard')").isNull)
    }

    func testIMEGuardDisabledConfigurationInstallsNoListenersOrMarker() throws {
        let harness = try JSRuntimeHarness(fixture: "current-surface")
        try harness.evaluate("""
        window.__captureListeners = {};
        window.addEventListener = (type, callback) => { (window.__captureListeners[type] ||= []).push(callback); };
        window.removeEventListener = (type, callback) => {
          window.__captureListeners[type] = (window.__captureListeners[type] || []).filter((item) => item !== callback);
        };
        window.__windowListenerCount = (type) => (window.__captureListeners[type] || []).length;
        """)
        try harness.loadAdapter("ime-enter-guard")
        _ = try harness.invoke("install", request: harness.request(
            id: 1,
            adapterId: "ime-enter-guard",
            operation: "install",
            config: ["protectCompositionEnter": false]
        ))

        let editor = "document.querySelector(\".ProseMirror[contenteditable='true']\")"
        XCTAssertEqual(try harness.int("window.__windowListenerCount('keydown')"), 0)
        XCTAssertEqual(try harness.int("window.__windowListenerCount('compositionstart')"), 0)
        XCTAssertEqual(try harness.int("window.__windowListenerCount('compositionend')"), 0)
        XCTAssertEqual(try harness.int("\(editor).listenerCount('keydown')"), 0)
        XCTAssertTrue(try harness.value("\(editor).getAttribute('data-cae-ime-enter-guard')").isNull)
        XCTAssertEqual(try harness.int("window.__codexAppExtensionV2.observerCount()"), 0)
    }

    func testMarkdownUsesStableSemanticCandidatesAndRestoresHostValues() throws {
        let harness = try JSRuntimeHarness(fixture: "current-surface")
        XCTAssertTrue(harness.fixtureHTML.contains("Nested quote"))
        try harness.evaluate("""
        (() => {
          Object.defineProperty(window.__FakeNode.prototype, 'textContent', {
            configurable: true,
            get: function() { return this.__textContent || ''; },
            set: function(value) {
              this.__textContent = String(value);
              this.__textContentWriteCount = (this.__textContentWriteCount || 0) + 1;
            }
          });
          window.__FakeNode.prototype.textContentWriteCount = function() {
            return this.__textContentWriteCount || 0;
          };
          const scroller = document.querySelector('.thread-scroll-container');
          scroller.setAttribute('data-cae-markdown-theme', 'host-markdown');
          scroller.style.setProperty('--cae-heading-color', '#010203', 'important');
        })();
        """)
        try harness.loadAdapter("markdown-semantic-theme")
        let classicConfig: [String: Any] = [
            "heading": ["enabled": true, "color": "#F2C94C"],
            "strongText": ["enabled": true, "color": "#F2C94C", "fontWeight": 800],
            "inlineCode": [
                "textColor": "#df3079",
                "backgroundColor": "rgba(223, 48, 121, 0.10)",
                "borderColor": "rgba(223, 48, 121, 0.18)"
            ],
            "blockquote": [
                "borderColor": "#df3079",
                "textColor": "inherit",
                "backgroundColor": "rgba(223, 48, 121, 0.06)"
            ]
        ]
        let installed = try harness.invoke("install", request: harness.request(
            id: 1,
            adapterId: "markdown-semantic-theme",
            operation: "install",
            config: classicConfig
        ))

        XCTAssertEqual((installed["result"] as? [String: Any])?["candidateCount"] as? Int, 2)
        let css = try harness.string("document.getElementById('cae-markdown-semantic-theme-style').textContent")
        let prefix = ".thread-scroll-container[data-cae-markdown-theme='true'] [data-selected-text-overlay-target]"
        XCTAssertTrue(css.contains(prefix))
        XCTAssertTrue(css.contains(":where(h1, h2, h3, h4, h5, h6)"))
        XCTAssertTrue(css.contains(":where(p, li, blockquote, td, th) :where(strong)"))
        XCTAssertTrue(css.contains(":where(.inline-markdown)"))
        XCTAssertTrue(css.contains("border: 1px solid var(--cae-inline-code-border) !important"))
        XCTAssertTrue(css.contains("border-radius: 6px !important"))
        XCTAssertTrue(css.contains("padding: 0.08em 0.36em !important"))
        XCTAssertTrue(css.contains(":where(pre, pre *) code"))
        XCTAssertTrue(css.contains("color: inherit !important"))
        XCTAssertTrue(css.contains("border: 0 !important"))
        XCTAssertTrue(css.contains(":where(blockquote) {"))
        XCTAssertTrue(css.contains("border-left: 3px solid var(--cae-blockquote-border) !important"))
        XCTAssertTrue(css.contains("border-radius: 0 6px 6px 0 !important"))
        XCTAssertTrue(css.contains("margin-inline: 0 !important"))
        XCTAssertTrue(css.contains("padding: 0.65em 0.9em !important"))
        XCTAssertTrue(css.contains(":where(blockquote) blockquote"))
        XCTAssertTrue(css.contains("background: transparent !important"))
        XCTAssertTrue(css.contains("border-left: 0 !important"))
        XCTAssertTrue(css.contains("padding: 0 !important"))
        XCTAssertFalse(css.contains("main.main-surface"))
        XCTAssertFalse(css.contains("innerHTML"))
        let childCount = try harness.int("document.querySelector('[data-selected-text-overlay-target]').children.length")

        let scroller = "document.querySelector('.thread-scroll-container')"
        let style = "document.getElementById('cae-markdown-semantic-theme-style')"
        let headingWrites = try harness.int("\(scroller).style.writeCount('--cae-heading-color')")
        let styleWrites = try harness.int("\(style).textContentWriteCount()")
        _ = try harness.invoke("update", request: harness.request(
            id: 2,
            adapterId: "markdown-semantic-theme",
            operation: "update",
            config: classicConfig
        ))
        XCTAssertEqual(try harness.int("\(scroller).style.writeCount('--cae-heading-color')"), headingWrites)
        XCTAssertEqual(try harness.int("\(style).textContentWriteCount()"), styleWrites)

        var disabledHeading = classicConfig
        disabledHeading["heading"] = ["enabled": false, "color": "#F2C94C"]
        _ = try harness.invoke("update", request: harness.request(
            id: 3, adapterId: "markdown-semantic-theme", operation: "update", config: disabledHeading
        ))
        XCTAssertFalse(try harness.string("document.getElementById('cae-markdown-semantic-theme-style').textContent").contains(":where(h1, h2, h3, h4, h5, h6)"))
        XCTAssertEqual(try harness.int("\(style).textContentWriteCount()"), styleWrites + 1)

        _ = try harness.invoke("uninstall", request: harness.request(
            id: 4, adapterId: "markdown-semantic-theme", operation: "uninstall", config: [:]
        ))
        XCTAssertEqual(try harness.string("document.querySelector('.thread-scroll-container').getAttribute('data-cae-markdown-theme')"), "host-markdown")
        XCTAssertEqual(try harness.string("document.querySelector('.thread-scroll-container').style.getPropertyValue('--cae-heading-color')"), "#010203")
        XCTAssertEqual(try harness.string("document.querySelector('.thread-scroll-container').style.getPropertyPriority('--cae-heading-color')"), "important")
        XCTAssertEqual(try harness.int("document.querySelector('[data-selected-text-overlay-target]').children.length"), childCount)
        XCTAssertTrue(try harness.value("document.getElementById('cae-markdown-semantic-theme-style')").isNull)
    }

    func testTransientEmptyNewChatSurfaceWaitsAndEveryAdapterRecoversAfterDOMAppears() throws {
        for (index, adapter) in ["wide-layout", "header-offset", "ime-enter-guard", "markdown-semantic-theme"].enumerated() {
            let harness = try JSRuntimeHarness(fixture: "current-surface")
            try harness.loadAdapter(adapter)
            try harness.evaluate("document.__loadFixture('')")

            let waiting = try harness.invoke("install", request: harness.request(
                id: index + 1,
                adapterId: adapter,
                operation: "install",
                config: harness.defaultConfig(adapterId: adapter)
            ))
            let result = try XCTUnwrap(waiting["result"] as? [String: Any], adapter)
            XCTAssertEqual(result["qualified"] as? Bool, false, adapter)
            XCTAssertEqual(result["recoverable"] as? Bool, true, adapter)
            XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.performanceSnapshot().observers.find((item) => item.adapterId === '\(adapter)').recoverable === true"), adapter)

            try harness.evaluate("""
            document.__loadFixture('<main data-app-shell-main-content-layout></main>');
            """)
            if adapter == "wide-layout" { try addSyntheticWideOwner(to: harness) }
            try harness.evaluate("window.__triggerMutation(1); window.__flushRAF(); window.__flushTimers();")

            XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.performanceSnapshot().observers.find((item) => item.adapterId === '\(adapter)').qualified === true"), adapter)
            XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.performanceSnapshot().observers.find((item) => item.adapterId === '\(adapter)').recoverable === false"), adapter)

            _ = try harness.invoke("uninstall", request: harness.request(
                id: 100 + index,
                adapterId: adapter,
                operation: "uninstall",
                config: [:]
            ))
            XCTAssertEqual(try harness.int("window.__codexAppExtensionV2.observerCount()"), 0, adapter)
        }
    }

    func testWideLayoutAppliesToUniqueEmptyTaskComposerAndUninstallRestoresHostState() throws {
        let harness = try JSRuntimeHarness(fixture: "current-surface")
        try harness.evaluate("""
        document.__loadFixture('<main data-app-shell-main-content-layout data-empty-task></main>');
        (() => {
          const layout = document.querySelector('[data-app-shell-main-content-layout]');
          const owner = layout.querySelectorAll("[class*='thread-composer-max-width']")[0];
          const staleOwner = new window.__FakeNode('stale-empty-task-owner');
          staleOwner.setAttribute('class', 'mx-auto max-w-(--thread-composer-max-width)');
          staleOwner.style.setProperty('--cae-wide-layout-owner-offset-x', '31px', 'important');
          layout.appendChild(staleOwner);
          layout.registerAll("[class*='thread-composer-max-width']", [owner, staleOwner]);
          layout.setAttribute('data-cae-wide-layout', 'host-empty');
          layout.style.setProperty('--thread-content-max-width', '777px', 'important');
          layout.style.setProperty('--markdown-wide-block-max-width', '778px', 'important');
          layout.style.setProperty('--cae-wide-layout-side-padding', '19px', 'important');
          layout.style.setProperty('--cae-wide-layout-content-offset-x', '21px', 'important');
          owner.style.setProperty('--cae-wide-layout-owner-offset-x', '13px', 'important');
          const style = document.createElement('style');
          style.id = 'cae-wide-layout-style';
          style.textContent = 'host-empty-style';
          document.head.appendChild(style);
          window.__emptyTaskOwner = owner;
          window.__staleEmptyTaskOwner = staleOwner;
        })();
        """)
        try harness.loadAdapter("wide-layout")

        let installed = try harness.invoke("install", request: harness.request(
            id: 1,
            adapterId: "wide-layout",
            operation: "install",
            config: harness.defaultConfig(adapterId: "wide-layout")
        ))
        XCTAssertEqual((installed["result"] as? [String: Any])?["qualified"] as? Bool, true)
        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.surface().qualified"))
        XCTAssertEqual(try harness.string("window.__codexAppExtensionV2.surface().kind"), "empty-composer")
        XCTAssertTrue(try harness.value("document.querySelector('.thread-scroll-container')").isNull)
        XCTAssertEqual(try harness.string("document.querySelector('[data-app-shell-main-content-layout]').getAttribute('data-cae-wide-layout')"), "true")
        XCTAssertEqual(
            try harness.string("document.querySelector('[data-app-shell-main-content-layout]').style.getPropertyValue('--thread-composer-max-width')"),
            "min(1800px, max(1px, calc(100% - 48px)))"
        )
        XCTAssertEqual(try harness.string("document.querySelector('[data-app-shell-main-content-layout]').style.getPropertyValue('--thread-content-max-width')"), "777px")
        XCTAssertEqual(try harness.string("document.querySelector('[data-app-shell-main-content-layout]').style.getPropertyValue('--markdown-wide-block-max-width')"), "778px")
        XCTAssertEqual(try harness.string("document.querySelector('[data-app-shell-main-content-layout]').style.getPropertyValue('--cae-wide-layout-side-padding')"), "19px")
        XCTAssertEqual(try harness.string("document.querySelector('[data-app-shell-main-content-layout]').style.getPropertyValue('--cae-wide-layout-content-offset-x')"), "21px")
        XCTAssertEqual(try harness.string("window.__emptyTaskOwner.style.getPropertyValue('--cae-wide-layout-owner-offset-x')"), "0px")
        XCTAssertEqual(try harness.string("window.__staleEmptyTaskOwner.style.getPropertyValue('--cae-wide-layout-owner-offset-x')"), "31px")
        XCTAssertEqual(try harness.string("window.__staleEmptyTaskOwner.style.getPropertyPriority('--cae-wide-layout-owner-offset-x')"), "important")
        XCTAssertTrue(try harness.string("document.getElementById('cae-wide-layout-style').textContent").contains("[data-app-shell-main-content-layout][data-cae-wide-layout='true']"))

        let diagnosed = try harness.invoke("diagnose", request: harness.request(
            id: 2, adapterId: "wide-layout", operation: "diagnose", config: [:]
        ))
        XCTAssertEqual((diagnosed["result"] as? [String: Any])?["qualified"] as? Bool, true)

        _ = try harness.invoke("uninstall", request: harness.request(
            id: 3, adapterId: "wide-layout", operation: "uninstall", config: [:]
        ))
        XCTAssertEqual(try harness.string("document.querySelector('[data-app-shell-main-content-layout]').getAttribute('data-cae-wide-layout')"), "host-empty")
        XCTAssertEqual(try harness.string("document.querySelector('[data-app-shell-main-content-layout]').style.getPropertyValue('--thread-content-max-width')"), "777px")
        XCTAssertEqual(try harness.string("document.querySelector('[data-app-shell-main-content-layout]').style.getPropertyPriority('--thread-content-max-width')"), "important")
        XCTAssertEqual(try harness.string("document.querySelector('[data-app-shell-main-content-layout]').style.getPropertyValue('--markdown-wide-block-max-width')"), "778px")
        XCTAssertEqual(try harness.string("document.querySelector('[data-app-shell-main-content-layout]').style.getPropertyValue('--cae-wide-layout-side-padding')"), "19px")
        XCTAssertEqual(try harness.string("document.querySelector('[data-app-shell-main-content-layout]').style.getPropertyValue('--cae-wide-layout-content-offset-x')"), "21px")
        XCTAssertEqual(try harness.string("window.__emptyTaskOwner.style.getPropertyValue('--cae-wide-layout-owner-offset-x')"), "13px")
        XCTAssertEqual(try harness.string("window.__emptyTaskOwner.style.getPropertyPriority('--cae-wide-layout-owner-offset-x')"), "important")
        XCTAssertEqual(try harness.string("window.__staleEmptyTaskOwner.style.getPropertyValue('--cae-wide-layout-owner-offset-x')"), "31px")
        XCTAssertEqual(try harness.string("document.getElementById('cae-wide-layout-style').textContent"), "host-empty-style")
    }

    func testWideLayoutAcceptsCanonicalContentWidthOwnerOnUniqueEmptyTaskPath() throws {
        let harness = try JSRuntimeHarness(fixture: "current-surface")
        try harness.evaluate("""
        document.__loadFixture('<main data-app-shell-main-content-layout data-empty-task></main>');
        (() => {
          const layout = document.querySelector('[data-app-shell-main-content-layout]');
          const editor = document.querySelector(".ProseMirror[contenteditable='true']");
          const owner = layout.querySelectorAll("[class*='thread-composer-max-width']")[0];
          owner.setAttribute('class', 'mx-auto w-full max-w-(--thread-content-max-width) px-toolbar');
          const hiddenOwner = new window.__FakeNode('hidden-marked-owner');
          hiddenOwner.setAttribute('class', 'mx-auto max-w-(--thread-content-max-width)');
          hiddenOwner.setAttribute('aria-hidden', 'true');
          hiddenOwner.style.setProperty('--cae-wide-layout-owner-offset-x', '31px', 'important');
          const hiddenEditor = new window.__FakeNode('hidden-marked-editor');
          hiddenEditor.setAttribute('class', 'ProseMirror');
          hiddenEditor.setAttribute('contenteditable', 'true');
          hiddenEditor.setAttribute('data-codex-composer', 'true');
          hiddenOwner.appendChild(hiddenEditor);
          layout.appendChild(hiddenOwner);
          layout.registerAll("[class*='thread-content-max-width']", [owner, hiddenOwner]);
          layout.registerAll("[class*='thread-composer-max-width']", []);
          document.__registerAll(".ProseMirror[data-codex-composer='true'][contenteditable='true'], .ProseMirror[data-codex-composer='true'][contenteditable='plaintext-only']", [editor, hiddenEditor]);
          window.__canonicalEmptyTaskOwner = owner;
          window.__hiddenMarkedOwner = hiddenOwner;
          window.__hiddenMarkedEditor = hiddenEditor;
        })();
        """)
        try harness.loadAdapter("wide-layout")

        let installed = try harness.invoke("install", request: harness.request(
            id: 1,
            adapterId: "wide-layout",
            operation: "install",
            config: harness.defaultConfig(adapterId: "wide-layout")
        ))
        XCTAssertEqual((installed["result"] as? [String: Any])?["qualified"] as? Bool, true)
        XCTAssertEqual(try harness.string("window.__codexAppExtensionV2.surface().kind"), "empty-composer")
        XCTAssertEqual(try harness.string("window.__codexAppExtensionV2.surface().editorSignal"), "marked")
        XCTAssertEqual(try harness.string("window.__canonicalEmptyTaskOwner.style.getPropertyValue('--cae-wide-layout-owner-offset-x')"), "0px")
        XCTAssertEqual(try harness.string("window.__hiddenMarkedOwner.style.getPropertyValue('--cae-wide-layout-owner-offset-x')"), "31px")
        XCTAssertEqual(try harness.string("window.__hiddenMarkedOwner.style.getPropertyPriority('--cae-wide-layout-owner-offset-x')"), "important")
        XCTAssertTrue(try harness.value("window.__hiddenMarkedEditor.getAttribute('data-cae-wide-layout-editor')").isNull)
        XCTAssertEqual(
            try harness.string("document.querySelector('[data-app-shell-main-content-layout]').style.getPropertyValue('--thread-composer-max-width')"),
            "min(1800px, max(1px, calc(100% - 48px)))"
        )
        XCTAssertEqual(try harness.string("document.querySelector('[data-app-shell-main-content-layout]').style.getPropertyValue('--thread-content-max-width')"), "")
        XCTAssertTrue(try harness.bool("document.getElementById('cae-wide-layout-style').textContent.includes(\"[class*='thread-content-max-width']:has(\")"))
        XCTAssertTrue(try harness.bool("document.getElementById('cae-wide-layout-style').textContent.includes('data-cae-wide-layout-editor')"))
        XCTAssertFalse(try harness.bool("document.getElementById('cae-wide-layout-style').textContent.includes('data-codex-composer')"))

        let diagnosed = try harness.invoke("diagnose", request: harness.request(
            id: 2, adapterId: "wide-layout", operation: "diagnose", config: [:]
        ))
        XCTAssertEqual((diagnosed["result"] as? [String: Any])?["qualified"] as? Bool, true)

        _ = try harness.invoke("uninstall", request: harness.request(
            id: 3, adapterId: "wide-layout", operation: "uninstall", config: [:]
        ))
        XCTAssertTrue(try harness.value("document.querySelector('[data-app-shell-main-content-layout]').getAttribute('data-cae-wide-layout')").isNull)
        XCTAssertEqual(try harness.string("document.querySelector('[data-app-shell-main-content-layout]').style.getPropertyValue('--thread-composer-max-width')"), "")
        XCTAssertEqual(try harness.string("window.__canonicalEmptyTaskOwner.style.getPropertyValue('--cae-wide-layout-owner-offset-x')"), "")
        XCTAssertEqual(try harness.string("window.__hiddenMarkedOwner.style.getPropertyValue('--cae-wide-layout-owner-offset-x')"), "31px")
        XCTAssertTrue(try harness.value("window.__hiddenMarkedEditor.getAttribute('data-cae-wide-layout-editor')").isNull)
        XCTAssertTrue(try harness.value("document.getElementById('cae-wide-layout-style')").isNull)
    }

    func testWideLayoutTracksPendingEmptyOwnerClassBidirectionally() throws {
        let harness = try JSRuntimeHarness(fixture: "current-surface")
        try harness.evaluate("""
        document.__loadFixture('<main data-app-shell-main-content-layout data-empty-task></main>');
        (() => {
          const layout = document.querySelector('[data-app-shell-main-content-layout]');
          const owner = layout.querySelectorAll("[class*='thread-composer-max-width']")[0];
          owner.setAttribute('class', 'pending-empty-composer-shell');
          layout.registerAll("[class*='thread-content-max-width']", []);
          layout.registerAll("[class*='thread-composer-max-width']", []);
          window.__pendingEmptyOwner = owner;
          window.__dispatchObservedAttribute = (node, attributeName) => {
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
        })();
        """)
        try harness.loadAdapter("wide-layout")

        let waiting = try harness.invoke("install", request: harness.request(
            id: 1,
            adapterId: "wide-layout",
            operation: "install",
            config: harness.defaultConfig(adapterId: "wide-layout")
        ))
        let waitingResult = try XCTUnwrap(waiting["result"] as? [String: Any])
        XCTAssertEqual(waitingResult["qualified"] as? Bool, false)
        XCTAssertEqual(waitingResult["recoverable"] as? Bool, true)
        XCTAssertEqual(waitingResult["reason"] as? String, "wide-composer-owner-missing")
        XCTAssertTrue(try harness.bool("window.__mutationObservers.some((observer) => !observer.disconnected && observer.targets.includes(window.__pendingEmptyOwner))"))

        try harness.evaluate("""
        (() => {
          const layout = document.querySelector('[data-app-shell-main-content-layout]');
          window.__pendingEmptyOwner.setAttribute('class', 'mx-auto max-w-(--thread-content-max-width)');
          layout.registerAll("[class*='thread-content-max-width']", [window.__pendingEmptyOwner]);
          window.__dispatchObservedAttribute(window.__pendingEmptyOwner, 'class');
        })();
        """)
        XCTAssertEqual(try harness.int("window.__rafQueue.length"), 1)
        try harness.evaluate("window.__flushRAF(); window.__flushTimers();")
        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.performanceSnapshot().observers.find((item) => item.adapterId === 'wide-layout').qualified === true"))
        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.performanceSnapshot().observers.find((item) => item.adapterId === 'wide-layout').recoverable === false"))
        XCTAssertEqual(try harness.string("window.__pendingEmptyOwner.style.getPropertyValue('--cae-wide-layout-owner-offset-x')"), "0px")

        try harness.evaluate("""
        (() => {
          const layout = document.querySelector('[data-app-shell-main-content-layout]');
          window.__pendingEmptyOwner.setAttribute('class', 'pending-empty-composer-shell');
          layout.registerAll("[class*='thread-content-max-width']", []);
          window.__dispatchObservedAttribute(window.__pendingEmptyOwner, 'class');
        })();
        """)
        XCTAssertEqual(try harness.int("window.__rafQueue.length"), 1)
        try harness.evaluate("window.__flushRAF(); window.__flushTimers();")
        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.performanceSnapshot().observers.find((item) => item.adapterId === 'wide-layout').qualified === false"))
        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.performanceSnapshot().observers.find((item) => item.adapterId === 'wide-layout').recoverable === true"))
        XCTAssertEqual(try harness.string("window.__pendingEmptyOwner.style.getPropertyValue('--cae-wide-layout-owner-offset-x')"), "")
        XCTAssertEqual(try harness.string("document.querySelector('[data-app-shell-main-content-layout]').getAttribute('data-cae-wide-layout')"), "true")
        XCTAssertEqual(
            try harness.string("document.querySelector('[data-app-shell-main-content-layout]').style.getPropertyValue('--thread-composer-max-width')"),
            "min(1800px, max(1px, calc(100% - 48px)))"
        )

        _ = try harness.invoke("uninstall", request: harness.request(
            id: 2, adapterId: "wide-layout", operation: "uninstall", config: [:]
        ))
        XCTAssertTrue(try harness.value("document.querySelector('[data-app-shell-main-content-layout]').getAttribute('data-cae-wide-layout')").isNull)
        XCTAssertEqual(try harness.string("document.querySelector('[data-app-shell-main-content-layout]').style.getPropertyValue('--thread-composer-max-width')"), "")
        XCTAssertTrue(try harness.value("document.querySelector(\".ProseMirror[contenteditable='true']\").getAttribute('data-cae-wide-layout-editor')").isNull)
        XCTAssertTrue(try harness.value("document.getElementById('cae-wide-layout-style')").isNull)
        XCTAssertTrue(try harness.bool("window.__mutationObservers.every((observer) => observer.disconnected)"))
        XCTAssertEqual(try harness.int("window.__rafQueue.length"), 0)
        XCTAssertEqual(try harness.int("window.__timerQueue.length"), 0)
    }

    func testWideLayoutSwitchesBetweenEmptyTaskAndSessionWithoutScopeResidue() throws {
        let harness = try JSRuntimeHarness(fixture: "current-surface")
        try harness.evaluate("document.__loadFixture('<main data-app-shell-main-content-layout data-empty-task></main>')")
        try harness.loadAdapter("wide-layout")
        _ = try harness.invoke("install", request: harness.request(
            id: 1,
            adapterId: "wide-layout",
            operation: "install",
            config: harness.defaultConfig(adapterId: "wide-layout")
        ))

        try harness.evaluate("""
        window.__oldEmptyLayout = document.querySelector('[data-app-shell-main-content-layout]');
        window.__oldEmptyOwner = window.__oldEmptyLayout.querySelectorAll("[class*='thread-composer-max-width']")[0];
        document.__setSurfaceMode('session');
        window.__triggerMutation(1);
        window.__flushRAF();
        window.__flushTimers();
        """)
        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.surface().qualified"))
        XCTAssertTrue(try harness.value("window.__oldEmptyLayout.getAttribute('data-cae-wide-layout')").isNull)
        XCTAssertEqual(try harness.string("window.__oldEmptyLayout.style.getPropertyValue('--thread-content-max-width')"), "")
        XCTAssertEqual(try harness.string("window.__oldEmptyOwner.style.getPropertyValue('--cae-wide-layout-owner-offset-x')"), "")
        XCTAssertEqual(try harness.string("document.querySelector('.thread-scroll-container').getAttribute('data-cae-wide-layout')"), "true")

        try harness.evaluate("""
        window.__oldSessionScroller = document.querySelector('.thread-scroll-container');
        window.__oldSessionOwner = window.__oldSessionScroller.querySelectorAll("[class*='thread-content-max-width']")[0];
        document.__setSurfaceMode('empty-task');
        window.__triggerMutation(1);
        window.__flushRAF();
        window.__flushTimers();
        """)
        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.surface().qualified"))
        XCTAssertEqual(try harness.string("window.__codexAppExtensionV2.surface().kind"), "empty-composer")
        XCTAssertTrue(try harness.value("document.querySelector('.thread-scroll-container')").isNull)
        XCTAssertTrue(try harness.value("window.__oldSessionScroller.getAttribute('data-cae-wide-layout')").isNull)
        XCTAssertEqual(try harness.string("window.__oldSessionScroller.style.getPropertyValue('--thread-content-max-width')"), "")
        XCTAssertEqual(try harness.string("window.__oldSessionOwner.style.getPropertyValue('--cae-wide-layout-owner-offset-x')"), "")
        XCTAssertEqual(try harness.string("document.querySelector('[data-app-shell-main-content-layout]').getAttribute('data-cae-wide-layout')"), "true")
        XCTAssertEqual(
            try harness.string("document.querySelector('[data-app-shell-main-content-layout]').style.getPropertyValue('--thread-composer-max-width')"),
            "min(1800px, max(1px, calc(100% - 48px)))"
        )
        XCTAssertEqual(try harness.string("document.querySelector('[data-app-shell-main-content-layout]').style.getPropertyValue('--thread-content-max-width')"), "")
        XCTAssertEqual(try harness.string("document.querySelector('[data-app-shell-main-content-layout]').style.getPropertyValue('--markdown-wide-block-max-width')"), "")
        XCTAssertEqual(try harness.string("document.querySelector('[data-app-shell-main-content-layout]').style.getPropertyValue('--cae-wide-layout-side-padding')"), "")
        XCTAssertEqual(try harness.string("document.querySelector('[data-app-shell-main-content-layout]').style.getPropertyValue('--cae-wide-layout-content-offset-x')"), "")

        let diagnosed = try harness.invoke("diagnose", request: harness.request(
            id: 2, adapterId: "wide-layout", operation: "diagnose", config: [:]
        ))
        XCTAssertEqual((diagnosed["result"] as? [String: Any])?["qualified"] as? Bool, true)

        _ = try harness.invoke("uninstall", request: harness.request(
            id: 3, adapterId: "wide-layout", operation: "uninstall", config: [:]
        ))
        XCTAssertTrue(try harness.value("document.querySelector('[data-app-shell-main-content-layout]').getAttribute('data-cae-wide-layout')").isNull)
        XCTAssertEqual(try harness.string("document.querySelector('[data-app-shell-main-content-layout]').style.getPropertyValue('--thread-content-max-width')"), "")
        XCTAssertTrue(try harness.value("document.getElementById('cae-wide-layout-style')").isNull)
        XCTAssertEqual(try harness.int("window.__codexAppExtensionV2.observerCount()"), 0)
    }

    func testWideLayoutTreatsDuplicateEmptyTaskEditorsAsHardStructuralConflict() throws {
        let harness = try JSRuntimeHarness(fixture: "current-surface")
        try harness.evaluate("document.__loadFixture('<main data-app-shell-main-content-layout data-empty-task data-duplicate-editor></main>')")
        try harness.loadAdapter("wide-layout")

        let installed = try harness.invoke("install", request: harness.request(
            id: 1,
            adapterId: "wide-layout",
            operation: "install",
            config: harness.defaultConfig(adapterId: "wide-layout")
        ))
        let result = try XCTUnwrap(installed["result"] as? [String: Any])
        XCTAssertEqual(result["qualified"] as? Bool, false)
        XCTAssertEqual(result["recoverable"] as? Bool, false)
        XCTAssertEqual(result["reason"] as? String, "native-editor-ambiguous")
        XCTAssertTrue(try harness.value("document.querySelector('[data-app-shell-main-content-layout]').getAttribute('data-cae-wide-layout')").isNull)
        XCTAssertTrue(try harness.value("document.getElementById('cae-wide-layout-style')").isNull)

        _ = try harness.invoke("uninstall", request: harness.request(
            id: 2, adapterId: "wide-layout", operation: "uninstall", config: [:]
        ))
        XCTAssertEqual(try harness.int("window.__codexAppExtensionV2.observerCount()"), 0)
    }

    func testQualifiedEmptyNewChatRunsLayoutAndInputAdaptersWhileMarkdownWaits() throws {
        let harness = try JSRuntimeHarness(fixture: "current-surface")
        try harness.evaluate("""
        (() => {
          document.__loadFixture('<main data-app-shell-main-content-layout data-empty-task></main>');
          const editor = document.querySelector(".ProseMirror[contenteditable='true']");
          editor.removeAttribute('data-codex-composer');
          document.__registerAll(".ProseMirror[data-codex-composer='true'][contenteditable='true'], .ProseMirror[data-codex-composer='true'][contenteditable='plaintext-only']", []);
          document.__registerAll('[data-codex-composer]', []);
        })();
        """)
        for adapter in ["wide-layout", "header-offset", "ime-enter-guard", "markdown-semantic-theme"] {
            try harness.loadAdapter(adapter)
        }

        var responses: [String: [String: Any]] = [:]
        for (index, adapter) in ["wide-layout", "header-offset", "ime-enter-guard", "markdown-semantic-theme"].enumerated() {
            responses[adapter] = try harness.invoke("install", request: harness.request(
                id: index + 1,
                adapterId: adapter,
                operation: "install",
                config: harness.defaultConfig(adapterId: adapter)
            ))
        }

        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.surface().qualified"))
        XCTAssertEqual(try harness.string("window.__codexAppExtensionV2.surface().kind"), "empty-composer")
        XCTAssertEqual(try harness.string("window.__codexAppExtensionV2.surface().editorSignal"), "fallback")
        XCTAssertEqual((responses["wide-layout"]?["result"] as? [String: Any])?["qualified"] as? Bool, true)
        XCTAssertEqual((responses["header-offset"]?["result"] as? [String: Any])?["qualified"] as? Bool, true)
        XCTAssertEqual((responses["ime-enter-guard"]?["result"] as? [String: Any])?["qualified"] as? Bool, true)
        XCTAssertEqual((responses["markdown-semantic-theme"]?["result"] as? [String: Any])?["qualified"] as? Bool, false)
        XCTAssertEqual((responses["markdown-semantic-theme"]?["result"] as? [String: Any])?["recoverable"] as? Bool, true)
        XCTAssertEqual(try harness.string("document.querySelector('[data-app-shell-main-content-layout]').getAttribute('data-cae-wide-layout')"), "true")
        XCTAssertEqual(try harness.string("document.querySelector(\".ProseMirror[contenteditable='true']\").getAttribute('data-cae-wide-layout-editor')"), "true")
        XCTAssertTrue(try harness.bool("document.getElementById('cae-wide-layout-style').textContent.includes(\"[data-cae-wide-layout-editor='true']\")"))
        XCTAssertEqual(try harness.string("document.querySelector('[data-app-shell-main-content-layout]').getAttribute('data-cae-header-offset')"), "true")
        XCTAssertEqual(try harness.string("document.querySelector(\".ProseMirror[contenteditable='true']\").getAttribute('data-cae-ime-enter-guard')"), "true")
        XCTAssertTrue(try harness.value("document.getElementById('cae-markdown-semantic-theme-style')").isNull)

        try harness.evaluate("""
        (() => {
          const editor = document.querySelector(".ProseMirror[contenteditable='true']");
          const owner = editor.parentElement;
          owner.setAttribute('aria-hidden', 'true');
          window.__dispatchObservedAttribute(owner, 'aria-hidden');
        })();
        window.__flushRAF();
        window.__flushTimers();
        """)
        XCTAssertFalse(try harness.bool("window.__codexAppExtensionV2.surface().qualified"))
        XCTAssertTrue(try harness.value("document.querySelector('[data-app-shell-main-content-layout]').getAttribute('data-cae-wide-layout')").isNull)
        XCTAssertTrue(try harness.value("document.querySelector(\".ProseMirror[contenteditable='true']\").getAttribute('data-cae-ime-enter-guard')").isNull)

        try harness.evaluate("""
        (() => {
          const owner = document.querySelector(".ProseMirror[contenteditable='true']").parentElement;
          owner.removeAttribute('aria-hidden');
          window.__dispatchObservedAttribute(owner, 'aria-hidden');
        })();
        window.__flushRAF();
        window.__flushTimers();
        """)
        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.surface().qualified"))
        XCTAssertEqual(try harness.string("window.__codexAppExtensionV2.surface().editorSignal"), "fallback")
        XCTAssertEqual(try harness.string("document.querySelector('[data-app-shell-main-content-layout]').getAttribute('data-cae-wide-layout')"), "true")
        XCTAssertEqual(try harness.string("document.querySelector(\".ProseMirror[contenteditable='true']\").getAttribute('data-cae-ime-enter-guard')"), "true")

        try harness.evaluate("""
        (() => {
          const editor = document.querySelector(".ProseMirror[contenteditable='true']");
          editor.setAttribute('data-codex-composer', 'true');
          document.__registerAll(".ProseMirror[data-codex-composer='true'][contenteditable='true'], .ProseMirror[data-codex-composer='true'][contenteditable='plaintext-only']", [editor]);
          document.__registerAll('[data-codex-composer]', [editor]);
        })();
        document.__setSurfaceMode('session');
        window.__triggerMutation(1);
        window.__flushRAF();
        window.__flushTimers();
        """)
        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.surface().qualified"))
        XCTAssertEqual(try harness.string("window.__codexAppExtensionV2.surface().kind"), "thread")
        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.performanceSnapshot().observers.every((item) => item.qualified === true && item.recoverable === false)"))
        XCTAssertEqual(try harness.string("document.querySelector('.thread-scroll-container').getAttribute('data-cae-wide-layout')"), "true")
        XCTAssertEqual(try harness.string("document.querySelector('.thread-scroll-container').getAttribute('data-cae-markdown-theme')"), "true")

        try uninstallAll(in: harness)
        XCTAssertEqual(try harness.int("window.__codexAppExtensionV2.observerCount()"), 0)
        XCTAssertEqual(try harness.int("window.__rafQueue.length"), 0)
        XCTAssertEqual(try harness.int("window.__timerQueue.length"), 0)
        XCTAssertTrue(try harness.value("document.getElementById('cae-wide-layout-style')").isNull)
        XCTAssertTrue(try harness.value("document.getElementById('cae-header-offset-style')").isNull)
        XCTAssertTrue(try harness.value("document.getElementById('cae-markdown-semantic-theme-style')").isNull)
        XCTAssertTrue(try harness.value("document.querySelector(\".ProseMirror[contenteditable='true']\").getAttribute('data-cae-wide-layout-editor')").isNull)
    }

    func testObserverBusUsesStableDocumentRootAndThreeQualifiedNativeNodesAndCoalescesBursts() throws {
        let harness = try JSRuntimeHarness(fixture: "current-surface")
        try addSyntheticWideOwner(to: harness)
        try harness.loadAdapter("wide-layout")
        try harness.loadAdapter("header-offset")
        _ = try harness.invoke("install", request: harness.request(
            id: 1, adapterId: "wide-layout", operation: "install", config: harness.defaultConfig(adapterId: "wide-layout")
        ))
        _ = try harness.invoke("install", request: harness.request(
            id: 2, adapterId: "header-offset", operation: "install", config: harness.defaultConfig(adapterId: "header-offset")
        ))

        XCTAssertEqual(try harness.int("window.__codexAppExtensionV2.observerCount()"), 2)
        XCTAssertEqual(try harness.int("window.__mutationObservers.filter((item) => !item.disconnected).length"), 3)
        try assertSingleObstacleDiscoveryObserver(in: harness)
        XCTAssertEqual(try harness.int("window.__mutationObservers.find((item) => !item.disconnected && item.targets.includes(document.documentElement)).targets.length"), 4)
        XCTAssertEqual(try harness.string("window.__mutationObservers.find((item) => !item.disconnected && item.targets.includes(document.documentElement)).targets.map((node) => node.name).join(',')"), "documentElement,layout,scroller,editor")
        try harness.evaluate("window.__flushRAF(); window.__flushTimers();")
        try harness.evaluate("window.__triggerMutation(10)")
        XCTAssertEqual(try harness.int("window.__rafQueue.length"), 1)
        XCTAssertEqual(try harness.int("window.__timerQueue.length"), 1)
        try harness.evaluate("window.__flushRAF(); window.__flushTimers();")
        XCTAssertEqual(try harness.int("window.__rafQueue.length"), 0)
        XCTAssertEqual(try harness.int("window.__timerQueue.length"), 0)

        _ = try harness.invoke("uninstall", request: harness.request(
            id: 3, adapterId: "wide-layout", operation: "uninstall", config: [:]
        ))
        _ = try harness.invoke("uninstall", request: harness.request(
            id: 4, adapterId: "header-offset", operation: "uninstall", config: [:]
        ))
        XCTAssertEqual(try harness.int("window.__codexAppExtensionV2.observerCount()"), 0)
        XCTAssertEqual(try harness.int("window.__mutationObservers.filter((item) => !item.disconnected).length"), 0)
    }

    func testSameTargetLayoutReplacementRebindsAllAdaptersAndCleansUp() throws {
        try assertSameTargetReplacement("layout")
    }

    func testSameTargetScrollerReplacementRebindsScopedAdaptersAndCleansUp() throws {
        try assertSameTargetReplacement("scroller")
    }

    func testSameTargetEditorReplacementRebindsInputAdapterAndCleansUp() throws {
        try assertSameTargetReplacement("editor")
    }

    func testTemporaryAmbiguousSurfaceMarksHealthUnqualifiedThenRecovers() throws {
        let harness = try fullyInstalledHarness()
        try harness.evaluate("""
        (() => {
          const editor = document.querySelector(".ProseMirror[contenteditable='true']");
          const duplicate = new window.__FakeNode('duplicate-editor');
          duplicate.setAttribute('class', 'ProseMirror');
          duplicate.setAttribute('contenteditable', 'true');
          duplicate.setAttribute('data-codex-composer', 'true');
          document.querySelector('[data-app-shell-main-content-layout]').appendChild(duplicate);
          document.__registerAll(".ProseMirror[data-codex-composer='true'][contenteditable='true'], .ProseMirror[data-codex-composer='true'][contenteditable='plaintext-only']", [editor, duplicate]);
          document.__registerAll(".ProseMirror[contenteditable='true'], .ProseMirror[contenteditable='plaintext-only']", [editor, duplicate]);
          document.__registerAll(".ProseMirror[contenteditable='true']", [editor, duplicate]);
          window.__triggerMutation(1);
          window.__flushRAF();
          window.__flushTimers();
        })();
        """)
        let ambiguousSnapshot = try harness.string("JSON.stringify(window.__codexAppExtensionV2.performanceSnapshot().observers)")
        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.performanceSnapshot().observers.find((item) => item.adapterId === 'ime-enter-guard').qualified === false"), ambiguousSnapshot)
        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.performanceSnapshot().observers.find((item) => item.adapterId === 'ime-enter-guard').recoverable === false"), ambiguousSnapshot)
        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.performanceSnapshot().observers.find((item) => item.adapterId === 'ime-enter-guard').failureReason !== null"), ambiguousSnapshot)
        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.performanceSnapshot().observers.filter((item) => item.adapterId !== 'ime-enter-guard').every((item) => item.qualified === true && item.failureReason === null)"), ambiguousSnapshot)

        try harness.evaluate("""
        (() => {
          const editor = document.querySelector(".ProseMirror[contenteditable='true']");
          document.__registerAll(".ProseMirror[data-codex-composer='true'][contenteditable='true'], .ProseMirror[data-codex-composer='true'][contenteditable='plaintext-only']", [editor]);
          document.__registerAll(".ProseMirror[contenteditable='true'], .ProseMirror[contenteditable='plaintext-only']", [editor]);
          document.__registerAll(".ProseMirror[contenteditable='true']", [editor]);
          window.__triggerMutation(1);
          window.__flushRAF();
          window.__flushTimers();
        })();
        """)
        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.performanceSnapshot().observers.every((item) => item.qualified === true && item.failureReason === null)"))
        try uninstallAll(in: harness)
    }

    func testMissingComposerKeepsLayoutAdaptersHealthyAndRebindsFreshNativeComposer() throws {
        let harness = try fullyInstalledHarness()
        try harness.evaluate("""
        (() => {
          window.__oldEditor = document.querySelector(".ProseMirror[contenteditable='true']");
          window.__oldEditor.remove();
          document.__registerAll(".ProseMirror[data-codex-composer='true'][contenteditable='true'], .ProseMirror[data-codex-composer='true'][contenteditable='plaintext-only']", []);
          document.__registerAll(".ProseMirror[contenteditable='true'], .ProseMirror[contenteditable='plaintext-only']", []);
          document.__registerAll(".ProseMirror[contenteditable='true']", []);
          document.__registerAll('[data-codex-composer]', []);
          window.__triggerMutation(1);
          window.__flushRAF();
          window.__flushTimers();
        })();
        """)

        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.surface().qualified"))
        XCTAssertTrue(try harness.value("window.__codexAppExtensionV2.surface().editor").isNull)
        XCTAssertEqual(try harness.int("window.__mutationObservers[0].targets.length"), 3)
        XCTAssertTrue(try harness.bool("window.__mutationObservers[0].targets.every(Boolean)"))
        XCTAssertEqual(try harness.string("window.__mutationObservers[0].targets.map((node) => node.name).join(',')"), "documentElement,layout,scroller")
        XCTAssertEqual(try harness.string("document.querySelector('.thread-scroll-container').getAttribute('data-cae-wide-layout')"), "true")
        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.performanceSnapshot().observers.find((item) => item.adapterId === 'ime-enter-guard').qualified === false"))
        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.performanceSnapshot().observers.find((item) => item.adapterId === 'ime-enter-guard').recoverable === true"))
        XCTAssertEqual(try harness.string("window.__codexAppExtensionV2.performanceSnapshot().observers.find((item) => item.adapterId === 'ime-enter-guard').failureReason"), "native-editor-not-unique")
        XCTAssertEqual(try harness.int("window.__oldEditor.listenerCount('keydown')"), 0)
        XCTAssertEqual(try harness.int("window.__oldEditor.listenerCount('compositionstart')"), 0)
        XCTAssertEqual(try harness.int("window.__oldEditor.listenerCount('compositionend')"), 0)
        XCTAssertTrue(try harness.value("window.__oldEditor.getAttribute('data-cae-ime-enter-guard')").isNull)

        try harness.evaluate("""
        (() => {
          const fresh = new window.__FakeNode('fresh-editor');
          fresh.setAttribute('class', 'ProseMirror');
          fresh.setAttribute('contenteditable', 'true');
          fresh.setAttribute('data-codex-composer', 'true');
          document.querySelector('[data-app-shell-main-content-layout]').appendChild(fresh);
          document.__registerAll(".ProseMirror[data-codex-composer='true'][contenteditable='true'], .ProseMirror[data-codex-composer='true'][contenteditable='plaintext-only']", [fresh]);
          document.__registerAll(".ProseMirror[contenteditable='true'], .ProseMirror[contenteditable='plaintext-only']", [fresh]);
          document.__registerAll(".ProseMirror[contenteditable='true']", [fresh]);
          document.__registerAll('[data-codex-composer]', [fresh]);
          window.__freshEditor = fresh;
          window.__triggerMutation(1);
          window.__flushRAF();
          window.__flushTimers();
        })();
        """)

        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.performanceSnapshot().observers.every((item) => item.qualified === true && item.failureReason === null)"))
        XCTAssertEqual(try harness.int("window.__mutationObservers[0].targets.length"), 4)
        XCTAssertEqual(try harness.string("window.__freshEditor.getAttribute('data-cae-ime-enter-guard')"), "true")
        XCTAssertEqual(try harness.int("window.__freshEditor.listenerCount('keydown')"), 1)
        XCTAssertEqual(try harness.int("window.__freshEditor.listenerCount('compositionstart')"), 1)
        XCTAssertEqual(try harness.int("window.__freshEditor.listenerCount('compositionend')"), 1)
        XCTAssertEqual(try harness.int("window.__oldEditor.listenerCount('keydown')"), 0)

        try uninstallAll(in: harness)
        XCTAssertEqual(try harness.int("window.__freshEditor.listenerCount('keydown')"), 0)
        XCTAssertEqual(try harness.int("window.__freshEditor.listenerCount('compositionstart')"), 0)
        XCTAssertEqual(try harness.int("window.__freshEditor.listenerCount('compositionend')"), 0)
        XCTAssertTrue(try harness.value("window.__freshEditor.getAttribute('data-cae-ime-enter-guard')").isNull)
        XCTAssertEqual(try harness.int("window.__codexAppExtensionV2.observerCount()"), 0)
    }

    private func assertSameTargetReplacement(_ part: String) throws {
        let harness = try fullyInstalledHarness()
        try harness.evaluate("""
        window.__oldLayout = document.querySelector('[data-app-shell-main-content-layout]');
        window.__oldScroller = document.querySelector('.thread-scroll-container');
        window.__oldEditor = document.querySelector(".ProseMirror[contenteditable='true']");
        document.__replaceSurface('\(part)');
        """)
        try addSyntheticWideOwner(to: harness)
        try harness.evaluate("window.__triggerMutation(1); window.__flushRAF(); window.__flushTimers();")

        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.surface().qualified"))
        XCTAssertEqual(try harness.int("window.__codexAppExtensionV2.observerCount()"), 4)
        XCTAssertEqual(try harness.int("window.__mutationObservers.filter((item) => !item.disconnected).length"), 3)
        try assertSingleObstacleDiscoveryObserver(in: harness)
        XCTAssertEqual(try harness.int("window.__mutationObservers.find((item) => !item.disconnected && item.targets.includes(document.documentElement)).targets.length"), 4)
        XCTAssertTrue(try harness.bool("window.__codexAppExtensionV2.performanceSnapshot().observers.every((item) => item.qualified === true)"))
        XCTAssertEqual(try harness.string("document.querySelector('[data-app-shell-main-content-layout]').getAttribute('data-cae-header-offset')"), "true")
        XCTAssertEqual(try harness.string("document.querySelector('.thread-scroll-container').getAttribute('data-cae-wide-layout')"), "true")
        XCTAssertEqual(
            try harness.string("document.querySelector('.thread-scroll-container').style.getPropertyValue('--thread-content-max-width')"),
            "min(1800px, max(1px, calc(100% - 48px)))"
        )
        XCTAssertEqual(try harness.string("document.querySelector('.thread-scroll-container').getAttribute('data-cae-markdown-theme')"), "true")
        XCTAssertEqual(try harness.string("document.querySelector(\".ProseMirror[contenteditable='true']\").getAttribute('data-cae-ime-enter-guard')"), "true")
        XCTAssertEqual(try harness.int("document.querySelector(\".ProseMirror[contenteditable='true']\").listenerCount('keydown')"), 1)
        XCTAssertEqual(try harness.int("document.querySelector(\".ProseMirror[contenteditable='true']\").listenerCount('compositionstart')"), 1)
        XCTAssertEqual(try harness.int("document.querySelector(\".ProseMirror[contenteditable='true']\").listenerCount('compositionend')"), 1)
        XCTAssertEqual(try harness.int("document.head.children.filter((node) => node.id && node.id.startsWith('cae-')).length"), 3)

        if part == "layout" {
            XCTAssertFalse(try harness.bool("window.__mutationObservers.some((item) => !item.disconnected && item.targets.includes(window.__oldLayout))"))
            XCTAssertEqual(try harness.int("window.__oldEditor.listenerCount('keydown')"), 0)
            XCTAssertTrue(try harness.value("window.__oldLayout.getAttribute('data-cae-header-offset')").isNull)
            XCTAssertTrue(try harness.value("window.__oldScroller.getAttribute('data-cae-wide-layout')").isNull)
            XCTAssertEqual(try harness.string("window.__oldScroller.style.getPropertyValue('--thread-content-max-width')"), "")
        } else if part == "scroller" {
            XCTAssertTrue(try harness.value("window.__oldScroller.getAttribute('data-cae-wide-layout')").isNull)
            XCTAssertTrue(try harness.value("window.__oldScroller.getAttribute('data-cae-markdown-theme')").isNull)
            XCTAssertEqual(try harness.string("window.__oldScroller.style.getPropertyValue('--thread-content-max-width')"), "")
        } else {
            XCTAssertEqual(try harness.int("window.__oldEditor.listenerCount('keydown')"), 0)
            XCTAssertEqual(try harness.int("window.__oldEditor.listenerCount('compositionstart')"), 0)
            XCTAssertEqual(try harness.int("window.__oldEditor.listenerCount('compositionend')"), 0)
        }

        try uninstallAll(in: harness)
        XCTAssertEqual(try harness.int("window.__codexAppExtensionV2.observerCount()"), 0)
        XCTAssertEqual(try harness.int("window.__mutationObservers.filter((item) => !item.disconnected).length"), 0)
        XCTAssertEqual(try harness.int("window.__rafQueue.length"), 0)
        XCTAssertEqual(try harness.int("window.__timerQueue.length"), 0)
        XCTAssertEqual(try harness.int("document.querySelector(\".ProseMirror[contenteditable='true']\").listenerCount('keydown')"), 0)
        XCTAssertEqual(try harness.int("document.head.children.filter((node) => node.id && node.id.startsWith('cae-')).length"), 0)
    }

    private func fullyInstalledHarness() throws -> JSRuntimeHarness {
        let harness = try JSRuntimeHarness(fixture: "current-surface")
        try addSyntheticWideOwner(to: harness)
        for (index, adapter) in ["wide-layout", "header-offset", "ime-enter-guard", "markdown-semantic-theme"].enumerated() {
            try harness.loadAdapter(adapter)
            _ = try harness.invoke("install", request: harness.request(
                id: index + 1,
                adapterId: adapter,
                operation: "install",
                config: harness.defaultConfig(adapterId: adapter)
            ))
        }
        try harness.evaluate("window.__flushRAF(); window.__flushTimers();")
        return harness
    }

    private func addSyntheticWideOwner(to harness: JSRuntimeHarness) throws {
        try harness.evaluate("""
        (() => {
          const scroller = document.querySelector('.thread-scroll-container');
          if (!scroller) return;
          const existing = scroller.querySelectorAll("[class*='thread-content-max-width']");
          if (existing.length > 0) return;
          const owner = new window.__FakeNode('synthetic-wide-owner');
          owner.setAttribute('class', 'mx-auto max-w-(--thread-content-max-width)');
          scroller.appendChild(owner);
          scroller.registerAll("[class*='thread-content-max-width']", [owner]);
          scroller.registerAll("[class*='thread-composer-max-width']", []);
        })();
        """)
    }

    private func uninstallAll(in harness: JSRuntimeHarness) throws {
        for (index, adapter) in ["wide-layout", "header-offset", "ime-enter-guard", "markdown-semantic-theme"].enumerated() {
            _ = try harness.invoke("uninstall", request: harness.request(
                id: 100 + index,
                adapterId: adapter,
                operation: "uninstall",
                config: [:]
            ))
        }
    }

    private func assertSingleObstacleDiscoveryObserver(in harness: JSRuntimeHarness) throws {
        XCTAssertEqual(try harness.int("""
        window.__mutationObservers.filter((observer) => !observer.disconnected &&
          !observer.targets.includes(document.documentElement) && observer.targets.some((target, index) => {
            const optionOffset = Math.max(0, (observer.options?.length || 0) - observer.targets.length);
            const options = observer.options?.[optionOffset + index] || {};
            return target === document.querySelector('[data-app-shell-main-content-layout]') &&
              options.attributes === true && options.subtree === true &&
              JSON.stringify(options.attributeFilter) === JSON.stringify(['data-pip-obstacle']);
          })).length
        """), 1)
    }

    @MainActor
    private func floatingPanelWebKitFixture(panelHTML: String) throws -> WKWebView {
        let html = """
        <!doctype html>
        <html><head><meta charset="utf-8"><style>
          html, body { margin: 0; width: 100%; height: 100%; overflow: hidden; }
          #layout { position: absolute; left: 120px; right: 0; top: 0; bottom: 0; }
          #scroller { position: absolute; inset: 60px 0 0; overflow: auto; }
          #content-row { width: calc(100% - 40px); margin-inline: 20px; height: 500px; }
          #composer-row { position: absolute; bottom: 0; width: 100%; height: 120px; }
          .thread-content-max-width-shell, .thread-composer-max-width-shell { box-sizing: border-box; width: 900px; margin-inline: auto; }
          #content { height: 440px; }
          #markdown { width: 100%; height: 400px; }
          #composer { height: 100px; }
          #editor { min-height: 80px; }
          #panel-host { position: absolute; right: 0; top: 60px; bottom: 12px; width: 260px; pointer-events: none; }
          #panel, #panel-body { position: absolute; left: 0; top: 0; width: 244px; height: 160px; }
          .painted-panel { background: rgb(24, 24, 27); }
          .negative-panel { position: fixed; right: 0; top: 80px; width: 300px; height: 160px; }
        </style></head><body>
          <main id="layout" data-app-shell-main-content-layout>
            <section id="scroller" class="thread-scroll-container">
              <div id="content-row"><div id="content" class="thread-content-max-width-shell">
                <article id="markdown" data-selected-text-overlay-target><p>Fixture response.</p></article>
              </div></div>
              <div id="composer-row"><div id="composer-shift">
                <div id="composer" class="thread-composer-max-width-shell">
                  <div id="editor" class="ProseMirror" contenteditable="true" data-codex-composer="true"><p>Fixture input.</p></div>
                </div>
              </div></div>
            </section>
            \(panelHTML)
          </main>
        </body></html>
        """
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1_200, height: 800))
        let hostWindow = NSWindow(
            contentRect: webView.frame,
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        hostWindow.title = "Wide layout WebKit regression"
        hostWindow.level = .floating
        hostWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hostWindow.isReleasedWhenClosed = false
        addTeardownBlock {
            await MainActor.run {
                webView.stopLoading()
                webView.navigationDelegate = nil
                webView.removeFromSuperview()
                hostWindow.contentView = nil
                hostWindow.orderOut(nil)
                hostWindow.close()
            }
        }
        webView.autoresizingMask = [.width, .height]
        hostWindow.contentView = webView
        hostWindow.center()
        hostWindow.orderFrontRegardless()
        pumpFloatingPanelWindowEvents()
        XCTAssertTrue(hostWindow.isVisible)
        XCTAssertTrue(webView.window === hostWindow)
        let loaded = expectation(description: "Floating panel WebKit fixture loaded")
        let navigationDelegate = WebKitFixtureNavigationDelegate(expectation: loaded)
        webView.navigationDelegate = navigationDelegate
        webView.loadHTMLString(html, baseURL: nil)
        wait(for: [loaded], timeout: 10)
        if let error = navigationDelegate.error { throw error }

        let visibilityDeadline = Date().addingTimeInterval(4)
        var documentVisible = false
        repeat {
            pumpFloatingPanelWindowEvents()
            let visibility = try evaluateWebKitJSON("JSON.stringify({ visible: document.visibilityState === 'visible' })", in: webView)
            documentVisible = visibility["visible"] as? Bool == true
            if documentVisible && hostWindow.occlusionState.contains(.visible) { break }
        } while Date() < visibilityDeadline
        XCTAssertTrue(hostWindow.occlusionState.contains(.visible), "WebKit fixture window must be unoccluded")
        XCTAssertTrue(documentVisible, "WebKit fixture document must be visible before installing the adapter")

        let bundle = Bundle(for: PageRuntimeTests.self)
        let scripts = try ["bootstrap", "wide-layout"].map { resource in
            let url = try XCTUnwrap(bundle.url(forResource: resource, withExtension: "js"))
            return try String(contentsOf: url, encoding: .utf8)
        }.joined(separator: "\n")
        let installed = try evaluateWebKitJSON(scripts + """
        \nJSON.stringify(window.__codexAppExtensionV2.install({
          runtimeVersion: 2, requestId: 1, adapterId: 'wide-layout', operation: 'install',
          config: { maximumContentWidth: 1800, minimumSidePadding: 24 }
        }))
        """, in: webView)
        XCTAssertTrue(installed["error"] is NSNull)
        XCTAssertEqual((installed["result"] as? [String: Any])?["qualified"] as? Bool, true)
        return webView
    }

    @MainActor
    private func pumpFloatingPanelWindowEvents() {
        // A command-line XCTest runner does not dispatch AppKit window events itself.
        let application = NSApplication.shared
        let deadline = Date().addingTimeInterval(0.02)
        while Date() < deadline,
              let event = application.nextEvent(matching: .any, until: Date(), inMode: .default, dequeue: true) {
            application.sendEvent(event)
        }
        application.updateWindows()
        RunLoop.current.run(until: deadline)
    }

    @MainActor
    private func mutateFloatingPanelFixture(_ script: String, in webView: WKWebView) throws {
        _ = try evaluateWebKitJSON("""
        (() => {
          \(script)
          window.__fixtureMutationSettled = false;
          requestAnimationFrame(() => requestAnimationFrame(() => { window.__fixtureMutationSettled = true; }));
          return JSON.stringify({});
        })()
        """, in: webView)
        let deadline = Date().addingTimeInterval(4)
        var settled = false
        while !settled && Date() < deadline {
            pumpFloatingPanelWindowEvents()
            let state = try evaluateWebKitJSON("JSON.stringify({ settled: window.__fixtureMutationSettled })", in: webView)
            settled = state["settled"] as? Bool == true
        }
        XCTAssertTrue(settled, "Real WebKit mutation and animation-frame callbacks must settle")
    }

    @MainActor
    private func waitForFloatingPanelGeometry(
        in webView: WKWebView,
        width: Double,
        right: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(4)
        var geometry: [String: Any] = [:]
        repeat {
            pumpFloatingPanelWindowEvents()
            geometry = try evaluateWebKitJSON("""
            (() => {
              const rect = (id) => document.getElementById(id).getBoundingClientRect();
              const panel = document.getElementById('panel');
              const panelRect = panel?.getBoundingClientRect();
              return JSON.stringify({
                contentLeft: rect('content').left, contentRight: rect('content').right, contentWidth: rect('content').width,
                markdownLeft: rect('markdown').left, markdownRight: rect('markdown').right,
                composerLeft: rect('composer').left, composerRight: rect('composer').right, composerWidth: rect('composer').width,
                surfaceLeft: rect('scroller').left, referenceTop: rect('composer-row').top,
                panelLeft: panelRect?.left ?? 0, panelBottom: panelRect?.bottom ?? 0, panelHeight: panelRect?.height ?? 0,
                panelBackground: panel ? getComputedStyle(panel).backgroundColor : null,
                panelChildren: panel?.children.length ?? 0,
                hasHomeSurface: document.querySelector('[data-pip-home-surface]') !== null
              });
            })()
            """, in: webView)
            let contentWidth = try number("contentWidth", in: geometry)
            let contentRight = try number("contentRight", in: geometry)
            let composerRight = try number("composerRight", in: geometry)
            if abs(contentWidth - width) <= 1 && abs(contentRight - right) <= 1 && abs(composerRight - right) <= 1 {
                return geometry
            }
        } while Date() < deadline
        XCTAssertEqual(try number("contentWidth", in: geometry), width, accuracy: 1, file: file, line: line)
        XCTAssertEqual(try number("contentRight", in: geometry), right, accuracy: 1, file: file, line: line)
        XCTAssertEqual(try number("composerRight", in: geometry), right, accuracy: 1, file: file, line: line)
        return geometry
    }

    private func assertFloatingPanelClearance(
        _ geometry: [String: Any],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        for prefix in ["content", "markdown", "composer"] {
            XCTAssertGreaterThanOrEqual(
                try number("\(prefix)Left", in: geometry) - number("surfaceLeft", in: geometry),
                23, file: file, line: line
            )
            XCTAssertGreaterThanOrEqual(
                try number("panelLeft", in: geometry) - number("\(prefix)Right", in: geometry),
                23, file: file, line: line
            )
        }
    }

    @MainActor
    private func evaluateWebKitJSON(_ script: String, in webView: WKWebView) throws -> [String: Any] {
        let evaluated = expectation(description: "WebKit JavaScript evaluated")
        var value: Any?
        var evaluationError: Error?
        webView.evaluateJavaScript(script) { result, error in
            value = result
            evaluationError = error
            evaluated.fulfill()
        }
        wait(for: [evaluated], timeout: 10)
        if let evaluationError {
            throw evaluationError
        }
        let jsonString = try XCTUnwrap(value as? String)
        let json = try XCTUnwrap(jsonString.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
    }

    private func number(_ key: String, in dictionary: [String: Any]) throws -> Double {
        try XCTUnwrap(dictionary[key] as? NSNumber).doubleValue
    }
}
