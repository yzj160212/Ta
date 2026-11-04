import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var dockIconController: DockIconController?


    func applicationDidFinishLaunching(_ notification: Notification) {
        // 故意不设置 `NSApplication.shared.applicationIconImage`。
        // Dock 里显示的图标来自 App Bundle 的 Ta.icns（已按 macOS 图标网格留出
        // ~80.5% 的图形占比）；一旦在这里用满幅美术图覆盖，Dock 会把它缩放到整块
        // 图标位置，结果比邻居大一圈（实测 134px vs 110px @ tilesize 67pt）。
        // Dock 图标是否显示由偏好决定（设置 → 常规）。提到创建菜单栏之前应用，
        // 免得启动瞬间先闪一下 Dock 图标。
        dockIconController = DockIconController()

        if let appModel = AppModel.current {
            menuBarController = MenuBarController(appModel: appModel)
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        guard let appModel = AppModel.current, !appModel.isCapturing else {
            return false
        }
        appModel.showWelcome()
        return true
    }
}
