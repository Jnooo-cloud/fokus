import AppKit
import CoreGraphics
import ZoneCore

/// Samples the frontmost app and, in a browser, the active tab's domain. Stores seconds per hour only.
@MainActor
final class UsageTracker {
    static let idleLimit: TimeInterval = 180
    static let titlesKey = "trackPageTitles"
    private static let interval: TimeInterval = 5
    let store: UsageStore
    private let browsers: BrowserBlocker
    private var pending = UsageDay()
    private var pendingDate = Date()
    private var lastSample = Date()
    private var lastFlush = Date()
    private var sampling = false

    init(browsers: BrowserBlocker) {
        self.browsers = browsers
        store = UsageStore(directory: FokusPaths.data.appendingPathComponent("usage"))
    }

    func tick(now: Date) {
        guard now.timeIntervalSince(lastSample) >= Self.interval, !sampling else { return }
        // Sleep and long stalls leave a gap instead of being counted as use.
        let elapsed = min(now.timeIntervalSince(lastSample), Self.interval * 3)
        lastSample = now
        if now.timeIntervalSince(lastFlush) >= 60 || !Calendar.autoupdatingCurrent.isDate(now, inSameDayAs: pendingDate) { flush(now: now) }
        guard !Self.isAway, let app = NSWorkspace.shared.frontmostApplication, let name = app.localizedName,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        let hour = Calendar.autoupdatingCurrent.component(.hour, from: now)
        sampling = true
        Task {
            defer { sampling = false }
            let withTitle = UserDefaults.standard.bool(forKey: Self.titlesKey)
            let page = await browsers.activePage(of: app, withTitle: withTitle)
            pending.add(elapsed, key: page.map { UsageDay.siteKey($0.host) } ?? UsageDay.appKey(name), hour: hour)
            if let page, let title = page.title { pending.addTitle(elapsed, title: title, domain: page.host) }
        }
    }

    func flush(now: Date = Date()) {
        lastFlush = now
        guard !pending.hours.isEmpty else { pendingDate = now; return }
        var day = store.load(pendingDate)
        day.merge(pending)
        try? store.save(day, for: pendingDate)
        pending = UsageDay()
        pendingDate = now
    }

    private static var isAway: Bool {
        let anyInput = CGEventType(rawValue: ~0)!
        if CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput) >= idleLimit { return true }
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return session?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}
