import Cocoa

// MARK: - 视觉组件

/// 圆角卡片：系统设置风格的分组容器
final class CardView: NSView {

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

/// 1 像素分隔线，左侧缩进与文字对齐
final class SeparatorView: NSView {

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
final class SymbolBadgeView: NSView {

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
final class StatusDotView: NSView {

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

/// 面板背景：sheet 的窗口背景不易覆盖，直接自绘
final class PanelBackgroundView: NSView {

    override func draw(_ dirtyRect: NSRect) {
        NSColor.underPageBackgroundColor.setFill()
        self.bounds.fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        self.needsDisplay = true
    }
}

// MARK: - 布局工具

enum UIConstants {
    static let windowWidth: CGFloat = 520
    static let contentInset: CGFloat = 24
    static let cardInset: CGFloat = 14
    static let iconWidth: CGFloat = 16
}

/// 两个界面共用的布局构造器
enum UIBuilder {

    /// 分组卡片：行之间插入分隔线
    static func makeCard(rows: [NSView]) -> NSView {
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
    static func makeSection(title: String, card: NSView, footnote: NSTextField?) -> NSView {
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
    static func makeSettingRow(symbol: String,
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
        if let icon = makeRowIcon(symbol) {
            leading.append(icon)
        }

        let row = NSStackView(views: leading + [titles, makeSpacer()] + trailing)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: UIConstants.cardInset),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -UIConstants.cardInset),
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: 9),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -9)
        ])
        return container
    }

    /// 标题行 + 整行滑块
    static func makeSliderBlock(slider: NSSlider, header: NSView) -> NSView {
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
                                            constant: UIConstants.cardInset + UIConstants.iconWidth + 8),
            slider.trailingAnchor.constraint(equalTo: container.trailingAnchor,
                                             constant: -UIConstants.cardInset),
            slider.topAnchor.constraint(equalTo: header.bottomAnchor, constant: -4),
            slider.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10)
        ])
        return container
    }

    static func makeSpacer() -> NSView {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        return spacer
    }

    static func makeRowIcon(_ symbolName: String) -> NSImageView? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else {
            return nil
        }
        let imageView = NSImageView(image: image)
        imageView.contentTintColor = .secondaryLabelColor
        imageView.setAccessibilityElement(false)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.widthAnchor.constraint(equalToConstant: UIConstants.iconWidth).isActive = true
        return imageView
    }

    static func configureWrapping(_ label: NSTextField, width: CGFloat) {
        label.usesSingleLineMode = false
        label.cell?.wraps = true
        label.cell?.isScrollable = false
        label.maximumNumberOfLines = 0
        label.preferredMaxLayoutWidth = width
    }

    static func addFullWidth(_ child: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(child)
        child.translatesAutoresizingMaskIntoConstraints = false
        child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    /// 内容根栈：垂直、左对齐、固定左边距
    static func makeContentStack(insets: NSEdgeInsets, spacing: CGFloat) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }
}
