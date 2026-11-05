import Cocoa
import ApplicationServices

/// 全局按键监听
///
/// 通过 CGEventTap 在会话层拦截按键：命中触发键时吞掉事件（前台应用收不到），
/// 同时回调给界面层启停连点。支持"录制"模式来设置任意触发键。
final class HotKeyMonitor {

    static let shared = HotKeyMonitor()

    /// 触发键按下（主线程回调）
    var onTriggerDown: (() -> Void)?
    /// 触发键抬起（主线程回调）
    var onTriggerUp: (() -> Void)?
    /// 录制到新按键（主线程回调，参数为虚拟键码）
    var onKeyCaptured: ((UInt16) -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var isActive = false

    private let stateLock = NSLock()
    private var recording = false

    private init() {}

    /// 是否处于按键录制状态
    var isRecording: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return recording
    }

    /// 进入录制状态，下一次按键会被捕获
    func beginRecording() {
        stateLock.lock()
        recording = true
        stateLock.unlock()
    }

    /// 退出录制状态
    func cancelRecording() {
        stateLock.lock()
        recording = false
        stateLock.unlock()
    }

    /// 安装全局事件监听
    /// - Returns: 是否安装成功（未授权或系统拒绝时返回 false）
    @discardableResult
    func start() -> Bool {
        if isActive { return true }
        guard AXIsProcessTrusted() else { return false }

        // 修饰键（⌘⌥⌃⇧、Caps Lock、Fn）不会产生 keyDown/keyUp，而是 flagsChanged
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: rapidTapEventCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            return false
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        self.tap = port
        self.runLoopSource = source
        self.isActive = true
        return true
    }

    /// 卸载全局事件监听
    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let port = tap {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        runLoopSource = nil
        tap = nil
        isActive = false
    }

    // MARK: - 事件处理

    /// 由 C 回调转发进来，必须快速返回
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // 系统因超时或用户输入禁用了监听，需要重新启用
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port = tap {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))

        // 修饰键单独处理，并且不吞事件
        if type == .flagsChanged {
            return self.handleModifierEvent(code: code, event: event)
        }

        // 录制期间吞掉按键，避免误输入到前台应用
        if isRecording && type == .keyDown {
            stateLock.lock()
            recording = false
            stateLock.unlock()
            DispatchQueue.main.async { [weak self] in
                self?.onKeyCaptured?(code)
            }
            return nil
        }

        guard code == Settings.shared.current.triggerKeyCode,
              type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown {
            // 过滤按住不放产生的系统重复事件
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                DispatchQueue.main.async { [weak self] in
                    self?.onTriggerDown?()
                }
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.onTriggerUp?()
            }
        }
        // 命中的触发键不再传给前台应用
        return nil
    }
}

// MARK: - 修饰键

extension HotKeyMonitor {

    /// 处理 ⌘⌥⌃⇧ / Caps Lock / Fn 的状态变化
    ///
    /// 修饰键事件始终放行：吞掉修饰键会导致系统和前台应用丢失按键状态，
    /// 例如 ⌘ 被吞后所有 ⌘ 组合键都会失效。
    fileprivate func handleModifierEvent(code: UInt16, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let flag = HotKeyMonitor.modifierFlag(for: code) else {
            return Unmanaged.passUnretained(event)
        }
        let pressed = event.flags.contains(flag)

        if self.isRecording {
            if pressed {
                self.stateLock.lock()
                self.recording = false
                self.stateLock.unlock()
                DispatchQueue.main.async { [weak self] in
                    self?.onKeyCaptured?(code)
                }
            }
            return Unmanaged.passUnretained(event)
        }

        if code == Settings.shared.current.triggerKeyCode {
            DispatchQueue.main.async { [weak self] in
                if pressed {
                    self?.onTriggerDown?()
                } else {
                    self?.onTriggerUp?()
                }
            }
        }
        return Unmanaged.passUnretained(event)
    }

    /// 修饰键键码 → 对应的 CGEventFlags
    fileprivate static func modifierFlag(for code: UInt16) -> CGEventFlags? {
        switch code {
        case 54, 55: return .maskCommand
        case 56, 60: return .maskShift
        case 58, 61: return .maskAlternate
        case 59, 62: return .maskControl
        case 57: return .maskAlphaShift
        case 63: return .maskSecondaryFn
        default: return nil
        }
    }
}

/// CGEventTap 的 C 函数指针回调：不能捕获上下文，实例通过 refcon 取回
private func rapidTapEventCallback(proxy: CGEventTapProxy,
                                    type: CGEventType,
                                    event: CGEvent,
                                    refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon = refcon else {
        return Unmanaged.passUnretained(event)
    }
    let monitor = Unmanaged<HotKeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
    return monitor.handle(type: type, event: event)
}
