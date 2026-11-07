import SwiftUI
import ZoneCore

/// Opt-in lock with no unlocks. The only way out early is the long emergency wait.
struct HardModeCard: View {
    @Bindable var model: ZoneModel
    @State private var minutes = 60

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill").font(.system(size: 12)).foregroundStyle(Arc.rose)
                Text("Hard Mode").font(.system(size: 14, weight: .medium))
                Spacer()
                if model.isHard {
                    Text(L("bis \(model.hardEndText)", "until \(model.hardEndText)")).font(.system(size: 12)).foregroundStyle(Arc.secondary)
                }
            }
            if model.isHard { running } else { setup }
        }
        .padding(18)
        .background(Arc.distraction.opacity(0.07), in: UnevenRoundedRectangle(bottomLeadingRadius: Arc.panelRadius, bottomTrailingRadius: Arc.panelRadius))
    }

    @ViewBuilder private var setup: some View {
        Text(L("Kein Entsperren, kein Beenden. Nur ein Notausgang mit 5 Minuten Wartezeit.", "No unlocking, no ending. Only an emergency exit after a 5 minute wait."))
            .font(.system(size: 13)).foregroundStyle(Arc.secondary).fixedSize(horizontal: false, vertical: true)
        PillPicker(options: SessionEngine.hardChoices.map { ($0, MenuFormat.duration($0)) }, selection: $minutes)
        HoldToConfirm(title: L("Halten zum Starten", "Hold to Start"), duration: 2, tint: AnyShapeStyle(Arc.rose.opacity(0.55))) { model.startHard(minutes: minutes) }
            .disabled(model.selectedList?.isEmpty != false)
    }

    @ViewBuilder private var running: some View {
        if let ready = model.emergencyReadyAt {
            if ready > model.now {
                Text(L("Notausgang öffnet in \(Countdown.text(until: ready, now: model.now)). Bleib auf dieser Seite.", "Emergency exit opens in \(Countdown.text(until: ready, now: model.now)). Stay on this page."))
                    .font(.system(size: 13)).foregroundStyle(Arc.secondary).monospacedDigit()
                Button(L("Abbrechen", "Cancel")) { model.cancelEmergency() }.buttonStyle(ArcButtonStyle(kind: .quiet))
            } else {
                HoldToConfirm(title: L("Halten: Hard Mode beenden", "Hold: End Hard Mode"), duration: 3, tint: AnyShapeStyle(Arc.rose.opacity(0.55))) { model.endHard() }
            }
        } else {
            Text(L("Durchziehen lohnt sich. Falls wirklich etwas brennt:", "Seeing it through pays off. If something is really on fire:")).font(.system(size: 13)).foregroundStyle(Arc.secondary)
            Button(L("Notausgang (5 Min warten)", "Emergency exit (wait 5 min)")) { model.beginEmergency() }.buttonStyle(ArcButtonStyle(kind: .quiet))
        }
    }
}
