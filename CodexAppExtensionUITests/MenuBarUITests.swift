import XCTest

@MainActor
func waitForStatusDashboard(_ app: XCUIApplication) {
    XCTAssertTrue(app.windows["Codex App Extension 状态"].waitForExistence(timeout: 3))
}

@MainActor
final class MenuBarUITests: XCTestCase {
    private let quickToggles = [
        (identifier: "quick.global", title: "启用扩展"),
        (identifier: "quick.wide", title: "宽屏布局"),
        (identifier: "quick.ime", title: "中文输入保护"),
        (identifier: "quick.markdown", title: "Markdown 外观"),
    ]

    func testFiveStatesExposeIconTextAndContextActions() throws {
        for (state, text) in [("normal", "运行正常"), ("waiting", "等待重启确认"), ("page-waiting", "等待页面就绪"), ("degraded", "增强降级"), ("offline", "ChatGPT 未运行")] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-testing", "--ui-status=\(state)"]
            app.launch()
            let status = app.menuBars.statusItems.firstMatch
            XCTAssertTrue(status.waitForExistence(timeout: 3), "缺少菜单栏状态项: \(state)")
            XCTAssertEqual(status.identifier, "menuBar.status")
            waitForStatusDashboard(app)
            XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 2))
            XCTAssertTrue(app.buttons["action.settings"].exists)
            XCTAssertTrue(app.buttons["action.reconnect"].exists)
            if state == "waiting" { XCTAssertTrue(app.buttons["action.confirmRestart"].exists) }
            if state == "page-waiting" { XCTAssertTrue(app.staticTexts["1 项等待"].exists) }
            if state == "offline" { XCTAssertTrue(app.buttons["action.start"].exists) }
            app.terminate()
        }
    }

    func testRestartCancelPerformsNoConfirmationAction() throws {
        let (app, status) = launchRealMenuWaitingForRestart()
        openRealStatusMenu(app, status: status)
        app.buttons["action.confirmRestart"].click()
        let cancel = app.buttons["restart.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 2))
        cancel.click()
        reopenRealStatusMenu(app, status: status)
        XCTAssertTrue(app.staticTexts["等待重启确认"].exists)
        XCTAssertTrue(app.buttons["action.confirmRestart"].exists)
        XCTAssertEqual(app.staticTexts["ui.restart.confirmationCount"].label, "重启确认次数：0")
    }

    func testRestartConfirmationCallsRuntimeExactlyOnceAndClearsPending() throws {
        let (app, status) = launchRealMenuWaitingForRestart()
        openRealStatusMenu(app, status: status)
        app.buttons["action.confirmRestart"].click()
        let confirm = app.buttons["restart.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 2))
        confirm.click()

        reopenRealStatusMenu(app, status: status)
        XCTAssertTrue(app.staticTexts["运行正常"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["action.confirmRestart"].exists)
        XCTAssertEqual(app.staticTexts["ui.restart.confirmationCount"].label, "重启确认次数：1")
    }

    func testQuickTogglesShareAlignedColumnsAndRemainInteractive() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-status=normal"]
        app.launch()
        XCTAssertTrue(app.menuBars.statusItems.firstMatch.waitForExistence(timeout: 3))
        waitForStatusDashboard(app)

        let titles = quickToggles.map { app.staticTexts[$0.title] }
        let switches = quickToggles.map { app.checkBoxes[$0.identifier] }
        for (index, title) in titles.enumerated() {
            XCTAssertTrue(title.waitForExistence(timeout: 2), "缺少快速开关标题 \(index)")
        }
        for (metadata, toggle) in zip(quickToggles, switches) {
            XCTAssertTrue(toggle.waitForExistence(timeout: 2), "缺少快速开关 \(metadata.identifier)")
            XCTAssertEqual(toggle.identifier, metadata.identifier)
            XCTAssertEqual(toggle.elementType, .checkBox, "macOS switch 应保持 AXCheckBox/AXSwitch 角色")
            XCTAssertEqual(toggle.label, metadata.title)
        }

        let pixelTolerance: CGFloat = 1
        let titleLeading = try XCTUnwrap(titles.first?.frame.minX)
        let switchTrailing = try XCTUnwrap(switches.first?.frame.maxX)
        for title in titles.dropFirst() {
            XCTAssertEqual(title.frame.minX, titleLeading, accuracy: pixelTolerance)
        }
        for toggle in switches.dropFirst() {
            XCTAssertEqual(toggle.frame.maxX, switchTrailing, accuracy: pixelTolerance)
        }

        let wideLayout = app.checkBoxes["quick.wide"]
        let initialValue = String(describing: wideLayout.value ?? "")
        wideLayout.click()
        let valueChanged = NSPredicate { candidate, _ in
            guard let element = candidate as? XCUIElement else { return false }
            return String(describing: element.value ?? "") != initialValue
        }
        expectation(for: valueChanged, evaluatedWith: wideLayout)
        waitForExpectations(timeout: 2)
    }

    func testQuickTogglesAreDisabledWhileConfigurationIsApplying() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-status=normal", "--ui-is-applying"]
        app.launch()
        XCTAssertTrue(app.menuBars.statusItems.firstMatch.waitForExistence(timeout: 3))
        waitForStatusDashboard(app)

        for metadata in quickToggles {
            let toggle = app.checkBoxes[metadata.identifier]
            XCTAssertTrue(toggle.waitForExistence(timeout: 2), "缺少快速开关 \(metadata.identifier)")
            XCTAssertEqual(toggle.identifier, metadata.identifier)
            XCTAssertEqual(toggle.elementType, .checkBox, "macOS switch 应保持 AXCheckBox/AXSwitch 角色")
            XCTAssertEqual(toggle.label, metadata.title)
            XCTAssertFalse(toggle.isEnabled, "配置应用期间必须禁用 \(metadata.identifier)")
        }
    }

    func testLayoutSettingsExplainMaximumWidthClamping() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-status=normal"]
        app.launch()
        XCTAssertTrue(app.menuBars.statusItems.firstMatch.waitForExistence(timeout: 3))
        waitForStatusDashboard(app)
        app.buttons["action.settings"].click()
        XCTAssertTrue(app.staticTexts["通用"].waitForExistence(timeout: 3))
        app.staticTexts["布局"].firstMatch.click()

        XCTAssertTrue(app.staticTexts["最大内容宽度是配置上限；实际宽度会按当前可用区域和最小侧边距自动收窄，不改变输入框、右侧栏或菜单。"].waitForExistence(timeout: 2))
        let preview = app.descendants(matching: .any)["settings.layout.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 2))
    }

    private func launchRealMenuWaitingForRestart() -> (XCUIApplication, XCUIElement) {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-test-real-menu", "--ui-status=waiting"]
        app.launch()
        let status = app.menuBars.statusItems["menuBar.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 3))
        XCTAssertFalse(app.windows["Codex App Extension 状态"].exists)
        return (app, status)
    }

    private func openRealStatusMenu(_ app: XCUIApplication, status: XCUIElement) {
        status.click()
        XCTAssertTrue(app.staticTexts["ui.restart.confirmationCount"].waitForExistence(timeout: 2))
    }

    private func reopenRealStatusMenu(_ app: XCUIApplication, status: XCUIElement) {
        let marker = app.staticTexts["ui.restart.confirmationCount"]
        if marker.exists {
            status.click()
            let closed = NSPredicate(format: "exists == false")
            expectation(for: closed, evaluatedWith: marker)
            waitForExpectations(timeout: 2)
        }
        status.click()
        XCTAssertTrue(marker.waitForExistence(timeout: 2))
    }
}
