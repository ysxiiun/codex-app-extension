import XCTest

@MainActor
final class RecoveryUITests: XCTestCase {
    func testNoApplicationRunningWithoutCDPAndNormalCDPPaths() throws {
        for (state, expected) in [
            ("offline", "ChatGPT 未运行"),
            ("waiting", "等待重启确认"),
            ("normal", "运行正常")
        ] {
            let app = launch(status: state)
            openStatusMenu(app)
            XCTAssertTrue(app.staticTexts[expected].waitForExistence(timeout: 2), "恢复路径状态不匹配: \(state)")
            app.terminate()
        }
    }

    func testCorruptConfigurationRecoveryIsExplained() throws {
        let app = launch(status: "corrupt")
        openSettings(app)

        XCTAssertTrue(app.staticTexts["settings.error"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["配置损坏，已使用最后可用配置"].exists)
    }

    func testAdapterFailureHealthCheckRecoversWithoutKillingApplication() throws {
        let app = launch(status: "adapter-failure")
        openStatusMenu(app)
        XCTAssertTrue(app.staticTexts["增强降级"].waitForExistence(timeout: 2))
        app.buttons["action.settings"].click()
        XCTAssertTrue(app.staticTexts["通用"].waitForExistence(timeout: 3))
        app.staticTexts["兼容与诊断"].firstMatch.click()
        let health = app.buttons["settings.diagnostics.health"]
        XCTAssertTrue(health.waitForExistence(timeout: 2))
        health.click()
        app.typeKey("w", modifierFlags: .command)
        openStatusMenu(app)
        XCTAssertTrue(app.staticTexts["运行正常"].waitForExistence(timeout: 2))
    }

    func testTargetReloadAndDiagnosticActionsPublishFreshState() throws {
        let app = launch(status: "build-change")
        openSettings(app)
        app.staticTexts["兼容与诊断"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["ui-target"].waitForExistence(timeout: 2))

        app.buttons["settings.diagnostics.reconnect"].click()
        XCTAssertTrue(app.staticTexts["ui-target-reloaded"].waitForExistence(timeout: 2))

        app.buttons["settings.diagnostics.copySummary"].click()
        XCTAssertTrue(app.staticTexts["诊断摘要已复制"].waitForExistence(timeout: 2))
        app.buttons["settings.diagnostics.export"].click()
        let actionStatus = app.staticTexts["settings.diagnostics.actionStatus"]
        XCTAssertTrue(actionStatus.waitForExistence(timeout: 2))
    }

    private func launch(status: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-status=\(status)"]
        app.launch()
        return app
    }

    private func openStatusMenu(_ app: XCUIApplication) {
        let status = app.menuBars.statusItems.firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 3))
        waitForStatusDashboard(app)
        XCTAssertTrue(app.buttons["action.settings"].waitForExistence(timeout: 2))
    }

    private func openSettings(_ app: XCUIApplication) {
        openStatusMenu(app)
        app.buttons["action.settings"].click()
        XCTAssertTrue(app.staticTexts["通用"].waitForExistence(timeout: 3))
    }
}
