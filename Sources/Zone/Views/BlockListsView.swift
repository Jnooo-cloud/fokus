import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ZoneCore

struct BlockListsView: View {
    let model: ZoneModel
    @State private var deleting: BlockList?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PageHeader(title: "Sperrlisten", subtitle: "Was während einer Sitzung gesperrt ist.") {
                    Button("Neue Liste") { model.newList() }.buttonStyle(ArcButtonStyle(kind: .primary)).help("Neue Sperrliste (⌘N)")
                }
                if model.document.blockLists.isEmpty {
                    ContentUnavailableView {
                        Label("Keine Sperrlisten", systemImage: "hand.raised")
                    } description: {
                        Text("Wähle Websites und Apps, die in einer Sitzung gesperrt sind.")
                    }
                }
                ForEach(model.document.blockLists) { list in
                    BlockListRow(list: list, edit: { model.editingList = list }, duplicate: {
                        model.saveList(BlockList(name: list.name + " Kopie", domains: list.domains, apps: list.apps,
                                                 exceptions: list.exceptions, blocksEverything: list.blocksEverything))
                    }, delete: { deleting = list }).arcCard(padding: 6)
                }
                Text("Änderungen gelten für künftige Sitzungen.").font(.system(size: 11.5)).foregroundStyle(Arc.tertiary)
            }
            .padding(.horizontal, 32).padding(.top, 44).padding(.bottom, 28)
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .confirmationDialog("Diese Sperrliste löschen?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Liste löschen", role: .destructive) { if let deleting { model.deleteList(deleting) }; deleting = nil }
        }
    }
}

private struct BlockListRow: View {
    let list: BlockList
    let edit: () -> Void
    let duplicate: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button { edit() } label: {
                HStack(spacing: 14) {
                    Image(systemName: "hand.raised").font(.title2).foregroundStyle(.secondary)
                        .frame(width: 30).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(list.name).font(.headline)
                        RuleSummary(list: list)
                        if !list.isEmpty {
                            Text(((list.blocksEverything ? ["Alle Websites"] : list.domains) + list.apps.map(\.name)).joined(separator: ", "))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 12)
                    Image(systemName: "chevron.right").font(.caption.weight(.medium))
                        .foregroundStyle(.tertiary).accessibilityHidden(true)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(list.name)")
            .accessibilityValue(RuleSummary.text(for: list))
            .contextMenu {
                Button("Duplizieren") { duplicate() }
                Button("Löschen", role: .destructive) { delete() }
            }
            Menu {
                Button("Duplizieren") { duplicate() }
                Button("Löschen", role: .destructive) { delete() }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22)
            .accessibilityLabel("Actions for \(list.name)").help("Weitere Aktionen")
        }.padding(.horizontal, 10).padding(.vertical, 8).accessibilityElement(children: .contain)
    }
}

struct BlockListEditor: View {
    let model: ZoneModel
    @Environment(\.dismiss) private var dismiss
    @State private var list: BlockList
    @State private var websiteInput = ""
    @State private var exceptionInput = ""
    @State private var error: String?
    @State private var editingApps = false

    init(model: ZoneModel, list: BlockList) {
        self.model = model
        _list = State(initialValue: list)
    }

    private var isNew: Bool { !model.document.blockLists.contains { $0.id == list.id && !$0.isEmpty } }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(isNew ? "Neue Sperrliste" : "Sperrliste bearbeiten").font(.title2.weight(.semibold))
            LabeledContent("Name") {
                TextField("Listenname", text: $list.name).textFieldStyle(.roundedBorder)
            }
            Picker("Regeln", selection: $editingApps) {
                Text("Websites").tag(false)
                Text("Apps").tag(true)
            }.pickerStyle(.segmented).labelsHidden()
            Group {
                if !editingApps {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Alles sperren außer Ausnahmen", isOn: $list.blocksEverything).toggleStyle(.switch).controlSize(.small)
                        HStack {
                            TextField("youtube.com, reddit.com…", text: $websiteInput).textFieldStyle(.roundedBorder).onSubmit(addWebsites)
                            Button("Hinzufügen", action: addWebsites).disabled(websiteInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        Text("Domains gelten samt Subdomains. Mehrere mit Komma oder Leerzeichen trennen.")
                            .font(.caption).foregroundStyle(.secondary)
                        List {
                            ForEach(list.domains, id: \.self) { domain in
                                HStack {
                                    Label(domain, systemImage: "globe")
                                    Spacer()
                                    Button { list.domains.removeAll { $0 == domain } } label: { Image(systemName: "minus.circle") }
                                        .buttonStyle(.borderless).accessibilityLabel("Remove \(domain)")
                                }
                            }
                        }.overlay { if list.domains.isEmpty { Text("Keine Websites eingetragen").foregroundStyle(.secondary) } }
                        HStack {
                            TextField("Ausnahme, z. B. business.facebook.com", text: $exceptionInput).textFieldStyle(.roundedBorder).onSubmit(addExceptions)
                            Button("Erlauben", action: addExceptions).disabled(exceptionInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        ForEach(list.exceptions, id: \.self) { domain in
                            HStack {
                                Label(domain, systemImage: "checkmark.circle").font(.callout)
                                Spacer()
                                Button { list.exceptions.removeAll { $0 == domain } } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.borderless).accessibilityLabel("Remove \(domain)")
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Apps schließen beim Sitzungsstart oder wenn du sie öffnest.").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Apps hinzufügen…", systemImage: "plus", action: addApps)
                        }
                        List {
                            ForEach(list.apps) { app in
                                HStack {
                                    AppIcon(app: app)
                                    Text(app.name).help(app.bundleID)
                                    Spacer()
                                    Button { list.apps.removeAll { $0.id == app.id } } label: { Image(systemName: "minus.circle") }
                                        .buttonStyle(.borderless).accessibilityLabel("Remove \(app.name)")
                                }
                            }
                        }.overlay { if list.apps.isEmpty { Text("Keine Apps eingetragen").foregroundStyle(.secondary) } }
                        Text("Vorher speichern: Fokus kann gewählte Apps sofort beenden, Ungespeichertes geht dann verloren.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.frame(height: 360)
            if let error { Text(error).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Text("Änderungen gelten für künftige Sitzungen.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Abbrechen") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Speichern") {
                    if !websiteInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { addWebsites(); if error != nil { return } }
                    list.name = list.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if model.saveList(list) { dismiss() }
                    else { error = model.errorMessage; model.errorMessage = nil }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(list.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || (list.isEmpty && websiteInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }.padding(24).frame(width: 560)
    }

    private func addWebsites() {
        do {
            list.domains = Array(Set(list.domains).union(try DomainRule.parseList(websiteInput))).sorted()
            websiteInput = ""
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func addExceptions() {
        do {
            list.exceptions = Array(Set(list.exceptions).union(try DomainRule.parseList(exceptionInput))).sorted()
            exceptionInput = ""
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func addApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Apps hinzufügen"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { continue }
            guard !AppBlocker.protectedIDs.contains(id) else { error = "Fokus lässt wichtige System-Apps immer offen."; continue }
            guard !list.apps.contains(where: { $0.bundleID == id }) else { continue }
            let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? url.deletingPathExtension().lastPathComponent
            list.apps.append(BlockedApp(bundleID: id, name: name, path: url.path))
        }
        list.apps.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
