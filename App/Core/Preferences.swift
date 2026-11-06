import Foundation
import Observation

/// User settings, persisted in UserDefaults.
@Observable
final class Preferences {
    private let defaults: UserDefaults

    var startAtLaunch: Bool { didSet { defaults.set(startAtLaunch, forKey: "startAtLaunch") } }
    /// nil follows the system output device.
    var outputDeviceUID: String? { didSet { defaults.set(outputDeviceUID, forKey: "outputDeviceUID") } }
    var bufferTargetMs: Double { didSet { defaults.set(bufferTargetMs, forKey: "bufferTargetMs") } }
    var limiterEnabled: Bool { didSet { defaults.set(limiterEnabled, forKey: "limiterEnabled") } }
    var masterVolume: Float { didSet { defaults.set(masterVolume, forKey: "masterVolume") } }
    /// Volume per capture device UID.
    var deviceVolumes: [String: Float] { didSet { defaults.set(deviceVolumes, forKey: "deviceVolumes") } }
    var onboardingCompleted: Bool { didSet { defaults.set(onboardingCompleted, forKey: "onboardingCompleted") } }

    static let bufferRange: ClosedRange<Double> = 20...200

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            "startAtLaunch": true,
            "bufferTargetMs": 40.0,
            "limiterEnabled": true,
            "masterVolume": Float(1.0),
            "onboardingCompleted": false,
        ])
        startAtLaunch = defaults.bool(forKey: "startAtLaunch")
        outputDeviceUID = defaults.string(forKey: "outputDeviceUID")
        bufferTargetMs = min(max(defaults.double(forKey: "bufferTargetMs"), Self.bufferRange.lowerBound), Self.bufferRange.upperBound)
        limiterEnabled = defaults.bool(forKey: "limiterEnabled")
        masterVolume = defaults.float(forKey: "masterVolume")
        deviceVolumes = (defaults.dictionary(forKey: "deviceVolumes") as? [String: Float]) ?? [:]
        onboardingCompleted = defaults.bool(forKey: "onboardingCompleted")
    }

    func volume(forDevice uid: String) -> Float { deviceVolumes[uid] ?? 1.0 }

    func setVolume(_ v: Float, forDevice uid: String) { deviceVolumes[uid] = v }
}
