import AppKit

final class ColorChipButton: NSButton {
    var color: NSColor = .systemRed { didSet { needsDisplay = true } }
    var selected = false { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 4, dy: 4)
        color.setFill()
        NSBezierPath(ovalIn: rect).fill()
        NSColor.white.withAlphaComponent(0.25).setStroke()
        let edge = NSBezierPath(ovalIn: rect)
        edge.lineWidth = 1
        edge.stroke()
        if selected || isHighlighted {
            NSColor.white.setStroke()
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
            ring.lineWidth = 2
            ring.stroke()
        }
    }
}

final class StrokePreview: NSView {
    var color: NSColor = .systemRed { didSet { needsDisplay = true } }
    var width: CGFloat = 4 { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 8, y: bounds.midY))
        path.line(to: NSPoint(x: bounds.width - 8, y: bounds.midY))
        path.lineCapStyle = .round
        path.lineWidth = width
        color.setStroke()
        path.stroke()
    }
}
