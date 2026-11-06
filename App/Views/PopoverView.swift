import ReceiverKit
import SwiftUI

struct PopoverView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            if let banner = bannerContent {
                banner
                Hairline()
            }
            slotList
            Hairline()
            footer
        }
        .frame(width: 400)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.35))
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                AppGlyph(state: model.menuBarState)
                VStack(alignment: .leading, spacing: 1) {
                    Text("AudioPipe").font(.system(size: 14, weight: .semibold))
                    Text(subtitle).font(Theme.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(isOn: Binding(get: { model.isOn }, set: { model.setOn($0) })) {
                    Text(model.isOn ? "On" : "Off")
                        .font(Theme.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .toggleStyle(FlatSwitchStyle())
                .fixedSize()
                .accessibilityLabel("Play USB devices")
            }

            HStack(spacing: 10) {
                Image(systemName: model.masterVolume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                FlatSlider(
                    value: Binding(get: { Double(model.masterVolume) }, set: { model.masterVolume = Float($0) }),
                    accessibilityLabel: "Master volume"
                )
                Text("\(Int((model.masterVolume * 100).rounded()))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, alignment: .trailing)
            }

            LevelMeter(rmsDB: model.masterPeakDB, peakDB: model.masterPeakDB, segments: 40,
                       accessibilityLabel: "Master level")

            OutputPicker(model: model)
        }
        .padding(14)
    }

    private var subtitle: String {
        guard model.isOn else { return "Off" }
        let count = model.slots.count
        guard count > 0 else { return "Waiting for a USB device" }
        let devices = "\(count) device\(count == 1 ? "" : "s")"
        let playing = model.playingCount
        return playing > 0 ? "\(devices) · \(playing) playing" : devices
    }

    // MARK: Banner

    private var bannerContent: AnyView? {
        guard model.cameraDenied else { return nil }
        return AnyView(Banner(
            icon: "video.slash",
            tint: Theme.danger,
            title: "Camera access is off",
            message: "macOS treats iPhones and iPads as cameras, so AudioPipe needs camera access to play their sound. It never records video.",
            actionTitle: "Open Privacy Settings",
            action: { SystemSettings.openCameraPrivacy() }
        ))
    }

    // MARK: Devices

    @ViewBuilder private var slotList: some View {
        if model.slots.isEmpty {
            emptyState
        } else {
            let list = VStack(spacing: 1) {
                ForEach(model.slots) { slot in
                    SlotRow(slot: slot, model: model)
                }
            }
            Group {
                if model.slots.count > 4 {
                    ScrollView { list }.frame(height: 4 * 92)
                } else {
                    list
                }
            }
            .background(Theme.hairline)
        }
    }

    private var emptyState: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "cable.connector")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.isOn ? "No device plugged in" : "Playback is off")
                    .font(Theme.label)
                Text(model.isOn
                     ? "Plug an iPhone or iPad into this Mac with a USB cable. Unlock it and tap Trust if it asks."
                     : "Turn AudioPipe on to play iPhones and iPads plugged in by USB.")
                    .font(Theme.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "cable.connector")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 1)
                Text("Each iPhone or iPad plugged in by USB gets its own channel. While plugged in, its sound plays here instead of on its own speakers.")
                    .font(Theme.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                Button { WindowManager.shared.showSettings(model: model) } label: {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(FlatButtonStyle(kind: .secondary, compact: true))
                .keyboardShortcut(",", modifiers: .command)

                Button { WindowManager.shared.showSettings(model: model, tab: .diagnostics) } label: {
                    Label("Diagnostics", systemImage: "waveform.path.ecg")
                }
                .buttonStyle(FlatButtonStyle(kind: .ghost, compact: true))

                Spacer()

                Button { NSApp.terminate(nil) } label: {
                    Text("Quit")
                }
                .buttonStyle(FlatButtonStyle(kind: .ghost, compact: true))
                .keyboardShortcut("q", modifiers: .command)
            }
        }
        .padding(14)
    }
}

// MARK: - Pieces

struct OutputPicker: View {
    @Bindable var model: AppModel

    private enum Choice: Hashable {
        case system
        case device(String)
    }

    var body: some View {
        let options: [Choice] = [.system] + model.outputs.devices.map { .device($0.uid) }
        let current: Choice = model.outputs.device(uid: model.prefs.outputDeviceUID).map { .device($0.uid) } ?? .system
        FlatDropdown(
            options: options,
            selection: current,
            title: { choice in
                switch choice {
                case .system:
                    return model.outputs.defaultDevice.map { "System Output (\($0.name))" } ?? "System Output"
                case .device(let uid):
                    return model.outputs.device(uid: uid)?.name ?? "Unavailable device"
                }
            },
            onSelect: { choice in
                switch choice {
                case .system: model.selectOutput(uid: nil)
                case .device(let uid): model.selectOutput(uid: uid)
                }
            },
            accessibilityLabel: "Output device",
            icon: "hifispeaker"
        )
    }
}

struct Banner: View {
    let icon: String
    let tint: Color
    let title: String
    let message: String
    let actionTitle: String?
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle().fill(tint).frame(width: 3)
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(tint).padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.label)
                Text(message).font(Theme.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let actionTitle {
                    Button(actionTitle, action: action)
                        .buttonStyle(FlatButtonStyle(kind: .secondary, compact: true))
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.trailing, 14)
        .background(tint.opacity(0.07))
    }
}

/// Square app glyph in the header, coloured by state.
struct AppGlyph: View {
    let state: AppModel.MenuBarState
    var body: some View {
        ZStack {
            Rectangle().fill(color.opacity(0.16))
            Image(systemName: MenuBarIcon.symbol(for: state))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)
    }

    private var color: Color {
        switch state {
        case .off: return .secondary
        case .waiting: return Theme.accent
        case .playing: return Theme.playing
        }
    }
}

enum MenuBarIcon {
    static func symbol(for state: AppModel.MenuBarState) -> String {
        switch state {
        case .off: return "speaker.slash"
        case .waiting: return "cable.connector"
        case .playing: return "waveform"
        }
    }
}

enum SystemSettings {
    static func openCameraPrivacy() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }
}
