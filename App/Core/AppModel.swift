import AVFoundation
import AppKit
import Foundation
import Observation
import ReceiverKit

/// Everything that belongs to one plugged-in device at runtime.
final class SlotRuntime {
    let uid: String
    /// Mixer bus key; stable for a device while the app runs.
    let index: Int
    let model: SlotModel
    let buffer = SlotAudioBuffer(capacitySeconds: 1.0)
    let log: RotatingLog
    let capture: WiredCapture
    var drift = DriftController()
    var appliedRate = 1.0

    init(uid: String, index: Int, model: SlotModel, log: RotatingLog) {
        self.uid = uid
        self.index = index
        self.model = model
        self.log = log
        self.capture = WiredCapture(uid: uid, name: model.name, buffer: buffer, log: log)
    }
}

struct LogSource: Identifiable, Hashable {
    let id: String
    let title: String
    let log: RotatingLog

    static func == (a: LogSource, b: LogSource) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

@MainActor
@Observable
final class AppModel {
    enum MenuBarState { case off, waiting, playing }

    let prefs: Preferences
    let outputs = OutputDevices()
    /// iPhones and iPads plugged in by USB.
    let watcher = WiredDeviceWatcher()

    /// One slot per plugged-in device being captured, in plug-in order.
    private(set) var slots: [SlotModel] = []
    private(set) var isOn = false
    private(set) var cameraAccess = AVCaptureDevice.authorizationStatus(for: .video)
    private(set) var masterPeakDB: Float = -60
    var masterVolume: Float {
        didSet {
            prefs.masterVolume = masterVolume
            mixer.masterVolume = masterVolume
        }
    }

    @ObservationIgnored private let mixer = AudioMixer()
    @ObservationIgnored private var runtimes: [String: SlotRuntime] = [:]
    @ObservationIgnored private var indexes: [String: Int] = [:]
    @ObservationIgnored private var tickTimer: Timer?
    @ObservationIgnored private var tickCount = 0
    @ObservationIgnored private let sleepAssertion = SleepAssertion()
    @ObservationIgnored private let wakeMonitor = WakeMonitor()
    @ObservationIgnored let logDirectory: URL

    init(prefs: Preferences = Preferences()) {
        self.prefs = prefs
        self.masterVolume = prefs.masterVolume

        let fm = FileManager.default
        logDirectory = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/AudioPipe", isDirectory: true)

        mixer.masterVolume = masterVolume
        mixer.limiterEnabled = prefs.limiterEnabled
        if let device = outputs.device(uid: prefs.outputDeviceUID) {
            mixer.setOutputDevice(device.id)
        }
        outputs.onDefaultChanged = { [weak self] in self?.mixer.systemDefaultChanged() }
        outputs.onDevicesChanged = { [weak self] in self?.devicesChanged() }

        watcher.onChange = { [weak self] in self?.syncDevices() }
        watcher.start()
        // Capture sessions don't always survive sleep; start them fresh.
        wakeMonitor.onWake = { [weak self] in self?.restartCapture() }
        wakeMonitor.start()

        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    // MARK: - Derived state

    var menuBarState: MenuBarState {
        if !isOn { return .off }
        return slots.contains { $0.state == .playing } ? .playing : .waiting
    }

    var playingCount: Int { slots.filter { $0.state == .playing }.count }

    var cameraDenied: Bool { cameraAccess == .denied || cameraAccess == .restricted }

    var outputName: String {
        if let d = outputs.device(uid: prefs.outputDeviceUID) { return d.name }
        return outputs.defaultDevice.map { "System (\($0.name))" } ?? "System Output"
    }

    var logSources: [LogSource] {
        runtimes.values.sorted { $0.index < $1.index }.map {
            LogSource(id: "device-\($0.index)", title: $0.model.name, log: $0.log)
        }
    }

    var anySolo: Bool { slots.contains { $0.solo } }

    func slot(forDevice uid: String) -> SlotModel? {
        _ = slots  // observe: runtimes change together with slots
        return runtimes[uid]?.model
    }

    // MARK: - On / off

    func setOn(_ on: Bool) {
        isOn = on
        syncDevices()
        if !on { sleepAssertion.set(false) }
    }

    /// Stops every capture and starts them again for the devices plugged in now.
    func restartCapture() {
        guard isOn else { return }
        removeAll()
        watcher.rescan()
        syncDevices()
    }

    /// Asks for Camera access up front (onboarding). macOS treats iPhones and
    /// iPads as cameras, so capturing their audio needs it.
    func requestCameraAccess() {
        AVCaptureDevice.requestAccess(for: .video) { _ in
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    self?.cameraAccess = AVCaptureDevice.authorizationStatus(for: .video)
                    self?.restartCapture()
                }
            }
        }
    }

    /// Blocking shutdown for app termination.
    func shutdown() {
        for rt in runtimes.values {
            rt.capture.stopAndWait()
            rt.log.note("Stopped capturing (app quit)")
        }
        mixer.stop()
        sleepAssertion.set(false)
    }

    // MARK: - Devices

    /// One capture per plugged-in device while on. Devices that leave are
    /// stopped and removed.
    private func syncDevices() {
        let wanted = isOn ? watcher.devices : []
        let wantedIDs = Set(wanted.map(\.uid))

        for (uid, rt) in runtimes where !wantedIDs.contains(uid) {
            remove(rt)
        }

        for device in wanted where runtimes[device.uid] == nil {
            let index: Int
            if let known = indexes[device.uid] {
                index = known
            } else {
                index = indexes.count + 1
                indexes[device.uid] = index
            }
            let model = SlotModel(index: index, name: device.name)
            model.volume = prefs.volume(forDevice: device.uid)
            model.state = .starting
            let rt = SlotRuntime(uid: device.uid, index: index, model: model,
                                 log: RotatingLog(directory: logDirectory, name: "device-\(index)"))
            rt.buffer.setTarget(seconds: prefs.bufferTargetMs / 1000)
            runtimes[device.uid] = rt
            mixer.addSlot(index: index, buffer: rt.buffer)
            rt.capture.start()
        }

        slots = wanted.compactMap { runtimes[$0.uid]?.model }
        applyGains()
    }

    /// `wait` blocks until the session has stopped, so a new capture of the
    /// same device doesn't overlap the old one.
    private func remove(_ rt: SlotRuntime, wait: Bool = false) {
        wait ? rt.capture.stopAndWait() : rt.capture.stop()
        rt.buffer.flush()
        mixer.removeSlot(index: rt.index)
        runtimes.removeValue(forKey: rt.uid)
        rt.log.note("Stopped capturing")
    }

    private func removeAll() {
        for rt in runtimes.values { remove(rt, wait: true) }
        slots = []
    }

    // MARK: - 10 Hz tick: levels, states, drift, latency

    private func tick() {
        // Each check is an IPC to tccd, so every 2 s is plenty to notice a
        // change made in System Settings.
        tickCount += 1
        if tickCount % 20 == 1 {
            let access = AVCaptureDevice.authorizationStatus(for: .video)
            if access != cameraAccess { cameraAccess = access }
        }

        let outputLatency = mixer.outputLatency
        let target = prefs.bufferTargetMs / 1000
        var masterPeak: Float = 0
        var anyPlaying = false

        for rt in runtimes.values {
            let m = rt.model
            let levels = rt.buffer.takeLevels()
            let audioRecent = rt.buffer.secondsSinceAudio < 0.5

            // A device streams silence while nothing plays, so "playing" means sound, not data.
            let newState: SlotState
            switch rt.capture.status {
            case .failed(let reason): newState = .failed(reason)
            case .starting, .stopped: newState = .starting
            case .running: newState = rt.buffer.secondsSinceSound < 0.5 ? .playing : .connected
            }
            if m.state != newState {
                if newState.isFailed { m.lastLogLines = rt.log.recentLines(8) }
                m.state = newState
            }
            if newState == .playing { anyPlaying = true }

            let gain = effectiveGain(m)
            let peakDB = AudioLevels.decibels(levels.peak)
            let rmsDB = AudioLevels.decibels(levels.rms)
            if m.peakDB != peakDB { m.peakDB = peakDB }
            if m.rmsDB != rmsDB { m.rmsDB = rmsDB }
            masterPeak = max(masterPeak, levels.peak * gain)

            let depth = rt.buffer.depthSeconds
            let depthMs = (depth * 1000).rounded()
            if m.depthMs != depthMs { m.depthMs = depthMs }
            let latencyMs = ((depth + outputLatency) * 1000).rounded()
            if m.addedLatencyMs != latencyMs { m.addedLatencyMs = latencyMs }
            let underruns = rt.buffer.underruns
            if m.underruns != underruns { m.underruns = underruns }
            let dropped = rt.buffer.droppedFrames
            if m.droppedFrames != dropped { m.droppedFrames = dropped }

            // Clock drift: while frames flow (silence included) and the buffer is primed.
            let flowing = audioRecent && (newState == .playing || newState == .connected)
            if flowing, rt.buffer.isPrimed {
                if let rate = rt.drift.addSample(depthSeconds: depth, targetSeconds: target, dt: 0.1) {
                    rt.appliedRate = rate
                    mixer.setRate(index: rt.index, rate: rate)
                    m.driftRate = rate
                }
            } else if rt.appliedRate != 1 {
                rt.drift.reset()
                rt.appliedRate = 1
                mixer.setRate(index: rt.index, rate: 1)
                m.driftRate = 1
            }
        }

        let master = AudioLevels.decibels(masterPeak * masterVolume)
        if masterPeakDB != master { masterPeakDB = master }
        sleepAssertion.set(anyPlaying)
    }

    // MARK: - Mixer controls

    private func effectiveGain(_ m: SlotModel) -> Float {
        if anySolo { return m.solo ? m.volume : 0 }
        return m.muted ? 0 : m.volume
    }

    private func applyGains() {
        for m in slots { mixer.setGain(index: m.index, volume: effectiveGain(m), pan: m.pan) }
    }

    func setVolume(_ v: Float, for slot: SlotModel) {
        slot.volume = v
        if let uid = runtimes.values.first(where: { $0.model === slot })?.uid {
            prefs.setVolume(v, forDevice: uid)
        }
        applyGains()
    }

    func toggleMute(_ slot: SlotModel) {
        slot.muted.toggle()
        applyGains()
    }

    func toggleSolo(_ slot: SlotModel) {
        slot.solo.toggle()
        applyGains()
    }

    func setBufferTarget(ms: Double) {
        prefs.bufferTargetMs = min(max(ms, Preferences.bufferRange.lowerBound), Preferences.bufferRange.upperBound)
        for rt in runtimes.values {
            rt.buffer.setTarget(seconds: prefs.bufferTargetMs / 1000)
            rt.drift.reset()
        }
    }

    func setLimiter(_ on: Bool) {
        prefs.limiterEnabled = on
        mixer.limiterEnabled = on
    }

    func selectOutput(uid: String?) {
        prefs.outputDeviceUID = uid
        mixer.setOutputDevice(outputs.device(uid: uid)?.id)
    }

    private func devicesChanged() {
        // A pinned device that comes back (e.g. AirPods reconnecting) is used again.
        if let device = outputs.device(uid: prefs.outputDeviceUID), mixer.pinnedDevice != device.id {
            mixer.setOutputDevice(device.id)
        }
    }
}
