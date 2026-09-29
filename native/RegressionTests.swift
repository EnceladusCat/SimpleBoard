import AppKit

private final class ActionCounter: NSObject {
    var count = 0
    @objc func clicked(_ sender: Any?) { count += 1 }
}

func runRegressionTests() {
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
}
