import AppKit
import SwiftUI

/// Fokus' visual language: neutral surfaces, hairline borders, large radii and one soft gradient.
enum Arc {
    private static func dynamic(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
    private static func alpha(_ color: NSColor, _ light: CGFloat, _ dark: CGFloat) -> Color {
        dynamic(color.withAlphaComponent(light), color.withAlphaComponent(dark))
    }
    private static func gray(_ value: CGFloat) -> NSColor { NSColor(white: value, alpha: 1) }
    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(red: r, green: g, blue: b, alpha: 1) }

    static let background = dynamic(gray(1), rgb(0.047, 0.047, 0.063))
    static let sidebar = dynamic(gray(0.975), rgb(0.063, 0.063, 0.082))
    static let surface = dynamic(gray(1), rgb(0.086, 0.086, 0.11))
    static let muted = dynamic(gray(0.955), rgb(0.13, 0.13, 0.16))
    static let border = dynamic(gray(0.91), NSColor(white: 1, alpha: 0.075))
    static let ink = dynamic(gray(0.09), gray(0.96))
    static let secondary = dynamic(gray(0.4), gray(0.62))
    static let tertiary = dynamic(gray(0.55), gray(0.42))
    static let onInk = dynamic(gray(1), gray(0.06))
    static let track = dynamic(gray(0.9), rgb(0.15, 0.15, 0.19))

    /// Category colours: saturated enough to read at a glance on dark surfaces.
    static let work = dynamic(rgb(0.42, 0.33, 0.95), rgb(0.55, 0.48, 1.0))
    static let neutralTone = dynamic(gray(0.78), rgb(0.33, 0.35, 0.42))
    static let distraction = dynamic(rgb(0.93, 0.33, 0.33), rgb(1.0, 0.42, 0.42))
    static let glow = Color(red: 0.42, green: 0.3, blue: 1.0)
    static let glowPage = alpha(rgb(0.42, 0.3, 1.0), 0.07, 0.16)
    static let glowCard = alpha(rgb(0.42, 0.3, 1.0), 0.1, 0.28)
    static let shadow = alpha(.black, 0.06, 0.35)
    static let edgeTop = dynamic(gray(0.88), NSColor(white: 1, alpha: 0.11))
    static let edgeBottom = dynamic(gray(0.93), NSColor(white: 1, alpha: 0.035))
    static let divider = dynamic(gray(0.9), NSColor(white: 1, alpha: 0.06))

    static let green = dynamic(rgb(0.05, 0.48, 0.36), rgb(0.36, 0.83, 0.63))
    static let rose = dynamic(rgb(0.78, 0.2, 0.33), rgb(0.96, 0.48, 0.53))
    static let amber = dynamic(rgb(0.64, 0.4, 0.03), rgb(0.96, 0.77, 0.4))
    static let neutral = dynamic(gray(0.8), gray(0.36))

    static let gradientColors = [Color(red: 0.55, green: 0.45, blue: 1.0), Color(red: 1.0, green: 0.48, blue: 0.62)]
    static let gradient = LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing)
    static let inkGradient = LinearGradient(colors: [Color(red: 0.45, green: 0.35, blue: 0.68), Color(red: 0.72, green: 0.42, blue: 0.24)],
                                            startPoint: .leading, endPoint: .trailing)

    static let controlRadius: CGFloat = 14
    static let panelRadius: CGFloat = 20
}

struct ArcCard: ViewModifier {
    var padding: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Arc.surface, in: RoundedRectangle(cornerRadius: Arc.panelRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Arc.panelRadius, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Arc.edgeTop, Arc.edgeBottom], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: Arc.shadow, radius: 14, y: 6)
    }
}

extension View {
    func arcCard(padding: CGFloat = 18) -> some View { modifier(ArcCard(padding: padding)) }
}

struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 28, weight: .semibold)).tracking(-0.9).foregroundStyle(Arc.ink)
                if let subtitle { Text(subtitle).font(.system(size: 13)).foregroundStyle(Arc.secondary) }
            }
            Spacer()
            trailing
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct ArcButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet }
    var kind = Kind.secondary
    var wide = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(kind == .primary ? Arc.onInk : Arc.ink)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .frame(maxWidth: wide ? .infinity : nil)
            .background(background, in: RoundedRectangle(cornerRadius: Arc.controlRadius, style: .continuous))
            .overlay {
                if kind == .secondary {
                    RoundedRectangle(cornerRadius: Arc.controlRadius, style: .continuous).strokeBorder(Arc.border, lineWidth: 1)
                }
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: Arc.controlRadius, style: .continuous))
    }

    private var background: Color {
        switch kind {
        case .primary: Arc.ink
        case .secondary: Arc.surface
        case .quiet: Arc.muted
        }
    }
}

/// A pill row for picking one of a few values.
struct PillPicker<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.value) { option in
                Button { withAnimation(.snappy(duration: 0.2)) { selection = option.value } } label: {
                    Text(option.label).font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(selection == option.value ? Arc.ink : Arc.secondary)
                        .padding(.vertical, 7).frame(maxWidth: .infinity)
                        .background {
                            if selection == option.value {
                                RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Arc.surface)
                                    .shadow(color: Arc.shadow, radius: 2, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Arc.muted, in: RoundedRectangle(cornerRadius: Arc.controlRadius, style: .continuous))
    }
}

struct ChipRow: View {
    let chips: [(id: String?, label: String)]
    @Binding var selection: String?

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(chips, id: \.label) { chip in
                Button { selection = chip.id } label: {
                    Text(chip.label).font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(selection == chip.id ? Arc.onInk : Arc.ink)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(selection == chip.id ? Arc.ink : Arc.muted, in: Capsule())
                        .contentShape(Capsule())
                }.buttonStyle(.plain)
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
        }
        return CGSize(width: width, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += row + spacing; row = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}

/// Press and hold for `duration` to fire. Letting go early drains the bar and does nothing.
struct HoldToConfirm: View {
    let title: String
    var duration: Double = 1.5
    var tint: AnyShapeStyle = AnyShapeStyle(Arc.gradient)
    let action: () -> Void
    @State private var progress: CGFloat = 0
    @State private var holdTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Arc.controlRadius, style: .continuous).fill(Arc.muted)
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: Arc.controlRadius, style: .continuous).fill(tint)
                    .frame(width: proxy.size.width * progress)
            }
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Arc.ink)
        }
        .frame(height: 40)
        .clipShape(RoundedRectangle(cornerRadius: Arc.controlRadius, style: .continuous))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in begin() }.onEnded { _ in cancel() })
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }

    private func begin() {
        guard holdTask == nil else { return }
        withAnimation(.linear(duration: duration)) { progress = 1 }
        holdTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            action()
            progress = 0
        }
    }

    private func cancel() {
        holdTask?.cancel()
        holdTask = nil
        withAnimation(.easeOut(duration: 0.25)) { progress = 0 }
    }
}

struct CountdownRing: View {
    let fraction: Double
    let label: String
    var size: CGFloat = 132

    var body: some View {
        ZStack {
            Circle().stroke(Arc.track, lineWidth: 5)
            Circle().trim(from: 0, to: fraction)
                .stroke(AngularGradient(colors: Arc.gradientColors + [Arc.gradientColors[0]], center: .center),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: fraction)
            Text(label).font(.system(size: size * 0.3, weight: .light, design: .rounded)).monospacedDigit()
                .foregroundStyle(Arc.ink).contentTransition(.numericText(countsDown: true))
        }.frame(width: size, height: size)
    }
}

enum ThemeChoice: String, CaseIterable, Identifiable {
    case system = "System", light = "Hell", dark = "Dunkel"
    var id: Self { self }
    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
    var next: ThemeChoice {
        switch self {
        case .system: .light
        case .light: .dark
        case .dark: .system
        }
    }
}

/// Applies the theme picked in Fokus; every window uses it so they always match.
struct ThemedWindow: ViewModifier {
    @AppStorage("theme") private var theme = ThemeChoice.dark
    func body(content: Content) -> some View { content.preferredColorScheme(theme.scheme) }
}
