import Foundation
import Observation
import ZoneCore

/// Chats with an agent CLI that sees Fokus only through its read-only MCP server.
@MainActor @Observable
final class AssistantStore {
    enum Role { case user, assistant }

    struct Message: Identifiable, Equatable {
        let id = UUID()
        let role: Role
        var text: String
        var failed = false
    }

    private(set) var messages: [Message] = []
    private(set) var running = false
    private(set) var lookingAt: String?
    @ObservationIgnored private var sessionID: String?
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var buffer = Data()
    @ObservationIgnored private var errors = Data()

    static let tools = ["fokus_heute", "fokus_nutzung", "fokus_wochenbericht", "fokus_entsperrungen", "fokus_einstellungen", "fokus_seitentitel"]

    var claudePath: String? { Self.findClaude() }

    func send(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !running else { return }
        messages.append(Message(role: .user, text: question))
        guard let claude = claudePath else {
            messages.append(Message(role: .assistant, text: L(
                "Claude Code wurde nicht gefunden. Installiere es mit `npm install -g @anthropic-ai/claude-code` und melde dich einmal im Terminal mit `claude` an.",
                "Claude Code was not found. Install it with `npm install -g @anthropic-ai/claude-code` and sign in once in Terminal with `claude`."), failed: true))
            return
        }
        do { try start(claude: claude, question: question) }
        catch { finish(failure: error.localizedDescription) }
    }

    func stop() {
        process?.terminate()
    }

    func reset() {
        stop()
        messages = []
        sessionID = nil
        lookingAt = nil
    }

    private func start(claude: String, question: String) throws {
        let folder = FokusPaths.data.appendingPathComponent("assistant", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let config = folder.appendingPathComponent("mcp.json")
        var environment = ["FOKUS_BUNDLE_ID": Bundle.main.bundleIdentifier ?? "local.fokus.app"]
        if let custom = ProcessInfo.processInfo.environment["FOKUS_DATA_DIR"] { environment["FOKUS_DATA_DIR"] = custom }
        let server: [String: Any] = ["command": Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/fokus-mcp").path, "env": environment]
        try JSONSerialization.data(withJSONObject: ["mcpServers": ["fokus": server]]).write(to: config, options: .atomic)

        // No built-in tools and no user settings: the agent can only read Fokus data, nothing on the Mac.
        var arguments = ["-p", question, "--output-format", "stream-json", "--verbose",
                         "--mcp-config", config.path, "--strict-mcp-config", "--tools", "", "--setting-sources", "",
                         "--allowedTools", Self.tools.map { "mcp__fokus__" + $0 }.joined(separator: " "),
                         "--append-system-prompt", Self.briefing()]
        if let sessionID { arguments += ["--resume", sessionID] }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: claude)
        task.arguments = arguments
        task.currentDirectoryURL = folder
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = ((claude as NSString).deletingLastPathComponent) + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        task.environment = env
        task.standardInput = FileHandle.nullDevice
        let output = Pipe(), failure = Pipe()
        task.standardOutput = output
        task.standardError = failure
        buffer = Data()
        errors = Data()
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            Task { @MainActor in self?.receive(chunk) }
        }
        failure.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            Task { @MainActor in self?.errors.append(chunk) }
        }
        task.terminationHandler = { [weak self] ended in
            output.fileHandleForReading.readabilityHandler = nil
            failure.fileHandleForReading.readabilityHandler = nil
            let status = ended.terminationStatus, reason = ended.terminationReason
            Task { @MainActor in self?.ended(status: status, interrupted: reason == .uncaughtSignal) }
        }
        messages.append(Message(role: .assistant, text: ""))
        running = true
        lookingAt = nil
        process = task
        try task.run()
    }

    private func receive(_ chunk: Data) {
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer[..<newline]
            buffer.removeSubrange(...newline)
            guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            handle(event)
        }
    }

    private func handle(_ event: [String: Any]) {
        if let id = event["session_id"] as? String { sessionID = id }
        switch event["type"] as? String {
        case "assistant":
            let content = (event["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            for block in content {
                if block["type"] as? String == "text", let text = block["text"] as? String, !text.isEmpty {
                    appendToAnswer(text)
                    lookingAt = nil
                } else if block["type"] as? String == "tool_use", let name = block["name"] as? String {
                    lookingAt = Self.label(for: name)
                }
            }
        case "result":
            if event["is_error"] as? Bool == true {
                finish(failure: event["result"] as? String ?? L("Unbekannter Fehler", "Unknown error"))
            } else if currentAnswer.isEmpty, let text = event["result"] as? String {
                appendToAnswer(text)
            }
        default: break
        }
    }

    private var currentAnswer: String { messages.last?.role == .assistant ? messages.last?.text ?? "" : "" }

    private func appendToAnswer(_ text: String) {
        guard let index = messages.indices.last, messages[index].role == .assistant else { return }
        messages[index].text += messages[index].text.isEmpty ? text : "\n\n" + text
    }

    private func ended(status: Int32, interrupted: Bool) {
        process = nil
        running = false
        lookingAt = nil
        if interrupted { finish(failure: L("Abgebrochen.", "Stopped.")); return }
        guard status != 0 || currentAnswer.isEmpty else { return }
        let detail = String(decoding: errors, as: UTF8.self).split(separator: "\n").last.map(String.init)
        finish(failure: detail ?? L("Claude Code hat nicht geantwortet. Bist du im Terminal mit `claude` angemeldet?",
                                     "Claude Code did not answer. Are you signed in with `claude` in Terminal?"))
    }

    private func finish(failure: String) {
        running = false
        if let index = messages.indices.last, messages[index].role == .assistant, messages[index].text.isEmpty {
            messages[index].text = failure
            messages[index].failed = true
        } else if !failure.isEmpty, messages.last?.failed != true {
            messages.append(Message(role: .assistant, text: failure, failed: true))
        }
    }

    private static func label(for tool: String) -> String {
        switch tool.replacingOccurrences(of: "mcp__fokus__", with: "") {
        case "fokus_heute": L("deinen heutigen Tag", "your day")
        case "fokus_nutzung": L("deine Nutzung", "your usage")
        case "fokus_wochenbericht": L("deinen Wochenbericht", "your weekly report")
        case "fokus_entsperrungen": L("deine Entsperrungen", "your unlocks")
        case "fokus_einstellungen": L("deine Einstellungen", "your settings")
        case "fokus_seitentitel": L("deine Seitentitel", "your page titles")
        default: L("deine Daten", "your data")
        }
    }

    private static func briefing() -> String {
        let today = Date().formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(AppLanguage.locale))
        return L("""
        Du bist der Coach in der Mac-App Fokus, einem Website-Blocker mit Zeiterfassung. Heute ist \(today).
        Hol dir vor jeder Antwort die echten Zahlen über die fokus-Werkzeuge, rate nie.
        Antworte auf Deutsch, kurz und direkt, ohne Floskeln. Nenne Zahlen und gib höchstens drei konkrete nächste Schritte.
        Du kannst nichts ändern, nur lesen. Schlage Änderungen vor und sag, wo man sie in Fokus findet:
        Sperrlisten, Zeitpläne, Fokus (Sitzung oder Hard Mode starten), Entsperren, Kategorien, Einstellungen.
        """, """
        You are the coach inside Fokus, a Mac website blocker with time tracking. Today is \(today).
        Fetch real numbers with the fokus tools before every answer, never guess.
        Answer in English, short and direct. Give numbers and at most three concrete next steps.
        You can only read, not change anything. Suggest changes and say where to find them in Fokus:
        Block Lists, Schedules, Focus (start a session or Hard Mode), Unlock, Categories, Settings.
        """)
    }

    /// The CLI lives where its installer put it; apps don't inherit the shell's PATH.
    private static func findClaude() -> String? {
        let home = NSHomeDirectory()
        var candidates = [UserDefaults.standard.string(forKey: "claudePath")].compactMap { $0 }
        let nvm = home + "/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvm) {
            candidates += versions.sorted(by: >).map { "\(nvm)/\($0)/bin/claude" }
        }
        candidates += [home + "/.claude/local/claude", home + "/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
