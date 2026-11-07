import Foundation
import ZoneCore

// A read-only MCP server over stdio. Claude asks for Fokus data; nothing here changes it.

let dataDirectory: URL = {
    if let custom = ProcessInfo.processInfo.environment["FOKUS_DATA_DIR"], !custom.isEmpty { return URL(fileURLWithPath: custom) }
    return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Fokus")
}()
let bundleID = ProcessInfo.processInfo.environment["FOKUS_BUNDLE_ID"] ?? "local.fokus.app"
let usage = UsageStore(directory: dataDirectory.appendingPathComponent("usage"))
var calendar: Calendar = {
    var value = Calendar(identifier: .gregorian)
    value.firstWeekday = 2
    value.timeZone = .autoupdatingCurrent
    return value
}()

struct ToolError: Error { let message: String }

func document() -> ZoneDocument {
    (try? DocumentStore(url: dataDirectory.appendingPathComponent("sessions.json")).load()) ?? ZoneDocument()
}

func categories() -> CategoryConfig {
    let url = dataDirectory.appendingPathComponent("categories.json")
    return (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(CategoryConfig.self, from: $0) } ?? .defaults()
}

func minutes(_ seconds: Double) -> Int { Int((seconds / 60).rounded()) }
/// Local calendar day; the ISO formatter would use UTC and shift late-evening dates.
func day(_ date: Date) -> String {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
}

func parseDay(_ value: Any?, fallback: Date) throws -> Date {
    guard let text = value as? String, !text.isEmpty else { return calendar.startOfDay(for: fallback) }
    var parser = Date.ISO8601FormatStyle().year().month().day()
    parser.timeZone = .autoupdatingCurrent
    guard let date = try? parser.parse(text) else { throw ToolError(message: "Datum \(text) nicht lesbar, erwartet YYYY-MM-DD.") }
    return calendar.startOfDay(for: date)
}

func dates(from start: Date, to end: Date) -> [Date] {
    var result: [Date] = []
    var current = start
    while current <= end, result.count < 400 {
        result.append(current)
        current = calendar.date(byAdding: .day, value: 1, to: current) ?? end.addingTimeInterval(1)
    }
    return result
}

struct Context {
    let doc = document()
    let config = categories()
    var blocked: [String] { doc.blockLists.flatMap(\.domains) }
    func summary(_ days: [UsageDay]) -> UsageSummary {
        UsageSummary(days: days, classify: config.classifier(blocked: blocked), group: config.grouper(blocked: blocked), titleRule: config.matcher)
    }
}

func totals(_ value: UsageTotals) -> [String: Any] {
    ["aktiv_min": minutes(value.total), "arbeit_min": minutes(value.work), "neutral_min": minutes(value.neutral),
     "ablenkung_min": minutes(value.distraction), "fokus_score_prozent": value.score]
}

func items(_ summary: UsageSummary, config: CategoryConfig, limit: Int) -> [[String: Any]] {
    summary.items.prefix(limit).map { item in
        ["name": item.name, "typ": item.isSite ? "website" : "app", "minuten": minutes(item.seconds),
         "wertung": item.category.rawValue, "kategorie": config.path(item.groupID)]
    }
}

func groups(_ summary: UsageSummary, config: CategoryConfig) -> [[String: Any]] {
    summary.byGroup.compactMap { id, seconds in
        seconds >= 60 ? ["kategorie": config.path(id), "minuten": minutes(seconds)] : nil
    }.sorted { ($0["minuten"] as? Int ?? 0) > ($1["minuten"] as? Int ?? 0) }
}

func attempts() -> [String: [String: Int]] {
    // Inside Fokus.app this binary shares the app's identifier, so its own defaults are the app's.
    let defaults = Bundle.main.bundleIdentifier == bundleID ? UserDefaults.standard : UserDefaults(suiteName: bundleID)
    return defaults?.dictionary(forKey: "blockedAttempts") as? [String: [String: Int]] ?? [:]
}

// MARK: Tools

func usageRange(_ args: [String: Any]) throws -> Any {
    let context = Context()
    let today = calendar.startOfDay(for: Date())
    let end = try parseDay(args["bis"], fallback: today)
    let start = try parseDay(args["von"], fallback: calendar.date(byAdding: .day, value: -6, to: end) ?? end)
    guard start <= end else { throw ToolError(message: "von liegt nach bis.") }
    let span = dates(from: start, to: end)
    let loaded = span.map { usage.load($0) }
    let summary = context.summary(loaded)
    let perDay = zip(span, loaded).map { date, value -> [String: Any] in
        ["datum": day(date), "wochentag": date.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "de_DE")))]
            .merging(totals(context.summary([value]).totals)) { a, _ in a }
    }
    return [
        "zeitraum": ["von": day(start), "bis": day(end)],
        "summe": totals(summary.totals),
        "tage": perDay,
        "nach_kategorie": groups(summary, config: context.config),
        "top_apps_und_websites": items(summary, config: context.config, limit: Int(args["limit"] as? Double ?? 25)),
        "ablenkung_nach_stunde_min": Dictionary(uniqueKeysWithValues: summary.distractionByHour.enumerated()
            .filter { $0.element >= 60 }.map { (String($0.offset), minutes($0.element)) }),
        "hinweis": "Aktive Zeit ohne Pausen über 3 Minuten. Fokus-Score = Arbeit / (Arbeit + Ablenkung).",
    ]
}

func today(_ args: [String: Any]) throws -> Any {
    let context = Context()
    let date = calendar.startOfDay(for: Date())
    let summary = context.summary([usage.load(date)])
    let hours = summary.byHour.enumerated().filter { $0.element.total >= 60 }.map { hour, value -> [String: Any] in
        ["stunde": hour, "arbeit_min": minutes(value.work), "neutral_min": minutes(value.neutral), "ablenkung_min": minutes(value.distraction)]
    }
    let active = SessionEngine.activeSessions(in: context.doc, at: Date()).map { session -> [String: Any] in
        ["name": session.name, "bis": session.endsAt.formatted(date: .omitted, time: .shortened), "streng": session.isStrict,
         "gesperrt": session.blockList.blocksEverything ? ["alles außer Ausnahmen"] : session.blockList.domains]
    }
    return [
        "datum": day(date),
        "summe": totals(summary.totals),
        "stunden": hours,
        "nach_kategorie": groups(summary, config: context.config),
        "top_apps_und_websites": items(summary, config: context.config, limit: 20),
        "laufende_sitzungen": active,
        "hard_mode_bis": context.doc.hardMode.map { $0.until.formatted(date: .omitted, time: .shortened) } ?? "aus",
        "entsperrt_heute": SessionEngine.unlocksToday(in: context.doc, at: Date()),
        "sperrversuche_heute": attempts()[day(date)] ?? [:],
    ]
}

func weekReport(_ args: [String: Any]) throws -> Any {
    let context = Context()
    let offset = Int(args["wochen_zurueck"] as? Double ?? 0)
    guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start,
          let start = calendar.date(byAdding: .day, value: -7 * offset, to: thisWeek) else { throw ToolError(message: "Woche nicht berechenbar.") }
    let current = context.summary((0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }.map { usage.load($0) })
    let previous = context.summary((1...7).compactMap { calendar.date(byAdding: .day, value: -$0, to: start) }.map { usage.load($0) })
    let end = start.addingTimeInterval(7 * 86400)
    let unlocks = context.doc.unlockEntries.filter { $0.date >= start && $0.date < end }
    let advice = WeekAdvice.suggestions(current: current, previous: previous, unlocks: unlocks.count, blocked: context.blocked)
    return [
        "woche": ["von": day(start), "bis": day(end.addingTimeInterval(-1))],
        "diese_woche": totals(current.totals),
        "vorwoche": totals(previous.totals),
        "nach_kategorie": groups(current, config: context.config),
        "top_ablenkungen": items(current, config: context.config, limit: 40).filter { ($0["wertung"] as? String) == UsageCategory.distraction.rawValue }.prefix(8).map { $0 },
        "ablenkung_nach_stunde_min": Dictionary(uniqueKeysWithValues: current.distractionByHour.enumerated()
            .filter { $0.element >= 60 }.map { (String($0.offset), minutes($0.element)) }),
        "entsperrungen": unlocks.count,
        "fokus_vorschlaege": advice.map(\.text),
    ]
}

func unlocks(_ args: [String: Any]) throws -> Any {
    let context = Context()
    let days = min(30, max(1, Int(args["tage"] as? Double ?? 14)))
    let since = calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    let entries = context.doc.unlockEntries.filter { $0.date >= since }.map { entry -> [String: Any] in
        ["zeit": entry.date.formatted(.iso8601), "was": entry.target ?? "alles", "minuten": entry.minutes, "grund": entry.reason]
    }
    let tries = attempts().filter { $0.key >= day(since) }
    return ["entsperrungen": entries, "sperrversuche_pro_tag": tries,
            "hinweis": "Sperrversuche zählen, wie oft eine gesperrte Seite geöffnet und umgeleitet wurde."]
}

func setup(_ args: [String: Any]) throws -> Any {
    let context = Context()
    let lists = context.doc.blockLists.map { list -> [String: Any] in
        ["name": list.name, "websites": list.domains, "ausnahmen": list.exceptions, "alles_sperren": list.blocksEverything,
         "apps": list.apps.map(\.name)]
    }
    let schedules = context.doc.schedules.map { schedule -> [String: Any] in
        let names = ["", "So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]
        return ["name": schedule.name, "aktiv": schedule.isEnabled, "tage": schedule.weekdays.sorted().map { names[$0] },
                "von": String(format: "%02d:%02d", schedule.startMinute / 60, schedule.startMinute % 60),
                "bis": String(format: "%02d:%02d", schedule.endMinute / 60, schedule.endMinute % 60),
                "liste": context.doc.blockLists.first { $0.id == schedule.blockListID }?.name ?? "?"]
    }
    let tree = context.config.tops.map { top -> [String: Any] in
        ["name": top.name, "zaehlt_als": top.rating.rawValue, "unterkategorien": context.config.children(of: top.id).map(\.name)]
    }
    let rules = context.config.titleRules.map { rule -> [String: Any] in
        ["website": rule.domain ?? "alle", "stichwort": rule.keyword, "kategorie": context.config.path(rule.groupID)]
    }
    let settings = context.doc.unlockSettings
    return ["sperrlisten": lists, "zeitplaene": schedules, "kategorien": tree, "titel_regeln": rules,
            "entsperren": ["erste_wartezeit_s": settings.baseDelay, "zuschlag_s": settings.stepDelay,
                           "limit_pro_tag": settings.dailyLimit, "grund_noetig": settings.requiresReason]]
}

func pageTitles(_ args: [String: Any]) throws -> Any {
    let context = Context()
    let today = calendar.startOfDay(for: Date())
    let end = try parseDay(args["bis"], fallback: today)
    let start = try parseDay(args["von"], fallback: calendar.date(byAdding: .day, value: -6, to: end) ?? end)
    let summary = context.summary(dates(from: start, to: end).map { usage.load($0) })
    let filter = (args["website"] as? String)?.lowercased()
    let result = summary.titles.filter { filter == nil || DomainRule.matches(host: $0.key, domain: filter!) }.map { domain, pages -> [String: Any] in
        ["website": domain, "seiten": pages.prefix(20).map { page -> [String: Any] in
            ["titel": page.title, "minuten": minutes(page.seconds),
             "kategorie_per_regel": context.config.titleMatch(domain: domain, title: page.title).map { context.config.path($0) } ?? "-"]
        }]
    }
    if result.isEmpty { return ["hinweis": "Keine Seitentitel gespeichert. Die Titel-Erfassung ist in Fokus unter Einstellungen → Zeiterfassung optional."] }
    return ["zeitraum": ["von": day(start), "bis": day(end)], "titel": result]
}

let dateRange: [String: Any] = [
    "type": "object",
    "properties": [
        "von": ["type": "string", "description": "Erster Tag, YYYY-MM-DD. Standard: 6 Tage vor bis."],
        "bis": ["type": "string", "description": "Letzter Tag, YYYY-MM-DD. Standard: heute."],
        "limit": ["type": "number", "description": "Wie viele Apps und Websites, Standard 25."],
    ],
]

let tools: [(name: String, description: String, schema: [String: Any], run: ([String: Any]) throws -> Any)] = [
    ("fokus_heute", "Heutige Bildschirmzeit aus der Mac-App Fokus: Summen, Fokus-Score, Stunden, Kategorien, Top-Apps und -Websites, laufende Sperren, Entsperrungen und Sperrversuche.",
     ["type": "object", "properties": [:]], today),
    ("fokus_nutzung", "Bildschirmzeit für einen Zeitraum: Summen, Tage, Kategorien, Top-Apps und -Websites, Ablenkung nach Uhrzeit.", dateRange, usageRange),
    ("fokus_wochenbericht", "Wochenbericht Mo bis So im Vergleich zur Vorwoche, mit größten Ablenkungen und Vorschlägen.",
     ["type": "object", "properties": ["wochen_zurueck": ["type": "number", "description": "0 = diese Woche, 1 = letzte Woche."]]], weekReport),
    ("fokus_entsperrungen", "Wann und warum der Nutzer gesperrte Seiten freigegeben hat, plus Sperrversuche pro Tag.",
     ["type": "object", "properties": ["tage": ["type": "number", "description": "Rückblick in Tagen, 1 bis 30, Standard 14."]]], unlocks),
    ("fokus_einstellungen", "Sperrlisten, Zeitpläne, Kategorien, Titel-Regeln und Entsperr-Regeln, wie sie in Fokus eingestellt sind.",
     ["type": "object", "properties": [:]], setup),
    ("fokus_seitentitel", "Zeit pro Seitentitel einzelner Websites, nur wenn die Titel-Erfassung an ist.",
     ["type": "object", "properties": [
        "von": ["type": "string", "description": "YYYY-MM-DD"], "bis": ["type": "string", "description": "YYYY-MM-DD"],
        "website": ["type": "string", "description": "Optional, z. B. youtube.com"]]], pageTitles),
]

// MARK: JSON-RPC over stdio

func send(_ message: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: message, options: [.withoutEscapingSlashes]) else { return }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

func handle(_ request: [String: Any]) {
    let id = request["id"]
    let method = request["method"] as? String ?? ""
    let params = request["params"] as? [String: Any] ?? [:]
    func reply(_ result: Any) { if let id { send(["jsonrpc": "2.0", "id": id, "result": result]) } }
    func fail(_ code: Int, _ message: String) { if let id { send(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]) } }

    switch method {
    case "initialize":
        reply(["protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
               "capabilities": ["tools": [String: Any]()],
               "serverInfo": ["name": "fokus", "version": "0.1.0"],
               "instructions": "Read-only Zugriff auf die lokale Bildschirmzeit- und Sperr-App Fokus. Zeiten sind in Minuten. Antworte auf Deutsch."])
    case "ping": reply([String: Any]())
    case "tools/list":
        reply(["tools": tools.map { ["name": $0.name, "description": $0.description, "inputSchema": $0.schema,
                                     "annotations": ["readOnlyHint": true]] }])
    case "tools/call":
        guard let name = params["name"] as? String, let tool = tools.first(where: { $0.name == name }) else {
            fail(-32602, "Unbekanntes Werkzeug"); return
        }
        do {
            let result = try tool.run(params["arguments"] as? [String: Any] ?? [:])
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            reply(["content": [["type": "text", "text": String(decoding: data, as: UTF8.self)]]])
        } catch let error as ToolError {
            reply(["content": [["type": "text", "text": error.message]], "isError": true])
        } catch {
            reply(["content": [["type": "text", "text": error.localizedDescription]], "isError": true])
        }
    default:
        if id != nil { fail(-32601, "Methode \(method) gibt es nicht") }
    }
}

while let line = readLine(strippingNewline: true) {
    guard !line.isEmpty, let data = line.data(using: .utf8),
          let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
    handle(request)
}
