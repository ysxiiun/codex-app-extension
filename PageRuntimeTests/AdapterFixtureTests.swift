import Foundation
import XCTest
@testable import ExtensionCore

final class AdapterFixtureTests: XCTestCase {
    func testWideLayoutUsesNativeVariablesAndRestoresHostValues() throws {
        let harness = try JSRuntimeHarness(fixture: "current-surface")
        try addSyntheticWideOwner(to: harness)
        XCTAssertTrue(harness.fixtureHTML.contains("thread-scroll-container"))
        XCTAssertTrue(harness.fixtureHTML.contains("data-testid=\"right-rail\""))
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
        XCTAssertFalse(css.contains("\n.thread-scroll-container[data-cae-wide-layout='true'] [class*='markdown-wide-block-max-width']"))
        XCTAssertFalse(css.contains("\n.thread-scroll-container[data-cae-wide-layout='true'] [data-selected-text-overlay-target]"))
        XCTAssertTrue(css.contains("max-width: var(--thread-content-max-width) !important"))
        XCTAssertTrue(css.contains("translate: var(--cae-wide-layout-owner-offset-x, var(--cae-wide-layout-content-offset-x)) 0 !important"))
        XCTAssertTrue(css.contains(".ProseMirror[contenteditable='true'] *"))
        XCTAssertTrue(css.contains("[role='menu'] *"))
        XCTAssertTrue(css.contains("[role='listbox'] *"))
        XCTAssertTrue(css.contains("[class*='thread-floating-content'] *"))
        XCTAssertFalse(css.contains("padding-inline:"))
        XCTAssertFalse(css.contains("margin-inline:"))
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
          const nestedRailMenu = new window.__FakeNode('nested-rail-menu');
          nestedRailMenu.setAttribute('role', 'menu');
          nestedRailMenu.style.backgroundColor = 'rgb(39, 39, 42)';
          nestedRailMenu.getBoundingClientRect = () => rect(1680, 1880, 180, 380);
          railBody.appendChild(nestedRailMenu);
          rail.appendChild(railBody);
          rail.appendChild(latentRailBody);
          rail.appendChild(showingRailBody);
          rail.appendChild(churnRailBody);
          showingRailBody.getBoundingClientRect = () => rect(1660, 1900, 112, 460);
          churnRailBody.getBoundingClientRect = () => rect(1660, 1900, 112, 460);
          rail.registerAll('*', [railBody, nestedRailMenu, latentRailBody, showingRailBody, churnRailBody]);
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
          document.__registerAll(
            "[class*='thread-floating-content-top-inset'][class*='thread-floating-content-bottom-inset'], [data-codex-app-extension-native-floating-panel='true']",
            [transientWrapper, transientRail, rail]
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
          window.__triggerRailMutation = (node) => window.__mutationObservers
            .filter((observer) => !observer.disconnected && observer.targets.some((target, index) => {
              const options = observer.options?.[index] || {};
              return options.attributes && (target === node || (options.subtree && target.contains(node)));
            }))
            .forEach((observer) => observer.callback([{ type: 'attributes', target: node }]));
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
          window.__wideLayoutNativeShiftHost = nativeShiftHost;
          window.__wideLayoutComposerShiftHost = composerShiftHost;
          window.__wideLayoutCanonicalOwner = canonicalOwner;
          window.__wideLayoutComposerOwner = composerOwner;
          window.__wideLayoutRail = rail;
          window.__wideLayoutRailBody = railBody;
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
        window.__triggerRailMutation(window.__wideLayoutCanonicalOwner);
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
        window.__wideLayoutRailBody.style.display = '';
        window.__wideLayoutRailBody.getBoundingClientRect = () => ({
          left: 1980, right: 2220, top: 112, bottom: 460, width: 240, height: 348
        });
        window.__triggerResize(window.__wideLayoutRailBody);
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
        XCTAssertTrue(try harness.bool("['transitionrun','transitionstart','transitionend','transitioncancel','animationstart','animationend','animationcancel'].every((type) => window.__wideLayoutNativeShiftHost.listenerCount(type) === 0 && window.__wideLayoutRail.listenerCount(type) === 0)"))
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
        XCTAssertEqual(try harness.int("window.__mutationObservers.filter((item) => !item.disconnected).length"), 2)
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
        XCTAssertEqual(try harness.int("window.__mutationObservers.filter((item) => !item.disconnected).length"), 2)
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
}
