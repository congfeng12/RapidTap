import Cocoa
import ApplicationServices

/// 主界面：只保留连点设置与启动区域，其余内容收进「设置」面板
final class MainViewController: NSViewController {

    private static let contentTopInset: CGFloat = 38
    private static let contentBottomInset: CGFloat = 20

    private let settings = Settings.shared
    private let engine = ClickEngine.shared
    private let monitor = HotKeyMonitor.shared

    private let contentStack = NSStackView()
    private let settingsButton = NSButton(title: "设置", target: nil, action: nil)

    // 权限横幅（仅未授权时显示）
    private let permissionCard = CardView()
    private let permissionBadge = SymbolBadgeView(symbolName: "exclamationmark.shield.fill",
                                                  tint: .systemOrange,
                                                  side: 24)
    private let permissionLabel = NSTextField(labelWithString: "未授权：无法拦截按键和模拟点击")
    private let permissionButton = NSButton(title: "去授权", target: nil, action: nil)

    // 更新横幅（仅有新版本时显示）
    private let updateCard = CardView()
    private let updateLabel = NSTextField(labelWithString: "")
    private let updateButton = NSButton(title: "查看", target: nil, action: nil)

    // 连点设置
    private let cpsValueLabel = NSTextField(labelWithString: "")
    private let cpsSubtitleLabel = NSTextField(labelWithString: "")
    private let cpsSlider = NSSlider(value: Config().clicksPerSecond, minValue: 1, maxValue: 60, target: nil, action: nil)
    private let humanizeSwitch = NSSwitch()
    private let jitterValueLabel = NSTextField(labelWithString: "")
    private let jitterSlider = NSSlider(value: Config().jitterPercent, minValue: 0, maxValue: 45, target: nil, action: nil)
    private let cursorJitterSwitch = NSSwitch()
    private var jitterBlockView: NSView?

    // 运行状态
    private let statusDot = StatusDotView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    private let toggleButton = NSButton(title: "开始连点", target: nil, action: nil)
    private let playImage = NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil)
    private let stopImage = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: nil)

    private var uiTimer: Timer?
    private var isSyncingUI = false
    private var didAutoCheckUpdate = false
    private var isSettingsPresented = false

    // MARK: - 生命周期

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: UIConstants.windowWidth, height: 560))
        root.wantsLayer = true
        self.view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.buildLayout()
        self.bindActions()
        self.bindMonitor()
        self.refreshFromSettings()
        self.refreshRuntime()
        self.refreshPermission()
        self.refreshUpdateBanner()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.updateStateChanged),
                                               name: UpdateManager.stateDidChange,
                                               object: nil)

        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.refreshRuntime()
            self?.refreshPermission()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.uiTimer = timer
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        self.refreshFromSettings()
        self.refreshRuntime()
        self.refreshPermission()
        self.refreshUpdateBanner()

        // 启动后静默检查一次更新
        guard !self.didAutoCheckUpdate else { return }
        self.didAutoCheckUpdate = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            UpdateManager.shared.autoCheckIfNeeded()
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard let window = self.view.window, let contentView = window.contentView else { return }

        let desired = self.preferredHeight
        guard abs(contentView.frame.height - desired) > 0.5 else { return }

        // 保持窗口左上角不动地调整高度，避免每次布局都跳动
        let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        window.setContentSize(NSSize(width: UIConstants.windowWidth, height: desired))
        window.setFrameOrigin(NSPoint(x: topLeft.x, y: topLeft.y - window.frame.height))
    }

    /// 内容理想高度（含上下留白），由 AppDelegate 用于初始化窗口尺寸
    var preferredHeight: CGFloat {
        let height = self.contentStack.frame.height
        guard height > 1 else { return 420 }
        return height + Self.contentTopInset + Self.contentBottomInset
    }

    deinit {
        self.uiTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 布局

    private func buildLayout() {
        let root = self.contentStack
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: UIConstants.contentInset),
            root.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -UIConstants.contentInset),
            root.topAnchor.constraint(equalTo: self.view.topAnchor, constant: Self.contentTopInset),
            root.bottomAnchor.constraint(lessThanOrEqualTo: self.view.bottomAnchor,
                                         constant: -Self.contentBottomInset),
            root.widthAnchor.constraint(equalToConstant: UIConstants.windowWidth - UIConstants.contentInset * 2)
        ])

        UIBuilder.addFullWidth(self.makeHeader(), to: root)
        UIBuilder.addFullWidth(self.makePermissionBanner(), to: root)
        UIBuilder.addFullWidth(self.makeUpdateBanner(), to: root)
        UIBuilder.addFullWidth(self.makeClickCard(), to: root)
        UIBuilder.addFullWidth(self.makeStatusCard(), to: root)
    }

    private func makeHeader() -> NSView {
        let badge = SymbolBadgeView(symbolName: "cursorarrow.click.2",
                                    tint: .controlAccentColor,
                                    side: 36)

        let title = NSTextField(labelWithString: "RapidTap")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        title.textColor = .labelColor

        let subtitle = NSTextField(labelWithString: "全局触发键 · 鼠标左键连点 · 拟人化节奏")
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor

        let titles = NSStackView(views: [title, subtitle])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 1

        self.settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        self.settingsButton.imagePosition = .imageLeading
        self.settingsButton.bezelStyle = .rounded
        self.settingsButton.controlSize = .regular
        self.settingsButton.setAccessibilityLabel("打开设置")

        let row = NSStackView(views: [badge, titles, UIBuilder.makeSpacer(), self.settingsButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    private func makePermissionBanner() -> NSView {
        self.permissionLabel.font = .systemFont(ofSize: 12)
        self.permissionLabel.textColor = .labelColor
        self.permissionLabel.lineBreakMode = .byTruncatingTail

        self.permissionButton.controlSize = .small
        self.permissionButton.bezelStyle = .rounded

        let row = NSStackView(views: [self.permissionBadge,
                                      self.permissionLabel,
                                      UIBuilder.makeSpacer(),
                                      self.permissionButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false

        self.permissionCard.translatesAutoresizingMaskIntoConstraints = false
        self.permissionCard.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: self.permissionCard.leadingAnchor, constant: UIConstants.cardInset),
            row.trailingAnchor.constraint(equalTo: self.permissionCard.trailingAnchor, constant: -UIConstants.cardInset),
            row.topAnchor.constraint(equalTo: self.permissionCard.topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: self.permissionCard.bottomAnchor, constant: -10)
        ])
        self.permissionCard.isHidden = true
        return self.permissionCard
    }

    private func makeUpdateBanner() -> NSView {
        self.updateLabel.font = .systemFont(ofSize: 12)
        self.updateLabel.textColor = .labelColor

        self.updateButton.controlSize = .small
        self.updateButton.bezelStyle = .rounded

        var views: [NSView] = []
        if let icon = UIBuilder.makeRowIcon("arrow.triangle.2.circlepath") {
            views.append(icon)
        }
        views.append(contentsOf: [self.updateLabel, UIBuilder.makeSpacer(), self.updateButton])

        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false

        self.updateCard.translatesAutoresizingMaskIntoConstraints = false
        self.updateCard.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: self.updateCard.leadingAnchor, constant: UIConstants.cardInset),
            row.trailingAnchor.constraint(equalTo: self.updateCard.trailingAnchor, constant: -UIConstants.cardInset),
            row.topAnchor.constraint(equalTo: self.updateCard.topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: self.updateCard.bottomAnchor, constant: -10)
        ])
        self.updateCard.isHidden = true
        return self.updateCard
    }

    private func makeClickCard() -> NSView {
        self.cpsValueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        self.cpsValueLabel.textColor = .secondaryLabelColor
        self.cpsSubtitleLabel.font = .systemFont(ofSize: 11)
        self.cpsSubtitleLabel.textColor = .secondaryLabelColor
        self.cpsSlider.setContentHuggingPriority(.init(1), for: .horizontal)
        self.cpsSlider.setAccessibilityLabel("点击频率")

        let cpsRow = UIBuilder.makeSettingRow(symbol: "speedometer",
                                              title: "点击频率",
                                              subtitleLabel: self.cpsSubtitleLabel,
                                              trailing: [self.cpsValueLabel])
        let cpsBlock = UIBuilder.makeSliderBlock(slider: self.cpsSlider, header: cpsRow)

        self.humanizeSwitch.controlSize = .regular
        self.humanizeSwitch.setAccessibilityLabel("拟人化随机节奏")
        let humanizeRow = UIBuilder.makeSettingRow(symbol: "wand.and.stars",
                                                   title: "拟人化随机节奏",
                                                   subtitle: "间隔抖动 · 按压时长随机 · 偶发停顿",
                                                   trailing: [self.humanizeSwitch])

        self.jitterValueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        self.jitterValueLabel.textColor = .secondaryLabelColor
        self.jitterSlider.setContentHuggingPriority(.init(1), for: .horizontal)
        self.jitterSlider.setAccessibilityLabel("间隔随机幅度")

        let jitterRow = UIBuilder.makeSettingRow(symbol: "slider.horizontal.3",
                                                 title: "间隔随机幅度",
                                                 trailing: [self.jitterValueLabel])
        let jitterBlock = UIBuilder.makeSliderBlock(slider: self.jitterSlider, header: jitterRow)
        self.jitterBlockView = jitterBlock

        self.cursorJitterSwitch.controlSize = .regular
        self.cursorJitterSwitch.setAccessibilityLabel("点击坐标微抖动")
        let cursorRow = UIBuilder.makeSettingRow(symbol: "cursorarrow",
                                                 title: "点击坐标微抖动",
                                                 subtitle: "每次落点偏移 ±1.2 像素",
                                                 trailing: [self.cursorJitterSwitch])

        return UIBuilder.makeCard(rows: [cpsBlock, humanizeRow, jitterBlock, cursorRow])
    }

    private func makeStatusCard() -> NSView {
        self.statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        self.statusLabel.textColor = .labelColor

        self.countLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        self.countLabel.textColor = .secondaryLabelColor

        let topRow = NSStackView(views: [self.statusDot,
                                         self.statusLabel,
                                         UIBuilder.makeSpacer(),
                                         self.countLabel])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 8
        topRow.translatesAutoresizingMaskIntoConstraints = false

        self.toggleButton.bezelStyle = .rounded
        self.toggleButton.controlSize = .large
        self.toggleButton.font = .systemFont(ofSize: 13, weight: .semibold)
        self.toggleButton.bezelColor = .controlAccentColor
        self.toggleButton.imagePosition = .imageLeading
        self.toggleButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        self.toggleButton.translatesAutoresizingMaskIntoConstraints = false

        let card = CardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(topRow)
        card.addSubview(self.toggleButton)

        NSLayoutConstraint.activate([
            topRow.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: UIConstants.cardInset),
            topRow.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -UIConstants.cardInset),
            topRow.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),

            self.toggleButton.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: UIConstants.cardInset),
            self.toggleButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -UIConstants.cardInset),
            self.toggleButton.topAnchor.constraint(equalTo: topRow.bottomAnchor, constant: 10),
            self.toggleButton.heightAnchor.constraint(equalToConstant: 32),
            self.toggleButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ])
        return card
    }

    // MARK: - 事件绑定

    private func bindActions() {
        self.settingsButton.target = self
        self.settingsButton.action = #selector(self.openSettings)

        self.permissionButton.target = self
        self.permissionButton.action = #selector(self.openPermissionSettings)

        self.updateButton.target = self
        self.updateButton.action = #selector(self.openSettings)

        self.cpsSlider.target = self
        self.cpsSlider.action = #selector(self.cpsChanged)
        self.cpsSlider.isContinuous = true

        self.humanizeSwitch.target = self
        self.humanizeSwitch.action = #selector(self.humanizeChanged)

        self.jitterSlider.target = self
        self.jitterSlider.action = #selector(self.jitterChanged)
        self.jitterSlider.isContinuous = true

        self.cursorJitterSwitch.target = self
        self.cursorJitterSwitch.action = #selector(self.cursorJitterChanged)

        self.toggleButton.target = self
        self.toggleButton.action = #selector(self.toggleRunning)
    }

    private func bindMonitor() {
        self.monitor.onTriggerDown = { [weak self] in
            self?.triggerKeyPressed()
        }
        self.monitor.onTriggerUp = { [weak self] in
            self?.triggerKeyReleased()
        }
    }

    // MARK: - 用户操作

    @objc private func openSettings(_ sender: Any) {
        guard !self.isSettingsPresented else { return }
        self.isSettingsPresented = true

        let controller = SettingsViewController()
        controller.onDismiss = { [weak self] in
            guard let self = self else { return }
            self.isSettingsPresented = false
            self.refreshFromSettings()
            self.refreshRuntime()
            self.refreshPermission()
        }
        _ = controller.view   // 触发 loadView（macOS 13 没有 loadViewIfNeeded）
        controller.view.layoutSubtreeIfNeeded()
        let size = controller.preferredSize
        controller.view.frame = NSRect(origin: .zero, size: size)
        controller.preferredContentSize = size
        self.presentAsSheet(controller)
    }

    @objc private func openPermissionSettings(_ sender: Any) {
        self.requestPermissionPrompt()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        self.refreshPermission()
    }

    @objc private func cpsChanged(_ sender: Any) {
        guard !self.isSyncingUI else { return }
        let value = self.cpsSlider.doubleValue.rounded()
        self.settings.update { $0.clicksPerSecond = value }
        self.refreshDerivedLabels()
    }

    @objc private func humanizeChanged(_ sender: Any) {
        guard !self.isSyncingUI else { return }
        let enabled = self.humanizeSwitch.state == .on
        self.settings.update { $0.humanize = enabled }
        self.refreshDerivedLabels()
    }

    @objc private func jitterChanged(_ sender: Any) {
        guard !self.isSyncingUI else { return }
        let value = self.jitterSlider.doubleValue.rounded()
        self.settings.update { $0.jitterPercent = value }
        self.refreshDerivedLabels()
    }

    @objc private func cursorJitterChanged(_ sender: Any) {
        guard !self.isSyncingUI else { return }
        let enabled = self.cursorJitterSwitch.state == .on
        self.settings.update { $0.cursorJitter = enabled }
    }

    @objc private func toggleRunning(_ sender: Any) {
        if self.engine.isRunning {
            self.engine.stop()
        } else if !self.engine.start() {
            NSSound.beep()
            self.refreshPermission()
        }
        self.refreshRuntime()
    }

    // MARK: - 触发键处理

    private func triggerKeyPressed() {
        let config = self.settings.current
        if config.holdToClick {
            if !self.engine.start() {
                NSSound.beep()
                self.refreshPermission()
            }
        } else if self.engine.isRunning {
            self.engine.stop()
        } else if !self.engine.start() {
            NSSound.beep()
            self.refreshPermission()
        }
        self.refreshRuntime()
    }

    private func triggerKeyReleased() {
        if self.settings.current.holdToClick {
            self.engine.stop()
            self.refreshRuntime()
        }
    }

    // MARK: - 界面刷新

    @objc private func updateStateChanged() {
        self.refreshUpdateBanner()
    }

    private func refreshFromSettings() {
        self.isSyncingUI = true
        defer { self.isSyncingUI = false }

        let config = self.settings.current
        self.cpsSlider.doubleValue = config.clicksPerSecond
        self.humanizeSwitch.state = config.humanize ? .on : .off
        self.jitterSlider.doubleValue = config.jitterPercent
        self.cursorJitterSwitch.state = config.cursorJitter ? .on : .off
        self.refreshDerivedLabels()
    }

    private func refreshDerivedLabels() {
        let config = self.settings.current
        let interval = 1000.0 / max(1.0, config.clicksPerSecond)

        self.cpsValueLabel.stringValue = String(format: "%.0f 次/秒", config.clicksPerSecond)
        self.cpsSubtitleLabel.stringValue = String(format: "间隔 %.0f 毫秒", interval)
        self.jitterValueLabel.stringValue = String(format: "±%.0f%%", config.jitterPercent)

        self.jitterBlockView?.alphaValue = config.humanize ? 1.0 : 0.4
        self.jitterSlider.isEnabled = config.humanize
    }

    private func refreshPermission() {
        let trusted = AXIsProcessTrusted()
        self.permissionCard.isHidden = trusted
        if trusted {
            self.settings.rememberAuthorized()
            if !self.monitor.isActive {
                _ = self.monitor.start()
            }
        }
    }

    private func refreshUpdateBanner() {
        if let info = UpdateManager.shared.availableUpdate {
            self.updateLabel.stringValue = "发现新版本 \(info.tag)"
            self.updateCard.isHidden = false
        } else {
            self.updateCard.isHidden = true
        }
    }

    private func refreshRuntime() {
        let running = self.engine.isRunning
        let count = self.engine.clickCount
        let keyName = KeyNames.name(for: self.settings.current.triggerKeyCode)

        self.statusDot.color = running ? .systemGreen : .tertiaryLabelColor
        self.statusLabel.stringValue = running ? "运行中" : "未运行"
        self.countLabel.stringValue = "已点击 \(count) 次"

        self.toggleButton.title = running ? "停止连点（\(keyName)）" : "开始连点（\(keyName)）"
        self.toggleButton.bezelColor = running ? .systemRed : .controlAccentColor
        self.toggleButton.image = running ? self.stopImage : self.playImage
    }

    private func requestPermissionPrompt() {
        // 用字面量键触发系统授权弹窗，避免不同 SDK 对 CFString 全局量的桥接差异
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
