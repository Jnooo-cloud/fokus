import AppKit

/// Developer check without screen recording rights: FOKUS_SNAPSHOT=<dir> renders every page to PNG, then quits.
/// Run the binary directly (see scripts/snapshot.sh); it reads the same data as the installed app.
@MainActor
enum Snapshot {
    static func run(model: ZoneModel) {
        guard let directory = ProcessInfo.processInfo.environment["FOKUS_SNAPSHOT"] else { return }
        Task { @MainActor in
            @MainActor func capture(_ name: String) async {
                try? await Task.sleep(for: .seconds(1.5))
                guard let view = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 500 })?.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(directory)/\(name).png"))
            }
            try? await Task.sleep(for: .seconds(3))
            if let chrome = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").first {
                let page = await model.browsers.activePage(of: chrome, withTitle: true)
                let host = page.map { "\($0.host) | \($0.title ?? "-")" } ?? "nil"
                try? host.write(toFile: "\(directory)/host.txt", atomically: true, encoding: .utf8)
            }
            await capture("dashboard")
            model.page = .report
            await capture("report")
            model.insights.weekOffset = -1
            await capture("report-vorwoche")
            model.insights.weekOffset = 0
            model.quickMinutes = 45
            for page in [ZoneModel.Page.focus, .unlock, .lists, .schedules, .categories] { model.page = page; await capture(page.rawValue) }
            model.page = .assistant
            await capture("assistent-leer")
            if let question = ProcessInfo.processInfo.environment["FOKUS_ASK"] {
                model.assistant.send(question)
                for _ in 0..<120 where model.assistant.running { try? await Task.sleep(for: .seconds(1)) }
                await capture("assistent-antwort")
            }
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 500 }) {
                window.setContentSize(NSSize(width: window.frame.width, height: 1500))
                model.page = .categories
                await capture("kategorien-lang")
            }
            exit(0)
        }
    }
}
