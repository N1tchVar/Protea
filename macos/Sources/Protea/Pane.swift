import AppKit
import SwiftTerm

// MARK: - Activity

/// Output and input timestamps, written from SwiftTerm's parse thread and read on main.
final class ActivityClock: @unchecked Sendable {
    private let lock = NSLock()
    private var lastInput: CFTimeInterval = 0
    private var lastAgentOutput: CFTimeInterval = 0
    private var sawOutput = false

    func noteInput() {
        lock.lock(); lastInput = CACurrentMediaTime(); lock.unlock()
    }

    func noteOutput() {
        let now = CACurrentMediaTime()
        lock.lock()
        sawOutput = true
        // Output right after a keystroke is the echo of that keystroke, not the agent working.
        if now - lastInput > 0.4 { lastAgentOutput = now }
        lock.unlock()
    }

    func read() -> (output: CFTimeInterval, input: CFTimeInterval, saw: Bool) {
        lock.lock(); defer { lock.unlock() }
        return (lastAgentOutput, lastInput, sawOutput)
    }
}

/// A SwiftTerm view that reports clicks and bells to its pane.
final class TerminalHost: LocalProcessTerminalView {
    let clock = ActivityClock()
    var onClick: (() -> Void)?
    var onBell: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClick?()
        super.mouseDown(with: event)
    }

    override nonisolated func bell(source: Terminal) {
        super.bell(source: source)
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.onBell?() }
        }
    }
}

// MARK: - Pane

/// One session on the canvas: a header you can drag, a live terminal, and resize edges.
final class PaneView: NSView, LocalProcessTerminalViewDelegate, NSTextFieldDelegate {
    static let headerHeight: CGFloat = 40
    static let radius: CGFloat = 13
    static let minSize = NSSize(width: 360, height: 200)

    let id: UUID
    let agent: Agent
    private(set) var title: String
    private var cwd: String

    var onFocus: ((UUID) -> Void)?
    var onMoved: ((UUID, CGRect) -> Void)?
    var onZoom: ((UUID) -> Void)?
    var onClose: ((UUID) -> Void)?
    var onRestart: ((UUID) -> Void)?
    var onRename: ((UUID, String) -> Void)?
    var onTopic: ((UUID, String) -> Void)?
    var onCwd: ((UUID, String) -> Void)?

    private let chrome = FlippedView()
    private let header = PaneHeader()
    private(set) var terminal: TerminalHost
    private var launched = false
    private(set) var runID = UUID()
    private var exited = false
    private var bellPending = false
    private var needsSince: CFTimeInterval = 0
    private(set) var state: SessionState = .starting

    var isFocused = false { didSet { if oldValue != isFocused { updateChrome() } } }

    init(record: SessionRecord, agent: Agent) {
        id = record.id
        self.agent = agent
        title = record.title
        cwd = record.cwd
        terminal = PaneView.makeTerminal()
        super.init(frame: record.frame)

        wantsLayer = true
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.55
        layer?.shadowRadius = 22
        layer?.shadowOffset = CGSize(width: 0, height: -10)

        chrome.wantsLayer = true
        chrome.layer?.cornerRadius = PaneView.radius
        chrome.layer?.cornerCurve = .continuous
        chrome.layer?.masksToBounds = true
        chrome.layer?.backgroundColor = Palette.pane.cgColor
        chrome.layer?.borderWidth = 1
        addSubview(chrome)

        header.configure(agent: agent, title: title, detail: detailText(topic: nil))
        header.titleField.delegate = self
        header.onDragBegan = { [weak self] in self?.focus(); self?.focusTerminal() }
        header.onDragged = { [weak self] delta in self?.move(by: delta) }
        header.onDragEnded = { [weak self] in self?.commitFrame() }
        header.onDoubleClick = { [weak self] in guard let self else { return }; self.onZoom?(self.id) }
        header.onClose = { [weak self] in guard let self else { return }; self.onClose?(self.id) }
        header.onRestart = { [weak self] in guard let self else { return }; self.onRestart?(self.id) }
        header.onZoom = { [weak self] in guard let self else { return }; self.onZoom?(self.id) }
        chrome.addSubview(header)

        attach(terminal)

        for edge in ResizeHandle.Edge.allCases {
            let handle = ResizeHandle(edge: edge)
            handle.onResize = { [weak self] dw, dh in self?.resize(dw: dw, dh: dh) }
            handle.onResizeEnded = { [weak self] in self?.commitFrame() }
            addSubview(handle)
        }
        updateChrome()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private static func makeTerminal() -> TerminalHost {
        let t = TerminalHost(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let size = CGFloat(UserDefaults.standard.double(forKey: "terminal.fontSize").clamped(11, 18, default: 12.5))
        t.font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        t.nativeBackgroundColor = Palette.pane
        t.nativeForegroundColor = Palette.terminalText
        t.caretColor = Palette.azure
        t.selectedTextBackgroundColor = Palette.azure.withAlphaComponent(0.32)
        t.installColors(Palette.ansi)
        t.optionAsMetaKey = true
        t.bellStyle = .none
        // `--snapshot` renders a window that may sit behind others; keep drawing for it.
        if ProcessInfo.processInfo.arguments.contains("--snapshot") { t.suspendsRenderingWhenNotVisible = false }
        return t
    }

    private func attach(_ t: TerminalHost) {
        t.processDelegate = self
        t.onClick = { [weak self] in self?.focus() }
        t.onBell = { [weak self] in self?.bellPending = true }
        let clock = t.clock
        t.setProcessOutputHandler { clock.noteOutput() }
        chrome.addSubview(t)
        needsLayout = true
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        chrome.frame = bounds
        header.frame = NSRect(x: 0, y: 0, width: bounds.width, height: PaneView.headerHeight)
        // Size the terminal to whole rows (SwiftTerm's own cell height), so no partial row shows as a band.
        let font = terminal.font as CTFont
        let cell = max(1, ceil(CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)))
        let available = bounds.height - PaneView.headerHeight - 14
        let rows = max(1, floor(available / cell))
        terminal.frame = NSRect(x: 12, y: PaneView.headerHeight + 6, width: bounds.width - 20, height: rows * cell + 0.01)
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: PaneView.radius, cornerHeight: PaneView.radius, transform: nil)
        for case let handle as ResizeHandle in subviews { handle.frame = handle.edge.frame(in: bounds) }
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        needsLayout = true
    }

    // MARK: Process

    func launch() {
        guard !launched else { return }
        launched = true
        exited = false
        var dir = cwd
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: dir, isDirectory: &isDir) || !isDir.boolValue {
            dir = FileManager.default.homeDirectoryForCurrentUser.path
        }
        runID = UUID()
        terminal.startProcess(executable: Session.userShell,
                              args: ["-l", "-i", "-c", agent.launchScript(sessionID: runID)],
                              environment: Session.environment,
                              execName: nil,
                              currentDirectory: dir)
        header.setUsage(nil)
        UsageMonitor.shared.track(pane: id, agent: agent, runID: runID, cwd: dir, launchedAt: Date())
    }

    func terminate() {
        UsageMonitor.shared.untrack(pane: id)
        let pid = terminal.process?.shellPid ?? 0
        // Interactive shells ignore SIGTERM; a hangup ends the shell and the agent inside it.
        if pid > 0 { kill(pid, SIGHUP) }
        terminal.terminate()
    }

    func restart() {
        terminate()
        terminal.removeFromSuperview()
        terminal = PaneView.makeTerminal()
        attach(terminal)
        layoutSubtreeIfNeeded()
        launched = false
        state = .starting
        launch()
        updateChrome()
        focusTerminal()
    }

    func focusTerminal() { window?.makeFirstResponder(terminal) }

    func setUsage(_ usage: SessionUsage?) { header.setUsage(usage) }

    /// Type text into the session as if you had, then press Return if asked.
    func sendText(_ text: String, submit: Bool) {
        focusTerminal()
        terminal.clock.noteInput()
        terminal.send(txt: text)
        guard submit else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.terminal.clock.noteInput()
            self?.terminal.send(txt: "\r")
        }
    }

    /// Visible terminal text, for `--snapshot` debugging.
    var visibleText: String {
        terminal.terminalContentSnapshot(region: .viewport)?.rows.map(\.text).joined(separator: "\n") ?? "(no snapshot)"
    }

    private func focus() { onFocus?(id) }

    // MARK: Status

    private static let promptPatterns = [
        "do you want to", "do you want me to", "would you like to", "allow this", "allow command",
        "allow execution", "approve this", "approve?", "(y/n)", "[y/n]", "yes, and don't ask again",
        "press enter to continue", "waiting for your approval", "requires approval", "apply this change",
        "enter to confirm", "trust this folder", "❯ 1. yes",
    ]

    private func promptVisible() -> Bool {
        guard let snap = terminal.terminalContentSnapshot(region: .viewport) else { return false }
        let text = snap.rows.suffix(14).map { $0.text.lowercased() }.joined(separator: "\n")
        return PaneView.promptPatterns.contains { text.contains($0) }
    }

    func evaluate(now: CFTimeInterval) -> SessionState {
        let r = terminal.clock.read()
        var next: SessionState
        if exited {
            next = .exited
        } else if !r.saw {
            next = .starting
        } else if now - r.output < 1.3 {
            next = .working
        } else {
            switch state {
            case .working, .starting:
                next = promptVisible() ? .needsYou : .idle
            case .needsYou:
                next = r.input > needsSince ? .idle : .needsYou
            default:
                next = .idle
            }
        }
        if bellPending {
            bellPending = false
            if next != .exited && !(isFocused && NSApp.isActive) { next = .needsYou }
        }
        if next == .needsYou && state != .needsYou { needsSince = now }
        if next != state {
            state = next
            updateChrome()
        }
        return state
    }

    private func updateChrome() {
        header.setState(state)
        header.setFocused(isFocused)
        let border: NSColor
        switch (state, isFocused) {
        case (.needsYou, _): border = Palette.coral.withAlphaComponent(0.85)
        case (_, true): border = Palette.azure.withAlphaComponent(0.8)
        default: border = Palette.line
        }
        chrome.layer?.borderColor = border.cgColor
        layer?.shadowColor = (isFocused ? Palette.azure : state == .needsYou ? Palette.coral : NSColor.black).cgColor
        layer?.shadowOpacity = isFocused || state == .needsYou ? 0.32 : 0.55
        layer?.shadowRadius = isFocused ? 30 : 22
    }

    private func detailText(topic: String?) -> String {
        let place = cwd.abbreviatingHome
        if let topic, !topic.isEmpty { return topic }
        return "\(agent.name) · \(place)"
    }

    // MARK: Move & resize

    private func move(by delta: NSPoint) {
        setFrameOrigin(NSPoint(x: frame.origin.x + delta.x, y: frame.origin.y + delta.y))
    }

    private func resize(dw: CGFloat, dh: CGFloat) {
        var f = frame
        f.size.width = max(PaneView.minSize.width, f.width + dw)
        f.size.height = max(PaneView.minSize.height, f.height + dh)
        frame = f
    }

    private func commitFrame() {
        // Snap to a soft 4pt grid so edges line up.
        let f = frame
        frame = CGRect(x: (f.minX / 4).rounded() * 4, y: (f.minY / 4).rounded() * 4,
                       width: (f.width / 4).rounded() * 4, height: (f.height / 4).rounded() * 4)
        onMoved?(id, frame)
    }

    // MARK: Rename

    func controlTextDidEndEditing(_ obj: Notification) {
        let new = header.titleField.stringValue.trimmingCharacters(in: .whitespaces)
        header.endRename()
        if new.isEmpty {
            header.titleField.stringValue = title
        } else if new != title {
            title = new
            onRename?(id, new)
        }
        focusTerminal()
    }

    // MARK: LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        // Claude Code and others put the current task in the window title.
        let topic = title.trimmingCharacters(in: CharacterSet(charactersIn: "✳✻✶✢·*⠂⠐ ").union(.whitespaces))
        header.setDetail(detailText(topic: topic.isEmpty ? nil : topic))
        onTopic?(id, topic)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory, let url = URL(string: directory), url.isFileURL || directory.hasPrefix("/") else { return }
        cwd = url.isFileURL ? url.path : directory
        onCwd?(id, cwd)
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        exited = true
        terminal.feed(text: "\r\n\u{1b}[2m  Session ended. Press ⇧⌘R or the restart button to start it again.\u{1b}[0m\r\n")
    }
}

// MARK: - Header

final class PaneHeader: NSView {
    let titleField = NSTextField(labelWithString: "")
    private let detailField = NSTextField(labelWithString: "")
    private let badge = NSView()
    private let icon = NSImageView()
    private let pill = StatusPill()
    private let usageChip = UsageChip()
    private let zoomButton = HoverButton(symbol: "arrow.up.left.and.arrow.down.right", tip: "Zoom to session")
    private let restartButton = HoverButton(symbol: "arrow.clockwise", tip: "Restart session")
    private let closeButton = HoverButton(symbol: "xmark", tip: "Close session")
    private let hairline = NSView()

    var onDragBegan: (() -> Void)?
    var onDragged: ((NSPoint) -> Void)?
    var onDragEnded: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onClose: (() -> Void)?
    var onRestart: (() -> Void)?
    var onZoom: (() -> Void)?

    private var lastDrag: NSPoint?
    private var renaming = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Palette.header.cgColor

        badge.wantsLayer = true
        badge.layer?.cornerRadius = 7
        badge.layer?.cornerCurve = .continuous
        addSubview(badge)
        icon.imageScaling = .scaleNone
        badge.addSubview(icon)

        titleField.font = .systemFont(ofSize: 13, weight: .semibold)
        titleField.textColor = Palette.marble
        titleField.lineBreakMode = .byTruncatingTail
        titleField.focusRingType = .none
        titleField.drawsBackground = false
        addSubview(titleField)

        detailField.font = .systemFont(ofSize: 12, weight: .regular)
        detailField.textColor = Palette.marble3
        detailField.lineBreakMode = .byTruncatingTail
        addSubview(detailField)

        addSubview(pill)
        usageChip.isHidden = true
        addSubview(usageChip)
        for b in [zoomButton, restartButton, closeButton] { addSubview(b) }
        zoomButton.onPress = { [weak self] in self?.onZoom?() }
        restartButton.onPress = { [weak self] in self?.onRestart?() }
        closeButton.onPress = { [weak self] in self?.onClose?() }

        hairline.wantsLayer = true
        hairline.layer?.backgroundColor = Palette.line.cgColor
        addSubview(hairline)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    func configure(agent: Agent, title: String, detail: String) {
        badge.layer?.backgroundColor = agent.tint.withAlphaComponent(0.16).cgColor
        badge.layer?.borderColor = agent.tint.withAlphaComponent(0.3).cgColor
        badge.layer?.borderWidth = 0.5
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .bold)
        icon.image = NSImage(systemSymbolName: agent.symbol, accessibilityDescription: agent.name)?.withSymbolConfiguration(config)
        icon.contentTintColor = agent.tint
        titleField.stringValue = title
        detailField.stringValue = detail
        needsLayout = true
    }

    func setDetail(_ s: String) {
        if detailField.stringValue != s { detailField.stringValue = s; needsLayout = true }
    }

    func setState(_ state: SessionState) { pill.state = state; needsLayout = true }

    func setUsage(_ usage: SessionUsage?) {
        usageChip.usage = usage
        usageChip.isHidden = usage == nil
        needsLayout = true
    }
    func setFocused(_ on: Bool) { layer?.backgroundColor = (on ? Palette.raised : Palette.header).cgColor }

    override func layout() {
        super.layout()
        let h = bounds.height
        badge.frame = NSRect(x: 12, y: (h - 24) / 2, width: 24, height: 24)
        icon.frame = badge.bounds
        var right = bounds.width - 8
        for b in [closeButton, restartButton, zoomButton] {
            b.frame = NSRect(x: right - 26, y: (h - 26) / 2, width: 26, height: 26)
            right -= 28
        }
        let pillSize = pill.fittingSize
        pill.frame = NSRect(x: right - pillSize.width - 6, y: (h - pillSize.height) / 2, width: pillSize.width, height: pillSize.height)
        right = pill.frame.minX - 6
        if !usageChip.isHidden {
            let w = usageChip.fittingSize.width
            usageChip.frame = NSRect(x: right - w, y: (h - 20) / 2, width: w, height: 20)
            right = usageChip.frame.minX - 8
        } else {
            right -= 4
        }

        let x0: CGFloat = 46
        let titleWidth = min(titleField.intrinsicContentSize.width + 4, max(60, (right - x0) * 0.55))
        titleField.frame = NSRect(x: x0, y: (h - 18) / 2, width: renaming ? max(titleWidth, 140) : titleWidth, height: 18)
        let dx = titleField.frame.maxX + 8
        detailField.frame = NSRect(x: dx, y: (h - 16) / 2 + 0.5, width: max(0, right - dx), height: 16)
        detailField.isHidden = renaming
        hairline.frame = NSRect(x: 0, y: h - 1, width: bounds.width, height: 1)
    }

    // Drag the header to move the pane. Double-click to zoom; double-click the title to rename.
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if event.clickCount == 2 {
            if titleField.frame.insetBy(dx: -4, dy: -6).contains(p) { beginRename() } else { onDoubleClick?() }
            return
        }
        onDragBegan?()
        lastDrag = superview?.superview?.superview?.convert(event.locationInWindow, from: nil)
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let doc = superview?.superview?.superview, let last = lastDrag else { return }
        let p = doc.convert(event.locationInWindow, from: nil)
        onDragged?(NSPoint(x: p.x - last.x, y: p.y - last.y))
        lastDrag = p
    }

    override func mouseUp(with event: NSEvent) {
        if lastDrag != nil {
            NSCursor.pop()
            lastDrag = nil
            onDragEnded?()
        }
    }

    override func resetCursorRects() {
        addCursorRect(NSRect(x: 0, y: 0, width: pill.frame.minX, height: bounds.height), cursor: .openHand)
    }

    private func beginRename() {
        renaming = true
        titleField.isEditable = true
        titleField.isSelectable = true
        titleField.isBezeled = false
        titleField.drawsBackground = true
        titleField.backgroundColor = Palette.pane
        needsLayout = true
        window?.makeFirstResponder(titleField)
        titleField.currentEditor()?.selectAll(nil)
    }

    func endRename() {
        renaming = false
        titleField.isEditable = false
        titleField.isSelectable = false
        titleField.drawsBackground = false
        needsLayout = true
    }
}

// MARK: - Status pill

final class StatusPill: NSView {
    private let label = NSTextField(labelWithString: "")
    private let dot = CALayer()

    var state: SessionState = .starting { didSet { if oldValue != state { refresh() } } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        dot.cornerRadius = 3
        layer?.addSublayer(dot)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        addSubview(label)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var fittingSize: NSSize {
        NSSize(width: label.intrinsicContentSize.width + 26, height: 20)
    }

    override func layout() {
        super.layout()
        dot.frame = CGRect(x: 9, y: (bounds.height - 6) / 2, width: 6, height: 6)
        label.frame = NSRect(x: 19, y: (bounds.height - 15) / 2, width: bounds.width - 22, height: 15)
    }

    private func refresh() {
        let c = state.nsColor
        label.stringValue = state.label
        label.textColor = state == .idle || state == .starting ? Palette.marble2 : c
        layer?.backgroundColor = c.withAlphaComponent(state == .idle ? 0.12 : 0.14).cgColor
        dot.backgroundColor = c.cgColor
        dot.removeAllAnimations()
        if state.pulses {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1
            pulse.toValue = 0.25
            pulse.duration = 0.8
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            dot.add(pulse, forKey: "pulse")
        }
        needsLayout = true
        superview?.needsLayout = true
    }
}

// MARK: - Usage chip

/// A small ring for how full the context is, and the tokens in it. Hover for the details.
final class UsageChip: NSView {
    private let ring = CAShapeLayer()
    private let track = CAShapeLayer()
    private let label = NSTextField(labelWithString: "")

    var usage: SessionUsage? { didSet { refresh() } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
        for l in [track, ring] {
            l.fillColor = nil
            l.lineWidth = 2
            l.lineCap = .round
            layer?.addSublayer(l)
        }
        track.strokeColor = NSColor.white.withAlphaComponent(0.12).cgColor
        label.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
        label.textColor = Palette.marble2
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var fittingSize: NSSize { NSSize(width: label.intrinsicContentSize.width + 30, height: 20) }

    override func layout() {
        super.layout()
        // An arc that starts at 12 o'clock and runs clockwise.
        let center = CGPoint(x: 12.5, y: bounds.midY)
        let path = CGMutablePath()
        path.addArc(center: center, radius: 5.5, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true)
        track.path = path
        ring.path = path
        label.frame = NSRect(x: 23, y: (bounds.height - 14) / 2, width: bounds.width - 26, height: 14)
    }

    private func refresh() {
        guard let u = usage else { return }
        let f = u.contextFraction
        label.stringValue = UsageFormat.tokens(u.contextTokens)
        ring.strokeEnd = max(0.02, f)
        ring.strokeColor = (f > 0.9 ? Palette.coral : f > 0.7 ? NSColor(hex: 0xF2C46D) : Palette.azure).cgColor
        var tip = "Context \(UsageFormat.tokens(u.contextTokens)) of \(UsageFormat.tokens(u.contextWindow)) (\(Int(f * 100))%)"
        tip += "\n\(UsageFormat.tokens(u.totalTokens)) tokens this session"
        if let c = UsageFormat.cost(u.cost) { tip += " · ≈ \(c) at API prices" }
        if let m = u.model { tip += "\n\(m)" }
        for l in u.limits { tip += "\n\(l.label) limit: \(Int(l.usedPercent))% used" }
        toolTip = tip
        needsLayout = true
        superview?.needsLayout = true
    }
}

// MARK: - Buttons & handles

final class HoverButton: NSView {
    private let image = NSImageView()
    var onPress: (() -> Void)?
    private var hovering = false { didSet { update() } }

    init(symbol: String, tip: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous
        toolTip = tip
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        image.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?.withSymbolConfiguration(config)
        image.imageScaling = .scaleNone
        addSubview(image)
        update()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() { super.layout(); image.frame = bounds }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { layer?.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor }
    override func mouseUp(with event: NSEvent) {
        update()
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress?() }
    }

    private func update() {
        layer?.backgroundColor = hovering ? NSColor.white.withAlphaComponent(0.08).cgColor : NSColor.clear.cgColor
        image.contentTintColor = hovering ? Palette.marble : Palette.marble3
    }
}

final class ResizeHandle: NSView {
    enum Edge: CaseIterable {
        case right, bottom, corner

        func frame(in b: NSRect) -> NSRect {
            switch self {
            case .right: NSRect(x: b.width - 5, y: PaneView.headerHeight, width: 10, height: b.height - PaneView.headerHeight - 14)
            case .bottom: NSRect(x: 14, y: b.height - 5, width: b.width - 28, height: 10)
            case .corner: NSRect(x: b.width - 16, y: b.height - 16, width: 20, height: 20)
            }
        }
    }

    let edge: Edge
    var onResize: ((CGFloat, CGFloat) -> Void)?
    var onResizeEnded: (() -> Void)?
    private var last: NSPoint?

    init(edge: Edge) {
        self.edge = edge
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard edge == .corner else { return }
        Palette.marble3.withAlphaComponent(0.45).setStroke()
        for i in 0..<3 {
            let o = CGFloat(i) * 4
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 13 - o, y: 4))
            path.line(to: NSPoint(x: 4, y: 13 - o))
            path.lineWidth = 1
            path.stroke()
        }
    }

    override func resetCursorRects() {
        let cursor: NSCursor
        switch edge {
        case .right: cursor = .resizeLeftRight
        case .bottom: cursor = .resizeUpDown
        case .corner:
            if #available(macOS 15.0, *) {
                cursor = .frameResize(position: .bottomRight, directions: .all)
            } else {
                cursor = .crosshair
            }
        }
        addCursorRect(bounds, cursor: cursor)
    }

    override func mouseDown(with event: NSEvent) {
        last = superview?.superview?.convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let doc = superview?.superview, let l = last else { return }
        let p = doc.convert(event.locationInWindow, from: nil)
        let dx = p.x - l.x, dy = p.y - l.y
        switch edge {
        case .right: onResize?(dx, 0)
        case .bottom: onResize?(0, dy)
        case .corner: onResize?(dx, dy)
        }
        last = p
    }

    override func mouseUp(with event: NSEvent) {
        last = nil
        onResizeEnded?()
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

extension Double {
    func clamped(_ lo: Double, _ hi: Double, default d: Double) -> Double {
        self == 0 ? d : Swift.min(hi, Swift.max(lo, self))
    }
}
