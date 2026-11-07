import SwiftUI
import ZoneCore

/// The deliberate way out: say why, wait, then hold. Leaving the page cancels the wait.
struct UnlockView: View {
    @Bindable var model: ZoneModel

    private var settings: UnlockSettings { model.document.unlockSettings }
    private var used: Int { model.unlocksToday }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Entsperren", subtitle: "Nur kurz, und nur wenn du es wirklich brauchst.")
                ForEach(model.activeUnlocks) { unlock in
                    HStack(spacing: 10) {
                        Circle().fill(Arc.green).frame(width: 7, height: 7)
                        Text(unlock.domain ?? "Alles").font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text(Countdown.text(until: unlock.until, now: model.now)).monospacedDigit().foregroundStyle(Arc.secondary)
                        Button("Wieder sperren") { model.relock(unlock) }.buttonStyle(ArcButtonStyle(kind: .quiet))
                    }.arcCard(padding: 12)
                }
                if model.isHard {
                    state(icon: "lock.fill", title: "Hard Mode läuft", detail: "Bis \(model.hardEndText) ist Entsperren aus. Den Notausgang findest du unter Fokus.")
                } else if !model.hasBlocks {
                    state(icon: "checkmark.circle", title: "Gerade ist nichts gesperrt", detail: "Sobald eine Sitzung läuft, kannst du hier etwas freigeben.")
                } else if used >= settings.dailyLimit {
                    state(icon: "hand.raised", title: "Tageslimit erreicht", detail: "Du hast heute \(used)× entsperrt. Morgen geht es wieder.")
                } else {
                    form
                }
            }
            .padding(.horizontal, 32).padding(.top, 44).padding(.bottom, 28)
            .frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .onDisappear { model.cancelUnlock() }
    }

    private func state(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 22, weight: .light)).foregroundStyle(Arc.secondary)
            Text(title).font(.system(size: 15, weight: .medium))
            Text(detail).font(.system(size: 13)).foregroundStyle(Arc.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 26).arcCard()
    }

    @ViewBuilder private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            field("Was brauchst du?") {
                ChipRow(chips: [(nil, "Alles")] + model.blockedTargets.map { (Optional($0), $0) }, selection: $model.unlockTarget)
            }
            field("Wie lange?") {
                PillPicker(options: SessionEngine.unlockChoices.map { ($0, "\($0) Minuten") }, selection: $model.unlockMinutes)
            }
            if settings.requiresReason {
                field("Wofür?") {
                    TextField("Zum Beispiel: Kundenanfrage beantworten", text: $model.unlockReason)
                        .textFieldStyle(.plain).font(.system(size: 13))
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(Arc.muted, in: RoundedRectangle(cornerRadius: Arc.controlRadius, style: .continuous))
                }
            }
        }
        .disabled(model.unlockReadyAt != nil)
        .arcCard()

        VStack(spacing: 14) {
            if let ready = model.unlockReadyAt {
                if ready > model.now {
                    let left = ready.timeIntervalSince(model.now)
                    CountdownRing(fraction: left / max(model.unlockDelay, 1), label: "\(Int(ceil(left)))")
                    Text("Brauchst du das gerade wirklich?").font(.system(size: 13)).foregroundStyle(Arc.secondary)
                    Button("Abbrechen") { model.cancelUnlock() }.buttonStyle(ArcButtonStyle(kind: .quiet))
                } else {
                    HoldToConfirm(title: "Halten: \(model.unlockMinutes) Minuten freigeben") { model.confirmUnlock() }
                    Button("Doch nicht") { model.cancelUnlock() }.buttonStyle(ArcButtonStyle(kind: .quiet))
                }
            } else {
                Button("Wartezeit starten · \(Int(model.unlockDelay)) Sek") { model.beginUnlock() }
                    .buttonStyle(ArcButtonStyle(kind: .primary, wide: true))
                    .disabled(settings.requiresReason && model.unlockReason.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
            }
            Text("\(used) von \(settings.dailyLimit) heute · jede Freigabe macht die nächste Wartezeit länger")
                .font(.system(size: 11.5)).foregroundStyle(Arc.tertiary)
        }.frame(maxWidth: .infinity).arcCard()
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Arc.secondary)
            content()
        }
    }
}
