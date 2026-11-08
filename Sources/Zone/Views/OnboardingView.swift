import AppKit
import SwiftUI
import ZoneCore

/// First launch: walks through the browser permission, a first block list and the login item,
/// so the app works without reading any instructions.
struct OnboardingView: View {
    @Bindable var model: ZoneModel
    private var step: Int {
        get { model.onboardingStep }
        nonmutating set { model.onboardingStep = newValue }
    }
    @State private var domains: [String] = []
    @State private var picked: Set<String> = []
    @State private var custom = ""
    @State private var useSchedule = false
    @State private var startAtLogin = true

    private let steps = 4

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0..<steps, id: \.self) { index in
                    Capsule().fill(index <= step ? Arc.ink : Arc.track).frame(height: 4)
                }
            }.frame(width: 220).padding(.top, 44)

            Group {
                switch step {
                case 0: welcome
                case 1: browsers
                case 2: blockList
                default: finish
                }
            }
            .frame(maxWidth: 520)
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 40)

            HStack {
                if step > 0 {
                    Button(L("Zurück", "Back")) { step -= 1 }.buttonStyle(ArcButtonStyle(kind: .quiet))
                }
                Spacer()
                if step < steps - 1 {
                    Button(nextTitle) { step += 1 }.buttonStyle(ArcButtonStyle(kind: .primary))
                        .keyboardShortcut(.defaultAction)
                        .disabled(step == 0 && !Autostart.isInstalledLocation)
                } else {
                    Button(L("Fokus starten", "Start Fokus")) { complete() }.buttonStyle(ArcButtonStyle(kind: .primary))
                        .keyboardShortcut(.defaultAction)
                }
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 40).padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack(alignment: .top) {
                Arc.background
                RadialGradient(colors: [Arc.glowPage, .clear], center: .top, startRadius: 0, endRadius: 520).frame(height: 420)
            }.ignoresSafeArea()
        }
        .onAppear(perform: loadList)
    }

    private var nextTitle: String {
        if step == 1 && !model.browsers.hasConnectedBrowser { return L("Später", "Later") }
        return L("Weiter", "Continue")
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            ZoneMark().frame(width: 44, height: 44)
            Text(L("Willkommen bei Fokus", "Welcome to Fokus")).font(.system(size: 30, weight: .semibold)).tracking(-1)
                .foregroundStyle(Arc.ink)
            VStack(alignment: .leading, spacing: 12) {
                point("hand.raised", L("Sperrt ablenkende Websites in deinem Browser, ohne Erweiterung.", "Blocks distracting websites in your browser, no extension needed."))
                point("lock.open", L("Entsperren geht, aber nur mit Wartezeit und für ein paar Minuten.", "You can unlock, but only after a wait and for a few minutes."))
                point("chart.bar", L("Zeigt dir, wohin deine Zeit am Mac geht.", "Shows where your time on the Mac goes."))
                point("lock.shield", L("Alles bleibt auf diesem Mac. Kein Konto, keine Cloud.", "Everything stays on this Mac. No account, no cloud."))
            }
            if !Autostart.isInstalledLocation {
                VStack(alignment: .leading, spacing: 10) {
                    Label(L("Fokus läuft noch aus dem Download", "Fokus is still running from the download"), systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Arc.amber)
                    Text(L("Zieh Fokus in den Ordner Programme und öffne es dort. Sonst klappen Updates und der Autostart nicht.", "Drag Fokus into the Applications folder and open it from there. Otherwise updates and autostart won’t work."))
                        .font(.system(size: 12.5)).foregroundStyle(Arc.secondary).fixedSize(horizontal: false, vertical: true)
                    Button(L("Programme-Ordner öffnen und beenden", "Open Applications and Quit")) {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
                        exit(0)
                    }.buttonStyle(ArcButtonStyle())
                }.arcCard(padding: 14)
            }
        }
    }

    private var browsers: some View {
        VStack(alignment: .leading, spacing: 16) {
            title(L("Browser verbinden", "Connect your browser"),
                  L("Klick auf Verbinden. macOS fragt dann, ob Fokus den Browser steuern darf. Dort auf OK klicken.", "Click Connect. macOS will ask whether Fokus may control the browser. Click OK there."))
            VStack(spacing: 0) {
                ForEach(Array(model.browsers.installed.enumerated()), id: \.element.id) { index, browser in
                    if index > 0 { Rectangle().fill(Arc.divider).frame(height: 1) }
                    BrowserPermissionRow(browser: browser, blocker: model.browsers).padding(.vertical, 10)
                }
                if model.browsers.installed.isEmpty {
                    Text(L("Kein unterstützter Browser gefunden. Fokus kann trotzdem Zeit erfassen und Apps sperren.", "No supported browser found. Fokus can still track time and block apps."))
                        .font(.system(size: 12.5)).foregroundStyle(Arc.secondary)
                }
            }.arcCard(padding: 14)
            Text(L("Fokus liest nur die Adresse des aktiven Tabs, nie den Seiteninhalt. Du kannst das später unter Einstellungen → Websites ändern.", "Fokus only reads the address of the active tab, never the page content. You can change this later in Settings → Websites."))
                .font(.system(size: 12)).foregroundStyle(Arc.tertiary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var blockList: some View {
        VStack(alignment: .leading, spacing: 16) {
            title(L("Was soll gesperrt werden?", "What should be blocked?"),
                  L("Das ist deine erste Sperrliste. Sie gilt erst, wenn du eine Fokus-Sitzung startest.", "This is your first block list. It only applies once you start a focus session."))
            VStack(alignment: .leading, spacing: 12) {
                FlowLayout(spacing: 6) {
                    ForEach(domains, id: \.self) { domain in
                        let on = picked.contains(domain)
                        Button { if on { picked.remove(domain) } else { picked.insert(domain) } } label: {
                            Label(domain, systemImage: on ? "checkmark" : "plus")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(on ? Arc.onInk : Arc.ink)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(on ? Arc.ink : Arc.muted, in: Capsule())
                                .contentShape(Capsule())
                        }.buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField(L("Weitere Seite, z. B. netflix.com", "Another site, e.g. netflix.com"), text: $custom)
                        .textFieldStyle(.roundedBorder).onSubmit(addCustom)
                    Button(L("Hinzufügen", "Add"), action: addCustom).buttonStyle(ArcButtonStyle()).disabled(cleaned(custom) == nil)
                }
            }.arcCard(padding: 14)
            Toggle(isOn: $useSchedule) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Automatisch Mo bis Fr, 9 bis 17 Uhr sperren", "Block automatically Mon to Fri, 9 to 5"))
                    Text(L("Lässt sich unter Zeitpläne jederzeit ändern.", "You can change this anytime under Schedules."))
                        .font(.caption).foregroundStyle(Arc.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .disabled(!model.browsers.hasConnectedBrowser)
            .arcCard(padding: 14)
            if !model.browsers.hasConnectedBrowser {
                Text(L("Für den Zeitplan erst einen Browser verbinden.", "Connect a browser first to use the schedule."))
                    .font(.caption).foregroundStyle(Arc.tertiary)
            }
        }
    }

    private var finish: some View {
        VStack(alignment: .leading, spacing: 16) {
            title(L("Fast fertig", "Almost done"),
                  L("Fokus sitzt danach oben in der Menüleiste. Von dort startest du Sitzungen und öffnest dieses Fenster.", "Fokus then lives in the menu bar. Start sessions and open this window from there."))
            Toggle(isOn: $startAtLogin) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Beim Anmelden starten", "Start at login"))
                    Text(L("Startet Fokus nach einem Absturz von selbst neu, damit Sperren nicht still ausfallen. macOS zeigt dazu kurz eine Meldung zu Hintergrundobjekten.", "Restarts Fokus after a crash so blocking never silently stops. macOS briefly shows a note about background items."))
                        .font(.caption).foregroundStyle(Arc.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }.toggleStyle(.switch).arcCard(padding: 14)
            VStack(alignment: .leading, spacing: 10) {
                point("arrow.down.circle", L("Neue Versionen meldet Fokus selbst. Ein Klick installiert sie.", "Fokus tells you about new versions. One click installs them."))
                point("lock.open", L("Brauchst du eine gesperrte Seite kurz, öffne Fokus → Entsperren.", "Need a blocked site for a moment? Open Fokus → Unlock."))
            }
        }
    }

    // MARK: Pieces

    private func title(_ text: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text).font(.system(size: 26, weight: .semibold)).tracking(-0.8).foregroundStyle(Arc.ink)
            Text(detail).font(.system(size: 13)).foregroundStyle(Arc.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func point(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon).foregroundStyle(Arc.work).frame(width: 18)
            Text(text).font(.system(size: 13.5)).foregroundStyle(Arc.ink).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Data

    private func loadList() {
        let list = model.document.blockLists.first
        domains = list?.domains ?? []
        picked = Set(domains)
    }

    private func cleaned(_ text: String) -> String? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["https://", "http://", "www."] where value.hasPrefix(prefix) { value.removeFirst(prefix.count) }
        value = String(value.split(separator: "/").first ?? "")
        return value.contains(".") && !value.contains(" ") ? value : nil
    }

    private func addCustom() {
        guard let domain = cleaned(custom) else { return }
        if !domains.contains(domain) { domains.append(domain) }
        picked.insert(domain)
        custom = ""
    }

    private func complete() {
        if var list = model.document.blockLists.first {
            list.domains = domains.filter(picked.contains)
            model.saveList(list)
            if useSchedule, let schedule = model.document.schedules.first(where: { $0.blockListID == list.id }), !list.isEmpty {
                var next = schedule
                next.isEnabled = true
                _ = model.saveSchedule(next)
            }
        }
        UserDefaults.standard.set(true, forKey: ZoneModel.onboardingKey)
        model.showOnboarding = false
        if startAtLogin && !Autostart.isInstalled && Autostart.isInstalledLocation {
            do { try Autostart.install() }
            catch { model.errorMessage = L("Autostart ließ sich nicht einrichten: \(error.localizedDescription)", "Could not set up autostart: \(error.localizedDescription)") }
        }
    }
}
