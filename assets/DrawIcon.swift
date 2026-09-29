import AppKit

// Original, reproducible icon artwork. Coordinates are vector paths in a
// 1024-point square; every icon size is rendered directly from these paths.
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func roundRect(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func artwork() {
    let tile = roundRect(NSRect(x: 64, y: 64, width: 896, height: 896), 202)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0.03, 0.05, 0.09, 0.28)
    shadow.shadowBlurRadius = 22
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    color(0.10, 0.13, 0.18).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [color(0.12, 0.15, 0.21), color(0.27, 0.32, 0.40)])!
        .draw(in: tile, angle: 90)
    color(1, 1, 1, 0.20).setStroke()
    tile.lineWidth = 3
    tile.stroke()

    // A luminous glass board; a generous silhouette remains legible in the Dock.
    let board = roundRect(NSRect(x: 203, y: 238, width: 591, height: 548), 65)
    NSGradient(colors: [color(0.60, 0.69, 0.80, 0.06), color(0.88, 0.94, 1, 0.24)])!
        .draw(in: board, angle: 75)
    color(0.90, 0.96, 1, 0.90).setStroke()
    board.lineWidth = 18
    board.stroke()
    let topEdge = NSBezierPath()
    topEdge.move(to: NSPoint(x: 268, y: 744))
    topEdge.line(to: NSPoint(x: 580, y: 744))
    topEdge.lineWidth = 5
    topEdge.lineCapStyle = .round
    color(1, 1, 1, 0.22).setStroke()
    topEdge.stroke()

    // A single freehand gesture, not a letter or a third-party logo.
    let ink = NSBezierPath()
    ink.move(to: NSPoint(x: 282, y: 402))
    ink.curve(to: NSPoint(x: 370, y: 505), controlPoint1: NSPoint(x: 319, y: 530),
              controlPoint2: NSPoint(x: 408, y: 585))
    ink.curve(to: NSPoint(x: 408, y: 386), controlPoint1: NSPoint(x: 328, y: 412),
              controlPoint2: NSPoint(x: 334, y: 332))
    ink.curve(to: NSPoint(x: 540, y: 395), controlPoint1: NSPoint(x: 466, y: 446),
              controlPoint2: NSPoint(x: 465, y: 364))
    ink.lineWidth = 35
    ink.lineCapStyle = .round
    ink.lineJoinStyle = .round
    color(1, 0.40, 0.45).setStroke()
    ink.stroke()

    // The pencil bridges the board's edge to suggest desktop annotation.
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: 546, yBy: 383)
    transform.rotate(byDegrees: -40)
    transform.concat()
    let body = roundRect(NSRect(x: -39, y: 96, width: 78, height: 346), 27)
    NSGraphicsContext.saveGraphicsState()
    let pencilShadow = NSShadow()
    pencilShadow.shadowColor = color(0.02, 0.03, 0.05, 0.4)
    pencilShadow.shadowBlurRadius = 16
    pencilShadow.shadowOffset = NSSize(width: -5, height: -7)
    pencilShadow.set()
    color(1, 0.40, 0.45).setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [color(0.92, 0.23, 0.32), color(1, 0.54, 0.56)])!
        .draw(in: body, angle: 0)
    color(1, 0.86, 0.84, 0.6).setFill()
    roundRect(NSRect(x: -25, y: 142, width: 7, height: 244), 3.5).fill()
    color(0.97, 0.98, 1).setFill()
    NSRect(x: -39, y: 352, width: 78, height: 18).fill()
    let nib = NSBezierPath()
    nib.move(to: NSPoint(x: -39, y: 111))
    nib.line(to: NSPoint(x: 39, y: 111))
    nib.line(to: NSPoint(x: 0, y: 8))
    nib.close()
    color(0.96, 0.97, 1).setFill()
    nib.fill()
    let tip = NSBezierPath()
    tip.move(to: NSPoint(x: -12, y: 40))
    tip.line(to: NSPoint(x: 12, y: 40))
    tip.line(to: NSPoint(x: 0, y: 8))
    tip.close()
    color(1, 0.40, 0.45).setFill()
    tip.fill()
    NSGraphicsContext.restoreGraphicsState()
}

func render(_ size: Int, to url: URL) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB,
                                  bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    artwork()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("work/AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try render(size, to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2, to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try render(1024, to: root.appendingPathComponent("assets/AppIcon.png"))

// ICNS is a big-endian container of named image representations. Packaging the
// PNG chunks directly also works in headless environments without icon services.
func uint32(_ value: Int) -> Data {
    var word = UInt32(value).bigEndian
    return withUnsafeBytes(of: &word) { Data($0) }
}
var chunks = Data()
for (type, file) in [
    ("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"), ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png"), ("ic11", "icon_16x16@2x.png"),
    ("ic12", "icon_32x32@2x.png"), ("ic13", "icon_128x128@2x.png"),
    ("ic14", "icon_256x256@2x.png")
] {
    let png = try Data(contentsOf: iconset.appendingPathComponent(file))
    chunks.append(Data(type.utf8))
    chunks.append(uint32(png.count + 8))
    chunks.append(png)
}
var icon = Data("icns".utf8)
icon.append(uint32(chunks.count + 8))
icon.append(chunks)
let iconURL = root.appendingPathComponent("assets/AppIcon.icns")
try icon.write(to: iconURL)
precondition(NSImage(contentsOf: iconURL)?.isValid == true, "macOS must be able to decode the icon")
print("Rendered artwork, macOS icon representations and validated AppIcon.icns")
