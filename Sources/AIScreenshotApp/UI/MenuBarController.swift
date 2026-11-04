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
        if arguments.contains(forceShowArgument) { return true }
        guard defaults.object(forKey: defaultsKey) != nil else { return true }
        return defaults.bool(forKey: defaultsKey)
    }

    /// 用启动参数恢复显示后，把偏好也改回「显示」，免得设置页开关与实际状态打架。
    ///
    /// ⚠️ 写 UserDefaults 会同步发出 `didChangeNotification`；在通知回调里再读写
    /// UserDefaults 会撞上 CFPreferences 重入（实测 SIGSEGV），所以这个写入必须
    /// 放在通知栈之外执行 —— 由调用方在已经脱开通知路径的地方调用。
    static func persistForcedVisibilityIfNeeded(
        arguments: [String],
        defaults: UserDefaults = .standard
    ) {
        guard arguments.contains(forceShowArgument) else { return }
        if defaults.bool(forKey: defaultsKey) != true {
            defaults.set(true, forKey: defaultsKey)
        }
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
        let arguments = ProcessInfo.processInfo.arguments
        MenuBarIconPreference.persistForcedVisibilityIfNeeded(arguments: arguments)
        let visible = MenuBarIconPreference.isVisible(arguments: arguments)
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
        // 不能在 didChangeNotification 里同步再读 UserDefaults（会重入 CFPreferences）。
        Task { @MainActor [weak self] in
            self?.applyVisibility()
        }
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
/// Dock 图标是否显示。
///
/// 隐藏 Dock 图标（切到 `.accessory` 激活策略）后 App 依然在后台运行，
/// 菜单栏图标、全局快捷键、截图与 Agent Bridge 都不受影响。
enum DockIconPreference {
    static let defaultsKey = "dockIconVisible"
    /// 启动参数：强制显示 Dock 图标，并把偏好改回「显示」。
    ///
    /// 只有「Dock 图标和菜单栏图标都隐藏」时才需要它 —— 那时 GUI 上没有任何入口，
    /// 只能用 `open -a 拓 --args --show-dock-icon` 找回。
    static let forceShowArgument = "--show-dock-icon"

    static func isVisible(arguments: [String], defaults: UserDefaults = .standard) -> Bool {
        if arguments.contains(forceShowArgument) { return true }
        guard defaults.object(forKey: defaultsKey) != nil else { return true }
        return defaults.bool(forKey: defaultsKey)
    }

    /// 见 `MenuBarIconPreference.persistForcedVisibilityIfNeeded` 关于重入的说明。
    static func persistForcedVisibilityIfNeeded(
        arguments: [String],
        defaults: UserDefaults = .standard
    ) {
        guard arguments.contains(forceShowArgument) else { return }
        if defaults.bool(forKey: defaultsKey) != true {
            defaults.set(true, forKey: defaultsKey)
        }
    }

    static func activationPolicy(visible: Bool) -> NSApplication.ActivationPolicy {
        visible ? .regular : .accessory
    }
}

/// 按偏好切换 `NSApplication` 的激活策略，即时控制 Dock 图标。
///
/// 切换用 `setActivationPolicy` 而不是改 Info.plist 的 `LSUIElement`：
/// 前者能在运行期来回切、立刻生效，也不必为「显示/隐藏」各打一份包。
@MainActor
final class DockIconController {
    // deinit 是 nonisolated，Swift 6 下需要显式标注；观察者随 App 生命周期存在。
    nonisolated(unsafe) private var defaultsObserver: NSObjectProtocol?

    init() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // 同样要脱出通知栈，否则 apply() 里的 UserDefaults 读取会重入崩溃。
            Task { @MainActor in
                self?.apply()
            }
        }
        apply()
        // AppKit 在启动收尾阶段会按 Info.plist 里的 LSUIElement 再摆一次激活策略，
        // 太早设置会被覆盖；等这一轮 runloop 结束后再应用一次。
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.apply() }
        }
    }

    deinit {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    /// 按偏好应用激活策略。重复调用是幂等的。
    func apply() {
        let arguments = ProcessInfo.processInfo.arguments
        DockIconPreference.persistForcedVisibilityIfNeeded(arguments: arguments)
        let visible = DockIconPreference.isVisible(arguments: arguments)
        let policy = DockIconPreference.activationPolicy(visible: visible)
        guard NSApplication.shared.activationPolicy() != policy else { return }
        _ = NSApplication.shared.setActivationPolicy(policy)
    }
}
