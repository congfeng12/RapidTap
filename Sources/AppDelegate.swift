import Cocoa

/// 应用生命周期：创建主窗口、菜单，退出时释放全局监听与连点线程
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        self.buildMainMenu()

        // 岛风需要内置字体；Apple 风格下注册了也不影响
        IslandFont.registerBundledFonts()
        self.applyAppearance()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.styleChanged),
                                               name: .rapidTapStyleChanged,
                                               object: nil)

        let controller = self.makeRootViewController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "RapidTap 连点器"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = self.rootBackgroundColor
        window.contentViewController = controller

        // 先完成一次布局拿到内容高度，再按鼠标所在显示器居中，避免窗口跳动
        controller.view.layoutSubtreeIfNeeded()
        window.setContentSize(NSSize(width: 520, height: controller.preferredHeight))
        self.positionOnActiveScreen(window)

        window.makeKeyAndOrderFront(nil)
        self.window = window

        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        ClickEngine.shared.stop()
        HotKeyMonitor.shared.stop()
    }

    /// 根据配置创建对应风格的根界面
    private func makeRootViewController() -> NSViewController & RootViewSizing {
        switch Settings.shared.current.uiStyle {
        case .island:
            return IslandMainViewController()
        case .apple:
            return MainViewController()
        }
    }

    /// 根窗口背景色
    private var rootBackgroundColor: NSColor {
        return Settings.shared.current.uiStyle == .island ? Island.bg : .underPageBackgroundColor
    }

    /// 应用外观：岛风强制浅色；Apple 风格使用用户选择的主题
    private func applyAppearance() {
        if Settings.shared.current.uiStyle == .island {
            NSApp.appearance = NSAppearance(named: .aqua)
        } else {
            Settings.shared.current.theme.apply()
        }
    }

    /// 设置里切换界面风格后，原地重建根界面并保持窗口位置
    @objc private func styleChanged() {
        guard let window = self.window else { return }

        let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        let controller = self.makeRootViewController()
        controller.view.layoutSubtreeIfNeeded()

        window.contentViewController = controller
        window.setContentSize(NSSize(width: 520, height: controller.preferredHeight))
        window.setFrameOrigin(NSPoint(x: topLeft.x, y: topLeft.y - window.frame.height))
        window.backgroundColor = self.rootBackgroundColor
        self.applyAppearance()
    }

    /// 把窗口放到当前鼠标所在的显示器中央（多屏环境下更符合直觉）
    private func positionOnActiveScreen(_ window: NSWindow) {
        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(cursor, $0.frame, false) } ?? NSScreen.main
        guard let target = screen else { return }

        let visible = target.visibleFrame
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                      y: visible.midY - size.height / 2))
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 RapidTap",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 RapidTap",
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 RapidTap",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // 编辑菜单保证系统快捷键（复制/粘贴等）正常工作
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }
}
