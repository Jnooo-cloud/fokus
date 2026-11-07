import Foundation
import Testing
@testable import ZoneCore

struct SessionTests {
    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Tehran")!
        return value
    }
    func date(_ year: Int = 2026, _ month: Int = 10, _ day: Int = 19, _ hour: Int = 10, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
    let list = BlockList(name: "Work", domains: ["example.com"], apps: [.init(bundleID: "com.example.game", name: "Game")])

    @Test func domainsNormalizeAndRespectBoundaries() throws {
        #expect(try DomainRule.normalize(" HTTPS://WWW.Example.COM/ ") == "example.com")
        #expect(try DomainRule.normalize("*.example.com") == "example.com")
        #expect(try DomainRule.normalize("example.com.") == "example.com")
        #expect(DomainRule.matches(host: "deep.sub.example.com", domain: "example.com"))
        #expect(!DomainRule.matches(host: "notexample.com", domain: "example.com"))
        #expect(!DomainRule.matches(host: "example.com.evil.com", domain: "example.com"))
        #expect(try DomainRule.parseList("example.com, www.example.com\nother.com") == ["example.com", "other.com"])
    }

    @Test(arguments: ["https://example.com/private", "example.com:8080", "https://user@example.com", "a..com", "-bad.com", "file:///etc/hosts", "127.0.0.1", "localhost", "example.com?search=hello"])
    func rejectsAmbiguousRules(_ input: String) { #expect(throws: ZoneError.self) { try DomainRule.normalize(input) } }

    @Test func exactSessionBoundariesAndSleepCatchUp() throws {
        let now = date()
        let session = try SessionEngine.start(list: list, minutes: 25, options: .init(), at: now)
        #expect(!session.isActive(at: now.addingTimeInterval(-1)))
        #expect(session.isActive(at: now))
        #expect(session.isActive(at: now.addingTimeInterval(1499)))
        #expect(!session.isActive(at: now.addingTimeInterval(1500)))
        let rules = EffectiveRules(document: .init(sessions: [session]), at: now.addingTimeInterval(3600))
        #expect(rules.domains.isEmpty)
        #expect(rules.applicationIDs.isEmpty)
    }

    @Test func lockedSessionsAllowOnlyConfiguredPauses() throws {
        let now = date()
        var session = try SessionEngine.start(list: list, minutes: 25,
            options: .init(mode: .locked, pause: .init(minutes: 5, allowance: 1)), at: now)
        #expect(throws: ZoneError.lockedSession) { try SessionEngine.stop(&session, at: now) }
        try SessionEngine.pause(&session, at: now)
        #expect(session.pausesRemaining == 0)
        #expect(session.isPaused(at: now.addingTimeInterval(299)))
        #expect(!session.isPaused(at: now.addingTimeInterval(300)))
        #expect(session.endsAt == now.addingTimeInterval(1500))
        #expect(throws: ZoneError.noPauses) { try SessionEngine.pause(&session, at: now.addingTimeInterval(301)) }
        #expect(throws: ZoneError.lockedSession) { try SessionEngine.stop(&session, at: now.addingTimeInterval(301)) }
    }

    @Test func earlyResumeDoesNotRefundPause() throws {
        let now = date()
        var session = try SessionEngine.start(list: list, minutes: 25, options: .init(), at: now)
        try SessionEngine.pause(&session, at: now)
        SessionEngine.resume(&session)
        #expect(!session.isPaused(at: now))
        #expect(session.pausesRemaining == 0)
        #expect(throws: ZoneError.noPauses) { try SessionEngine.pause(&session, at: now) }
    }

    @Test func pausesNeverExtendPastSession() throws {
        let now = date()
        var session = try SessionEngine.start(list: list, minutes: 1, options: .init(pause: .init(minutes: 60)), at: now)
        try SessionEngine.pause(&session, at: now.addingTimeInterval(30))
        #expect(session.pausedUntil == session.endsAt)
    }

    @Test func overlappingSessionsKeepTheirOwnRules() throws {
        let now = date()
        var first = try SessionEngine.start(list: list, minutes: 25, options: .init(), at: now)
        let second = try SessionEngine.start(list: BlockList(domains: ["other.com", "example.com"]), minutes: 45, options: .init(), at: now)
        try SessionEngine.pause(&first, at: now)
        let document = ZoneDocument(sessions: [first, second])
        #expect(EffectiveRules(document: document, at: now).domains == ["example.com", "other.com"])
        #expect(EffectiveRules(document: document, at: now).applicationIDs.isEmpty)
        #expect(EffectiveRules(document: document, at: now.addingTimeInterval(300)).applicationIDs == ["com.example.game"])
    }

    @Test func overnightUsesStartDayAndStopsAtExactEnd() throws {
        // Monday night into Tuesday.
        let schedule = FocusSchedule(blockListID: list.id, weekdays: [2], startMinute: 23 * 60, endMinute: 2 * 60)
        let interval = try #require(SessionEngine.activeInterval(for: schedule, at: date(2026, 10, 20, 1), calendar: calendar))
        #expect(interval.start == date(2026, 10, 19, 23))
        #expect(interval.end == date(2026, 10, 20, 2))
        #expect(SessionEngine.activeInterval(for: schedule, at: interval.end, calendar: calendar) == nil)
        #expect(SessionEngine.activeInterval(for: schedule, at: date(2026, 10, 21, 1), calendar: calendar) == nil)
    }

    @Test func scheduledSessionsCannotEndEarly() throws {
        let now = date()
        let schedule = FocusSchedule(blockListID: list.id, weekdays: [2], startMinute: 9 * 60, endMinute: 11 * 60,
                                     options: .init(mode: .flexible, pause: .init(minutes: 5, allowance: 1)))
        var document = ZoneDocument(blockLists: [list], schedules: [schedule])
        SessionEngine.materialize(&document, at: now, calendar: calendar)
        #expect(document.sessions[0].isStrict)
        #expect(throws: ZoneError.lockedSession) { try SessionEngine.stop(&document.sessions[0], at: now) }
        try SessionEngine.pause(&document.sessions[0], at: now)
        #expect(document.sessions[0].isPaused(at: now.addingTimeInterval(60)))
        #expect(throws: ZoneError.lockedSession) { try SessionEngine.stop(&document.sessions[0], at: now.addingTimeInterval(60)) }
        var oneOff = try SessionEngine.start(list: list, minutes: 25, options: .init(), at: now)
        #expect(!oneOff.isStrict)
        try SessionEngine.stop(&oneOff, at: now)
    }

    @Test func stoppedRecurringOccurrenceDoesNotRestart() throws {
        let now = date()
        let schedule = FocusSchedule(blockListID: list.id, weekdays: [2], startMinute: 9 * 60, endMinute: 11 * 60)
        var document = ZoneDocument(blockLists: [list], schedules: [schedule])
        SessionEngine.materialize(&document, at: now, calendar: calendar)
        #expect(document.sessions.count == 1)
        // Earlier versions allowed ending flexible scheduled sessions; their saved state still holds.
        document.sessions[0].stoppedAt = now
        SessionEngine.materialize(&document, at: now.addingTimeInterval(60), calendar: calendar)
        #expect(document.sessions.count == 1)
        #expect(SessionEngine.activeSessions(in: document, at: now, calendar: calendar).isEmpty)
        SessionEngine.materialize(&document, at: date(2026, 10, 26, 10), calendar: calendar)
        #expect(document.sessions.count == 1)
        #expect(document.sessions[0].isActive(at: date(2026, 10, 26, 10)))
    }

    @Test func editsCannotWeakenExistingLockedSession() {
        let now = date()
        var schedule = FocusSchedule(blockListID: list.id, weekdays: [2], startMinute: 9 * 60, endMinute: 11 * 60,
                                     options: .init(mode: .locked, pause: .init(allowance: 0)))
        var document = ZoneDocument(blockLists: [list], schedules: [schedule])
        SessionEngine.materialize(&document, at: now, calendar: calendar)
        document.blockLists[0].domains = []
        document.blockLists[0].apps = []
        schedule.isEnabled = false
        document.schedules = [schedule]
        SessionEngine.materialize(&document, at: now, calendar: calendar)
        #expect(document.sessions[0].blockList == list)
        #expect(document.sessions[0].options.mode == .locked)
        #expect(document.sessions[0].options.pause.allowance == 0)
        #expect(EffectiveRules(document: document, at: now, calendar: calendar).blocks(host: "example.com"))
    }

    @Test func oneOffCanStartAfterMissedWake() {
        let now = date()
        let schedule = FocusSchedule(blockListID: list.id, kind: .once, onceStart: now.addingTimeInterval(-3600), onceEnd: now.addingTimeInterval(3600))
        let document = ZoneDocument(blockLists: [list], schedules: [schedule])
        let active = SessionEngine.activeSessions(in: document, at: now)
        #expect(active.count == 1)
        #expect(active.first?.endsAt == schedule.onceEnd)
    }

    @Test func daylightSavingDoesNotCreateTwoOccurrences() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let day = newYork.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let schedule = FocusSchedule(blockListID: list.id, weekdays: [1], startMinute: 90, endMinute: 150)
        let interval = try #require(SessionEngine.occurrence(of: schedule, startingOn: day, calendar: newYork))
        #expect(interval.duration == 7200)
        let document = ZoneDocument(blockLists: [list], schedules: [schedule])
        let first = SessionEngine.activeSessions(in: document, at: interval.start, calendar: newYork)
        let second = SessionEngine.activeSessions(in: document, at: interval.start.addingTimeInterval(3600), calendar: newYork)
        #expect(first.first?.id == second.first?.id)
    }

    @Test func springGapMovesToNextValidTime() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let day = newYork.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let schedule = FocusSchedule(blockListID: list.id, weekdays: [1], startMinute: 150, endMinute: 240)
        let interval = try #require(SessionEngine.occurrence(of: schedule, startingOn: day, calendar: newYork))
        #expect(newYork.component(.hour, from: interval.start) == 3)
        #expect(newYork.component(.hour, from: interval.end) == 4)
    }

    @Test func nextWeekAndDisabledSchedule() throws {
        var schedule = FocusSchedule(blockListID: list.id, weekdays: [2], startMinute: 540, endMinute: 660)
        #expect(SessionEngine.nextInterval(for: schedule, after: date(), calendar: calendar)?.start == date(2026, 10, 26, 9))
        schedule.isEnabled = false
        #expect(SessionEngine.nextInterval(for: schedule, after: date(), calendar: calendar) == nil)
    }

    @Test func persistenceRetainsPauseAndStopState() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DocumentStore(url: directory.appendingPathComponent("sessions.json"))
        var session = try SessionEngine.start(list: list, minutes: 25, options: .init(), at: date())
        try SessionEngine.pause(&session, at: date())
        let document = ZoneDocument(blockLists: [list], sessions: [session])
        try store.save(document)
        #expect(try store.load() == document)
        try Data("broken".utf8).write(to: store.url)
        #expect(throws: (any Error).self) { try store.load() }
        #expect(try String(contentsOf: store.url, encoding: .utf8) == "broken")
    }

    @Test func invalidDurationsAndEmptyRules() {
        #expect(throws: ZoneError.invalidDuration) { try SessionEngine.start(list: list, minutes: 0, options: .init(), at: date()) }
        #expect(throws: ZoneError.emptyBlockList) { try SessionEngine.start(list: BlockList(), minutes: 25, options: .init(), at: date()) }
        let invalid = FocusSchedule(blockListID: list.id, startMinute: 540, endMinute: 540)
        #expect(throws: ZoneError.invalidSchedule) { try SessionEngine.validate(invalid) }
    }
}

struct FokusRuleTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func document(_ list: BlockList) throws -> ZoneDocument {
        let session = try SessionEngine.start(list: list, minutes: 60, options: SessionOptions(), at: now)
        return ZoneDocument(blockLists: [list], sessions: [session])
    }

    @Test func testExceptionKeepsSubdomainOpen() throws {
        let rules = EffectiveRules(document: try document(BlockList(domains: ["facebook.com"], exceptions: ["business.facebook.com"])), at: now)
        #expect(rules.blocks(host: "www.facebook.com"))
        #expect(!rules.blocks(host: "business.facebook.com"))
    }

    @Test func testAllowlistBlocksEverythingElse() throws {
        let rules = EffectiveRules(document: try document(BlockList(exceptions: ["arxiv.org"], blocksEverything: true)), at: now)
        #expect(rules.blocks(host: "youtube.com"))
        #expect(!rules.blocks(host: "www.arxiv.org"))
    }

    @Test func testUnlockExpiresByItself() throws {
        var doc = try document(BlockList(domains: ["youtube.com", "reddit.com"]))
        try SessionEngine.unlock(&doc, domain: "youtube.com", minutes: 5, reason: "Tutorial", at: now)
        let during = EffectiveRules(document: doc, at: now.addingTimeInterval(299))
        #expect(!during.blocks(host: "www.youtube.com"))
        #expect(during.blocks(host: "reddit.com"))
        #expect(EffectiveRules(document: doc, at: now.addingTimeInterval(301)).blocks(host: "www.youtube.com"))
    }

    @Test func testWaitGrowsAndLimitStops() throws {
        var doc = try document(BlockList(domains: ["youtube.com"]))
        doc.unlockSettings.dailyLimit = 2
        #expect(SessionEngine.unlockDelay(in: doc, at: now) == 20)
        try SessionEngine.unlock(&doc, domain: nil, minutes: 5, reason: "Eins", at: now)
        #expect(SessionEngine.unlockDelay(in: doc, at: now) == 40)
        try SessionEngine.unlock(&doc, domain: nil, minutes: 5, reason: "Zwei", at: now)
        #expect(throws: ZoneError.unlockLimitReached) { try SessionEngine.unlock(&doc, domain: nil, minutes: 5, reason: "Drei", at: now) }
    }

    @Test func testReasonIsRequired() throws {
        var doc = try document(BlockList(domains: ["youtube.com"]))
        #expect(throws: ZoneError.missingReason) { try SessionEngine.unlock(&doc, domain: nil, minutes: 5, reason: " ", at: now) }
    }

    @Test func testHardModeRevokesAndRefusesUnlocks() throws {
        let list = BlockList(domains: ["youtube.com"])
        var doc = ZoneDocument(blockLists: [list])
        try SessionEngine.unlock(&doc, domain: "youtube.com", minutes: 10, reason: "Vorher", at: now)
        try SessionEngine.startHard(&doc, list: list, minutes: 30, at: now)
        #expect(EffectiveRules(document: doc, at: now.addingTimeInterval(60)).blocks(host: "youtube.com"))
        #expect(throws: ZoneError.hardModeActive) { try SessionEngine.unlock(&doc, domain: nil, minutes: 5, reason: "Bitte", at: now) }
        SessionEngine.endHard(&doc, at: now.addingTimeInterval(60))
        #expect(!EffectiveRules(document: doc, at: now.addingTimeInterval(61)).blocks(host: "youtube.com"))
    }

    @Test func testOldSaveFileStillLoads() throws {
        let json = #"{"version":1,"blockLists":[{"id":"7B2E3F30-3B7C-4A7E-9C37-1E2A0F6B1C11","name":"A","domains":["x.com"],"apps":[]}],"schedules":[],"sessions":[],"defaultOptions":{"mode":"flexible","pause":{"minutes":5,"allowance":0}},"defaultMinutes":25}"#
        let doc = try JSONDecoder().decode(ZoneDocument.self, from: Data(json.utf8))
        #expect(doc.blockLists[0].exceptions.isEmpty)
        #expect(doc.unlockSettings.dailyLimit == 6)
    }
}

struct UsageTests {
    private let classify: UsageClassifier = { name, isSite in
        isSite && name == "youtube.com" ? .distraction : name == "Claude" ? .work : .neutral
    }

    @Test func testSummaryAddsUpByCategoryAndHour() {
        var day = UsageDay()
        day.add(600, key: UsageDay.siteKey("youtube.com"), hour: 14)
        day.add(300, key: UsageDay.siteKey("youtube.com"), hour: 14)
        day.add(1800, key: UsageDay.appKey("Claude"), hour: 9)
        let summary = UsageSummary(days: [day], classify: classify)
        #expect(summary.totals.distraction == 900)
        #expect(summary.totals.score == 67)
        #expect(summary.distractionByHour[14] == 900)
        #expect(summary.items.first?.name == "Claude")
    }

    @Test func testStoreMergesAndSurvivesMissingDays() throws {
        let store = UsageStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        #expect(store.load(Date()).hours.isEmpty)
        var day = UsageDay()
        day.add(5, key: "a:X", hour: 1)
        try store.save(day, for: Date())
        var loaded = store.load(Date())
        loaded.merge(day)
        #expect(loaded.hours["1"]?["a:X"] == 10)
    }

    @Test func testAdviceOffersOnlyUnblockedSites() {
        var day = UsageDay()
        day.add(7200, key: UsageDay.siteKey("youtube.com"), hour: 14)
        let current = UsageSummary(days: [day], classify: classify)
        let previous = UsageSummary(days: [], classify: classify)
        let open = WeekAdvice.suggestions(current: current, previous: previous, unlocks: 0, blocked: [])
        #expect(open.first?.blockDomain == "youtube.com")
        let blocked = WeekAdvice.suggestions(current: current, previous: previous, unlocks: 0, blocked: ["youtube.com"])
        #expect(blocked.allSatisfy { $0.blockDomain == nil })
    }

    @Test func testTitlesAreOptionalAndRemovable() throws {
        let old = try JSONDecoder().decode(UsageDay.self, from: Data(#"{"hours":{"9":{"s:youtube.com":60}}}"#.utf8))
        #expect(old.titles.isEmpty)
        let store = UsageStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        var day = UsageDay()
        day.add(60, key: UsageDay.siteKey("youtube.com"), hour: 9)
        day.addTitle(60, title: "Video A", domain: "youtube.com")
        try store.save(day, for: Date())
        #expect(UsageSummary(days: [store.load(Date())], classify: classify).titles["youtube.com"]?.first?.title == "Video A")
        store.removeTitles()
        #expect(store.load(Date()).titles.isEmpty)
        #expect(store.load(Date()).hours["9"]?["s:youtube.com"] == 60)
    }
}

struct CategoryTests {
    @Test func testSubgroupsInheritRatingAndDomainsCoverSubdomains() {
        var config = CategoryConfig()
        let fun = config.addGroup(name: "Ablenkung", rating: .distraction)
        let shop = config.addGroup(name: "Shopping", rating: .work, parentID: fun)
        config.assign(name: "amazon.de", isSite: true, to: shop)
        #expect(config.assignment(name: "smile.amazon.de", isSite: true) == shop)
        #expect(config.rating(of: shop) == .distraction)
        #expect(config.path(shop) == "Ablenkung › Shopping")
    }

    @Test func testDeletingMovesItemsUpOrClearsThem() {
        var config = CategoryConfig()
        let work = config.addGroup(name: "Arbeit", rating: .work)
        let dev = config.addGroup(name: "Entwicklung", rating: .work, parentID: work)
        config.assign(name: "Xcode", isSite: false, to: dev)
        config.delete(dev)
        #expect(config.assignment(name: "Xcode", isSite: false) == work)
        config.delete(work)
        #expect(config.assignment(name: "Xcode", isSite: false) == nil)
        #expect(config.groups.isEmpty)
    }

    @Test func testDefaultsMigrateOldChoices() {
        let config = CategoryConfig.defaults(migrating: ["youtube.com": "Arbeit", "Spotify": "Ablenkung"])
        #expect(config.rating(of: config.assignment(name: "youtube.com", isSite: true)) == .work)
        #expect(config.rating(of: config.assignment(name: "Spotify", isSite: false)) == .distraction)
        #expect(config.rating(of: config.assignment(name: "www.instagram.com", isSite: true)) == .distraction)
    }

    @Test func testSummaryCountsTimePerGroup() {
        var config = CategoryConfig()
        let fun = config.addGroup(name: "Ablenkung", rating: .distraction)
        config.assign(name: "youtube.com", isSite: true, to: fun)
        var day = UsageDay()
        day.add(600, key: UsageDay.siteKey("youtube.com"), hour: 20)
        day.add(300, key: UsageDay.appKey("Finder"), hour: 20)
        let frozen = config
        let summary = UsageSummary(days: [day], classify: { name, site in frozen.rating(of: frozen.assignment(name: name, isSite: site)) ?? .neutral },
                                   group: { name, site in frozen.assignment(name: name, isSite: site) })
        #expect(summary.byGroup[fun] == 600)
        #expect(summary.byGroup[nil] == 300)
        #expect(summary.totals.distraction == 600)
    }

    @Test func testTitleRulesMoveTimeAndPreferTheirDomain() {
        var config = CategoryConfig()
        let work = config.addGroup(name: "Arbeit", rating: .work)
        let research = config.addGroup(name: "Recherche", rating: .work, parentID: work)
        let fun = config.addGroup(name: "Ablenkung", rating: .distraction)
        config.assign(name: "youtube.com", isSite: true, to: fun)
        config.titleRules = [TitleRule(domain: nil, keyword: "tutorial", groupID: fun),
                             TitleRule(domain: "youtube.com", keyword: "Tutorial", groupID: research)]
        #expect(config.titleMatch(domain: "m.youtube.com", title: "Swift TUTORIAL") == research)
        #expect(config.titleMatch(domain: "vimeo.com", title: "tutorial") == fun)

        var day = UsageDay()
        day.add(600, key: UsageDay.siteKey("youtube.com"), hour: 10)
        day.add(600, key: UsageDay.siteKey("youtube.com"), hour: 20)
        day.addTitle(300, title: "Swift Tutorial", domain: "youtube.com")
        day.addTitle(900, title: "Katzenvideo", domain: "youtube.com")
        let frozen = config
        let summary = UsageSummary(days: [day], classify: { name, site in frozen.rating(of: frozen.assignment(name: name, isSite: site)) ?? .neutral },
                                   group: { name, site in frozen.assignment(name: name, isSite: site) }, titleRule: frozen.matcher)
        #expect(summary.totals.work == 300)
        #expect(summary.totals.distraction == 900)
        #expect(summary.byHour[10].work == 150)
        #expect(summary.byGroup[research] == 300)
        #expect(summary.byGroup[fun] == 900)
    }

    @Test func testDeletingAGroupMovesItsRulesUp() {
        var config = CategoryConfig()
        let work = config.addGroup(name: "Arbeit", rating: .work)
        let research = config.addGroup(name: "Recherche", rating: .work, parentID: work)
        config.titleRules = [TitleRule(domain: nil, keyword: "Doku", groupID: research)]
        config.delete(research)
        #expect(config.titleRules.first?.groupID == work)
        config.delete(work)
        #expect(config.titleRules.isEmpty)
    }
}
