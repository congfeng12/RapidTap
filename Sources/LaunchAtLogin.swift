import Foundation
import ServiceManagement

/// 开机自启动（登录项）管理
///
/// 使用 macOS 13 起推荐的 `SMAppService.mainApp`：
/// 注册后应用会出现在「系统设置 → 通用 → 登录项」中，用户可随时关闭。
enum LaunchAtLogin {

    /// 系统当前记录的登录项状态
    static var status: SMAppService.Status {
        return SMAppService.mainApp.status
    }

    /// 是否已启用开机自启动
    static var isEnabled: Bool {
        return status == .enabled
    }

    /// 开启或关闭开机自启动
    /// - Parameter enabled: true 注册登录项，false 取消注册
    /// - Throws: 注册/注销失败时抛出系统错误（例如未获用户批准）
    static func set(_ enabled: Bool) throws {
        let service = SMAppService.mainApp

        if enabled {
            guard service.status != .enabled else { return }
            try service.register()
        } else {
            guard service.status == .enabled || service.status == .requiresApproval else { return }
            try service.unregister()
        }
    }
}
