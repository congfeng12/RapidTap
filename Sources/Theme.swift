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
