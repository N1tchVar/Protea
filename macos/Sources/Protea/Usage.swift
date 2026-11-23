import Foundation
import AppKit

// MARK: - Models

struct RateLimit: Equatable, Sendable, Identifiable {
    var id: String { label }
    let label: String
    let usedPercent: Double
    let resetsAt: Date?
}

/// What one session has used, read from the agent's own transcript on disk.
struct SessionUsage: Equatable, Sendable {
    var model: String?
    var totalTokens = 0
    var outputTokens = 0
    var contextTokens = 0
    var contextWindow = 200_000
    var cost: Double?
    var limits: [RateLimit] = []

    var contextFraction: Double {
        contextWindow > 0 ? min(1, Double(contextTokens) / Double(contextWindow)) : 0
    }
}

/// Claude Code's rolling 5-hour window, across every Claude session on this Mac.
struct ClaudeWindow: Equatable, Sendable {
    let start: Date
    let resets: Date
    let tokens: Int
    let cost: Double?
    let messages: Int

    var elapsedFraction: Double {
        min(1, max(0, Date().timeIntervalSince(start) / resets.timeIntervalSince(start)))
    }
}

// MARK: - Pricing (API list prices, $ per million tokens)

struct Pricing: Sendable {
    let input: Double
    let output: Double
    let cacheRead: Double

    /// Most specific prefixes first. Unknown models get no cost, only tokens.
    private static let table: [(String, Pricing, Int)] = [
        ("fable-5-1", Pricing(input: 10, output: 50, cacheRead: 0.25), 1_000_000),
        ("mythos-5-1", Pricing(input: 10, output: 50, cacheRead: 0.25), 1_000_000),
        ("fable-5", Pricing(input: 10, output: 50, cacheRead: 1.0), 1_000_000),
        ("opus-5-5", Pricing(input: 4, output: 20, cacheRead: 0.20), 1_000_000),
        ("opus-5", Pricing(input: 5, output: 25, cacheRead: 0.50), 1_000_000),
        ("opus-4-8", Pricing(input: 5, output: 25, cacheRead: 0.50), 1_000_000),
        ("opus-4-7", Pricing(input: 5, output: 25, cacheRead: 0.50), 1_000_000),
        ("opus-4-6", Pricing(input: 5, output: 25, cacheRead: 0.50), 1_000_000),
        ("sonnet-5-5", Pricing(input: 2, output: 10, cacheRead: 0.20), 1_000_000),
        ("sonnet-5", Pricing(input: 2, output: 10, cacheRead: 0.20), 1_000_000),
        ("sonnet-4-6", Pricing(input: 3, output: 15, cacheRead: 0.30), 1_000_000),
        ("haiku-4-5", Pricing(input: 1, output: 5, cacheRead: 0.10), 200_000),
    ]

    static func lookup(_ model: String) -> (Pricing, Int)? {
        let m = model.lowercased()
        return table.first { m.contains($0.0) }.map { ($0.1, $0.2) }
    }

    /// Cache writes bill at 1.25× input (5-minute) or 2× input (1-hour).
    func cost(input: Int, write5m: Int, write1h: Int, read: Int, output: Int) -> Double {
        (Double(input) * self.input
            + Double(write5m) * self.input * 1.25
            + Double(write1h) * self.input * 2
            + Double(read) * cacheRead
            + Double(output) * self.output) / 1_000_000
    }
}

// MARK: - Formatting

enum UsageFormat {
    static func tokens(_ n: Int) -> String {
        switch n {
        case ..<1_000: return "\(n)"
        case ..<100_000: return String(format: "%.1fk", Double(n) / 1_000).replacingOccurrences(of: ".0k", with: "k")
        case ..<1_000_000: return "\(n / 1_000)k"
        default: return String(format: "%.1fM", Double(n) / 1_000_000).replacingOccurrences(of: ".0M", with: "M")
        }
    }

    static func cost(_ c: Double?) -> String? {
        guard let c else { return nil }
        return c < 0.01 ? "<$0.01" : String(format: "$%.2f", c)
    }

    static func time(_ d: Date?) -> String {
        guard let d else { return "" }
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInToday(d) ? "h:mm a" : "EEE h:mm a"
        return f.string(from: d)
    }
}

// MARK: - Monitor

/// Polls transcripts in the background and publishes usage for the UI.
@MainActor
final class UsageMonitor: ObservableObject {
    static let shared = UsageMonitor()

    @Published private(set) var sessions: [UUID: SessionUsage] = [:]
    @Published private(set) var claudeWindow: ClaudeWindow?
    @Published private(set) var codexLimits: [RateLimit] = []

    private var tracked: [UUID: UsageWorker.Job] = [:]
    private let worker = UsageWorker()
    private let queue = DispatchQueue(label: "protea.usage", qos: .utility)
    private var timer: Timer?
    private var ticks = 0
    private var polling = false

    func start() {
        guard timer == nil else { return }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { _ in
            MainActor.assumeIsolated { UsageMonitor.shared.poll() }
        }
    }

    func track(pane: UUID, agent: Agent, runID: UUID, cwd: String, launchedAt: Date) {
        switch agent.binary {
        case "claude": tracked[pane] = .claude(sessionID: runID.uuidString.lowercased(), cwd: cwd)
        case "codex": tracked[pane] = .codex(launchedAt: launchedAt, cwd: cwd)
        default: tracked[pane] = nil
        }
        sessions[pane] = nil
    }

    func untrack(pane: UUID) {
        tracked[pane] = nil
        sessions[pane] = nil
        queue.async { [worker] in worker.forget(pane) }
    }

    private func poll() {
        guard !polling else { return }
        polling = true
        ticks += 1
        let jobs = tracked
        let includeWindow = ticks % 3 == 1
        queue.async { [worker] in
            let result = worker.poll(jobs: jobs, includeWindow: includeWindow)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let monitor = UsageMonitor.shared
                    monitor.polling = false
                    for (pane, usage) in result.sessions where monitor.tracked[pane] != nil {
                        if monitor.sessions[pane] != usage {
                            monitor.sessions[pane] = usage
                            AppStore.shared.canvas.pane(pane)?.setUsage(usage)
                        }
                    }
                    if includeWindow, monitor.claudeWindow != result.window { monitor.claudeWindow = result.window }
                    let limits = result.sessions.values.compactMap { $0.limits.isEmpty ? nil : $0.limits }.first ?? monitor.codexLimits
                    if monitor.codexLimits != limits { monitor.codexLimits = limits }
                }
            }
        }
    }
}

// MARK: - Worker (runs on the usage queue only)

final class UsageWorker: @unchecked Sendable {
    enum Job: Sendable, Equatable {
        case claude(sessionID: String, cwd: String)
        case codex(launchedAt: Date, cwd: String)
    }

    struct Result: Sendable {
        var sessions: [UUID: SessionUsage] = [:]
        var window: ClaudeWindow?
    }

    private struct ClaudeEntry {
        let time: Date
        let tokens: Int
        let cost: Double?
    }

    private final class ClaudeSession {
        let reader: JSONLReader
        var seen = Set<String>()
        var usage = SessionUsage()
        var cost: Double = 0
        var costKnown = true
        init(url: URL) { reader = JSONLReader(url: url) }
    }

    private final class CodexSession {
        let reader: JSONLReader
        var usage = SessionUsage(contextWindow: 272_000)
        init(url: URL) { reader = JSONLReader(url: url) }
    }

    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var claude: [UUID: ClaudeSession] = [:]
    private var codex: [UUID: CodexSession] = [:]
    private var codexClaimed = Set<URL>()
    private var windowReaders: [URL: JSONLReader] = [:]
    private var windowEntries: [String: ClaudeEntry] = [:]
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    func forget(_ pane: UUID) {
        claude[pane] = nil
        if let c = codex.removeValue(forKey: pane) { codexClaimed.remove(c.reader.url) }
    }

    func poll(jobs: [UUID: Job], includeWindow: Bool) -> Result {
        var result = Result()
        for (pane, job) in jobs {
            switch job {
            case let .claude(sessionID, cwd):
                if let u = pollClaude(pane: pane, sessionID: sessionID, cwd: cwd) { result.sessions[pane] = u }
            case let .codex(launchedAt, cwd):
                if let u = pollCodex(pane: pane, launchedAt: launchedAt, cwd: cwd) { result.sessions[pane] = u }
            }
        }
        if includeWindow { result.window = claudeWindow() }
        return result
    }

    // MARK: Claude

    private var claudeProjects: URL { home.appendingPathComponent(".claude/projects", isDirectory: true) }

    private func pollClaude(pane: UUID, sessionID: String, cwd: String) -> SessionUsage? {
        if claude[pane] == nil {
            guard let url = findClaudeTranscript(sessionID: sessionID, cwd: cwd) else { return nil }
            claude[pane] = ClaudeSession(url: url)
        }
        guard let s = claude[pane] else { return nil }
        for line in s.reader.newLines() {
            guard line["type"] as? String == "assistant",
                  let message = line["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any] else { continue }
            let key = (message["id"] as? String ?? UUID().uuidString) + (line["requestId"] as? String ?? "")
            guard s.seen.insert(key).inserted else { continue }
            let parts = Self.claudeParts(usage)
            let model = message["model"] as? String ?? s.usage.model ?? ""
            s.usage.model = model
            s.usage.totalTokens += parts.total
            s.usage.outputTokens += parts.output
            s.usage.contextTokens = parts.input + parts.write5m + parts.write1h + parts.read
            if let (price, window) = Pricing.lookup(model) {
                s.usage.contextWindow = window
                s.cost += price.cost(input: parts.input, write5m: parts.write5m, write1h: parts.write1h, read: parts.read, output: parts.output)
            } else {
                s.costKnown = false
                if s.usage.contextTokens > s.usage.contextWindow { s.usage.contextWindow = 1_000_000 }
            }
            s.usage.cost = s.costKnown ? s.cost : nil
        }
        return s.seen.isEmpty ? nil : s.usage
    }

    private static func claudeParts(_ usage: [String: Any]) -> (input: Int, write5m: Int, write1h: Int, read: Int, output: Int, total: Int) {
        let input = usage["input_tokens"] as? Int ?? 0
        let output = usage["output_tokens"] as? Int ?? 0
        let read = usage["cache_read_input_tokens"] as? Int ?? 0
        let creation = usage["cache_creation_input_tokens"] as? Int ?? 0
        var w5 = creation, w1 = 0
        if let split = usage["cache_creation"] as? [String: Any] {
            w5 = split["ephemeral_5m_input_tokens"] as? Int ?? 0
            w1 = split["ephemeral_1h_input_tokens"] as? Int ?? 0
            if w5 + w1 == 0 { w5 = creation }
        }
        return (input, w5, w1, read, output, input + creation + read + output)
    }

    private func findClaudeTranscript(sessionID: String, cwd: String) -> URL? {
        // Claude Code names the project folder after the path, with every other character turned into "-".
        let encoded = String(cwd.map { $0.isLetter || $0.isNumber ? $0 : "-" })
        let direct = claudeProjects.appendingPathComponent(encoded).appendingPathComponent("\(sessionID).jsonl")
        if FileManager.default.fileExists(atPath: direct.path) { return direct }
        let dirs = (try? FileManager.default.contentsOfDirectory(at: claudeProjects, includingPropertiesForKeys: nil)) ?? []
        for dir in dirs {
            let candidate = dir.appendingPathComponent("\(sessionID).jsonl")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    /// Mirrors how Claude's usage blocks work: a block starts on the hour of its first message and lasts five hours.
    private func claudeWindow() -> ClaudeWindow? {
        let now = Date()
        let horizon = now.addingTimeInterval(-10 * 3600)
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: claudeProjects, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for dir in dirs {
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for file in files where file.pathExtension == "jsonl" {
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                guard modified > horizon else { continue }
                let reader = windowReaders[file] ?? JSONLReader(url: file)
                windowReaders[file] = reader
                for line in reader.newLines() {
                    guard line["type"] as? String == "assistant",
                          let message = line["message"] as? [String: Any],
                          let usage = message["usage"] as? [String: Any],
                          let stamp = line["timestamp"] as? String,
                          let time = iso.date(from: stamp), time > horizon else { continue }
                    let key = (message["id"] as? String ?? stamp) + (line["requestId"] as? String ?? "")
                    if windowEntries[key] != nil { continue }
                    let p = Self.claudeParts(usage)
                    let cost = Pricing.lookup(message["model"] as? String ?? "")
                        .map { $0.0.cost(input: p.input, write5m: p.write5m, write1h: p.write1h, read: p.read, output: p.output) }
                    windowEntries[key] = ClaudeEntry(time: time, tokens: p.total, cost: cost)
                }
            }
        }
        windowEntries = windowEntries.filter { $0.value.time > horizon }

        let sorted = windowEntries.values.sorted { $0.time < $1.time }
        guard let first = sorted.first else { return nil }
        let block: TimeInterval = 5 * 3600
        var start = Self.floorHour(first.time)
        var last = first.time
        var current: [ClaudeEntry] = []
        for e in sorted {
            if e.time >= start.addingTimeInterval(block) || e.time.timeIntervalSince(last) > block {
                start = Self.floorHour(e.time)
                current = []
            }
            current.append(e)
            last = e.time
        }
        let resets = start.addingTimeInterval(block)
        guard now < resets else { return nil }
        let costs = current.map(\.cost)
        return ClaudeWindow(start: start, resets: resets,
                            tokens: current.reduce(0) { $0 + $1.tokens },
                            cost: costs.contains { $0 == nil } ? nil : costs.reduce(0) { $0 + ($1 ?? 0) },
                            messages: current.count)
    }

    private static func floorHour(_ d: Date) -> Date {
        Calendar.current.dateInterval(of: .hour, for: d)?.start ?? d
    }

    // MARK: Codex

    private func pollCodex(pane: UUID, launchedAt: Date, cwd: String) -> SessionUsage? {
        if codex[pane] == nil {
            guard let url = findCodexRollout(after: launchedAt, cwd: cwd) else { return nil }
            codexClaimed.insert(url)
            codex[pane] = CodexSession(url: url)
        }
        guard let s = codex[pane] else { return nil }
        var sawTokens = s.usage.totalTokens > 0
        for line in s.reader.newLines() {
            let payload = line["payload"] as? [String: Any] ?? [:]
            if line["type"] as? String == "turn_context", let model = payload["model"] as? String { s.usage.model = model }
            guard payload["type"] as? String == "token_count" else { continue }
            if let info = payload["info"] as? [String: Any] {
                if let total = info["total_token_usage"] as? [String: Any] {
                    s.usage.totalTokens = total["total_tokens"] as? Int ?? s.usage.totalTokens
                    s.usage.outputTokens = total["output_tokens"] as? Int ?? s.usage.outputTokens
                    sawTokens = true
                }
                if let last = info["last_token_usage"] as? [String: Any] {
                    s.usage.contextTokens = last["total_tokens"] as? Int ?? s.usage.contextTokens
                }
                if let window = info["model_context_window"] as? Int, window > 0 { s.usage.contextWindow = window }
            }
            if let limits = payload["rate_limits"] as? [String: Any] {
                s.usage.limits = ["primary", "secondary"].compactMap { Self.codexLimit(limits[$0] as? [String: Any], line: line) }
            }
        }
        return sawTokens ? s.usage : nil
    }

    private static func codexLimit(_ raw: [String: Any]?, line: [String: Any]) -> RateLimit? {
        guard let raw, let used = (raw["used_percent"] as? Double) ?? (raw["used_percent"] as? Int).map(Double.init) else { return nil }
        let minutes = raw["window_minutes"] as? Int ?? 0
        let label = minutes >= 1440 ? (minutes >= 7 * 1440 ? "Weekly" : "\(minutes / 1440)-day") : minutes > 0 ? "\(minutes / 60)-hour" : "Limit"
        var resets: Date?
        if let at = (raw["resets_at"] as? Double) ?? (raw["resets_at"] as? Int).map(Double.init) {
            resets = Date(timeIntervalSince1970: at)
        } else if let inSeconds = (raw["resets_in_seconds"] as? Double) ?? (raw["resets_in_seconds"] as? Int).map(Double.init) {
            resets = Date().addingTimeInterval(inSeconds)
        }
        return RateLimit(label: label, usedPercent: used, resetsAt: resets)
    }

    private func findCodexRollout(after launchedAt: Date, cwd: String) -> URL? {
        let fm = FileManager.default
        let root = home.appendingPathComponent(".codex/sessions", isDirectory: true)
        let cal = Calendar.current
        var candidates: [(URL, Date)] = []
        for dayOffset in [0, -1] {
            guard let day = cal.date(byAdding: .day, value: dayOffset, to: Date()) else { continue }
            let c = cal.dateComponents([.year, .month, .day], from: day)
            let dir = root.appendingPathComponent(String(format: "%04d/%02d/%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0))
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey])) ?? []
            for f in files where f.pathExtension == "jsonl" && !codexClaimed.contains(f) {
                let created = (try? f.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                if created >= launchedAt.addingTimeInterval(-5) { candidates.append((f, created)) }
            }
        }
        for (url, _) in candidates.sorted(by: { $0.1 < $1.1 }) {
            guard let first = JSONLReader.firstLine(of: url) else { continue }
            let payload = first["payload"] as? [String: Any] ?? first
            if (payload["cwd"] as? String).map({ URL(fileURLWithPath: $0).standardized.path == URL(fileURLWithPath: cwd).standardized.path }) ?? false {
                return url
            }
        }
        return nil
    }
}

// MARK: - Incremental JSONL reading

final class JSONLReader {
    let url: URL
    private var offset: UInt64 = 0
    private var partial = Data()

    init(url: URL) { self.url = url }

    /// Lines appended since the last call, parsed. A half-written last line waits for the next call.
    func newLines() -> [[String: Any]] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        if size < offset { offset = 0; partial = Data() }
        guard size > offset else { return [] }
        try? handle.seek(toOffset: offset)
        let data = (try? handle.readToEnd()) ?? Data()
        offset += UInt64(data.count)
        var buffer = partial
        buffer.append(data)
        var lines: [[String: Any]] = []
        var start = buffer.startIndex
        while let newline = buffer[start...].firstIndex(of: 0x0A) {
            let slice = buffer[start..<newline]
            if !slice.isEmpty, let obj = try? JSONSerialization.jsonObject(with: slice) as? [String: Any] { lines.append(obj) }
            start = buffer.index(after: newline)
        }
        partial = Data(buffer[start...])
        return lines
    }

    static func firstLine(of url: URL) -> [String: Any]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let chunk = (try? handle.read(upToCount: 64 * 1024)) ?? Data()
        let line = chunk.split(separator: 0x0A, maxSplits: 1).first ?? chunk
        return try? JSONSerialization.jsonObject(with: line) as? [String: Any]
    }
}
