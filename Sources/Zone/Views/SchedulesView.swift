import SwiftUI
import ZoneCore

struct SchedulesView: View {
    let model: ZoneModel
    @State private var deleting: FocusSchedule?
    @State private var enabling: FocusSchedule?
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PageHeader(title: "Zeitpläne", subtitle: "Feste Fokuszeiten, die von selbst starten.") {
                    Button("Neuer Zeitplan") { model.newSchedule() }.buttonStyle(ArcButtonStyle(kind: .primary)).disabled(model.availableLists.isEmpty)
                }
                if model.document.schedules.isEmpty {
                    ContentUnavailableView {
                        Label("Keine Zeitpläne", systemImage: "calendar")
                    } description: {
                        Text("Plane eine einmalige Sitzung oder wiederhole sie an festen Tagen.")
                    }
                }
                ForEach(model.schedulesByNextStart) { schedule in
                    ScheduleRow(schedule: schedule, model: model, setEnabled: { enabled in
                        var next = schedule
                        next.isEnabled = enabled
                        if enabled && SessionEngine.activeInterval(for: next, at: Date()) != nil {
                            enabling = next
                        } else { _ = model.saveSchedule(next) }
                    }, delete: { deleting = schedule }).arcCard(padding: 6)
                }
                Text("Zeiten folgen der Zeitzone dieses Macs. Fokus muss laufen, damit Sitzungen starten.")
                    .font(.system(size: 11.5)).foregroundStyle(Arc.tertiary)
            }
            .padding(.horizontal, 32).padding(.top, 44).padding(.bottom, 28)
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .confirmationDialog("Diesen Zeitplan löschen?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Zeitplan löschen", role: .destructive) { if let deleting { model.deleteSchedule(deleting) }; deleting = nil }
        } message: { Text("A session already running will finish as planned.") }
        .confirmationDialog("Diese Sitzung startet jetzt", isPresented: Binding(get: { enabling != nil }, set: { if !$0 { enabling = nil } }), titleVisibility: .visible) {
            Button("Aktivieren und starten") { if let enabling { _ = model.saveSchedule(enabling) }; enabling = nil }
        } message: {
            Text("Die aktuelle Zeit liegt in diesem Zeitplan. Gewählte Apps werden geschlossen. Geplante Sitzungen lassen sich nicht früher beenden.")
        }
    }
}

private struct ScheduleRow: View {
    let schedule: FocusSchedule
    let model: ZoneModel
    let setEnabled: @MainActor @Sendable (Bool) -> Void
    let delete: () -> Void

    private var running: Bool { model.isRunning(schedule) }
    private var status: String {
        if running { return "Läuft" }
        if !schedule.isEnabled { return "Aus" }
        if schedule.kind == .once && schedule.onceEnd <= model.now { return "Erledigt" }
        return "An"
    }

    var body: some View {
        HStack(spacing: 12) {
            Button { model.editingSchedule = schedule } label: {
                HStack(spacing: 14) {
                    Image(systemName: schedule.kind == .weekly ? "calendar.badge.clock" : "calendar")
                        .font(.title2).foregroundStyle(.secondary).frame(width: 30).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(schedule.name).font(.headline)
                        Text(summary).font(.callout).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            if let list = model.document.blockLists.first(where: { $0.id == schedule.blockListID }) {
                                Text(list.name)
                            }
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Image(systemName: "chevron.right").font(.caption.weight(.medium))
                        .foregroundStyle(.tertiary).accessibilityHidden(true)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(schedule.name)")
            .accessibilityValue(summary)
            .contextMenu {
                Button("Löschen", role: .destructive) { delete() }.disabled(running)
            }
            // A closure avoids a Swift 6.2 IRGen crash converting the isolated callback directly.
            Toggle(status, isOn: Binding(get: { schedule.isEnabled || running }, set: { enabled in setEnabled(enabled) }))
                .toggleStyle(.switch).controlSize(.small).fixedSize()
                .disabled(running)
                .help(running ? "Geplante Sitzungen laufen bis zum Ende." : "")
                .accessibilityLabel("Enable \(schedule.name)")
            Menu {
                Button("Löschen", role: .destructive) { delete() }.disabled(running)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22)
            .accessibilityLabel("Actions for \(schedule.name)").help("Weitere Aktionen")
        }.padding(.horizontal, 10).padding(.vertical, 8).accessibilityElement(children: .contain)
    }

    private var summary: String {
        ScheduleFormat.summary(schedule)
            + (schedule.kind == .weekly && schedule.endMinute < schedule.startMinute ? " (next day)" : "")
    }

}

struct ScheduleEditor: View {
    let model: ZoneModel
    @State private var schedule: FocusSchedule
    @Environment(\.dismiss) private var dismiss
    @State private var confirmSave = false
    @State private var saveError: String?

    init(model: ZoneModel, schedule: FocusSchedule) {
        self.model = model
        _schedule = State(initialValue: schedule)
    }

    private var isRunning: Bool { model.isRunning(schedule) }

    private var validationMessage: String? {
        if let session = model.runningSession(for: schedule) { return ZoneModel.runningScheduleMessage(session) }
        if schedule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Gib diesem Zeitplan einen Namen." }
        if schedule.kind == .weekly {
            if schedule.weekdays.isEmpty { return "Wähle mindestens einen Tag." }
            if schedule.startMinute == schedule.endMinute { return "Wähle unterschiedliche Start- und Endzeiten." }
        } else {
            if schedule.onceEnd <= schedule.onceStart { return "Das Ende muss nach dem Start liegen." }
            if schedule.onceEnd.timeIntervalSince(schedule.onceStart) > 86400 { return "A session can last up to 24 hours." }
            if schedule.isEnabled && schedule.onceEnd <= model.now { return "Wähle ein Ende in der Zukunft oder schalte den Zeitplan aus." }
        }
        if schedule.isEnabled && model.document.blockLists.first(where: { $0.id == schedule.blockListID })?.domains.isEmpty == false
            && !model.websiteBlockingReady { return "Verbinde in den Einstellungen einen Browser oder speichere den Zeitplan deaktiviert." }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(model.document.schedules.contains { $0.id == schedule.id } ? "Zeitplan bearbeiten" : "Neuer Zeitplan")
                .font(.title2.weight(.semibold))
            Form {
                TextField("Name", text: $schedule.name)
                Picker("Sperrliste", selection: $schedule.blockListID) {
                    ForEach(model.availableLists) { Text($0.name).tag($0.id) }
                }
                Picker("Wiederholen", selection: $schedule.kind) {
                    Text("Wöchentlich").tag(ScheduleKind.weekly)
                    Text("Nur einmal").tag(ScheduleKind.once)
                }.pickerStyle(.segmented)
                if schedule.kind == .weekly {
                    LabeledContent("Tage") {
                        HStack(spacing: 4) {
                            ForEach(ScheduleFormat.orderedWeekdays, id: \.self) { day in
                                Toggle(isOn: Binding(get: { schedule.weekdays.contains(day) }, set: { selected in
                                    if selected { schedule.weekdays.insert(day) } else { schedule.weekdays.remove(day) }
                                })) {
                                    Text(Calendar.autoupdatingCurrent.shortWeekdaySymbols[day - 1])
                                }.toggleStyle(.button).controlSize(.small)
                                    .accessibilityLabel(Calendar.autoupdatingCurrent.weekdaySymbols[day - 1])
                            }
                        }
                    }
                    DatePicker("Von", selection: timeBinding(\.startMinute), displayedComponents: .hourAndMinute)
                    DatePicker("Bis", selection: timeBinding(\.endMinute), displayedComponents: .hourAndMinute)
                    if schedule.endMinute < schedule.startMinute {
                        Text("Endet am nächsten Tag.").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    DatePicker("Von", selection: $schedule.onceStart, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("Bis", selection: $schedule.onceEnd, displayedComponents: [.date, .hourAndMinute])
                }
                Toggle("Aktiv", isOn: $schedule.isEnabled)
            }.formStyle(.columns).disabled(isRunning)
            Divider()
            ScheduleOptionsDisclosure(options: $schedule.options).disabled(isRunning)
            Text("Änderungen gelten für künftige Sitzungen. Geplante App-Sperren können ungespeicherte Arbeit schließen.")
                .font(.caption).foregroundStyle(.secondary)
            if let message = validationMessage ?? saveError {
                Text(message).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Zeitplan speichern") {
                    if schedule.isEnabled, SessionEngine.activeInterval(for: schedule, at: Date()) != nil { confirmSave = true }
                    else { save() }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(validationMessage != nil)
            }
        }.padding(24).frame(width: 530)
            .confirmationDialog("Diese Sitzung startet jetzt", isPresented: $confirmSave, titleVisibility: .visible) {
                Button("Speichern und starten") { save() }
            } message: { Text("Die aktuelle Zeit liegt in diesem Zeitplan. Gewählte Apps werden geschlossen. Geplante Sitzungen lassen sich nicht früher beenden.") }
    }

    private func save() {
        schedule.name = schedule.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if model.saveSchedule(schedule) { dismiss() }
        else { saveError = model.errorMessage; model.errorMessage = nil }
    }

    private func timeBinding(_ keyPath: WritableKeyPath<FocusSchedule, Int>) -> Binding<Date> {
        Binding(get: {
            let minutes = schedule[keyPath: keyPath]
            return Calendar.autoupdatingCurrent.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        }, set: { date in
            let parts = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: date)
            schedule[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        })
    }
}

private struct ScheduleOptionsDisclosure: View {
    @Binding var options: SessionOptions
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            SessionOptionsEditor(options: $options, scheduled: true).padding(.top, 12)
        } label: {
            Text(SessionOptionsSummary.text(for: options, scheduled: true))
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}
