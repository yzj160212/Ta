import AppKit
import SwiftUI

extension Notification.Name {
    static let taMenuBarShouldClose = Notification.Name("TaMenuBarShouldClose")
}

/// 菜单栏图标是否显示。
///
/// 隐藏后 App 照常运行：全局快捷键、截图、识图、Agent Bridge 都不受影响，
/// 只是菜单栏上不再占一个图标位。
enum MenuBarIconPreference {
    static let defaultsKey = "menuBarIconVisible"
    /// 启动参数：强制显示图标，并把偏好改回「显示」。
    ///
    /// 图标被隐藏后，恢复入口有两个：
    /// 1. 点 Dock 图标 → 打开欢迎页 → ⌘, 打开设置 → 常规 → 打开开关；
    /// 2. `open -a 拓 --args --show-menu-bar-icon`。
    static let forceShowArgument = "--show-menu-bar-icon"

    static func isVisible(arguments: [String], defaults: UserDefaults = .standard) -> Bool {
        if arguments.contains(forceShowArgument) {
            defaults.set(true, forKey: defaultsKey)
            return true
        }
        guard defaults.object(forKey: defaultsKey) != nil else { return true }
        return defaults.bool(forKey: defaultsKey)
    }
}

@MainActor
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let appModel: AppModel

    init(appModel: AppModel) {
        self.appModel = appModel
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 326, height: 574)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarContentView(appModel: appModel)
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(closePopover(_:)),
            name: .taMenuBarShouldClose,
            object: nil
        )
        // @AppStorage 写 UserDefaults 会触发这个通知，用来即时跟随设置页里的开关。
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(defaultsDidChange(_:)),
            name: UserDefaults.didChangeNotification,
            object: nil
        )

        applyVisibility()
    }

    /// 当前菜单栏上是否挂着图标（供测试与状态展示使用）。
    var isIconInstalled: Bool { statusItem != nil }

    /// 按偏好安装或移除状态栏图标。重复调用是幂等的。
    func applyVisibility() {
        let visible = MenuBarIconPreference.isVisible(
            arguments: ProcessInfo.processInfo.arguments
        )
        if visible {
            installStatusItemIfNeeded()
        } else {
            removeStatusItem()
        }
    }

    private func installStatusItemIfNeeded() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            if let sourceImage = TaBrandAssets.appIcon,
               let image = sourceImage.copy() as? NSImage {
                image.size = NSSize(width: 19, height: 19)
                image.isTemplate = false
                button.image = image
                button.imageScaling = .scaleProportionallyDown
            } else {
                button.image = NSImage(systemSymbolName: "seal.fill", accessibilityDescription: TaBrand.name)
            }
            button.toolTip = "\(TaBrand.name) · \(TaBrand.englishName)"
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        statusItem = item
    }

    private func removeStatusItem() {
        guard let item = statusItem else { return }
        popover.performClose(nil)
        NSStatusBar.system.removeStatusItem(item)
        statusItem = nil
    }

    @objc private func defaultsDidChange(_ notification: Notification) {
        applyVisibility()
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    @objc private func closePopover(_ notification: Notification) {
        popover.performClose(nil)
    }
}