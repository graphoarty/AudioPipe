import Foundation
import Observation
import ReceiverKit

enum SlotState: Equatable {
    case off
    case starting
    /// Capturing; the device is sending silence.
    case connected
    case playing
    case failed(String)

    var isPlaying: Bool { self == .playing }
    var isFailed: Bool { if case .failed = self { return true } else { return false } }
}

/// What the UI shows for one plugged-in device.
@Observable
final class SlotModel: Identifiable {
    let index: Int
    var name: String
    var state: SlotState = .off

    var volume: Float = 1
    var pan: Float = 0
    var muted = false
    var solo = false

    var peakDB: Float = -60
    var rmsDB: Float = -60
    /// Delay the Mac adds: ring buffer depth plus output device latency.
    var addedLatencyMs: Double = 0
    var depthMs: Double = 0
    var underruns: UInt64 = 0
    var droppedFrames: UInt64 = 0
    var driftRate: Double = 1
    var lastLogLines: [String] = []

    var id: Int { index }

    init(index: Int, name: String) {
        self.index = index
        self.name = name
    }

    var statusText: String {
        switch state {
        case .off: return "Off"
        case .starting: return "Starting…"
        case .connected: return "Connected by USB"
        case .playing: return "Playing over USB"
        case .failed: return "Failed"
        }
    }

    /// SF Symbol for the device, guessed from its name.
    var symbol: String {
        let n = name.lowercased()
        if n.contains("ipad") { return "ipad" }
        if n.contains("iphone") { return "iphone" }
        return "cable.connector"
    }

    var accessibilityName: String { name }
}
