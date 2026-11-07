import SwiftUI
import ZoneCore

/// One place to start a session, see what it blocks, and get out of it the intended way.
struct FocusView: View {
    @Bindable var model: ZoneModel
    @State private var showAnother = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Fokus", subtitle: model.activeSessions.isEmpty
                           ? "Eine Sitzung sperrt deine Liste für eine feste Zeit. Danach ist alles wieder offen."
                           : "Läuft gerade. Gesperrtes leitet Chrome auf eine Fokus-Seite um.")
                BlockingNotice(model: model)
                ForEach(model.activeSessions) { session in
                    RunningSessionCard(session: session, model: model)
                }
                if model.availableLists.isEmpty {
                    FirstListPrompt(model: model).frame(maxWidth: .infinity).padding(.vertical, 40)
                } else if model.activeSessions.isEmpty {
                    StartSessionCard(model: model)
                } else if !model.isHard {
                    DisclosureGroup("Weitere Sitzung dazu starten", isExpanded: $showAnother) {
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
        case .flexible: "Flexibel"
        case .locked: "Durchziehen"
        case .hard: "Hard Mode"
        }
    }
    var detail: String {
        switch self {
        case .flexible: "Jederzeit beenden"
        case .locked: "Kein Beenden, Entsperren geht"
        case .hard: "Kein Beenden, kein Entsperren"
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
            step(1, "Wie lange?") {
                VStack(alignment: .leading, spacing: 10) {
                    PillPicker(options: Self.durations.map { ($0, MenuFormat.duration($0)) } + [(Self.customTag, "Eigene")],
                               selection: Binding(get: { custom ? Self.customTag : model.quickMinutes },
                                                  set: { value in
                                                      custom = value == Self.customTag
                                                      if !custom { model.quickMinutes = value }
                                                  }))
                    if custom { customDuration }
                }
            }
            step(2, "Was wird gesperrt?") {
                VStack(alignment: .leading, spacing: 8) {
                    ChipRow(chips: model.availableLists.map { (Optional($0.id.uuidString), $0.name) },
                            selection: Binding(get: { model.selectedListID?.uuidString },
                                               set: { model.selectedListID = $0.flatMap(UUID.init(uuidString:)) }))
                    if let list {
                        Text(Self.contents(of: list)).font(.system(size: 12)).foregroundStyle(Arc.secondary).lineLimit(2)
                    }
                }
            }
            step(3, "Wie streng?") {
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
                    HoldToConfirm(title: "2 Sek halten: Hard Mode bis \(end.formatted(date: .omitted, time: .shortened))", duration: 2,
                                  tint: AnyShapeStyle(Arc.distraction.opacity(0.55))) { start() }
                        .disabled(list == nil || needsBrowser || !validMinutes)
                } else {
                    Button("Fokus bis \(end.formatted(date: .omitted, time: .shortened)) starten") {
                        if list?.apps.isEmpty == false { confirmApps = true } else { start() }
                    }
                    .buttonStyle(ArcButtonStyle(kind: .primary, wide: true))
                    .disabled(list == nil || needsBrowser || model.storageFailed || !validMinutes)
                }
            }
        }
        .modifier(OptionalCard(enabled: !embedded))
        .confirmationDialog("Gewählte Apps schließen und starten?", isPresented: $confirmApps, titleVisibility: .visible) {
            Button("Starten") { start() }
        } message: { Text("Speichere vorher. Apps aus der Liste werden sofort geschlossen.") }
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
            Text("Minuten").font(.system(size: 13)).foregroundStyle(Arc.secondary)
            Text("oder bis").font(.system(size: 13)).foregroundStyle(Arc.tertiary).padding(.leading, 6)
            DatePicker("Bis", selection: Binding(get: { end }, set: { date in
                // A time earlier than now means tomorrow.
                var target = date
                if target <= Date() { target = target.addingTimeInterval(86400) }
                model.quickMinutes = max(1, min(1440, Int((target.timeIntervalSince(Date()) / 60).rounded())))
            }), displayedComponents: .hourAndMinute).labelsHidden().fixedSize()
            Spacer()
            if !validMinutes { Text("1 bis 1.440 Min").font(.system(size: 11.5)).foregroundStyle(Arc.distraction) }
        }
    }

    private var summary: String {
        guard validMinutes else { return "Gib eine Dauer zwischen 1 Minute und 24 Stunden ein." }
        guard let list else { return "Wähle eine Liste." }
        let what = list.blocksEverything ? "alle Websites außer deinen Ausnahmen" : Self.contents(of: list)
        let until = end.formatted(date: .omitted, time: .shortened)
        switch strictness {
        case .flexible: return "Bis \(until) ist \(what) gesperrt. Du kannst jederzeit beenden oder kurz entsperren."
        case .locked: return "Bis \(until) ist \(what) gesperrt. Beenden geht nicht, kurz entsperren schon."
        case .hard: return "Bis \(until) ist \(what) gesperrt. Kein Beenden, kein Entsperren. Nur ein Notausgang mit 5 Min Wartezeit."
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
        let sites = list.blocksEverything ? ["alle Websites"] : list.domains
        let all = sites + list.apps.map(\.name)
        return all.count <= 4 ? all.joined(separator: ", ") : all.prefix(3).joined(separator: ", ") + " und \(all.count - 3) weitere"
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
        if session.scheduleID != nil { return ("Zeitplan", Arc.work) }
        return session.options.mode == .locked ? ("Durchziehen", Arc.work) : ("Flexibel", Arc.green)
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
                    Text("Gesperrt bis \(session.endsAt.formatted(date: .omitted, time: .shortened))").font(.system(size: 17, weight: .semibold))
                    Text(StartSessionCard.contents(of: session.blockList)).font(.system(size: 12.5)).foregroundStyle(Arc.secondary).lineLimit(3)
                    if !model.activeUnlocks.isEmpty {
                        Text("Gerade frei: \(model.activeUnlocks.map { $0.domain ?? "alles" }.joined(separator: ", "))")
                            .font(.system(size: 12)).foregroundStyle(Arc.green)
                    }
                }
            }
            if hard {
                HardModeCard(model: model).padding(.horizontal, -18).padding(.bottom, -18)
            } else {
                HStack(spacing: 8) {
                    Button("Kurz entsperren…") { model.page = .unlock }.buttonStyle(ArcButtonStyle(kind: .secondary, wide: true))
                        .disabled(model.isHard)
                    if !session.isStrict {
                        Button("Beenden") { confirmEnd = true }.buttonStyle(ArcButtonStyle(kind: .quiet))
                    }
                }
                Text(session.isStrict ? "Diese Sitzung läuft bis zum Ende. Kurz entsperren geht mit Wartezeit."
                                      : "Beenden gibt sofort alles frei. Kurz entsperren gibt nur eine Seite für ein paar Minuten frei.")
                    .font(.system(size: 11.5)).foregroundStyle(Arc.tertiary)
            }
        }
        .arcCard(padding: 20)
        .confirmationDialog("Sitzung beenden?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("Beenden", role: .destructive) { model.stop(session) }
        } message: { Text("Alles aus dieser Sitzung ist dann sofort wieder offen.") }
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
                    Text("Nächster Zeitplan: \(name)").font(.system(size: 13, weight: .medium))
                    Text("Startet von selbst \(start.formatted(.dateTime.weekday(.wide).hour().minute()))")
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
            Text("Wähle, was gesperrt wird").font(compact ? .headline : .title2.weight(.semibold))
            Text("Trag Websites und Apps in eine Sperrliste ein und starte eine Sitzung, wenn du dich konzentrieren willst.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Sperrliste anlegen…", systemImage: "plus") {
                openWindow.openMain()
                model.newList()
            }.buttonStyle(.borderedProminent).padding(.top, 4)
        }.frame(maxWidth: 380)
    }
}
