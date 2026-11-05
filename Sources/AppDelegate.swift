import Cocoa

/// 应用生命周期：创建主窗口、菜单，退出时释放全局监听与连点线程
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        self.buildMainMenu()

        // 先应用保存的主题，再创建窗口，避免启动时闪一下另一种外观
        Settings.shared.current.theme.apply()

        let controller = MainViewController()
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
        window.backgroundColor = .underPageBackgroundColor
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
