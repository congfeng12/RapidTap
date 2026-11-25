import Cocoa
import ApplicationServices

/// 设置面板（以 sheet 形式打开）
///
/// 收纳主界面之外的全部内容：权限状态、触发键与模式、主题、开机自启动、软件更新与风险提示。
final class IslandSettingsViewController: NSViewController {

    /// 面板关闭回调，由主界面用于恢复状态
    var onDismiss: (() -> Void)?

    private static let topInset: CGFloat = 20
    private static let bottomInset: CGFloat = 20

    private let settings = Settings.shared
    private let monitor = HotKeyMonitor.shared

    private let contentStack = NSStackView()

    // 权限
    private let permissionBadge = IslandSymbolBadgeView(symbolName: "checkmark.shield.fill",
                                                  tint: .systemGreen,
                                                  side: 30)
    private let permissionTitleLabel = NSTextField(labelWithString: "辅助功能权限")
    private let permissionSubtitleLabel = NSTextField(labelWithString: "")
    private let permissionButton = IslandButton(title: "去授权", target: nil, action: nil)
    private let permissionHintLabel = NSTextField(labelWithString: "")

    // 触发
    private let triggerValueLabel = NSTextField(labelWithString: "")
    private let recordButton = IslandButton(title: "重新设置", target: nil, action: nil)
    private let modeControl = IslandSegmented(labels: ["按住连点", "按一下切换"],
                                                 trackingMode: .selectOne,
                                                 target: nil,
                                                 action: nil)
    private let triggerHintLabel = NSTextField(labelWithString: "")

    // 通用
    private let styleButton = IslandButton(title: "Apple 风格")
    private let launchAtLoginSwitch = IslandSwitch()
    private let launchAtLoginSubtitle = NSTextField(labelWithString: "登录后自动打开")
    private let updateSubtitleLabel = NSTextField(labelWithString: "")
    private let updateButton = IslandButton(title: "检查更新", target: nil, action: nil)

    private let footerLabel = NSTextField(labelWithString: "")
    private let doneButton = IslandButton(title: "完成", target: nil, action: nil)

    private var uiTimer: Timer?
    private var isSyncingUI = false
    private var isRecordingKey = false

    // MARK: - 生命周期

    override func loadView() {
        let root = IslandPanelBackgroundView(frame: NSRect(x: 0, y: 0, width: IslandConstants.windowWidth, height: 640))
        root.wantsLayer = true
        self.view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.buildLayout()
        self.bindActions()
        self.bindMonitor()
        self.refreshFromSettings()
        self.refreshTriggerDisplay()
        self.refreshPermission()
        self.styleButton.title = self.settings.current.uiStyle.displayName
        self.refreshLaunchAtLogin()
        self.refreshUpdateRow()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.updateStateChanged),
                                               name: UpdateManager.stateDidChange,
                                               object: nil)

        let timer = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.refreshPermission()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.uiTimer = timer
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        self.isRecordingKey = false
        self.monitor.cancelRecording()
        self.monitor.onKeyCaptured = nil
        self.uiTimer?.invalidate()
        self.onDismiss?()
    }

    deinit {
        self.uiTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    /// 面板理想尺寸
    var preferredSize: NSSize {
        let height = self.contentStack.frame.height
        return NSSize(width: IslandConstants.windowWidth,
                      height: max(420, height + Self.topInset + Self.bottomInset))
    }

    // MARK: - 布局

    private func buildLayout() {
        let root = self.contentStack
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 16
        root.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: IslandConstants.contentInset),
            root.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -IslandConstants.contentInset),
            root.topAnchor.constraint(equalTo: self.view.topAnchor, constant: Self.topInset),
            root.bottomAnchor.constraint(lessThanOrEqualTo: self.view.bottomAnchor, constant: -Self.bottomInset),
            root.widthAnchor.constraint(equalToConstant: IslandConstants.windowWidth - IslandConstants.contentInset * 2)
        ])

        IslandBuilder.addFullWidth(self.makeTitle(), to: root)
        IslandBuilder.addFullWidth(self.makePermissionBlock(), to: root)
        IslandBuilder.addFullWidth(IslandBuilder.makeSection(title: "触发",
                                                     card: self.makeTriggerCard(),
                                                     footnote: self.triggerHintLabel), to: root)
        IslandBuilder.addFullWidth(IslandBuilder.makeSection(title: "通用",
                                                     card: self.makeGeneralCard(),
                                                     footnote: nil), to: root)
        IslandBuilder.addFullWidth(self.makeFooter(), to: root)
        IslandBuilder.addFullWidth(self.makeDoneRow(), to: root)
    }

    private func makeTitle() -> NSView {
        let title = NSTextField(labelWithString: "设置")
        title.font = Island.font(17, 700)
        title.textColor = Island.text
        return title
    }

    private func makePermissionBlock() -> NSView {
        self.permissionTitleLabel.font = Island.font(13, 600)
        self.permissionTitleLabel.textColor = Island.text

        self.permissionSubtitleLabel.font = Island.font(11, 500)
        self.permissionSubtitleLabel.textColor = Island.secondaryText

        self.permissionButton.controlSize = .regular
        self.permissionButton.bezelStyle = .rounded

        let titles = NSStackView(views: [self.permissionTitleLabel, self.permissionSubtitleLabel])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 2

        let row = NSStackView(views: [self.permissionBadge,
                                      titles,
                                      IslandBuilder.makeSpacer(),
                                      self.permissionButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false

        let card = IslandCardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: IslandConstants.cardInset),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -IslandConstants.cardInset),
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
        ])

        self.permissionHintLabel.font = Island.font(11, 500)
        self.permissionHintLabel.textColor = Island.warningText
        IslandBuilder.configureWrapping(self.permissionHintLabel,
                                    width: IslandConstants.windowWidth - IslandConstants.contentInset * 2)
        self.permissionHintLabel.isHidden = true

        let stack = NSStackView(views: [card, self.permissionHintLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        self.permissionHintLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func makeTriggerCard() -> NSView {
        self.modeControl.controlSize = .regular
        self.modeControl.setAccessibilityLabel("触发模式")

        self.triggerValueLabel.setAccessibilityLabel("当前触发按键")
        self.triggerValueLabel.font = Island.mono(13, 700)
        self.triggerValueLabel.textColor = Island.text
        self.triggerValueLabel.alignment = .right

        self.recordButton.controlSize = .regular
        self.recordButton.bezelStyle = .rounded
        self.recordButton.setAccessibilityHelp("进入录制状态后按下新的触发键")

        let keyRow = IslandBuilder.makeSettingRow(symbol: "keyboard",
                                              title: "触发按键",
                                              trailing: [self.triggerValueLabel, self.recordButton])
        let modeRow = IslandBuilder.makeSettingRow(symbol: "hand.tap",
                                               title: "触发模式",
                                               trailing: [self.modeControl])

        self.triggerHintLabel.stringValue = "在主界面开启连点器后，普通按键会被全局拦截、不再传给当前应用；⌘⌥⌃⇧ 等修饰键不会被拦截，建议配合「按住连点」。"
        self.triggerHintLabel.font = Island.font(11, 500)
        self.triggerHintLabel.textColor = Island.mutedText
        IslandBuilder.configureWrapping(self.triggerHintLabel,
                                    width: IslandConstants.windowWidth - IslandConstants.contentInset * 2)

        return IslandBuilder.makeCard(rows: [keyRow, modeRow])
    }

    private func makeGeneralCard() -> NSView {
        self.styleButton.controlSize = .small
        self.styleButton.setAccessibilityLabel("界面风格")
        let styleRow = IslandBuilder.makeSettingRow(symbol: "paintpalette",
                                                    title: "界面风格",
                                                    subtitle: "切换后立即生效",
                                                    trailing: [self.styleButton])

        self.launchAtLoginSwitch.controlSize = .regular
        self.launchAtLoginSwitch.setAccessibilityLabel("开机自启动")
        self.launchAtLoginSubtitle.font = Island.font(11, 500)
        self.launchAtLoginSubtitle.textColor = Island.secondaryText
        let loginRow = IslandBuilder.makeSettingRow(symbol: "power",
                                                title: "开机自启动",
                                                subtitleLabel: self.launchAtLoginSubtitle,
                                                trailing: [self.launchAtLoginSwitch])

        self.updateSubtitleLabel.font = Island.font(11, 500)
        self.updateSubtitleLabel.textColor = Island.secondaryText
        self.updateButton.controlSize = .regular
        self.updateButton.bezelStyle = .rounded
        let updateRow = IslandBuilder.makeSettingRow(symbol: "arrow.triangle.2.circlepath",
                                                 title: "软件更新",
                                                 subtitleLabel: self.updateSubtitleLabel,
                                                 trailing: [self.updateButton])

        return IslandBuilder.makeCard(rows: [styleRow, loginRow, updateRow])
    }

    private func makeFooter() -> NSView {
        self.footerLabel.stringValue = "风险提示：仅供个人自动化与单机场景使用。全局事件注入无法保证绕过专业反作弊系统，在联网游戏中使用可能违反服务条款并导致封号，请自行评估风险。"
        self.footerLabel.font = Island.font(11, 500)
        self.footerLabel.textColor = Island.mutedText
        IslandBuilder.configureWrapping(self.footerLabel,
                                    width: IslandConstants.windowWidth - IslandConstants.contentInset * 2)
        return self.footerLabel
    }

    private func makeDoneRow() -> NSView {
        self.doneButton.bezelStyle = .rounded
        self.doneButton.controlSize = .large
        self.doneButton.style = .primary
        self.doneButton.keyEquivalent = "\r"

        let row = NSStackView(views: [IslandBuilder.makeSpacer(), self.doneButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 0
        return row
    }

    // MARK: - 事件绑定

    private func bindActions() {
        self.doneButton.target = self
        self.doneButton.action = #selector(self.doneClicked)

        self.permissionButton.target = self
        self.permissionButton.action = #selector(self.openPermissionSettings)

        self.recordButton.target = self
        self.recordButton.action = #selector(self.toggleKeyRecording)

        self.modeControl.target = self
        self.modeControl.action = #selector(self.modeChanged)

        self.styleButton.target = self
        self.styleButton.action = #selector(self.showStyleMenu)

        self.launchAtLoginSwitch.target = self
        self.launchAtLoginSwitch.action = #selector(self.launchAtLoginChanged)

        self.updateButton.target = self
        self.updateButton.action = #selector(self.updateButtonClicked)
    }

    private func bindMonitor() {
        self.monitor.onKeyCaptured = { [weak self] code in
            self?.keyCaptured(code)
        }
    }

    // MARK: - 用户操作

    @objc private func doneClicked(_ sender: Any) {
        self.dismiss(self)
    }

    @objc private func openPermissionSettings(_ sender: Any) {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        self.refreshPermission()
    }

    @objc private func toggleKeyRecording(_ sender: Any) {
        if self.isRecordingKey {
            self.isRecordingKey = false
            self.monitor.cancelRecording()
            self.refreshTriggerDisplay()
            return
        }

        guard AXIsProcessTrusted() else {
            NSSound.beep()
            self.refreshPermission()
            return
        }
        if !self.monitor.isActive && !self.monitor.start() {
            NSSound.beep()
            self.triggerHintLabel.stringValue = "无法安装全局监听：请在「系统设置 → 隐私与安全性 → 输入监控」中允许 RapidTap 后重试。"
            self.triggerHintLabel.textColor = Island.warningText
            return
        }

        self.isRecordingKey = true
        self.monitor.beginRecording()
        self.refreshTriggerDisplay()
    }

    @objc private func modeChanged(_ sender: Any) {
        guard !self.isSyncingUI else { return }
        let hold = self.modeControl.selectedSegment == 0
        self.settings.update { $0.holdToClick = hold }
    }

    @objc private func showStyleMenu(_ sender: Any) {
        let menu = NSMenu()
        for style in UIStyle.allCases {
            let item = NSMenuItem(title: style.displayName,
                                  action: #selector(self.chooseStyle(_:)),
                                  keyEquivalent: "")
            item.representedObject = style.rawValue
            item.target = self
            menu.addItem(item)
        }
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: self.styleButton.bounds.height + 4),
                   in: self.styleButton)
    }

    @objc private func chooseStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let style = UIStyle(rawValue: raw) else { return }

        self.settings.update { $0.uiStyle = style }
        self.dismiss(self)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .rapidTapStyleChanged, object: nil)
        }
    }

    @objc private func launchAtLoginChanged(_ sender: Any) {
        guard !self.isSyncingUI else { return }

        let enabled = self.launchAtLoginSwitch.state == .on
        do {
            try LaunchAtLogin.set(enabled)
        } catch {
            NSSound.beep()
            self.launchAtLoginSubtitle.stringValue = "设置失败：\(error.localizedDescription)"
            self.launchAtLoginSubtitle.textColor = Island.error
        }
        self.refreshLaunchAtLogin()
    }

    @objc private func updateButtonClicked(_ sender: Any) {
        if let info = UpdateManager.shared.availableUpdate {
            UpdateManager.shared.install(info)
        } else {
            UpdateManager.shared.check()
        }
    }

    @objc private func updateStateChanged() {
        self.refreshUpdateRow()
    }

    private func keyCaptured(_ code: UInt16) {
        guard self.isRecordingKey else { return }
        self.isRecordingKey = false
        self.monitor.cancelRecording()

        // Esc 作为取消
        if code == KeyCode.escape {
            self.refreshTriggerDisplay()
            return
        }

        self.settings.update { $0.triggerKeyCode = code }
        self.triggerHintLabel.stringValue = "在主界面开启连点器后，普通按键会被全局拦截、不再传给当前应用；⌘⌥⌃⇧ 等修饰键不会被拦截，建议配合「按住连点」。"
        self.triggerHintLabel.textColor = Island.mutedText
        self.refreshTriggerDisplay()
    }

    // MARK: - 界面刷新

    private func refreshFromSettings() {
        self.isSyncingUI = true
        defer { self.isSyncingUI = false }

        let config = self.settings.current
        self.selectMode(hold: config.holdToClick)
        self.launchAtLoginSwitch.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    private func selectMode(hold: Bool) {
        let index = hold ? 0 : 1
        self.modeControl.selectedSegment = index
        for segment in 0..<self.modeControl.segmentCount {
            self.modeControl.setSelected(segment == index, forSegment: segment)
        }
    }

    private func refreshTriggerDisplay() {
        if self.isRecordingKey {
            self.triggerValueLabel.stringValue = "请按键…（Esc 取消）"
            self.triggerValueLabel.textColor = Island.warningText
            self.recordButton.title = "取消"
        } else {
            self.triggerValueLabel.stringValue = KeyNames.name(for: self.settings.current.triggerKeyCode)
            self.triggerValueLabel.textColor = Island.text
            self.recordButton.title = "重新设置"
        }
    }

    private func refreshPermission() {
        let trusted = AXIsProcessTrusted()

        if trusted {
            self.permissionBadge.symbolName = "checkmark.shield.fill"
            self.permissionBadge.tint = Island.success
            self.permissionSubtitleLabel.stringValue = "已授权，可以开始连点"
            self.permissionSubtitleLabel.textColor = Island.secondaryText
            self.permissionButton.isHidden = true
            self.permissionHintLabel.isHidden = true
            self.settings.rememberAuthorized()
            if !self.monitor.isActive {
                _ = self.monitor.start()
            }
        } else {
            self.permissionBadge.symbolName = "exclamationmark.shield.fill"
            self.permissionBadge.tint = Island.warning
            self.permissionSubtitleLabel.stringValue = "未授权：无法拦截按键和模拟点击"
            self.permissionSubtitleLabel.textColor = Island.warningText
            self.permissionButton.isHidden = false
            self.permissionHintLabel.isHidden = false

            if self.settings.hasBeenAuthorized {
                self.permissionHintLabel.stringValue = "系统授权已失效（重新编译后常见）。请在「系统设置 → 隐私与安全性 → 辅助功能」中取消勾选 RapidTap，再重新勾选。"
            } else {
                self.permissionHintLabel.stringValue = "在「系统设置 → 隐私与安全性 → 辅助功能」中勾选 RapidTap；若列表中没有，点 + 手动添加本应用。"
            }
        }
    }

    private func refreshLaunchAtLogin() {
        let status = LaunchAtLogin.status
        self.launchAtLoginSwitch.state = (status == .enabled) ? .on : .off

        switch status {
        case .enabled:
            self.launchAtLoginSubtitle.stringValue = "登录后自动打开"
            self.launchAtLoginSubtitle.textColor = Island.secondaryText
        case .requiresApproval:
            self.launchAtLoginSubtitle.stringValue = "需在「系统设置 → 通用 → 登录项」中允许"
            self.launchAtLoginSubtitle.textColor = Island.warningText
        case .notRegistered, .notFound:
            self.launchAtLoginSubtitle.stringValue = "登录后不会自动打开"
            self.launchAtLoginSubtitle.textColor = Island.secondaryText
        @unknown default:
            self.launchAtLoginSubtitle.stringValue = "登录后自动打开"
            self.launchAtLoginSubtitle.textColor = Island.secondaryText
        }
    }

    private func refreshUpdateRow() {
        let current = UpdateService.shared.currentVersion

        switch UpdateManager.shared.state {
        case .idle:
            self.updateSubtitleLabel.stringValue = "当前版本 \(current)"
            self.updateSubtitleLabel.textColor = Island.secondaryText
            self.updateButton.title = "检查更新"
            self.updateButton.bezelColor = nil
            self.updateButton.isEnabled = true

        case .checking:
            self.updateSubtitleLabel.stringValue = "正在检查更新…"
            self.updateSubtitleLabel.textColor = Island.secondaryText
            self.updateButton.title = "检查中…"
            self.updateButton.bezelColor = nil
            self.updateButton.isEnabled = false

        case .upToDate:
            self.updateSubtitleLabel.stringValue = "已是最新版本（\(current)）"
            self.updateSubtitleLabel.textColor = Island.secondaryText
            self.updateButton.title = "检查更新"
            self.updateButton.bezelColor = nil
            self.updateButton.isEnabled = true

        case .available(let info):
            self.updateSubtitleLabel.stringValue = "发现新版本 \(info.tag)（当前 \(current)）"
            self.updateSubtitleLabel.textColor = Island.warningText
            self.updateButton.title = "更新到 \(info.tag)"
            self.updateButton.bezelColor = Island.primary
            self.updateButton.isEnabled = true

        case .installing(let message):
            self.updateSubtitleLabel.stringValue = message
            self.updateSubtitleLabel.textColor = Island.secondaryText
            self.updateButton.title = "更新中…"
            self.updateButton.bezelColor = nil
            self.updateButton.isEnabled = false

        case .failed(let message):
            self.updateSubtitleLabel.stringValue = message
            self.updateSubtitleLabel.textColor = Island.error
            self.updateButton.title = "重试"
            self.updateButton.bezelColor = nil
            self.updateButton.isEnabled = true
        }
    }
}
