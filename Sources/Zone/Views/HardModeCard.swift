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
                    Text("bis \(model.hardEndText)").font(.system(size: 12)).foregroundStyle(Arc.secondary)
                }
            }
            if model.isHard { running } else { setup }
        }
        .padding(18)
        .background(Arc.distraction.opacity(0.07), in: UnevenRoundedRectangle(bottomLeadingRadius: Arc.panelRadius, bottomTrailingRadius: Arc.panelRadius))
    }

    @ViewBuilder private var setup: some View {
        Text("Kein Entsperren, kein Beenden. Nur ein Notausgang mit 5 Minuten Wartezeit.")
            .font(.system(size: 13)).foregroundStyle(Arc.secondary).fixedSize(horizontal: false, vertical: true)
        PillPicker(options: SessionEngine.hardChoices.map { ($0, MenuFormat.duration($0)) }, selection: $minutes)
        HoldToConfirm(title: "Halten zum Starten", duration: 2, tint: AnyShapeStyle(Arc.rose.opacity(0.55))) { model.startHard(minutes: minutes) }
            .disabled(model.selectedList?.isEmpty != false)
    }

    @ViewBuilder private var running: some View {
        if let ready = model.emergencyReadyAt {
            if ready > model.now {
                Text("Notausgang öffnet in \(Countdown.text(until: ready, now: model.now)). Bleib auf dieser Seite.")
                    .font(.system(size: 13)).foregroundStyle(Arc.secondary).monospacedDigit()
                Button("Abbrechen") { model.cancelEmergency() }.buttonStyle(ArcButtonStyle(kind: .quiet))
            } else {
                HoldToConfirm(title: "Halten: Hard Mode beenden", duration: 3, tint: AnyShapeStyle(Arc.rose.opacity(0.55))) { model.endHard() }
            }
        } else {
            Text("Durchziehen lohnt sich. Falls wirklich etwas brennt:").font(.system(size: 13)).foregroundStyle(Arc.secondary)
            Button("Notausgang (5 Min warten)") { model.beginEmergency() }.buttonStyle(ArcButtonStyle(kind: .quiet))
        }
    }
}
