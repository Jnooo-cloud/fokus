import SwiftUI
import ZoneCore

struct MainView: View {
    @Bindable var model: ZoneModel

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(model: model)
            Rectangle().fill(Arc.divider).frame(width: 1)
            Group {
                switch model.page {
                case .dashboard: DashboardView(model: model)
                case .report: ReportView(model: model)
                case .focus: FocusView(model: model)
                case .unlock: UnlockView(model: model)
                case .lists: BlockListsView(model: model)
                case .schedules: SchedulesView(model: model)
                case .categories: CategoriesView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                ZStack(alignment: .top) {
                    Arc.background
                    // A faint light source at the top keeps the dark surface from looking flat.
                    RadialGradient(colors: [Arc.glowPage, .clear], center: .top, startRadius: 0, endRadius: 520)
                        .frame(height: 420)
                }.ignoresSafeArea()
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Arc.sidebar.ignoresSafeArea())
        .frame(minWidth: 760, minHeight: 560)
        .sheet(item: $model.editingList) { BlockListEditor(model: model, list: $0) }
        .sheet(item: $model.editingSchedule) { ScheduleEditor(model: model, schedule: $0) }
        .modifier(ErrorPresenter(model: model))
        .modifier(ThemedWindow())
    }
}

private struct Sidebar: View {
    @Bindable var model: ZoneModel

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 9) {
                ZoneMark().frame(width: 20, height: 20)
                Text("Fokus").font(.system(size: 15, weight: .semibold)).tracking(-0.3).foregroundStyle(Arc.ink)
            }.padding(.horizontal, 10).padding(.top, 44).padding(.bottom, 16)
            // Day and week share one entry; the header switches between them.
            ForEach(ZoneModel.Page.allCases.filter { $0 != .report }) { page in
                SidebarRow(page: page, selected: model.page == page || (page == .dashboard && model.page == .report)) { model.page = page }
            }
            Spacer()
            SettingsLink {
                HStack(spacing: 9) {
                    Image(systemName: "gearshape").frame(width: 18)
                    Text("Einstellungen").lineLimit(1).fixedSize()
                    Spacer()
                }
                .font(.system(size: 12.5)).foregroundStyle(Arc.secondary)
                .padding(.horizontal, 10).padding(.vertical, 8).contentShape(Rectangle())
            }.buttonStyle(.plain)
            ThemeToggle()
            SidebarStatus(model: model)
        }
        .padding(10)
        .frame(width: 186)
        .background(Arc.sidebar)
    }
}

private struct SidebarRow: View {
    let page: ZoneModel.Page
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: page.symbol).frame(width: 18)
                Text(page.rawValue)
                Spacer()
            }
            .font(.system(size: 13, weight: selected ? .medium : .regular))
            .foregroundStyle(selected ? Arc.ink : Arc.secondary)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(selected ? Arc.muted : (hovering ? Arc.muted.opacity(0.55) : .clear),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
    }
}

private struct ThemeToggle: View {
    @AppStorage("theme") private var theme = ThemeChoice.dark
    var body: some View {
        Button { withAnimation(.easeInOut(duration: 0.2)) { theme = theme.next } } label: {
            HStack(spacing: 9) {
                Image(systemName: theme.symbol).frame(width: 18)
                Text("Design: \(theme.rawValue)")
                Spacer()
            }
            .font(.system(size: 12.5)).foregroundStyle(Arc.secondary)
            .padding(.horizontal, 10).padding(.vertical, 8).contentShape(Rectangle())
        }.buttonStyle(.plain).help("Zwischen System, Hell und Dunkel wechseln")
    }
}

private struct SidebarStatus: View {
    let model: ZoneModel

    private var title: String {
        if model.isHard { return "Hard Mode" }
        return model.activeSessions.isEmpty ? "Bereit" : "Fokus läuft"
    }
    private var color: Color {
        if model.isHard { return Arc.rose }
        return model.activeSessions.isEmpty ? Arc.neutral : Arc.green
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Arc.ink).lineLimit(1).fixedSize()
            Spacer()
            if !model.menuTitle.isEmpty {
                Text(model.menuTitle).font(.system(size: 11.5)).monospacedDigit().foregroundStyle(Arc.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(Arc.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Arc.border, lineWidth: 1))
    }
}
