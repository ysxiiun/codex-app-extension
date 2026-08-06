import XCTest
@testable import ExtensionCore

final class AdapterPerformanceTests: XCTestCase {
    func testMutationBurstSchedulesAtMostOneRAFAndOneSettleRefresh() throws {
        let harness = try JSRuntimeHarness(fixture: "current-surface")
        try harness.loadAdapter("wide-layout")
        _ = try harness.invoke("install", request: harness.request(
            id: 1,
            adapterId: "wide-layout",
            operation: "install",
            config: harness.defaultConfig(adapterId: "wide-layout")
        ))
        try harness.evaluate("window.__flushRAF(); window.__flushTimers();")

        try harness.evaluate("window.__triggerMutation(100)")

        XCTAssertEqual(try harness.int("window.__rafQueue.length"), 1)
        XCTAssertEqual(try harness.int("window.__timerQueue.length"), 1)
        try harness.evaluate("window.__flushRAF(); window.__flushTimers();")
        XCTAssertEqual(try harness.int("window.__rafQueue.length"), 0)
        XCTAssertEqual(try harness.int("window.__timerQueue.length"), 0)
        XCTAssertEqual(try harness.int("window.__codexAppExtensionV2.performanceSnapshot().events.length"), 2)
    }

    func testThreeOverBudgetStrikesDegradeOnlySlowAdapterAndStopItsWrites() throws {
        let harness = try JSRuntimeHarness(fixture: "current-surface")
        try installMeasuredAdapters(in: harness)

        try flushBurst(in: harness)
        try flushBurst(in: harness)
        let slowWritesAtDegradation = try harness.int("document.querySelector('[data-app-shell-main-content-layout]').style.writeCount('--slow-layout-write')")
        let healthyWritesAtDegradation = try harness.int("document.querySelector('[data-app-shell-main-content-layout]').style.writeCount('--healthy-layout-write')")
        XCTAssertEqual(slowWritesAtDegradation, 3)
        XCTAssertGreaterThanOrEqual(healthyWritesAtDegradation, 3)

        try flushBurst(in: harness)

        XCTAssertEqual(
            try harness.int("document.querySelector('[data-app-shell-main-content-layout]').style.writeCount('--slow-layout-write')"),
            slowWritesAtDegradation
        )
        XCTAssertGreaterThan(
            try harness.int("document.querySelector('[data-app-shell-main-content-layout]').style.writeCount('--healthy-layout-write')"),
            healthyWritesAtDegradation
        )
        let degraded = try harness.invoke("diagnose", request: harness.request(
            id: 3, adapterId: "slow-layout", operation: "diagnose", config: [:]
        ))
        XCTAssertEqual((degraded["error"] as? [String: Any])?["code"] as? String, "adapter-performance-budget-exceeded")
        XCTAssertEqual(try harness.int("window.__codexAppExtensionV2.handshake(9).result.runtimeVersion"), 2)
    }

    func testPerformanceEventRingIsBoundedAndUninstallClearsObserverTimersAndRecoveryState() throws {
        let harness = try JSRuntimeHarness(fixture: "current-surface")
        try harness.loadAdapter("wide-layout")
        _ = try harness.invoke("install", request: harness.request(
            id: 1, adapterId: "wide-layout", operation: "install", config: harness.defaultConfig(adapterId: "wide-layout")
        ))
        try harness.evaluate("window.__flushRAF(); window.__flushTimers();")
        for _ in 0..<40 {
            try flushBurst(in: harness)
        }
        XCTAssertEqual(try harness.int("window.__codexAppExtensionV2.performanceSnapshot().events.length"), 32)

        try harness.evaluate("window.__triggerMutation(5)")
        XCTAssertEqual(try harness.int("window.__rafQueue.length"), 1)
        XCTAssertEqual(try harness.int("window.__timerQueue.length"), 1)
        _ = try harness.invoke("uninstall", request: harness.request(
            id: 2, adapterId: "wide-layout", operation: "uninstall", config: [:]
        ))
        XCTAssertEqual(try harness.int("window.__codexAppExtensionV2.observerCount()"), 0)
        XCTAssertEqual(try harness.int("window.__rafQueue.length"), 0)
        XCTAssertEqual(try harness.int("window.__timerQueue.length"), 0)
        XCTAssertEqual(try harness.int("window.__mutationObservers.filter((item) => !item.disconnected).length"), 0)

        let reinstalled = try harness.invoke("install", request: harness.request(
            id: 3, adapterId: "wide-layout", operation: "install", config: harness.defaultConfig(adapterId: "wide-layout")
        ))
        XCTAssertNil(harness.nonNullError(reinstalled))
        XCTAssertEqual(try harness.int("window.__codexAppExtensionV2.observerCount()"), 1)
    }

    func testObserverRegistryHasFixedMaximumCapacity() throws {
        let harness = try JSRuntimeHarness(fixture: "current-surface")
        try harness.evaluate("for (let i = 0; i < 100; i += 1) window.__codexAppExtensionV2.observe('observer-' + i, function() {});")

        XCTAssertEqual(try harness.int("window.__codexAppExtensionV2.observerCount()"), 16)
        XCTAssertEqual(try harness.int("window.__codexAppExtensionV2.performanceSnapshot().policy.maximumObserverCount"), 16)
    }

    private func installMeasuredAdapters(in harness: JSRuntimeHarness) throws {
        try harness.evaluate("""
        (() => {
          let clock = 0;
          window.performance = { now() { return clock; } };
          const runtime = window.__codexAppExtensionV2;
          const layout = document.querySelector('[data-app-shell-main-content-layout]');
          let slowUnsubscribe = null;
          let healthyUnsubscribe = null;
          runtime.register({
            adapterId: 'slow-layout',
            probe() { return { qualified: true }; },
            install(config, api) {
              slowUnsubscribe = api.observe('slow-layout', () => {
                layout.style.setProperty('--slow-layout-write', String(clock));
                clock += 9;
              });
              return { qualified: true };
            },
            update() { return { changed: true }; },
            diagnose() { return { healthy: true }; },
            uninstall() { slowUnsubscribe?.(); slowUnsubscribe = null; return { changed: true }; }
          });
          runtime.register({
            adapterId: 'healthy-layout',
            probe() { return { qualified: true }; },
            install(config, api) {
              healthyUnsubscribe = api.observe('healthy-layout', () => {
                layout.style.setProperty('--healthy-layout-write', String(clock));
                clock += 1;
              });
              return { qualified: true };
            },
            update() { return { changed: true }; },
            diagnose() { return { healthy: true }; },
            uninstall() { healthyUnsubscribe?.(); healthyUnsubscribe = null; return { changed: true }; }
          });
        })();
        """)
        _ = try harness.invoke("install", request: harness.request(id: 1, adapterId: "slow-layout", operation: "install", config: [:]))
        _ = try harness.invoke("install", request: harness.request(id: 2, adapterId: "healthy-layout", operation: "install", config: [:]))
    }

    private func flushBurst(in harness: JSRuntimeHarness) throws {
        try harness.evaluate("window.__triggerMutation(20); window.__flushRAF(); window.__flushTimers();")
    }
}
