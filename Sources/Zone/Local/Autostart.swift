import AppKit
import Foundation

/// Keeps Fokus running through a per-user LaunchAgent: it starts at login and launchd restarts it after
/// a crash or force quit, but not after a normal quit. install-local.sh writes the same file.
enum Autostart {
    static var label: String { Bundle.main.bundleIdentifier ?? "local.fokus.app" }
    static var plist: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }
    static var isInstalled: Bool { FileManager.default.fileExists(atPath: plist.path) }
    /// launchd names its jobs in the environment of the processes it starts.
    static var isRunningUnderLaunchd: Bool { ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] == label }

    /// Writes the agent and lets launchd start a managed copy. The copy asks this one to quit, so there is
    /// never more than one Fokus running.
    static func install() throws {
        guard let executable = Bundle.main.executablePath else { return }
        let contents: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "ThrottleInterval": 5,
            "LimitLoadToSessionType": "Aqua",
            "ProcessType": "Interactive",
        ]
        try FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: contents, format: .xml, options: 0)
        try data.write(to: plist, options: .atomic)
        launchctl(["bootout", "gui/\(getuid())/\(label)"])
        launchctl(["bootstrap", "gui/\(getuid())", plist.path])
    }

    static func remove() {
        launchctl(["bootout", "gui/\(getuid())/\(label)"])
        try? FileManager.default.removeItem(at: plist)
    }

    @discardableResult private static func launchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardError = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }

    // MARK: One copy at a time

    private static let handOver = Notification.Name("FokusHandOver")

    /// Call once at launch. Returns false when this copy should quit right away.
    @MainActor static func claimSingleInstance(onHandOver: @escaping @MainActor () -> Void) -> Bool {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: label)
            .filter { $0.processIdentifier != getpid() }
        if !others.isEmpty && !isRunningUnderLaunchd {
            others.first?.activate()
            return false
        }
        if !others.isEmpty {
            DistributedNotificationCenter.default().postNotificationName(handOver, object: label, deliverImmediately: true)
        }
        DistributedNotificationCenter.default().addObserver(forName: handOver, object: label, queue: .main) { _ in
            guard !isRunningUnderLaunchd else { return }
            Task { @MainActor in onHandOver() }
        }
        return true
    }

    /// A copy started from the disk image or a quarantined download runs from a read-only location.
    static var isInstalledLocation: Bool {
        let path = Bundle.main.bundlePath
        return !path.hasPrefix("/Volumes/") && !path.contains("/AppTranslocation/")
    }
}
