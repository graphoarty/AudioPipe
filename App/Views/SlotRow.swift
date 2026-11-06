import SwiftUI

struct SlotRow: View {
    let slot: SlotModel
    let model: AppModel
    @State private var hovering = false

    private var stateColor: Color { Theme.color(for: slot.state) }
    private var silenced: Bool { slot.muted || (model.anySolo && !slot.solo) }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(stateColor)
                .frame(width: 3)
                .animation(.easeOut(duration: 0.25), value: slot.state)

            VStack(alignment: .leading, spacing: 8) {
                topLine
                if case .failed(let reason) = slot.state {
                    Text(reason).font(Theme.caption).foregroundStyle(Theme.danger).lineLimit(3)
                }
                LevelMeter(rmsDB: slot.rmsDB, peakDB: slot.peakDB, dimmed: silenced,
                           accessibilityLabel: "\(slot.accessibilityName) level")
                controls
            }
            .padding(.leading, 11)
            .padding(.trailing, 14)
            .padding(.vertical, 11)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(hovering ? 0.55 : 0.4))
        .background(.background.opacity(0.0001))
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Restart Capture") { model.restartCapture() }
            Button("Show Logs") { WindowManager.shared.showSettings(model: model, tab: .diagnostics) }
        }
    }

    private var topLine: some View {
        HStack(spacing: 8) {
            Image(systemName: slot.symbol)
                .font(.system(size: 14, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    StatusDot(color: stateColor, pulsing: slot.state == .starting)
                    Text(slot.statusText)
                        .font(Theme.caption)
                        .foregroundStyle(slot.state == .playing ? Color.primary : .secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            if slot.state == .playing || slot.state == .connected {
                Text("+\(Int(slot.addedLatencyMs)) ms")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .help("Delay the Mac adds (ring buffer + output device latency). The device's own USB send delay isn't included.")
                    .accessibilityLabel("Mac adds \(Int(slot.addedLatencyMs)) milliseconds")
            }
            FlatLatchButton(title: "M", isOn: slot.muted, onColor: Theme.mute,
                            accessibilityLabel: "Mute \(slot.accessibilityName)") { model.toggleMute(slot) }
            FlatLatchButton(title: "S", isOn: slot.solo, onColor: Theme.solo,
                            accessibilityLabel: "Solo \(slot.accessibilityName)") { model.toggleSolo(slot) }
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Image(systemName: slot.volume == 0 || silenced ? "speaker.slash" : "speaker.wave.1")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            FlatSlider(
                value: Binding(get: { Double(slot.volume) }, set: { model.setVolume(Float($0), for: slot) }),
                tint: silenced ? Color.secondary : Theme.accent,
                accessibilityLabel: "\(slot.accessibilityName) volume"
            )
            Text("\(Int((slot.volume * 100).rounded()))")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
        }
    }
}
