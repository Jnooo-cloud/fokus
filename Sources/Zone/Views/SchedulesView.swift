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
                PageHeader(title: L("Zeitpläne", "Schedules"), subtitle: L("Feste Fokuszeiten, die von selbst starten.", "Fixed focus times that start on their own.")) {
                    Button(L("Neuer Zeitplan", "New Schedule")) { model.newSchedule() }.buttonStyle(ArcButtonStyle(kind: .primary)).disabled(model.availableLists.isEmpty)
                }
                if model.document.schedules.isEmpty {
                    ContentUnavailableView {
                        Label(L("Keine Zeitpläne", "No Schedules"), systemImage: "calendar")
                    } description: {
                        Text(L("Plane eine einmalige Sitzung oder wiederhole sie an festen Tagen.", "Plan a one-time session or repeat it on set days."))
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
                Text(L("Zeiten folgen der Zeitzone dieses Macs. Fokus muss laufen, damit Sitzungen starten.", "Times follow this Mac’s time zone. Fokus must be running for sessions to start."))
                    .font(.system(size: 11.5)).foregroundStyle(Arc.tertiary)
            }
            .padding(.horizontal, 32).padding(.top, 44).padding(.bottom, 28)
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .confirmationDialog(L("Diesen Zeitplan löschen?", "Delete this schedule?"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button(L("Zeitplan löschen", "Delete Schedule"), role: .destructive) { if let deleting { model.deleteSchedule(deleting) }; deleting = nil }
        } message: { Text(L("A session already running will finish as planned.", "A session already running will finish as planned.")) }
        .confirmationDialog(L("Diese Sitzung startet jetzt", "This session starts now"), isPresented: Binding(get: { enabling != nil }, set: { if !$0 { enabling = nil } }), titleVisibility: .visible) {
            Button(L("Aktivieren und starten", "Enable and Start")) { if let enabling { _ = model.saveSchedule(enabling) }; enabling = nil }
        } message: {
            Text(L("Die aktuelle Zeit liegt in diesem Zeitplan. Gewählte Apps werden geschlossen. Geplante Sitzungen lassen sich nicht früher beenden.", "The current time falls inside this schedule. Selected apps will close. Scheduled sessions can’t be ended early."))
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
        if running { return L("Läuft", "Running") }
        if !schedule.isEnabled { return L("Aus", "Off") }
        if schedule.kind == .once && schedule.onceEnd <= model.now { return L("Erledigt", "Done") }
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
                Button(L("Löschen", "Delete"), role: .destructive) { delete() }.disabled(running)
            }
            // A closure avoids a Swift 6.2 IRGen crash converting the isolated callback directly.
            Toggle(status, isOn: Binding(get: { schedule.isEnabled || running }, set: { enabled in setEnabled(enabled) }))
                .toggleStyle(.switch).controlSize(.small).fixedSize()
                .disabled(running)
                .help(running ? L("Geplante Sitzungen laufen bis zum Ende.", "Scheduled sessions run to the end.") : "")
                .accessibilityLabel("Enable \(schedule.name)")
            Menu {
                Button(L("Löschen", "Delete"), role: .destructive) { delete() }.disabled(running)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22)
            .accessibilityLabel("Actions for \(schedule.name)").help(L("Weitere Aktionen", "More actions"))
        }.padding(.horizontal, 10).padding(.vertical, 8).accessibilityElement(children: .contain)
    }

    private var summary: String {
        ScheduleFormat.summary(schedule)
            + (schedule.kind == .weekly && schedule.endMinute < schedule.startMinute ? L(" (next day)", " (next day)") : "")
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
        if schedule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return L("Gib diesem Zeitplan einen Namen.", "Give this schedule a name.") }
        if schedule.kind == .weekly {
            if schedule.weekdays.isEmpty { return L("Wähle mindestens einen Tag.", "Choose at least one day.") }
            if schedule.startMinute == schedule.endMinute { return L("Wähle unterschiedliche Start- und Endzeiten.", "Choose different start and end times.") }
        } else {
            if schedule.onceEnd <= schedule.onceStart { return L("Das Ende muss nach dem Start liegen.", "The end must be after the start.") }
            if schedule.onceEnd.timeIntervalSince(schedule.onceStart) > 86400 { return L("A session can last up to 24 hours.", "A session can last up to 24 hours.") }
            if schedule.isEnabled && schedule.onceEnd <= model.now { return L("Wähle ein Ende in der Zukunft oder schalte den Zeitplan aus.", "Choose a future end, or turn this schedule off.") }
        }
        if schedule.isEnabled && model.document.blockLists.first(where: { $0.id == schedule.blockListID })?.domains.isEmpty == false
            && !model.websiteBlockingReady { return L("Verbinde in den Einstellungen einen Browser oder speichere den Zeitplan deaktiviert.", "Connect a browser in Settings, or save this schedule turned off.") }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(model.document.schedules.contains { $0.id == schedule.id } ? L("Zeitplan bearbeiten", "Edit Schedule") : L("Neuer Zeitplan", "New Schedule"))
                .font(.title2.weight(.semibold))
            Form {
                TextField("Name", text: $schedule.name)
                Picker(L("Sperrliste", "Block list"), selection: $schedule.blockListID) {
                    ForEach(model.availableLists) { Text($0.name).tag($0.id) }
                }
                Picker(L("Wiederholen", "Repeat"), selection: $schedule.kind) {
                    Text(L("Wöchentlich", "Weekly")).tag(ScheduleKind.weekly)
                    Text(L("Nur einmal", "Just once")).tag(ScheduleKind.once)
                }.pickerStyle(.segmented)
                if schedule.kind == .weekly {
                    LabeledContent(L("Tage", "Days")) {
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
                    DatePicker(L("Von", "From"), selection: timeBinding(\.startMinute), displayedComponents: .hourAndMinute)
                    DatePicker(L("Bis", "Until"), selection: timeBinding(\.endMinute), displayedComponents: .hourAndMinute)
                    if schedule.endMinute < schedule.startMinute {
                        Text(L("Endet am nächsten Tag.", "Ends the next day.")).font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    DatePicker(L("Von", "From"), selection: $schedule.onceStart, displayedComponents: [.date, .hourAndMinute])
                    DatePicker(L("Bis", "Until"), selection: $schedule.onceEnd, displayedComponents: [.date, .hourAndMinute])
                }
                Toggle(L("Aktiv", "Active"), isOn: $schedule.isEnabled)
            }.formStyle(.columns).disabled(isRunning)
            Divider()
            ScheduleOptionsDisclosure(options: $schedule.options).disabled(isRunning)
            Text(L("Änderungen gelten für künftige Sitzungen. Geplante App-Sperren können ungespeicherte Arbeit schließen.", "Changes apply to future sessions. Scheduled app blocks may close unsaved work."))
                .font(.caption).foregroundStyle(.secondary)
            if let message = validationMessage ?? saveError {
                Text(message).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button(L("Abbrechen", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("Zeitplan speichern", "Save Schedule")) {
                    if schedule.isEnabled, SessionEngine.activeInterval(for: schedule, at: Date()) != nil { confirmSave = true }
                    else { save() }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(validationMessage != nil)
            }
        }.padding(24).frame(width: 530)
            .confirmationDialog(L("Diese Sitzung startet jetzt", "This session starts now"), isPresented: $confirmSave, titleVisibility: .visible) {
                Button(L("Speichern und starten", "Save and Start")) { save() }
            } message: { Text(L("Die aktuelle Zeit liegt in diesem Zeitplan. Gewählte Apps werden geschlossen. Geplante Sitzungen lassen sich nicht früher beenden.", "The current time falls inside this schedule. Selected apps will close. Scheduled sessions can’t be ended early.")) }
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
