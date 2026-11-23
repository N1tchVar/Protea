import AppKit

/// The scroll view that owns zoom. Pinch zooms everywhere; ⌘-scroll zooms around the pointer.
final class CanvasScrollView: NSScrollView {
    var onMagnify: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        hasHorizontalScroller = false
        hasVerticalScroller = false
        allowsMagnification = true
        minMagnification = 0.12
        maxMagnification = 2.5
        drawsBackground = true
        backgroundColor = Palette.canvas
        horizontalScrollElasticity = .allowed
        verticalScrollElasticity = .allowed
        contentView.postsBoundsChangedNotifications = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            let factor = exp(event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.01 : 0.08))
            let point = documentView?.convert(event.locationInWindow, from: nil) ?? .zero
            setMagnification(max(minMagnification, min(maxMagnification, magnification * factor)), centeredAt: point)
            onMagnify?()
            return
        }
        super.scrollWheel(with: event)
    }

    override func magnify(with event: NSEvent) {
        super.magnify(with: event)
        onMagnify?()
    }
}

/// The surface the panes live on: a quiet dot grid. Drag empty space to pan.
final class CanvasDocumentView: NSView {
    let workspaceID: UUID
    var onBackgroundClick: (() -> Void)?
    private var panStart: NSPoint?
    private var originStart: NSPoint = .zero

    init(workspaceID: UUID) {
        self.workspaceID = workspaceID
        super.init(frame: NSRect(origin: .zero, size: CanvasController.size))
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        Palette.canvas.setFill()
        dirtyRect.fill()

        // Keep the dot count sane when zoomed far out.
        let zoom = enclosingScrollView?.magnification ?? 1
        var spacing: CGFloat = 26
        while spacing * zoom < 13 { spacing *= 2 }
        let size = max(1.2, 1.6 / max(zoom, 0.6))
        let x0 = floor(dirtyRect.minX / spacing) * spacing
        let y0 = floor(dirtyRect.minY / spacing) * spacing
        var rects: [NSRect] = []
        rects.reserveCapacity(Int((dirtyRect.width / spacing + 2) * (dirtyRect.height / spacing + 2)))
        var y = y0
        while y <= dirtyRect.maxY {
            var x = x0
            while x <= dirtyRect.maxX {
                rects.append(NSRect(x: x - size / 2, y: y - size / 2, width: size, height: size))
                x += spacing
            }
            y += spacing
        }
        NSColor(red: 0.62, green: 0.75, blue: 1, alpha: 0.085).setFill()
        NSGraphicsContext.current?.cgContext.fill(rects)
    }

    override func mouseDown(with event: NSEvent) {
        onBackgroundClick?()
        panStart = event.locationInWindow
        originStart = enclosingScrollView?.contentView.bounds.origin ?? .zero
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = panStart, let sv = enclosingScrollView else { return }
        let z = sv.magnification
        let dx = (event.locationInWindow.x - start.x) / z
        let dy = (event.locationInWindow.y - start.y) / z
        sv.contentView.scroll(to: NSPoint(x: originStart.x - dx, y: originStart.y + dy))
        sv.reflectScrolledClipView(sv.contentView)
    }

    override func mouseUp(with event: NSEvent) {
        if panStart != nil { NSCursor.pop() }
        panStart = nil
    }

    override func resetCursorRects() {
        addCursorRect(visibleRect, cursor: .openHand)
    }
}

/// Owns the scroll view, one document per workspace, and every pane. Panes and their
/// processes stay alive when you switch workspaces; only the visible document changes.
@MainActor
final class CanvasController {
    static let size = NSSize(width: 24000, height: 16000)
    static let home = NSPoint(x: 9000, y: 6000)
    static let defaultPaneSize = NSSize(width: 640, height: 420)
    static let topInset: CGFloat = 64

    weak var store: AppStore?
    let scrollView = CanvasScrollView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
    private var documents: [UUID: CanvasDocumentView] = [:]
    private var panes: [UUID: PaneView] = [:]
    private var paneWorkspace: [UUID: UUID] = [:]
    private var currentWorkspace: UUID?
    private var cameraTimer: Timer?

    init() {
        scrollView.onMagnify = { [weak self] in self?.magnificationChanged() }
        NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.magnificationChanged() }
        }
    }

    // MARK: Workspaces

    func show(workspace ws: WorkspaceRecord) {
        currentWorkspace = ws.id
        let doc = documents[ws.id] ?? makeDocument(for: ws)
        scrollView.documentView = doc
        let center = ws.center ?? (ws.sessions.isEmpty ? CanvasController.home : union(ws.sessions.map(\.frame)).center)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if ws.center == nil && !ws.sessions.isEmpty {
                    self.overview(animated: false)
                } else {
                    self.setCamera(zoom: ws.zoom, center: center)
                }
            }
        }
    }

    func dropWorkspace(_ id: UUID) {
        documents[id]?.removeFromSuperview()
        documents[id] = nil
    }

    private func makeDocument(for ws: WorkspaceRecord) -> CanvasDocumentView {
        let doc = CanvasDocumentView(workspaceID: ws.id)
        doc.onBackgroundClick = { [weak self] in self?.setFocused(nil) }
        documents[ws.id] = doc
        for record in ws.sessions { addPane(record, to: ws.id, animated: false) }
        return doc
    }

    // MARK: Panes

    @discardableResult
    func addPane(_ record: SessionRecord, to workspaceID: UUID, animated: Bool) -> PaneView? {
        guard let doc = documents[workspaceID] else { return nil }
        let pane = PaneView(record: record, agent: Agent.with(id: record.agentID))
        pane.frame = record.frame
        pane.onFocus = { [weak self] id in self?.setFocused(id) }
        pane.onMoved = { [weak self] id, frame in self?.store?.paneMoved(id, frame: frame) }
        pane.onZoom = { [weak self] id in self?.focusPane(id, zoom: true) }
        pane.onClose = { [weak self] id in self?.store?.close(id) }
        pane.onRestart = { [weak self] id in self?.restartPane(id) }
        pane.onRename = { [weak self] id, title in self?.store?.rename(id, to: title) }
        pane.onTopic = { [weak self] id, topic in self?.store?.topicChanged(id, to: topic) }
        pane.onCwd = { [weak self] id, path in self?.store?.cwdChanged(id, to: path) }
        panes[record.id] = pane
        paneWorkspace[record.id] = workspaceID
        doc.addSubview(pane)
        pane.launch()
        if animated {
            pane.alphaValue = 0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.28
                pane.animator().alphaValue = 1
            }
        }
        return pane
    }

    func removePane(_ id: UUID, animated: Bool) {
        guard let pane = panes[id] else { return }
        panes[id] = nil
        paneWorkspace[id] = nil
        pane.terminate()
        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                pane.animator().alphaValue = 0
            }, completionHandler: { pane.removeFromSuperview() })
        } else {
            pane.removeFromSuperview()
        }
    }

    func restartPane(_ id: UUID) { panes[id]?.restart() }

    func terminateAll() { panes.values.forEach { $0.terminate() } }

    func pane(_ id: UUID) -> PaneView? { panes[id] }

    var debugText: String {
        let u = UsageMonitor.shared
        var lines = panes.values.map { "── \($0.title) [\($0.state.label)]\n\($0.visibleText)" }
        if let w = u.claudeWindow {
            lines.append("USAGE window start=\(w.start) resets=\(w.resets) tokens=\(w.tokens) cost=\(w.cost ?? -1) replies=\(w.messages)")
        } else {
            lines.append("USAGE window none")
        }
        return lines.joined(separator: "\n\n")
    }

    private func setFocused(_ id: UUID?) {
        for (pid, pane) in panes where paneWorkspace[pid] == currentWorkspace { pane.isFocused = pid == id }
        if store?.focusedID != id { store?.focusedID = id }
        if id == nil { scrollView.window?.makeFirstResponder(scrollView.documentView) }
    }

    func focusPane(_ id: UUID, zoom: Bool) {
        guard let pane = panes[id] else { return }
        setFocused(id)
        pane.focusTerminal()
        if zoom { animateCamera(toFit: pane.frame.insetBy(dx: -40, dy: -40), maxZoom: 1) }
    }

    /// Bring a pane into view without changing zoom unless it would not fit.
    func reveal(_ id: UUID) {
        guard let pane = panes[id] else { return }
        let visible = scrollView.contentView.bounds
        if visible.contains(pane.frame) { return }
        let current = scrollView.magnification
        let fit = fitZoom(for: pane.frame.insetBy(dx: -60, dy: -60))
        animateCamera(zoom: min(current, fit), center: pane.frame.center)
    }

    func evaluateStates(now: CFTimeInterval) -> [(UUID, SessionState)] {
        panes.map { ($0.key, $0.value.evaluate(now: now)) }
    }

    func apply(frames: [UUID: CGRect]) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.42
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ctx.allowsImplicitAnimation = true
            for (id, f) in frames { panes[id]?.animator().frame = f }
        }
        let all = Array(frames.values)
        if !all.isEmpty { animateCamera(toFit: union(all).insetBy(dx: -60, dy: -60), maxZoom: 1) }
    }

    // MARK: Layout

    func nextFreeFrame(in workspaceID: UUID) -> CGRect {
        let existing = panes.filter { paneWorkspace[$0.key] == workspaceID }.map { $0.value.frame }
        let size = CanvasController.defaultPaneSize
        let gap: CGFloat = 24
        guard !existing.isEmpty else { return CGRect(origin: CanvasController.home, size: size) }
        let bounds = union(existing)
        let columns = max(3, Int((bounds.width + gap) / (size.width + gap)))
        for row in 0..<40 {
            for col in 0..<columns {
                let r = CGRect(x: bounds.minX + CGFloat(col) * (size.width + gap),
                               y: bounds.minY + CGFloat(row) * (size.height + gap),
                               width: size.width, height: size.height)
                if !existing.contains(where: { $0.insetBy(dx: -gap / 2, dy: -gap / 2).intersects(r) }) { return r }
            }
        }
        return CGRect(x: bounds.maxX + gap, y: bounds.minY, width: size.width, height: size.height)
    }

    /// Lay sessions into an even grid that fills the window, then fit it.
    func tile(_ sessions: [SessionRecord]) -> [UUID: CGRect] {
        let ordered = sessions.sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
        let n = ordered.count
        let gap: CGFloat = 20
        let view = scrollView.contentView.frame.size
        let area = NSSize(width: max(view.width - 80, 600), height: max(view.height - CanvasController.topInset - 56, 400))

        var best = (cols: 1, rows: n, score: CGFloat.infinity)
        for cols in 1...n {
            let rows = Int(ceil(Double(n) / Double(cols)))
            let w = (area.width - gap * CGFloat(cols - 1)) / CGFloat(cols)
            let h = (area.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
            let score = abs(log((w / max(h, 1)) / 1.6)) + CGFloat(cols * rows - n) * 0.15
            if score < best.score { best = (cols, rows, score) }
        }
        var cell = NSSize(width: (area.width - gap * CGFloat(best.cols - 1)) / CGFloat(best.cols),
                          height: (area.height - gap * CGFloat(best.rows - 1)) / CGFloat(best.rows))
        // Never smaller than a usable terminal; the camera zooms out instead.
        if cell.width < 420 || cell.height < 260 {
            let s = max(420 / cell.width, 260 / cell.height)
            cell = NSSize(width: cell.width * s, height: cell.height * s)
        }
        let origin = union(ordered.map(\.frame)).origin
        var frames: [UUID: CGRect] = [:]
        for (i, s) in ordered.enumerated() {
            let col = i % best.cols, row = i / best.cols
            frames[s.id] = CGRect(x: origin.x + CGFloat(col) * (cell.width + gap),
                                  y: origin.y + CGFloat(row) * (cell.height + gap),
                                  width: cell.width, height: cell.height).integral
        }
        apply(frames: frames)
        return frames
    }

    // MARK: Camera

    func camera() -> (zoom: CGFloat, center: CGPoint) {
        (scrollView.magnification, scrollView.contentView.bounds.center)
    }

    func overview(animated: Bool = true) {
        let frames = panes.filter { paneWorkspace[$0.key] == currentWorkspace }.map { $0.value.frame }
        guard !frames.isEmpty else {
            animateCamera(zoom: 1, center: CanvasController.home)
            return
        }
        let rect = union(frames).insetBy(dx: -70, dy: -70)
        if animated {
            animateCamera(toFit: rect, maxZoom: 1)
        } else {
            setCamera(zoom: fitZoom(for: rect, max: 1), center: adjustedCenter(rect.center, zoom: fitZoom(for: rect, max: 1)))
        }
    }

    func zoom(by factor: CGFloat) {
        let z = scrollView.magnification * factor
        animateCamera(zoom: z, center: scrollView.contentView.bounds.center, duration: 0.22)
    }

    func setZoom(_ z: CGFloat) {
        animateCamera(zoom: z, center: scrollView.contentView.bounds.center, duration: 0.28)
    }

    private func fitZoom(for rect: CGRect, max maxZoom: CGFloat = 2) -> CGFloat {
        let view = scrollView.contentView.frame.size
        let usable = NSSize(width: view.width, height: max(view.height - CanvasController.topInset, 100))
        let z = min(usable.width / rect.width, usable.height / rect.height)
        return min(maxZoom, max(scrollView.minMagnification, z))
    }

    /// Shift the camera down a little so content clears the floating top bar.
    private func adjustedCenter(_ c: CGPoint, zoom: CGFloat) -> CGPoint {
        CGPoint(x: c.x, y: c.y - (CanvasController.topInset / 2) / zoom)
    }

    func animateCamera(toFit rect: CGRect, maxZoom: CGFloat) {
        let z = fitZoom(for: rect, max: maxZoom)
        animateCamera(zoom: z, center: adjustedCenter(rect.center, zoom: z))
    }

    func animateCamera(zoom target: CGFloat, center: CGPoint, duration: CFTimeInterval = 0.5) {
        cameraTimer?.invalidate()
        let targetZoom = max(scrollView.minMagnification, min(scrollView.maxMagnification, target))
        let start = camera()
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            setCamera(zoom: targetZoom, center: center)
            return
        }
        let t0 = CACurrentMediaTime()
        cameraTimer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                let p = min(1, (CACurrentMediaTime() - t0) / duration)
                let e = p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2
                // Interpolate zoom in log space so it feels even.
                let z = exp(log(start.zoom) + (log(targetZoom) - log(start.zoom)) * e)
                let c = CGPoint(x: start.center.x + (center.x - start.center.x) * e,
                                y: start.center.y + (center.y - start.center.y) * e)
                self.setCamera(zoom: z, center: c)
                if p >= 1 { timer.invalidate() }
            }
        }
        RunLoop.main.add(cameraTimer!, forMode: .common)
    }

    func setCamera(zoom: CGFloat, center: CGPoint) {
        scrollView.magnification = zoom
        let size = scrollView.contentView.bounds.size
        scrollView.contentView.scroll(to: NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        magnificationChanged()
    }

    private func magnificationChanged() {
        let z = scrollView.magnification
        if let store, abs(store.zoom - z) > 0.004 { store.zoom = z }
    }

    private func union(_ rects: [CGRect]) -> CGRect {
        rects.dropFirst().reduce(rects.first ?? .zero) { $0.union($1) }
    }
}

extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
