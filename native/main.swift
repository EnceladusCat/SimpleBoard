import AppKit

// All drawings are session-local. No screenshots, files, or network are read.
enum Tool: Int, CaseIterable {
    case pen, line, rectangle, text, pointer
    var title: String { ["画笔", "直线", "方形", "文字", "选择 / 操作"][rawValue] }
    var symbol: String { ["pencil.tip", "line.diagonal", "rectangle", "textformat", "cursorarrow"][rawValue] }
    var shortcut: String { ["A", "Q", "W", "T", "V"][rawValue] }
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
    var keyHint = "" { didSet { hintLabel.stringValue = keyHint } }
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
        NSLayoutConstraint.activate([
            symbolView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            symbolView.widthAnchor.constraint(equalToConstant: 16),
            symbolView.heightAnchor.constraint(equalToConstant: 16),
            captionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            captionLabel.trailingAnchor.constraint(lessThanOrEqualTo: hintLabel.leadingAnchor, constant: -2),
            hintLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            hintLabel.widthAnchor.constraint(equalToConstant: 38)
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
    var tool: Tool = .pen { didSet { window?.invalidateCursorRects(for: self) } }
    var whiteboard = true { didSet { needsDisplay = true } }
    var lineWidth: CGFloat = 4
    var fontSize: CGFloat = 26
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
        if tool == .text {
            beginText(at: point(event))
            return
        }
        draft = Mark(tool: tool, points: [point(event)], width: lineWidth, color: red)
        needsDisplay = true
    }

    func moveDraft(_ event: NSEvent) {
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

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
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

        styleButton = compactButton("样式", symbol: "slider.horizontal.3", key: "4/26",
                                    action: #selector(showStyles))
        styleButton.setAccessibilityLabel("样式与快捷键说明")
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
        controller.view = GlassSurface(frame: NSRect(x: 0, y: 0, width: 238, height: 276))
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: controller.view.topAnchor, constant: 16)
        ])
        let heading = NSTextField(labelWithString: "样式")
        heading.font = .systemFont(ofSize: 14, weight: .semibold)
        stack.addArrangedSubview(heading)
        let widths = NSSegmentedControl(labels: ["细 2", "中 4", "粗 8"], trackingMode: .selectOne,
                                        target: self, action: #selector(changeWidth(_:)))
        widths.selectedSegment = 1
        widths.setAccessibilityLabel("线条粗细")
        addWide(widths, to: stack, height: 28)
        let row = NSStackView()
        row.distribution = .fillEqually
        row.addArrangedSubview(NSTextField(labelWithString: "文字大小"))
        let sizes = NSPopUpButton()
        sizes.addItems(withTitles: ["18 pt", "26 pt", "36 pt", "48 pt", "64 pt"])
        sizes.selectItem(at: 1)
        sizes.target = self
        sizes.action = #selector(changeFont(_:))
        sizes.setAccessibilityLabel("文字大小")
        row.addArrangedSubview(sizes)
        addWide(row, to: stack, height: 28)
        let font = NSTextField(labelWithString: "红色 · 等宽无衬线")
        font.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        font.textColor = canvas.red
        stack.addArrangedSubview(font)
        addSeparator(to: stack)
        let help = NSTextField(wrappingLabelWithString:
            "C 清空 · X 清空并退出\nShift：正方形 / 约束直线\n⌘Z 撤销 · ⌘⇧Z 重做\nEnter 换行 · ⌘Enter 完成文字\nEsc 取消文字\n\n快捷键仅在白板处于前台时生效。透明模式选 V，可操作下方应用。")
        help.font = .systemFont(ofSize: 12)
        help.textColor = .secondaryLabelColor
        addWide(help, to: stack)
        controller.view.layoutSubtreeIfNeeded()
        stylePopover = NSPopover()
        stylePopover.appearance = NSAppearance(named: .darkAqua)
        stylePopover.behavior = .transient
        stylePopover.contentViewController = controller
        stylePopover.contentSize = NSSize(width: 238, height: stack.fittingSize.height + 32)
    }

    @objc func showStyles() {
        if stylePopover.isShown { stylePopover.performClose(nil); return }
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
    }

    func updateButtons() {
        for b in toolButtons {
            b.state = b.tag == canvas.tool.rawValue ? .on : .off
            b.needsDisplay = true
        }
        undoButton?.isEnabled = !canvas.undoSteps.isEmpty
        redoButton?.isEnabled = !canvas.redoSteps.isEmpty
        styleButton?.keyHint = "\(Int(canvas.lineWidth))/\(Int(canvas.fontSize))"
        styleButton?.toolTip = "样式：线宽 \(Int(canvas.lineWidth)) pt / 字号 \(Int(canvas.fontSize)) pt；点击设置及查看快捷键"
        styleButton?.setAccessibilityLabel("样式：线宽 \(Int(canvas.lineWidth))，字号 \(Int(canvas.fontSize))。点击展开")
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
            .credits: NSAttributedString(string: "画笔 · 直线 · 方形 · 红色等宽文字\nZ 粘贴文字，C 清空，X 清空并退出。\n本地运行，无联网、录屏或辅助功能权限要求。")
        ])
    }

    func handleKey(_ event: NSEvent) -> NSEvent? {
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
        case 53: canvas.draft = nil; canvas.needsDisplay = true; return nil
        default: return event
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        // Switching apps restores normal desktop interaction without losing drawings.
        canvas.draft = nil
        if interactingWithDesktop { return }
        drawingWindow.orderOut(nil)
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        guard drawingWindow != nil else { return }
        if interactingWithDesktop {
            drawingWindow.orderFrontRegardless()
            palette.orderFrontRegardless()
            return
        }
        drawingWindow.makeKeyAndOrderFront(nil)
        palette.orderFrontRegardless()
        drawingWindow.makeFirstResponder(canvas.editor ?? canvas)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        focusCanvas()
        palette.orderFrontRegardless()
        return true
    }
    @objc func screenChanged() {
        guard let screen = drawingWindow.screen ?? NSScreen.main else { return }
        drawingWindow.setFrame(screen.visibleFrame, display: true)
        palette.setFrameTopLeftPoint(NSPoint(x: screen.visibleFrame.minX + 20, y: screen.visibleFrame.maxY - 24))
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
