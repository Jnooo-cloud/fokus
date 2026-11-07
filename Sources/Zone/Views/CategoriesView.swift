import SwiftUI
import ZoneCore

/// Assign-to-category entries for menus. Picking a top group files the item there directly.
struct CategoryMenuItems: View {
    let store: InsightsStore
    let name: String
    let isSite: Bool

    var body: some View {
        let config = store.categories
        ForEach(config.tops) { top in
            Menu(top.name) {
                Button("\(top.name) (allgemein)") { assign(top.id) }
                ForEach(config.children(of: top.id)) { child in
                    Button(child.name) { assign(child.id) }
                }
            }
        }
        Divider()
        Button("Ohne Kategorie") { assign(nil) }
    }

    private func assign(_ id: UUID?) { store.updateCategories { $0.assign(name: name, isSite: isSite, to: id) } }
}

struct CategoriesView: View {
    let model: ZoneModel
    private var store: InsightsStore { model.insights }
    @State private var search = ""
    @State private var onlyOpen = false
    @State private var newTop = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Kategorien", subtitle: "Oberkategorien bestimmen, was als Arbeit, Neutral oder Ablenkung zählt. Unterkategorien sortieren feiner.")
                ForEach(store.categories.tops) { top in
                    GroupCard(store: store, top: top)
                }
                HStack(spacing: 8) {
                    TextField("Neue Oberkategorie, z. B. Lernen", text: $newTop).textFieldStyle(.plain).font(.system(size: 13))
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(Arc.muted, in: RoundedRectangle(cornerRadius: Arc.controlRadius, style: .continuous))
                        .onSubmit(addTop)
                    Button("Hinzufügen", action: addTop).buttonStyle(ArcButtonStyle(kind: .primary))
                        .disabled(newTop.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                TitleRulesCard(store: store)
                assignments
            }
            .padding(.horizontal, 32).padding(.top, 44).padding(.bottom, 28)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .onAppear { store.refresh(blockedDomains: model.allBlockedDomains); store.loadRecent() }
    }

    private func addTop() {
        let name = newTop.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        store.updateCategories { $0.addGroup(name: name, rating: .neutral) }
        newTop = ""
    }

    private var filtered: [UsageItem] {
        store.recent.filter { item in
            (!onlyOpen || store.categories.assignment(name: item.name, isSite: item.isSite) == nil)
                && (search.isEmpty || item.name.localizedCaseInsensitiveContains(search))
        }
    }

    private var assignments: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ZUORDNUNG · LETZTE 30 TAGE").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Arc.secondary)
                Spacer()
                Toggle("Nur ohne Kategorie", isOn: $onlyOpen).toggleStyle(.switch).controlSize(.mini).font(.system(size: 12))
            }
            TextField("Suchen", text: $search).textFieldStyle(.plain).font(.system(size: 13))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Arc.muted, in: RoundedRectangle(cornerRadius: Arc.controlRadius, style: .continuous))
            if filtered.isEmpty {
                Text(onlyOpen ? "Alles ist einsortiert." : "Nichts gefunden.").font(.system(size: 13)).foregroundStyle(Arc.secondary).padding(.vertical, 8)
            }
            ForEach(filtered.prefix(60)) { item in
                HStack(spacing: 11) {
                    ItemIcon(name: item.name, isSite: item.isSite)
                    Text(item.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(DashboardView.short(item.seconds)).font(.system(size: 12)).monospacedDigit().foregroundStyle(Arc.tertiary)
                    Menu {
                        CategoryMenuItems(store: store, name: item.name, isSite: item.isSite)
                    } label: {
                        let id = store.categories.assignment(name: item.name, isSite: item.isSite)
                        HStack(spacing: 6) {
                            Circle().fill(DashboardView.color(store.categories.rating(of: id) ?? .neutral)).frame(width: 7, height: 7)
                            Text(store.categories.path(id)).font(.system(size: 12, weight: .medium))
                                .foregroundStyle(id == nil ? Arc.tertiary : Arc.ink)
                        }
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.visible).fixedSize()
                }.padding(.vertical, 3)
            }
            if filtered.count > 60 { Text("Weitere über die Suche finden.").font(.system(size: 11.5)).foregroundStyle(Arc.tertiary) }
        }.arcCard()
    }
}

private struct GroupCard: View {
    let store: InsightsStore
    let top: UsageGroup
    @State private var name = ""
    @State private var newChild = ""
    @State private var confirmDelete = false

    private var count: Int { store.categories.assignments.values.filter { id in id == top.id || store.categories.group(id)?.parentID == top.id }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle().fill(DashboardView.color(top.rating)).frame(width: 10, height: 10)
                TextField("Name", text: $name).textFieldStyle(.plain).font(.system(size: 15, weight: .semibold))
                    .onSubmit { store.updateCategories { $0.rename(top.id, to: name.trimmingCharacters(in: .whitespaces)) } }
                Text("\(count) zugeordnet").font(.system(size: 11.5)).foregroundStyle(Arc.tertiary).fixedSize()
                Button { confirmDelete = true } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).foregroundStyle(Arc.tertiary).help("Oberkategorie löschen")
            }
            HStack(spacing: 10) {
                Text("Zählt als").font(.system(size: 12)).foregroundStyle(Arc.secondary)
                PillPicker(options: UsageCategory.allCases.map { ($0, $0.rawValue) },
                           selection: Binding(get: { top.rating }, set: { rating in store.updateCategories { $0.setRating(top.id, rating) } }))
                    .frame(maxWidth: 330)
            }
            FlowLayout(spacing: 6) {
                ForEach(store.categories.children(of: top.id)) { child in
                    HStack(spacing: 5) {
                        Text(child.name).font(.system(size: 12.5, weight: .medium))
                        Button { store.updateCategories { $0.delete(child.id) } } label: {
                            Image(systemName: "xmark").font(.system(size: 8.5, weight: .bold))
                        }.buttonStyle(.plain).foregroundStyle(Arc.tertiary).help("Unterkategorie löschen, Einträge wandern nach \(top.name)")
                    }
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(Arc.muted, in: Capsule())
                }
                TextField("+ Unterkategorie", text: $newChild).textFieldStyle(.plain).font(.system(size: 12.5))
                    .frame(width: 130).padding(.horizontal, 11).padding(.vertical, 6)
                    .overlay(Capsule().strokeBorder(Arc.border, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                    .onSubmit {
                        let value = newChild.trimmingCharacters(in: .whitespaces)
                        guard !value.isEmpty else { return }
                        store.updateCategories { $0.addGroup(name: value, rating: top.rating, parentID: top.id) }
                        newChild = ""
                    }
            }
        }
        .arcCard()
        .onAppear { name = top.name }
        .onChange(of: top.name) { _, value in name = value }
        .confirmationDialog("\(top.name) löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { store.updateCategories { $0.delete(top.id) } }
        } message: { Text("Unterkategorien gehen mit. Zugeordnete Apps und Websites stehen danach ohne Kategorie da.") }
    }
}

/// Picks a category, shown as its path; used where a plain picker would flatten the hierarchy.
struct CategoryPicker: View {
    let store: InsightsStore
    @Binding var selection: UUID?

    var body: some View {
        Menu {
            ForEach(store.categories.tops) { top in
                Menu(top.name) {
                    Button("\(top.name) (allgemein)") { selection = top.id }
                    ForEach(store.categories.children(of: top.id)) { child in Button(child.name) { selection = child.id } }
                }
            }
        } label: {
            Text(selection == nil ? "Kategorie wählen" : store.categories.path(selection)).font(.system(size: 12.5, weight: .medium))
        }.menuStyle(.borderlessButton).fixedSize()
    }
}

private struct TitleRulesCard: View {
    let store: InsightsStore
    @AppStorage(UsageTracker.titlesKey) private var trackTitles = false
    @State private var domain = ""
    @State private var keyword = ""
    @State private var target: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(text: "REGELN NACH SEITENTITEL")
            Text("Sortiert einzelne Seiten anders als ihre Website. Beispiel: Auf youtube.com zählt alles mit „Tutorial“ im Titel als Recherche statt Entertainment.")
                .font(.system(size: 12.5)).foregroundStyle(Arc.secondary).fixedSize(horizontal: false, vertical: true)
            if !trackTitles {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(Arc.amber)
                    Text("Die Seitentitel-Erfassung ist aus. Regeln greifen erst für Zeit, die mit Titeln erfasst wurde.")
                        .font(.system(size: 12)).foregroundStyle(Arc.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Einschalten") { trackTitles = true }.buttonStyle(ArcButtonStyle(kind: .quiet))
                }
                .padding(10).background(Arc.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            ForEach(store.categories.titleRules) { rule in
                HStack(spacing: 6) {
                    Text(rule.domain ?? "Alle Websites").font(.system(size: 12.5, weight: .semibold))
                    Text("· Titel enthält").font(.system(size: 12.5)).foregroundStyle(Arc.secondary)
                    Text("„\(rule.keyword)“").font(.system(size: 12.5, weight: .semibold))
                    Image(systemName: "arrow.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Arc.tertiary)
                    Text(store.categories.path(rule.groupID)).font(.system(size: 12.5, weight: .medium))
                    Spacer()
                    Button { store.updateCategories { config in config.titleRules.removeAll { $0.id == rule.id } } } label: {
                        Image(systemName: "trash")
                    }.buttonStyle(.borderless).foregroundStyle(Arc.tertiary).help("Regel löschen")
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Arc.muted.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            HStack(spacing: 8) {
                field("youtube.com (leer = alle)", text: $domain).frame(width: 190)
                field("Stichwort, z. B. Tutorial", text: $keyword)
                CategoryPicker(store: store, selection: $target)
                Button("Regel anlegen", action: add).buttonStyle(ArcButtonStyle(kind: .primary))
                    .disabled(keyword.trimmingCharacters(in: .whitespaces).isEmpty || target == nil || domainInvalid)
            }
            if domainInvalid { Text("Das ist keine gültige Domain.").font(.system(size: 11.5)).foregroundStyle(Arc.distraction) }
        }.arcCard()
    }

    private var domainInvalid: Bool {
        let value = domain.trimmingCharacters(in: .whitespaces)
        return !value.isEmpty && (try? DomainRule.normalize(value)) == nil
    }

    private func add() {
        guard let target else { return }
        let value = domain.trimmingCharacters(in: .whitespaces)
        let rule = TitleRule(domain: value.isEmpty ? nil : try? DomainRule.normalize(value),
                             keyword: keyword.trimmingCharacters(in: .whitespaces), groupID: target)
        store.updateCategories { $0.titleRules.append(rule) }
        keyword = ""
    }

    private func field(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text).textFieldStyle(.plain).font(.system(size: 12.5))
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(Arc.muted, in: RoundedRectangle(cornerRadius: Arc.controlRadius, style: .continuous))
    }
}
