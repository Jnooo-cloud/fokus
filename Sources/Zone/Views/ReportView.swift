import SwiftUI
import ZoneCore

struct ReportView: View {
    @Bindable var model: ZoneModel
    private var store: InsightsStore { model.insights }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Woche", subtitle: range) {
                    HStack(spacing: 6) {
                        PillPicker(options: [(ZoneModel.Page.dashboard, "Tag"), (ZoneModel.Page.report, "Woche")], selection: $model.page)
                            .frame(width: 150).padding(.trailing, 6)
                        Button { store.weekOffset -= 1 } label: { Image(systemName: "chevron.left") }.buttonStyle(ArcButtonStyle(kind: .quiet))
                        Button { store.weekOffset += 1 } label: { Image(systemName: "chevron.right") }
                            .buttonStyle(ArcButtonStyle(kind: .quiet)).disabled(store.weekOffset >= 0)
                    }
                }
                if let report = store.report {
                    if report.current.totals.total < 60 {
                        Text("Für diese Woche gibt es noch keine Daten.").font(.system(size: 13)).foregroundStyle(Arc.secondary).arcCard()
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
        return "\(start.formatted(.dateTime.day().month(.abbreviated))) bis \(end.formatted(.dateTime.day().month(.abbreviated)))"
    }

    @ViewBuilder private func content(_ report: WeekReport) -> some View {
        let now = report.current.totals, before = report.previous.totals
        HStack(spacing: 10) {
            Stat(title: "Fokus-Score", value: "\(now.score) %", delta: before.total > 0 ? "\(signed(now.score - before.score)) Punkte" : nil, good: now.score >= before.score)
            Stat(title: "Arbeit", value: DashboardView.time(now.work), delta: change(now.work, before.work), good: now.work >= before.work)
            Stat(title: "Ablenkung", value: DashboardView.time(now.distraction), delta: change(now.distraction, before.distraction), good: now.distraction <= before.distraction)
            Stat(title: "Entsperrt", value: "\(unlocks(report))×", delta: nil, good: true)
        }
        let advice = WeekAdvice.suggestions(current: report.current, previous: report.previous, unlocks: unlocks(report), blocked: model.allBlockedDomains)
        if !advice.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Das würde ich ändern").font(.system(size: 13, weight: .medium))
                ForEach(advice) { item in
                    HStack(spacing: 10) {
                        Text(item.text).font(.system(size: 13)).foregroundStyle(Arc.secondary).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        if let domain = item.blockDomain {
                            Button("Sperren") { model.addToSelectedList(domain) }.buttonStyle(ArcButtonStyle(kind: .quiet))
                        }
                    }
                }
            }.arcCard()
        }
        VStack(alignment: .leading, spacing: 10) {
            Text("Wann du abdriftest").font(.system(size: 13, weight: .medium))
            Heatmap(heat: report.heat)
        }.arcCard()
        VStack(alignment: .leading, spacing: 8) {
            Text("Tage").font(.system(size: 13, weight: .medium))
            ForEach(report.days) { day in
                HStack(spacing: 10) {
                    Text(day.date, format: .dateTime.weekday(.abbreviated)).font(.system(size: 12.5)).foregroundStyle(Arc.secondary).frame(width: 30, alignment: .leading)
                    Text(DashboardView.time(day.totals.total)).font(.system(size: 12.5)).monospacedDigit().frame(width: 92, alignment: .leading)
                    Text(day.totals.total > 0 ? "\(day.totals.score) %" : "–").font(.system(size: 12.5, weight: .medium)).monospacedDigit().frame(width: 44, alignment: .trailing)
                    Text("Ablenkung \(DashboardView.time(day.totals.distraction))").font(.system(size: 12.5)).foregroundStyle(Arc.secondary)
                    Spacer()
                }
            }
        }.arcCard()
        VStack(alignment: .leading, spacing: 8) {
            Text("Größte Zeitfresser").font(.system(size: 13, weight: .medium))
            let top = report.current.items.filter { $0.category == .distraction }.prefix(6)
            if top.isEmpty { Text("Keine Ablenkung erfasst.").font(.system(size: 13)).foregroundStyle(Arc.secondary) }
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
                Text("Warum du entsperrt hast").font(.system(size: 13, weight: .medium))
                ForEach(reasons.suffix(8).reversed()) { entry in
                    Text("\(entry.target ?? "Alles"): \(entry.reason)").font(.system(size: 13)).foregroundStyle(Arc.secondary).lineLimit(1)
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
    private let names = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
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
                            .help("\(names[index]), \(hour) Uhr: \(DashboardView.time(row[hour]))")
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
