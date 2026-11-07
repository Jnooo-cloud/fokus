import SwiftUI
import ZoneCore

/// One place to start a session, see what it blocks, and get out of it the intended way.
struct FocusView: View {
    @Bindable var model: ZoneModel
    @State private var showAnother = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: L("Fokus", "Focus"), subtitle: model.activeSessions.isEmpty
                           ? L("Eine Sitzung sperrt deine Liste für eine feste Zeit. Danach ist alles wieder offen.", "A session blocks your list for a set time. After that everything is open again.")
                           : L("Läuft gerade. Gesperrtes leitet Chrome auf eine Fokus-Seite um.", "Running. Blocked pages redirect to a Fokus page."))
                BlockingNotice(model: model)
                ForEach(model.activeSessions) { session in
                    RunningSessionCard(session: session, model: model)
                }
                if model.availableLists.isEmpty {
                    FirstListPrompt(model: model).frame(maxWidth: .infinity).padding(.vertical, 40)
                } else if model.activeSessions.isEmpty {
                    StartSessionCard(model: model)
                } else if !model.isHard {
                    DisclosureGroup(L("Weitere Sitzung dazu starten", "Start another session"), isExpanded: $showAnother) {
                        StartSessionCard(model: model, embedded: true).padding(.top, 10)
                    }.font(.system(size: 13, weight: .medium)).arcCard()
                }
                if let next = model.nextScheduledSession { NextScheduleRow(model: model, name: next.name, start: next.start) }
            }
            .padding(.horizontal, 32).padding(.top, 44).padding(.bottom, 28)
            .frame(maxWidth: 600).frame(maxWidth: .infinity)
        }
    }
}

private enum Strictness: String, CaseIterable, Identifiable {
    case flexible, locked, hard
    var id: Self { self }
    var title: String {
        switch self {
        case .flexible: L("Flexibel", "Flexible")
        case .locked: L("Durchziehen", "Commit")
        case .hard: "Hard Mode"
        }
    }
    var detail: String {
        switch self {
        case .flexible: L("Jederzeit beenden", "End anytime")
        case .locked: L("Kein Beenden, Entsperren geht", "No ending, unlocking allowed")
        case .hard: L("Kein Beenden, kein Entsperren", "No ending, no unlocking")
        }
    }
    var symbol: String {
        switch self {
        case .flexible: "leaf"
        case .locked: "lock"
        case .hard: "lock.fill"
        }
    }
}

private struct StartSessionCard: View {
    @Bindable var model: ZoneModel
    var embedded = false
    @State private var strictness = Strictness.flexible
    @State private var confirmApps = false
    @State private var custom = false
    private static let durations = [25, 50, 90, 120, 240]
    private static let customTag = -1

    private var list: BlockList? { model.selectedList }
    private var minutes: Int { model.quickMinutes }
    private var end: Date { model.now.addingTimeInterval(Double(minutes) * 60) }
    private var needsBrowser: Bool { list?.blocksWebsites == true && !model.websiteBlockingReady }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            step(1, L("Wie lange?", "How long?")) {
                VStack(alignment: .leading, spacing: 10) {
                    PillPicker(options: Self.durations.map { ($0, MenuFormat.duration($0)) } + [(Self.customTag, L("Eigene", "Custom"))],
                               selection: Binding(get: { custom ? Self.customTag : model.quickMinutes },
                                                  set: { value in
                                                      custom = value == Self.customTag
                                                      if !custom { model.quickMinutes = value }
                                                  }))
                    if custom { customDuration }
                }
            }
            step(2, L("Was wird gesperrt?", "What gets blocked?")) {
                VStack(alignment: .leading, spacing: 8) {
                    ChipRow(chips: model.availableLists.map { (Optional($0.id.uuidString), $0.name) },
                            selection: Binding(get: { model.selectedListID?.uuidString },
                                               set: { model.selectedListID = $0.flatMap(UUID.init(uuidString:)) }))
                    if let list {
                        Text(Self.contents(of: list)).font(.system(size: 12)).foregroundStyle(Arc.secondary).lineLimit(2)
                    }
                }
            }
            step(3, L("Wie streng?", "How strict?")) {
                HStack(spacing: 8) {
                    ForEach(Strictness.allCases) { option in
                        StrictnessTile(option: option, selected: strictness == option) { strictness = option }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(summary).font(.system(size: 13)).foregroundStyle(Arc.ink.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                if needsBrowser { BrowserSetupPrompt(model: model) }
                if strictness == .hard {
                    HoldToConfirm(title: L("2 Sek halten: Hard Mode bis \(end.formatted(date: .omitted, time: .shortened))", "Hold 2 s: Hard Mode until \(end.formatted(date: .omitted, time: .shortened))"), duration: 2,
                                  tint: AnyShapeStyle(Arc.distraction.opacity(0.55))) { start() }
                        .disabled(list == nil || needsBrowser || !validMinutes)
                } else {
                    Button(L("Fokus bis \(end.formatted(date: .omitted, time: .shortened)) starten", "Focus until \(end.formatted(date: .omitted, time: .shortened))")) {
                        if list?.apps.isEmpty == false { confirmApps = true } else { start() }
                    }
                    .buttonStyle(ArcButtonStyle(kind: .primary, wide: true))
                    .disabled(list == nil || needsBrowser || model.storageFailed || !validMinutes)
                }
            }
        }
        .modifier(OptionalCard(enabled: !embedded))
        .confirmationDialog(L("Gewählte Apps schließen und starten?", "Quit the selected apps and start?"), isPresented: $confirmApps, titleVisibility: .visible) {
            Button(L("Starten", "Start")) { start() }
        } message: { Text(L("Speichere vorher. Apps aus der Liste werden sofort geschlossen.", "Save first. Apps on the list close right away.")) }
        .onAppear { custom = !Self.durations.contains(model.quickMinutes) }
    }

    private var validMinutes: Bool { (1...1440).contains(minutes) }

    /// Either a number of minutes or an end time; both end up as minutes.
    private var customDuration: some View {
        HStack(spacing: 10) {
            TextField("45", text: $model.quickMinutesText)
                .textFieldStyle(.plain).font(.system(size: 15, weight: .semibold)).monospacedDigit()
                .multilineTextAlignment(.center).frame(width: 64).padding(.vertical, 8)
                .background(Arc.muted, in: RoundedRectangle(cornerRadius: Arc.controlRadius, style: .continuous))
            Text(L("Minuten", "minutes")).font(.system(size: 13)).foregroundStyle(Arc.secondary)
            Text(L("oder bis", "or until")).font(.system(size: 13)).foregroundStyle(Arc.tertiary).padding(.leading, 6)
            DatePicker(L("Bis", "Until"), selection: Binding(get: { end }, set: { date in
                // A time earlier than now means tomorrow.
                var target = date
                if target <= Date() { target = target.addingTimeInterval(86400) }
                model.quickMinutes = max(1, min(1440, Int((target.timeIntervalSince(Date()) / 60).rounded())))
            }), displayedComponents: .hourAndMinute).labelsHidden().fixedSize()
            Spacer()
            if !validMinutes { Text(L("1 bis 1.440 Min", "1 to 1,440 min")).font(.system(size: 11.5)).foregroundStyle(Arc.distraction) }
        }
    }

    private var summary: String {
        guard validMinutes else { return L("Gib eine Dauer zwischen 1 Minute und 24 Stunden ein.", "Enter a duration between 1 minute and 24 hours.") }
        guard let list else { return L("Wähle eine Liste.", "Choose a list.") }
        let what = list.blocksEverything ? L("alle Websites außer deinen Ausnahmen", "all websites except your exceptions") : Self.contents(of: list)
        let until = end.formatted(date: .omitted, time: .shortened)
        switch strictness {
        case .flexible: return L("Bis \(until) ist \(what) gesperrt. Du kannst jederzeit beenden oder kurz entsperren.", "Blocked until \(until): \(what). You can end anytime or unlock briefly.")
        case .locked: return L("Bis \(until) ist \(what) gesperrt. Beenden geht nicht, kurz entsperren schon.", "Blocked until \(until): \(what). You can’t end it, but you can unlock briefly.")
        case .hard: return L("Bis \(until) ist \(what) gesperrt. Kein Beenden, kein Entsperren. Nur ein Notausgang mit 5 Min Wartezeit.", "Blocked until \(until): \(what). No ending, no unlocking. Only an emergency exit after a 5 min wait.")
        }
    }

    private func start() {
        switch strictness {
        case .hard: model.startHard(minutes: minutes)
        case .flexible, .locked:
            model.quickOptions.mode = strictness == .locked ? .locked : .flexible
            model.startQuickSession()
        }
    }

    static func contents(of list: BlockList) -> String {
        let sites = list.blocksEverything ? [L("alle Websites", "all websites")] : list.domains
        let all = sites + list.apps.map(\.name)
        return all.count <= 4 ? all.joined(separator: ", ") : all.prefix(3).joined(separator: ", ") + L(" und \(all.count - 3) weitere", " and \(all.count - 3) more")
    }

    private func step<Content: View>(_ number: Int, _ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("\(number)").font(.system(size: 11, weight: .semibold)).foregroundStyle(Arc.onInk)
                    .frame(width: 18, height: 18).background(Arc.ink.opacity(0.8), in: Circle())
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            content()
        }
    }
}

private struct OptionalCard: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.arcCard(padding: 20) } else { content }
    }
}

private struct StrictnessTile: View {
    let option: Strictness
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: option.symbol).font(.system(size: 13))
                    .foregroundStyle(option == .hard ? Arc.distraction : Arc.ink)
                Text(option.title).font(.system(size: 12.5, weight: .semibold))
                Text(option.detail).font(.system(size: 11)).foregroundStyle(Arc.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(11).frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .background(selected ? Arc.muted : Arc.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? Arc.ink.opacity(0.55) : Arc.border, lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

private struct RunningSessionCard: View {
    let session: FocusSession
    let model: ZoneModel
    @State private var confirmEnd = false

    private var hard: Bool { model.isHard && model.document.hardMode?.sessionID == session.id }
    private var badge: (String, Color) {
        if hard { return ("Hard Mode", Arc.distraction) }
        if session.scheduleID != nil { return (L("Zeitplan", "Schedule"), Arc.work) }
        return session.options.mode == .locked ? (L("Durchziehen", "Commit"), Arc.work) : (L("Flexibel", "Flexible"), Arc.green)
    }
    private var fraction: Double {
        let total = session.endsAt.timeIntervalSince(session.startsAt)
        return total > 0 ? max(0, min(1, session.endsAt.timeIntervalSince(model.now) / total)) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(session.name).font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(badge.0).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(badge.1)
                    .padding(.horizontal, 9).padding(.vertical, 4).background(badge.1.opacity(0.14), in: Capsule())
            }
            HStack(spacing: 22) {
                CountdownRing(fraction: fraction, label: Countdown.text(until: session.endsAt, now: model.now), size: 128)
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Gesperrt bis \(session.endsAt.formatted(date: .omitted, time: .shortened))", "Blocked until \(session.endsAt.formatted(date: .omitted, time: .shortened))")).font(.system(size: 17, weight: .semibold))
                    Text(StartSessionCard.contents(of: session.blockList)).font(.system(size: 12.5)).foregroundStyle(Arc.secondary).lineLimit(3)
                    if !model.activeUnlocks.isEmpty {
                        Text(L("Gerade frei: ", "Free right now: ") + model.activeUnlocks.map { $0.domain ?? L("alles", "everything") }.joined(separator: ", "))
                            .font(.system(size: 12)).foregroundStyle(Arc.green)
                    }
                }
            }
            if hard {
                HardModeCard(model: model).padding(.horizontal, -18).padding(.bottom, -18)
            } else {
                HStack(spacing: 8) {
                    Button(L("Kurz entsperren…", "Unlock briefly…")) { model.page = .unlock }.buttonStyle(ArcButtonStyle(kind: .secondary, wide: true))
                        .disabled(model.isHard)
                    if !session.isStrict {
                        Button(L("Beenden", "End")) { confirmEnd = true }.buttonStyle(ArcButtonStyle(kind: .quiet))
                    }
                }
                Text(session.isStrict ? L("Diese Sitzung läuft bis zum Ende. Kurz entsperren geht mit Wartezeit.", "This session runs to the end. Brief unlocks come with a wait.")
                                      : L("Beenden gibt sofort alles frei. Kurz entsperren gibt nur eine Seite für ein paar Minuten frei.", "Ending frees everything at once. A brief unlock frees one site for a few minutes."))
                    .font(.system(size: 11.5)).foregroundStyle(Arc.tertiary)
            }
        }
        .arcCard(padding: 20)
        .confirmationDialog(L("Sitzung beenden?", "End session?"), isPresented: $confirmEnd, titleVisibility: .visible) {
            Button(L("Beenden", "End"), role: .destructive) { model.stop(session) }
        } message: { Text(L("Alles aus dieser Sitzung ist dann sofort wieder offen.", "Everything in this session opens up again right away.")) }
    }
}

private struct NextScheduleRow: View {
    let model: ZoneModel
    let name: String
    let start: Date

    var body: some View {
        Button { model.page = .schedules } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar").foregroundStyle(Arc.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Nächster Zeitplan: \(name)", "Next schedule: \(name)")).font(.system(size: 13, weight: .medium))
                    Text(L("Startet von selbst \(start.formatted(.dateTime.weekday(.wide).hour().minute().locale(AppLanguage.locale)))", "Starts on its own \(start.formatted(.dateTime.weekday(.wide).hour().minute().locale(AppLanguage.locale)))"))
                        .font(.system(size: 12)).foregroundStyle(Arc.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Arc.tertiary)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).arcCard(padding: 14)
    }
}

struct FirstListPrompt: View {
    let model: ZoneModel
    var compact = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "hand.raised").font(.system(size: compact ? 28 : 40, weight: .light))
                .foregroundStyle(.secondary).accessibilityHidden(true)
            Text(L("Wähle, was gesperrt wird", "Choose what to block")).font(compact ? .headline : .title2.weight(.semibold))
            Text(L("Trag Websites und Apps in eine Sperrliste ein und starte eine Sitzung, wenn du dich konzentrieren willst.", "Put websites and apps on a block list, then start a session whenever you want to focus."))
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(L("Sperrliste anlegen…", "Create a Block List…"), systemImage: "plus") {
                openWindow.openMain()
                model.newList()
            }.buttonStyle(.borderedProminent).padding(.top, 4)
        }.frame(maxWidth: 380)
    }
}
