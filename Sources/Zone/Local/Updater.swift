import AppKit
import CryptoKit
import Foundation
import Observation
import ZoneCore

/// Finds new versions in a public GitHub releases repo and installs them in place.
/// Each release carries `Fokus-<version>.zip` and `Fokus-<version>.zip.sig`. The signature is checked
/// against the public key built into the app, so only archives signed by the maintainer get installed.
@MainActor @Observable
final class Updater {
    enum State: Equatable {
        case idle, checking, upToDate, available, downloading, installing
        case failed(String)
    }

    struct Release: Equatable {
        let version: String
        let notes: String
        let archive: URL
        let signature: URL
    }

    private(set) var state = State.idle
    private(set) var latest: Release?
    private(set) var lastCheck: Date?
    /// Only release builds name a feed. Local builds from install-local.sh update by rebuilding.
    let repo = Bundle.main.object(forInfoDictionaryKey: "FokusUpdateRepo") as? String
    let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    @ObservationIgnored private let publicKey = Bundle.main.object(forInfoDictionaryKey: "FokusUpdateKey") as? String
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored var onTestInstall: (() -> Void)?

    var isEnabled: Bool { repo != nil && publicKey != nil }
    var hasUpdate: Bool { latest != nil && [.available, .downloading, .installing].contains(state) || isFailedWithRelease }
    private var isFailedWithRelease: Bool { if case .failed = state { return latest != nil } else { return false } }

    func start() {
        guard isEnabled, timer == nil else { return }
        Task { await check() }
        let every = Timer(timeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check() }
        }
        RunLoop.main.add(every, forMode: .common)
        timer = every
    }

    func check() async {
        guard let repo, state != .downloading, state != .installing else { return }
        state = .checking
        do {
            // FOKUS_UPDATE_FEED points the check at a local copy of the feed for testing.
            let feedURL = ProcessInfo.processInfo.environment["FOKUS_UPDATE_FEED"].flatMap(URL.init(string:))
                ?? URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
            var request = URLRequest(url: feedURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Fokus/\(current)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            lastCheck = Date()
            guard (response as? HTTPURLResponse).map({ $0.statusCode == 200 }) ?? feedURL.isFileURL else { state = .upToDate; return }
            let feed = try JSONDecoder().decode(Feed.self, from: data)
            let version = feed.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            guard Self.isNewer(version, than: current) else { latest = nil; state = .upToDate; return }
            guard let archive = feed.assets.first(where: { $0.name == "Fokus-\(version).zip" }),
                  let signature = feed.assets.first(where: { $0.name == "Fokus-\(version).zip.sig" }) else {
                latest = nil; state = .upToDate; return
            }
            latest = Release(version: version, notes: feed.body ?? "", archive: archive.browser_download_url, signature: signature.browser_download_url)
            state = .available
            // Test hook: installs right away so the whole path runs without clicking.
            if ProcessInfo.processInfo.environment["FOKUS_TEST_UPDATE"] == "1" { onTestInstall?() }
        } catch {
            lastCheck = Date()
            state = .failed(L("Update-Prüfung fehlgeschlagen. Keine Verbindung?", "Update check failed. No connection?"))
        }
    }

    /// Downloads, verifies and swaps the app, then hands over to a small helper that restarts Fokus.
    func install(blockedReason: String?, beforeQuit: () -> Void) async {
        guard let latest, let publicKey else { return }
        if let blockedReason { state = .failed(blockedReason); return }
        state = .downloading
        do {
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("fokus-update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let archive = work.appendingPathComponent("Fokus.zip")
            let (downloaded, _) = try await URLSession.shared.download(from: latest.archive)
            try FileManager.default.moveItem(at: downloaded, to: archive)
            let (signatureData, _) = try await URLSession.shared.data(from: latest.signature)

            let key = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: publicKey) ?? Data())
            let signature = Data(base64Encoded: String(decoding: signatureData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)) ?? Data()
            guard key.isValidSignature(signature, for: try Data(contentsOf: archive)) else {
                throw UpdateError(L("Die Signatur des Updates stimmt nicht. Nichts wurde geändert.", "The update signature does not match. Nothing was changed."))
            }

            state = .installing
            let unpacked = work.appendingPathComponent("unpacked")
            try Self.run("/usr/bin/ditto", ["-x", "-k", archive.path, unpacked.path])
            let newApp = unpacked.appendingPathComponent("Fokus.app")
            let info = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist"))
            guard info?["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
                  info?["CFBundleShortVersionString"] as? String == latest.version else {
                throw UpdateError(L("Das Update passt nicht zu dieser App. Nichts wurde geändert.", "The update does not match this app. Nothing was changed."))
            }
            try Self.handOver(newApp: newApp, work: work)
            beforeQuit()
            exit(0)
        } catch let error as UpdateError {
            state = .failed(error.message)
        } catch {
            state = .failed(L("Update fehlgeschlagen: \(error.localizedDescription)", "Update failed: \(error.localizedDescription)"))
        }
    }

    /// The helper waits for this process to end, swaps the bundle, and starts Fokus again. It runs in its
    /// own session so launchd does not stop it together with this app.
    private static func handOver(newApp: URL, work: URL) throws {
        let target = Bundle.main.bundleURL.path
        let label = Bundle.main.bundleIdentifier ?? "local.fokus.app"
        let script = """
        while kill -0 \(getpid()) 2>/dev/null; do sleep 0.2; done
        backup="\(work.path)/previous.app"
        mv "\(target)" "$backup" || exit 1
        if ! mv "\(newApp.path)" "\(target)"; then mv "$backup" "\(target)"; fi
        xattr -dr com.apple.quarantine "\(target)" 2>/dev/null
        launchctl kickstart "gui/$(id -u)/\(label)" 2>/dev/null || open "\(target)"
        """
        let scriptURL = work.appendingPathComponent("install.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))
        var pid: pid_t = 0
        let arguments = ["/bin/sh", scriptURL.path]
        var argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        let status = posix_spawn(&pid, "/bin/sh", nil, &attributes, &argv, environ)
        guard status == 0 else { throw UpdateError(L("Konnte das Update nicht starten (\(status)).", "Could not start the update (\(status)).")) }
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError(L("Entpacken fehlgeschlagen.", "Unpacking failed.")) }
    }

    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let left = index < a.count ? a[index] : 0, right = index < b.count ? b[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    private struct Feed: Decodable {
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        let tag_name: String
        let body: String?
        let assets: [Asset]
    }

    private struct UpdateError: Error { let message: String; init(_ message: String) { self.message = message } }
}
