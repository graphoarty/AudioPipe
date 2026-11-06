import SwiftUI

/// First-launch guide: the idea, then camera access and plugging in.
struct OnboardingView: View {
    @Bindable var model: AppModel
    let onFinish: () -> Void
    @State private var step = 0
    private let steps = 2

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(0..<steps, id: \.self) { i in
                    Rectangle()
                        .fill(i <= step ? Theme.accent : Theme.track)
                        .frame(height: 3)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 38)
            .animation(.easeOut(duration: 0.2), value: step)

            Group {
                switch step {
                case 0: IdeaStep()
                default: ConnectStep(model: model)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Hairline()
            HStack {
                Text("Step \(step + 1) of \(steps)").font(Theme.caption).foregroundStyle(.secondary)
                Spacer()
                if step > 0 {
                    Button("Back") { step -= 1 }
                        .buttonStyle(FlatButtonStyle(kind: .ghost))
                }
                Button(step == steps - 1 ? "Done" : "Continue") {
                    if step == steps - 1 {
                        model.prefs.onboardingCompleted = true
                        onFinish()
                    } else {
                        step += 1
                        if step == steps - 1, !model.isOn { model.setOn(true) }
                    }
                }
                .buttonStyle(FlatButtonStyle(kind: .primary))
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
        }
        .frame(width: 560, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct StepTitle: View {
    let eyebrow: String
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow.uppercased()).font(Theme.sectionTitle).tracking(1).foregroundStyle(Theme.accent)
            Text(title).font(.system(size: 22, weight: .semibold))
            Text(detail).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct IdeaStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            StepTitle(
                eyebrow: "Welcome to AudioPipe",
                title: "Plug in, and it plays here",
                detail: "Connect iPhones and iPads to this Mac with USB cables. Each one gets its own channel with volume, mute and solo, and the Mac mixes them all live. Nothing to install on the devices."
            )
            HStack(spacing: 14) {
                deviceColumn("iphone", "iPhone", "Channel 1", Theme.playing)
                deviceColumn("ipad", "iPad", "Channel 2", Theme.connected)
                deviceColumn("ipad", "Another iPad", "Channel 3", Color.primary.opacity(0.3))
            }
            Label("Low delay: the sound travels over the cable, not Wi-Fi.",
                  systemImage: "bolt")
                .font(Theme.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func deviceColumn(_ icon: String, _ device: String, _ channel: String, _ color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 26, weight: .light)).frame(height: 34)
            Text(device).font(Theme.caption).foregroundStyle(.secondary)
            Image(systemName: "cable.connector").font(.system(size: 10)).foregroundStyle(.tertiary)
            Text(channel)
                .font(Theme.label)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(color.opacity(0.15))
                .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 3) }
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Theme.fill)
    }
}

private struct ConnectStep: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepTitle(
                eyebrow: "Connect",
                title: "Allow camera access, then plug in",
                detail: "macOS treats iPhones and iPads as cameras, so it asks whether AudioPipe may use the camera. Click Allow. AudioPipe only uses the sound and never records video. Then plug in a device, unlock it and tap Trust if it asks."
            )
            CameraAccessRow(model: model)
            VStack(spacing: 1) {
                if model.slots.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "cable.connector").foregroundStyle(.secondary).frame(width: 18)
                        Text("Waiting for a device…").font(Theme.label).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(8)
                    .background(Theme.fill)
                }
                ForEach(model.slots) { slot in
                    HStack(spacing: 10) {
                        Rectangle().fill(Theme.color(for: slot.state)).frame(width: 3, height: 26)
                        Image(systemName: slot.symbol).foregroundStyle(.secondary)
                        Text(slot.name).font(Theme.label)
                        Spacer()
                        Text(slot.statusText).font(Theme.caption).foregroundStyle(.secondary)
                    }
                    .padding(.trailing, 12)
                    .padding(.vertical, 6)
                    .background(Theme.fill)
                }
            }
        }
    }
}
