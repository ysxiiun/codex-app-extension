# Repair Bundle 2

Independent Review passed. Verification failed only in the four new real-WebKit tests (75 tests, 50 assertions).

- test-defect: AdapterFixtureTests.swift must process AppKit window events for its shown fixture during waits. The minimal own-page experiment confirms NSRunLoop alone leaves document hidden with 0 RAF callbacks despite window.isVisible; nextEvent/sendEvent/updateWindows restores visible state and 116 callbacks in 2 seconds, without activating the app.
- Add public window occlusion/document visibility readiness validation and retain real RAF, mutation and resize callbacks, existing cleanup and timeouts. No production changes.
- Rerun isolated baseline, affected suites and all remaining must-test commands. Review only test-host repair delta; no relabeling earlier candidate results.
