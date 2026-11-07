import AppKit
import SwiftUI
import ZoneCore

struct DashboardView: View {
    @Bindable var model: ZoneModel
    private var store: InsightsStore { model.insights }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: L("Heute", "Today"), subtitle: Date().formatted(.dateTime.weekday(.wide).day().month(.wide).locale(AppLanguage.locale))) {
                    PillPicker(options: [(ZoneModel.Page.dashboard, L("Tag", "Day")), (ZoneModel.Page.report, L("Woche", "Week"))], selection: $model.page)
                        .frame(width: 150)
                }
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) {
                        TimelineCard(hours: store.hourTotals)
                        EntriesCard(entries: store.entries, store: store)
                    }
                    VStack(spacing: 16) {
                        FocusTimeCard(today: store.today, yesterday: store.yesterday)
                        SplitCard(totals: store.today)
                        GroupsCard(store: store)
                        HabitCard(model: model)
                        if !findings.isEmpty { FindingsCard(lines: findings) }
                    }.frame(width: 280)
                }
            }
            .padding(.horizontal, 28).padding(.top, 44).padding(.bottom, 28)
            .frame(maxWidth: 1000).frame(maxWidth: .infinity)
        }
        .onAppear { store.refresh(blockedDomains: model.allBlockedDomains) }
    }

    private var findings: [String] {
        var lines: [String] = []
        if let top = store.entries.first(where: { $0.category == .distraction }) {
            lines.append(L("\(top.name) frisst heute am meisten: \(Self.time(top.seconds)).", "\(top.name) took the most time today: \(Self.time(top.seconds))."))
        }
        if let peak = store.hours.enumerated().max(by: { $0.element < $1.element }), peak.element >= 300 {
            lines.append(L("Schwächste Stunde: \(peak.offset) bis \(peak.offset + 1) Uhr.", "Weakest hour: \(peak.offset):00 to \(peak.offset + 1):00."))
        }
        if let attempt = model.attemptsToday.max(by: { $0.value < $1.value }), attempt.value >= 2 {
            lines.append(L("\(attempt.key) wolltest du \(attempt.value)× öffnen.", "You tried to open \(attempt.key) \(attempt.value)×."))
        }
        return lines
    }

    static func time(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        return minutes < 60 ? L("\(minutes) Min", "\(minutes) min") : L("\(minutes / 60) Std \(minutes % 60) Min", "\(minutes / 60) h \(minutes % 60) min")
    }

    static func short(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }

    static func color(_ category: UsageCategory) -> Color {
        switch category {
        case .work: Arc.work
        case .neutral: Arc.neutralTone
        case .distraction: Arc.distraction
        }
    }
}

struct CardTitle: View {
    let text: String
    var trailing: String?
    var body: some View {
        HStack {
            Text(text).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Arc.secondary)
            Spacer()
            if let trailing { Text(trailing).font(.system(size: 12)).foregroundStyle(Arc.tertiary) }
        }
    }
}

/// Each hour as a bar filled to its share of 60 minutes, split by category.
private struct TimelineCard: View {
    let hours: [UsageTotals]
    private var range: [Int] {
        let active = hours.indices.filter { hours[$0].total >= 30 }
        let now = Calendar.autoupdatingCurrent.component(.hour, from: Date())
        let first = min(active.first ?? 8, 8), last = max(active.last ?? now, now, 18)
        return Array(first...min(last, 23))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(text: L("TAGESVERLAUF", "TIMELINE"), trailing: L("pro Stunde", "per hour"))
            VStack(spacing: 5) {
                ForEach(range, id: \.self) { hour in
                    HStack(spacing: 10) {
                        Text(String(format: "%02d", hour)).font(.system(size: 11, weight: .medium)).monospacedDigit()
                            .foregroundStyle(Arc.tertiary).frame(width: 18, alignment: .trailing)
                        GeometryReader { proxy in
                            let unit = proxy.size.width / 3600
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Arc.track.opacity(0.6))
                                HStack(spacing: 2) {
                                    segment(hours[hour].work * unit, Arc.work)
                                    segment(hours[hour].neutral * unit, Arc.neutralTone)
                                    segment(hours[hour].distraction * unit, Arc.distraction)
                                }
                            }
                        }.frame(height: 16)
                            .help(L("\(hour) Uhr: \(DashboardView.time(hours[hour].total)) aktiv, \(DashboardView.time(hours[hour].distraction)) Ablenkung", "\(hour):00: \(DashboardView.time(hours[hour].total)) active, \(DashboardView.time(hours[hour].distraction)) distraction"))
                    }
                }
            }
            HStack(spacing: 14) {
                LegendDot(name: L("Arbeit", "Work"), color: Arc.work)
                LegendDot(name: "Neutral", color: Arc.neutralTone)
                LegendDot(name: L("Ablenkung", "Distraction"), color: Arc.distraction)
            }
        }.arcCard()
    }

    @ViewBuilder private func segment(_ width: CGFloat, _ color: Color) -> some View {
        if width >= 1 {
            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(color.gradient).frame(width: width)
        }
    }
}

private struct LegendDot: View {
    let name: String
    let color: Color
    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(name).font(.system(size: 11.5)).foregroundStyle(Arc.secondary)
        }
    }
}

private struct FocusTimeCard: View {
    let today: UsageTotals
    let yesterday: UsageTotals

    private var delta: String? {
        guard yesterday.work >= 300 else { return nil }
        let change = Int(((today.work - yesterday.work) / yesterday.work * 100).rounded())
        return (change >= 0 ? "+" : "") + "\(change) % " + L("vs. gestern", "vs. yesterday")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(text: L("FOKUSZEIT", "FOCUS TIME"))
            Text(DashboardView.short(today.work)).font(.system(size: 40, weight: .semibold)).tracking(-1.4)
                .foregroundStyle(LinearGradient(colors: [Arc.ink, Arc.ink.opacity(0.75)], startPoint: .top, endPoint: .bottom))
            if let delta {
                Text(delta).font(.system(size: 12, weight: .medium)).foregroundStyle(today.work >= yesterday.work ? Arc.green : Arc.rose)
            }
            HStack(spacing: 0) {
                metric(L("Aktiv", "Active"), DashboardView.short(today.total))
                Rectangle().fill(Arc.divider).frame(width: 1, height: 30)
                metric("Score", "\(today.score) %")
            }.padding(.top, 4)
        }
        .arcCard()
        .background {
            RadialGradient(colors: [Arc.glowCard, .clear], center: .topTrailing, startRadius: 0, endRadius: 190)
                .clipShape(RoundedRectangle(cornerRadius: Arc.panelRadius, style: .continuous))
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 11)).foregroundStyle(Arc.tertiary)
            Text(value).font(.system(size: 15, weight: .semibold)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Donut of the three categories with a legend that carries the minutes.
private struct SplitCard: View {
    let totals: UsageTotals

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardTitle(text: L("VERTEILUNG", "SPLIT"))
            HStack(spacing: 16) {
                ZStack {
                    let total = max(totals.total, 1)
                    let parts = [(totals.work, Arc.work), (totals.neutral, Arc.neutralTone), (totals.distraction, Arc.distraction)]
                    Circle().stroke(Arc.track, lineWidth: 11)
                    ForEach(0..<3, id: \.self) { index in
                        let start = parts.prefix(index).reduce(0) { $0 + $1.0 } / total
                        let end = start + parts[index].0 / total
                        Circle().trim(from: start, to: max(start, end - 0.006))
                            .stroke(parts[index].1, style: StrokeStyle(lineWidth: 11, lineCap: .butt))
                            .rotationEffect(.degrees(-90))
                    }
                    VStack(spacing: 0) {
                        Text("\(totals.score)").font(.system(size: 19, weight: .semibold)).monospacedDigit()
                        Text("Score").font(.system(size: 9.5)).foregroundStyle(Arc.tertiary)
                    }
                }.frame(width: 86, height: 86)
                VStack(alignment: .leading, spacing: 9) {
                    row(L("Arbeit", "Work"), totals.work, Arc.work)
                    row("Neutral", totals.neutral, Arc.neutralTone)
                    row(L("Ablenkung", "Distraction"), totals.distraction, Arc.distraction)
                }
            }
        }.arcCard()
    }

    private func row(_ name: String, _ seconds: Double, _ color: Color) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(name).font(.system(size: 12)).foregroundStyle(Arc.secondary)
            Spacer(minLength: 4)
            Text(DashboardView.short(seconds)).font(.system(size: 12, weight: .medium)).monospacedDigit()
        }
    }
}

private struct HabitCard: View {
    let model: ZoneModel
    var body: some View {
        HStack(spacing: 0) {
            stat(L("Sperrversuche", "Blocked attempts"), "\(model.attemptsToday.values.reduce(0, +))")
            Rectangle().fill(Arc.divider).frame(width: 1, height: 34)
            stat(L("Entsperrt", "Unlocked"), "\(model.unlocksToday)×")
        }.arcCard(padding: 14)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 11)).foregroundStyle(Arc.tertiary)
            Text(value).font(.system(size: 19, weight: .semibold)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 2)
    }
}

private struct FindingsCard: View {
    let lines: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle(text: L("AUFGEFALLEN", "NOTICED"))
            ForEach(lines, id: \.self) {
                Text($0).font(.system(size: 12.5)).foregroundStyle(Arc.ink.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
            }
        }.arcCard()
    }
}

private struct EntriesCard: View {
    let entries: [UsageItem]
    let store: InsightsStore
    private var total: Double { max(entries.reduce(0) { $0 + $1.seconds }, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CardTitle(text: L("APPS UND WEBSITES", "APPS AND WEBSITES"), trailing: "Top 14").padding(.bottom, 8)
            if entries.isEmpty { Text(L("Noch keine Daten für heute.", "No data for today yet.")).font(.system(size: 13)).foregroundStyle(Arc.secondary) }
            ForEach(entries.prefix(14)) { entry in
                EntryRow(entry: entry, share: entry.seconds / total, largest: entries.first?.seconds ?? 1, store: store,
                         pages: store.titles[entry.name] ?? [])
            }
            Text(store.titles.isEmpty ? L("Rechtsklick auf einen Eintrag ändert die Kategorie.", "Right-click an item to change its category.") : L("Klick auf eine Website zeigt die Seiten, Rechtsklick ändert die Kategorie.", "Click a website to see its pages, right-click to change the category.")).font(.system(size: 11)).foregroundStyle(Arc.tertiary).padding(.top, 6)
        }.arcCard()
    }
}

private struct EntryRow: View {
    let entry: UsageItem
    let share: Double
    let largest: Double
    let store: InsightsStore
    var pages: [(title: String, seconds: Double)] = []
    @State private var hovering = false
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row
            if expanded {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(pages.prefix(8).enumerated()), id: \.offset) { _, page in
                        HStack(spacing: 8) {
                            Text(page.title).font(.system(size: 12)).foregroundStyle(Arc.secondary).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 8)
                            if let rule = store.categories.titleMatch(domain: entry.name, title: page.title) {
                                Text(store.categories.path(rule)).font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(DashboardView.color(store.categories.rating(of: rule) ?? .neutral)).fixedSize()
                            }
                            Text(DashboardView.short(page.seconds)).font(.system(size: 11.5)).monospacedDigit().foregroundStyle(Arc.tertiary).fixedSize()
                        }
                    }
                }.padding(.leading, 47).padding(.trailing, 8).padding(.bottom, 6)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if !pages.isEmpty { withAnimation(.snappy(duration: 0.2)) { expanded.toggle() } } }
        .contextMenu { CategoryMenuItems(store: store, name: entry.name, isSite: entry.isSite) }
    }

    private var row: some View {
        HStack(spacing: 11) {
            ItemIcon(name: entry.name, isSite: entry.isSite)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.name.count > 30 ? entry.name.prefix(29) + "…" : entry.name)
                        .font(.system(size: 13, weight: .medium)).lineLimit(1).fixedSize()
                    Spacer(minLength: 8)
                    Text(DashboardView.short(entry.seconds)).font(.system(size: 12.5, weight: .medium)).monospacedDigit().fixedSize()
                    Text("\(Int((share * 100).rounded())) %").font(.system(size: 11.5)).monospacedDigit()
                        .foregroundStyle(Arc.tertiary).frame(width: 34, alignment: .trailing)
                }
                Text(store.categories.path(entry.groupID)).font(.system(size: 10.5)).foregroundStyle(Arc.tertiary).lineLimit(1)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Arc.track.opacity(0.6))
                        Capsule().fill(DashboardView.color(entry.category).gradient)
                            .frame(width: max(4, proxy.size.width * entry.seconds / max(largest, 1)))
                    }
                }.frame(height: 4)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .background(hovering ? Arc.muted.opacity(0.6) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering = $0 }
        .overlay(alignment: .trailing) {
            if !pages.isEmpty {
                Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Arc.tertiary).offset(x: 2)
            }
        }
    }
}

/// Real app icons; websites get a monogram so no favicon request ever leaves the Mac.
struct ItemIcon: View {
    let name: String
    let isSite: Bool
    @MainActor private static var cache: [String: NSImage] = [:]

    var body: some View {
        Group {
            if !isSite, let icon = Self.icon(for: name) {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Self.tint(for: name).gradient)
                    .overlay(Text(String(name.prefix(1)).uppercased()).font(.system(size: 13, weight: .bold)).foregroundStyle(.white))
            }
        }.frame(width: 28, height: 28)
    }

    private static func icon(for name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        let paths = ["/Applications/\(name).app", "/System/Applications/\(name).app", "/System/Applications/Utilities/\(name).app",
                     NSHomeDirectory() + "/Applications/\(name).app"]
        guard let path = paths.first(where: FileManager.default.fileExists) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache[name] = image
        return image
    }

    private static func tint(for name: String) -> Color {
        let hues: [Double] = [0.72, 0.58, 0.95, 0.08, 0.45, 0.83, 0.13]
        let index = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xffff } % hues.count
        return Color(hue: hues[index], saturation: 0.55, brightness: 0.72)
    }
}

/// Time per top category with its subcategories underneath.
private struct GroupsCard: View {
    let store: InsightsStore

    var body: some View {
        let config = store.categories
        let rows = config.tops.map { top -> (UsageGroup, Double, [(UsageGroup, Double)]) in
            let subs = config.children(of: top.id).map { ($0, store.byGroup[$0.id] ?? 0) }.filter { $0.1 >= 60 }.sorted { $0.1 > $1.1 }
            return (top, (store.byGroup[top.id] ?? 0) + subs.reduce(0) { $0 + $1.1 }, subs)
        }.filter { $0.1 >= 60 }.sorted { $0.1 > $1.1 }
        let open = store.byGroup[nil] ?? 0
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(text: L("KATEGORIEN", "CATEGORIES"))
            if rows.isEmpty && open < 60 { Text(L("Noch nichts erfasst.", "Nothing tracked yet.")).font(.system(size: 12.5)).foregroundStyle(Arc.secondary) }
            ForEach(rows, id: \.0.id) { top, seconds, subs in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 2).fill(DashboardView.color(top.rating)).frame(width: 8, height: 8)
                        Text(top.name).font(.system(size: 12.5, weight: .semibold))
                        Spacer()
                        Text(DashboardView.short(seconds)).font(.system(size: 12, weight: .medium)).monospacedDigit()
                    }
                    ForEach(subs, id: \.0.id) { sub, value in
                        HStack {
                            Text(sub.name).font(.system(size: 11.5)).foregroundStyle(Arc.secondary)
                            Spacer()
                            Text(DashboardView.short(value)).font(.system(size: 11.5)).monospacedDigit().foregroundStyle(Arc.tertiary)
                        }.padding(.leading, 15)
                    }
                }
            }
            if open >= 60 {
                HStack {
                    Text(L("Ohne Kategorie", "No category")).font(.system(size: 12)).foregroundStyle(Arc.tertiary)
                    Spacer()
                    Text(DashboardView.short(open)).font(.system(size: 12)).monospacedDigit().foregroundStyle(Arc.tertiary)
                }
            }
        }.arcCard()
    }
}
