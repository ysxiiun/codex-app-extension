import XCTest

@MainActor
final class SettingsUITests: XCTestCase {
    private func launchSettings(additionalArguments: [String] = []) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-status=normal"] + additionalArguments
        app.launch()
        let status = app.menuBars.statusItems.firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 3))
        waitForStatusDashboard(app)
        app.buttons["action.settings"].click()
        XCTAssertTrue(app.staticTexts["通用"].waitForExistence(timeout: 3))
        return app
    }

    func testFivePageNavigationAndInputProtection() throws {
        let app = try launchSettings()
        for page in ["通用", "布局", "输入", "外观", "兼容与诊断"] {
            let item = app.staticTexts[page].firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 2), "缺少设置页 \(page)")
            item.click()
        }
        app.staticTexts["布局"].firstMatch.click()
        for identifier in [
            "settings.layout.maximumWidth.slider",
            "settings.layout.sidePadding.slider",
            "settings.layout.preview",
            "settings.layout.reset.wide",
            "settings.layout.reset.header",
        ] {
            XCTAssertTrue(app.descendants(matching: .any)[identifier].waitForExistence(timeout: 2), "缺少布局控件 \(identifier)")
        }
        let headerMode = app.descendants(matching: .any)["settings.layout.headerMode"]
        XCTAssertTrue(headerMode.waitForExistence(timeout: 2))
        headerMode.click()
        app.menuItems["自定义"].click()
        XCTAssertTrue(app.descendants(matching: .any)["settings.layout.headerOffset.slider"].waitForExistence(timeout: 2))
        app.staticTexts["输入"].firstMatch.click()
        XCTAssertTrue(app.descendants(matching: .any)["settings.input.imeGuard"].waitForExistence(timeout: 2))

        app.staticTexts["外观"].firstMatch.click()
        for identifier in [
            "settings.appearance.preset",
            "settings.appearance.reset.all",
            "settings.appearance.reset.markdown",
            "settings.appearance.preview",
            "settings.appearance.preview.scheme",
            "settings.appearance.preview.heading",
            "settings.appearance.preview.body",
            "settings.appearance.preview.inlineCode",
            "settings.appearance.preview.quote",
            "settings.appearance.preview.nestedQuote",
            "settings.appearance.heading.enabled",
            "settings.appearance.heading.color",
            "settings.appearance.strong.enabled",
            "settings.appearance.strong.color",
            "settings.appearance.strong.fontWeight.slider",
            "settings.appearance.strong.fontWeight",
            "settings.appearance.inlineCode.text",
            "settings.appearance.inlineCode.background",
            "settings.appearance.inlineCode.border",
            "settings.appearance.blockquote.border",
            "settings.appearance.blockquote.text",
            "settings.appearance.blockquote.background",
        ] {
            XCTAssertTrue(app.descendants(matching: .any)[identifier].waitForExistence(timeout: 2), "缺少外观控件 \(identifier)")
        }
        for identifier in [
            "settings.appearance.heading.color",
            "settings.appearance.strong.color",
            "settings.appearance.inlineCode.text",
            "settings.appearance.inlineCode.background",
            "settings.appearance.inlineCode.border",
            "settings.appearance.blockquote.border",
            "settings.appearance.blockquote.text",
            "settings.appearance.blockquote.background",
        ] {
            XCTAssertTrue(app.descendants(matching: .any)["\(identifier).status"].exists, "缺少颜色状态 \(identifier)")
        }
        XCTAssertFalse(app.descendants(matching: .any)["settings.appearance.focusRing"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["settings.appearance.focusColor"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["settings.appearance.reset.focus"].exists)
    }

    func testAppearanceWideAndNarrowLayoutsKeepPreviewAndLastEditorReachable() throws {
        for mode in ["narrow", "wide"] {
            let app = try launchSettings(additionalArguments: ["--ui-appearance-layout=\(mode)"])
            app.staticTexts["外观"].firstMatch.click()

            let layout = app.descendants(matching: .any)["settings.appearance.layout.\(mode)"]
            XCTAssertTrue(layout.waitForExistence(timeout: 2), "未进入 \(mode) 外观布局")
            XCTAssertTrue(app.descendants(matching: .any)["settings.appearance.preview"].exists)

            let lastStatus = app.descendants(matching: .any)["settings.appearance.blockquote.background.status"]
            let scroll = mode == "wide"
                ? app.scrollViews["settings.appearance.editor.scroll"]
                : app.scrollViews["settings.appearance.layout.narrow"]
            scrollUntilHittable(lastStatus, in: scroll)
            XCTAssertTrue(lastStatus.isHittable, "\(mode) 布局无法滚动到最后一个颜色状态")
            assertNoIntersection(lastStatus, app.buttons["settings.apply"])
            app.terminate()
        }
    }

    func testClassicAppearanceResetPreservesLayoutAndInputDraft() throws {
        let app = try launchSettings(additionalArguments: ["--ui-appearance-layout=narrow"])
        app.staticTexts["布局"].firstMatch.click()
        let width = app.textFields["settings.layout.maximumWidth"]
        XCTAssertTrue(width.waitForExistence(timeout: 2))
        width.click(); width.typeKey("a", modifierFlags: .command); width.typeText("1232")

        app.staticTexts["输入"].firstMatch.click()
        let ime = app.switches["settings.input.imeGuard"]
        XCTAssertTrue(ime.waitForExistence(timeout: 2))
        if (ime.value as? String) != "0" { ime.click() }

        app.staticTexts["外观"].firstMatch.click()
        let reset = app.buttons["settings.appearance.reset.all"]
        XCTAssertTrue(reset.waitForExistence(timeout: 2))
        reset.click()
        XCTAssertEqual(app.textFields["settings.appearance.heading.color"].value as? String, "#F2C94C")

        app.staticTexts["布局"].firstMatch.click()
        let finalWidth = app.textFields["settings.layout.maximumWidth"]
        XCTAssertTrue(finalWidth.waitForExistence(timeout: 2))
        let widthValue = String(describing: finalWidth.value ?? "").replacingOccurrences(of: ",", with: "")
        XCTAssertEqual(widthValue, "1232")
        app.staticTexts["输入"].firstMatch.click()
        let finalIME = app.switches["settings.input.imeGuard"]
        XCTAssertTrue(finalIME.waitForExistence(timeout: 2))
        XCTAssertEqual(String(describing: finalIME.value ?? ""), "0")
    }

    func testAppearanceColorFeedbackAndPreviewSchemeAreDirectlyOperable() throws {
        let app = try launchSettings(additionalArguments: ["--ui-appearance-layout=narrow"])
        app.staticTexts["外观"].firstMatch.click()

        let rgbaField = app.textFields["settings.appearance.inlineCode.background"]
        XCTAssertTrue(rgbaField.waitForExistence(timeout: 2))
        XCTAssertEqual(rgbaField.value as? String, "rgba(223, 48, 121, 0.10)")
        XCTAssertEqual(app.descendants(matching: .any)["settings.appearance.inlineCode.background.status"].label, "有效颜色")
        XCTAssertTrue(app.descendants(matching: .any)["settings.appearance.inlineCode.background.picker"].exists)

        let scheme = app.descendants(matching: .any)["settings.appearance.preview.scheme"]
        XCTAssertTrue(scheme.waitForExistence(timeout: 2))
        let lightChoice = app.descendants(matching: .any).matching(NSPredicate(format: "label == '浅色'")).firstMatch
        XCTAssertTrue(lightChoice.waitForExistence(timeout: 2))
        lightChoice.click()
        XCTAssertTrue(app.descendants(matching: .any)["settings.appearance.preview.heading"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["settings.appearance.preview.inlineCode"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["settings.appearance.preview.quote"].exists)

        let semanticField = app.textFields["settings.appearance.blockquote.text"]
        scrollUntilHittable(semanticField, in: app.scrollViews["settings.appearance.layout.narrow"])
        XCTAssertEqual(semanticField.value as? String, "inherit")
        let semanticStatus = app.descendants(matching: .any)["settings.appearance.blockquote.text.status"]
        XCTAssertEqual(semanticStatus.label, "语义颜色 inherit")
        XCTAssertFalse(app.descendants(matching: .any)["settings.appearance.blockquote.text.picker"].exists)

        let invalidField = app.textFields["settings.appearance.blockquote.background"]
        replaceText(invalidField, with: "not-a-css-color")
        let invalidStatus = app.descendants(matching: .any)["settings.appearance.blockquote.background.status"]
        XCTAssertEqual(invalidStatus.label, "无效")
        XCTAssertFalse(app.descendants(matching: .any)["settings.appearance.blockquote.background.picker"].exists)
    }

    func testAppearanceRealWindowResizeKeepsContentAboveFooter() throws {
        let app = try launchSettings()
        app.staticTexts["外观"].firstMatch.click()
        let window = app.windows.firstMatch
        guard window.waitForExistence(timeout: 2) else {
            throw XCTSkip("当前 LSUIElement 设置窗口未作为 XCUI window 暴露，XCUITest 无法拖动真实窗口边框；宽/窄布局与 footer 不相交由强制布局测试覆盖。")
        }

        if !app.descendants(matching: .any)["settings.appearance.layout.wide"].exists {
            let zoom = window.buttons[XCUIIdentifierZoomWindow]
            guard zoom.waitForExistence(timeout: 2) else {
                throw XCTSkip("当前 macOS 未向 XCUITest 暴露 LSUIElement 设置窗口的 zoom 按钮，无法先扩大窗口执行真实 resize。")
            }
            zoom.click()
        }
        XCTAssertTrue(app.descendants(matching: .any)["settings.appearance.layout.wide"].waitForExistence(timeout: 2))
        let lastStatus = app.descendants(matching: .any)["settings.appearance.blockquote.background.status"]
        scrollUntilHittable(lastStatus, in: app.scrollViews["settings.appearance.editor.scroll"])
        assertNoIntersection(lastStatus, app.buttons["settings.apply"])

        let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 0.995, dy: 0.995))
        let narrower = window.coordinate(withNormalizedOffset: CGVector(dx: 0.58, dy: 0.995))
        corner.press(forDuration: 0.2, thenDragTo: narrower)
        XCTAssertTrue(app.descendants(matching: .any)["settings.appearance.layout.narrow"].waitForExistence(timeout: 3))
        scrollUntilHittable(lastStatus, in: app.scrollViews["settings.appearance.layout.narrow"])
        assertNoIntersection(lastStatus, app.buttons["settings.apply"])
    }

    func testOpenSettingsOnLaunchOpensWindowWithoutStatusMenuInteraction() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-status=normal", "--ui-open-settings-on-launch"]
        app.launch()

        XCTAssertTrue(app.staticTexts["通用"].waitForExistence(timeout: 8))
    }

    func testInvalidDraftAndPreapplyFailureAreExplained() throws {
        let app = try launchSettings()
        app.staticTexts["布局"].firstMatch.click()
        let width = app.textFields["settings.layout.maximumWidth"]
        XCTAssertTrue(width.waitForExistence(timeout: 2))
        width.click(); width.typeKey("a", modifierFlags: .command); width.typeText("100")
        app.buttons["settings.apply"].click()
        XCTAssertTrue(app.staticTexts["settings.error"].waitForExistence(timeout: 2))

        width.click(); width.typeKey("a", modifierFlags: .command); width.typeText("666")
        app.buttons["settings.apply"].click()
        XCTAssertTrue(app.staticTexts["settings.error"].waitForExistence(timeout: 2))
    }

    private func scrollUntilHittable(_ element: XCUIElement, in scrollView: XCUIElement) {
        XCTAssertTrue(scrollView.waitForExistence(timeout: 2))
        for _ in 0..<8 where !element.isHittable {
            scrollView.swipeUp()
        }
    }

    private func replaceText(_ field: XCUIElement, with value: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(value)
        XCTAssertEqual(field.value as? String, value)
    }

    private func assertNoIntersection(_ content: XCUIElement, _ footerButton: XCUIElement) {
        XCTAssertTrue(content.waitForExistence(timeout: 2))
        XCTAssertTrue(footerButton.waitForExistence(timeout: 2))
        XCTAssertFalse(content.frame.intersects(footerButton.frame))
    }
}
