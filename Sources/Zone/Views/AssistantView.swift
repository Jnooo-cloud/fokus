import SwiftUI
import ZoneCore

struct AssistantView: View {
    let model: ZoneModel
    private var store: AssistantStore { model.assistant }
    @State private var input = ""
    @FocusState private var typing: Bool

    private var suggestions: [String] {
        [L("Was fällt dir an meiner Woche auf?", "What stands out about my week?"),
         L("Wann bin ich am unkonzentriertesten?", "When am I least focused?"),
         L("Was sollte ich sperren?", "What should I block?"),
         L("Warum entsperre ich so oft?", "Why do I unlock so often?")]
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: L("Assistent", "Assistant"),
                       subtitle: L("Frag nach deinen Mustern. Claude Code sieht dabei nur deine Fokus-Daten.",
                                   "Ask about your patterns. Claude Code only sees your Fokus data.")) {
                if !store.messages.isEmpty {
                    Button(L("Neuer Chat", "New Chat")) { store.reset() }.buttonStyle(ArcButtonStyle(kind: .quiet))
                }
            }
            .padding(.horizontal, 32).padding(.top, 44).padding(.bottom, 12)
            .frame(maxWidth: 760)

            ScrollViewReader { scroller in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if store.messages.isEmpty { start }
                        ForEach(store.messages) { message in Bubble(message: message, store: store).id(message.id) }
                    }
                    .padding(.horizontal, 32).padding(.vertical, 12)
                    .frame(maxWidth: 760).frame(maxWidth: .infinity)
                }
                .onChange(of: store.messages) { _, messages in
                    if let last = messages.last { withAnimation { scroller.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            composer
        }
    }

    private var start: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").foregroundStyle(Arc.work)
                Text(store.claudePath == nil ? L("Claude Code nicht gefunden", "Claude Code not found") : L("Agent: Claude Code", "Agent: Claude Code"))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(L("Codex und Ollama folgen", "Codex and Ollama coming")).font(.system(size: 11.5)).foregroundStyle(Arc.tertiary)
            }
            FlowLayout(spacing: 8) {
                ForEach(suggestions, id: \.self) { question in
                    Button(question) { store.send(question) }
                        .buttonStyle(ArcButtonStyle(kind: .secondary))
                }
            }
            Text(L("Läuft über dein Claude-Konto. Was Claude abfragt, geht an Anthropic: Zeiten pro App und Website, Entsperr-Gründe, Einstellungen. Der Assistent kann nichts ändern.",
                   "Runs on your Claude account. What Claude looks up goes to Anthropic: time per app and website, unlock reasons, settings. The assistant can’t change anything."))
                .font(.system(size: 11.5)).foregroundStyle(Arc.tertiary).fixedSize(horizontal: false, vertical: true)
        }.arcCard()
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if store.running {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(store.lookingAt.map { L("Schaut sich \($0) an…", "Looking at \($0)…") } ?? L("Denkt nach…", "Thinking…"))
                        .font(.system(size: 12)).foregroundStyle(Arc.secondary)
                    Spacer()
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField(L("Frag etwas über deine Zeit…", "Ask something about your time…"), text: $input, axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 13.5)).lineLimit(1...5)
                    .focused($typing)
                    .onSubmit(send)
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(Arc.surface, in: RoundedRectangle(cornerRadius: Arc.controlRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Arc.controlRadius, style: .continuous).strokeBorder(Arc.border, lineWidth: 1))
                if store.running {
                    Button { store.stop() } label: { Image(systemName: "stop.fill") }.buttonStyle(ArcButtonStyle(kind: .quiet))
                        .help(L("Abbrechen", "Stop"))
                } else {
                    Button(action: send) { Image(systemName: "arrow.up") }.buttonStyle(ArcButtonStyle(kind: .primary))
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
        .padding(.horizontal, 32).padding(.vertical, 16)
        .frame(maxWidth: 760).frame(maxWidth: .infinity)
        .background(Arc.background.opacity(0.92))
        .onAppear { typing = true }
    }

    private func send() {
        let text = input
        input = ""
        store.send(text)
    }
}

private struct Bubble: View {
    let message: AssistantStore.Message
    let store: AssistantStore

    private var rendered: AttributedString {
        (try? AttributedString(markdown: message.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(message.text)
    }

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 80) }
            Group {
                if message.role == .assistant && message.text.isEmpty {
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text("…").foregroundStyle(Arc.tertiary) }
                } else {
                    Text(rendered).font(.system(size: 13.5)).lineSpacing(3).textSelection(.enabled)
                        .foregroundStyle(message.role == .user ? Arc.onInk : (message.failed ? Arc.distraction : Arc.ink))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(message.role == .user ? Arc.ink : Arc.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                if message.role == .assistant {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Arc.border, lineWidth: 1)
                }
            }
            if message.role == .assistant { Spacer(minLength: 80) }
        }
    }
}
