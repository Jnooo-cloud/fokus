import Foundation
import Observation
import ZoneCore

struct DayUsage: Identifiable, Equatable, Sendable {
    var id: Date { date }
    let date: Date
    let totals: UsageTotals
}

/// A week's numbers next to the week before, plus when the distraction happened.
struct WeekReport: Sendable {
    let start: Date
    let current: UsageSummary
    let previous: UsageSummary
    let days: [DayUsage]
    /// Distracted seconds by weekday (0 = Monday) and hour.
    let heat: [[Double]]
}

@MainActor @Observable
final class InsightsStore {
    private(set) var today = UsageTotals()
    private(set) var entries: [UsageItem] = []
    private(set) var titles: [String: [(title: String, seconds: Double)]] = [:]
    private(set) var days: [DayUsage] = []
    private(set) var hours: [Double] = Array(repeating: 0, count: 24)
    private(set) var hourTotals = Array(repeating: UsageTotals(), count: 24)
    private(set) var yesterday = UsageTotals()
    private(set) var report: WeekReport?
    var weekOffset = 0 { didSet { rebuild() } }
    private(set) var categories: CategoryConfig
    private(set) var byGroup: [UUID?: Double] = [:]
    private(set) var recent: [UsageItem] = []
    @ObservationIgnored private var blocked: [String] = []
    @ObservationIgnored private let store: UsageStore
    @ObservationIgnored private let flush: () -> Void

    @ObservationIgnored private let categoriesURL: URL

    init(store: UsageStore, flush: @escaping () -> Void) {
        self.store = store
        self.flush = flush
        categoriesURL = store.directory.deletingLastPathComponent().appendingPathComponent("categories.json")
        if let data = try? Data(contentsOf: categoriesURL), let saved = try? JSONDecoder().decode(CategoryConfig.self, from: data) {
            categories = saved
        } else {
            // First start with categories: earlier right-click choices carry over.
            let old = UserDefaults.standard.dictionary(forKey: "categoryOverrides") as? [String: String] ?? [:]
            categories = CategoryConfig.defaults(migrating: old)
            // Saved right away, so later changes to the defaults never touch an existing setup.
            if let data = try? JSONEncoder().encode(categories) { try? data.write(to: categoriesURL, options: .atomic) }
        }
    }

    func updateCategories(_ change: (inout CategoryConfig) -> Void) {
        change(&categories)
        if let data = try? JSONEncoder().encode(categories) { try? data.write(to: categoriesURL, options: .atomic) }
        rebuild()
        loadRecent()
    }

    /// Everything seen in the last 30 days, for sorting into categories.
    func loadRecent() {
        let calendar = Calendar.autoupdatingCurrent
        let midnight = calendar.startOfDay(for: Date())
        let days = (0..<30).compactMap { calendar.date(byAdding: .day, value: -$0, to: midnight) }.map { store.load($0) }
        recent = UsageSummary(days: days, classify: classifier(), group: grouper(), titleRule: categories.matcher).items.filter { $0.seconds >= 60 }
    }

    private func grouper() -> UsageGrouper { categories.grouper(blocked: blocked) }
    private func classifier() -> UsageClassifier { categories.classifier(blocked: blocked) }

    func refresh(blockedDomains: [String]) {
        blocked = blockedDomains
        flush()
        rebuild()
    }

    func removeTitles() {
        flush()
        store.removeTitles()
        rebuild()
    }

    private func rebuild() {
        let classify = classifier()
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = .autoupdatingCurrent
        let midnight = calendar.startOfDay(for: Date())
        let summary = UsageSummary(days: [store.load(midnight)], classify: classify, group: grouper(), titleRule: categories.matcher)
        today = summary.totals
        hours = summary.distractionByHour
        hourTotals = summary.byHour
        yesterday = calendar.date(byAdding: .day, value: -1, to: midnight).map { UsageSummary(days: [store.load($0)], classify: classify, titleRule: categories.matcher).totals } ?? UsageTotals()
        entries = summary.items.filter { $0.seconds >= 60 }
        titles = summary.titles
        byGroup = summary.byGroup
        days = (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: midnight) }.map { date in
            DayUsage(date: date, totals: UsageSummary(days: [store.load(date)], classify: classify, titleRule: categories.matcher).totals)
        }
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: midnight)?.start,
              let start = calendar.date(byAdding: .day, value: 7 * weekOffset, to: thisWeek) else { return }
        let dates = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let loaded = dates.map { store.load($0) }
        let earlier = (1...7).compactMap { calendar.date(byAdding: .day, value: -$0, to: start) }.map { store.load($0) }
        let heat = loaded.map { UsageSummary(days: [$0], classify: classify, titleRule: categories.matcher).distractionByHour }
        report = WeekReport(start: start, current: UsageSummary(days: loaded, classify: classify, group: grouper(), titleRule: categories.matcher),
                            previous: UsageSummary(days: earlier, classify: classify, titleRule: categories.matcher),
                            days: zip(dates, loaded).map { DayUsage(date: $0, totals: UsageSummary(days: [$1], classify: classify, titleRule: categories.matcher).totals) },
                            heat: heat)
    }
}
