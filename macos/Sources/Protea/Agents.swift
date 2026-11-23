import AppKit
import SwiftUI

/// A kind of session: an agent CLI or a plain shell. Commands can be changed in Settings.
struct Agent: Identifiable, Hashable {
    let id: String
    let name: String
    let defaultCommand: String
    let install: String?
    let symbol: String
    let tint: NSColor

    static let all: [Agent] = [
        Agent(id: "claude", name: "Claude Code", defaultCommand: "claude",
              install: "npm install -g @anthropic-ai/claude-code", symbol: "asterisk", tint: NSColor(hex: 0xE08A63)),
        Agent(id: "codex", name: "Codex", defaultCommand: "codex",
              install: "npm install -g @openai/codex", symbol: "chevron.left.forwardslash.chevron.right", tint: NSColor(hex: 0xEEF4FF)),
        Agent(id: "gemini", name: "Gemini", defaultCommand: "gemini",
              install: "npm install -g @google/gemini-cli", symbol: "sparkle", tint: NSColor(hex: 0x7CB2FF)),
        Agent(id: "gpt", name: "GPT", defaultCommand: "codex -m gpt-5",
              install: "npm install -g @openai/codex", symbol: "circle.hexagongrid", tint: NSColor(hex: 0x4FD1B0)),
        Agent(id: "shell", name: "Shell", defaultCommand: "",
              install: nil, symbol: "terminal", tint: NSColor(hex: 0xA8B9D4)),
    ]

    static func with(id: String) -> Agent { all.first { $0.id == id } ?? all[all.count - 1] }

    static func commandKey(_ id: String) -> String { "agent.\(id).command" }

    var command: String {
        let custom = UserDefaults.standard.string(forKey: Agent.commandKey(id))?.trimmingCharacters(in: .whitespaces)
        if let custom, !custom.isEmpty { return custom }
        return defaultCommand
    }

    /// The program the command runs, for the "is it installed" check.
    var binary: String? { command.split(separator: " ").first.map(String.init) }

    /// The command for one run. Claude Code gets its own session ID so Protea can find its transcript for usage.
    func command(sessionID: UUID) -> String {
        let cmd = command
        guard binary == "claude" else { return cmd }
        let flags = cmd.split(separator: " ").map(String.init)
        let resumes = flags.contains { ["--resume", "-r", "--continue", "-c", "--session-id"].contains($0) }
        return resumes ? cmd : "\(cmd) --session-id \(sessionID.uuidString.lowercased())"
    }

    /// A shell script: run the agent if it's installed, explain how to install it if not,
    /// then leave a login shell in the same folder when it exits.
    func launchScript(sessionID: UUID) -> String {
        let fallback = #"exec "${SHELL:-/bin/zsh}" -l"#
        guard let binary else { return fallback }
        var lines = ["clear"]
        let run = command(sessionID: sessionID)
        if let install {
            lines.append("if command -v \(binary.shellQuoted) >/dev/null 2>&1; then \(run); else printf '\\n  \\033[1m%s\\033[0m is not installed.\\n  Install it with:  \\033[36m%s\\033[0m\\n\\n' \(name.shellQuoted) \(install.shellQuoted); fi")
        } else {
            lines.append(run)
        }
        lines.append(fallback)
        return lines.joined(separator: "\n")
    }
}

/// Which agent CLIs are on the user's PATH, checked once through a login shell.
@MainActor
final class AgentAvailability: ObservableObject {
    static let shared = AgentAvailability()
    @Published private(set) var installed: Set<String> = []
    @Published private(set) var checked = false

    func refresh() {
        let binaries = Agent.all.compactMap(\.binary)
        let script = binaries.map { "command -v \($0.shellQuoted) >/dev/null 2>&1 && echo \($0.shellQuoted)" }.joined(separator: "; ")
        Task.detached {
            let found = Self.run(script)
            await MainActor.run {
                self.installed = Set(found.split(separator: "\n").map(String.init))
                self.checked = true
            }
        }
    }

    func isInstalled(_ agent: Agent) -> Bool {
        guard let binary = agent.binary else { return true }
        return !checked || installed.contains(binary)
    }

    nonisolated private static func run(_ script: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Session.userShell)
        process.arguments = ["-l", "-i", "-c", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
