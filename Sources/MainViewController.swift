import Cocoa
import ApplicationServices

// MARK: - 视觉组件

/// 圆角卡片：系统设置风格的分组容器
private final class CardView: NSView {

    override var isOpaque: Bool { return false }

    override func draw(_ dirtyRect: NSRect) {
        // 与系统设置一致：不描边，仅靠卡片与窗口的底色差异分层
        let path = NSBezierPath(roundedRect: self.bounds, xRadius: 10, yRadius: 10)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        self.needsDisplay = true
    }
}

/// 1 像素分隔线，左侧缩进与标题对齐
private final class SeparatorView: NSView {

    /// 左侧缩进：与行内文字对齐（卡片内边距 + 图标 + 间距）
    var leadingInset: CGFloat = 38

    override var isOpaque: Bool { return false }

    override func draw(_ dirtyRect: NSRect) {
        // separatorColor 自带 10% 透明度，直接使用即为系统级细分隔线
        NSColor.separatorColor.setFill()
        let width = max(0, self.bounds.width - self.leadingInset)
        NSRect(x: self.leadingInset, y: 0, width: width, height: 1).fill()
    }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: NSView.noIntrinsicMetric, height: 1)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        self.needsDisplay = true
    }
}

/// 图标徽章：圆角底色 + SF Symbol
private final class SymbolBadgeView: NSView {

    private let imageView = NSImageView()
    private let side: CGFloat

    var tint: NSColor {
        didSet {
            self.imageView.contentTintColor = self.tint
            self.needsDisplay = true
        }
    }

    var symbolName: String {
        didSet {
            self.imageView.image = SymbolBadgeView.makeImage(self.symbolName, side: self.side)
        }
    }

    init(symbolName: String, tint: NSColor, side: CGFloat) {
        self.side = side
        self.tint = tint
        self.symbolName = symbolName
        super.init(frame: .zero)

        self.translatesAutoresizingMaskIntoConstraints = false
        self.imageView.image = SymbolBadgeView.makeImage(symbolName, side: side)
        self.imageView.contentTintColor = tint
        self.imageView.imageScaling = .scaleProportionallyDown
        self.imageView.setAccessibilityElement(false)
        self.imageView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.imageView)

        NSLayoutConstraint.activate([
            self.widthAnchor.constraint(equalToConstant: side),
            self.heightAnchor.constraint(equalToConstant: side),
            self.imageView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            self.imageView.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            self.imageView.widthAnchor.constraint(equalToConstant: side * 0.55),
            self.imageView.heightAnchor.constraint(equalToConstant: side * 0.55)
        ])
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: self.bounds,
                                xRadius: self.side * 0.26,
                                yRadius: self.side * 0.26)
        self.tint.withAlphaComponent(0.14).setFill()
        path.fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        self.needsDisplay = true
    }

    private static func makeImage(_ symbolName: String, side: CGFloat) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: side * 0.5, weight: .semibold)
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }
}

/// 状态圆点
private final class StatusDotView: NSView {

    var color: NSColor = .tertiaryLabelColor {
        didSet { self.needsDisplay = true }
    }

    override var isOpaque: Bool { return false }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: 8, height: 8)
    }

    override func draw(_ dirtyRect: NSRect) {
        let diameter = min(self.bounds.width, self.bounds.height)
        let rect = NSRect(x: (self.bounds.width - diameter) / 2,
                          y: (self.bounds.height - diameter) / 2,
                          width: diameter,
                          height: diameter)
        self.color.setFill()
        NSBezierPath(ovalIn: rect).fill()
    }
}

// MARK: - 主界面

/// 主界面：按 macOS 系统设置的分组表单风格组织
final class MainViewController: NSViewController {

    private static let windowWidth: CGFloat = 520
    private static let contentInset: CGFloat = 24
    private static let cardInset: CGFloat = 14
    private static let iconWidth: CGFloat = 16
    private static let contentTopInset: CGFloat = 38
    private static let contentBottomInset: CGFloat = 20

    private let settings = Settings.shared
    private let engine = ClickEngine.shared
    private let monitor = HotKeyMonitor.shared

    private let contentStack = NSStackView()

    // 权限
    private let permissionBadge = SymbolBadgeView(symbolName: "checkmark.shield.fill",
                                                  tint: .systemGreen,
                                                  side: 30)
    private let permissionTitleLabel = NSTextField(labelWithString: "辅助功能权限")
    private let permissionSubtitleLabel = NSTextField(labelWithString: "")
    private let permissionButton = NSButton(title: "去授权", target: nil, action: nil)
    private let permissionHintLabel = NSTextField(labelWithString: "")

    // 触发
    private let triggerValueLabel = NSTextField(labelWithString: "")
    private let recordButton = NSButton(title: "重新设置", target: nil, action: nil)
    private let modeControl = NSSegmentedControl(labels: ["按住连点", "按一下切换"],
                                                 trackingMode: .selectOne,
                                                 target: nil,
                                                 action: nil)
    private let triggerHintLabel = NSTextField(labelWithString: "")

    // 连点
    private let cpsValueLabel = NSTextField(labelWithString: "")
    private let cpsSubtitleLabel = NSTextField(labelWithString: "")
    private let cpsSlider = NSSlider(value: Config().clicksPerSecond, minValue: 1, maxValue: 60, target: nil, action: nil)
    private let jitterValueLabel = NSTextField(labelWithString: "")
    private let jitterSlider = NSSlider(value: Config().jitterPercent, minValue: 0, maxValue: 45, target: nil, action: nil)
    private let humanizeSwitch = NSSwitch()
    private let cursorJitterSwitch = NSSwitch()
    private let themeControl = NSSegmentedControl(labels: ["浅色", "深色", "跟随系统"],
                                                  trackingMode: .selectOne,
                                                  target: nil,
                                                  action: nil)
    private let launchAtLoginSwitch = NSSwitch()
    private let launchAtLoginSubtitle = NSTextField(labelWithString: "登录后自动打开")

    // 软件更新
    private let updateSubtitleLabel = NSTextField(labelWithString: "")
    private let updateButton = NSButton(title: "检查更新", target: nil, action: nil)
    private var availableUpdate: UpdateInfo?
    private var isCheckingUpdate = false
    private var didAutoCheckUpdate = false
    private var jitterBlockView: NSView?

    // 状态
    private let statusDot = StatusDotView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    private let toggleButton = NSButton(title: "开始连点", target: nil, action: nil)
    private let footerLabel = NSTextField(labelWithString: "")

    private let playImage = NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil)
    private let stopImage = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: nil)

    private var uiTimer: Timer?
    /// 程序化同步控件状态时置位，避免触发 action 把值再写回配置
    private var isSyncingUI = false
    private var isRecordingKey = false
    private var promptedPermission = false

    // MARK: - 生命周期

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: Self.windowWidth, height: 760))
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
        self.refreshRuntime()

        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.refreshRuntime()
            self?.refreshPermission()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.uiTimer = timer
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // 视图挂载后再同步一次，避免分段控件在窗口显示前设置选中项不生效
        self.refreshFromSettings()
        self.refreshTriggerDisplay()
        self.refreshRuntime()
        self.promptPermissionIfNeeded()
        self.autoCheckUpdatesIfNeeded()
    }

    /// 每次启动后自动检查一次更新（静默，不打断用户）
    private func autoCheckUpdatesIfNeeded() {
        guard !self.didAutoCheckUpdate else { return }
        self.didAutoCheckUpdate = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.checkForUpdates()
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard let window = self.view.window, let contentView = window.contentView else { return }

        let desired = self.preferredHeight
        guard abs(contentView.frame.height - desired) > 0.5 else { return }

        // 保持窗口左上角不动地调整高度，避免每次布局都跳动
        let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        window.setContentSize(NSSize(width: Self.windowWidth, height: desired))
        window.setFrameOrigin(NSPoint(x: topLeft.x, y: topLeft.y - window.frame.height))
    }

    /// 内容理想高度（含上下留白），由 AppDelegate 用于初始化窗口尺寸
    var preferredHeight: CGFloat {
        let height = self.contentStack.frame.height
        guard height > 1 else { return 700 }
        return height + Self.contentTopInset + Self.contentBottomInset
    }

    deinit {
        self.uiTimer?.invalidate()
    }

    // MARK: - 布局

    private func buildLayout() {
        let root = self.contentStack
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 18
        root.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: Self.contentInset),
            root.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -Self.contentInset),
            root.topAnchor.constraint(equalTo: self.view.topAnchor, constant: Self.contentTopInset),
            root.bottomAnchor.constraint(lessThanOrEqualTo: self.view.bottomAnchor,
                                         constant: -Self.contentBottomInset),
            root.widthAnchor.constraint(equalToConstant: Self.windowWidth - Self.contentInset * 2)
        ])

        self.addFullWidth(self.makeHeader(), to: root)
        self.addFullWidth(self.makePermissionBlock(), to: root)
        self.addFullWidth(self.makeSection(title: "触发",
                                          card: self.makeTriggerCard(),
                                          footnote: self.triggerHintLabel), to: root)
        self.addFullWidth(self.makeSection(title: "连点",
                                          card: self.makeClickCard(),
                                          footnote: nil), to: root)
        self.addFullWidth(self.makeSection(title: "通用",
                                          card: self.makeGeneralCard(),
                                          footnote: nil), to: root)
        self.addFullWidth(self.makeStatusCard(), to: root)
        self.addFullWidth(self.makeFooter(), to: root)
    }

    private func makeHeader() -> NSView {
        let badge = SymbolBadgeView(symbolName: "cursorarrow.click.2",
                                    tint: .controlAccentColor,
                                    side: 44)

        let title = NSTextField(labelWithString: "RapidTap")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        title.textColor = .labelColor

        let subtitle = NSTextField(labelWithString: "全局触发键 · 鼠标左键连点 · 拟人化节奏")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor

        let titles = NSStackView(views: [title, subtitle])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 2

        let row = NSStackView(views: [badge, titles])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    private func makePermissionBlock() -> NSView {
        self.permissionTitleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        self.permissionTitleLabel.textColor = .labelColor

        self.permissionSubtitleLabel.font = .systemFont(ofSize: 11)
        self.permissionSubtitleLabel.textColor = .secondaryLabelColor

        self.permissionButton.controlSize = .regular
        self.permissionButton.bezelStyle = .rounded

        let titles = NSStackView(views: [self.permissionTitleLabel, self.permissionSubtitleLabel])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 2

        let row = NSStackView(views: [self.permissionBadge,
                                      titles,
                                      self.makeSpacer(),
                                      self.permissionButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false

        let card = CardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Self.cardInset),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Self.cardInset),
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),

            self.permissionBadge.widthAnchor.constraint(equalToConstant: 30),
            self.permissionBadge.heightAnchor.constraint(equalToConstant: 30)
        ])

        self.permissionHintLabel.font = .systemFont(ofSize: 11)
        self.permissionHintLabel.textColor = .systemOrange
        self.configureWrapping(self.permissionHintLabel)
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
        self.modeControl.setAccessibilityLabel("触发模式")
        self.triggerValueLabel.setAccessibilityLabel("当前触发按键")
        self.recordButton.setAccessibilityHelp("进入录制状态后按下新的触发键")

        self.triggerValueLabel.font = .monospacedSystemFont(ofSize: 13, weight: .semibold)
        self.triggerValueLabel.textColor = .labelColor
        self.triggerValueLabel.alignment = .right

        self.recordButton.controlSize = .regular
        self.recordButton.bezelStyle = .rounded

        self.modeControl.controlSize = .regular

        let keyRow = self.makeSettingRow(symbol: "keyboard",
                                         title: "触发按键",
                                         trailing: [self.triggerValueLabel, self.recordButton])
        let modeRow = self.makeSettingRow(symbol: "hand.tap",
                                          title: "触发模式",
                                          trailing: [self.modeControl])

        self.triggerHintLabel.stringValue = "普通按键会被全局拦截，不再传给当前应用；⌘⌥⌃⇧ 等修饰键不会被拦截，仍可正常组合使用，建议配合「按住连点」。"
        self.triggerHintLabel.font = .systemFont(ofSize: 11)
        self.triggerHintLabel.textColor = .tertiaryLabelColor
        self.configureWrapping(self.triggerHintLabel)

        return self.makeCard(rows: [keyRow, modeRow])
    }

    private func makeClickCard() -> NSView {
        // 点击频率
        self.cpsValueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        self.cpsValueLabel.textColor = .secondaryLabelColor
        self.cpsSubtitleLabel.font = .systemFont(ofSize: 11)
        self.cpsSubtitleLabel.textColor = .secondaryLabelColor
        self.cpsSlider.setContentHuggingPriority(.init(1), for: .horizontal)

        let cpsRow = self.makeSettingRow(symbol: "speedometer",
                                         title: "点击频率",
                                         subtitleLabel: self.cpsSubtitleLabel,
                                         trailing: [self.cpsValueLabel])
        let cpsBlock = self.wrapSlider(self.cpsSlider, header: cpsRow)

        // 拟人化
        self.humanizeSwitch.controlSize = .regular
        self.humanizeSwitch.setAccessibilityLabel("拟人化随机节奏")
        self.cpsSlider.setAccessibilityLabel("点击频率")
        self.jitterSlider.setAccessibilityLabel("间隔随机幅度")
        let humanizeRow = self.makeSettingRow(symbol: "wand.and.stars",
                                              title: "拟人化随机节奏",
                                              subtitle: "间隔抖动 · 按压时长随机 · 偶发停顿",
                                              trailing: [self.humanizeSwitch])

        // 间隔随机幅度
        self.jitterValueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        self.jitterValueLabel.textColor = .secondaryLabelColor
        self.jitterSlider.setContentHuggingPriority(.init(1), for: .horizontal)

        let jitterRow = self.makeSettingRow(symbol: "slider.horizontal.3",
                                            title: "间隔随机幅度",
                                            trailing: [self.jitterValueLabel])
        let jitterBlock = self.wrapSlider(self.jitterSlider, header: jitterRow)
        self.jitterBlockView = jitterBlock

        // 坐标抖动
        self.cursorJitterSwitch.controlSize = .regular
        self.cursorJitterSwitch.setAccessibilityLabel("点击坐标微抖动")
        let cursorRow = self.makeSettingRow(symbol: "cursorarrow",
                                            title: "点击坐标微抖动",
                                            subtitle: "每次落点偏移 ±1.2 像素",
                                            trailing: [self.cursorJitterSwitch])

        return self.makeCard(rows: [cpsBlock, humanizeRow, jitterBlock, cursorRow])
    }

    private func makeGeneralCard() -> NSView {
        self.themeControl.controlSize = .regular
        self.themeControl.setAccessibilityLabel("外观主题")

        let themeRow = self.makeSettingRow(symbol: "circle.lefthalf.filled",
                                           title: "主题",
                                           subtitle: "浅色、深色或跟随系统外观",
                                           trailing: [self.themeControl])

        self.launchAtLoginSwitch.controlSize = .regular
        self.launchAtLoginSwitch.setAccessibilityLabel("开机自启动")
        self.launchAtLoginSubtitle.font = .systemFont(ofSize: 11)
        self.launchAtLoginSubtitle.textColor = .secondaryLabelColor

        let loginRow = self.makeSettingRow(symbol: "power",
                                           title: "开机自启动",
                                           subtitleLabel: self.launchAtLoginSubtitle,
                                           trailing: [self.launchAtLoginSwitch])

        self.updateSubtitleLabel.font = .systemFont(ofSize: 11)
        self.updateSubtitleLabel.textColor = .secondaryLabelColor
        self.updateSubtitleLabel.stringValue = "当前版本 \(UpdateService.shared.currentVersion)"
        self.updateButton.controlSize = .regular
        self.updateButton.bezelStyle = .rounded

        let updateRow = self.makeSettingRow(symbol: "arrow.triangle.2.circlepath",
                                            title: "软件更新",
                                            subtitleLabel: self.updateSubtitleLabel,
                                            trailing: [self.updateButton])

        return self.makeCard(rows: [themeRow, loginRow, updateRow])
    }

    private func makeStatusCard() -> NSView {
        self.statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        self.statusLabel.textColor = .labelColor

        self.countLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        self.countLabel.textColor = .secondaryLabelColor

        let topRow = NSStackView(views: [self.statusDot,
                                         self.statusLabel,
                                         self.makeSpacer(),
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
            topRow.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Self.cardInset),
            topRow.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Self.cardInset),
            topRow.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),

            self.toggleButton.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Self.cardInset),
            self.toggleButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Self.cardInset),
            self.toggleButton.topAnchor.constraint(equalTo: topRow.bottomAnchor, constant: 10),
            self.toggleButton.heightAnchor.constraint(equalToConstant: 32),
            self.toggleButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ])
        return card
    }

    private func makeFooter() -> NSView {
        self.footerLabel.stringValue = "仅供个人自动化与单机场景使用。全局事件注入无法保证绕过专业反作弊系统，在联网游戏中使用可能违反服务条款并导致封号，请自行评估风险。"
        self.footerLabel.font = .systemFont(ofSize: 11)
        self.footerLabel.textColor = .tertiaryLabelColor
        self.configureWrapping(self.footerLabel)
        return self.footerLabel
    }

    // MARK: - 布局辅助

    /// 分组卡片：行之间插入分隔线
    private func makeCard(rows: [NSView]) -> NSView {
        let card = CardView()
        card.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        for (index, row) in rows.enumerated() {
            if index > 0 {
                let separator = SeparatorView()
                separator.translatesAutoresizingMaskIntoConstraints = false
                stack.addArrangedSubview(separator)
                separator.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
                separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
            }
            stack.addArrangedSubview(row)
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor)
        ])
        return card
    }

    /// 分组：小标题 + 卡片 + 可选脚注
    private func makeSection(title: String, card: NSView, footnote: NSTextField?) -> NSView {
        let header = NSTextField(labelWithString: title)
        header.font = .systemFont(ofSize: 11, weight: .semibold)
        header.textColor = .secondaryLabelColor
        header.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(header)
        container.addSubview(card)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
            header.topAnchor.constraint(equalTo: container.topAnchor),
            card.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            card.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6)
        ])

        if let footnote = footnote {
            // 手动添加的视图必须关闭 autoresizing 约束，否则会被压成 0 宽度
            footnote.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(footnote)
            NSLayoutConstraint.activate([
                footnote.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
                footnote.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -2),
                footnote.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 6),
                footnote.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        } else {
            card.bottomAnchor.constraint(equalTo: container.bottomAnchor).isActive = true
        }
        return container
    }

    /// 一行设置项：左侧图标 + 标题/副标题，右侧控件
    private func makeSettingRow(symbol: String,
                                title: String,
                                subtitle: String? = nil,
                                subtitleLabel: NSTextField? = nil,
                                trailing: [NSView]) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = .labelColor

        var titleViews: [NSView] = [titleLabel]
        if let subtitle = subtitle {
            let label = NSTextField(labelWithString: subtitle)
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            label.lineBreakMode = .byTruncatingTail
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            titleViews.append(label)
        } else if let subtitleLabel = subtitleLabel {
            titleViews.append(subtitleLabel)
        }

        let titles = NSStackView(views: titleViews)
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 2

        var leading: [NSView] = []
        if let icon = self.makeRowIcon(symbol) {
            leading.append(icon)
        }

        let row = NSStackView(views: leading + [titles, self.makeSpacer()] + trailing)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.cardInset),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.cardInset),
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: 9),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -9)
        ])
        return container
    }

    /// 标题行 + 整行滑块
    private func wrapSlider(_ slider: NSSlider, header: NSView) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        slider.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(header)
        container.addSubview(slider)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            header.topAnchor.constraint(equalTo: container.topAnchor),

            slider.leadingAnchor.constraint(equalTo: container.leadingAnchor,
                                            constant: Self.cardInset + Self.iconWidth + 8),
            slider.trailingAnchor.constraint(equalTo: container.trailingAnchor,
                                             constant: -Self.cardInset),
            slider.topAnchor.constraint(equalTo: header.bottomAnchor, constant: -4),
            slider.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10)
        ])
        return container
    }

    private func makeRowIcon(_ symbolName: String) -> NSImageView? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else {
            return nil
        }
        let imageView = NSImageView(image: image)
        imageView.contentTintColor = .secondaryLabelColor
        imageView.setAccessibilityElement(false)  // 装饰性图标，不参与朗读
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.widthAnchor.constraint(equalToConstant: Self.iconWidth).isActive = true
        return imageView
    }

    private func makeSpacer() -> NSView {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        return spacer
    }

    private func configureWrapping(_ label: NSTextField) {
        label.usesSingleLineMode = false
        label.cell?.wraps = true
        label.cell?.isScrollable = false
        label.maximumNumberOfLines = 0
        label.preferredMaxLayoutWidth = Self.windowWidth - Self.contentInset * 2
    }

    private func addFullWidth(_ child: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(child)
        child.translatesAutoresizingMaskIntoConstraints = false
        child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    // MARK: - 事件绑定

    private func bindActions() {
        self.permissionButton.target = self
        self.permissionButton.action = #selector(self.openPermissionSettings)

        self.recordButton.target = self
        self.recordButton.action = #selector(self.toggleKeyRecording)

        self.modeControl.target = self
        self.modeControl.action = #selector(self.modeChanged)

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

        self.themeControl.target = self
        self.themeControl.action = #selector(self.themeChanged)

        self.launchAtLoginSwitch.target = self
        self.launchAtLoginSwitch.action = #selector(self.launchAtLoginChanged)

        self.updateButton.target = self
        self.updateButton.action = #selector(self.updateButtonClicked)

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
        self.monitor.onKeyCaptured = { [weak self] code in
            self?.keyCaptured(code)
        }
    }

    // MARK: - 用户操作

    @objc private func openPermissionSettings(_ sender: Any) {
        self.requestPermissionPrompt()

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
            self.triggerHintLabel.textColor = .systemOrange
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
        self.refreshRuntime()
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

    @objc private func themeChanged(_ sender: Any) {
        guard !self.isSyncingUI else { return }
        let theme: Theme
        switch self.themeControl.selectedSegment {
        case 0:
            theme = .light
        case 1:
            theme = .dark
        default:
            theme = .system
        }
        self.settings.update { $0.theme = theme }
        theme.apply()
    }

    @objc private func launchAtLoginChanged(_ sender: Any) {
        guard !self.isSyncingUI else { return }

        let enabled = self.launchAtLoginSwitch.state == .on
        do {
            try LaunchAtLogin.set(enabled)
        } catch {
            NSSound.beep()
            self.launchAtLoginSubtitle.stringValue = "设置失败：\(error.localizedDescription)"
            self.launchAtLoginSubtitle.textColor = .systemRed
        }
        self.refreshLaunchAtLogin()
    }

    @objc private func updateButtonClicked(_ sender: Any) {
        guard !self.isCheckingUpdate else { return }
        if let update = self.availableUpdate {
            self.installUpdate(update)
        } else {
            self.checkForUpdates()
        }
    }

    /// 检查更新（启动时静默调用，也可由按钮触发）
    private func checkForUpdates() {
        guard !self.isCheckingUpdate else { return }
        self.isCheckingUpdate = true
        self.updateButton.isEnabled = false
        self.updateButton.title = "检查中…"
        self.updateSubtitleLabel.textColor = .secondaryLabelColor
        self.updateSubtitleLabel.stringValue = "正在检查更新…"

        UpdateService.shared.check { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isCheckingUpdate = false
                self.updateButton.isEnabled = true

                switch result {
                case .success(let info):
                    if let info = info {
                        self.availableUpdate = info
                        self.updateSubtitleLabel.stringValue = "发现新版本 \(info.tag)（当前 \(UpdateService.shared.currentVersion)）"
                        self.updateSubtitleLabel.textColor = .systemOrange
                        self.updateButton.title = "更新到 \(info.tag)"
                        self.updateButton.bezelColor = .controlAccentColor
                    } else {
                        self.availableUpdate = nil
                        self.updateSubtitleLabel.stringValue = "已是最新版本（\(UpdateService.shared.currentVersion)）"
                        self.updateSubtitleLabel.textColor = .secondaryLabelColor
                        self.updateButton.title = "检查更新"
                        self.updateButton.bezelColor = nil
                    }

                case .failure(let error):
                    self.availableUpdate = nil
                    self.updateSubtitleLabel.stringValue = "检查失败：\(error.localizedDescription)"
                    self.updateSubtitleLabel.textColor = .systemRed
                    self.updateButton.title = "重试"
                    self.updateButton.bezelColor = nil
                }
            }
        }
    }

    /// 下载并安装更新
    private func installUpdate(_ info: UpdateInfo) {
        guard !self.isCheckingUpdate else { return }
        self.isCheckingUpdate = true
        self.updateButton.isEnabled = false
        self.updateButton.title = "更新中…"
        self.updateSubtitleLabel.textColor = .secondaryLabelColor
        self.updateSubtitleLabel.stringValue = "正在下载 \(info.tag)…"

        UpdateService.shared.downloadAndInstall(info, progress: { [weak self] message in
            DispatchQueue.main.async {
                self?.updateSubtitleLabel.stringValue = message
            }
        }, completion: { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if case .failure(let error) = result {
                    self.isCheckingUpdate = false
                    self.updateButton.isEnabled = true
                    self.updateButton.title = "重试"
                    self.updateButton.bezelColor = nil
                    self.updateSubtitleLabel.stringValue = "更新失败：\(error.localizedDescription)"
                    self.updateSubtitleLabel.textColor = .systemRed
                }
            }
        })
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
        guard !self.isRecordingKey else { return }

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
        guard !self.isRecordingKey else { return }
        if self.settings.current.holdToClick {
            self.engine.stop()
            self.refreshRuntime()
        }
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
        self.triggerHintLabel.stringValue = "普通按键会被全局拦截，不再传给当前应用；⌘⌥⌃⇧ 等修饰键不会被拦截，仍可正常组合使用，建议配合「按住连点」。"
        self.triggerHintLabel.textColor = .tertiaryLabelColor
        self.refreshTriggerDisplay()
        self.refreshRuntime()
    }

    // MARK: - 界面刷新

    private func refreshFromSettings() {
        self.isSyncingUI = true
        defer { self.isSyncingUI = false }

        let config = self.settings.current
        self.selectMode(hold: config.holdToClick)
        self.cpsSlider.doubleValue = config.clicksPerSecond
        self.humanizeSwitch.state = config.humanize ? .on : .off
        self.jitterSlider.doubleValue = config.jitterPercent
        self.cursorJitterSwitch.state = config.cursorJitter ? .on : .off
        self.selectTheme(config.theme)
        self.refreshLaunchAtLogin()
        self.refreshDerivedLabels()
    }

    private func selectMode(hold: Bool) {
        let index = hold ? 0 : 1
        self.modeControl.selectedSegment = index
        for segment in 0..<self.modeControl.segmentCount {
            self.modeControl.setSelected(segment == index, forSegment: segment)
        }
    }

    private func selectTheme(_ theme: Theme) {
        let index: Int
        switch theme {
        case .light:
            index = 0
        case .dark:
            index = 1
        case .system:
            index = 2
        }
        self.themeControl.selectedSegment = index
        for segment in 0..<self.themeControl.segmentCount {
            self.themeControl.setSelected(segment == index, forSegment: segment)
        }
    }

    private func refreshLaunchAtLogin() {
        let status = LaunchAtLogin.status
        self.launchAtLoginSwitch.state = (status == .enabled) ? .on : .off

        switch status {
        case .enabled:
            self.launchAtLoginSubtitle.stringValue = "登录后自动打开"
            self.launchAtLoginSubtitle.textColor = .secondaryLabelColor
        case .requiresApproval:
            self.launchAtLoginSubtitle.stringValue = "需在「系统设置 → 通用 → 登录项」中允许"
            self.launchAtLoginSubtitle.textColor = .systemOrange
        case .notRegistered, .notFound:
            self.launchAtLoginSubtitle.stringValue = "登录后不会自动打开"
            self.launchAtLoginSubtitle.textColor = .secondaryLabelColor
        @unknown default:
            self.launchAtLoginSubtitle.stringValue = "登录后自动打开"
            self.launchAtLoginSubtitle.textColor = .secondaryLabelColor
        }
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

    private func refreshTriggerDisplay() {
        if self.isRecordingKey {
            self.triggerValueLabel.stringValue = "请按键…（Esc 取消）"
            self.triggerValueLabel.textColor = .systemOrange
            self.recordButton.title = "取消"
        } else {
            self.triggerValueLabel.stringValue = KeyNames.name(for: self.settings.current.triggerKeyCode)
            self.triggerValueLabel.textColor = .labelColor
            self.recordButton.title = "重新设置"
        }
    }

    private func refreshPermission() {
        let trusted = AXIsProcessTrusted()

        if trusted {
            self.permissionBadge.symbolName = "checkmark.shield.fill"
            self.permissionBadge.tint = .systemGreen
            self.permissionSubtitleLabel.stringValue = "已授权，可以开始连点"
            self.permissionSubtitleLabel.textColor = .secondaryLabelColor
            self.permissionButton.isHidden = true
            self.permissionHintLabel.isHidden = true
            self.settings.rememberAuthorized()
            if !self.monitor.isActive {
                _ = self.monitor.start()
            }
        } else {
            self.permissionBadge.symbolName = "exclamationmark.shield.fill"
            self.permissionBadge.tint = .systemOrange
            self.permissionSubtitleLabel.stringValue = "未授权：无法拦截按键和模拟点击"
            self.permissionSubtitleLabel.textColor = .systemOrange
            self.permissionButton.isHidden = false
            self.permissionHintLabel.isHidden = false

            if self.settings.hasBeenAuthorized {
                // 曾经授权成功过：多半是重新编译导致签名变化，系统授权失效
                self.permissionHintLabel.stringValue = "系统授权已失效（重新编译后常见）。请在「系统设置 → 隐私与安全性 → 辅助功能」中取消勾选 RapidTap，再重新勾选。"
            } else {
                self.permissionHintLabel.stringValue = "在「系统设置 → 隐私与安全性 → 辅助功能」中勾选 RapidTap；若列表中没有，点 + 手动添加本应用。"
            }
        }
    }

    /// 首次启动且未授权时主动唤起系统授权弹窗，让应用出现在"辅助功能"列表中
    private func promptPermissionIfNeeded() {
        guard !self.promptedPermission, !AXIsProcessTrusted() else { return }
        self.promptedPermission = true
        self.requestPermissionPrompt()
    }

    private func requestPermissionPrompt() {
        // 用字面量键触发系统授权弹窗，避免不同 SDK 对 CFString 全局量的桥接差异
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
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
}
