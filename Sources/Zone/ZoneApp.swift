import AppKit
import SwiftUI
import ZoneCore

@main
struct ZoneApp: App {
    @NSApplicationDelegateAdaptor(ZoneAppDelegate.self) private var delegate
    @State private var model = ZoneModel()

    var body: some Scene {
        Window("Fokus", id: "main") {
            MainView(model: model)
                .onAppear { delegate.model = model; Snapshot.run(model: model) }
        }
        .defaultSize(width: 920, height: 680)
        .windowStyle(.hiddenTitleBar)
        .defaultLaunchBehavior(.presented)
        .windowResizability(.contentMinSize)
        .commands {
            ZoneCommands(model: model)
            SidebarCommands()
            CommandGroup(replacing: .appTermination) {
                Button(L("Fokus beenden", "Quit Fokus")) { model.quit() }.keyboardShortcut("q")
                    .disabled(model.hasStrictSession)
            }
        }

        Settings {
            SettingsView(model: model)
                .onAppear { delegate.model = model }
                .modifier(ThemedWindow())
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarView(model: model)
                .modifier(ThemedWindow())
                .onAppear { delegate.model = model }
        } label: {
            if model.menuTitle.isEmpty {
                Image(nsImage: MenuBarIcon.image(for: model.menuState))
            } else {
                Label {
                    Text(model.menuTitle).monospacedDigit()
                } icon: {
                    Image(nsImage: MenuBarIcon.image(for: model.menuState))
                }.labelStyle(.titleAndIcon)
            }
        }
        .menuBarExtraStyle(.window)
    }
}

private struct ZoneCommands: Commands {
    let model: ZoneModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(L("Neue Sperrliste…", "New Block List…")) { openMain(); model.newList() }
                .keyboardShortcut("n")
            Button(L("Neuer Zeitplan…", "New Schedule…")) { openMain(); model.newSchedule() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(model.availableLists.isEmpty)
        }
        CommandMenu("Fokus") {
            Button(L("Neue Sitzung", "New Session")) { model.page = .focus; openMain() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Divider()
            Button(L("Sperrlisten", "Block Lists")) { model.page = .lists; openMain() }
                .keyboardShortcut("2", modifiers: .command)
            Button(L("Zeitpläne", "Schedules")) { model.page = .schedules; openMain() }
                .keyboardShortcut("3", modifiers: .command)
        }
        CommandGroup(replacing: .help) {
            // Fokus is a fork of Zone; its project page explains the shared blocking basics.
            Link(L("Zone, die Basis von Fokus", "Zone, the base of Fokus"), destination: URL(string: "https://github.com/morajabi/zone")!)
        }
    }

    private func openMain() { openWindow(id: "main"); NSApp.activate() }
}

@MainActor
final class ZoneAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: ZoneModel?
    func applicationWillTerminate(_ notification: Notification) { model?.tracker.flush() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Never hold up logout, restart, or shutdown. Sessions are saved and resume at next launch.
        let reason = NSAppleEventManager.shared().currentAppleEvent?
            .attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason))?.enumCodeValue
        let systemReasons = [kAELogOut, kAEReallyLogOut, kAEShowRestartDialog, kAEShowShutdownDialog, kAERestart, kAEShutDown]
        if let reason, systemReasons.map({ OSType($0) }).contains(reason) { return .terminateNow }
        return model?.hasStrictSession == true ? .terminateCancel : .terminateNow
    }
}
