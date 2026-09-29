import AppKit

private final class ActionCounter: NSObject {
    var count = 0
    @objc func clicked(_ sender: Any?) { count += 1 }
}

func runRegressionTests() {
    setbuf(stdout, nil)
    let icon = NSImage(contentsOfFile: "assets/AppIcon.icns")
    precondition(icon?.isValid == true, "The bundled application icon must decode on macOS")
    let artwork = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: "assets/AppIcon.png")))!
    precondition(artwork.pixelsWide == 1024 && artwork.pixelsHigh == 1024 && artwork.hasAlpha)
    precondition(artwork.colorAt(x: 0, y: 0)!.alphaComponent == 0)
    print("PASS: macOS application icon and transparent 1024px artwork")
    NSApp.appearance = NSAppearance(named: .aqua)
    let delegate = AppDelegate()
    delegate.canvas = Canvas(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
    delegate.makePalette(visibleFrame: NSRect(x: 0, y: 0, width: 1280, height: 800))
    delegate.drawingWindow = DrawingWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
                                            styleMask: [.borderless], backing: .buffered, defer: false)
    for whiteboard in [true, false, true, false, true] {
        delegate.canvas.whiteboard = whiteboard
        delegate.updateWindowLevels()
        precondition(delegate.palette.level.rawValue > delegate.drawingWindow.level.rawValue)
        precondition(delegate.drawingWindow.level == (whiteboard ? .normal : .floating))
    }
    precondition(delegate.styleButton.caption == "样式和工具" && delegate.styleButton.keyHint.isEmpty)
    print("PASS: toolbar stays at a higher window level in whiteboard and transparent modes")
    let root = delegate.palette.contentView!
    root.layoutSubtreeIfNeeded()

    let glass = root as! GlassSurface
    precondition(glass.material == .hudWindow && glass.blendingMode == .behindWindow)
    precondition(glass.state == .active && !delegate.palette.isOpaque)
    precondition(delegate.palette.backgroundColor == .clear && delegate.palette.alphaValue == 1)
    precondition(delegate.palette.titlebarAppearsTransparent)
    precondition(delegate.stylePopover.contentViewController?.view is GlassSurface)
    print("PASS: glass toolbar and styles; native backdrop blur; controls retain full opacity")

    func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
    let buttons = descendants(root).compactMap { $0 as? PaletteButton }
    precondition(buttons.count == 9)
    let counter = ActionCounter()
    let clear = buttons.first { $0.caption == "清空" }!
    precondition(clear.keyHint == "C" && clear.action == #selector(AppDelegate.clearDrawing))
    clear.target = counter
    clear.action = #selector(ActionCounter.clicked(_:))
    for expected in 1...12 {
        clear.performClick(nil)
        precondition(counter.count == expected)
        precondition(!clear.isHighlighted && !clear.showsSelection)
    }
    let pen = buttons.first { $0.caption == "画笔" }!
    pen.target = counter
    pen.action = #selector(ActionCounter.clicked(_:))
    pen.state = .off
    pen.performClick(nil)
    precondition(pen.state == .on && pen.showsSelection)

    for button in buttons {
        let labels = button.subviews.compactMap { $0 as? NSTextField }
        precondition(labels.count == 2)
        for label in labels {
            precondition(!label.isEditable && !label.isSelectable && !label.drawsBackground)
            precondition(label.frame.minX >= 0 && label.frame.maxX <= button.bounds.width)
            let center = NSPoint(x: label.frame.midX, y: label.frame.midY)
            precondition(button.hitTest(button.convert(center, to: button.superview)) === button)
        }
    }
    print("PASS: clear fires once per click; tools retain selection; labels forward clicks")

    // Render the real palette, including all native labels, not just draw(_:).
    // Alternate tools, appearance, enabled state and hint text under optimization.
    for iteration in 0..<2000 {
        autoreleasepool {
            delegate.canvas.tool = Tool.allCases[iteration % Tool.allCases.count]
            delegate.canvas.lineWidth = [2, 4, 8][iteration % 3]
            delegate.canvas.fontSize = [18, 26, 36, 48, 64][iteration % 5]
            delegate.updateButtons()
            clear.isEnabled = iteration % 7 != 0
            clear.highlight(iteration % 3 == 0)
            if iteration % 100 == 0 {
                root.appearance = NSAppearance(named: iteration % 200 == 0 ? .aqua : .darkAqua)
            }
            root.layoutSubtreeIfNeeded()
            let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds)!
            root.cacheDisplay(in: root.bounds, to: rep)
            precondition(rep.pixelsWide > 0 && rep.pixelsHigh > 0)
        }
    }
    clear.isEnabled = true
    clear.highlight(false)
    root.appearance = NSAppearance(named: .darkAqua)
    delegate.canvas.tool = .pen
    delegate.updateButtons()
    let preview = root.bitmapImageRepForCachingDisplay(in: root.bounds)!
    root.cacheDisplay(in: root.bounds, to: preview)
    try! preview.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "work/palette-1.3.png"))
    print("PASS: 2,000 complete toolbar renders with tool, style, enabled and appearance changes")

    let canvas = delegate.canvas!
    canvas.append(Mark(tool: .pen, points: [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 40)]))
    canvas.tool = .pointer
    canvas.clear()
    precondition(canvas.marks.isEmpty)
    canvas.undoAction()
    precondition(canvas.marks.count == 1, "Undo must restore clear while in pointer mode")
    canvas.redoAction()
    precondition(canvas.marks.isEmpty)
    let mouse = NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: 30, y: 30),
                                  modifierFlags: [], timestamp: 0, windowNumber: 0,
                                  context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    canvas.mouseDown(with: mouse)
    precondition(canvas.draft == nil, "Pointer must never begin a drawing")
    for tool in [Tool.pen, .line, .rectangle, .text] {
        canvas.append(Mark(tool: tool, points: [CGPoint(x: 20, y: 20), CGPoint(x: 80, y: 80)],
                           text: "红色等宽文字 ABC 123\n第二行"))
    }
    for whiteboard in [true, false] {
        canvas.whiteboard = whiteboard
        for _ in 0..<100 {
            autoreleasepool {
                let rep = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
                canvas.cacheDisplay(in: canvas.bounds, to: rep)
            }
        }
    }
    print("PASS: pointer, clear/undo/redo and 200 white/transparent canvas renders")

    let pureBlue = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
    delegate.setStrokeColor(pureBlue)
    precondition(RGBValue(canvas.strokeColor)!.text == "rgb(0, 0, 255)")
    canvas.tool = .pen
    canvas.mouseDown(with: mouse)
    canvas.mouseUp(with: mouse)
    precondition(RGBValue(canvas.marks.last!.color)!.hex == "#0000FF")
    let oldMark = canvas.marks.last!
    delegate.strokeRGBFields[0].stringValue = "256"
    delegate.applyRGB()
    precondition(RGBValue(canvas.strokeColor)!.hex == "#0000FF", "Invalid RGB must not change color")
    delegate.strokeRGBFields[0].stringValue = "255"
    delegate.strokeRGBFields[1].stringValue = "128"
    delegate.strokeRGBFields[2].stringValue = "0"
    delegate.applyRGB()
    precondition(RGBValue(canvas.strokeColor)!.text == "rgb(255, 128, 0)")
    precondition(RGBValue(oldMark.color)!.hex == "#0000FF", "Existing strokes retain their color")
    canvas.beginText(at: CGPoint(x: 30, y: 30))
    canvas.editor!.string = "颜色测试"
    canvas.commitText()
    precondition(RGBValue(canvas.marks.last!.color) == RGBValue(canvas.red), "Text stays red")
    precondition(delegate.recordSample(NSColor(srgbRed: 0.5, green: 1, blue: 0, alpha: 1)))
    precondition(delegate.sampledRGB!.text == "rgb(128, 255, 0)")
    let previousSample = delegate.sampledRGB
    precondition(!delegate.recordSample(nil) && delegate.sampledRGB == previousSample)
    delegate.useSampleColor()
    precondition(RGBValue(canvas.strokeColor) == previousSample)
    precondition(delegate.copyRGBItem.isEnabled && delegate.useSampleItem.isEnabled)
    precondition(RGBValue(NSColor(white: 0.5, alpha: 1)) != nil)
    print("PASS: RGB color input, invalid values, immutable strokes, red text, sampling/cancel and use-color")

    let m1 = PixelMeasurement(start: .zero, end: CGPoint(x: 3, y: 4), scale: 1)
    let m2 = PixelMeasurement(start: CGPoint(x: 3, y: 4), end: .zero, scale: 2)
    precondition(m1.distance == 5 && m2.distance == 10 && m2.dx == 6 && m2.dy == 8)
    canvas.tool = .ruler
    let historyCount = canvas.undoSteps.count
    let marksCount = canvas.marks.count
    canvas.mouseDown(with: mouse)
    let measurementStart = canvas.measurement!.start
    canvas.updateMeasurement(to: CGPoint(x: measurementStart.x + 3, y: measurementStart.y + 4))
    precondition(canvas.measurement!.distance == 5)
    canvas.mouseUp(with: mouse)
    precondition(!canvas.measuring && canvas.measurement != nil)
    precondition(canvas.marks.count == marksCount && canvas.undoSteps.count == historyCount)
    let rulerBitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
    canvas.cacheDisplay(in: canvas.bounds, to: rulerBitmap)
    canvas.tool = .pen
    precondition(canvas.measurement == nil)
    canvas.tool = .ruler
    canvas.mouseDown(with: mouse)
    canvas.clear()
    precondition(canvas.measurement == nil && !canvas.measuring)
    print("PASS: 1x/2x pixel distances, reversed drag, ruler rendering, no undo pollution and cleanup")

    delegate.setStrokeColor(canvas.red)
    let toolsRoot = delegate.stylePopover.contentViewController!.view
    toolsRoot.layoutSubtreeIfNeeded()
    precondition(delegate.advancedBody.isHidden && delegate.toolsBody.isHidden)
    precondition(toolsRoot.bounds.height < 370, "Default panel must be compact")
    let compactHeight = toolsRoot.bounds.height
    let compactBitmap = toolsRoot.bitmapImageRepForCachingDisplay(in: toolsRoot.bounds)!
    toolsRoot.cacheDisplay(in: toolsRoot.bounds, to: compactBitmap)
    try! compactBitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "work/tools-1.6-compact.png"))
    delegate.toggleAdvanced()
    delegate.toggleTools()
    precondition(!delegate.advancedBody.isHidden && !delegate.toolsBody.isHidden)
    precondition(toolsRoot.bounds.height > compactHeight)
    delegate.hexField.stringValue = "#3366cc"
    delegate.applyHex()
    precondition(RGBValue(canvas.strokeColor)!.text == "rgb(51, 102, 204)")
    delegate.hexField.stringValue = "#12#456"
    delegate.applyHex()
    precondition(RGBValue(canvas.strokeColor)!.hex == "#3366CC" && !delegate.colorMessage.isHidden)
    delegate.widthSlider.doubleValue = 7.7
    delegate.changeWidthSlider(delegate.widthSlider)
    precondition(canvas.lineWidth == 8 && delegate.strokePreview.width == 8)
    for view in descendants(toolsRoot) where view is NSControl && !view.isHiddenOrHasHiddenAncestor {
        let rect = view.convert(view.bounds, to: toolsRoot)
        precondition(rect.minY >= -1 && rect.maxY <= toolsRoot.bounds.height + 1,
                     "Tool controls must fit inside the panel")
    }
    let toolsBitmap = toolsRoot.bitmapImageRepForCachingDisplay(in: toolsRoot.bounds)!
    toolsRoot.cacheDisplay(in: toolsRoot.bounds, to: toolsBitmap)
    try! toolsBitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "work/tools-1.6-expanded.png"))
    print("PASS: collapsed \(Int(compactHeight))pt panel, disclosures, HEX validation and stroke preview")

    let source = try! String(contentsOfFile: "native/main.swift", encoding: .utf8)
    precondition(source.contains("colorSampler.show"))
    for forbidden in ["CGRequestScreenCaptureAccess", "CGPreflightScreenCaptureAccess", "ScreenCaptureKit"] {
        precondition(!source.contains(forbidden), "Native sampling must not request capture access")
    }
    print("PASS: native color sampler retained; no screen-capture permission request")
}
