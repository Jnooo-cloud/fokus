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
    guard let date = try? parser.parse(text) else { throw ToolError(message: "Could not read date \(text), expected YYYY-MM-DD.") }
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

/// Ratings are stored in German on disk; clients get English.
func rating(_ value: UsageCategory) -> String {
    switch value {
    case .work: "work"
    case .neutral: "neutral"
    case .distraction: "distraction"
    }
}

func totals(_ value: UsageTotals) -> [String: Any] {
    ["active_min": minutes(value.total), "work_min": minutes(value.work), "neutral_min": minutes(value.neutral),
     "distraction_min": minutes(value.distraction), "focus_score_percent": value.score]
}

func items(_ summary: UsageSummary, config: CategoryConfig, limit: Int) -> [[String: Any]] {
    summary.items.prefix(limit).map { item in
        ["name": item.name, "type": item.isSite ? "website" : "app", "minutes": minutes(item.seconds),
         "rating": rating(item.category), "category": config.path(item.groupID)]
    }
}

func groups(_ summary: UsageSummary, config: CategoryConfig) -> [[String: Any]] {
    summary.byGroup.compactMap { id, seconds in
        seconds >= 60 ? ["category": config.path(id), "minutes": minutes(seconds)] : nil
    }.sorted { ($0["minutes"] as? Int ?? 0) > ($1["minutes"] as? Int ?? 0) }
}

func byHour(_ seconds: [Double]) -> [String: Int] {
    Dictionary(uniqueKeysWithValues: seconds.enumerated().filter { $0.element >= 60 }.map { (String($0.offset), minutes($0.element)) })
}

func attempts() -> [String: [String: Int]] {
    // Inside Fokus.app this binary shares the app's identifier, so its own defaults are the app's.
    let defaults = Bundle.main.bundleIdentifier == bundleID ? UserDefaults.standard : UserDefaults(suiteName: bundleID)
    return defaults?.dictionary(forKey: "blockedAttempts") as? [String: [String: Int]] ?? [:]
}

/// Argument by its English name, or the German one older setups still send.
func arg(_ args: [String: Any], _ name: String, _ legacy: String) -> Any? { args[name] ?? args[legacy] }

// MARK: Tools

func usageRange(_ args: [String: Any]) throws -> Any {
    let context = Context()
    let today = calendar.startOfDay(for: Date())
    let end = try parseDay(arg(args, "to", "bis"), fallback: today)
    let start = try parseDay(arg(args, "from", "von"), fallback: calendar.date(byAdding: .day, value: -6, to: end) ?? end)
    guard start <= end else { throw ToolError(message: "from is after to.") }
    let span = dates(from: start, to: end)
    let loaded = span.map { usage.load($0) }
    let summary = context.summary(loaded)
    let perDay = zip(span, loaded).map { date, value -> [String: Any] in
        ["date": day(date), "weekday": date.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "en_US")))]
            .merging(totals(context.summary([value]).totals)) { a, _ in a }
    }
    return [
        "range": ["from": day(start), "to": day(end)],
        "total": totals(summary.totals),
        "days": perDay,
        "by_category": groups(summary, config: context.config),
        "top_apps_and_websites": items(summary, config: context.config, limit: Int(args["limit"] as? Double ?? 25)),
        "distraction_by_hour_min": byHour(summary.distractionByHour),
        "note": "Active time, without breaks over 3 minutes. Focus score = work / (work + distraction).",
    ]
}

func today(_ args: [String: Any]) throws -> Any {
    let context = Context()
    let date = calendar.startOfDay(for: Date())
    let summary = context.summary([usage.load(date)])
    let hours = summary.byHour.enumerated().filter { $0.element.total >= 60 }.map { hour, value -> [String: Any] in
        ["hour": hour, "work_min": minutes(value.work), "neutral_min": minutes(value.neutral), "distraction_min": minutes(value.distraction)]
    }
    let active = SessionEngine.activeSessions(in: context.doc, at: Date()).map { session -> [String: Any] in
        ["name": session.name, "until": session.endsAt.formatted(date: .omitted, time: .shortened), "strict": session.isStrict,
         "blocked": session.blockList.blocksEverything ? ["everything except the exceptions"] : session.blockList.domains]
    }
    return [
        "date": day(date),
        "total": totals(summary.totals),
        "hours": hours,
        "by_category": groups(summary, config: context.config),
        "top_apps_and_websites": items(summary, config: context.config, limit: 20),
        "running_sessions": active,
        "hard_mode_until": context.doc.hardMode.map { $0.until.formatted(date: .omitted, time: .shortened) } ?? "off",
        "unlocks_today": SessionEngine.unlocksToday(in: context.doc, at: Date()),
        "blocked_attempts_today": attempts()[day(date)] ?? [:],
    ]
}

func weekReport(_ args: [String: Any]) throws -> Any {
    let context = Context()
    let offset = Int(arg(args, "weeks_back", "wochen_zurueck") as? Double ?? 0)
    guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start,
          let start = calendar.date(byAdding: .day, value: -7 * offset, to: thisWeek) else { throw ToolError(message: "Could not work out the week.") }
    let current = context.summary((0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }.map { usage.load($0) })
    let previous = context.summary((1...7).compactMap { calendar.date(byAdding: .day, value: -$0, to: start) }.map { usage.load($0) })
    let end = start.addingTimeInterval(7 * 86400)
    let unlocks = context.doc.unlockEntries.filter { $0.date >= start && $0.date < end }
    let advice = WeekAdvice.suggestions(current: current, previous: previous, unlocks: unlocks.count, blocked: context.blocked)
    return [
        "week": ["from": day(start), "to": day(end.addingTimeInterval(-1))],
        "this_week": totals(current.totals),
        "previous_week": totals(previous.totals),
        "by_category": groups(current, config: context.config),
        "top_distractions": items(current, config: context.config, limit: 40).filter { ($0["rating"] as? String) == "distraction" }.prefix(8).map { $0 },
        "distraction_by_hour_min": byHour(current.distractionByHour),
        "unlocks": unlocks.count,
        "suggestions": advice.map(\.text),
    ]
}

func unlocks(_ args: [String: Any]) throws -> Any {
    let context = Context()
    let days = min(30, max(1, Int(arg(args, "days", "tage") as? Double ?? 14)))
    let since = calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    let entries = context.doc.unlockEntries.filter { $0.date >= since }.map { entry -> [String: Any] in
        ["time": entry.date.formatted(.iso8601), "what": entry.target ?? "everything", "minutes": entry.minutes, "reason": entry.reason]
    }
    let tries = attempts().filter { $0.key >= day(since) }
    return ["unlocks": entries, "blocked_attempts_per_day": tries,
            "note": "Blocked attempts count how often a blocked page was opened and redirected."]
}

func setup(_ args: [String: Any]) throws -> Any {
    let context = Context()
    let lists = context.doc.blockLists.map { list -> [String: Any] in
        ["name": list.name, "websites": list.domains, "exceptions": list.exceptions, "blocks_everything": list.blocksEverything,
         "apps": list.apps.map(\.name)]
    }
    let schedules = context.doc.schedules.map { schedule -> [String: Any] in
        let names = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return ["name": schedule.name, "enabled": schedule.isEnabled, "days": schedule.weekdays.sorted().map { names[$0] },
                "from": String(format: "%02d:%02d", schedule.startMinute / 60, schedule.startMinute % 60),
                "to": String(format: "%02d:%02d", schedule.endMinute / 60, schedule.endMinute % 60),
                "block_list": context.doc.blockLists.first { $0.id == schedule.blockListID }?.name ?? "?"]
    }
    let tree = context.config.tops.map { top -> [String: Any] in
        ["name": top.name, "counts_as": rating(top.rating), "subcategories": context.config.children(of: top.id).map(\.name)]
    }
    let rules = context.config.titleRules.map { rule -> [String: Any] in
        ["website": rule.domain ?? "all", "keyword": rule.keyword, "category": context.config.path(rule.groupID)]
    }
    let settings = context.doc.unlockSettings
    return ["block_lists": lists, "schedules": schedules, "categories": tree, "title_rules": rules,
            "unlocking": ["first_wait_s": settings.baseDelay, "added_wait_per_unlock_s": settings.stepDelay,
                          "daily_limit": settings.dailyLimit, "reason_required": settings.requiresReason]]
}

func pageTitles(_ args: [String: Any]) throws -> Any {
    let context = Context()
    let today = calendar.startOfDay(for: Date())
    let end = try parseDay(arg(args, "to", "bis"), fallback: today)
    let start = try parseDay(arg(args, "from", "von"), fallback: calendar.date(byAdding: .day, value: -6, to: end) ?? end)
    let summary = context.summary(dates(from: start, to: end).map { usage.load($0) })
    let filter = (args["website"] as? String)?.lowercased()
    let result = summary.titles.filter { filter == nil || DomainRule.matches(host: $0.key, domain: filter!) }.map { domain, pages -> [String: Any] in
        ["website": domain, "pages": pages.prefix(20).map { page -> [String: Any] in
            ["title": page.title, "minutes": minutes(page.seconds),
             "category_by_rule": context.config.titleMatch(domain: domain, title: page.title).map { context.config.path($0) } ?? "-"]
        }]
    }
    if result.isEmpty { return ["note": "No page titles stored. Recording titles is optional, in Fokus under Settings → Time tracking."] }
    return ["range": ["from": day(start), "to": day(end)], "titles": result]
}

let dateRange: [String: Any] = [
    "type": "object",
    "properties": [
        "from": ["type": "string", "description": "First day, YYYY-MM-DD. Default: 6 days before to."],
        "to": ["type": "string", "description": "Last day, YYYY-MM-DD. Default: today."],
        "limit": ["type": "number", "description": "How many apps and websites, default 25."],
    ],
]

/// `legacy` is the German name from before 0.3, still accepted so existing setups keep working.
let tools: [(name: String, legacy: String, description: String, schema: [String: Any], run: ([String: Any]) throws -> Any)] = [
    ("fokus_today", "fokus_heute", "Today's screen time from the Mac app Fokus: totals, focus score, hour by hour, categories, top apps and websites, running focus sessions, unlocks and blocked attempts.",
     ["type": "object", "properties": [:]], today),
    ("fokus_usage", "fokus_nutzung", "Screen time for a date range: totals, each day, categories, top apps and websites, distraction by hour of day.", dateRange, usageRange),
    ("fokus_weekly_report", "fokus_wochenbericht", "Weekly report, Monday to Sunday, compared with the week before, with the biggest distractions and suggestions.",
     ["type": "object", "properties": ["weeks_back": ["type": "number", "description": "0 = this week, 1 = last week."]]], weekReport),
    ("fokus_unlocks", "fokus_entsperrungen", "When and why the user unlocked blocked sites, plus blocked attempts per day.",
     ["type": "object", "properties": ["days": ["type": "number", "description": "How many days back, 1 to 30, default 14."]]], unlocks),
    ("fokus_settings", "fokus_einstellungen", "Block lists, schedules, categories, page title rules and unlock rules as set up in Fokus.",
     ["type": "object", "properties": [:]], setup),
    ("fokus_page_titles", "fokus_seitentitel", "Time per page title on individual websites. Only has data if the user turned on page titles.",
     ["type": "object", "properties": [
        "from": ["type": "string", "description": "YYYY-MM-DD"], "to": ["type": "string", "description": "YYYY-MM-DD"],
        "website": ["type": "string", "description": "Optional, e.g. youtube.com"]]], pageTitles),
]

// MARK: Guidance for the model

let instructions = """
Fokus is a local macOS app that blocks distracting websites and apps and records screen time. This server gives read-only access to its data. You cannot start sessions, change block lists or unlock anything; suggest the change and tell the user where to make it in the app (Focus, Block Lists, Schedules, Unlock, Categories, Settings).

What you can see:
- fokus_today: today so far, hour by hour, plus running sessions, Hard Mode, unlocks and blocked attempts.
- fokus_usage: any date range, per day, per category, top apps and websites, distraction by hour of day.
- fokus_weekly_report: Monday to Sunday against the week before, biggest distractions, Fokus' own suggestions.
- fokus_unlocks: each unlock with time, target, length and the reason the user typed, plus how often blocked pages were opened.
- fokus_settings: block lists, schedules, categories and unlock rules. Read this before recommending a change, so you don't suggest something that is already set up.
- fokus_page_titles: time per page title. Empty unless the user turned titles on.

How to read it: all times are minutes of active use. Idle time over 3 minutes and a locked screen are not counted. Every app and website is rated work, neutral or distraction by the user's categories. Focus score = work / (work + distraction), neutral is left out. Hours are 0 to 23 in local time. Websites are stored per domain, never as full URLs. Category names are the user's own and may be in German.

Fetch the numbers before you answer, never estimate them. Days with very little active time say nothing about habits. Reply in the language the user writes in.
"""

let coachRules = """
Rules: use the real numbers from the fokus tools, never guess. If there are fewer than 3 days with data, say so and treat everything as provisional. Ignore days with under 30 active minutes when you look for habits. No lecturing. You can only read; I make the changes myself in the Fokus app, so tell me exactly where (Focus, Block Lists, Schedules, Unlock, Categories, Settings). Reply in the language I write in.
"""

let prompts: [(name: String, title: String, description: String, arguments: [[String: Any]], text: ([String: Any]) -> String)] = [
    ("focus_coach", "Focus coach", "Finds where and when your focus breaks and gives up to three concrete changes to make in Fokus.",
     [["name": "goal", "description": "What you want to get better at, e.g. 'no YouTube before noon'. Optional.", "required": false]],
     { args in
        let goal = (args["goal"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "less time lost to distraction and longer stretches of real work"
        return """
        Be my focus coach, based on my Fokus data. My goal: \(goal).

        1. Get fokus_weekly_report for this week and last week (weeks_back 0 and 1), fokus_usage for the last 14 days, fokus_unlocks and fokus_settings.
        2. Look for the pattern behind the totals: on which weekdays and at which hours the distraction piles up, which two or three sites or apps make up most of it, what reasons I gave when I unlocked, and when blocked attempts spike.
        3. Hold that against my setup. Are the biggest time sinks on a block list at all? Does a schedule cover the hours where I drift? Is unlocking too easy?
        4. Give me at most three changes. Each one must be specific enough to do in two minutes: which block list, which schedule with days and hours, Flexible, Commit or Hard Mode.
        5. Name the one number we look at next week to see whether it worked.

        \(coachRules)
        """
     }),
    ("weekly_review", "Weekly review", "A short review of your week: what went well, where the time went, one thing to change next week.",
     [],
     { _ in
        """
        Review my week with my Fokus data.

        1. Get fokus_weekly_report for this week and last week (weeks_back 0 and 1) and fokus_unlocks for the last 7 days.
        2. Tell me in this order: active time and focus score against last week, my best day and what was different about it, my three biggest time sinks with minutes, and the hours of the day where I drift most.
        3. End with one change for next week and the number that shows whether it worked.

        Keep it under 200 words.

        \(coachRules)
        """
     }),
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
               "capabilities": ["tools": [String: Any](), "prompts": [String: Any]()],
               "serverInfo": ["name": "fokus", "version": "0.3.0"],
               "instructions": instructions])
    case "ping": reply([String: Any]())
    case "tools/list":
        reply(["tools": tools.map { ["name": $0.name, "description": $0.description, "inputSchema": $0.schema,
                                     "annotations": ["readOnlyHint": true]] }])
    case "tools/call":
        guard let name = params["name"] as? String, let tool = tools.first(where: { $0.name == name || $0.legacy == name }) else {
            fail(-32602, "Unknown tool"); return
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
    case "prompts/list":
        reply(["prompts": prompts.map { ["name": $0.name, "title": $0.title, "description": $0.description, "arguments": $0.arguments] }])
    case "prompts/get":
        guard let name = params["name"] as? String, let prompt = prompts.first(where: { $0.name == name }) else {
            fail(-32602, "Unknown prompt"); return
        }
        reply(["description": prompt.description,
               "messages": [["role": "user", "content": ["type": "text", "text": prompt.text(params["arguments"] as? [String: Any] ?? [:])]]]])
    default:
        if id != nil { fail(-32601, "Method \(method) does not exist") }
    }
}

while let line = readLine(strippingNewline: true) {
    guard !line.isEmpty, let data = line.data(using: .utf8),
          let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
    handle(request)
}
