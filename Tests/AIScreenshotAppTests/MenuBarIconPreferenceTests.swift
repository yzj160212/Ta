import XCTest
@testable import AIScreenshotApp

/// 菜单栏图标可隐藏之后的回归防线。
///
/// 隐藏的语义是「只是不占菜单栏的位置」：App 继续在后台运行，全局快捷键、
/// 截图、识图与 Agent Bridge 全部照常工作。
final class MenuBarIconPreferenceTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ta-menubar-icon-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testDefaultsToVisibleWhenPreferenceMissing() {
        XCTAssertTrue(MenuBarIconPreference.isVisible(arguments: [], defaults: defaults))
    }

    func testHonorsHiddenPreference() {
        defaults.set(false, forKey: MenuBarIconPreference.defaultsKey)
        XCTAssertFalse(MenuBarIconPreference.isVisible(arguments: [], defaults: defaults))
    }

    func testForceShowArgumentRestoresIconAndPersistsPreference() {
        defaults.set(false, forKey: MenuBarIconPreference.defaultsKey)

        let visible = MenuBarIconPreference.isVisible(
            arguments: ["/Applications/拓.app/Contents/MacOS/AIScreenshotApp", MenuBarIconPreference.forceShowArgument],
            defaults: defaults
        )

        XCTAssertTrue(visible)
        // 读取本身不写偏好（写 UserDefaults 会发通知，在通知回调里再读会重入崩溃），
        // 持久化交给显式方法。
        XCTAssertFalse(defaults.bool(forKey: MenuBarIconPreference.defaultsKey))

        MenuBarIconPreference.persistForcedVisibilityIfNeeded(
            arguments: [MenuBarIconPreference.forceShowArgument],
            defaults: defaults
        )
        XCTAssertTrue(
            defaults.bool(forKey: MenuBarIconPreference.defaultsKey),
            "用启动参数恢复后要把偏好改回「显示」，否则设置页开关和实际状态会打架"
        )
    }

    // MARK: - Dock 图标

    func testDockIconDefaultsToVisible() {
        XCTAssertTrue(DockIconPreference.isVisible(arguments: [], defaults: defaults))
        XCTAssertEqual(DockIconPreference.activationPolicy(visible: true), .regular)
        XCTAssertEqual(
            DockIconPreference.activationPolicy(visible: false),
            .accessory,
            "隐藏 Dock 图标走 .accessory：Dock 里不出现，但菜单栏图标与后台能力都保留"
        )
    }

    func testDockIconHonorsHiddenPreferenceAndForceShowArgument() {
        defaults.set(false, forKey: DockIconPreference.defaultsKey)
        XCTAssertFalse(DockIconPreference.isVisible(arguments: [], defaults: defaults))

        // 两个入口都隐藏时唯一的找回方式
        let visible = DockIconPreference.isVisible(
            arguments: ["AIScreenshotApp", DockIconPreference.forceShowArgument],
            defaults: defaults
        )
        XCTAssertTrue(visible)
        XCTAssertFalse(defaults.bool(forKey: DockIconPreference.defaultsKey))

        DockIconPreference.persistForcedVisibilityIfNeeded(
            arguments: [DockIconPreference.forceShowArgument],
            defaults: defaults
        )
        XCTAssertTrue(defaults.bool(forKey: DockIconPreference.defaultsKey))
    }

    @MainActor
    func testControllerFollowsPreferenceWhenReapplied() throws {
        let standard = UserDefaults.standard
        let original = standard.object(forKey: MenuBarIconPreference.defaultsKey)
        defer {
            if let original {
                standard.set(original, forKey: MenuBarIconPreference.defaultsKey)
            } else {
                standard.removeObject(forKey: MenuBarIconPreference.defaultsKey)
            }
        }

        let appModel = AppModel(arguments: ["AIScreenshotApp", "--agent-bridge"])
        let controller = MenuBarController(appModel: appModel)

        standard.set(false, forKey: MenuBarIconPreference.defaultsKey)
        controller.applyVisibility()
        XCTAssertFalse(controller.isIconInstalled, "偏好为隐藏时不应挂着状态栏图标")

        standard.set(true, forKey: MenuBarIconPreference.defaultsKey)
        controller.applyVisibility()
        XCTAssertTrue(controller.isIconInstalled, "偏好为显示时应重新装回图标")

        standard.set(false, forKey: MenuBarIconPreference.defaultsKey)
        controller.applyVisibility()
        XCTAssertFalse(controller.isIconInstalled)
    }
}