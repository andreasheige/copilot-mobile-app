import Foundation
import Combine

// One entry per unique AI tool (groups all PIDs together)
struct LocalAIProcess: Identifiable {
    let id: String           // binary name used as stable ID
    let binary: String
    let name: String         // display name e.g. "GitHub Copilot"
    let icon: String
    let pids: [Int]
    let tmuxTargets: [String] // tmux targets running this tool
}

struct LocalTmuxWindow: Identifiable {
    let id: String           // "session:window"
    let session: String
    let window: String
    let currentCommand: String
    let pid: Int
}

// Known AI CLI/app binary names to detect (matched against basename, case-insensitive)
private let AI_TOOLS: [(binary: String, display: String, icon: String)] = [
    ("copilot",  "GitHub Copilot", "terminal.fill"),
    ("claude",   "Claude CLI",     "atom"),
    ("Claude",   "Claude.app",     "atom"),
    ("codex",    "Codex",          "chevron.left.forwardslash.chevron.right"),
    ("aider",    "Aider",          "wand.and.stars"),
    ("continue", "Continue",       "arrow.right.circle"),
    ("gemini",   "Gemini",         "sparkles"),
    ("cline",    "Cline",          "terminal"),
    ("amp",      "Amp",            "bolt"),
]

@MainActor
final class LocalProcessWatcher: ObservableObject {
    @Published var aiProcesses: [LocalAIProcess] = []
    @Published var tmuxWindows: [LocalTmuxWindow] = []

    private var timer: Timer?

    init() {
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scan() }
        }
    }

    deinit { timer?.invalidate() }

    func scan() {
        Task.detached(priority: .background) {
            let (processes, windows) = Self.findAll()
            await MainActor.run {
                self.aiProcesses = processes
                self.tmuxWindows = windows
            }
        }
    }

    // MARK: - Process + tmux detection

    nonisolated private static func log(_ msg: String) {
        let line = "[\(Date())] \(msg)\n"
        let url = URL(fileURLWithPath: "/tmp/copilot-menu-bar.log")
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path) {
                if let fh = try? FileHandle(forWritingTo: url) {
                    fh.seekToEndOfFile(); fh.write(data); try? fh.close()
                }
            } else {
                try? data.write(to: url)
            }
        }
    }

    nonisolated private static func findAll() -> ([LocalAIProcess], [LocalTmuxWindow]) {
        log("--- scan start ---")
        let tmuxPath = findTmux()
        log("tmux path: '\(tmuxPath)'")
        let tmuxPanes = scanTmuxPanes()
        log("panes found: \(tmuxPanes.count)")
        for p in tmuxPanes { log("  pane: \(p.target) cmd=\(p.currentCommand) pids=\(p.pids)") }

        let windows = tmuxPanes.map {
            LocalTmuxWindow(id: $0.target, session: $0.session, window: $0.window,
                            currentCommand: $0.currentCommand, pid: $0.pids.first ?? 0)
        }

        guard let psOutput = shell("ps -axo pid=,comm= 2>/dev/null") else {
            return ([], windows)
        }

        // Map pid -> TmuxPane
        var pidToPane: [Int: TmuxPane] = [:]
        for pane in tmuxPanes {
            for pid in pane.pids { pidToPane[pid] = pane }
        }

        // Accumulate per-binary
        var byBinary: [String: (tool: (binary: String, display: String, icon: String), pids: [Int], targets: [String])] = [:]
        let selfPid = ProcessInfo.processInfo.processIdentifier

        for line in psOutput.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let spaceIdx = trimmed.firstIndex(of: " ") ?? trimmed.endIndex
            guard let pid = Int(trimmed[..<spaceIdx]), pid != selfPid else { continue }
            let comm = String(trimmed[trimmed.index(after: spaceIdx)...]).trimmingCharacters(in: .whitespaces)
            let basename = comm.components(separatedBy: "/").last ?? comm
            guard let tool = AI_TOOLS.first(where: { basename == $0.binary }) else { continue }

            var entry = byBinary[tool.binary] ?? (tool, [], [])
            guard !entry.pids.contains(pid) else { continue }
            entry.pids.append(pid)
            if let pane = pidToPane[pid] {
                let target = pane.target
                if !entry.targets.contains(target) { entry.targets.append(target) }
            }
            byBinary[tool.binary] = entry
        }

        let processes = byBinary.values.map { entry in
            LocalAIProcess(id: entry.tool.binary, binary: entry.tool.binary,
                           name: entry.tool.display, icon: entry.tool.icon,
                           pids: entry.pids, tmuxTargets: entry.targets)
        }.sorted { $0.pids.count > $1.pids.count }

        return (processes, windows)
    }

    private struct TmuxPane {
        let target: String       // "session:window"
        let session: String
        let window: String
        let currentCommand: String
        let pids: [Int]
    }

    nonisolated private static func scanTmuxPanes() -> [TmuxPane] {
        let tmuxPath = findTmux()
        guard !tmuxPath.isEmpty else { return [] }
        guard let output = run(tmuxPath, args: [
            "list-panes", "-a", "-F",
            "#{session_name}|#{window_name}|#{pane_pid}|#{pane_current_command}"
        ]) else { return [] }

        return output.components(separatedBy: .newlines).compactMap { line in
            let parts = line.split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count >= 3, let panePid = Int(parts[2]) else { return nil }
            let session = String(parts[0])
            let window  = String(parts[1])
            let currentCommand = parts.count >= 4 ? String(parts[3]) : ""
            let target = "\(session):\(window)"
            let children = childPIDs(of: panePid)
            return TmuxPane(target: target, session: session, window: window,
                            currentCommand: currentCommand, pids: [panePid] + children)
        }
    }

    nonisolated private static func findTmux() -> String {
        for p in ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"] {
            if FileManager.default.fileExists(atPath: p) { return p }
        }
        return ""
    }

    nonisolated private static func childPIDs(of pid: Int) -> [Int] {
        guard let output = run("/usr/bin/pgrep", args: ["-P", "\(pid)"]) else { return [] }
        let children = output.components(separatedBy: .newlines).compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        return children + children.flatMap { childPIDs(of: $0) }
    }

    /// Run an executable directly (no shell) and return stdout.
    nonisolated private static func run(_ exe: String, args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exe)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespaces)
    }

    /// Legacy shell helper for ps (which needs shell for the format flags).
    nonisolated private static func shell(_ command: String) -> String? {
        run("/bin/bash", args: ["-c", command])
    }
}
