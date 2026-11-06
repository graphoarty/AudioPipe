import SwiftUI

// A small flat design system: square corners everywhere, no pills, no round
// knobs. Fills and 1 px hairlines instead of bezels and shadows.

enum Theme {
    static let accent = Color(red: 0.31, green: 0.45, blue: 1.00)
    static let playing = Color(red: 0.16, green: 0.80, blue: 0.56)
    static let connected = Color(red: 0.36, green: 0.62, blue: 1.00)
    static let warning = Color(red: 1.00, green: 0.70, blue: 0.20)
    static let danger = Color(red: 0.96, green: 0.33, blue: 0.31)
    static let mute = Color(red: 1.00, green: 0.62, blue: 0.18)
    static let solo = Color(red: 0.98, green: 0.82, blue: 0.20)

    static let fill = Color.primary.opacity(0.055)
    static let fillHover = Color.primary.opacity(0.10)
    static let fillPressed = Color.primary.opacity(0.16)
    static let hairline = Color.primary.opacity(0.10)
    static let track = Color.primary.opacity(0.12)

    static func color(for state: SlotState) -> Color {
        switch state {
        case .playing: return playing
        case .connected: return connected
        case .starting: return warning
        case .failed: return danger
        case .off: return Color.primary.opacity(0.18)
        }
    }

    static let mono = Font.system(size: 11, weight: .regular, design: .monospaced)
    static let caption = Font.system(size: 11)
    static let label = Font.system(size: 12, weight: .medium)
    static let sectionTitle = Font.system(size: 10, weight: .semibold)
}

// MARK: - Buttons

struct FlatButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, ghost, danger }
    var kind: Kind = .secondary
    var compact = false
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        FlatButtonBody(configuration: configuration, kind: kind, compact: compact, fullWidth: fullWidth)
    }
}

private struct FlatButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let kind: FlatButtonStyle.Kind
    let compact: Bool
    let fullWidth: Bool
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(compact ? Theme.caption.weight(.medium) : Theme.label)
            .lineLimit(1)
            .padding(.horizontal, compact ? 8 : 12)
            .padding(.vertical, compact ? 4 : 6)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .foregroundStyle(foreground)
            .background(Rectangle().fill(background))
            .overlay(Rectangle().strokeBorder(border, lineWidth: 1))
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return .white
        case .danger: return Theme.danger
        case .secondary, .ghost: return .primary
        }
    }

    private var background: Color {
        let pressed = configuration.isPressed
        switch kind {
        case .primary:
            return Theme.accent.opacity(pressed ? 0.75 : hovering ? 0.9 : 1)
        case .secondary:
            return pressed ? Theme.fillPressed : hovering ? Theme.fillHover : Theme.fill
        case .ghost:
            return pressed ? Theme.fillPressed : hovering ? Theme.fill : .clear
        case .danger:
            return Theme.danger.opacity(pressed ? 0.22 : hovering ? 0.16 : 0.10)
        }
    }

    private var border: Color {
        switch kind {
        case .secondary: return Theme.hairline
        default: return .clear
        }
    }
}

/// Square icon button (e.g. gear, close).
struct FlatIconButton: View {
    let systemImage: String
    let help: String
    var size: CGFloat = 24
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .frame(width: size, height: size)
                .background(Rectangle().fill(hovering ? Theme.fillHover : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Square latching button such as M (mute) and S (solo).
struct FlatLatchButton: View {
    let title: String
    let isOn: Bool
    let onColor: Color
    let accessibilityLabel: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .frame(width: 22, height: 20)
                .foregroundStyle(isOn ? Color.black.opacity(0.85) : Color.primary.opacity(0.7))
                .background(Rectangle().fill(isOn ? onColor : (hovering ? Theme.fillHover : Theme.fill)))
                .overlay(Rectangle().strokeBorder(isOn ? Color.clear : Theme.hairline, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

// MARK: - Switch

/// Rectangular switch: square track, square knob.
struct FlatSwitchStyle: ToggleStyle {
    var tint: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.label
            Spacer(minLength: 0)
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Rectangle()
                    .fill(configuration.isOn ? tint : Theme.track)
                    .frame(width: 30, height: 16)
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .padding(2)
                    .shadow(color: .black.opacity(0.15), radius: 0.5, y: 0.5)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.14)) { configuration.isOn.toggle() }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
        .accessibilityAction { configuration.isOn.toggle() }
    }
}

// MARK: - Slider

/// Flat slider: thin rectangular track with a fill and a narrow bar thumb.
struct FlatSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var step: Double? = nil
    var tint: Color = Theme.accent
    var accessibilityLabel: String
    var accessibilityValueText: ((Double) -> String)? = nil
    var onEditingEnded: (() -> Void)? = nil
    @State private var hovering = false
    @State private var dragging = false

    private var fraction: Double {
        guard range.upperBound > range.lowerBound else { return 0 }
        return (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    var body: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width)
            let x = CGFloat(fraction) * w
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.track).frame(height: 4)
                Rectangle().fill(tint).frame(width: x, height: 4)
                Rectangle()
                    .fill(Color.primary.opacity(hovering || dragging ? 0.95 : 0.8))
                    .frame(width: 4, height: hovering || dragging ? 14 : 12)
                    .offset(x: min(max(0, x - 2), w - 4))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        dragging = true
                        set(fraction: Double(g.location.x / w))
                    }
                    .onEnded { _ in
                        dragging = false
                        onEditingEnded?()
                    }
            )
        }
        .frame(height: 18)
        .onHover { hovering = $0 }
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValueText?(value) ?? "\(Int((fraction * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            let delta = step ?? (range.upperBound - range.lowerBound) / 20
            switch direction {
            case .increment: value = min(range.upperBound, value + delta)
            case .decrement: value = max(range.lowerBound, value - delta)
            @unknown default: break
            }
            onEditingEnded?()
        }
    }

    private func set(fraction f: Double) {
        var v = range.lowerBound + min(max(f, 0), 1) * (range.upperBound - range.lowerBound)
        if let step { v = (v / step).rounded() * step }
        value = min(max(v, range.lowerBound), range.upperBound)
    }
}

// MARK: - Level meter

/// Segmented horizontal meter, -60…0 dBFS. RMS fills, peak shows as a tick.
struct LevelMeter: View {
    var rmsDB: Float
    var peakDB: Float
    var dimmed = false
    var segments = 28
    var accessibilityLabel: String

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 1.5
            let segW = (geo.size.width - gap * CGFloat(segments - 1)) / CGFloat(segments)
            let lit = litCount(rmsDB)
            let peak = litCount(peakDB)
            HStack(spacing: gap) {
                ForEach(0..<segments, id: \.self) { i in
                    Rectangle()
                        .fill(color(for: i).opacity(segmentOpacity(i, lit: lit, peak: peak)))
                        .frame(width: max(1, segW))
                }
            }
        }
        .frame(height: 5)
        .saturation(dimmed ? 0 : 1)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(peakDB <= -59 ? "Silent" : "\(Int(peakDB)) decibels")
    }

    private func litCount(_ db: Float) -> Int {
        Int(((max(-60, min(0, db)) + 60) / 60 * Float(segments)).rounded())
    }

    private func segmentOpacity(_ i: Int, lit: Int, peak: Int) -> Double {
        if i < lit { return 1 }
        if i == peak - 1 && peak > 0 { return 0.9 }
        return 0.13
    }

    private func color(for i: Int) -> Color {
        let f = Double(i) / Double(segments)
        if f > 0.9 { return Theme.danger }
        if f > 0.75 { return Theme.solo }
        return Theme.playing
    }
}

// MARK: - Dropdown

/// Flat dropdown: a rectangular field that opens a list of flat rows.
struct FlatDropdown<Option: Hashable>: View {
    let options: [Option]
    let selection: Option
    let title: (Option) -> String
    let onSelect: (Option) -> Void
    var accessibilityLabel: String
    var icon: String? = nil
    @State private var open = false
    @State private var hovering = false

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Text(title(selection)).font(Theme.label).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(open ? 180 : 0))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Rectangle().fill(hovering || open ? Theme.fillHover : Theme.fill))
            .overlay(Rectangle().strokeBorder(Theme.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(title(selection))
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(options, id: \.self) { option in
                    FlatMenuRow(title: title(option), selected: option == selection) {
                        onSelect(option)
                        open = false
                    }
                }
            }
            .padding(4)
            .frame(minWidth: 240)
        }
    }
}

struct FlatMenuRow: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(selected ? Theme.accent : Color.clear)
                    .frame(width: 3, height: 14)
                Text(title).font(Theme.label).lineLimit(1)
                Spacer()
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Rectangle().fill(hovering ? Theme.accent.opacity(0.15) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Stepper, text field, tabs, section

struct FlatStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var accessibilityLabel: String

    var body: some View {
        HStack(spacing: 0) {
            stepButton("minus", enabled: value > range.lowerBound) { value -= 1 }
            Text("\(value)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .frame(width: 34, height: 24)
                .background(Rectangle().fill(Theme.fill))
            stepButton("plus", enabled: value < range.upperBound) { value += 1 }
        }
        .overlay(Rectangle().strokeBorder(Theme.hairline, lineWidth: 1))
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { d in
            if d == .increment, value < range.upperBound { value += 1 }
            if d == .decrement, value > range.lowerBound { value -= 1 }
        }
    }

    private func stepButton(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold)).frame(width: 26, height: 24)
        }
        .buttonStyle(FlatPlainHover())
        .disabled(!enabled)
    }
}

/// Hover/press fill only, no padding: for buttons that size themselves.
struct FlatPlainHover: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration)
    }
    private struct HoverBody: View {
        let configuration: ButtonStyle.Configuration
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled
        var body: some View {
            configuration.label
                .background(Rectangle().fill(configuration.isPressed ? Theme.fillPressed : hovering ? Theme.fillHover : Color.clear))
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.35)
                .onHover { hovering = $0 }
        }
    }
}

struct FlatTextField: View {
    let placeholder: String
    @Binding var text: String
    var monospaced = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(monospaced ? Theme.mono : Theme.label)
            .focused($focused)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Rectangle().fill(Theme.fill))
            .overlay(Rectangle().strokeBorder(focused ? Theme.accent : Theme.hairline, lineWidth: 1))
    }
}

struct FlatTabBar<Tab: Hashable & Identifiable>: View {
    let tabs: [Tab]
    @Binding var selection: Tab
    let title: (Tab) -> String
    let icon: (Tab) -> String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                FlatTabButton(title: title(tab), icon: icon(tab), selected: tab == selection) {
                    selection = tab
                }
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}

private struct FlatTabButton: View {
    let title: String
    let icon: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 15, weight: .regular))
                Text(title).font(Theme.caption.weight(.medium))
            }
            .foregroundStyle(selected ? Theme.accent : Color.primary.opacity(0.75))
            .frame(width: 92, height: 50)
            .background(Rectangle().fill(hovering && !selected ? Theme.fill : Color.clear))
            .overlay(alignment: .bottom) {
                Rectangle().fill(selected ? Theme.accent : Color.clear).frame(height: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(Theme.sectionTitle)
            .tracking(0.8)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(Theme.hairline).frame(height: 1) }
}

/// A flat card: subtle fill, square corners.
struct FlatCard<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Rectangle().fill(Theme.fill))
    }
}

/// Square status chip.
struct StatusDot: View {
    let color: Color
    var pulsing = false
    @State private var phase = false
    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: 7, height: 7)
            .opacity(pulsing ? (phase ? 0.35 : 1) : 1)
            .onAppear {
                guard pulsing else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { phase = true }
            }
    }
}
