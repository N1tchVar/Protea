import AppKit
import SwiftUI

// MARK: - Saved state

struct SessionRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var agentID: String
    var cwd: String
    var frame: CGRect
}

struct WorkspaceRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var folder: String
    var sessions: [SessionRecord] = []
    var zoom: CGFloat = 1
    var center: CGPoint?
}

private struct SavedState: Codable {
    var workspaces: [WorkspaceRecord]
    var selected: UUID?
}

// MARK: - Live state

enum SessionState: Equatable {
    case starting, working, idle, needsYou, exited

    var label: String {
        switch self {
        case .starting: "Starting"
        case .working: "Working"
        case .idle: "Idle"
        case .needsYou: "Needs you"
        case .exited: "Exited"
        }
    }

    var nsColor: NSColor {
        switch self {
        case .starting: Palette.marble3
        case .working: Palette.azure
        case .idle: Palette.marble3
        case .needsYou: Palette.coral
        case .exited: NSColor(hex: 0x3A4A63)
        }
    }

    var color: SwiftUI.Color { SwiftUI.Color(nsColor: nsColor) }
    var pulses: Bool { self == .working || self == .needsYou }
}

struct SessionStatus: Equatable {
    var state: SessionState = .starting
    var since = Date()
    var topic: String?
}

/// Helpers for launching processes the way a terminal would.
enum Session {
    static var userShell: String {
        if let shell = ProcessInfo.processInfo.environment["SHELL"], !shell.isEmpty { return shell }
        if let pw = getpwuid(getuid()), let shell = pw.pointee.pw_shell { return String(cString: shell) }
        return "/bin/zsh"
    }

    static var environment: [String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["TERM_PROGRAM"] = "Protea"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        env["SHELL"] = userShell
        env["HOME"] = env["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
        return env.map { "\($0.key)=\($0.value)" }
    }
}

// MARK: - Store

@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published var workspaces: [WorkspaceRecord] = []
    @Published var selectedID: UUID?
    @Published var status: [UUID: SessionStatus] = [:]
    @Published var focusedID: UUID?
    @Published var zoom: CGFloat = 1
    @Published var tiled: Set<UUID> = []
    @Published var showNewSession = false
    @Published var showUsage = false

    let canvas = CanvasController()
    private var tileBackup: [UUID: [UUID: CGRect]] = [:]
    private var saveWork: DispatchWorkItem?
    private var ticker: Timer?
    private var keyMonitor: Any?
    private var scrollMonitor: Any?
    private(set) var lastAgentID = "claude"
    /// Off in `--demo` and `--snapshot` so they never overwrite your layout.
    var persists = true

    var current: WorkspaceRecord? { workspaces.first { $0.id == selectedID } }
    private var currentIndex: Int? { workspaces.firstIndex { $0.id == selectedID } }

    // MARK: Lifecycle

    func start(demo: Bool = false) {
        canvas.store = self
        if demo {
            loadDemo()
        } else {
            load()
        }
        if workspaces.isEmpty {
            workspaces = [WorkspaceRecord(name: "Main", folder: FileManager.default.homeDirectoryForCurrentUser.path)]
        }
        for ws in workspaces { for s in ws.sessions { status[s.id] = SessionStatus() } }
        show(selectedID ?? workspaces[0].id)

        ticker = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { _ in
            MainActor.assumeIsolated { AppStore.shared.tick() }
        }
        // Typing into a terminal is input, not agent activity.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                if let host = event.window?.firstResponder as? TerminalHost { host.clock.noteInput() }
            }
            return event
        }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            MainActor.assumeIsolated {
                if event.modifierFlags.contains(.command), event.window?.firstResponder is TerminalHost || event.window != nil {
                    let sv = AppStore.shared.canvas.scrollView
                    if let hit = sv.window?.contentView?.hitTest(event.locationInWindow), hit.isDescendant(of: sv) {
                        sv.scrollWheel(with: event)
                        return nil
                    }
                }
                return event
            }
        }
        AgentAvailability.shared.refresh()
        UsageMonitor.shared.start()
    }

    func shutdown() {
        saveNow()
        canvas.terminateAll()
    }

    // MARK: Workspaces

    func show(_ id: UUID) {
        if let old = selectedID, old != id, let i = workspaces.firstIndex(where: { $0.id == old }) {
            let cam = canvas.camera()
            workspaces[i].zoom = cam.zoom
            workspaces[i].center = cam.center
        }
        selectedID = id
        guard let ws = workspaces.first(where: { $0.id == id }) else { return }
        canvas.show(workspace: ws)
        focusedID = nil
        scheduleSave()
    }

    func addWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Open Workspace"
        panel.message = "Choose the folder your agents will work in."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let ws = WorkspaceRecord(name: url.lastPathComponent, folder: url.path)
        workspaces.append(ws)
        show(ws.id)
    }

    func renameWorkspace(_ id: UUID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let i = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces[i].name = name
        scheduleSave()
    }

    func removeWorkspace(_ id: UUID) {
        guard workspaces.count > 1, let i = workspaces.firstIndex(where: { $0.id == id }) else { return }
        let ws = workspaces[i]
        if !ws.sessions.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Remove “\(ws.name)”?"
            alert.informativeText = "Its \(ws.sessions.count) session\(ws.sessions.count == 1 ? "" : "s") will stop. Your files are not touched."
            alert.addButton(withTitle: "Remove")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        for s in ws.sessions { canvas.removePane(s.id, animated: false); status[s.id] = nil }
        canvas.dropWorkspace(id)
        workspaces.remove(at: i)
        if selectedID == id { show(workspaces[0].id) }
        scheduleSave()
    }

    func revealInFinder(_ id: UUID) {
        guard let ws = workspaces.first(where: { $0.id == id }) else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: ws.folder)
    }

    // MARK: Sessions

    func newSession(_ agent: Agent) {
        guard let wi = currentIndex else { return }
        lastAgentID = agent.id
        let ws = workspaces[wi]
        let frame = canvas.nextFreeFrame(in: ws.id)
        let record = SessionRecord(title: uniqueTitle(agent.name, in: ws), agentID: agent.id, cwd: ws.folder, frame: frame)
        workspaces[wi].sessions.append(record)
        status[record.id] = SessionStatus()
        tiled.remove(ws.id)
        canvas.addPane(record, to: ws.id, animated: true)
        canvas.reveal(record.id)
        canvas.focusPane(record.id, zoom: false)
        scheduleSave()
    }

    func newSessionWithLastAgent() { newSession(Agent.with(id: lastAgentID)) }

    /// Where dictation goes: the focused session, or the first one in this workspace.
    var dictationTarget: SessionRecord? {
        guard let ws = current else { return nil }
        return ws.sessions.first { $0.id == focusedID } ?? ws.sessions.first
    }

    func dictate(_ text: String) {
        guard let target = dictationTarget else { return }
        let submit = UserDefaults.standard.object(forKey: "voice.submit") as? Bool ?? true
        canvas.pane(target.id)?.sendText(text, submit: submit)
        if focusedID != target.id { canvas.focusPane(target.id, zoom: false) }
    }

    func close(_ id: UUID) {
        canvas.removePane(id, animated: true)
        for i in workspaces.indices { workspaces[i].sessions.removeAll { $0.id == id } }
        status[id] = nil
        if focusedID == id { focusedID = nil }
        updateDockBadge()
        scheduleSave()
    }

    func closeFocused() { if let id = focusedID { close(id) } }
    func restart(_ id: UUID) { canvas.restartPane(id) }
    func restartFocused() { if let id = focusedID { restart(id) } }

    func focus(_ id: UUID, zoom: Bool) {
        if let ws = workspaces.first(where: { $0.sessions.contains { $0.id == id } }), ws.id != selectedID {
            show(ws.id)
        }
        canvas.focusPane(id, zoom: zoom)
    }

    func focusNext(_ step: Int) {
        guard let sessions = current?.sessions, !sessions.isEmpty else { return }
        let ordered = sessions.sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
        let i = ordered.firstIndex { $0.id == focusedID } ?? -step
        let next = ordered[(i + step + ordered.count) % ordered.count]
        canvas.focusPane(next.id, zoom: true)
    }

    func rename(_ id: UUID, to title: String) {
        let title = title.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        mutate(id) { $0.title = title }
    }

    func paneMoved(_ id: UUID, frame: CGRect) {
        mutate(id) { $0.frame = frame }
        if let ws = workspaces.first(where: { $0.sessions.contains { $0.id == id } }) {
            tiled.remove(ws.id)
            tileBackup[ws.id] = nil
        }
    }

    func cwdChanged(_ id: UUID, to path: String) { mutate(id) { $0.cwd = path } }

    func topicChanged(_ id: UUID, to topic: String) {
        let clean = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        if status[id]?.topic != clean { status[id]?.topic = clean.isEmpty ? nil : clean }
    }

    private func mutate(_ id: UUID, _ change: (inout SessionRecord) -> Void) {
        for w in workspaces.indices {
            if let s = workspaces[w].sessions.firstIndex(where: { $0.id == id }) {
                change(&workspaces[w].sessions[s])
                scheduleSave()
                return
            }
        }
    }

    private func uniqueTitle(_ base: String, in ws: WorkspaceRecord) -> String {
        let taken = Set(ws.sessions.map(\.title))
        if !taken.contains(base) { return base }
        var n = 2
        while taken.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    // MARK: Canvas

    func toggleTile() {
        guard let ws = current, !ws.sessions.isEmpty else { return }
        if tiled.contains(ws.id), let backup = tileBackup[ws.id] {
            canvas.apply(frames: backup)
            for (id, f) in backup { mutate(id) { $0.frame = f } }
            tiled.remove(ws.id)
            tileBackup[ws.id] = nil
        } else {
            tileBackup[ws.id] = Dictionary(uniqueKeysWithValues: ws.sessions.map { ($0.id, $0.frame) })
            let frames = canvas.tile(ws.sessions)
            for (id, f) in frames { mutate(id) { $0.frame = f } }
            tiled.insert(ws.id)
        }
    }

    func overview() { canvas.overview() }
    func zoomIn() { canvas.zoom(by: 1.25) }
    func zoomOut() { canvas.zoom(by: 0.8) }
    func actualSize() { canvas.setZoom(1) }

    // MARK: Status

    private func tick() {
        let now = CACurrentMediaTime()
        for (id, state) in canvas.evaluateStates(now: now) {
            guard var s = status[id], s.state != state else { continue }
            let wasNeeding = s.state == .needsYou
            s.state = state
            s.since = Date()
            status[id] = s
            if state == .needsYou, !wasNeeding, (focusedID != id || !NSApp.isActive) {
                NSApp.requestUserAttention(.informationalRequest)
            }
        }
        updateDockBadge()
    }

    private func updateDockBadge() {
        let n = status.values.filter { $0.state == .needsYou }.count
        NSApp.dockTile.badgeLabel = n > 0 ? "\(n)" : nil
    }

    func counts(for ws: WorkspaceRecord) -> (working: Int, needs: Int) {
        var w = 0, n = 0
        for s in ws.sessions {
            switch status[s.id]?.state {
            case .working: w += 1
            case .needsYou: n += 1
            default: break
            }
        }
        return (w, n)
    }

    // MARK: Persistence

    private static var stateURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Protea", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }

    func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { MainActor.assumeIsolated { AppStore.shared.saveNow() } }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func saveNow() {
        guard persists else { return }
        if let i = currentIndex {
            let cam = canvas.camera()
            workspaces[i].zoom = cam.zoom
            workspaces[i].center = cam.center
        }
        let state = SavedState(workspaces: workspaces, selected: selectedID)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: Self.stateURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.stateURL),
              let state = try? JSONDecoder().decode(SavedState.self, from: data) else { return }
        workspaces = state.workspaces
        selectedID = state.selected
    }

    /// A workspace full of shells, used by `--demo` and `--snapshot`.
    private func loadDemo() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var ws = WorkspaceRecord(name: "Halcyon", folder: home)
        let o = CanvasController.home
        ws.sessions = [
            SessionRecord(title: "Overseer", agentID: "claude", cwd: home, frame: CGRect(x: o.x, y: o.y, width: 660, height: 520)),
            SessionRecord(title: "API", agentID: "codex", cwd: home, frame: CGRect(x: o.x + 684, y: o.y, width: 560, height: 248)),
            SessionRecord(title: "Tests", agentID: "gemini", cwd: home, frame: CGRect(x: o.x + 684, y: o.y + 272, width: 560, height: 248)),
            SessionRecord(title: "Shell", agentID: "shell", cwd: home, frame: CGRect(x: o.x, y: o.y + 544, width: 1244, height: 260)),
        ]
        ws.zoom = 1.0
        let empty = WorkspaceRecord(name: "Website", folder: home)
        workspaces = [ws, empty]
        selectedID = CommandLine.arguments.contains("--empty") ? empty.id : ws.id
    }
}
