import AppKit
import SwiftUI
import ZoneCore

struct SettingsView: View {
    @Bindable var model: ZoneModel

    var body: some View {
        TabView(selection: $model.settingsPane) {
            GeneralSettings(model: model)
                .tabItem { Label(L("Allgemein", "General"), systemImage: "gearshape") }.tag(ZoneModel.SettingsPane.general)
            Form { BrowserSettings(model: model) }.formStyle(.grouped)
                .tabItem { Label("Websites", systemImage: "globe") }.tag(ZoneModel.SettingsPane.websites)
        }
        .frame(width: 560, height: 540)
        .modifier(ErrorPresenter(model: model))
    }
}

private struct GeneralSettings: View {
    let model: ZoneModel
    @AppStorage("theme") private var theme = ThemeChoice.dark
    @AppStorage(AppLanguage.defaultsKey) private var language = AppLanguage.system
    @AppStorage(UsageTracker.titlesKey) private var trackTitles = false
    @State private var confirmWipe = false
    private var settings: UnlockSettings { model.document.unlockSettings }

    private func binding<Value>(_ path: WritableKeyPath<UnlockSettings, Value>) -> Binding<Value> {
        Binding(get: { model.document.unlockSettings[keyPath: path] }, set: { value in
            var next = model.document.unlockSettings
            next[keyPath: path] = value
            model.updateUnlockSettings(next)
        })
    }

    var body: some View {
        Form {
            Section(L("Sitzungen", "Sessions")) {
                LabeledContent(L("Flexibel", "Flexible"), value: L("Jederzeit beendbar", "End anytime"))
                LabeledContent(L("Gesperrt", "Locked"), value: L("Läuft bis zum Ende", "Runs to the end"))
                LabeledContent(L("Geplant", "Scheduled"), value: L("Läuft immer bis zum Ende", "Always runs to the end"))
                Text(L("Fokus muss laufen, um Browser zu steuern. Nach einem Absturz oder Sofort-Beenden startet es von selbst neu.", "Fokus must run to control browsers. After a crash or force quit it restarts on its own."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Design", "Appearance")) {
                Picker(L("Erscheinungsbild", "Appearance"), selection: $theme) {
                    ForEach(ThemeChoice.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
            }
            Section(L("Sprache", "Language")) {
                Picker(L("Sprache", "Language"), selection: $language) {
                    ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                }
            }
            Section(L("Zeiterfassung", "Time Tracking")) {
                Toggle(L("Seitentitel speichern", "Save page titles"), isOn: $trackTitles)
                Text(L("Aus: Fokus speichert nur die Domain, etwa youtube.com. An: zusätzlich den Tab-Titel, damit du einzelne Seiten siehst. Inkognito-Fenster nie.", "Off: Fokus saves only the domain, like youtube.com. On: also the tab title, so you see single pages. Never for incognito windows."))
                    .font(.caption).foregroundStyle(.secondary)
                Button(L("Gespeicherte Seitentitel löschen", "Delete Saved Page Titles"), role: .destructive) { confirmWipe = true }
            }
            .confirmationDialog(L("Alle gespeicherten Seitentitel löschen?", "Delete all saved page titles?"), isPresented: $confirmWipe, titleVisibility: .visible) {
                Button(L("Titel löschen", "Delete Titles"), role: .destructive) { model.insights.removeTitles() }
            } message: { Text(L("Die Zeiten pro Domain und App bleiben erhalten. Das lässt sich nicht rückgängig machen.", "Time per domain and app stays. This can’t be undone.")) }
            Section(L("Entsperren", "Unlock")) {
                Stepper(L("Limit pro Tag: \(settings.dailyLimit)", "Daily limit: \(settings.dailyLimit)"), value: binding(\.dailyLimit), in: 1...20)
                Stepper(L("Erste Wartezeit: \(settings.baseDelay) Sek", "First wait: \(settings.baseDelay) s"), value: binding(\.baseDelay), in: 10...120, step: 10)
                Stepper(L("Zuschlag je Entsperrung: \(settings.stepDelay) Sek", "Added per unlock: \(settings.stepDelay) s"), value: binding(\.stepDelay), in: 0...60, step: 10)
                Toggle(L("Grund verlangen", "Ask for a reason"), isOn: binding(\.requiresReason))
                if model.isHard { Text(L("Während Hard Mode gesperrt.", "Locked during Hard Mode.")).font(.caption).foregroundStyle(.secondary) }
            }.disabled(model.isHard)
            UpdateSettings(model: model)
            Section(L("Datenschutz", "Privacy")) {
                Text(L("Listen und Zeiten bleiben auf diesem Mac. Kein Konto, keine Analyse, keine Cloud.", "Lists and times stay on this Mac. No account, no analytics, no cloud."))
                    .foregroundStyle(.secondary)
                Link(L("Basiert auf Zone (MIT)", "Based on Zone (MIT)"), destination: URL(string: "https://github.com/morajabi/zone")!)
            }
        }.formStyle(.grouped)
    }
}

private struct BrowserSettings: View {
    let model: ZoneModel
    var body: some View {
        Section {
            Text(L("Fokus leitet gesperrte Tabs auf eine lokale Seite um. Verbinde jeden Browser, den du nutzt.", "Fokus redirects blocked tabs to a local page. Connect every browser you use."))
                .foregroundStyle(.secondary)
            ForEach(model.browsers.installed) { browser in
                BrowserPermissionRow(browser: browser, blocker: model.browsers)
            }
            if model.browsers.installed.isEmpty {
                Text(L("Keine unterstützten Browser gefunden.", "No supported browsers found.")).foregroundStyle(.secondary)
            }
            Button(L("Browser neu prüfen", "Refresh Browsers")) { model.browsers.refreshInstalled() }
        } header: { Text(L("Browser", "Browsers")) } footer: {
            Text(L("Unterstützt Safari, Chrome, Dia, Arc, Brave, Edge, Opera und Helium. Andere Browser lassen sich als App sperren.", "Supports Safari, Chrome, Dia, Arc, Brave, Edge, Opera and Helium. Other browsers can be blocked as apps."))
        }
        Section {
            Text(L("Eine Seite kann kurz aufblitzen, bevor sie umgeleitet wird. Nach dem Entsperren kommst du mit Zurück wieder hin.", "A page may flash briefly before it redirects. After unlocking, use Back to return to it."))
            Text(L("Fokus liest Tab-Adressen und speichert davon nur die Domain, summiert pro Stunde. Inkognito-Fenster zählen als Browserzeit. Seiteninhalte liest es nicht.", "Fokus reads tab addresses and keeps only the domain, summed per hour. Incognito windows count as browser time. It never reads page content."))
        }.font(.caption).foregroundStyle(.secondary)
    }
}

struct BrowserPermissionRow: View {
    let browser: SupportedBrowser
    let blocker: BrowserBlocker
    private var access: BrowserAccess { blocker.access[browser.id] ?? .notRunning }

    var body: some View {
        HStack(spacing: 12) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.id) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 28, height: 28)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(browser.name)
                Text(access.description).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if access == .checking {
                ProgressView().controlSize(.small).accessibilityLabel("Connecting \(browser.name)")
            } else if access == .ready || access == .closed {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("\(browser.name) connected")
            } else if access == .denied {
                Button(L("Einstellungen öffnen…", "Open Settings…")) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                }.accessibilityLabel("Open Automation settings for \(browser.name)")
            } else {
                Button(L("Verbinden…", "Connect…")) { blocker.connect(browser) }.accessibilityLabel("Connect \(browser.name)")
            }
        }
    }
}

private struct UpdateSettings: View {
    let model: ZoneModel
    @State private var autostart = Autostart.isInstalled
    private var updater: Updater { model.updater }

    var body: some View {
        Section(L("App", "App")) {
            Toggle(L("Beim Anmelden starten", "Start at login"), isOn: $autostart)
                .onChange(of: autostart) { _, on in
                    if on { do { try Autostart.install() } catch { model.errorMessage = error.localizedDescription; autostart = false } }
                    else { Autostart.remove() }
                }
                .disabled(!Autostart.isInstalledLocation)
            LabeledContent(L("Version", "Version"), value: updater.current)
            if updater.isEnabled {
                HStack {
                    Text(statusText).foregroundStyle(.secondary)
                    Spacer()
                    if updater.latest != nil && updater.state != .downloading && updater.state != .installing {
                        Button(L("Jetzt aktualisieren", "Update Now")) { model.installUpdate() }
                    } else {
                        Button(L("Nach Updates suchen", "Check for Updates")) { Task { await updater.check() } }
                            .disabled(updater.state == .checking || updater.state == .downloading || updater.state == .installing)
                    }
                }
            } else {
                Text(L("Eigener Build: Updates kommen über scripts/install-local.sh.", "Own build: update with scripts/install-local.sh."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var statusText: String {
        switch updater.state {
        case .idle: L("Noch nicht geprüft", "Not checked yet")
        case .checking: L("Prüfe…", "Checking…")
        case .upToDate: L("Aktuell", "Up to date")
        case .available: L("Version \(updater.latest?.version ?? "") verfügbar", "Version \(updater.latest?.version ?? "") available")
        case .downloading: L("Lade herunter…", "Downloading…")
        case .installing: L("Installiere…", "Installing…")
        case .failed(let message): message
        }
    }
}
