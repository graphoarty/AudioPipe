import AVFoundation
import ReceiverKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case general, audio, diagnostics
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .audio: return "slider.vertical.3"
        case .diagnostics: return "waveform.path.ecg"
        }
    }
}

final class SettingsNavigation: ObservableObject {
    @Published var tab: SettingsTab = .general
}

struct SettingsView: View {
    @Bindable var model: AppModel
    @ObservedObject var nav: SettingsNavigation

    var body: some View {
        VStack(spacing: 0) {
            FlatTabBar(tabs: SettingsTab.allCases, selection: $nav.tab, title: \.title, icon: \.icon)
                .padding(.top, 30)  // under the transparent title bar
            ScrollView {
                Group {
                    switch nav.tab {
                    case .general: GeneralSettings(model: model)
                    case .audio: AudioSettings(model: model)
                    case .diagnostics: DiagnosticsSettings(model: model)
                    }
                }
                .padding(22)
            }
        }
        .frame(width: 600, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

func settingLabel(_ title: String, _ detail: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(title).font(Theme.label)
        Text(detail).font(Theme.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    let model: AppModel
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "USB devices")
                settingLabel("iPhones and iPads plugged into this Mac",
                             "Each one gets its own channel. While plugged in, it plays here instead of on its own speakers.")
                let devices = model.watcher.devices
                if devices.isEmpty {
                    Text("None plugged in. Unlock the device and tap Trust if it asks.")
                        .font(Theme.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.fill)
                } else {
                    VStack(spacing: 1) {
                        ForEach(devices) { device in
                            let slot = model.slot(forDevice: device.uid)
                            HStack(spacing: 10) {
                                Image(systemName: slot?.symbol ?? "cable.connector")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18)
                                Text(device.name).font(Theme.label)
                                Spacer()
                                if let slot {
                                    StatusDot(color: Theme.color(for: slot.state))
                                    Text(slot.statusText).font(Theme.caption).foregroundStyle(.secondary)
                                } else {
                                    Text(model.isOn ? "Starting…" : "Off").font(Theme.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(8)
                            .background(Theme.fill)
                        }
                    }
                }
                CameraAccessRow(model: model)
            }

            Hairline()

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Startup")
                Toggle(isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin)) {
                    settingLabel("Launch at login", "Opens AudioPipe in the menu bar when you log in.")
                }
                .toggleStyle(FlatSwitchStyle())
                if let loginError {
                    Text(loginError).font(Theme.caption).foregroundStyle(Theme.danger)
                }
                Toggle(isOn: Binding(get: { model.prefs.startAtLaunch }, set: { model.prefs.startAtLaunch = $0 })) {
                    settingLabel("Turn on at launch", "Start playing plugged-in devices as soon as the app opens.")
                }
                .toggleStyle(FlatSwitchStyle())
            }

            Hairline()

            HStack {
                settingLabel("Setup guide", "Walk through the first-launch steps again.")
                Spacer()
                Button("Show Setup Guide") { WindowManager.shared.showOnboarding(model: model) }
                    .buttonStyle(FlatButtonStyle(kind: .secondary, compact: true))
            }
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            try LaunchAtLogin.set(on)
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        launchAtLogin = LaunchAtLogin.isEnabled
    }
}

/// Camera access state with the action that fixes it.
struct CameraAccessRow: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.label)
                Text("macOS treats iPhones and iPads as cameras. AudioPipe only uses their sound and never records video.")
                    .font(Theme.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            switch model.cameraAccess {
            case .notDetermined:
                Button("Allow") { model.requestCameraAccess() }
                    .buttonStyle(FlatButtonStyle(kind: .primary, compact: true))
            case .denied, .restricted:
                Button("Open Privacy Settings") { SystemSettings.openCameraPrivacy() }
                    .buttonStyle(FlatButtonStyle(kind: .secondary, compact: true))
            default:
                EmptyView()
            }
        }
        .padding(8)
        .background(Theme.fill)
    }

    private var title: String {
        switch model.cameraAccess {
        case .authorized: return "Camera access allowed"
        case .notDetermined: return "Camera access not asked yet"
        default: return "Camera access is off"
        }
    }

    private var icon: String {
        model.cameraAccess == .authorized ? "checkmark.square.fill" : (model.cameraDenied ? "xmark.square.fill" : "questionmark.square")
    }

    private var tint: Color {
        model.cameraAccess == .authorized ? Theme.playing : (model.cameraDenied ? Theme.danger : Theme.warning)
    }
}

// MARK: - Audio

private struct AudioSettings: View {
    @Bindable var model: AppModel
    @State private var buffer: Double = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Output")
                settingLabel("Output device", "Follow the system output, or pin a specific device.")
                OutputPicker(model: model)
            }

            Hairline()

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Buffering")
                HStack {
                    settingLabel("Buffer per device",
                                 "Absorbs uneven USB delivery (audio arrives in ~21 ms blocks). Lower means less delay but more risk of dropouts.")
                    Spacer()
                    Text("\(Int(buffer)) ms")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .frame(width: 60, alignment: .trailing)
                }
                FlatSlider(
                    value: $buffer, range: Preferences.bufferRange, step: 5,
                    accessibilityLabel: "Buffer target",
                    accessibilityValueText: { "\(Int($0)) milliseconds" },
                    onEditingEnded: { model.setBufferTarget(ms: buffer) }
                )
                HStack {
                    Text("20 ms").font(Theme.mono).foregroundStyle(.tertiary)
                    Spacer()
                    Text("200 ms").font(Theme.mono).foregroundStyle(.tertiary)
                }
            }

            Hairline()

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Master")
                Toggle(isOn: Binding(get: { model.prefs.limiterEnabled }, set: { model.setLimiter($0) })) {
                    settingLabel("Peak limiter", "Prevents clipping when several loud sources play at once.")
                }
                .toggleStyle(FlatSwitchStyle())
            }

            Hairline()

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Live")
                SlotStatsTable(model: model)
            }
        }
        .onAppear { buffer = model.prefs.bufferTargetMs }
    }
}

private struct SlotStatsTable: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 1) {
            row(["Device", "State", "Buffer", "Mac adds", "Rate", "Underruns"], header: true)
            if model.slots.isEmpty {
                Text("No devices playing.")
                    .font(Theme.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.fill)
            }
            ForEach(model.slots) { s in
                row([
                    s.name,
                    s.statusText,
                    "\(Int(s.depthMs)) ms",
                    "\(Int(s.addedLatencyMs)) ms",
                    String(format: "%+.0f ppm", (s.driftRate - 1) * 1_000_000),
                    "\(s.underruns)",
                ], header: false)
            }
        }
    }

    private func row(_ cells: [String], header: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { i, c in
                Text(c)
                    .font(header ? Theme.sectionTitle : (i == 0 ? Theme.caption.weight(.medium) : Theme.mono))
                    .foregroundStyle(header ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: i <= 1 ? .infinity : 72, alignment: i <= 1 ? .leading : .trailing)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(header ? Color.clear : Theme.fill)
    }
}

// MARK: - Diagnostics

private struct DiagnosticsSettings: View {
    @Bindable var model: AppModel
    @State private var selectedLog: String = "device-1"
    @State private var logText = ""
    @State private var refresh = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Capture")
                infoRow("Playback", model.isOn ? "On" : "Off", color: model.isOn ? Theme.playing : .secondary)
                infoRow("Camera access", cameraText, color: model.cameraAccess == .authorized ? Theme.playing : Theme.danger)
                infoRow("Plugged in", model.watcher.devices.isEmpty ? "None" : model.watcher.devices.map(\.name).joined(separator: ", "))
                infoRow("Output", model.outputName)

                HStack(spacing: 8) {
                    Button { model.restartCapture() } label: { Label("Restart Capture", systemImage: "arrow.clockwise") }
                        .buttonStyle(FlatButtonStyle(kind: .primary, compact: true))
                        .disabled(!model.isOn)
                    Button { NSWorkspace.shared.open(model.logDirectory) } label: { Label("Open Logs Folder", systemImage: "folder") }
                        .buttonStyle(FlatButtonStyle(kind: .secondary, compact: true))
                }
            }

            Hairline()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionHeader(title: "Device logs")
                    Spacer()
                    let sources = model.logSources
                    if !sources.isEmpty {
                        FlatDropdown(
                            options: sources.map(\.id),
                            selection: sources.contains { $0.id == selectedLog } ? selectedLog : sources[0].id,
                            title: { id in sources.first { $0.id == id }?.title ?? id },
                            onSelect: { selectedLog = $0; reloadLog() },
                            accessibilityLabel: "Log source"
                        )
                        .frame(width: 220)
                    }
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(logText.isEmpty ? "No output yet." : logText)
                            .font(Theme.mono)
                            .foregroundStyle(logText.isEmpty ? .secondary : .primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                        Color.clear.frame(height: 1).id("end")
                    }
                    .frame(height: 260)
                    .background(Color.black.opacity(0.18))
                    .overlay(Rectangle().strokeBorder(Theme.hairline, lineWidth: 1))
                    .onChange(of: logText) { proxy.scrollTo("end", anchor: .bottom) }
                }
            }
        }
        .onAppear(perform: reloadLog)
        .onReceive(refresh) { _ in reloadLog() }
    }

    private var cameraText: String {
        switch model.cameraAccess {
        case .authorized: return "Allowed"
        case .notDetermined: return "Not asked yet"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        @unknown default: return "Unknown"
        }
    }

    private func reloadLog() {
        let sources = model.logSources
        guard let source = sources.first(where: { $0.id == selectedLog }) ?? sources.first else {
            if !logText.isEmpty { logText = "" }
            return
        }
        let text = source.log.fullText(maxBytes: 40_000)
        if text != logText { logText = text }
    }

    private func infoRow(_ title: String, _ value: String, mono: Bool = false, color: Color? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).font(Theme.caption).foregroundStyle(.secondary).frame(width: 120, alignment: .leading)
            HStack(spacing: 6) {
                if let color { StatusDot(color: color) }
                Text(value)
                    .font(mono ? Theme.mono : Theme.label)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
    }
}
