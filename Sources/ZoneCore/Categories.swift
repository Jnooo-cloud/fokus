import Foundation

extension UsageCategory: Codable {}

/// A user-made category. Top-level groups decide how time is rated; subgroups inherit their parent's rating.
public struct UsageGroup: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var rating: UsageCategory
    public var parentID: UUID?

    public init(id: UUID = UUID(), name: String, rating: UsageCategory, parentID: UUID? = nil) {
        self.id = id
        self.name = name
        self.rating = rating
        self.parentID = parentID
    }
}

/// "Titles on youtube.com containing Tutorial count as Research". No domain means every website.
public struct TitleRule: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var domain: String?
    public var keyword: String
    public var groupID: UUID

    public init(id: UUID = UUID(), domain: String?, keyword: String, groupID: UUID) {
        self.id = id
        self.domain = domain
        self.keyword = keyword
        self.groupID = groupID
    }
}

public typealias UsageGrouper = @Sendable (_ name: String, _ isSite: Bool) -> UUID?

public struct CategoryConfig: Codable, Equatable, Sendable {
    public var groups: [UsageGroup]
    /// Keyed like usage data: `a:<app>` or `s:<domain>`. A domain also covers its subdomains.
    public var assignments: [String: UUID]
    public var titleRules: [TitleRule]

    public init(groups: [UsageGroup] = [], assignments: [String: UUID] = [:], titleRules: [TitleRule] = []) {
        self.groups = groups
        self.assignments = assignments
        self.titleRules = titleRules
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        groups = try values.decode([UsageGroup].self, forKey: .groups)
        assignments = try values.decode([String: UUID].self, forKey: .assignments)
        titleRules = try values.decodeIfPresent([TitleRule].self, forKey: .titleRules) ?? []
    }

    /// Rules for this domain win over rules for every website; within each, the first added wins.
    public func titleMatch(domain: String, title: String) -> UUID? {
        let usable = titleRules.filter { group($0.groupID) != nil && !$0.keyword.isEmpty && title.localizedCaseInsensitiveContains($0.keyword) }
        if let specific = usable.first(where: { rule in rule.domain.map { DomainRule.matches(host: domain, domain: $0) } ?? false }) {
            return specific.groupID
        }
        return usable.first { $0.domain == nil }?.groupID
    }

    public var matcher: TitleMatcher {
        let config = self
        return { domain, title in
            guard let id = config.titleMatch(domain: domain, title: title), let rating = config.rating(of: id) else { return nil }
            return (id, rating)
        }
    }

    public var tops: [UsageGroup] { groups.filter { $0.parentID == nil } }
    public func children(of id: UUID) -> [UsageGroup] { groups.filter { $0.parentID == id } }
    public func group(_ id: UUID?) -> UsageGroup? { id.flatMap { id in groups.first { $0.id == id } } }

    public func top(of id: UUID?) -> UsageGroup? {
        guard let group = group(id) else { return nil }
        return group.parentID.flatMap { self.group($0) } ?? group
    }

    public func rating(of id: UUID?) -> UsageCategory? { top(of: id)?.rating }

    public func path(_ id: UUID?) -> String {
        guard let group = group(id) else { return "Ohne Kategorie" }
        guard let parent = group.parentID.flatMap({ self.group($0) }) else { return group.name }
        return "\(parent.name) › \(group.name)"
    }

    public func assignment(name: String, isSite: Bool) -> UUID? {
        if !isSite { return assignments[UsageDay.appKey(name)].flatMap { group($0)?.id } }
        // youtube.com covers m.youtube.com; the most specific match wins.
        var labels = name.split(separator: ".").map(String.init)
        while labels.count >= 2 {
            if let id = assignments[UsageDay.siteKey(labels.joined(separator: "."))], group(id) != nil { return id }
            labels.removeFirst()
        }
        return nil
    }

    public mutating func assign(name: String, isSite: Bool, to id: UUID?) {
        let key = isSite ? UsageDay.siteKey(name) : UsageDay.appKey(name)
        assignments[key] = id
    }

    @discardableResult
    public mutating func addGroup(name: String, rating: UsageCategory, parentID: UUID? = nil) -> UUID {
        let group = UsageGroup(name: name, rating: rating, parentID: parentID)
        groups.append(group)
        return group.id
    }

    public mutating func rename(_ id: UUID, to name: String) {
        guard let index = groups.firstIndex(where: { $0.id == id }), !name.isEmpty else { return }
        groups[index].name = name
    }

    public mutating func setRating(_ id: UUID, _ rating: UsageCategory) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].rating = rating
    }

    /// Items of a removed subgroup move up to its parent; a removed top group takes its subgroups with it.
    public mutating func delete(_ id: UUID) {
        guard let removed = group(id) else { return }
        let removedIDs = Set([id] + children(of: id).map(\.id))
        groups.removeAll { removedIDs.contains($0.id) }
        for (key, value) in assignments where removedIDs.contains(value) {
            assignments[key] = removed.parentID
        }
        titleRules = titleRules.compactMap { rule in
            guard removedIDs.contains(rule.groupID) else { return rule }
            guard let parent = removed.parentID else { return nil }
            var moved = rule
            moved.groupID = parent
            return moved
        }
    }

    public static func defaults(migrating overrides: [String: String] = [:]) -> CategoryConfig {
        var config = CategoryConfig()
        let work = config.addGroup(name: "Arbeit", rating: .work)
        let personal = config.addGroup(name: "Privat", rating: .neutral)
        let distraction = config.addGroup(name: "Ablenkung", rating: .distraction)
        let talk = config.addGroup(name: "Kommunikation", rating: .work, parentID: work)
        let build = config.addGroup(name: "Entwicklung", rating: .work, parentID: work)
        let research = config.addGroup(name: "Recherche", rating: .work, parentID: work)
        let content = config.addGroup(name: "Content", rating: .work, parentID: work)
        _ = config.addGroup(name: "Lesen", rating: .neutral, parentID: personal)
        _ = config.addGroup(name: "Organisation", rating: .neutral, parentID: personal)
        let social = config.addGroup(name: "Social Media", rating: .distraction, parentID: distraction)
        let entertainment = config.addGroup(name: "Entertainment", rating: .distraction, parentID: distraction)
        let shopping = config.addGroup(name: "Shopping", rating: .distraction, parentID: distraction)
        let news = config.addGroup(name: "News", rating: .distraction, parentID: distraction)
        let apps: [(String, UUID)] = [
            ("Claude", research), ("Terminal", build), ("Code", build), ("Cursor", build), ("Xcode", build),
            ("Mail", talk), ("Kalender", talk), ("Calendar", talk), ("Slack", talk), ("Microsoft Teams", talk), ("zoom.us", talk),
            ("DaVinci Resolve", content), ("Figma", content), ("Microsoft Word", work), ("Microsoft Excel", work),
            ("Obsidian", work), ("Notion", work), ("Vorschau", work), ("Preview", work), ("Pages", work), ("Numbers", work), ("Keynote", work),
        ]
        let sites: [(String, UUID)] = [
            ("github.com", build), ("vercel.com", build), ("claude.ai", research), ("chatgpt.com", research), ("gemini.google.com", research), ("perplexity.ai", research),
            ("meet.google.com", talk), ("mail.google.com", talk), ("calendar.google.com", talk),
            ("docs.google.com", work), ("notion.so", work), ("stackoverflow.com", build),
            ("instagram.com", social), ("tiktok.com", social), ("facebook.com", social), ("x.com", social), ("twitter.com", social),
            ("reddit.com", social), ("linkedin.com", social), ("youtube.com", entertainment), ("netflix.com", entertainment),
            ("twitch.tv", entertainment), ("amazon.de", shopping), ("amazon.com", shopping), ("zalando.de", shopping),
            ("spiegel.de", news), ("tagesschau.de", news), ("bild.de", news),
        ]
        for (name, id) in apps { config.assign(name: name, isSite: false, to: id) }
        for (name, id) in sites { config.assign(name: name, isSite: true, to: id) }
        let topFor: [UsageCategory: UUID] = [.work: work, .neutral: personal, .distraction: distraction]
        for (name, raw) in overrides {
            guard let rating = UsageCategory(rawValue: raw), let id = topFor[rating] else { continue }
            config.assign(name: name, isSite: name.contains("."), to: id)
        }
        return config
    }
}
