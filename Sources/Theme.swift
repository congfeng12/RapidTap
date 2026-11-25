import Cocoa

/// 应用外观主题
enum Theme: String, Codable, CaseIterable {
    case system
    case light
    case dark

    /// 对应的 NSAppearance，nil 表示跟随系统
    var appearance: NSAppearance? {
        switch self {
        case .system:
            return nil
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        }
    }

    /// 把主题应用到整个应用（含菜单与弹窗）
    func apply() {
        NSApp.appearance = self.appearance
    }
}


/// 界面风格
enum UIStyle: String, Codable, CaseIterable {
    case apple
    case island

    var displayName: String {
        switch self {
        case .apple: return "Apple 风格"
        case .island: return "动森风格"
        }
    }
}

extension Notification.Name {
    /// 用户在设置里切换界面风格
    static let rapidTapStyleChanged = Notification.Name("rapidTapStyleChanged")
}

/// 主窗口根视图控制器需要提供内容高度，便于切换风格后重新定尺寸
protocol RootViewSizing: AnyObject {
    var preferredHeight: CGFloat { get }
}
