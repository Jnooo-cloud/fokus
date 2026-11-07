import Foundation

public enum UsageCategory: String, CaseIterable, Identifiable, Sendable {
    case work = "Arbeit", neutral = "Neutral", distraction = "Ablenkung"
    public var id: Self { self }
}

public struct UsageTotals: Equatable, Sendable {
    public var work = 0.0, neutral = 0.0, distraction = 0.0

    public init() {}

    public var total: Double { work + neutral + distraction }
    /// Share of work in everything that was clearly work or distraction.
    public var score: Int {
        let counted = work + distraction
        return counted > 0 ? Int((work / counted * 100).rounded()) : 0
    }

    public mutating func add(_ seconds: Double, _ category: UsageCategory) {
        switch category {
        case .work: work += seconds
        case .neutral: neutral += seconds
        case .distraction: distraction += seconds
        }
    }
}

/// One day of seconds per hour. Keys are `a:<app name>` or `s:<domain>`; no addresses or titles are kept.
public struct UsageDay: Codable, Equatable, Sendable {
    public var hours: [String: [String: Double]]
    /// Only filled when page titles are switched on: domain, then title, then seconds.
    public var titles: [String: [String: Double]]

    public init(hours: [String: [String: Double]] = [:], titles: [String: [String: Double]] = [:]) {
        self.hours = hours
        self.titles = titles
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        hours = try values.decode([String: [String: Double]].self, forKey: .hours)
        titles = try values.decodeIfPresent([String: [String: Double]].self, forKey: .titles) ?? [:]
    }

    public mutating func addTitle(_ seconds: Double, title: String, domain: String) {
        titles[domain, default: [:]][title, default: 0] += seconds
    }

    public static func appKey(_ name: String) -> String { "a:" + name }
    public static func siteKey(_ domain: String) -> String { "s:" + domain }

    public mutating func add(_ seconds: Double, key: String, hour: Int) {
        hours[String(hour), default: [:]][key, default: 0] += seconds
    }

    public mutating func merge(_ other: UsageDay) {
        for (hour, keys) in other.hours {
            for (key, seconds) in keys { hours[hour, default: [:]][key, default: 0] += seconds }
        }
        for (domain, pages) in other.titles {
            for (title, seconds) in pages { titles[domain, default: [:]][title, default: 0] += seconds }
        }
    }
}

public struct UsageStore: Sendable {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    private static func name(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d.json", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public func load(_ date: Date, calendar: Calendar = .autoupdatingCurrent) -> UsageDay {
        let url = directory.appendingPathComponent(Self.name(date, calendar: calendar))
        return (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(UsageDay.self, from: $0) } ?? UsageDay()
    }

    /// Wipes every stored page title and keeps the domain and app times.
    public func removeTitles() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file), var day = try? JSONDecoder().decode(UsageDay.self, from: data),
                  !day.titles.isEmpty else { continue }
            day.titles = [:]
            try? JSONEncoder().encode(day).write(to: file, options: .atomic)
        }
    }

    public func save(_ day: UsageDay, for date: Date, calendar: Calendar = .autoupdatingCurrent) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(day).write(to: directory.appendingPathComponent(Self.name(date, calendar: calendar)), options: .atomic)
    }
}

/// Classifies a usage key's name; `isSite` tells domains from app names.
public typealias UsageClassifier = @Sendable (_ name: String, _ isSite: Bool) -> UsageCategory

public struct UsageItem: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public let seconds: Double
    public let isSite: Bool
    public let category: UsageCategory
    public var groupID: UUID? = nil
}

public struct UsageSummary: Sendable {
    public var totals = UsageTotals()
    public var items: [UsageItem] = []
    /// Distracted seconds per hour of the day.
    public var distractionByHour = Array(repeating: 0.0, count: 24)
    public var byHour = Array(repeating: UsageTotals(), count: 24)
    /// Pages per domain, longest first.
    public var titles: [String: [(title: String, seconds: Double)]] = [:]
    /// Seconds per category; `nil` holds everything without a category.
    public var byGroup: [UUID?: Double] = [:]

    /// `titleRule` maps a page title to a category. Matched time leaves its domain's category; titles are only
    /// stored per day, so each hour of the domain gives up the same share.
    public init(days: [UsageDay], classify: UsageClassifier, group: UsageGrouper = { _, _ in nil },
                titleRule: TitleMatcher? = nil) {
        var pages: [String: [String: Double]] = [:]
        for day in days {
            for (domain, entries) in day.titles {
                for (title, value) in entries { pages[domain, default: [:]][title, default: 0] += value }
            }
        }
        titles = pages.mapValues { entries in entries.map { (title: $0.key, seconds: $0.value) }.sorted { $0.seconds > $1.seconds } }

        var seconds: [String: Double] = [:]
        for day in days { for keys in day.hours.values { for (key, value) in keys { seconds[Self.normalize(key), default: 0] += value } } }

        // Share of each domain's time that a title rule moves elsewhere.
        var moved: [String: [(group: UUID, rating: UsageCategory, share: Double)]] = [:]
        if let titleRule {
            for (domain, entries) in pages {
                let total = seconds[UsageDay.siteKey(domain)] ?? 0
                guard total > 0 else { continue }
                var buckets: [UUID: (rating: UsageCategory, seconds: Double)] = [:]
                for (title, value) in entries {
                    guard let match = titleRule(domain, title) else { continue }
                    buckets[match.group, default: (match.rating, 0)].seconds += value
                }
                let sum = buckets.values.reduce(0) { $0 + $1.seconds }
                let scale = sum > total ? total / sum : 1
                moved[domain] = buckets.map { (group: $0.key, rating: $0.value.rating, share: $0.value.seconds * scale / total) }
            }
        }

        for day in days {
            for (hourName, keys) in day.hours {
                let hour = Int(hourName).flatMap { (0..<24).contains($0) ? $0 : nil }
                for (rawKey, value) in keys {
                    let key = Self.normalize(rawKey)
                    let isSite = key.hasPrefix("s:")
                    let name = String(key.dropFirst(2))
                    var parts: [(UsageCategory, Double)] = []
                    let shifts = isSite ? moved[name] ?? [] : []
                    for shift in shifts { parts.append((shift.rating, value * shift.share)) }
                    parts.append((classify(name, isSite), value * max(0, 1 - shifts.reduce(0) { $0 + $1.share })))
                    for (category, part) in parts where part > 0 {
                        totals.add(part, category)
                        if let hour {
                            byHour[hour].add(part, category)
                            if category == .distraction { distractionByHour[hour] += part }
                        }
                    }
                }
            }
        }
        items = seconds.map { key, value in
            let name = String(key.dropFirst(2)), isSite = key.hasPrefix("s:")
            return UsageItem(name: name, seconds: value, isSite: isSite, category: classify(name, isSite), groupID: group(name, isSite))
        }.sorted { $0.seconds > $1.seconds }
        for item in items {
            let shifts = item.isSite ? moved[item.name] ?? [] : []
            for shift in shifts { byGroup[shift.group, default: 0] += item.seconds * shift.share }
            byGroup[item.groupID, default: 0] += item.seconds * max(0, 1 - shifts.reduce(0) { $0 + $1.share })
        }
    }

    /// ActivityWatch recorded browser pages like "newtab" as domains.
    private static func normalize(_ key: String) -> String {
        key.hasPrefix("s:") && !key.contains(".") ? UsageDay.appKey("Google Chrome") : key
    }
}

public typealias TitleMatcher = @Sendable (_ domain: String, _ title: String) -> (group: UUID, rating: UsageCategory)?

public struct WeekSuggestion: Identifiable, Equatable, Sendable {
    public var id: String { text }
    public let text: String
    /// When set, the report offers to add this domain to a block list.
    public let blockDomain: String?
}

public enum WeekAdvice {
    /// Plain rules on purpose: every line can be traced back to a number in the report.
    public static func suggestions(current: UsageSummary, previous: UsageSummary, unlocks: Int, blocked: [String]) -> [WeekSuggestion] {
        var result: [WeekSuggestion] = []
        let unblocked = current.items.filter { item in
            item.isSite && item.category == .distraction && item.seconds >= 3600
                && !blocked.contains { DomainRule.matches(host: item.name, domain: $0) }
        }
        for item in unblocked.prefix(2) {
            result.append(WeekSuggestion(text: "\(item.name) hat dich \(hours(item.seconds)) gekostet und ist nicht gesperrt.", blockDomain: item.name))
        }
        if let peak = current.distractionByHour.enumerated().max(by: { $0.element < $1.element }), peak.element >= 1800 {
            result.append(WeekSuggestion(text: "Dein schwächster Slot ist \(peak.offset) bis \(peak.offset + 1) Uhr. Leg dort einen Fokusblock oder Hard Mode hin.", blockDomain: nil))
        }
        if unlocks >= 10 {
            result.append(WeekSuggestion(text: "\(unlocks)× entsperrt. Senk das Tageslimit oder erhöh die Wartezeit in den Einstellungen.", blockDomain: nil))
        }
        if previous.totals.distraction > 0, current.totals.distraction > previous.totals.distraction * 1.25 {
            result.append(WeekSuggestion(text: "Ablenkung ist mehr als 25 % über der Vorwoche. Schau, welcher Tag das ausgelöst hat.", blockDomain: nil))
        }
        return result
    }

    private static func hours(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        return minutes < 60 ? "\(minutes) Min" : "\(minutes / 60) Std \(minutes % 60) Min"
    }
}
