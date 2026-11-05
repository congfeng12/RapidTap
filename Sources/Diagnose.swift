import Cocoa
import ApplicationServices

/// 命令行诊断：确认当前进程是否具备权限、能否创建事件监听
enum Diagnose {

    static func run() {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        print("RapidTap 环境诊断")
        print("  macOS        : \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)")
        print("  架构         : \(architectureName())")
        print("  辅助功能权限 : \(AXIsProcessTrusted() ? "已授权" : "未授权")")

        let callback: CGEventTapCallBack = { _, _, event, _ in
            return Unmanaged.passUnretained(event)
        }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let port = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                     place: .headInsertEventTap,
                                     options: .listenOnly,
                                     eventsOfInterest: mask,
                                     callback: callback,
                                     userInfo: nil)
        print("  全局监听     : \(port == nil ? "不可用（缺少辅助功能/输入监控权限）" : "可用")")
        if let port = port {
            CFMachPortInvalidate(port)
        }
        print("  HID 事件源   : \(CGEventSource(stateID: .hidSystemState) == nil ? "不可用" : "可用")")
        print("  程序路径     : \(Bundle.main.bundlePath)")

        let settings = Settings.shared
        let config = settings.current
        print("  配置文件     : \(settings.configFilePath)")
        print("  当前设置     : 触发键 \(KeyNames.name(for: config.triggerKeyCode))"
              + " / \(Int(config.clicksPerSecond)) 次/秒"
              + " / \(config.holdToClick ? "按住连点" : "按一下切换")"
              + " / 拟人化\(config.humanize ? "开" : "关")"
              + " / 坐标抖动\(config.cursorJitter ? "开" : "关")")
    }

    private static func architectureName() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}
