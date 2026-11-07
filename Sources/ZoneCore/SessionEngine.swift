import Foundation

public enum SessionEngine {
    public static func validate(_ schedule: FocusSchedule) throws {
        if schedule.kind == .once {
            guard schedule.onceEnd > schedule.onceStart,
                  schedule.onceEnd.timeIntervalSince(schedule.onceStart) <= 86400 else { throw ZoneError.invalidSchedule }
        } else {
            guard !schedule.weekdays.isEmpty, schedule.weekdays.allSatisfy({ (1...7).contains($0) }),
                  (0..<1440).contains(schedule.startMinute), (0..<1440).contains(schedule.endMinute),
                  schedule.startMinute != schedule.endMinute else { throw ZoneError.invalidSchedule }
        }
    }

    public static func occurrence(of schedule: FocusSchedule, startingOn day: Date,
                                  calendar: Calendar = .autoupdatingCurrent) -> DateInterval? {
        guard schedule.kind == .weekly, schedule.weekdays.contains(calendar.component(.weekday, from: day)),
              (try? validate(schedule)) != nil else { return nil }
        let midnight = calendar.startOfDay(for: day)
        // One occurrence on fall-back days; missing wall times advance to the next valid time.
        guard let start = calendar.date(bySettingHour: schedule.startMinute / 60, minute: schedule.startMinute % 60,
                                        second: 0, of: midnight, matchingPolicy: .nextTime, repeatedTimePolicy: .first),
              let endDay = schedule.endMinute <= schedule.startMinute
                ? calendar.date(byAdding: .day, value: 1, to: midnight) : midnight,
              let end = calendar.date(bySettingHour: schedule.endMinute / 60, minute: schedule.endMinute % 60,
                                      second: 0, of: endDay, matchingPolicy: .nextTime, repeatedTimePolicy: .first),
              end > start else { return nil }
        return DateInterval(start: start, end: end)
    }

    public static func activeInterval(for schedule: FocusSchedule, at now: Date,
                                      calendar: Calendar = .autoupdatingCurrent) -> DateInterval? {
        guard schedule.isEnabled else { return nil }
        if schedule.kind == .once {
            guard schedule.onceStart <= now && now < schedule.onceEnd else { return nil }
            return DateInterval(start: schedule.onceStart, end: schedule.onceEnd)
        }
        for offset in [-1, 0] {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  let interval = occurrence(of: schedule, startingOn: day, calendar: calendar),
                  interval.start <= now && now < interval.end else { continue }
            return interval
        }
        return nil
    }

    public static func nextInterval(for schedule: FocusSchedule, after now: Date,
                                    calendar: Calendar = .autoupdatingCurrent) -> DateInterval? {
        guard schedule.isEnabled else { return nil }
        if schedule.kind == .once {
            return schedule.onceStart > now ? DateInterval(start: schedule.onceStart, end: schedule.onceEnd) : nil
        }
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  let interval = occurrence(of: schedule, startingOn: day, calendar: calendar),
                  interval.start > now else { continue }
            return interval
        }
        return nil
    }

    public static func materialize(_ document: inout ZoneDocument, at now: Date,
                                   calendar: Calendar = .autoupdatingCurrent) {
        document.sessions.removeAll { $0.endsAt <= now }
        document.temporaryUnlocks.removeAll { $0.until <= now }
        document.unlockEntries.removeAll { now.timeIntervalSince($0.date) > 30 * 86400 }
        if let hard = document.hardMode, hard.until <= now { document.hardMode = nil }
        for schedule in document.schedules {
            guard let interval = activeInterval(for: schedule, at: now, calendar: calendar),
                  let list = document.blockLists.first(where: { $0.id == schedule.blockListID }), !list.isEmpty else { continue }
            let id = schedule.id.uuidString + ":" + String(Int(interval.start.timeIntervalSince1970))
            guard !document.sessions.contains(where: { $0.id == id }) else { continue }
            document.sessions.append(FocusSession(id: id, name: schedule.name, blockList: list,
                startsAt: interval.start, endsAt: interval.end, options: schedule.options, scheduleID: schedule.id))
        }
    }

    public static func activeSessions(in document: ZoneDocument, at now: Date,
                                      calendar: Calendar = .autoupdatingCurrent) -> [FocusSession] {
        var copy = document
        materialize(&copy, at: now, calendar: calendar)
        return copy.sessions.filter { $0.isActive(at: now) }.sorted { $0.endsAt < $1.endsAt }
    }

    public static func start(list: BlockList, minutes: Int, options: SessionOptions, at now: Date) throws -> FocusSession {
        guard !list.isEmpty else { throw ZoneError.emptyBlockList }
        guard (1...1440).contains(minutes) else { throw ZoneError.invalidDuration }
        return FocusSession(name: list.name, blockList: list, startsAt: now,
                            endsAt: now.addingTimeInterval(Double(minutes) * 60), options: options)
    }

    public static let unlockChoices = [5, 10]
    public static let hardChoices = [30, 60, 120, 240]
    public static let emergencyDelay: TimeInterval = 300

    public static func unlocksToday(in document: ZoneDocument, at now: Date, calendar: Calendar = .autoupdatingCurrent) -> Int {
        document.unlockEntries.filter { calendar.isDate($0.date, inSameDayAs: now) }.count
    }

    /// Every unlock today makes the next wait longer.
    public static func unlockDelay(in document: ZoneDocument, at now: Date) -> TimeInterval {
        let settings = document.unlockSettings
        return Double(min(settings.maxDelay, settings.baseDelay + settings.stepDelay * unlocksToday(in: document, at: now)))
    }

    public static func isHard(_ document: ZoneDocument, at now: Date) -> Bool {
        document.hardMode.map { $0.until > now } ?? false
    }

    public static func unlock(_ document: inout ZoneDocument, domain: String?, minutes: Int, reason: String, at now: Date) throws {
        guard unlockChoices.contains(minutes) else { throw ZoneError.invalidUnlock }
        guard !isHard(document, at: now) else { throw ZoneError.hardModeActive }
        guard unlocksToday(in: document, at: now) < document.unlockSettings.dailyLimit else { throw ZoneError.unlockLimitReached }
        let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !document.unlockSettings.requiresReason || reason.count >= 3 else { throw ZoneError.missingReason }
        document.temporaryUnlocks.removeAll { $0.domain == domain }
        document.temporaryUnlocks.append(TemporaryUnlock(domain: domain, until: now.addingTimeInterval(Double(minutes) * 60)))
        document.unlockEntries.append(UnlockEntry(date: now, target: domain, reason: reason, minutes: minutes))
    }

    /// Starts a locked session with `list` and revokes anything currently unlocked.
    public static func startHard(_ document: inout ZoneDocument, list: BlockList, minutes: Int, at now: Date) throws {
        let session = try start(list: list, minutes: minutes, options: SessionOptions(mode: .locked), at: now)
        document.sessions.append(session)
        document.temporaryUnlocks.removeAll()
        document.hardMode = HardMode(until: session.endsAt, sessionID: session.id)
    }

    /// The emergency exit. The caller enforces the long wait.
    public static func endHard(_ document: inout ZoneDocument, at now: Date) {
        if let id = document.hardMode?.sessionID, let index = document.sessions.firstIndex(where: { $0.id == id }) {
            document.sessions[index].stoppedAt = now
        }
        document.hardMode = nil
    }

    public static func pause(_ session: inout FocusSession, at now: Date) throws {
        guard session.isActive(at: now), !session.isPaused(at: now) else { throw ZoneError.inactiveSession }
        guard session.pausesRemaining > 0 else { throw ZoneError.noPauses }
        session.pausesUsed += 1
        session.pausedUntil = min(session.endsAt, now.addingTimeInterval(Double(session.options.pause.minutes) * 60))
    }

    public static func resume(_ session: inout FocusSession) { session.pausedUntil = nil }

    public static func stop(_ session: inout FocusSession, at now: Date) throws {
        guard session.isActive(at: now) else { throw ZoneError.inactiveSession }
        guard !session.isStrict else { throw ZoneError.lockedSession }
        session.stoppedAt = now
        session.pausedUntil = nil
    }
}

public struct EffectiveRules: Equatable, Sendable {
    public var domains: Set<String>
    public var applicationIDs: Set<String>
    /// Blocked domains' subdomains that stay open, plus anything temporarily unlocked.
    public var exceptions: Set<String>

    public init(document: ZoneDocument, at now: Date, calendar: Calendar = .autoupdatingCurrent) {
        let sessions = SessionEngine.activeSessions(in: document, at: now, calendar: calendar).filter { !$0.isPaused(at: now) }
        let unlocks = SessionEngine.isHard(document, at: now) ? [] : document.temporaryUnlocks.filter { $0.until > now }
        guard !unlocks.contains(where: { $0.domain == nil }) else {
            domains = []; applicationIDs = []; exceptions = []
            return
        }
        domains = Set(sessions.flatMap { $0.blockList.domains + ($0.blockList.blocksEverything ? [DomainRule.everything] : []) })
        applicationIDs = Set(sessions.flatMap { $0.blockList.apps.map(\.bundleID) })
        exceptions = Set(sessions.flatMap { $0.blockList.exceptions } + unlocks.compactMap(\.domain))
    }

    public func blocks(host: String) -> Bool {
        domains.contains { DomainRule.matches(host: host, domain: $0) }
            && !exceptions.contains { DomainRule.matches(host: host, domain: $0) }
    }
}
