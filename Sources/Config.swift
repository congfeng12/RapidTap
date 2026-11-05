import Foundation

/// 连点器运行配置，持久化在 UserDefaults 中
struct Config: Codable {
    /// 触发按键的虚拟键码（CGKeyCode）
    var triggerKeyCode: UInt16 = KeyCode.f6
    /// true = 按住触发；false = 按一下开始、再按一下停止
    var holdToClick: Bool = false
    /// 每秒点击次数
    var clicksPerSecond: Double = 12
    /// 是否开启拟人化节奏（间隔抖动 + 按压时长随机 + 偶发停顿）
    var humanize: Bool = true
    /// 间隔随机抖动幅度，百分比 0~45
    var jitterPercent: Double = 22
    /// 关闭拟人化时使用的固定按压时长，毫秒
    var pressDurationMs: Double = 35
    /// 是否让点击坐标产生亚像素抖动
    var cursorJitter: Bool = false
    /// 外观主题：浅色 / 深色 / 跟随系统
    var theme: Theme = .system

    private enum CodingKeys: String, CodingKey {
        case triggerKeyCode, holdToClick, clicksPerSecond, humanize
        case jitterPercent, pressDurationMs, cursorJitter, theme
    }

    init() {}

    /// 逐字段解码并回退到默认值：
    /// 即使某个字段缺失或类型变化（例如后续版本新增字段），也不会整体重置已保存的触发键
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.triggerKeyCode = try container.decodeIfPresent(UInt16.self, forKey: .triggerKeyCode) ?? KeyCode.f6
        self.holdToClick = try container.decodeIfPresent(Bool.self, forKey: .holdToClick) ?? false
        self.clicksPerSecond = try container.decodeIfPresent(Double.self, forKey: .clicksPerSecond) ?? 12
        self.humanize = try container.decodeIfPresent(Bool.self, forKey: .humanize) ?? true
        self.jitterPercent = try container.decodeIfPresent(Double.self, forKey: .jitterPercent) ?? 22
        self.pressDurationMs = try container.decodeIfPresent(Double.self, forKey: .pressDurationMs) ?? 35
        self.cursorJitter = try container.decodeIfPresent(Bool.self, forKey: .cursorJitter) ?? false
        self.theme = try container.decodeIfPresent(Theme.self, forKey: .theme) ?? .system
    }
}

/// 配置读写：多线程安全（连点线程会高频读取），任何修改立即原子落盘
///
/// 存储位置：`~/Library/Application Support/RapidTap/config.json`
/// 使用独立文件而不是 UserDefaults，是为了让每一次改动都同步写入磁盘：
/// UserDefaults 落盘是异步的，拖动滑杆连续写入或进程被强制结束时可能丢失最后一次修改。
final class Settings {

    static let shared = Settings()

    /// 旧版本存 UserDefaults 的键，仅用于一次性迁移
    private static let legacyKey = "rapidtap.config.v1"
    private static let authorizedOnceKey = "rapidtap.authorizedOnce"

    private let lock = NSLock()
    private var config: Config
    private let fileURL: URL

    /// 配置文件路径（供诊断与排查使用）
    var configFilePath: String { fileURL.path }

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                              in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = support.appendingPathComponent("RapidTap", isDirectory: true)
        self.fileURL = directory.appendingPathComponent("config.json")

        // 1. 优先读取配置文件
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Config.self, from: data) {
            self.config = decoded
            return
        }

        // 2. 首次运行或文件丢失：从旧版本 UserDefaults 迁移，避免丢掉已有设置
        if let data = UserDefaults.standard.data(forKey: Settings.legacyKey),
           let decoded = try? JSONDecoder().decode(Config.self, from: data) {
            self.config = decoded
            Settings.write(decoded, to: fileURL)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                UserDefaults.standard.removeObject(forKey: Settings.legacyKey)
            }
            return
        }

        // 3. 全新安装：写入默认配置
        self.config = Config()
        Settings.write(self.config, to: fileURL)
    }

    /// 当前配置快照（值类型，调用方可安全持有）
    var current: Config {
        lock.lock()
        defer { lock.unlock() }
        return config
    }

    /// 修改配置并立即落盘
    /// - Parameter mutate: 在锁内修改配置的闭包
    func update(_ mutate: (inout Config) -> Void) {
        lock.lock()
        mutate(&config)
        let snapshot = config
        lock.unlock()

        Settings.write(snapshot, to: fileURL)
    }

    /// 原子写入配置文件
    private static func write(_ config: Config, to url: URL) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("RapidTap: 配置写入失败 \(url.path): \(error.localizedDescription)")
        }
    }

    // MARK: - 授权记录

    /// 是否曾经成功获得过辅助功能授权
    /// 用于区分"从未授权"和"授权后失效（例如重新编译导致签名变化）"
    var hasBeenAuthorized: Bool {
        UserDefaults.standard.bool(forKey: Settings.authorizedOnceKey)
    }

    /// 记录已获得授权（只写一次）
    func rememberAuthorized() {
        guard !UserDefaults.standard.bool(forKey: Settings.authorizedOnceKey) else { return }
        UserDefaults.standard.set(true, forKey: Settings.authorizedOnceKey)
    }
}
