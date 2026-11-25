import Cocoa
import CoreText

// MARK: - 主题（取自 animal-island-ui design tokens）

enum Island {

    // 背景 / 卡片
    static let bg = NSColor(hex: 0xF8F8F0)
    static let card = NSColor(hex: 0xF7F3DF)
    static let cardDashed = NSColor(hex: 0xFAF8F2)

    // 文字（暖棕）
    static let text = NSColor(hex: 0x794F27)
    static let bodyText = NSColor(hex: 0x725D42)
    static let secondaryText = NSColor(hex: 0x9F927D)
    static let mutedText = NSColor(hex: 0x8A7B66)

    // 边框
    static let border = NSColor(hex: 0x9F927D)
    static let borderLight = NSColor(hex: 0xC4B89E)
    static let borderDashed = NSColor(hex: 0xE8DCC8)

    // 主色与状态色
    static let primary = NSColor(hex: 0x19C8B9)
    static let primaryActive = NSColor(hex: 0x11A89B)
    static let primaryBg = NSColor(hex: 0xE6F9F6)
    static let success = NSColor(hex: 0x6FBA2C)
    static let successBg = NSColor(hex: 0x86D67A)
    static let warning = NSColor(hex: 0xF5C31C)
    static let warningText = NSColor(hex: 0xB26A00)
    static let error = NSColor(hex: 0xE05A5A)

    // 控件底色
    static let track = NSColor(hex: 0xF0E8D8)
    static let switchOffBg = NSColor(hex: 0xD4C9B4)
    static let shadow3D = NSColor(hex: 0xBDAEA0)
    static let shadow = NSColor(srgbRed: 61.0 / 255, green: 52.0 / 255, blue: 40.0 / 255, alpha: 0.10)

    // 圆角
    static let radiusCard: CGFloat = 20
    static let radiusSmall: CGFloat = 16
    static let radiusLarge: CGFloat = 24

    /// 主题字体：Nunito（拉丁）+ 系统字体（中文兜底）
    static func font(_ size: CGFloat, _ weight: CGFloat = 500) -> NSFont {
        return IslandFont.font(size, weight)
    }

    static func mono(_ size: CGFloat, _ weight: CGFloat = 600) -> NSFont {
        return IslandFont.mono(size, weight)
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
                  green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                  blue: CGFloat(hex & 0xFF) / 255.0,
                  alpha: 1.0)
    }
}

/// 字体加载：优先内置 Nunito 可变字体，失败时回退到系统圆体
enum IslandFont {

    private static var registered = false

    static func registerBundledFonts() {
        guard !registered else { return }
        registered = true
        guard let url = Bundle.main.url(forResource: "Nunito", withExtension: "ttf", subdirectory: "Fonts") else {
            return
        }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    static func font(_ size: CGFloat, _ weight: CGFloat) -> NSFont {
        let variation: [NSNumber: NSNumber] = [
            NSNumber(value: 0x77676874): NSNumber(value: weight)  // 'wght'
        ]
        let descriptor = NSFontDescriptor(fontAttributes: [
            .name: "Nunito",
            .variation: variation
        ])
        if let font = NSFont(descriptor: descriptor, size: size) {
            return font
        }
        return systemRounded(size, weight)
    }

    static func mono(_ size: CGFloat, _ weight: CGFloat) -> NSFont {
        return NSFont.monospacedDigitSystemFont(ofSize: size, weight: systemWeight(weight))
    }

    private static func systemRounded(_ size: CGFloat, _ weight: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: systemWeight(weight))
        if let descriptor = base.fontDescriptor.withDesign(.rounded),
           let rounded = NSFont(descriptor: descriptor, size: size) {
            return rounded
        }
        return base
    }

    private static func systemWeight(_ weight: CGFloat) -> NSFont.Weight {
        switch weight {
        case ..<450: return .regular
        case ..<550: return .medium
        case ..<650: return .semibold
        case ..<750: return .bold
        default: return .heavy
        }
    }
}

// MARK: - 卡片 / 分隔线 / 徽章

/// 岛屿卡片：20pt 圆角、奶油底、柔和暖棕阴影
final class IslandCardView: NSView {

    var dashed = false {
        didSet { self.needsDisplay = true }
    }

    override var isOpaque: Bool { return false }

    override func draw(_ dirtyRect: NSRect) {
        let rect = self.bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: Island.radiusCard, yRadius: Island.radiusCard)

        if self.dashed {
            Island.cardDashed.setFill()
            path.fill()
            Island.borderDashed.setStroke()
            path.lineWidth = 2
            path.setLineDash([6, 4], count: 2, phase: 0)
            path.stroke()
            return
        }

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = Island.shadow
        shadow.shadowBlurRadius = 8
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.set()
        Island.card.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// 虚线分隔线（2px，12px 周期）
final class IslandSeparatorView: NSView {

    var leadingInset: CGFloat = 16

    override var isOpaque: Bool { return false }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: NSView.noIntrinsicMetric, height: 10)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: self.leadingInset, y: self.bounds.midY))
        path.line(to: NSPoint(x: self.bounds.width - self.leadingInset, y: self.bounds.midY))
        path.lineWidth = 2
        path.setLineDash([6, 6], count: 2, phase: 0)
        Island.borderLight.setStroke()
        path.stroke()
    }
}

/// 圆形图标徽章：淡色底 + 2px 描边
final class IslandSymbolBadgeView: NSView {

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
            self.imageView.image = IslandSymbolBadgeView.makeImage(self.symbolName, side: self.side)
        }
    }

    init(symbolName: String, tint: NSColor, side: CGFloat) {
        self.side = side
        self.tint = tint
        self.symbolName = symbolName
        super.init(frame: .zero)

        self.translatesAutoresizingMaskIntoConstraints = false
        self.imageView.image = IslandSymbolBadgeView.makeImage(symbolName, side: side)
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
            self.imageView.widthAnchor.constraint(equalToConstant: side * 0.5),
            self.imageView.heightAnchor.constraint(equalToConstant: side * 0.5)
        ])
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(ovalIn: self.bounds.insetBy(dx: 1, dy: 1))
        self.tint.withAlphaComponent(0.16).setFill()
        path.fill()
        self.tint.withAlphaComponent(0.55).setStroke()
        path.lineWidth = 2
        path.stroke()
    }

    private static func makeImage(_ symbolName: String, side: CGFloat) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: side * 0.46, weight: .bold)
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }
}

/// 状态圆点
final class IslandStatusDotView: NSView {

    var color: NSColor = Island.secondaryText {
        didSet { self.needsDisplay = true }
    }

    override var isOpaque: Bool { return false }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: 10, height: 10)
    }

    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: self.bounds.insetBy(dx: 1, dy: 1))
        self.color.withAlphaComponent(0.25).setFill()
        circle.fill()
        self.color.setStroke()
        circle.lineWidth = 2
        circle.stroke()
    }
}

/// sheet 背景
final class IslandPanelBackgroundView: NSView {

    override func draw(_ dirtyRect: NSRect) {
        Island.bg.setFill()
        self.bounds.fill()
    }
}

// MARK: - 自绘控件

/// 岛屿风开关：52×28、2.5px 双描边、圆形滑块
final class IslandSwitch: NSView {

    var state: NSControl.StateValue = .off {
        didSet {
            self.needsDisplay = true
            self.setAccessibilityValue(self.state == .on ? 1 : 0)
        }
    }

    var isEnabled: Bool = true {
        didSet { self.needsDisplay = true }
    }

    /// 兼容 NSButton/NSSwitch 调用点（尺寸固定，此处仅占位）
    var controlSize: NSControl.ControlSize = .regular

    var target: AnyObject?
    var action: Selector?

    override var intrinsicContentSize: NSSize {
        return NSSize(width: 52, height: 28)
    }

    override var acceptsFirstResponder: Bool { return true }

    override func draw(_ dirtyRect: NSRect) {
        let on = self.state == .on
        let track = self.bounds.insetBy(dx: 1.25, dy: 1.25)
        let path = NSBezierPath(roundedRect: track, xRadius: track.height / 2, yRadius: track.height / 2)
        (on ? Island.successBg : Island.switchOffBg).setFill()
        path.fill()
        (on ? Island.success : Island.borderLight).setStroke()
        path.lineWidth = 2.5
        path.stroke()

        let knobSize: CGFloat = 21
        let knobX = on ? (self.bounds.width - 2 - knobSize) : 2
        let knobRect = NSRect(x: knobX, y: (self.bounds.height - knobSize) / 2,
                              width: knobSize, height: knobSize)
        let knob = NSBezierPath(ovalIn: knobRect.insetBy(dx: 1.25, dy: 1.25))
        Island.card.setFill()
        knob.fill()
        (on ? Island.success : Island.borderLight).setStroke()
        knob.lineWidth = 2.5
        knob.stroke()

        if !self.isEnabled {
            Island.bg.withAlphaComponent(0.5).setFill()
            path.fill()
        }
    }

    override func accessibilityPerformPress() -> Bool {
        guard self.isEnabled else { return false }
        self.state = (self.state == .on) ? .off : .on
        if let action = self.action {
            NSApp.sendAction(action, to: self.target, from: self)
        }
        return true
    }

    override func mouseDown(with event: NSEvent) {
        guard self.isEnabled else { return }
        self.state = (self.state == .on) ? .off : .on
        if let action = self.action {
            NSApp.sendAction(action, to: self.target, from: self)
        }
    }
}

/// 岛屿风滑块：圆角轨道 + 奶油圆钮
final class IslandSlider: NSView {

    var minValue: Double = 0
    var maxValue: Double = 1
    var doubleValue: Double = 0 {
        didSet {
            let clamped = min(max(self.doubleValue, self.minValue), self.maxValue)
            if clamped != self.doubleValue {
                self.doubleValue = clamped
                return
            }
            self.needsDisplay = true
            self.setAccessibilityValue(self.doubleValue)
        }
    }

    var isContinuous: Bool = true
    var isEnabled: Bool = true {
        didSet { self.needsDisplay = true }
    }

    var target: AnyObject?
    var action: Selector?

    private let trackHeight: CGFloat = 10
    private let knobSize: CGFloat = 22

    convenience init(value: Double, minValue: Double, maxValue: Double,
                     target: AnyObject?, action: Selector?) {
        self.init(frame: .zero)
        self.minValue = minValue
        self.maxValue = maxValue
        self.doubleValue = value
        self.target = target
        self.action = action
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.translatesAutoresizingMaskIntoConstraints = false
        self.setAccessibilityElement(true)
        self.setAccessibilityRole(.slider)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: 220, height: 28)
    }

    override func draw(_ dirtyRect: NSRect) {
        let trackRect = NSRect(x: 0, y: (self.bounds.height - self.trackHeight) / 2,
                               width: self.bounds.width, height: self.trackHeight)
        let track = NSBezierPath(roundedRect: trackRect.insetBy(dx: 1, dy: 1),
                                 xRadius: self.trackHeight / 2,
                                 yRadius: self.trackHeight / 2)
        Island.track.setFill()
        track.fill()
        Island.borderLight.setStroke()
        track.lineWidth = 2
        track.stroke()

        let progress = (self.doubleValue - self.minValue) / max(0.0001, self.maxValue - self.minValue)
        let knobCenter = self.knobSize / 2 + CGFloat(progress) * (self.bounds.width - self.knobSize)
        if progress > 0.001 {
            let fillRect = NSRect(x: 1, y: trackRect.minY + 1,
                                  width: max(0, knobCenter - 1), height: self.trackHeight - 2)
            let fill = NSBezierPath(roundedRect: fillRect,
                                    xRadius: (self.trackHeight - 2) / 2,
                                    yRadius: (self.trackHeight - 2) / 2)
            Island.primary.withAlphaComponent(self.isEnabled ? 1 : 0.4).setFill()
            fill.fill()
        }

        let knobRect = NSRect(x: knobCenter - self.knobSize / 2,
                              y: (self.bounds.height - self.knobSize) / 2,
                              width: self.knobSize, height: self.knobSize)
        let knob = NSBezierPath(ovalIn: knobRect.insetBy(dx: 0.5, dy: 0.5))
        Island.card.setFill()
        knob.fill()
        Island.border.setStroke()
        knob.lineWidth = 2.5
        knob.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        guard self.isEnabled else { return }
        self.updateValue(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard self.isEnabled else { return }
        self.updateValue(with: event)
    }

    private func updateValue(with event: NSEvent) {
        let point = self.convert(event.locationInWindow, from: nil)
        let usable = max(1, self.bounds.width - self.knobSize)
        let ratio = min(max(0, (point.x - self.knobSize / 2) / usable), 1)
        self.doubleValue = self.minValue + Double(ratio) * (self.maxValue - self.minValue)
        if let action = self.action {
            NSApp.sendAction(action, to: self.target, from: self)
        }
    }
}

/// 岛屿风按钮：胶囊形 + 2px 描边；primary 带 5px 立体底影
final class IslandButton: NSView {

    enum Style {
        case primary
        case secondary
    }

    var title: String {
        didSet {
            self.invalidateIntrinsicContentSize()
            self.needsDisplay = true
            self.setAccessibilityLabel(self.title)
        }
    }

    var image: NSImage? {
        didSet { self.invalidateIntrinsicContentSize(); self.needsDisplay = true }
    }

    var style: Style = .secondary {
        didSet { self.needsDisplay = true }
    }

    var isEnabled: Bool = true {
        didSet { self.needsDisplay = true }
    }

    var target: AnyObject?
    var action: Selector?

    // 兼容 NSButton 调用点
    var controlSize: NSControl.ControlSize = .regular {
        didSet { self.invalidateIntrinsicContentSize(); self.needsDisplay = true }
    }
    var bezelStyle: NSButton.BezelStyle = .rounded
    var bezelColor: NSColor?
    var imagePosition: NSControl.ImagePosition = .imageLeading
    var symbolConfiguration: NSImage.SymbolConfiguration?
    var keyEquivalent: String = ""

    private var isPressed = false

    convenience init(title: String, target: AnyObject? = nil, action: Selector? = nil) {
        self.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
    }

    override init(frame frameRect: NSRect) {
        self.title = ""
        super.init(frame: frameRect)
        self.translatesAutoresizingMaskIntoConstraints = false
        self.setAccessibilityElement(true)
        self.setAccessibilityRole(.button)
        self.setAccessibilityLabel(self.title)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    private var height: CGFloat {
        switch self.controlSize {
        case .small: return 30
        case .large: return 42
        default: return 34
        }
    }

    private var fontSize: CGFloat {
        switch self.controlSize {
        case .small: return 11.5
        case .large: return 14
        default: return 12.5
        }
    }

    override var intrinsicContentSize: NSSize {
        let font = Island.font(self.fontSize, 700)
        let textWidth = (self.title as NSString).size(withAttributes: [.font: font]).width
        var width = textWidth + 32
        if self.image != nil { width += 20 }
        return NSSize(width: max(width, self.height * 1.8), height: self.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let inset: CGFloat = self.style == .primary ? 1.5 : 1
        let rect = self.bounds.insetBy(dx: inset, dy: inset)

        if self.style == .primary {
            // 立体底影（模拟 box-shadow: 0 5px 0 #bdaea0），底部预留 6pt 避免被裁切
            let baseHeight: CGFloat = 6
            let mainRect = NSRect(x: 1.5, y: baseHeight,
                                  width: self.bounds.width - 3,
                                  height: self.bounds.height - baseHeight - 1.5)
            let baseRect = mainRect.offsetBy(dx: 0, dy: -5)
            let base = NSBezierPath(roundedRect: baseRect, xRadius: baseRect.height / 2, yRadius: baseRect.height / 2)
            Island.shadow3D.setFill()
            base.fill()

            let drawnRect = self.isPressed ? mainRect.offsetBy(dx: 0, dy: -3) : mainRect
            let main = NSBezierPath(roundedRect: drawnRect, xRadius: drawnRect.height / 2, yRadius: drawnRect.height / 2)
            Island.bg.setFill()
            main.fill()
            self.drawContent(in: drawnRect)
        } else {
            let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
            Island.bg.setFill()
            path.fill()
            Island.border.setStroke()
            path.lineWidth = 2
            path.stroke()
            self.drawContent(in: rect)
        }

        if !self.isEnabled {
            Island.bg.withAlphaComponent(0.55).setFill()
            NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
        }
    }

    private func drawContent(in rect: NSRect) {
        let font = Island.font(self.fontSize, 700)
        let color = self.isEnabled ? Island.text : Island.secondaryText
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .kern: 0.2
        ]
        let textSize = (self.title as NSString).size(withAttributes: attributes)
        let iconWidth: CGFloat = self.image == nil ? 0 : 16
        let gap: CGFloat = self.image == nil ? 0 : 6
        let totalWidth = textSize.width + iconWidth + gap
        var x = rect.midX - totalWidth / 2
        let y = rect.midY - textSize.height / 2

        if let image = self.image {
            let tinted = image.tinted(with: color)
            tinted.draw(in: NSRect(x: x, y: rect.midY - 8, width: 16, height: 16))
            x += iconWidth + gap
        }
        (self.title as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
    }

    override func accessibilityPerformPress() -> Bool {
        guard self.isEnabled else { return false }
        if let action = self.action {
            NSApp.sendAction(action, to: self.target, from: self)
        }
        return true
    }

    override func mouseDown(with event: NSEvent) {
        guard self.isEnabled else { return }
        self.isPressed = true
        self.needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard self.isPressed else { return }
        self.isPressed = false
        self.needsDisplay = true
        let point = self.convert(event.locationInWindow, from: nil)
        if self.bounds.contains(point), let action = self.action {
            NSApp.sendAction(action, to: self.target, from: self)
        }
    }
}

/// 岛屿风分段控件：胶囊容器 + 选中段奶油底
final class IslandSegmented: NSView {

    let labels: [String]
    var selectedSegment: Int = 0 {
        didSet { self.needsDisplay = true }
    }

    var segmentCount: Int { return self.labels.count }
    var controlSize: NSControl.ControlSize = .regular { didSet { self.needsDisplay = true } }
    var target: AnyObject?
    var action: Selector?

    private var segmentRects: [NSRect] = []

    init(labels: [String], trackingMode: NSSegmentedControl.SwitchTracking,
         target: AnyObject?, action: Selector?) {
        self.labels = labels
        self.target = target
        self.action = action
        super.init(frame: .zero)
        self.translatesAutoresizingMaskIntoConstraints = false
        self.setAccessibilityElement(true)
        self.setAccessibilityRole(.radioGroup)
    }

    convenience init(labels: [String], trackingMode: NSSegmentedControl.SwitchTracking) {
        self.init(labels: labels, trackingMode: trackingMode, target: nil, action: nil)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    private var height: CGFloat {
        return self.controlSize == .small ? 28 : 34
    }

    override var intrinsicContentSize: NSSize {
        let font = Island.font(12, 700)
        var width: CGFloat = 12
        for label in self.labels {
            width += (label as NSString).size(withAttributes: [.font: font]).width + 28
        }
        return NSSize(width: width, height: self.height)
    }

    func setSelected(_ selected: Bool, forSegment index: Int) {
        if selected {
            self.selectedSegment = index
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = self.bounds.insetBy(dx: 1, dy: 1)
        let container = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        Island.track.setFill()
        container.fill()

        let padding: CGFloat = 3
        let segmentWidth = (rect.width - padding * 2) / CGFloat(max(1, self.labels.count))
        let font = Island.font(12, 700)

        self.segmentRects = []
        for (index, label) in self.labels.enumerated() {
            let cell = NSRect(x: rect.minX + padding + CGFloat(index) * segmentWidth,
                              y: rect.minY + padding,
                              width: segmentWidth,
                              height: rect.height - padding * 2)
            self.segmentRects.append(cell)

            if index == self.selectedSegment {
                let selected = NSBezierPath(roundedRect: cell, xRadius: cell.height / 2, yRadius: cell.height / 2)
                Island.card.setFill()
                selected.fill()
                Island.border.setStroke()
                selected.lineWidth = 2
                selected.stroke()
            }

            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: index == self.selectedSegment ? Island.text : Island.bodyText,
                .kern: 0.2
            ]
            let size = (label as NSString).size(withAttributes: attributes)
            (label as NSString).draw(at: NSPoint(x: cell.midX - size.width / 2, y: cell.midY - size.height / 2),
                                     withAttributes: attributes)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = self.convert(event.locationInWindow, from: nil)
        for (index, rect) in self.segmentRects.enumerated() where rect.contains(point) {
            self.selectedSegment = index
            if let action = self.action {
                NSApp.sendAction(action, to: self.target, from: self)
            }
            return
        }
    }
}

extension NSImage {
    /// 用指定颜色着色（模板图）
    func tinted(with color: NSColor) -> NSImage {
        let image = self.copy() as! NSImage
        image.lockFocus()
        color.set()
        NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}

// MARK: - 布局工具

enum IslandConstants {
    static let windowWidth: CGFloat = 520
    static let contentInset: CGFloat = 24
    static let cardInset: CGFloat = 16
    static let iconWidth: CGFloat = 18
}

enum IslandBuilder {

    static func makeCard(rows: [NSView]) -> NSView {
        let card = IslandCardView()
        card.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        for (index, row) in rows.enumerated() {
            if index > 0 {
                let separator = IslandSeparatorView()
                separator.translatesAutoresizingMaskIntoConstraints = false
                stack.addArrangedSubview(separator)
                separator.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
                separator.heightAnchor.constraint(equalToConstant: 10).isActive = true
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

    static func makeSection(title: String, card: NSView, footnote: NSTextField?) -> NSView {
        let header = NSTextField(labelWithString: title)
        header.font = Island.font(12, 700)
        header.textColor = Island.text
        header.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(header)
        container.addSubview(card)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            header.topAnchor.constraint(equalTo: container.topAnchor),
            card.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            card.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8)
        ])

        if let footnote = footnote {
            footnote.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(footnote)
            NSLayoutConstraint.activate([
                footnote.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
                footnote.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
                footnote.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 8),
                footnote.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        } else {
            card.bottomAnchor.constraint(equalTo: container.bottomAnchor).isActive = true
        }
        return container
    }

    static func makeSettingRow(symbol: String,
                               title: String,
                               subtitle: String? = nil,
                               subtitleLabel: NSTextField? = nil,
                               trailing: [NSView]) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = Island.font(13.5, 600)
        titleLabel.textColor = Island.text

        var titleViews: [NSView] = [titleLabel]
        if let subtitle = subtitle {
            let label = NSTextField(labelWithString: subtitle)
            label.font = Island.font(11, 500)
            label.textColor = Island.secondaryText
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
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: IslandConstants.cardInset),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -IslandConstants.cardInset),
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10)
        ])
        return container
    }

    static func makeSliderBlock(slider: NSView, header: NSView) -> NSView {
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
                                            constant: IslandConstants.cardInset + IslandConstants.iconWidth + 10),
            slider.trailingAnchor.constraint(equalTo: container.trailingAnchor,
                                             constant: -IslandConstants.cardInset),
            slider.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 0),
            slider.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
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
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else {
            return nil
        }
        let imageView = NSImageView(image: image)
        imageView.contentTintColor = Island.secondaryText
        imageView.setAccessibilityElement(false)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.widthAnchor.constraint(equalToConstant: IslandConstants.iconWidth).isActive = true
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
}
