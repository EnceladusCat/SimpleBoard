import AppKit

// Drawings are session-local. Screen color selection is handled by macOS.
enum Tool: Int, CaseIterable {
    case pen, line, rectangle, text, pointer, ruler
    var title: String { ["画笔", "直线", "方形", "文字", "选择 / 操作", "像素直尺"][rawValue] }
    var symbol: String { ["pencil.tip", "line.diagonal", "rectangle", "textformat", "cursorarrow", "ruler"][rawValue] }
    var shortcut: String { ["A", "Q", "W", "T", "V", ""][rawValue] }
}

struct RGBValue: Equatable {
    let r: Int
    let g: Int
    let b: Int
    init?(_ color: NSColor) {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        r = Int((min(1, max(0, rgb.redComponent)) * 255).rounded())
        g = Int((min(1, max(0, rgb.greenComponent)) * 255).rounded())
        b = Int((min(1, max(0, rgb.blueComponent)) * 255).rounded())
    }
    var text: String { "rgb(\(r), \(g), \(b))" }
    var hex: String { String(format: "#%02X%02X%02X", r, g, b) }
}

struct PixelMeasurement {
    var start: CGPoint
    var end: CGPoint
    var scale: CGFloat
    var dx: CGFloat { abs(end.x - start.x) * scale }
    var dy: CGFloat { abs(end.y - start.y) * scale }
    var distance: CGFloat { hypot(dx, dy) }
    var text: String {
        String(format: "%.1f px  ·  ΔX %.1f  ΔY %.1f\n%.1f pt · %.0f× 渲染像素", Double(distance),
               Double(dx), Double(dy), Double(distance / scale), Double(scale))
    }
}

struct Mark {
    var tool: Tool
    var points: [CGPoint]
    var text = ""
    var width: CGFloat = 4
    var fontSize: CGFloat = 26
    var color: NSColor = .systemRed

    var attributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
         .foregroundColor: color]
    }

    func draw() {
        guard let first = points.first else { return }
        color.setStroke()
        color.setFill()
        if tool == .text {
            (text as NSString).draw(at: first, withAttributes: attributes)
            return
        }
        let path = NSBezierPath()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        if tool == .pen {
            if points.count == 1 {
                NSBezierPath(ovalIn: NSRect(x: first.x - width / 2, y: first.y - width / 2,
                                          width: width, height: width)).fill()
                return
            }
            path.move(to: first)
            for p in points.dropFirst() { path.line(to: p) }
        } else if let last = points.last {
            if tool == .line {
                path.move(to: first)
                path.line(to: last)
            } else {
                path.appendRect(NSRect(x: min(first.x, last.x), y: min(first.y, last.y),
                                       width: abs(last.x - first.x), height: abs(last.y - first.y)))
            }
        }
        path.stroke()
    }
}

final class DrawingWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// Native backdrop blur follows the windows behind the panel, without capturing
// the screen or reducing the opacity (and readability) of the controls.
final class GlassSurface: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
    }
}

// Compact native buttons keep a readable name and shortcut alongside each symbol.
final class PaletteButton: NSButton {
    private let captionLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")
    private let symbolView = NSImageView()
    private var accent: NSColor {
        effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 1, green: 0.43, blue: 0.47, alpha: 1)
            : NSColor(srgbRed: 0.90, green: 0.12, blue: 0.16, alpha: 1)
    }

    var caption = "" { didSet { captionLabel.stringValue = caption } }
    var keyHint = "" {
        didSet {
            hintLabel.stringValue = keyHint
            hintWidth?.constant = keyHint.isEmpty ? 0 : 38
        }
    }
    private var hintWidth: NSLayoutConstraint?
    var symbolName = "" {
        didSet {
            symbolView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        }
    }
    var destructive = false { didSet { updateAppearance() } }
    var showsSelection = false { didSet { updateAppearance() } }
    override var state: NSControl.StateValue { didSet { updateAppearance() } }
    override var isEnabled: Bool { didSet { updateAppearance() } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLabels()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLabels()
    }

    private func configureLabels() {
        // Let AppKit own text layout and font lifetimes. Do not measure NSStrings
        // with temporary font dictionaries in draw(_:); that path crashed in 1.2.
        captionLabel.font = .systemFont(ofSize: 12)
        hintLabel.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        hintLabel.alignment = .right
        for view in [symbolView, captionLabel, hintLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.setAccessibilityElement(false)
            addSubview(view)
            view.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        }
        hintWidth = hintLabel.widthAnchor.constraint(equalToConstant: keyHint.isEmpty ? 0 : 38)
        NSLayoutConstraint.activate([
            symbolView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            symbolView.widthAnchor.constraint(equalToConstant: 16),
            symbolView.heightAnchor.constraint(equalToConstant: 16),
            captionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            captionLabel.trailingAnchor.constraint(lessThanOrEqualTo: hintLabel.leadingAnchor, constant: -2),
            hintLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            hintWidth!
        ])
        updateAppearance()
    }

    private func updateAppearance() {
        let active = showsSelection && state == .on
        let color: NSColor = !isEnabled ? .disabledControlTextColor :
            (active || destructive ? accent : .labelColor)
        captionLabel.textColor = color
        hintLabel.textColor = !isEnabled ? .disabledControlTextColor :
            (active ? accent : .secondaryLabelColor)
        symbolView.contentTintColor = color
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    // The labels are decorative: clicking a glyph must still press the button.
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func draw(_ dirtyRect: NSRect) {
        let active = showsSelection && state == .on
        if active || isHighlighted {
            (active ? accent.withAlphaComponent(0.16) : NSColor.labelColor.withAlphaComponent(0.08)).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6).fill()
        }
    }
}

final class TextEditor: NSTextView {
    var finish: (() -> Void)?
    var cancel: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancel?(); return }
        if event.keyCode == 36 && event.modifierFlags.contains(.command) { finish?(); return }
        super.keyDown(with: event)
    }
    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }
}

final class Canvas: NSView {
    var tool: Tool = .pen {
        didSet {
            window?.invalidateCursorRects(for: self)
            if oldValue != tool { draft = nil; clearMeasurement() }
        }
    }
    var whiteboard = true { didSet { needsDisplay = true } }
    var lineWidth: CGFloat = 4
    var fontSize: CGFloat = 26
    var strokeColor = NSColor(srgbRed: 0.90, green: 0.12, blue: 0.16, alpha: 1)
    var measurement: PixelMeasurement?
    var measuring = false
    var measurementChanged: ((String) -> Void)?
    private let measurementLabel = NSTextField(wrappingLabelWithString: "")
    var marks: [Mark] = []
    var undoSteps: [[Mark]] = []
    var redoSteps: [[Mark]] = []
    var draft: Mark?
    var editor: TextEditor?
    var editorFrame: NSView?
    var editingPoint: CGPoint?
    var changed: (() -> Void)?
    var say: ((String) -> Void)?
    let red = NSColor(srgbRed: 0.90, green: 0.12, blue: 0.16, alpha: 1)

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // A nearly transparent fill keeps the desktop visible while accepting drawing clicks.
        (whiteboard ? NSColor.white : NSColor.black.withAlphaComponent(0.002)).setFill()
        bounds.fill()
        for mark in marks { mark.draw() }
        draft?.draw()
        if let m = measurement {
            let line = NSBezierPath()
            line.move(to: m.start)
            line.line(to: m.end)
            line.lineCapStyle = .round
            NSColor.black.withAlphaComponent(0.8).setStroke()
            line.lineWidth = 5
            line.stroke()
            NSColor.white.setStroke()
            line.lineWidth = 2
            line.stroke()
            for p in [m.start, m.end] {
                NSColor.systemTeal.setFill()
                NSBezierPath(ovalIn: NSRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)).fill()
            }
        }
    }

    func clearMeasurement() {
        measurement = nil
        measuring = false
        measurementLabel.removeFromSuperview()
        needsDisplay = true
    }

    func updateMeasurement(to point: CGPoint) {
        guard var m = measurement else { return }
        m.end = point
        m.scale = window?.backingScaleFactor ?? m.scale
        measurement = m
        measurementLabel.stringValue = m.text
        measurementLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        measurementLabel.appearance = NSAppearance(named: .darkAqua)
        measurementLabel.textColor = .white
        measurementLabel.drawsBackground = true
        measurementLabel.backgroundColor = NSColor.black.withAlphaComponent(0.85)
        measurementLabel.isSelectable = false
        let width = min(330, bounds.width)
        measurementLabel.frame = NSRect(x: max(0, min(point.x + 14, bounds.width - width)),
                                        y: max(0, min(point.y + 18, bounds.height - 44)),
                                        width: width, height: 44)
        if measurementLabel.superview == nil { addSubview(measurementLabel) }
        needsDisplay = true
        measurementChanged?(m.text)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === measurementLabel ? self : hit
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: tool == .pointer ? .arrow : tool == .text ? .iBeam : .crosshair)
    }

    func checkpoint() {
        undoSteps.append(marks)
        if undoSteps.count > 80 { undoSteps.removeFirst() }
        redoSteps.removeAll()
    }

    func update() {
        needsDisplay = true
        changed?()
    }

    func append(_ mark: Mark) {
        checkpoint()
        marks.append(mark)
        update()
    }

    func undoAction() {
        if editor != nil { commitText() }
        guard let previous = undoSteps.popLast() else { return }
        redoSteps.append(marks)
        marks = previous
        update()
    }

    func redoAction() {
        if editor != nil { commitText() }
        guard let next = redoSteps.popLast() else { return }
        undoSteps.append(marks)
        marks = next
        update()
    }

    func clear() {
        cancelText()
        clearMeasurement()
        draft = nil
        guard !marks.isEmpty else { return }
        checkpoint()
        marks.removeAll()
        update()
        say?("已清空 · ⌘Z 可撤销")
    }

    func point(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if editor != nil { commitText() }
        if tool == .pointer { return }
        if tool == .ruler {
            let p = point(event)
            measurement = PixelMeasurement(start: p, end: p, scale: window?.backingScaleFactor ?? 1)
            measuring = true
            updateMeasurement(to: p)
            return
        }
        if tool == .text {
            beginText(at: point(event))
            return
        }
        draft = Mark(tool: tool, points: [point(event)], width: lineWidth, color: strokeColor)
        needsDisplay = true
    }

    func moveDraft(_ event: NSEvent) {
        if tool == .ruler {
            if measuring { updateMeasurement(to: point(event)) }
            return
        }
        guard var shape = draft, let first = shape.points.first else { return }
        var p = point(event)
        if shape.tool == .pen {
            shape.points.append(p)
        } else {
            if event.modifierFlags.contains(.shift) {
                let dx = p.x - first.x, dy = p.y - first.y
                if shape.tool == .rectangle {
                    let side = max(abs(dx), abs(dy))
                    p = CGPoint(x: first.x + (dx < 0 ? -side : side),
                                y: first.y + (dy < 0 ? -side : side))
                } else {
                    let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
                    let length = hypot(dx, dy)
                    p = CGPoint(x: first.x + cos(angle) * length, y: first.y + sin(angle) * length)
                }
            }
            shape.points = [first, p]
        }
        draft = shape
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) { moveDraft(event) }

    override func mouseUp(with event: NSEvent) {
        if tool == .ruler {
            if measuring { updateMeasurement(to: point(event)) }
            measuring = false
            return
        }
        guard draft != nil else { return }
        moveDraft(event)
        if let shape = draft, let first = shape.points.first, let last = shape.points.last {
            let length = hypot(last.x - first.x, last.y - first.y)
            if shape.tool == .pen || length > 1 { append(shape) }
        }
        draft = nil
        needsDisplay = true
    }

    func beginText(at point: CGPoint) {
        commitText()
        let width = min(440, max(200, bounds.width - 40))
        let height: CGFloat = 180
        let origin = CGPoint(x: max(12, min(point.x, bounds.width - width - 12)),
                             y: max(12, min(point.y, bounds.height - height - 12)))
        let frame = NSView(frame: NSRect(origin: origin, size: NSSize(width: width, height: height)))
        frame.wantsLayer = true
        frame.layer?.backgroundColor = NSColor.clear.cgColor
        frame.layer?.borderWidth = 2
        frame.layer?.borderColor = red.cgColor
        frame.layer?.cornerRadius = 8
        let input = TextEditor(frame: NSRect(x: 8, y: 33, width: width - 16, height: height - 42))
        input.isRichText = false
        input.allowsUndo = true
        input.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        input.textColor = red
        input.insertionPointColor = red
        input.drawsBackground = false
        input.backgroundColor = .clear
        input.isAutomaticQuoteSubstitutionEnabled = false
        input.isAutomaticDashSubstitutionEnabled = false
        input.isAutomaticTextReplacementEnabled = false
        input.isAutomaticSpellingCorrectionEnabled = false
        input.isVerticallyResizable = true
        input.textContainer?.widthTracksTextView = true
        input.textContainerInset = .zero
        input.textContainer?.lineFragmentPadding = 0
        input.setAccessibilityLabel("输入红色等宽文字")
        let finish = NSButton(title: "完成 ⌘↩", target: self, action: #selector(finishEditing))
        finish.bezelStyle = .rounded
        finish.frame = NSRect(x: width - 108, y: 3, width: 100, height: 28)
        let hint = NSTextField(labelWithString: "Enter 换行 · Esc 取消")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 10, y: 8, width: 220, height: 17)
        frame.addSubview(input)
        frame.addSubview(hint)
        frame.addSubview(finish)
        addSubview(frame)
        editor = input
        editorFrame = frame
        editingPoint = CGPoint(x: origin.x + 8, y: origin.y + 9)
        input.finish = { [weak self] in self?.commitText() }
        input.cancel = { [weak self] in self?.cancelText() }
        window?.makeFirstResponder(input)
        say?("文字输入中 · ⌘Enter 完成")
    }

    @objc func finishEditing() { commitText() }

    func commitText() {
        guard let input = editor, let p = editingPoint else { return }
        let text = input.string
        cancelText()
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            append(Mark(tool: .text, points: [p], text: text, fontSize: fontSize, color: red))
        }
    }

    func cancelText() {
        editor = nil
        editorFrame?.removeFromSuperview()
        editorFrame = nil
        editingPoint = nil
        window?.makeFirstResponder(self)
    }

    func pasteText() {
        guard let raw = NSPasteboard.general.string(forType: .string),
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            say?("剪贴板没有可粘贴的文字")
            return
        }
        guard let window else { return }
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n")
                      .replacingOccurrences(of: "\r", with: "\n")
        let location = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        let mark = Mark(tool: .text, points: [], text: text, fontSize: fontSize, color: red)
        let size = (text as NSString).size(withAttributes: mark.attributes)
        let x = max(12, min(location.x, bounds.width - min(size.width, bounds.width - 24) - 12))
        let y = max(12, min(location.y, bounds.height - min(size.height, bounds.height - 24) - 12))
        append(Mark(tool: .text, points: [CGPoint(x: x, y: y)], text: text,
                    fontSize: fontSize, color: red))
        say?("已粘贴红色等宽文字 · ⌘Z 撤销")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextFieldDelegate {
    var drawingWindow: DrawingWindow!
    var palette: NSPanel!
    var canvas: Canvas!
    var mode: NSSegmentedControl!
    var toolButtons: [NSButton] = []
    var status: NSTextField!
    var undoButton: NSButton!
    var redoButton: NSButton!
    var styleButton: PaletteButton!
    var stylePopover: NSPopover!
    var strokeRGBFields: [NSTextField] = []
    var colorMessage: NSTextField!
    var rulerResult: NSTextField!
    var sampleResult: NSTextField!
    var copyRGBItem: NSMenuItem!
    var useSampleItem: NSMenuItem!
    var styleStack: NSStackView!
    var advancedBody: NSStackView!
    var toolsBody: NSStackView!
    var advancedToggle: NSButton!
    var toolsToggle: NSButton!
    var sampleRow: NSStackView!
    var colorPreview: ColorChipButton!
    var presetButtons: [ColorChipButton] = []
    var presetColors: [NSColor] { [canvas.red, .systemBlue, .systemGreen, .black, .white] }
    var hexField: NSTextField!
    var editingHex = false
    var widthSlider: NSSlider!
    var widthValue: NSTextField!
    var strokePreview: StrokePreview!
    var styleUndo: NSButton!
    var styleRedo: NSButton!
    var helpPanel: NSPanel!
    var sampledColor: NSColor?
    var sampledRGB: RGBValue?
    var isSampling = false
    private let colorSampler = NSColorSampler()
    var interactingWithDesktop = false
    var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: .aqua)
        makeMenu()
        let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main!
        drawingWindow = DrawingWindow(contentRect: screen.visibleFrame, styleMask: [.borderless],
                                      backing: .buffered, defer: false)
        drawingWindow.title = "简笔白板 · 绘图画布"
        drawingWindow.isOpaque = false
        drawingWindow.backgroundColor = .clear
        drawingWindow.hasShadow = false
        drawingWindow.level = .floating
        drawingWindow.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        drawingWindow.isReleasedWhenClosed = false
        drawingWindow.delegate = self
        canvas = Canvas(frame: NSRect(origin: .zero, size: screen.visibleFrame.size))
        canvas.autoresizingMask = [.width, .height]
        drawingWindow.contentView = canvas
        canvas.changed = { [weak self] in self?.updateButtons() }
        canvas.say = { [weak self] message in self?.showStatus(message) }
        canvas.measurementChanged = { [weak self] text in self?.showMeasurement(text) }
        makePalette(visibleFrame: screen.visibleFrame)
        drawingWindow.makeKeyAndOrderFront(nil)
        drawingWindow.makeFirstResponder(canvas)
        palette.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func makeMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "简笔白板")
        appMenu.addItem(withTitle: "关于简笔白板", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏简笔白板", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出简笔白板", action: #selector(exitApp), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        for (title, action, key) in [("剪切", #selector(NSText.cut(_:)), "x"),
                                     ("复制", #selector(NSText.copy(_:)), "c"),
                                     ("粘贴", #selector(NSText.paste(_:)), "v"),
                                     ("全选", #selector(NSText.selectAll(_:)), "a")] {
            editMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        editItem.submenu = editMenu
        menu.addItem(editItem)
        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "视图")
        viewMenu.addItem(withTitle: "切换白板 / 透明模式", action: #selector(toggleMode), keyEquivalent: "b")
        viewMenu.addItem(withTitle: "显示工具面板", action: #selector(showPalette), keyEquivalent: ",")
        viewMenu.addItem(withTitle: "帮助与快捷键", action: #selector(showHelp), keyEquivalent: "/")
        viewItem.submenu = viewMenu
        menu.addItem(viewItem)
        NSApp.mainMenu = menu
    }

    func makePalette(visibleFrame: NSRect) {
        let size = NSSize(width: 144, height: 460)
        let frame = NSRect(x: visibleFrame.minX + 16,
                           y: visibleFrame.maxY - size.height - 20,
                           width: size.width, height: size.height)
        palette = NSPanel(contentRect: frame, styleMask: [.titled, .utilityWindow, .fullSizeContentView], backing: .buffered, defer: false)
        palette.title = "简笔白板"
        palette.appearance = NSAppearance(named: .darkAqua)
        palette.titlebarAppearsTransparent = true
        palette.isOpaque = false
        palette.backgroundColor = .clear
        palette.hasShadow = true
        palette.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        palette.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        palette.isFloatingPanel = true
        palette.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        palette.hidesOnDeactivate = false
        palette.isReleasedWhenClosed = false
        let root = GlassSurface(frame: NSRect(origin: .zero, size: size))
        palette.contentView = root
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor, constant: 10)
        ])
        mode = NSSegmentedControl(labels: ["白板", "透明"], trackingMode: .selectOne,
                                  target: self, action: #selector(changeMode))
        mode.controlSize = .small
        mode.segmentDistribution = .fillEqually
        mode.selectedSegment = 0
        mode.setAccessibilityLabel("画布模式：白板或透明")
        mode.toolTip = "白板：白色背景；透明：在桌面上批注，选择 V 可操作其他应用。"
        addWide(mode, to: stack, height: 26)

        let toolStack = NSStackView()
        toolStack.orientation = .vertical
        toolStack.spacing = 3
        for tool in [Tool.pointer, .pen, .line, .rectangle, .text] {
            let button = compactButton(tool == .pointer ? "选择" : tool.title,
                                       symbol: tool.symbol, key: tool.shortcut,
                                       action: #selector(changeTool(_:)))
            button.tag = tool.rawValue
            button.setButtonType(.toggle)
            button.showsSelection = true
            button.setAccessibilityLabel(tool.title + " " + tool.shortcut)
            button.toolTip = tool == .pointer ? "选择 / 操作（V）：透明模式下点击穿透至其他应用" :
                "\(tool.title)（\(tool.shortcut)）"
            toolButtons.append(button)
            addWide(button, to: toolStack, height: 30)
        }
        addWide(toolStack, to: stack)
        addSeparator(to: stack)

        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.distribution = .fillEqually
        actions.spacing = 4
        undoButton = NSButton(image: NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "撤销")!,
                              target: self, action: #selector(undoDrawing))
        redoButton = NSButton(image: NSImage(systemSymbolName: "arrow.uturn.forward", accessibilityDescription: "重做")!,
                              target: self, action: #selector(redoDrawing))
        for (button, label) in [(undoButton!, "撤销（⌘Z）"), (redoButton!, "重做（⌘⇧Z）")] {
            button.bezelStyle = .recessed
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel(label)
            button.toolTip = label
            actions.addArrangedSubview(button)
        }
        addWide(actions, to: stack, height: 26)
        let paste = compactButton("贴文字", symbol: "doc.on.clipboard", key: "Z", action: #selector(pasteText))
        paste.toolTip = "贴文字（Z）：在鼠标位置粘贴红色等宽文字"
        addWide(paste, to: stack, height: 30)
        let clear = compactButton("清空", symbol: "trash", key: "C", action: #selector(clearDrawing))
        clear.toolTip = "清空画布（C），不退出；⌘Z 可以恢复"
        clear.setAccessibilityLabel("清空画布 C，不退出")
        addWide(clear, to: stack, height: 30)

        styleButton = compactButton("样式和工具", symbol: "slider.horizontal.3",
                                    action: #selector(showStyles))
        styleButton.setAccessibilityLabel("样式和工具：颜色、线宽、字号、像素直尺、屏幕取色")
        addWide(styleButton, to: stack, height: 30)
        makeStylePopover()
        addSeparator(to: stack)
        let exit = compactButton("退出", symbol: "xmark", key: "X", action: #selector(exitApp))
        exit.destructive = true
        exit.toolTip = "清空并退出（X）：本次批注不会保存"
        exit.setAccessibilityLabel("清空并退出 X")
        addWide(exit, to: stack, height: 30)
        status = NSTextField(wrappingLabelWithString: "白板 · 画笔")
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.maximumNumberOfLines = 2
        status.alignment = .center
        addWide(status, to: stack, height: 30)
        root.layoutSubtreeIfNeeded()
        palette.setContentSize(NSSize(width: size.width, height: stack.fittingSize.height + 20))
        palette.setFrameTopLeftPoint(NSPoint(x: frame.minX, y: visibleFrame.maxY - 20))
        updateWindowLevels()
        updateButtons()
    }

    func compactButton(_ caption: String, symbol: String, key: String = "",
                       action: Selector) -> PaletteButton {
        let button = PaletteButton(title: caption, target: self, action: action)
        button.caption = caption
        button.symbolName = symbol
        button.keyHint = key
        button.setButtonType(.momentaryPushIn)
        button.isBordered = false
        button.setAccessibilityLabel(caption + (key.isEmpty ? "" : " " + key))
        return button
    }

    func addSeparator(to stack: NSStackView) {
        let separator = NSBox()
        separator.boxType = .separator
        addWide(separator, to: stack, height: 1)
    }

    func makeStylePopover() {
        let controller = NSViewController()
        controller.view = GlassSurface(frame: NSRect(x: 0, y: 0, width: 300, height: 320))
        let stack = NSStackView()
        styleStack = stack
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: controller.view.topAnchor, constant: 18)
        ])
        let header = NSStackView()
        let heading = NSTextField(labelWithString: "样式和工具")
        heading.font = .systemFont(ofSize: 14, weight: .semibold)
        header.addArrangedSubview(heading)
        header.addArrangedSubview(NSView())
        let help = NSButton(image: NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: "帮助")!,
                            target: self, action: #selector(showHelp))
        help.isBordered = false
        help.toolTip = "帮助与快捷键（⌘/）"
        help.setAccessibilityLabel("帮助与快捷键")
        header.addArrangedSubview(help)
        addWide(header, to: stack, height: 24)

        let colors = NSStackView()
        colors.spacing = 7
        colors.addArrangedSubview(NSTextField(labelWithString: "颜色"))
        colorPreview = ColorChipButton(title: "", target: self, action: #selector(openColorPanel))
        colorPreview.color = canvas.strokeColor
        colorPreview.setAccessibilityLabel("当前画笔颜色；点击打开调色盘")
        colorPreview.toolTip = "选择画笔颜色，不改变已有笔迹或文字"
        colorPreview.widthAnchor.constraint(equalToConstant: 36).isActive = true
        colorPreview.heightAnchor.constraint(equalToConstant: 36).isActive = true
        colors.addArrangedSubview(colorPreview)
        colors.addArrangedSubview(NSView())
        for (index, name) in ["红", "蓝", "绿", "黑", "白"].enumerated() {
            let button = ColorChipButton(title: "", target: self, action: #selector(selectPreset(_:)))
            button.tag = index
            button.color = presetColors[index]
            button.toolTip = name
            button.setAccessibilityLabel("画笔颜色：" + name)
            button.widthAnchor.constraint(equalToConstant: 25).isActive = true
            button.heightAnchor.constraint(equalToConstant: 25).isActive = true
            presetButtons.append(button)
            colors.addArrangedSubview(button)
        }
        addWide(colors, to: stack, height: 36)
        advancedToggle = disclosure("精确颜色", action: #selector(toggleAdvanced))
        addWide(advancedToggle, to: stack, height: 18)
        advancedBody = NSStackView()
        advancedBody.orientation = .vertical
        advancedBody.spacing = 8
        let rgbRow = NSStackView()
        rgbRow.spacing = 6
        let rgb = RGBValue(canvas.strokeColor)!
        for (index, name) in ["R", "G", "B"].enumerated() {
            rgbRow.addArrangedSubview(NSTextField(labelWithString: name))
            let field = NSTextField(string: String([rgb.r, rgb.g, rgb.b][index]))
            field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            field.widthAnchor.constraint(equalToConstant: 53).isActive = true
            field.target = self
            field.action = #selector(applyRGB)
            field.delegate = self
            field.setAccessibilityLabel(name + "，0 到 255；回车应用")
            strokeRGBFields.append(field)
            rgbRow.addArrangedSubview(field)
        }
        addWide(rgbRow, to: advancedBody, height: 26)
        let hexRow = NSStackView()
        hexRow.addArrangedSubview(NSTextField(labelWithString: "HEX"))
        hexField = NSTextField(string: rgb.hex)
        hexField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        hexField.target = self
        hexField.action = #selector(applyHex)
        hexField.delegate = self
        hexField.setAccessibilityLabel("HEX 六位颜色；回车应用")
        hexRow.addArrangedSubview(hexField)
        let apply = smallButton("应用", action: #selector(applyExactColor))
        apply.toolTip = "应用正在编辑的 RGB 或 HEX"
        hexRow.addArrangedSubview(apply)
        addWide(hexRow, to: advancedBody, height: 28)
        colorMessage = NSTextField(labelWithString: "")
        colorMessage.font = .systemFont(ofSize: 11)
        colorMessage.textColor = .systemOrange
        addWide(colorMessage, to: advancedBody)
        colorMessage.isHidden = true
        addWide(advancedBody, to: stack)
        advancedBody.isHidden = true

        let widthRow = NSStackView()
        widthRow.spacing = 8
        widthRow.addArrangedSubview(NSTextField(labelWithString: "粗细"))
        widthSlider = NSSlider(value: Double(canvas.lineWidth), minValue: 1, maxValue: 12,
                               target: self, action: #selector(changeWidthSlider(_:)))
        widthSlider.isContinuous = true
        widthSlider.setAccessibilityLabel("画笔粗细，1 到 12 点")
        widthRow.addArrangedSubview(widthSlider)
        strokePreview = StrokePreview(frame: .zero)
        strokePreview.widthAnchor.constraint(equalToConstant: 36).isActive = true
        strokePreview.heightAnchor.constraint(equalToConstant: 24).isActive = true
        widthRow.addArrangedSubview(strokePreview)
        widthValue = NSTextField(labelWithString: "4")
        widthValue.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        widthValue.widthAnchor.constraint(equalToConstant: 18).isActive = true
        widthRow.addArrangedSubview(widthValue)
        addWide(widthRow, to: stack, height: 28)

        let textRow = NSStackView()
        textRow.spacing = 10
        textRow.addArrangedSubview(NSTextField(labelWithString: "文字"))
        let textColor = NSBox()
        textColor.boxType = .custom
        textColor.fillColor = canvas.red
        textColor.borderWidth = 0
        textColor.cornerRadius = 4
        textColor.widthAnchor.constraint(equalToConstant: 8).isActive = true
        textColor.heightAnchor.constraint(equalToConstant: 8).isActive = true
        textColor.toolTip = "文字默认红色，画笔调色不影响文字"
        textRow.addArrangedSubview(textColor)
        textRow.addArrangedSubview(NSView())
        let sizes = NSPopUpButton()
        sizes.addItems(withTitles: ["18 pt", "26 pt", "36 pt", "48 pt", "64 pt"])
        sizes.selectItem(at: 1)
        sizes.target = self
        sizes.action = #selector(changeFont(_:))
        sizes.setAccessibilityLabel("文字字号")
        sizes.widthAnchor.constraint(equalToConstant: 110).isActive = true
        textRow.addArrangedSubview(sizes)
        addWide(textRow, to: stack, height: 28)

        toolsToggle = disclosure("更多工具", action: #selector(toggleTools))
        addWide(toolsToggle, to: stack, height: 24)
        toolsBody = NSStackView()
        toolsBody.orientation = .vertical
        toolsBody.spacing = 10
        let toolRow = NSStackView()
        toolRow.distribution = .fillEqually
        toolRow.spacing = 8
        let ruler = smallButton("直尺", action: #selector(startRuler))
        ruler.image = NSImage(systemSymbolName: "ruler", accessibilityDescription: nil)
        ruler.imagePosition = .imageLeading
        ruler.toolTip = "拖动测量渲染像素距离；Esc 取消"
        let sampler = smallButton("吸色", action: #selector(sampleScreenColor))
        sampler.image = NSImage(systemSymbolName: "eyedropper", accessibilityDescription: nil)
        sampler.imagePosition = .imageLeading
        sampler.toolTip = "系统放大镜取色；单击后显示 RGB，Esc 取消"
        toolRow.addArrangedSubview(ruler)
        toolRow.addArrangedSubview(sampler)
        addWide(toolRow, to: toolsBody, height: 30)
        rulerResult = NSTextField(wrappingLabelWithString: "")
        rulerResult.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        rulerResult.isSelectable = true
        rulerResult.isHidden = true
        addWide(rulerResult, to: toolsBody, height: 36)
        sampleRow = NSStackView()
        sampleRow.spacing = 6
        sampleResult = NSTextField(labelWithString: "")
        sampleResult.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        sampleResult.isSelectable = true
        sampleRow.addArrangedSubview(sampleResult)
        sampleRow.addArrangedSubview(NSView())
        let actions = NSPopUpButton(frame: .zero, pullsDown: true)
        actions.addItem(withTitle: "•••")
        copyRGBItem = NSMenuItem(title: "复制 RGB", action: #selector(copyRGB), keyEquivalent: "")
        useSampleItem = NSMenuItem(title: "用于画笔", action: #selector(useSampleColor), keyEquivalent: "")
        for item in [copyRGBItem!, useSampleItem!] { item.target = self; actions.menu?.addItem(item) }
        actions.menu?.autoenablesItems = false
        copyRGBItem.isEnabled = false
        useSampleItem.isEnabled = false
        actions.setAccessibilityLabel("取色结果操作")
        sampleRow.addArrangedSubview(actions)
        addWide(sampleRow, to: toolsBody, height: 28)
        sampleRow.isHidden = true
        addWide(toolsBody, to: stack)
        toolsBody.isHidden = true
        addSeparator(to: stack)

        let footer = NSStackView()
        footer.distribution = .fillEqually
        footer.spacing = 6
        styleUndo = smallButton("撤销", action: #selector(undoDrawing))
        styleRedo = smallButton("重做", action: #selector(redoDrawing))
        footer.addArrangedSubview(styleUndo)
        footer.addArrangedSubview(styleRedo)
        footer.addArrangedSubview(smallButton("清空", action: #selector(clearDrawing)))
        addWide(footer, to: stack, height: 28)
        stylePopover = NSPopover()
        stylePopover.appearance = NSAppearance(named: .darkAqua)
        stylePopover.behavior = .transient
        stylePopover.contentViewController = controller
        refreshStyleSize()
        syncColorControls()
    }

    func smallButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        return button
    }

    func disclosure(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: "› " + title, target: self, action: action)
        button.isBordered = false
        button.alignment = .left
        button.font = .systemFont(ofSize: 12)
        button.contentTintColor = .secondaryLabelColor
        button.setAccessibilityLabel(title + "，展开或收起")
        return button
    }

    func refreshStyleSize() {
        guard let root = stylePopover?.contentViewController?.view, let styleStack else { return }
        root.layoutSubtreeIfNeeded()
        let size = NSSize(width: 300, height: styleStack.fittingSize.height + 36)
        stylePopover.contentSize = size
        root.setFrameSize(size)
        root.layoutSubtreeIfNeeded()
    }

    @objc func toggleAdvanced() {
        advancedBody.isHidden.toggle()
        advancedToggle.title = (advancedBody.isHidden ? "› " : "⌄ ") + "精确颜色"
        refreshStyleSize()
    }

    @objc func toggleTools() {
        toolsBody.isHidden.toggle()
        toolsToggle.title = (toolsBody.isHidden ? "› " : "⌄ ") + "更多工具"
        refreshStyleSize()
    }

    func showMeasurement(_ text: String) {
        rulerResult.stringValue = text
        rulerResult.isHidden = false
        if stylePopover.isShown { refreshStyleSize() }
    }

    func syncColorControls() {
        guard let rgb = RGBValue(canvas.strokeColor) else { return }
        colorPreview?.color = canvas.strokeColor
        colorPreview?.setAccessibilityLabel("当前画笔颜色 " + rgb.hex + "；点击打开调色盘")
        hexField?.stringValue = rgb.hex
        strokePreview?.color = canvas.strokeColor
        for button in presetButtons { button.selected = RGBValue(button.color) == rgb }
    }

    @objc func openColorPanel() {
        stylePopover.performClose(nil)
        let panel = NSColorPanel.shared
        panel.color = canvas.strokeColor
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.setTarget(self)
        panel.setAction(#selector(changeColorPanel(_:)))
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: palette.level.rawValue + 1)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc func changeColorPanel(_ sender: NSColorPanel) { setStrokeColor(sender.color) }

    @objc func applyExactColor() {
        if editingHex { applyHex() } else { applyRGB() }
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        editingHex = notification.object as? NSTextField === hexField
    }

    @objc func applyHex() {
        var text = hexField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, text.allSatisfy({ $0.isHexDigit }), let value = UInt32(text, radix: 16) else {
            colorMessage.stringValue = "请输入六位 HEX"
            colorMessage.isHidden = false
            refreshStyleSize()
            return
        }
        setStrokeColor(NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                               green: CGFloat((value >> 8) & 255) / 255,
                               blue: CGFloat(value & 255) / 255, alpha: 1))
    }

    @objc func changeWidthSlider(_ sender: NSSlider) {
        canvas.lineWidth = CGFloat(sender.doubleValue.rounded())
        sender.doubleValue = Double(canvas.lineWidth)
        updateButtons()
    }

    @objc func showHelp() {
        stylePopover.performClose(nil)
        if helpPanel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 520),
                                styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
            panel.title = "帮助与快捷键"
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = true
            panel.appearance = NSAppearance(named: .darkAqua)
            let view = GlassSurface(frame: NSRect(x: 0, y: 0, width: 360, height: 520))
            panel.contentView = view
            let text = NSTextField(wrappingLabelWithString:
                "A 画笔 · Q 直线 · W 方形 · T 文字 · V 选择\nZ 贴文字 · C 清空 · X 清空并退出\n⌘Z 撤销 · ⌘⇧Z 重做 · ⌘/ 帮助\nShift 约束形状 · ⌘↩ 完成文字 · Esc 取消\n\n颜色\n画笔调色不改变旧笔迹或红色文字。精确颜色中可输入 RGB / HEX，回车应用。\n\n直尺\n拖动测量距离，px 是渲染像素（逻辑点 × 屏幕倍率），不是网页 CSS px。\n\n吸色\n使用系统放大镜，单击确认后显示 RGB，Esc 取消。结果菜单可复制 RGB 或用于画笔，悬停读数查看 HEX。无需屏幕录制权限，不保存截图。原生接口不提供移动时的实时 RGB。\n\n快捷键仅前台生效；输入文字时字母正常输入。")
            text.font = .systemFont(ofSize: 12)
            text.frame = NSRect(x: 20, y: 18, width: 320, height: 484)
            view.addSubview(text)
            helpPanel = panel
        }
        helpPanel.level = NSWindow.Level(rawValue: palette.level.rawValue + 1)
        helpPanel.center()
        helpPanel.makeKeyAndOrderFront(nil)
    }

    func setStrokeColor(_ color: NSColor) {
        guard let rgb = RGBValue(color) else { return }
        canvas.strokeColor = NSColor(srgbRed: CGFloat(rgb.r) / 255, green: CGFloat(rgb.g) / 255,
                                    blue: CGFloat(rgb.b) / 255, alpha: 1)
        for (field, value) in zip(strokeRGBFields, [rgb.r, rgb.g, rgb.b]) { field.stringValue = String(value) }
        colorMessage.stringValue = ""
        colorMessage.isHidden = true
        syncColorControls()
        refreshStyleSize()
        updateButtons()
    }

    @objc func applyRGB() {
        let values = strokeRGBFields.compactMap { Int($0.stringValue.trimmingCharacters(in: .whitespaces)) }
        guard values.count == 3, values.allSatisfy({ (0...255).contains($0) }) else {
            colorMessage.stringValue = "请输入 0–255 的整数，颜色未更改"
            colorMessage.isHidden = false
            refreshStyleSize()
            return
        }
        setStrokeColor(NSColor(srgbRed: CGFloat(values[0]) / 255, green: CGFloat(values[1]) / 255,
                               blue: CGFloat(values[2]) / 255, alpha: 1))
    }

    @objc func selectPreset(_ sender: NSButton) {
        let colors: [NSColor] = [canvas.red, .systemBlue, .systemGreen, .black, .white]
        guard colors.indices.contains(sender.tag) else { return }
        setStrokeColor(colors[sender.tag])
    }

    @objc func startRuler() {
        stylePopover.performClose(nil)
        select(.ruler)
    }

    @discardableResult func recordSample(_ color: NSColor?) -> Bool {
        guard let color, let rgb = RGBValue(color) else { return false }
        sampledColor = color
        sampledRGB = rgb
        sampleResult.stringValue = rgb.text
        sampleResult.toolTip = rgb.hex
        sampleRow.isHidden = false
        copyRGBItem.isEnabled = true
        useSampleItem.isEnabled = true
        refreshStyleSize()
        return true
    }

    @objc func copyRGB() {
        guard let rgb = sampledRGB else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(rgb.text, forType: .string)
    }

    @objc func useSampleColor() {
        guard let color = sampledColor else { return }
        setStrokeColor(color)
    }

    @objc func sampleScreenColor() {
        guard !isSampling else { return }
        let wasVisible = prepareSampling()
        colorSampler.show { [weak self] color in
            self?.restoreAfterSampling(color, canvasWasVisible: wasVisible)
        }
    }

    func prepareSampling() -> Bool {
        canvas.commitText()
        canvas.draft = nil
        canvas.measuring = false
        let canvasWasVisible = drawingWindow.isVisible
        isSampling = true
        stylePopover.performClose(nil)
        helpPanel?.orderOut(nil)
        if NSColorPanel.sharedColorPanelExists { NSColorPanel.shared.orderOut(nil) }
        drawingWindow.orderOut(nil)
        palette.orderOut(nil)
        return canvasWasVisible
    }

    func restoreAfterSampling(_ color: NSColor?, canvasWasVisible: Bool) {
        isSampling = false
        recordSample(color)
        toolsBody.isHidden = false
        toolsToggle.title = "⌄ 更多工具"
        if NSApp.isActive {
            if canvasWasVisible { drawingWindow.orderFrontRegardless() }
            showStyles()
        } else {
            if interactingWithDesktop && canvasWasVisible { drawingWindow.orderFrontRegardless() }
            keepPaletteVisible()
        }
    }

    func updateWindowLevels() {
        guard let drawingWindow, let palette else { return }
        // isFloatingPanel can reset a panel's level: set the explicit level last.
        drawingWindow.level = canvas.whiteboard ? .normal : .floating
        palette.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
    }

    func keepPaletteVisible() {
        guard !isSampling, let palette else { return }
        updateWindowLevels()
        palette.orderFrontRegardless()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if notification.object as? NSWindow === drawingWindow { keepPaletteVisible() }
    }

    @objc func showStyles() {
        if stylePopover.isShown { stylePopover.performClose(nil); return }
        refreshStyleSize()
        showPalette()
        stylePopover.show(relativeTo: styleButton.bounds, of: styleButton, preferredEdge: .maxX)
    }

    func showStatus(_ message: String) {
        status.toolTip = message
        if message.contains("剪贴板没有") { status.stringValue = "剪贴板无文字" }
        else if message.contains("已粘贴") { status.stringValue = "已贴文字 · ⌘Z 撤销" }
        else if message.contains("已清空") { status.stringValue = "已清空 · ⌘Z 撤销" }
        else if message.contains("输入中") { status.stringValue = "输入中 · ⌘↩ 完成" }
        else {
            status.stringValue = interactingWithDesktop ? "可操作下方应用" :
                "\(canvas.whiteboard ? "白板" : "透明") · \(canvas.tool == .pointer ? "选择" : canvas.tool.title)"
        }
    }

    func addWide(_ view: NSView, to stack: NSStackView, height: CGFloat? = nil) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        if let height { view.heightAnchor.constraint(equalToConstant: height).isActive = true }
    }

    func focusCanvas() {
        guard !isSampling else { return }
        if canvas.tool == .pointer && !canvas.whiteboard {
            setDesktopInteraction(true)
            NSApp.activate(ignoringOtherApps: true)
            palette.makeKeyAndOrderFront(nil)
            return
        }
        setDesktopInteraction(false)
        NSApp.activate(ignoringOtherApps: true)
        drawingWindow.makeKeyAndOrderFront(nil)
        drawingWindow.makeFirstResponder(canvas)
        keepPaletteVisible()
    }

    func updateButtons() {
        for b in toolButtons {
            b.state = b.tag == canvas.tool.rawValue ? .on : .off
            b.needsDisplay = true
        }
        undoButton?.isEnabled = !canvas.undoSteps.isEmpty
        redoButton?.isEnabled = !canvas.redoSteps.isEmpty
        styleUndo?.isEnabled = !canvas.undoSteps.isEmpty
        styleRedo?.isEnabled = !canvas.redoSteps.isEmpty
        widthSlider?.doubleValue = Double(canvas.lineWidth)
        widthValue?.stringValue = "\(Int(canvas.lineWidth))"
        strokePreview?.width = canvas.lineWidth
        styleButton?.toolTip = "样式和工具：颜色、线宽 \(Int(canvas.lineWidth)) pt、字号 \(Int(canvas.fontSize)) pt、像素直尺、RGB 取色"
        styleButton?.setAccessibilityLabel("样式和工具：颜色、线宽、字号、像素直尺、RGB 取色")
        styleButton?.needsDisplay = true
    }

    func select(_ tool: Tool) {
        canvas.commitText()
        canvas.tool = tool
        updateButtons()
        showStatus(tool.title)
        if tool == .pointer {
            if canvas.whiteboard { focusCanvas() }
            else { setDesktopInteraction(true) }
        } else { focusCanvas() }
    }

    @objc func changeTool(_ sender: NSButton) { select(Tool(rawValue: sender.tag)!) }
    @objc func changeMode() {
        canvas.commitText()
        canvas.whiteboard = mode.selectedSegment == 0
        showStatus(canvas.whiteboard ? "白色画布" : "透明画布")
        if canvas.whiteboard { focusCanvas() }
        else { setDesktopInteraction(true) }
    }
    func setDesktopInteraction(_ enabled: Bool) {
        updateWindowLevels()
        interactingWithDesktop = enabled && !canvas.whiteboard
        drawingWindow.ignoresMouseEvents = interactingWithDesktop
        palette.hidesOnDeactivate = false
        if interactingWithDesktop {
            canvas.tool = .pointer
            canvas.commitText()
            canvas.draft = nil
            canvas.needsDisplay = true
            drawingWindow.orderFrontRegardless()
            palette.orderFrontRegardless()
        }
        updateButtons()
        showStatus(interactingWithDesktop ? "点击穿透 · 网页可正常点击、滚动" : "批注中")
    }
    @objc func toggleMode() {
        mode.selectedSegment = canvas.whiteboard ? 1 : 0
        changeMode()
    }
    @objc func showPalette() {
        guard !isSampling else { return }
        updateWindowLevels()
        NSApp.activate(ignoringOtherApps: true)
        palette.makeKeyAndOrderFront(nil)
    }
    @objc func changeWidth(_ sender: NSSegmentedControl) {
        canvas.lineWidth = [2, 4, 8][sender.selectedSegment]
        updateButtons()
        if !stylePopover.isShown { focusCanvas() }
    }
    @objc func changeFont(_ sender: NSPopUpButton) {
        canvas.commitText()
        canvas.fontSize = [18, 26, 36, 48, 64][sender.indexOfSelectedItem]
        updateButtons()
        if !stylePopover.isShown { focusCanvas() }
    }
    @objc func undoDrawing() { canvas.undoAction(); focusCanvas() }
    @objc func redoDrawing() { canvas.redoAction(); focusCanvas() }
    @objc func clearDrawing() {
        canvas.clear()
        select(.pointer)
        showStatus("已清空 · 选择模式 · ⌘Z 可撤销")
    }
    @objc func pasteText() { canvas.commitText(); canvas.pasteText(); focusCanvas() }
    @objc func exitApp() {
        canvas.cancelText()
        canvas.marks.removeAll()
        canvas.undoSteps.removeAll()
        canvas.redoSteps.removeAll()
        canvas.draft = nil
        canvas.display()
        drawingWindow.orderOut(nil)
        palette.orderOut(nil)
        NSApp.terminate(nil)
    }
    @objc func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "简笔白板",
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            .credits: NSAttributedString(string: "画笔 · 直线 · 方形 · 红色等宽文字\nZ 粘贴文字，C 清空，X 清空并退出。\n本地运行，无联网、录屏或辅助功能权限要求。\n吸色使用系统放大镜，仅返回选定颜色，不保存截图。")
        ])
    }

    func handleKey(_ event: NSEvent) -> NSEvent? {
        guard !isSampling else { return event }
        guard NSApp.keyWindow === drawingWindow || NSApp.keyWindow === palette else { return event }
        // Text responders retain normal letters, cut/paste, undo, and IME composition.
        if NSApp.keyWindow?.firstResponder is NSTextView { return event }
        let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if mods.contains(.command) {
            if event.keyCode == 6 { // ANSI Z, independent of the current input method.
                mods.contains(.shift) ? canvas.redoAction() : canvas.undoAction()
                return nil
            }
            if event.keyCode == 9 { pasteText(); return nil } // Cmd V
            return event
        }
        if mods.contains(.option) || mods.contains(.control) { return event }
        if event.characters == "?" { showHelp(); return nil }
        if event.isARepeat { return event }
        switch event.keyCode {
        case 8: clearDrawing(); return nil // C; text input and Cmd-C are handled above.
        case 7: exitApp(); return nil // X
        case 6: pasteText(); return nil // Z
        case 0: select(.pen); return nil // A
        case 12: select(.line); return nil // Q
        case 13: select(.rectangle); return nil // W
        case 17: select(.text); return nil
        case 9: select(.pointer); return nil
        case 53: canvas.draft = nil; canvas.clearMeasurement(); canvas.needsDisplay = true; return nil
        default: return event
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        guard !isSampling else { return }
        // Switching apps restores normal desktop interaction without losing drawings.
        canvas.draft = nil
        canvas.measuring = false
        if interactingWithDesktop { return }
        drawingWindow.orderOut(nil)
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        guard drawingWindow != nil, palette != nil, !isSampling else { return }
        updateWindowLevels()
        if interactingWithDesktop {
            drawingWindow.orderFrontRegardless()
            palette.orderFrontRegardless()
            return
        }
        drawingWindow.makeKeyAndOrderFront(nil)
        keepPaletteVisible()
        drawingWindow.makeFirstResponder(canvas.editor ?? canvas)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if isSampling { return true }
        focusCanvas()
        palette.orderFrontRegardless()
        return true
    }
    @objc func screenChanged() {
        if isSampling { return }
        guard let screen = drawingWindow.screen ?? NSScreen.main else { return }
        drawingWindow.setFrame(screen.visibleFrame, display: true)
        palette.setFrameTopLeftPoint(NSPoint(x: screen.visibleFrame.minX + 20, y: screen.visibleFrame.maxY - 24))
        canvas.clearMeasurement()
        keepPaletteVisible()
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }
}

let app = NSApplication.shared
#if REGRESSION_TESTS
runRegressionTests()
#else
let delegate = AppDelegate()
app.delegate = delegate
app.run()
#endif
