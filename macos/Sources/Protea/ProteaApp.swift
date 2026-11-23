import AppKit
import SwiftUI

@main
struct ProteaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Protea", id: "main") {
            RootView()
                .frame(minWidth: 980, minHeight: 620)
                .onAppear { AppDelegate.startIfNeeded() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1480, height: 920)
        .commands { ProteaCommands() }

        Settings { SettingsView() }
    }
}

struct ProteaCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Session") { AppStore.shared.newSessionWithLastAgent() }
                .keyboardShortcut("t")
            Menu("New Session With") {
                ForEach(Array(Agent.all.enumerated()), id: \.element.id) { index, agent in
                    Button(agent.name) { AppStore.shared.newSession(agent) }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.command, .option])
                }
            }
            Divider()
            Button("New Workspace…") { AppStore.shared.addWorkspace() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        CommandMenu("Voice") {
            Button("Dictate Prompt") { VoiceController.shared.toggle() }.keyboardShortcut("d")
            Button("Cancel Dictation") { VoiceController.shared.cancel() }
        }
        CommandMenu("Canvas") {
            Button("Zoom In") { AppStore.shared.zoomIn() }.keyboardShortcut("=")
            Button("Zoom Out") { AppStore.shared.zoomOut() }.keyboardShortcut("-")
            Button("Actual Size") { AppStore.shared.actualSize() }.keyboardShortcut("0")
            Button("Overview") { AppStore.shared.overview() }.keyboardShortcut("0", modifiers: [.command, .shift])
            Button("Tile Sessions") { AppStore.shared.toggleTile() }.keyboardShortcut("g", modifiers: [.command, .shift])
            Divider()
            Button("Next Session") { AppStore.shared.focusNext(1) }.keyboardShortcut("]")
            Button("Previous Session") { AppStore.shared.focusNext(-1) }.keyboardShortcut("[")
            Divider()
            Button("Restart Session") { AppStore.shared.restartFocused() }.keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Close Session") { AppStore.shared.closeFocused() }.keyboardShortcut("w", modifiers: [.command, .shift])
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var started = false
    private static var snapshotPath: String?
    private static var demo = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count { AppDelegate.snapshotPath = args[i + 1] }
        AppDelegate.demo = AppDelegate.snapshotPath != nil || args.contains("--demo")
    }

    @MainActor
    static func startIfNeeded() {
        guard !started else { return }
        started = true
        if let window = NSApp.windows.first(where: { $0.contentView != nil && $0.isVisible }) ?? NSApp.windows.first {
            window.backgroundColor = Palette.ink
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = false
        }
        AppStore.shared.persists = !demo
        AppStore.shared.start(demo: demo)
        if let path = snapshotPath {
            if CommandLine.arguments.contains("--usage") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                    MainActor.assumeIsolated {
                        let store = AppStore.shared
                        if let first = store.current?.sessions.first {
                            store.canvas.pane(first.id)?.setUsage(SessionUsage(model: "claude-opus-5-5", totalTokens: 1_240_000, outputTokens: 48_000,
                                                                               contextTokens: 184_000, contextWindow: 1_000_000, cost: 3.42))
                        }
                        store.showUsage = true
                    }
                }
            }
            if CommandLine.arguments.contains("--hud") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { MainActor.assumeIsolated { VoiceController.shared.previewForSnapshot() } }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 9) {
                MainActor.assumeIsolated {
                    Snapshot.write(to: path)
                    NSApp.terminate(nil)
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            let running = AppStore.shared.status.values.filter { $0.state != .exited }.count
            guard running > 0, !AppDelegate.demo, !UserDefaults.standard.bool(forKey: "quit.dontAsk") else { return .terminateNow }
            let alert = NSAlert()
            alert.messageText = "Quit Protea?"
            alert.informativeText = "\(running) running session\(running == 1 ? "" : "s") will stop. Your layout is saved and comes back next time."
            alert.addButton(withTitle: "Quit")
            alert.addButton(withTitle: "Cancel")
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Don’t ask again"
            let reply = alert.runModal()
            if alert.suppressionButton?.state == .on { UserDefaults.standard.set(true, forKey: "quit.dontAsk") }
            return reply == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppStore.shared.shutdown() }
    }
}

/// Renders the main window to a PNG. Used with `--snapshot <path>` to check the UI without screen recording.
enum Snapshot {
    private typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    /// Asks the window server for an image of our own window (no screen-recording permission needed for own windows).
    @MainActor
    static func write(to path: String) {
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
              let symbol = dlsym(handle, "CGWindowListCreateImage") else { return }
        let create = unsafeBitCast(symbol, to: CreateImage.self)
        let windows = NSApp.windows.filter { $0.isVisible && $0.contentView != nil }.sorted { $0.frame.width > $1.frame.width }
        for (i, window) in windows.enumerated() {
            // includingWindow = 8; boundsIgnoreFraming = 1, bestResolution = 8
            guard let image = create(.null, 8, UInt32(window.windowNumber), 1 | 8)?.takeRetainedValue(),
                  let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { continue }
            let file = i == 0 ? path : path.replacingOccurrences(of: ".png", with: "-\(i).png")
            try? data.write(to: URL(fileURLWithPath: file))
        }
        try? AppStore.shared.canvas.debugText.write(toFile: path + ".txt", atomically: true, encoding: .utf8)
    }
}
