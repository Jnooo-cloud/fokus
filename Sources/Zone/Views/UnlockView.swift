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
                PageHeader(title: L("Entsperren", "Unlock"), subtitle: L("Nur kurz, und nur wenn du es wirklich brauchst.", "Briefly, and only when you really need it."))
                ForEach(model.activeUnlocks) { unlock in
                    HStack(spacing: 10) {
                        Circle().fill(Arc.green).frame(width: 7, height: 7)
                        Text(unlock.domain ?? L("Alles", "Everything")).font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text(Countdown.text(until: unlock.until, now: model.now)).monospacedDigit().foregroundStyle(Arc.secondary)
                        Button(L("Wieder sperren", "Block Again")) { model.relock(unlock) }.buttonStyle(ArcButtonStyle(kind: .quiet))
                    }.arcCard(padding: 12)
                }
                if model.isHard {
                    state(icon: "lock.fill", title: L("Hard Mode läuft", "Hard Mode is on"), detail: L("Bis \(model.hardEndText) ist Entsperren aus. Den Notausgang findest du unter Fokus.", "Unlocking is off until \(model.hardEndText). The emergency exit is on the Focus page."))
                } else if !model.hasBlocks {
                    state(icon: "checkmark.circle", title: L("Gerade ist nichts gesperrt", "Nothing is blocked right now"), detail: L("Sobald eine Sitzung läuft, kannst du hier etwas freigeben.", "Once a session runs, you can free something here."))
                } else if used >= settings.dailyLimit {
                    state(icon: "hand.raised", title: L("Tageslimit erreicht", "Daily limit reached"), detail: L("Du hast heute \(used)× entsperrt. Morgen geht es wieder.", "You unlocked \(used)× today. Try again tomorrow."))
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
            field(L("Was brauchst du?", "What do you need?")) {
                ChipRow(chips: [(nil, L("Alles", "Everything"))] + model.blockedTargets.map { (Optional($0), $0) }, selection: $model.unlockTarget)
            }
            field(L("Wie lange?", "How long?")) {
                PillPicker(options: SessionEngine.unlockChoices.map { ($0, L("\($0) Minuten", "\($0) minutes")) }, selection: $model.unlockMinutes)
            }
            if settings.requiresReason {
                field(L("Wofür?", "What for?")) {
                    TextField(L("Zum Beispiel: Kundenanfrage beantworten", "For example: answer a client request"), text: $model.unlockReason)
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
                    Text(L("Brauchst du das gerade wirklich?", "Do you really need this right now?")).font(.system(size: 13)).foregroundStyle(Arc.secondary)
                    Button(L("Abbrechen", "Cancel")) { model.cancelUnlock() }.buttonStyle(ArcButtonStyle(kind: .quiet))
                } else {
                    HoldToConfirm(title: L("Halten: \(model.unlockMinutes) Minuten freigeben", "Hold: free for \(model.unlockMinutes) minutes")) { model.confirmUnlock() }
                    Button(L("Doch nicht", "Never mind")) { model.cancelUnlock() }.buttonStyle(ArcButtonStyle(kind: .quiet))
                }
            } else {
                Button(L("Wartezeit starten · \(Int(model.unlockDelay)) Sek", "Start wait · \(Int(model.unlockDelay)) s")) { model.beginUnlock() }
                    .buttonStyle(ArcButtonStyle(kind: .primary, wide: true))
                    .disabled(settings.requiresReason && model.unlockReason.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
            }
            Text(L("\(used) von \(settings.dailyLimit) heute · jede Freigabe macht die nächste Wartezeit länger", "\(used) of \(settings.dailyLimit) today · every unlock makes the next wait longer"))
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
