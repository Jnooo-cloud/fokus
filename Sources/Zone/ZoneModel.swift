import AppKit
import Observation
import ZoneCore

@MainActor @Observable
final class ZoneModel {
    enum WebsiteMode: String, CaseIterable, Identifiable {
        case browser = "Browser control", network = "Network filter"
        var id: Self { self }
    }
    enum Page: String, CaseIterable, Identifiable {
        case dashboard = "Überblick", report = "Wochenbericht", focus = "Fokus", unlock = "Entsperren", lists = "Sperrlisten", schedules = "Zeitpläne", categories = "Kategorien"
        var id: Self { self }
        var symbol: String {
            switch self {
            case .dashboard: "chart.bar"
            case .report: "chart.line.uptrend.xyaxis"
            case .focus: "circle.dotted.circle"
            case .unlock: "lock.open"
            case .lists: "hand.raised"
            case .schedules: "calendar"
            case .categories: "square.grid.2x2"
            }
        }
    }

    private(set) var document: ZoneDocument
    private(set) var activeSessions: [FocusSession] = []
    private(set) var now = Date()
    var page: Page = .dashboard
    var unlockTarget: String?
    var unlockMinutes = 5
    var unlockReason = ""
    private(set) var emergencyReadyAt: Date?
    private(set) var attempts = UserDefaults.standard.dictionary(forKey: "blockedAttempts") as? [String: [String: Int]] ?? [:]
    private(set) var unlockReadyAt: Date?
    var editingList: BlockList?
    var editingSchedule: FocusSchedule?
    enum SettingsPane: Hashable { case general, websites }
    var settingsPane: SettingsPane = .general
    var selectedListID: UUID? {
        didSet { UserDefaults.standard.set(selectedListID?.uuidString, forKey: "selectedListID") }
    }
    var quickMinutesText = "25"
    var quickMinutes: Int {
        get { Int(quickMinutesText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0 }
        set { quickMinutesText = String(newValue) }
    }
    var quickOptions = SessionOptions()
    var errorMessage: String?
    var lastBlockedApp: String?
    var appBlockFailure: String?
    let filter = FilterController()
    let browsers = BrowserBlocker()
    let insights: InsightsStore
    @ObservationIgnored let tracker: UsageTracker
    private(set) var websiteMode: WebsiteMode = .browser
    private(set) var changingWebsiteMode = false
    private(set) var storageFailed = false
    @ObservationIgnored private let store: DocumentStore
    @ObservationIgnored private let blocker = AppBlocker()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var ticks = 0

    init() {
        let tracker = UsageTracker(browsers: browsers)
        self.tracker = tracker
        insights = InsightsStore(store: tracker.store, flush: { tracker.flush() })
        websiteMode = UserDefaults.standard.string(forKey: "websiteMode").flatMap(WebsiteMode.init(rawValue:)) ?? .browser
        let directory = FokusPaths.data
        store = DocumentStore(url: directory.appendingPathComponent("sessions.json"))
        let isFirstRun = !FileManager.default.fileExists(atPath: store.url.path)
        do { document = try store.load() }
        catch {
            document = ZoneDocument()
            storageFailed = true
            errorMessage = "Fokus konnte die gespeicherten Sitzungen nicht lesen. Die Datei bleibt erhalten. \(error.localizedDescription)"
        }
        if isFirstRun { document = Self.starterDocument(); try? store.save(document) }
        quickMinutes = document.defaultMinutes
        quickOptions = document.defaultOptions
        let previousList = UserDefaults.standard.string(forKey: "selectedListID").flatMap(UUID.init(uuidString:))
        selectedListID = document.blockLists.first(where: { $0.id == previousList && !$0.isEmpty })?.id
            ?? document.blockLists.first(where: { !$0.isEmpty })?.id ?? document.blockLists.first?.id
        browsers.onRedirect = { [weak self] host in self?.recordAttempt(host) }
        blocker.onBlocked = { [weak self] name in self?.lastBlockedApp = name; self?.appBlockFailure = nil }
        blocker.onFailure = { [weak self] name in self?.appBlockFailure = "\(name) ließ sich nicht schließen." }
        tick()
        if websiteMode == .network { filter.update(document) }
        let clock = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        clock.tolerance = 0.15
        // Keep enforcing and advancing sessions while a menu or picker is open.
        RunLoop.main.add(clock, forMode: .common)
        timer = clock
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        Task {
            if websiteMode == .network { await filter.refresh() }
            else if filter.isSignedBuild { _ = await filter.disable() }
        }
    }

    /// A ready list and a weekday schedule that starts switched off, so nothing blocks before the user decides.
    private static func starterDocument() -> ZoneDocument {
        let list = BlockList(domains: ["instagram.com", "tiktok.com", "youtube.com", "reddit.com", "x.com", "facebook.com"])
        let schedule = FocusSchedule(name: "Fokuszeit", blockListID: list.id, isEnabled: false, weekdays: [2, 3, 4, 5, 6],
                                     startMinute: 9 * 60, endMinute: 17 * 60)
        return ZoneDocument(blockLists: [list], schedules: [schedule])
    }

    var activeUnlocks: [TemporaryUnlock] { document.temporaryUnlocks.filter { $0.until > now } }
    var blockedTargets: [String] {
        let rules = EffectiveRules(document: document, at: now)
        return rules.domains.filter { domain in domain != DomainRule.everything && !rules.exceptions.contains(domain) }.sorted()
    }
    var hasBlocks: Bool {
        let rules = EffectiveRules(document: document, at: now)
        return !rules.domains.isEmpty || !rules.applicationIDs.isEmpty
    }
    var allBlockedDomains: [String] { document.blockLists.flatMap(\.domains) }
    var unlocksToday: Int { SessionEngine.unlocksToday(in: document, at: now) }
    var unlockDelay: TimeInterval { SessionEngine.unlockDelay(in: document, at: now) }
    var recentUnlocks: [UnlockEntry] { Array(document.unlockEntries.suffix(6).reversed()) }
    var isHard: Bool { SessionEngine.isHard(document, at: now) }
    var hardEndText: String { document.hardMode?.until.formatted(date: .omitted, time: .shortened) ?? "" }
    var attemptsToday: [String: Int] { attempts[Self.dayKey(now)] ?? [:] }

    private static func dayKey(_ date: Date) -> String { date.formatted(.iso8601.year().month().day()) }

    private func recordAttempt(_ host: String) {
        let key = Self.dayKey(Date())
        attempts = attempts.filter { $0.key >= Self.dayKey(Date().addingTimeInterval(-30 * 86400)) }
        attempts[key, default: [:]][host, default: 0] += 1
        UserDefaults.standard.set(attempts, forKey: "blockedAttempts")
    }

    func beginUnlock() { unlockReadyAt = Date().addingTimeInterval(unlockDelay) }
    func cancelUnlock() { unlockReadyAt = nil }

    func confirmUnlock() {
        guard let ready = unlockReadyAt, ready <= Date() else { return }
        unlockReadyAt = nil
        var next = document
        do {
            try SessionEngine.unlock(&next, domain: unlockTarget, minutes: unlockMinutes, reason: unlockReason, at: Date())
            commit(next)
            unlockReason = ""
            tick()
        } catch { errorMessage = error.localizedDescription }
    }

    func addToSelectedList(_ domain: String) {
        guard var list = selectedList ?? document.blockLists.first, !list.domains.contains(domain) else { return }
        list.domains = (list.domains + [domain]).sorted()
        saveList(list)
        insights.refresh(blockedDomains: allBlockedDomains)
    }

    func startHard(minutes: Int) {
        guard let list = selectedList else { return }
        var next = document
        do { try SessionEngine.startHard(&next, list: list, minutes: minutes, at: Date()); commit(next); tick() }
        catch { errorMessage = error.localizedDescription }
    }

    func beginEmergency() { emergencyReadyAt = Date().addingTimeInterval(SessionEngine.emergencyDelay) }
    func cancelEmergency() { emergencyReadyAt = nil }

    func endHard() {
        guard let ready = emergencyReadyAt, ready <= Date() else { return }
        emergencyReadyAt = nil
        var next = document
        SessionEngine.endHard(&next, at: Date())
        commit(next)
        tick()
    }

    func updateUnlockSettings(_ settings: UnlockSettings) {
        var next = document
        next.unlockSettings = settings
        commit(next)
    }

    func relock(_ unlock: TemporaryUnlock) {
        var next = document
        next.temporaryUnlocks.removeAll { $0.id == unlock.id }
        commit(next)
        tick()
    }

    var selectedList: BlockList? { document.blockLists.first { $0.id == selectedListID } }
    var availableLists: [BlockList] { document.blockLists.filter { !$0.isEmpty } }
    var nextScheduledSession: (name: String, start: Date)? {
        document.schedules.compactMap { schedule -> (name: String, start: Date)? in
            guard let interval = SessionEngine.nextInterval(for: schedule, after: now) else { return nil }
            return (schedule.name, interval.start)
        }.min { $0.start < $1.start }
    }
    var hasStrictSession: Bool { activeSessions.contains(where: \.isStrict) }
    var hasWebsiteSession: Bool { activeSessions.contains { $0.blockList.blocksWebsites } }

    enum MenuState { case idle, focusing, paused }
    var menuState: MenuState {
        if activeSessions.isEmpty { return .idle }
        return activeSessions.contains { !$0.isPaused(at: now) } ? .focusing : .paused
    }
    /// Time until blocking fully ends, or until the earliest pause ends when every session is paused.
    var menuTitle: String {
        let focusing = activeSessions.filter { !$0.isPaused(at: now) }
        let until = focusing.isEmpty
            ? activeSessions.map { min($0.pausedUntil ?? $0.endsAt, $0.endsAt) }.min()
            : focusing.map(\.endsAt).max()
        return until.map { Self.shortDuration($0.timeIntervalSince(now)) } ?? ""
    }

    static func shortDuration(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int(ceil(interval / 60)))
        if minutes < 60 { return "\(minutes)m" }
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
    }

    static let durationPresets = [15, 25, 30, 45, 60, 90, 120]
    var durationChoices: [Int] {
        let presets = Self.durationPresets
        return (1...1440).contains(quickMinutes) && !presets.contains(quickMinutes) ? (presets + [quickMinutes]).sorted() : presets
    }

    func isRunning(_ schedule: FocusSchedule) -> Bool { activeSessions.contains { $0.scheduleID == schedule.id } }
    func runningSession(for schedule: FocusSchedule) -> FocusSession? { activeSessions.first { $0.scheduleID == schedule.id } }
    var isEditing: Bool { editingList != nil || editingSchedule != nil }

    /// Running schedules first, then by their next start; schedules that are off come last.
    var schedulesByNextStart: [FocusSchedule] {
        let ranked = document.schedules.map { schedule -> (schedule: FocusSchedule, group: Int, date: Date) in
            if let session = runningSession(for: schedule) { return (schedule, 0, session.endsAt) }
            if let next = SessionEngine.nextInterval(for: schedule, after: now) { return (schedule, 1, next.start) }
            return (schedule, schedule.isEnabled ? 2 : 3, .distantFuture)
        }
        return ranked.sorted { a, b in
            a.group != b.group ? a.group < b.group : a.date != b.date ? a.date < b.date
                : a.schedule.name.localizedStandardCompare(b.schedule.name) == .orderedAscending
        }.map(\.schedule)
    }
    var websiteBlockingReady: Bool { websiteMode == .browser ? browsers.hasConnectedBrowser : filter.isReady }
    var blockingIsDegraded: Bool {
        hasWebsiteSession && (!websiteBlockingReady || (websiteMode == .browser && browsers.attention != nil))
    }
    var websiteBlockingTitle: String {
        if websiteMode == .network { return filter.state.title }
        if browsers.attention != nil { return "Browser-Zugriff prüfen" }
        return websiteBlockingReady ? "Browser sind bereit" : "Browser verbinden"
    }

    func newList() {
        editingList = document.blockLists.count == 1 && document.blockLists[0].isEmpty
            ? document.blockLists[0] : BlockList(name: "")
    }

    func newSchedule() {
        guard let list = availableLists.first(where: { $0.id == selectedListID }) ?? availableLists.first else {
            newList()
            return
        }
        editingSchedule = FocusSchedule(blockListID: list.id, isEnabled: list.domains.isEmpty || websiteBlockingReady,
            onceStart: Date().addingTimeInterval(3600), onceEnd: Date().addingTimeInterval(7200))
    }
    var websiteBlockingDetail: String {
        if websiteMode == .network { return filter.detail }
        return browsers.attention ?? (websiteBlockingReady
            ? "Gesperrte Tabs werden umgeleitet, solange Fokus läuft."
            : "Verbinde deine Browser in den Einstellungen.")
    }

    func setWebsiteMode(_ mode: WebsiteMode) {
        guard mode != websiteMode, !hasWebsiteSession, !changingWebsiteMode else { return }
        changingWebsiteMode = true
        Task {
            defer { changingWebsiteMode = false }
            if mode == .browser {
                _ = await filter.finishPendingUpdates()
                guard await filter.disable() else {
                    errorMessage = "Could not turn off the network filter. Check its status before switching modes."
                    return
                }
            }
            websiteMode = mode
            UserDefaults.standard.set(mode.rawValue, forKey: "websiteMode")
            if mode == .network { filter.update(document) }
            tick()
        }
    }

    func tick() {
        now = Date()
        tracker.tick(now: now)
        // A confirm button left unanswered would otherwise stay a free pass.
        if let ready = unlockReadyAt, now.timeIntervalSince(ready) > 30 { unlockReadyAt = nil }
        guard !storageFailed else { return }
        var next = document
        SessionEngine.materialize(&next, at: now)
        if next != document { commit(next) }
        activeSessions = SessionEngine.activeSessions(in: document, at: now)
        blocker.update(EffectiveRules(document: document, at: now).applicationIDs)
        browsers.update(document, enabled: websiteMode == .browser)
        ticks += 1
        if ticks % 5 == 0 && websiteMode == .network { Task { await filter.refresh() } }
    }

    func startQuickSession() {
        guard let list = selectedList else { return }
        do {
            if !list.domains.isEmpty && !websiteBlockingReady {
                errorMessage = "Richte erst die Website-Sperre in den Einstellungen ein."
                return
            }
            let session = try SessionEngine.start(list: list, minutes: quickMinutes, options: quickOptions, at: Date())
            var next = document
            next.defaultMinutes = quickMinutes
            next.defaultOptions = quickOptions
            next.sessions.append(session)
            commit(next)
            tick()
        } catch { errorMessage = error.localizedDescription }
    }

    func pause(_ session: FocusSession) { changeSession(session) { try SessionEngine.pause(&$0, at: Date()) } }
    func resume(_ session: FocusSession) { changeSession(session) { SessionEngine.resume(&$0) } }
    func stop(_ session: FocusSession) { changeSession(session) { try SessionEngine.stop(&$0, at: Date()) } }

    private func changeSession(_ session: FocusSession, _ update: (inout FocusSession) throws -> Void) {
        var next = document
        guard let index = next.sessions.firstIndex(where: { $0.id == session.id }) else { return }
        do { try update(&next.sessions[index]); commit(next); tick() }
        catch { errorMessage = error.localizedDescription }
    }

    @discardableResult func saveList(_ list: BlockList) -> Bool {
        var next = document
        if let index = next.blockLists.firstIndex(where: { $0.id == list.id }) { next.blockLists[index] = list }
        else { next.blockLists.append(list) }
        if commit(next) {
            selectedListID = list.isEmpty ? availableLists.first?.id : list.id
            return true
        }
        return false
    }

    func deleteList(_ list: BlockList) {
        guard !document.schedules.contains(where: { $0.blockListID == list.id }) else {
            errorMessage = "Entferne erst die Zeitpläne, die diese Liste nutzen."
            return
        }
        var next = document
        next.blockLists.removeAll { $0.id == list.id }
        if commit(next), selectedListID == list.id { selectedListID = availableLists.first?.id }
    }

    func saveSchedule(_ schedule: FocusSchedule) -> Bool {
        if let session = runningSession(for: schedule) {
            errorMessage = Self.runningScheduleMessage(session)
            return false
        }
        do {
            try SessionEngine.validate(schedule)
            guard let list = document.blockLists.first(where: { $0.id == schedule.blockListID }), !list.isEmpty else { throw ZoneError.emptyBlockList }
            if schedule.isEnabled && !list.domains.isEmpty && !websiteBlockingReady {
                errorMessage = "Speichere den Zeitplan deaktiviert und verbinde dann deine Browser in den Einstellungen."
                return false
            }
            var next = document
            if let index = next.schedules.firstIndex(where: { $0.id == schedule.id }) { next.schedules[index] = schedule }
            else { next.schedules.append(schedule) }
            let saved = commit(next)
            tick()
            return saved
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func deleteSchedule(_ schedule: FocusSchedule) {
        if let session = runningSession(for: schedule) {
            errorMessage = Self.runningScheduleMessage(session)
            return
        }
        var next = document
        next.schedules.removeAll { $0.id == schedule.id }
        commit(next)
    }

    /// Scheduled sessions are strict: their schedule stays as it is until the session ends.
    static func runningScheduleMessage(_ session: FocusSession) -> String {
        "This schedule is running. You can change it after it ends at \(session.endsAt.formatted(date: .omitted, time: .shortened))."
    }

    func quit() {
        guard !hasStrictSession else { errorMessage = "Fokus bleibt offen, bis deine geplante oder gesperrte Sitzung endet."; return }
        if !activeSessions.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Sitzungen beenden und Fokus schließen?"
            alert.informativeText = websiteMode == .browser
                ? "Laufende Sitzungen enden. Geplante Sitzungen brauchen ein laufendes Fokus."
                : "Current sessions will end. App schedules need Zone running. Website schedules can continue in the network filter."
            alert.addButton(withTitle: "Sitzung beendens and Quit")
            alert.addButton(withTitle: "Abbrechen")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            var next = document
            for index in next.sessions.indices where next.sessions[index].isActive(at: Date()) {
                try? SessionEngine.stop(&next.sessions[index], at: Date())
            }
            guard commit(next) else { return }
        }
        Task {
            if websiteMode == .network, !(await filter.finishPendingUpdates()) {
                errorMessage = "Zone could not confirm the website filter received the changes. It will stay open so you can check its status."
                return
            }
            NSApplication.shared.terminate(nil)
        }
    }

    @discardableResult private func commit(_ next: ZoneDocument) -> Bool {
        guard !storageFailed else {
            errorMessage = "Saved data could not be read. Fix or restore the sessions file and restart Zone before making changes."
            return false
        }
        do {
            try store.save(next)
            document = next
            if websiteMode == .network { filter.update(next) }
            browsers.update(next, enabled: websiteMode == .browser)
            return true
        } catch { errorMessage = "Could not save changes: \(error.localizedDescription)"; return false }
    }
}
