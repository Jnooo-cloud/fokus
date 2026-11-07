import AppKit
import SwiftUI
import ZoneCore

struct SettingsView: View {
    @Bindable var model: ZoneModel

    var body: some View {
        TabView(selection: $model.settingsPane) {
            GeneralSettings(model: model)
                .tabItem { Label("Allgemein", systemImage: "gearshape") }.tag(ZoneModel.SettingsPane.general)
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
            Section("Sitzungen") {
                LabeledContent("Flexibel", value: "Jederzeit beendbar")
                LabeledContent("Gesperrt", value: "Läuft bis zum Ende")
                LabeledContent("Geplant", value: "Läuft immer bis zum Ende")
                Text("Fokus muss laufen, um Browser zu steuern. Nach einem Absturz oder Sofort-Beenden startet es von selbst neu.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Design") {
                Picker("Erscheinungsbild", selection: $theme) {
                    ForEach(ThemeChoice.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
            }
            Section("Zeiterfassung") {
                Toggle("Seitentitel speichern", isOn: $trackTitles)
                Text("Aus: Fokus speichert nur die Domain, etwa youtube.com. An: zusätzlich den Tab-Titel, damit du einzelne Seiten siehst. Inkognito-Fenster nie.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Gespeicherte Seitentitel löschen", role: .destructive) { confirmWipe = true }
            }
            .confirmationDialog("Alle gespeicherten Seitentitel löschen?", isPresented: $confirmWipe, titleVisibility: .visible) {
                Button("Titel löschen", role: .destructive) { model.insights.removeTitles() }
            } message: { Text("Die Zeiten pro Domain und App bleiben erhalten. Das lässt sich nicht rückgängig machen.") }
            Section("Entsperren") {
                Stepper("Limit pro Tag: \(settings.dailyLimit)", value: binding(\.dailyLimit), in: 1...20)
                Stepper("Erste Wartezeit: \(settings.baseDelay) Sek", value: binding(\.baseDelay), in: 10...120, step: 10)
                Stepper("Zuschlag je Entsperrung: \(settings.stepDelay) Sek", value: binding(\.stepDelay), in: 0...60, step: 10)
                Toggle("Grund verlangen", isOn: binding(\.requiresReason))
                if model.isHard { Text("Während Hard Mode gesperrt.").font(.caption).foregroundStyle(.secondary) }
            }.disabled(model.isHard)
            Section("Datenschutz") {
                Text("Listen und Zeiten bleiben auf diesem Mac. Kein Konto, keine Analyse, keine Cloud.")
                    .foregroundStyle(.secondary)
                Link("Basiert auf Zone (MIT)", destination: URL(string: "https://github.com/morajabi/zone")!)
            }
        }.formStyle(.grouped)
    }
}

private struct BrowserSettings: View {
    let model: ZoneModel
    var body: some View {
        Section {
            Text("Fokus leitet gesperrte Tabs auf eine lokale Seite um. Verbinde jeden Browser, den du nutzt.")
                .foregroundStyle(.secondary)
            ForEach(model.browsers.installed) { browser in
                BrowserPermissionRow(browser: browser, blocker: model.browsers)
            }
            if model.browsers.installed.isEmpty {
                Text("Keine unterstützten Browser gefunden.").foregroundStyle(.secondary)
            }
            Button("Browser neu prüfen") { model.browsers.refreshInstalled() }
        } header: { Text("Browser") } footer: {
            Text("Unterstützt Safari, Chrome, Dia, Arc, Brave, Edge, Opera und Helium. Andere Browser lassen sich als App sperren.")
        }
        Section {
            Text("Eine Seite kann kurz aufblitzen, bevor sie umgeleitet wird. Nach dem Entsperren kommst du mit Zurück wieder hin.")
            Text("Fokus liest Tab-Adressen und speichert davon nur die Domain, summiert pro Stunde. Inkognito-Fenster zählen als Browserzeit. Seiteninhalte liest es nicht.")
        }.font(.caption).foregroundStyle(.secondary)
    }
}

private struct BrowserPermissionRow: View {
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
                Button("Einstellungen öffnen…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                }.accessibilityLabel("Open Automation settings for \(browser.name)")
            } else {
                Button("Verbinden…") { blocker.connect(browser) }.accessibilityLabel("Connect \(browser.name)")
            }
        }
    }
}
