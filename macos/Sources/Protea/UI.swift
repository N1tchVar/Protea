import AppKit
import SwiftUI

// MARK: - Root

struct RootView: View {
    @ObservedObject var store = AppStore.shared

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 252)
            Rectangle().fill(Color.line).frame(width: 1)
            ZStack(alignment: .top) {
                CanvasRepresentable(controller: store.canvas)
                if let ws = store.current, ws.sessions.isEmpty {
                    EmptyStateView(workspace: ws)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
                TopBar()
                    .padding(.top, 12)
                    .padding(.horizontal, 14)
                VoiceHUD()
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 22)
            }
            .animation(.easeOut(duration: 0.25), value: store.current?.sessions.isEmpty)
        }
        .background(Color.ink)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }
}

struct CanvasRepresentable: NSViewRepresentable {
    let controller: CanvasController
    func makeNSView(context: Context) -> NSScrollView { controller.scrollView }
    func updateNSView(_ nsView: NSScrollView, context: Context) {}
}

// MARK: - Sidebar

struct SidebarView: View {
    @ObservedObject var store = AppStore.shared
    @State private var renaming: UUID?
    @State private var draftName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Room for the traffic lights.
            Color.clear.frame(height: 44)

            HStack(spacing: 10) {
                BrandMark(size: 26)
                Text("Protea")
                    .font(.system(size: 16, weight: .semibold))
                    .tracking(-0.4)
                    .foregroundStyle(Color.marble)
                Spacer()
                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.marble3)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 22)

            HStack {
                Text("WORKSPACES")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(Color.marble3)
                Spacer()
                Button(action: store.addWorkspace) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.marble2)
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("New workspace")
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(store.workspaces) { ws in
                        WorkspaceRow(workspace: ws, selected: ws.id == store.selectedID, onRename: {
                            draftName = ws.name
                            renaming = ws.id
                        })
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.never)

            Spacer(minLength: 0)
            SidebarFooter()
        }
        .background(
            LinearGradient(colors: [Color.sidebarBG, Color.ink], startPoint: .top, endPoint: .bottom)
        )
        .alert("Rename workspace", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $draftName)
            Button("Rename") { if let id = renaming { store.renameWorkspace(id, to: draftName) }; renaming = nil }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }
}

struct WorkspaceRow: View {
    @ObservedObject var store = AppStore.shared
    let workspace: WorkspaceRecord
    let selected: Bool
    let onRename: () -> Void
    @State private var hover = false

    var body: some View {
        let counts = store.counts(for: workspace)
        VStack(alignment: .leading, spacing: 2) {
            Button { store.show(workspace.id) } label: {
                HStack(spacing: 10) {
                    Image(systemName: selected ? "folder.fill" : "folder")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selected ? Color.azure : Color.marble3)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(workspace.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.marble)
                            .lineLimit(1)
                        Text(workspace.folder.abbreviatingHome)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.marble3)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 4)
                    if counts.needs > 0 {
                        CountBadge(n: counts.needs, color: .coral)
                    } else if counts.working > 0 {
                        CountBadge(n: counts.working, color: .azure)
                    } else if !workspace.sessions.isEmpty {
                        Text("\(workspace.sessions.count)")
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(Color.marble3)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if selected && !workspace.sessions.isEmpty {
                VStack(spacing: 1) {
                    ForEach(workspace.sessions) { s in SessionRow(session: s) }
                }
                .padding(.leading, 20)
                .padding(.trailing, 4)
                .padding(.bottom, 6)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(selected ? Color.white.opacity(0.055) : hover ? Color.white.opacity(0.03) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(selected ? Color.lineStrong : .clear, lineWidth: 0.5)
        )
        .onHover { hover = $0 }
        .contextMenu {
            Button("Rename…", action: onRename)
            Button("Show in Finder") { store.revealInFinder(workspace.id) }
            Divider()
            Button("Remove Workspace", role: .destructive) { store.removeWorkspace(workspace.id) }
                .disabled(store.workspaces.count < 2)
        }
    }
}

struct SessionRow: View {
    @ObservedObject var store = AppStore.shared
    let session: SessionRecord
    @State private var hover = false

    var body: some View {
        let agent = Agent.with(id: session.agentID)
        let status = store.status[session.id] ?? SessionStatus()
        let focused = store.focusedID == session.id
        Button { store.focus(session.id, zoom: true) } label: {
            HStack(spacing: 9) {
                AgentBadge(agent: agent, size: 20)
                Text(session.title)
                    .font(.system(size: 12.5, weight: focused ? .semibold : .regular))
                    .foregroundStyle(focused ? Color.marble : Color.marble2)
                    .lineLimit(1)
                Spacer(minLength: 4)
                StatusLabel(status: status)
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(focused ? Color.azure.opacity(0.14) : hover ? Color.white.opacity(0.04) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .contextMenu {
            Button("Zoom to Session") { store.focus(session.id, zoom: true) }
            Button("Restart") { store.restart(session.id) }
            Divider()
            Button("Close Session", role: .destructive) { store.close(session.id) }
        }
    }
}

struct StatusLabel: View {
    let status: SessionStatus

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 5) {
                StateDot(state: status.state)
                Text(text(now: context.date))
                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(status.state == .working || status.state == .needsYou ? status.state.color : Color.marble3)
            }
        }
    }

    private func text(now: Date) -> String {
        guard status.state == .idle else { return status.state.label }
        let s = Int(now.timeIntervalSince(status.since))
        if s < 60 { return "Idle" }
        if s < 3600 { return "\(s / 60)m" }
        return "\(s / 3600)h"
    }
}

struct CountBadge: View {
    let n: Int
    let color: Color
    var body: some View {
        Text("\(n)")
            .font(.system(size: 10.5, weight: .bold).monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .frame(height: 18)
            .background(color.opacity(0.15), in: Capsule())
    }
}

struct SidebarFooter: View {
    @ObservedObject var store = AppStore.shared

    var body: some View {
        let all = store.status.values
        let working = all.filter { $0.state == .working }.count
        let needs = all.filter { $0.state == .needsYou }.count
        HStack(spacing: 14) {
            Label("\(working) working", systemImage: "circle.fill")
                .foregroundStyle(working > 0 ? Color.azure : Color.marble3)
            Label("\(needs) need you", systemImage: "circle.fill")
                .foregroundStyle(needs > 0 ? Color.coral : Color.marble3)
        }
        .labelStyle(DotLabelStyle())
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Color.line).frame(height: 1) }
    }
}

struct DotLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 6))
            configuration.title
        }
    }
}

struct BrandMark: View {
    var size: CGFloat
    var body: some View {
        if let mark = Brand.mark {
            Image(nsImage: mark).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            Image(systemName: "leaf.fill").foregroundStyle(Color.azure).frame(width: size, height: size)
        }
    }
}

// MARK: - Top bar

struct TopBar: View {
    @ObservedObject var store = AppStore.shared

    var body: some View {
        HStack(spacing: 10) {
            if let ws = store.current {
                Button { store.revealInFinder(ws.id) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .foregroundStyle(Color.marble3)
                        Text(ws.name)
                            .foregroundStyle(Color.marble)
                            .fontWeight(.semibold)
                        Text(ws.folder.abbreviatingHome)
                            .foregroundStyle(Color.marble3)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.system(size: 12.5))
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassCapsule()
                .help("Show in Finder")
            }

            Spacer(minLength: 8)

            HStack(spacing: 2) {
                BarIconButton(symbol: "minus", help: "Zoom out (⌘−)", action: store.zoomOut)
                Button(action: store.actualSize) {
                    Text("\(Int((store.zoom * 100).rounded()))%")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color.marble2)
                        .frame(width: 48, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Actual size (⌘0)")
                BarIconButton(symbol: "plus", help: "Zoom in (⌘=)", action: store.zoomIn)
                Rectangle().fill(Color.lineStrong).frame(width: 1, height: 16).padding(.horizontal, 6)
                BarTextButton(symbol: "rectangle.dashed", title: "Overview", help: "Fit every session (⇧⌘0)", action: store.overview)
                BarTextButton(symbol: store.isTiled ? "rectangle.3.offgrid" : "square.grid.2x2",
                              title: store.isTiled ? "Untile" : "Tile",
                              help: "Arrange sessions in a grid (⇧⌘G)", action: store.toggleTile)
                UsageButton()
            }
            .padding(.horizontal, 6)
            .frame(height: 36)
            .glassCapsule()

            Spacer(minLength: 8)

            MicButton()

            Button { store.showNewSession.toggle() } label: {
                HStack(spacing: 7) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                    Text("New session").font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(
                    LinearGradient(colors: [Color(nsColor: NSColor(hex: 0x5CB0FF)), Color.azureDeep], startPoint: .top, endPoint: .bottom),
                    in: Capsule()
                )
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
                .shadow(color: Color.azure.opacity(0.35), radius: 12, y: 4)
                .contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
            .popover(isPresented: $store.showNewSession, arrowEdge: .bottom) {
                NewSessionPicker { agent in
                    store.showNewSession = false
                    store.newSession(agent)
                }
            }
        }
    }
}

extension AppStore {
    var isTiled: Bool { selectedID.map { tiled.contains($0) } ?? false }
}

struct BarIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(hover ? Color.marble : Color.marble2)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.white.opacity(hover ? 0.08 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

struct BarTextButton: View {
    let symbol: String
    let title: String
    let help: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11.5, weight: .medium))
                Text(title).font(.system(size: 12.5, weight: .medium))
            }
            .foregroundStyle(hover ? Color.marble : Color.marble2)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Capsule().fill(Color.white.opacity(hover ? 0.08 : 0)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - New session picker

struct NewSessionPicker: View {
    @ObservedObject var availability = AgentAvailability.shared
    let onPick: (Agent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("New session")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color.marble3)
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 6)
            ForEach(Array(Agent.all.enumerated()), id: \.element.id) { index, agent in
                AgentRow(agent: agent, shortcut: "⌥⌘\(index + 1)", installed: availability.isInstalled(agent)) { onPick(agent) }
            }
        }
        .padding(8)
        .frame(width: 330)
    }
}

struct AgentRow: View {
    let agent: Agent
    let shortcut: String
    let installed: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                AgentBadge(agent: agent, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.marble)
                    Text(agent.command.isEmpty ? "Your login shell" : agent.command)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.marble3)
                        .lineLimit(1)
                }
                Spacer()
                if !installed {
                    Text("Not installed")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.coral)
                        .padding(.horizontal, 7)
                        .frame(height: 18)
                        .background(Color.coral.opacity(0.14), in: Capsule())
                }
                Text(shortcut)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.marble3)
            }
            .padding(.horizontal, 10)
            .frame(height: 50)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hover ? Color.white.opacity(0.07) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    @ObservedObject var availability = AgentAvailability.shared
    @ObservedObject var store = AppStore.shared
    let workspace: WorkspaceRecord

    var body: some View {
        VStack(spacing: 0) {
            BrandMark(size: 58)
                .shadow(color: Color.azure.opacity(0.45), radius: 30)
            Text("Start a session")
                .font(.system(size: 30, weight: .semibold))
                .tracking(-0.9)
                .foregroundStyle(Color.marble)
                .padding(.top, 22)
            Text("Agents open in \(workspace.folder.abbreviatingHome). Run as many as you like, side by side.")
                .font(.system(size: 14))
                .foregroundStyle(Color.marble2)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 168, maximum: 178), spacing: 12)], spacing: 12) {
                ForEach(Agent.all) { agent in
                    AgentCard(agent: agent, installed: availability.isInstalled(agent)) { store.newSession(agent) }
                }
            }
            .frame(maxWidth: 960)
            .padding(.top, 30)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AgentCard: View {
    let agent: Agent
    let installed: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    AgentBadge(agent: agent, size: 34)
                    Spacer()
                    if !installed {
                        Text("Not installed")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(Color.coral)
                            .padding(.horizontal, 6)
                            .frame(height: 17)
                            .background(Color.coral.opacity(0.14), in: Capsule())
                    }
                }
                Spacer()
                Text(agent.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.marble)
                Text(agent.command.isEmpty ? "login shell" : agent.command)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.marble3)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 116, maxHeight: 116)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [Color.raised.opacity(hover ? 0.95 : 0.7), Color.paneBG], startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(hover ? Color.azure.opacity(0.55) : Color.lineStrong, lineWidth: hover ? 1 : 0.5)
            )
            .shadow(color: hover ? Color.azure.opacity(0.25) : .black.opacity(0.3), radius: hover ? 18 : 10, y: 6)
            .offset(y: hover ? -2 : 0)
            .animation(.easeOut(duration: 0.18), value: hover)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @AppStorage("terminal.fontSize") private var fontSize = 12.5
    @AppStorage("voice.submit") private var voiceSubmit = true

    var body: some View {
        Form {
            Section {
                ForEach(Agent.all.filter { $0.id != "shell" }) { agent in
                    CommandField(agent: agent)
                }
            } header: {
                Text("Agent commands")
            } footer: {
                Text("What each session type runs. New sessions use the change; running ones keep going.")
                    .foregroundStyle(.secondary)
            }
            Section("Voice") {
                Toggle("Press Return after dictating", isOn: $voiceSubmit)
                Text("Press ⌘D or the mic button, speak, then press Return to send it to the focused session. Esc cancels.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Terminal") {
                Stepper(value: $fontSize, in: 11...18, step: 0.5) {
                    Text("Font size: \(fontSize, specifier: "%.1f") pt")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding(.vertical, 8)
    }
}

struct CommandField: View {
    let agent: Agent
    @AppStorage private var command: String

    init(agent: Agent) {
        self.agent = agent
        _command = AppStorage(wrappedValue: "", Agent.commandKey(agent.id))
    }

    var body: some View {
        LabeledContent {
            TextField(agent.defaultCommand, text: $command)
                .font(.system(size: 12, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
        } label: {
            HStack(spacing: 8) {
                AgentBadge(agent: agent, size: 20)
                Text(agent.name)
            }
        }
    }
}


// MARK: - Voice

struct MicButton: View {
    @ObservedObject var voice = VoiceController.shared
    @State private var hover = false

    var body: some View {
        let on = voice.isActive
        Button { voice.toggle() } label: {
            Image(systemName: on ? "waveform" : "mic.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(on ? Color.white : hover ? Color.marble : Color.marble2)
                .symbolEffect(.variableColor.iterative, isActive: on)
                .frame(width: 36, height: 36)
                .background(Circle().fill(on ? Color.azure : Color.clear))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .glassCapsule()
        .onHover { hover = $0 }
        .help(on ? "Stop and send (Return)" : "Dictate a prompt (⌘D)")
    }
}

struct VoiceHUD: View {
    @ObservedObject var voice = VoiceController.shared
    @ObservedObject var store = AppStore.shared

    var body: some View {
        Group {
            switch voice.phase {
            case .idle:
                EmptyView()
            case let .failed(message):
                HStack(spacing: 12) {
                    Image(systemName: "mic.slash.fill").foregroundStyle(Color.coral)
                    Text(message).font(.system(size: 13)).foregroundStyle(Color.marble)
                    Button { voice.dismissError() } label: {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.marble3)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .frame(height: 48)
                .glassPanel(cornerRadius: 24)
            default:
                listening
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: voice.phase)
    }

    private var listening: some View {
        let target = store.dictationTarget
        return HStack(spacing: 16) {
            ZStack {
                Circle().fill(Color.azure.opacity(0.18))
                Circle().strokeBorder(Color.azure.opacity(0.5), lineWidth: 1)
                Image(systemName: "mic.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.azure)
            }
            .frame(width: 40, height: 40)

            Waveform(levels: voice.levels)
                .frame(width: 112, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(voice.transcript.isEmpty ? (voice.phase == .starting ? "Getting ready…" : "Listening…") : voice.transcript)
                    .font(.system(size: 14, weight: voice.transcript.isEmpty ? .regular : .medium))
                    .foregroundStyle(voice.transcript.isEmpty ? Color.marble3 : Color.marble)
                    .lineLimit(2)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let target {
                    HStack(spacing: 6) {
                        AgentBadge(agent: Agent.with(id: target.agentID), size: 14)
                        Text("to \(target.title)").font(.system(size: 11, weight: .medium)).foregroundStyle(Color.marble3)
                    }
                }
            }

            HStack(spacing: 6) {
                Button { voice.cancel() } label: {
                    Text("Esc").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.marble2)
                        .padding(.horizontal, 10).frame(height: 30)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(PressStyle())
                .help("Cancel")
                Button { voice.finish() } label: {
                    HStack(spacing: 5) {
                        Text("Send").font(.system(size: 12.5, weight: .semibold))
                        Image(systemName: "return").font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).frame(height: 30)
                    .background(Capsule().fill(Color.azure))
                }
                .buttonStyle(PressStyle())
                .disabled(voice.phase == .finishing)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .frame(width: 660, height: 72)
        .glassPanel(cornerRadius: 26)
        .shadow(color: Color.azure.opacity(0.25), radius: 30, y: 10)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

struct Waveform: View {
    let levels: [CGFloat]

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(Array(levels.enumerated()), id: \.offset) { i, level in
                Capsule()
                    .fill(LinearGradient(colors: [Color.sky, Color.azure], startPoint: .top, endPoint: .bottom))
                    .frame(width: 2.5, height: max(3, level * 30))
                    .opacity(0.35 + 0.65 * Double(i) / Double(max(levels.count - 1, 1)))
            }
        }
        .animation(.easeOut(duration: 0.08), value: levels)
    }
}

// MARK: - Usage

struct UsageButton: View {
    @ObservedObject var store = AppStore.shared
    @State private var hover = false

    var body: some View {
        let show = store.showUsage
        Button { store.showUsage.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.33percent").font(.system(size: 11.5, weight: .medium))
                Text("Usage").font(.system(size: 12.5, weight: .medium))
            }
            .foregroundStyle(hover || show ? Color.marble : Color.marble2)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Capsule().fill(Color.white.opacity(hover || show ? 0.08 : 0)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Tokens, context and limits")
        .popover(isPresented: $store.showUsage, arrowEdge: .bottom) { UsagePanel() }
    }
}

struct UsagePanel: View {
    @ObservedObject var usage = UsageMonitor.shared
    @ObservedObject var store = AppStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Usage")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.marble)

            UsageCard {
                HStack(spacing: 10) {
                    AgentBadge(agent: Agent.with(id: "claude"), size: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Claude Code · 5-hour window").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Color.marble)
                        if let w = usage.claudeWindow {
                            Text("Resets \(UsageFormat.time(w.resets)) · \(w.messages) replies")
                                .font(.system(size: 11)).foregroundStyle(Color.marble3)
                        } else {
                            Text("No Claude activity in the last 5 hours").font(.system(size: 11)).foregroundStyle(Color.marble3)
                        }
                    }
                    Spacer()
                    if let w = usage.claudeWindow {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(UsageFormat.tokens(w.tokens)).font(.system(size: 17, weight: .semibold).monospacedDigit()).foregroundStyle(Color.marble)
                            if let c = UsageFormat.cost(w.cost) {
                                Text("≈ \(c)").font(.system(size: 11).monospacedDigit()).foregroundStyle(Color.marble3)
                            }
                        }
                    }
                }
                if let w = usage.claudeWindow {
                    Meter(fraction: w.elapsedFraction, tint: .azure)
                        .help("Time elapsed in this window")
                }
            }

            if !usage.codexLimits.isEmpty {
                UsageCard {
                    HStack(spacing: 10) {
                        AgentBadge(agent: Agent.with(id: "codex"), size: 26)
                        Text("Codex plan limits").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Color.marble)
                        Spacer()
                    }
                    ForEach(usage.codexLimits) { limit in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(limit.label).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Color.marble2)
                                Spacer()
                                Text("\(Int(limit.usedPercent))% used" + (limit.resetsAt.map { " · resets \(UsageFormat.time($0))" } ?? ""))
                                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(Color.marble3)
                            }
                            Meter(fraction: limit.usedPercent / 100, tint: limit.usedPercent > 85 ? .coral : .azure)
                        }
                    }
                }
            }

            let rows = sessionRows
            VStack(alignment: .leading, spacing: 6) {
                Text("SESSIONS IN \(store.current?.name.uppercased() ?? "")")
                    .font(.system(size: 10, weight: .semibold)).tracking(0.9).foregroundStyle(Color.marble3)
                if rows.isEmpty {
                    Text("Claude Code and Codex sessions show their context and tokens here once they reply.")
                        .font(.system(size: 11.5)).foregroundStyle(Color.marble3)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(rows, id: \.0.id) { record, u in
                        HStack(spacing: 10) {
                            AgentBadge(agent: Agent.with(id: record.agentID), size: 20)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(record.title).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.marble).lineLimit(1)
                                    Spacer()
                                    Text("\(UsageFormat.tokens(u.totalTokens)) tok" + (UsageFormat.cost(u.cost).map { " · ≈ \($0)" } ?? ""))
                                        .font(.system(size: 10.5).monospacedDigit()).foregroundStyle(Color.marble3)
                                }
                                HStack(spacing: 8) {
                                    Meter(fraction: u.contextFraction, tint: u.contextFraction > 0.9 ? .coral : u.contextFraction > 0.7 ? Color(nsColor: NSColor(hex: 0xF2C46D)) : .azure)
                                    Text("\(UsageFormat.tokens(u.contextTokens)) / \(UsageFormat.tokens(u.contextWindow))")
                                        .font(.system(size: 10).monospacedDigit()).foregroundStyle(Color.marble3)
                                        .frame(width: 74, alignment: .trailing)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Text("Read from the transcripts Claude Code and Codex keep on this Mac. Costs are estimates at API list prices.")
                .font(.system(size: 10.5))
                .foregroundStyle(Color.marble3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 380)
    }

    private var sessionRows: [(SessionRecord, SessionUsage)] {
        (store.current?.sessions ?? []).compactMap { r in usage.sessions[r.id].map { (r, $0) } }
    }
}

struct UsageCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.line, lineWidth: 0.5))
    }
}

struct Meter: View {
    let fraction: Double
    let tint: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule().fill(tint).frame(width: max(3, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 5)
    }
}
