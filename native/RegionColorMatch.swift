import AppKit
import ScreenCaptureKit

// Pure image processing. Input/output are in-memory sRGB; there is no file or
// network access here. Re-adjusting tolerance always uses this same snapshot.
struct MatchSnapshot {
    let width: Int
    let height: Int
    let rgba: [UInt8]
    static let pixelLimit = 16_000_000

    init?(image: CGImage) {
        let w = image.width, h = image.height
        guard w > 0, h > 0, w <= Self.pixelLimit / h else { return nil }
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let converted = data.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: w, height: h))
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard converted else { return nil }
        width = w; height = h; rgba = data
    }

    func highlight(target: RGBValue, tolerance: Int) -> (image: CGImage, count: Int)? {
        let tolerance = max(0, min(40, tolerance))
        var output = rgba
        var count = 0
        for i in stride(from: 0, to: output.count, by: 4) {
            let matches = abs(Int(rgba[i]) - target.r) <= tolerance &&
                abs(Int(rgba[i + 1]) - target.g) <= tolerance &&
                abs(Int(rgba[i + 2]) - target.b) <= tolerance
            if matches { count += 1 }
            else {
                for channel in 0..<3 { output[i + channel] = UInt8((Double(rgba[i + channel]) * 0.22).rounded()) }
            }
        }
        guard let provider = CGDataProvider(data: Data(output) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        return (image, count)
    }
}

final class MatchSelectionView: NSView {
    var selected: ((CGRect) -> Void)?
    private var start: CGPoint?
    private var selection = CGRect.zero

    static func selection(from start: CGPoint, to end: CGPoint, bounds: CGRect) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y)).intersection(bounds)
    }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        selection = .zero
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        selection = Self.selection(from: start, to: convert(event.locationInWindow, from: nil), bounds: bounds)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        start = nil
        guard selection.width >= 4, selection.height >= 4, let window else { return }
        selected?(window.convertToScreen(convert(selection, to: nil)))
    }
    override func draw(_ dirtyRect: NSRect) {
        guard !selection.isEmpty else { return }
        NSColor.white.setStroke()
        let outline = NSBezierPath(rect: selection.insetBy(dx: 1, dy: 1))
        outline.lineWidth = 2
        outline.stroke()
        NSColor.black.setStroke()
        let inner = NSBezierPath(rect: selection.insetBy(dx: 3, dy: 3))
        inner.lineWidth = 1
        inner.stroke()
    }
}

// Exactly one capture per selection. No SCStream, frame timer, clipboard or
// screen enumeration capture. Requires macOS 15.2's region-only screenshot API.
final class RegionColorMatch: NSObject {
    enum Phase { case idle, selecting, capturing, ready, displaying }
    private(set) var phase: Phase = .idle
    private(set) var captureDenied = false
    var active: Bool { phase != .idle }
    private var completion: ((String?) -> Void)?
    private var token = UUID()
    private var selectionWindows: [NSWindow] = []
    private var resultWindow: NSWindow?
    private var imageView: NSImageView?
    private var hud: NSPanel?
    private var statusLabel: NSTextField?
    private var toleranceLabel: NSTextField?
    private var slider: NSSlider?
    private var snapshot: MatchSnapshot?
    private var target: RGBValue?
    private var eventMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var renderBusy = false
    private var wantedTolerance = 12
    private var resultRect = CGRect.zero
    private let worker = DispatchQueue(label: "local.simpleboard.color-match", qos: .userInitiated)
    typealias Screenshot = (CGRect, @escaping (CGImage?, Error?) -> Void) -> Void
    private let screenshot: Screenshot
    private let primaryTop: () -> CGFloat?
    private var captureIssued = false

    init(screenshot: @escaping Screenshot = RegionColorMatch.captureOnce,
         primaryTop: @escaping () -> CGFloat? = { NSScreen.screens.first?.frame.maxY }) {
        self.screenshot = screenshot
        self.primaryTop = primaryTop
        super.init()
    }

    private static func captureOnce(_ rect: CGRect, completion: @escaping (CGImage?, Error?) -> Void) {
        if #available(macOS 15.2, *) {
            // Let the actual OS operation enforce consent. A separate legacy
            // preflight is not authoritative for this single-shot API.
            SCScreenshotManager.captureImage(in: rect, completionHandler: completion)
        }
    }

    static func isPermissionDenial(_ error: Error?) -> Bool {
        guard let error = error as NSError? else { return false }
        return error.domain == SCStreamErrorDomain && error.code == SCStreamError.Code.userDeclined.rawValue
    }

    private func resignActive() {
        // Consent may move focus away while the OS owns an in-flight request.
        // Do not cancel it or show a result over another app. Before the read
        // is issued, and while selecting/displaying, switching apps cancels.
        if (phase == .capturing && captureIssued) || phase == .ready { return }
        finish()
    }

    // Called only by the user's menu-bar/reopen action, never by a capture callback.
    func resume() {
        guard active else { return }
        NSApp.activate(ignoringOtherApps: true)
        presentReadyResult()
    }

    private func presentReadyResult() {
        guard phase == .ready, NSApp.isActive else { return }
        phase = .displaying
        makeResultWindow()
        render()
    }

    static func captureRect(_ appKitRect: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: appKitRect.minX, y: primaryTop - appKitRect.maxY,
               width: appKitRect.width, height: appKitRect.height)
    }

    func begin(target: RGBValue, completion: @escaping (String?) -> Void) {
        guard !active else { return }
        guard #available(macOS 15.2, *) else { completion("区域配对需要 macOS 15.2 或更新版本；原生吸色仍可使用。"); return }
        captureDenied = false
        captureIssued = false
        phase = .selecting
        token = UUID()
        self.target = target
        self.completion = completion
        wantedTolerance = 12
        for screen in NSScreen.screens {
            let window = DrawingWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.title = "框选颜色配对区域"
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            // Nonzero alpha allows AppKit to receive drags over otherwise clear pixels.
            window.backgroundColor = NSColor.black.withAlphaComponent(0.001)
            window.hasShadow = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = MatchSelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.autoresizingMask = [.width, .height]
            view.selected = { [weak self] rect in self?.capture(rect, scale: screen.backingScaleFactor) }
            let hint = NSTextField(labelWithString: "拖动框选配对区域 · Esc 取消")
            hint.font = .systemFont(ofSize: 14, weight: .medium)
            hint.textColor = .white
            hint.drawsBackground = true
            hint.backgroundColor = .black.withAlphaComponent(0.8)
            hint.frame = NSRect(x: 28, y: screen.frame.height - 90, width: 320, height: 28)
            view.addSubview(hint)
            window.contentView = view
            selectionWindows.append(window)
            window.orderFrontRegardless()
        }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.active else { return event }
            if event.type == .rightMouseDown || event.keyCode == 53 { self.finish(); return nil }
            if event.type == .keyDown {
                if event.modifierFlags.contains(.command) {
                    // Retain explicit quit/collapse, but don't let hidden canvas
                    // commands run while the selection/snapshot owns the keyboard.
                    return [12, 4].contains(event.keyCode) ? event : nil
                }
                if self.phase != .displaying { return nil }
            }
            return event
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.resignActive() })
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.presentReadyResult() })
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.finish() })
        NSApp.activate(ignoringOtherApps: true)
        let key = selectionWindows.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? selectionWindows.first
        key?.makeKeyAndOrderFront(nil)
        key?.makeFirstResponder(key?.contentView)
    }

    private func capture(_ rect: CGRect, scale: CGFloat) {
        guard phase == .selecting else { return }
        guard rect.width * rect.height * scale * scale <= CGFloat(MatchSnapshot.pixelLimit) else {
            finish(error: "选区过大，请缩小后重试（最多 1600 万像素）。"); return
        }
        guard let primaryTop = primaryTop() else { finish(error: "无法定位屏幕。"); return }
        phase = .capturing
        resultRect = rect
        selectionWindows.forEach { $0.orderOut(nil) }
        selectionWindows.removeAll()
        let generation = token
        let quartzRect = Self.captureRect(rect, primaryTop: primaryTop)
        // Let WindowServer remove the selector before the one and only read.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.token == generation, self.phase == .capturing else { return }
            self.captureIssued = true
            self.screenshot(quartzRect) { [weak self] image, error in
                DispatchQueue.main.async {
                    guard let self, self.token == generation, self.phase == .capturing else { return }
                    guard let image, error == nil else {
                        let denied = Self.isPermissionDenial(error)
                        let detail = (error as NSError?).map { "\($0.domain) / \($0.code)" } ?? "未返回图像"
                        self.finish(error: denied
                            ? "系统未允许本次选区读取。可在系统设置中允许白板；若已允许，请退出并重新打开白板。"
                            : "选区读取失败（\(detail)）。本次已结束，没有自动重试。",
                            permissionDenied: denied)
                        return
                    }
                    self.worker.async { [weak self] in
                        let snapshot = MatchSnapshot(image: image)
                        DispatchQueue.main.async {
                            guard let self, self.token == generation, self.phase == .capturing else { return }
                            guard let snapshot else { self.finish(error: "选区过大或图像无法读取。"); return }
                            self.snapshot = snapshot
                            self.phase = .ready
                            self.presentReadyResult()
                        }
                    }
                }
            }
        }
    }

    private func makeResultWindow() {
        let window = DrawingWindow(contentRect: resultRect, styleMask: .borderless, backing: .buffered, defer: false)
        window.title = "颜色配对 · 单次快照"
        window.isReleasedWhenClosed = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        let image = NSImageView(frame: NSRect(origin: .zero, size: resultRect.size))
        image.imageScaling = .scaleAxesIndependently
        image.setAccessibilityLabel("颜色配对快照：匹配颜色保留亮度，其余压暗；Esc 退出")
        window.contentView = image
        imageView = image
        resultWindow = window

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 310, height: 100), styleMask: .borderless, backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        let root = GlassSurface(frame: NSRect(x: 0, y: 0, width: 310, height: 100))
        panel.contentView = root
        let title = NSTextField(labelWithString: target?.text ?? "颜色配对")
        title.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        title.frame = NSRect(x: 12, y: 73, width: 242, height: 18)
        root.addSubview(title)
        let close = NSButton(title: "×", target: self, action: #selector(closeResult))
        close.frame = NSRect(x: 270, y: 70, width: 28, height: 24)
        close.bezelStyle = .recessed
        close.setAccessibilityLabel("结束颜色配对")
        root.addSubview(close)
        let label = NSTextField(labelWithString: "容差 ±12")
        label.font = .systemFont(ofSize: 11)
        label.frame = NSRect(x: 12, y: 43, width: 76, height: 20)
        label.toolTip = "每个 sRGB 通道允许的差值；0 为精确匹配。只重算当前快照，不会再次读取屏幕。"
        root.addSubview(label)
        toleranceLabel = label
        let slider = NSSlider(value: 12, minValue: 0, maxValue: 40, target: self, action: #selector(changeTolerance(_:)))
        slider.frame = NSRect(x: 94, y: 42, width: 204, height: 22)
        slider.isContinuous = true
        slider.setAccessibilityLabel("颜色匹配容差，每个通道 0 至 40")
        root.addSubview(slider)
        self.slider = slider
        let status = NSTextField(labelWithString: "正在匹配… · Esc 退出")
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.frame = NSRect(x: 12, y: 13, width: 286, height: 20)
        root.addSubview(status)
        statusLabel = status
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: resultRect.midX, y: resultRect.midY)) }) {
            let visible = screen.visibleFrame
            let x = max(visible.minX, min(resultRect.minX, visible.maxX - 310))
            let y = resultRect.minY - 108 >= visible.minY ? resultRect.minY - 108 : min(visible.maxY - 100, resultRect.maxY + 8)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        hud = panel
    }

    @objc private func changeTolerance(_ sender: NSSlider) {
        wantedTolerance = Int(sender.doubleValue.rounded())
        sender.integerValue = wantedTolerance
        toleranceLabel?.stringValue = "容差 ±\(wantedTolerance)"
        render()
    }

    private func render() {
        guard phase == .displaying, !renderBusy, let snapshot, let target else { return }
        renderBusy = true
        let generation = token, tolerance = wantedTolerance
        statusLabel?.stringValue = "正在匹配… · Esc 退出"
        worker.async { [weak self] in
            let result = snapshot.highlight(target: target, tolerance: tolerance)
            DispatchQueue.main.async {
                guard let self, self.token == generation, self.phase == .displaying else { return }
                self.renderBusy = false
                if tolerance != self.wantedTolerance { self.render(); return }
                guard let result else { self.finish(error: "无法生成配对结果。"); return }
                let firstPresentation = self.imageView?.image == nil
                self.imageView?.image = NSImage(cgImage: result.image, size: self.resultRect.size)
                self.statusLabel?.stringValue = result.count == 0 ? "未匹配到颜色 · 调整容差 · Esc 退出" : "匹配 \(result.count) 像素 · 单次快照 · Esc 退出"
                if firstPresentation {
                    self.resultWindow?.makeKeyAndOrderFront(nil)
                    self.hud?.orderFrontRegardless()
                }
            }
        }
    }

    @objc private func closeResult() { finish() }

    #if REGRESSION_TESTS
    // Use only synthetic/file pixels to exercise result layout and cancellation;
    // this path is absent from release builds and never requests screen access.
    func regressionPrepareResult(snapshot: MatchSnapshot, target: RGBValue, rect: CGRect) -> NSView {
        phase = .displaying
        token = UUID()
        self.snapshot = snapshot
        self.target = target
        resultRect = rect
        makeResultWindow()
        return hud!.contentView!
    }
    var regressionResultFrame: CGRect? { resultWindow?.frame }
    var regressionHasImageState: Bool { snapshot != nil || imageView != nil || resultWindow != nil || hud != nil }
    func regressionQueueRender() { render() }
    func regressionSelect(target: RGBValue, rect: CGRect, completion: @escaping (String?) -> Void) {
        phase = .selecting
        token = UUID()
        self.target = target
        self.completion = completion
        captureDenied = false
        captureIssued = false
        capture(rect, scale: 1)
    }
    func regressionResignActive() { resignActive() }
    #endif

    func finish(error: String? = nil, permissionDenied: Bool = false, notify: Bool = true) {
        guard active else { return }
        captureDenied = permissionDenied
        captureIssued = false
        phase = .idle
        token = UUID()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        selectionWindows.forEach { $0.orderOut(nil) }
        selectionWindows.removeAll()
        resultWindow?.orderOut(nil)
        hud?.orderOut(nil)
        imageView?.image = nil
        imageView = nil; resultWindow = nil; hud = nil
        snapshot = nil; target = nil; slider = nil; statusLabel = nil; toleranceLabel = nil
        renderBusy = false
        let callback = completion
        completion = nil
        if notify { callback?(error) }
    }
}
