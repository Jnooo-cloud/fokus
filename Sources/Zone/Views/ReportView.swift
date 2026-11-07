import SwiftUI
import ZoneCore

struct ReportView: View {
    @Bindable var model: ZoneModel
    private var store: InsightsStore { model.insights }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: L("Woche", "Week"), subtitle: range) {
                    HStack(spacing: 6) {
                        PillPicker(options: [(ZoneModel.Page.dashboard, L("Tag", "Day")), (ZoneModel.Page.report, L("Woche", "Week"))], selection: $model.page)
                            .frame(width: 150).padding(.trailing, 6)
                        Button { store.weekOffset -= 1 } label: { Image(systemName: "chevron.left") }.buttonStyle(ArcButtonStyle(kind: .quiet))
                        Button { store.weekOffset += 1 } label: { Image(systemName: "chevron.right") }
                            .buttonStyle(ArcButtonStyle(kind: .quiet)).disabled(store.weekOffset >= 0)
                    }
                }
                if let report = store.report {
                    if report.current.totals.total < 60 {
                        Text(L("Für diese Woche gibt es noch keine Daten.", "No data for this week yet.")).font(.system(size: 13)).foregroundStyle(Arc.secondary).arcCard()
                    } else { content(report) }
                }
            }
            .padding(.horizontal, 32).padding(.top, 44).padding(.bottom, 28)
            .frame(maxWidth: 1000).frame(maxWidth: .infinity)
        }
        .onAppear { store.refresh(blockedDomains: model.allBlockedDomains) }
    }

    private var range: String {
        guard let start = store.report?.start else { return "" }
        let end = start.addingTimeInterval(6 * 86400)
        return L("\(start.formatted(.dateTime.day().month(.abbreviated).locale(AppLanguage.locale))) bis \(end.formatted(.dateTime.day().month(.abbreviated).locale(AppLanguage.locale)))", "\(start.formatted(.dateTime.day().month(.abbreviated).locale(AppLanguage.locale))) to \(end.formatted(.dateTime.day().month(.abbreviated).locale(AppLanguage.locale)))")
    }

    @ViewBuilder private func content(_ report: WeekReport) -> some View {
        let now = report.current.totals, before = report.previous.totals
        HStack(spacing: 10) {
            Stat(title: L("Fokus-Score", "Focus score"), value: "\(now.score) %", delta: before.total > 0 ? L("\(signed(now.score - before.score)) Punkte", "\(signed(now.score - before.score)) points") : nil, good: now.score >= before.score)
            Stat(title: L("Arbeit", "Work"), value: DashboardView.time(now.work), delta: change(now.work, before.work), good: now.work >= before.work)
            Stat(title: L("Ablenkung", "Distraction"), value: DashboardView.time(now.distraction), delta: change(now.distraction, before.distraction), good: now.distraction <= before.distraction)
            Stat(title: L("Entsperrt", "Unlocked"), value: "\(unlocks(report))×", delta: nil, good: true)
        }
        let advice = WeekAdvice.suggestions(current: report.current, previous: report.previous, unlocks: unlocks(report), blocked: model.allBlockedDomains)
        if !advice.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Das würde ich ändern", "What I would change")).font(.system(size: 13, weight: .medium))
                ForEach(advice) { item in
                    HStack(spacing: 10) {
                        Text(item.text).font(.system(size: 13)).foregroundStyle(Arc.secondary).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        if let domain = item.blockDomain {
                            Button(L("Sperren", "Block")) { model.addToSelectedList(domain) }.buttonStyle(ArcButtonStyle(kind: .quiet))
                        }
                    }
                }
            }.arcCard()
        }
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Wann du abdriftest", "When you drift")).font(.system(size: 13, weight: .medium))
            Heatmap(heat: report.heat)
        }.arcCard()
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Tage", "Days")).font(.system(size: 13, weight: .medium))
            ForEach(report.days) { day in
                HStack(spacing: 10) {
                    Text(day.date, format: .dateTime.weekday(.abbreviated)).font(.system(size: 12.5)).foregroundStyle(Arc.secondary).frame(width: 30, alignment: .leading)
                    Text(DashboardView.time(day.totals.total)).font(.system(size: 12.5)).monospacedDigit().frame(width: 92, alignment: .leading)
                    Text(day.totals.total > 0 ? "\(day.totals.score) %" : "–").font(.system(size: 12.5, weight: .medium)).monospacedDigit().frame(width: 44, alignment: .trailing)
                    Text(L("Ablenkung \(DashboardView.time(day.totals.distraction))", "Distraction \(DashboardView.time(day.totals.distraction))")).font(.system(size: 12.5)).foregroundStyle(Arc.secondary)
                    Spacer()
                }
            }
        }.arcCard()
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Größte Zeitfresser", "Biggest time sinks")).font(.system(size: 13, weight: .medium))
            let top = report.current.items.filter { $0.category == .distraction }.prefix(6)
            if top.isEmpty { Text(L("Keine Ablenkung erfasst.", "No distraction tracked.")).font(.system(size: 13)).foregroundStyle(Arc.secondary) }
            ForEach(Array(top)) { item in
                let before = report.previous.items.first { $0.name == item.name }?.seconds ?? 0
                HStack {
                    Text(item.name).font(.system(size: 13)).lineLimit(1)
                    Spacer()
                    if let delta = change(item.seconds, before) { Text(delta).font(.system(size: 12)).foregroundStyle(Arc.tertiary) }
                    Text(DashboardView.time(item.seconds)).font(.system(size: 12.5)).monospacedDigit().foregroundStyle(Arc.secondary).frame(width: 92, alignment: .trailing)
                }
            }
        }.arcCard()
        let reasons = model.document.unlockEntries.filter { $0.date >= report.start && $0.date < report.start.addingTimeInterval(7 * 86400) }
        if !reasons.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Warum du entsperrt hast", "Why you unlocked")).font(.system(size: 13, weight: .medium))
                ForEach(reasons.suffix(8).reversed()) { entry in
                    Text("\(entry.target ?? L("Alles", "Everything")): \(entry.reason)").font(.system(size: 13)).foregroundStyle(Arc.secondary).lineLimit(1)
                }
            }.arcCard()
        }
    }

    private func unlocks(_ report: WeekReport) -> Int {
        model.document.unlockEntries.filter { $0.date >= report.start && $0.date < report.start.addingTimeInterval(7 * 86400) }.count
    }

    private func signed(_ value: Int) -> String { value > 0 ? "+\(value)" : "\(value)" }

    private func change(_ now: Double, _ before: Double) -> String? {
        guard before >= 60 else { return nil }
        return "\(signed(Int(((now - before) / before * 100).rounded()))) %"
    }
}

private struct Stat: View {
    let title: String
    let value: String
    let delta: String?
    let good: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11.5)).foregroundStyle(Arc.secondary)
            Text(value).font(.system(size: 18, weight: .medium)).tracking(-0.4).lineLimit(1).minimumScaleFactor(0.7)
            Text(delta ?? " ").font(.system(size: 11.5)).foregroundStyle(good ? Arc.green : Arc.rose)
        }.arcCard(padding: 13)
    }
}

private struct Heatmap: View {
    let heat: [[Double]]
    private let hours = Array(6..<24)
    private var names: [String] { AppLanguage.isEnglish ? ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"] : ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"] }
    private var peak: Double { max(heat.flatMap { $0 }.max() ?? 1, 60) }

    var body: some View {
        VStack(spacing: 3) {
            ForEach(Array(heat.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 3) {
                    Text(names[index]).font(.system(size: 10.5)).foregroundStyle(Arc.tertiary).frame(width: 20, alignment: .leading)
                    ForEach(hours, id: \.self) { hour in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(row[hour] > 0 ? Arc.distraction.opacity(0.18 + 0.82 * row[hour] / peak) : Arc.muted)
                            .frame(height: 16).frame(maxWidth: .infinity)
                            .help(L("\(names[index]), \(hour) Uhr: \(DashboardView.time(row[hour]))", "\(names[index]), \(hour):00: \(DashboardView.time(row[hour]))"))
                    }
                }
            }
            HStack {
                Text("6").frame(maxWidth: .infinity, alignment: .leading)
                Text("15").frame(maxWidth: .infinity)
                Text("23").frame(maxWidth: .infinity, alignment: .trailing)
            }.font(.system(size: 10.5)).foregroundStyle(Arc.tertiary).padding(.leading, 23)
        }
    }
}
