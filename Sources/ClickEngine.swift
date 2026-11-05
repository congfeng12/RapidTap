import Cocoa
import ApplicationServices
import Darwin

/// 连点执行引擎
///
/// 在独立的高优先级线程中按设定频率向系统注入鼠标左键事件。
/// 拟人化开启时，间隔、按压时长、停顿都会带随机量，避免出现
/// "固定周期、固定脉宽" 这种明显由程序生成的节奏。
final class ClickEngine {

    static let shared = ClickEngine()

    private let lock = NSLock()
    private var running = false
    private var worker: Thread?
    private var clickCounter = 0

    private init() {}

    /// 当前是否正在连点
    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    /// 本次运行已注入的点击次数
    var clickCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return clickCounter
    }

    /// 是否已获得辅助功能权限（模拟点击与全局监听都依赖它）
    static var hasPermission: Bool {
        AXIsProcessTrusted()
    }

    /// 开始连点
    /// - Returns: 是否成功启动；未授权或已在运行时返回 false
    @discardableResult
    func start() -> Bool {
        guard AXIsProcessTrusted() else { return false }

        lock.lock()
        if running {
            lock.unlock()
            return false
        }
        running = true
        clickCounter = 0
        lock.unlock()

        let thread = Thread { [weak self] in
            self?.runLoop()
        }
        thread.name = "RapidTap.Clicker"
        thread.qualityOfService = .userInteractive

        lock.lock()
        worker = thread
        lock.unlock()

        thread.start()
        return true
    }

    /// 停止连点（线程会在当前周期结束后退出）
    func stop() {
        lock.lock()
        running = false
        worker = nil
        lock.unlock()
    }

    /// 在运行与停止之间切换
    func toggle() {
        if isRunning {
            stop()
        } else {
            start()
        }
    }

    // MARK: - 内部实现

    private func runLoop() {
        let startupConfig = Settings.shared.current
        if startupConfig.humanize {
            // 启动时随机延迟 8~50ms，避免每次都正好在按键瞬间开始
            Thread.sleep(forTimeInterval: Double.random(in: 0.008...0.050))
        }

        while isRunning {
            let config = Settings.shared.current
            let baseInterval = 1000.0 / max(1.0, config.clicksPerSecond)

            var waitMs = baseInterval
            var holdMs = config.pressDurationMs

            if config.humanize {
                let amplitude = baseInterval * min(max(config.jitterPercent, 0), 45) / 100.0
                waitMs = baseInterval + Double.random(in: -amplitude...amplitude)

                // 按压时长随机；上限压到周期的 45%，否则高频时实际节奏会被拖慢
                let randomHold = Double.random(in: 16...52)
                holdMs = min(randomHold, max(4, baseInterval * 0.45))

                // 约 1.4% 概率插入一次较长停顿，模拟人手换气/走神
                if Int.random(in: 0..<70) == 0 {
                    waitMs += Double.random(in: 55...160)
                }
            }

            holdMs = max(2, min(holdMs, waitMs - 1))
            waitMs = max(2, waitMs)

            performClick(holdMs: holdMs, jitter: config.cursorJitter)
            bumpCounter()

            let sleepMs = max(1, waitMs - holdMs)
            usleep(useconds_t(sleepMs * 1000))
        }
    }

    private func performClick(holdMs: Double, jitter: Bool) {
        guard var point = CGEvent(source: nil)?.location else { return }

        if jitter {
            // 亚像素级偏移：让连续点击的落点不是完全同一个坐标
            point.x += CGFloat(Double.random(in: -1.2...1.2))
            point.y += CGFloat(Double.random(in: -1.2...1.2))
        }

        // hidSystemState 让注入事件走 HID 事件源，兼容性优于合成事件源
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(mouseEventSource: source,
                                 mouseType: .leftMouseDown,
                                 mouseCursorPosition: point,
                                 mouseButton: .left),
              let up = CGEvent(mouseEventSource: source,
                               mouseType: .leftMouseUp,
                               mouseCursorPosition: point,
                               mouseButton: .left) else {
            return
        }

        down.setIntegerValueField(.mouseEventClickState, value: 1)
        up.setIntegerValueField(.mouseEventClickState, value: 1)

        down.post(tap: .cghidEventTap)
        usleep(useconds_t(max(1, holdMs) * 1000))
        up.post(tap: .cghidEventTap)
    }

    private func bumpCounter() {
        lock.lock()
        clickCounter += 1
        lock.unlock()
    }
}
