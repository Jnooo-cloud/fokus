import Foundation

public struct BlockedApp: Codable, Equatable, Identifiable, Sendable {
    public var id: String { bundleID }
    public var bundleID: String
    public var name: String
    public var path: String

    public init(bundleID: String, name: String, path: String = "") {
        self.bundleID = bundleID
        self.name = name
        self.path = path
    }
}

public struct BlockList: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var domains: [String]
    public var apps: [BlockedApp]
    /// Subdomains that stay reachable even though a parent domain is blocked.
    public var exceptions: [String]
    /// Allowlist mode: every website is blocked except `exceptions`.
    public var blocksEverything: Bool

    public init(id: UUID = UUID(), name: String = "Ablenkung", domains: [String] = [], apps: [BlockedApp] = [],
                exceptions: [String] = [], blocksEverything: Bool = false) {
        self.id = id
        self.name = name
        self.domains = domains
        self.apps = apps
        self.exceptions = exceptions
        self.blocksEverything = blocksEverything
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        domains = try values.decode([String].self, forKey: .domains)
        apps = try values.decode([BlockedApp].self, forKey: .apps)
        exceptions = try values.decodeIfPresent([String].self, forKey: .exceptions) ?? []
        blocksEverything = try values.decodeIfPresent(Bool.self, forKey: .blocksEverything) ?? false
    }

    public var isEmpty: Bool { domains.isEmpty && apps.isEmpty && !blocksEverything }
    public var blocksWebsites: Bool { !domains.isEmpty || blocksEverything }
}

public enum SessionMode: String, Codable, CaseIterable, Sendable {
    case flexible, locked
    public var title: String { self == .flexible ? "Flexibel" : "Gesperrt" }
}

public struct PausePolicy: Codable, Equatable, Sendable {
    public var minutes: Int
    public var allowance: Int

    public init(minutes: Int = 5, allowance: Int = 1) {
        self.minutes = min(60, max(1, minutes))
        self.allowance = min(20, max(0, allowance))
    }
}

public struct SessionOptions: Codable, Equatable, Sendable {
    public var mode: SessionMode
    public var pause: PausePolicy

    public init(mode: SessionMode = .flexible, pause: PausePolicy = PausePolicy()) {
        self.mode = mode
        self.pause = pause
    }
}

public struct FocusSession: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var blockList: BlockList
    public var startsAt: Date
    public var endsAt: Date
    public var options: SessionOptions
    public var scheduleID: UUID?
    public var pausesUsed: Int
    public var pausedUntil: Date?
    public var stoppedAt: Date?

    public init(id: String = UUID().uuidString, name: String, blockList: BlockList,
                startsAt: Date, endsAt: Date, options: SessionOptions = SessionOptions(), scheduleID: UUID? = nil) {
        self.id = id
        self.name = name
        self.blockList = blockList
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.options = options
        self.scheduleID = scheduleID
        self.pausesUsed = 0
    }

    public func isActive(at date: Date) -> Bool {
        stoppedAt == nil && startsAt <= date && date < endsAt
    }

    public func isPaused(at date: Date) -> Bool {
        isActive(at: date) && (pausedUntil.map { date < $0 } ?? false)
    }

    public var pausesRemaining: Int { max(0, options.pause.allowance - pausesUsed) }

    /// Scheduled and locked sessions run until their end; only their pauses are available.
    public var isStrict: Bool { scheduleID != nil || options.mode == .locked }
}

/// A short, self-expiring release. `domain == nil` releases everything, apps included.
public struct TemporaryUnlock: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var domain: String?
    public var until: Date

    public init(id: UUID = UUID(), domain: String?, until: Date) {
        self.id = id
        self.domain = domain
        self.until = until
    }
}

/// What was released and why, so the overview can show the pattern.
public struct UnlockEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var date: Date
    public var target: String?
    public var reason: String
    public var minutes: Int

    public init(id: UUID = UUID(), date: Date, target: String?, reason: String, minutes: Int) {
        self.id = id
        self.date = date
        self.target = target
        self.reason = reason
        self.minutes = minutes
    }
}

public struct UnlockSettings: Codable, Equatable, Sendable {
    /// Wait before the first unlock of a day, in seconds.
    public var baseDelay: Int
    /// Added for every unlock already used today.
    public var stepDelay: Int
    public var maxDelay: Int
    public var dailyLimit: Int
    public var requiresReason: Bool

    public init(baseDelay: Int = 20, stepDelay: Int = 20, maxDelay: Int = 180, dailyLimit: Int = 6, requiresReason: Bool = true) {
        self.baseDelay = baseDelay
        self.stepDelay = stepDelay
        self.maxDelay = maxDelay
        self.dailyLimit = dailyLimit
        self.requiresReason = requiresReason
    }
}

/// Self-imposed lock: nothing can be unlocked until `until`, except through the slow emergency exit.
public struct HardMode: Codable, Equatable, Sendable {
    public var until: Date
    public var sessionID: String?

    public init(until: Date, sessionID: String?) {
        self.until = until
        self.sessionID = sessionID
    }
}

public enum ScheduleKind: String, Codable, CaseIterable, Sendable {
    case weekly, once
}

public struct FocusSchedule: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var blockListID: UUID
    public var isEnabled: Bool
    public var kind: ScheduleKind
    /// Calendar weekday: Sunday = 1, Saturday = 7. Dates follow the Mac's current time zone.
    public var weekdays: Set<Int>
    public var startMinute: Int
    public var endMinute: Int
    public var onceStart: Date
    public var onceEnd: Date
    public var options: SessionOptions

    public init(id: UUID = UUID(), name: String = "Deep work", blockListID: UUID,
                isEnabled: Bool = true, kind: ScheduleKind = .weekly,
                weekdays: Set<Int> = [2, 3, 4, 5, 6], startMinute: Int = 9 * 60, endMinute: Int = 11 * 60,
                onceStart: Date = Date(), onceEnd: Date = Date().addingTimeInterval(3600),
                options: SessionOptions = SessionOptions()) {
        self.id = id
        self.name = name
        self.blockListID = blockListID
        self.isEnabled = isEnabled
        self.kind = kind
        self.weekdays = weekdays
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.onceStart = onceStart
        self.onceEnd = onceEnd
        self.options = options
    }
}

public struct ZoneDocument: Codable, Equatable, Sendable {
    public var version: Int = 1
    public var blockLists: [BlockList]
    public var schedules: [FocusSchedule]
    /// Includes stopped occurrences until their original end, preventing an immediate restart.
    public var sessions: [FocusSession]
    public var defaultOptions: SessionOptions
    public var defaultMinutes: Int
    public var temporaryUnlocks: [TemporaryUnlock]
    /// Kept for 30 days so the overview can show the habit.
    public var unlockEntries: [UnlockEntry]
    public var unlockSettings: UnlockSettings
    public var hardMode: HardMode?

    public init(blockLists: [BlockList] = [BlockList()], schedules: [FocusSchedule] = [],
                sessions: [FocusSession] = [], defaultOptions: SessionOptions = SessionOptions(), defaultMinutes: Int = 25,
                temporaryUnlocks: [TemporaryUnlock] = [], unlockEntries: [UnlockEntry] = [],
                unlockSettings: UnlockSettings = UnlockSettings(), hardMode: HardMode? = nil) {
        self.blockLists = blockLists
        self.schedules = schedules
        self.sessions = sessions
        self.defaultOptions = defaultOptions
        self.defaultMinutes = defaultMinutes
        self.temporaryUnlocks = temporaryUnlocks
        self.unlockEntries = unlockEntries
        self.unlockSettings = unlockSettings
        self.hardMode = hardMode
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        blockLists = try values.decode([BlockList].self, forKey: .blockLists)
        schedules = try values.decode([FocusSchedule].self, forKey: .schedules)
        sessions = try values.decode([FocusSession].self, forKey: .sessions)
        defaultOptions = try values.decode(SessionOptions.self, forKey: .defaultOptions)
        defaultMinutes = try values.decode(Int.self, forKey: .defaultMinutes)
        temporaryUnlocks = try values.decodeIfPresent([TemporaryUnlock].self, forKey: .temporaryUnlocks) ?? []
        unlockEntries = try values.decodeIfPresent([UnlockEntry].self, forKey: .unlockEntries) ?? []
        unlockSettings = try values.decodeIfPresent(UnlockSettings.self, forKey: .unlockSettings) ?? UnlockSettings()
        hardMode = try values.decodeIfPresent(HardMode.self, forKey: .hardMode)
    }
}

public enum ZoneError: Error, LocalizedError, Equatable {
    case invalidDomain(String), invalidDuration, emptyBlockList, invalidSchedule, lockedSession, noPauses, inactiveSession
    case unsupportedVersion, invalidUnlock, hardModeActive, unlockLimitReached, missingReason

    public var errorDescription: String? {
        switch self {
        case .invalidDomain(let value): "„\(value)“ ist keine Website-Domain. Nimm einen Namen wie youtube.com."
        case .invalidDuration: "Wähle eine Dauer zwischen 1 Minute und 24 Stunden."
        case .emptyBlockList: "Füge dieser Sperrliste zuerst eine Website oder App hinzu."
        case .invalidSchedule: "Wähle gültige Zeiten und mindestens einen Tag."
        case .lockedSession: "Diese Sitzung läuft bis zum Ende. Du kannst nur entsperren."
        case .noPauses: "Diese Sitzung hat keine Pausen mehr."
        case .inactiveSession: "Diese Sitzung ist nicht mehr aktiv."
        case .unsupportedVersion: "Diese Daten stammen aus einer neueren Version von Fokus."
        case .invalidUnlock: "Entsperren geht nur für 5 oder 10 Minuten."
        case .hardModeActive: "Hard Mode läuft. Entsperren geht erst danach."
        case .unlockLimitReached: "Dein Tageslimit fürs Entsperren ist erreicht."
        case .missingReason: "Schreib kurz, wofür du es brauchst."
        }
    }
}
