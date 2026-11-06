import AVFoundation
import AudioToolbox
import CoreAudio
import ReceiverKit
import os

/// One AVAudioEngine that mixes every slot.
///
/// Per slot: AVAudioSourceNode → AVAudioUnitVarispeed → AVAudioMixerNode
/// (volume, pan, mute) → master mixer → peak limiter → output.
/// The master mixer converts 44.1 kHz to the output device's rate.
final class AudioMixer {
    private struct Chain {
        let buffer: SlotAudioBuffer
        let source: AVAudioSourceNode
        let varispeed: AVAudioUnitVarispeed
        let mixer: AVAudioMixerNode
    }

    private let engine = AVAudioEngine()
    private let master = AVAudioMixerNode()
    private let limiter: AVAudioUnitEffect
    private var chains: [Int: Chain] = [:]
    private(set) var pinnedDevice: AudioDeviceID?
    private var configObserver: NSObjectProtocol?
    private let log = Logger(subsystem: "com.audiopipe.app", category: "audio")

    /// Called on the main queue after the graph was rebuilt for a new device.
    var onRebuild: (() -> Void)?

    init() {
        let desc = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        limiter = AVAudioUnitEffect(audioComponentDescription: desc)
        engine.attach(master)
        engine.attach(limiter)
        connectMasterPath()

        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            self?.log.info("Audio configuration changed; rebuilding graph")
            self?.rebuild()
        }
    }

    deinit {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
    }

    // MARK: Graph

    private var outputFormat: AVAudioFormat {
        let hw = engine.outputNode.outputFormat(forBus: 0)
        let rate = hw.sampleRate > 0 ? hw.sampleRate : 48_000
        return AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
    }

    private func connectMasterPath() {
        let fmt = outputFormat
        engine.disconnectNodeOutput(master)
        engine.disconnectNodeOutput(limiter)
        engine.connect(master, to: limiter, format: fmt)
        engine.connect(limiter, to: engine.outputNode, format: fmt)
    }

    private func connect(_ chain: Chain) {
        let fmt = SlotAudioBuffer.renderFormat
        engine.connect(chain.source, to: chain.varispeed, format: fmt)
        engine.connect(chain.varispeed, to: chain.mixer, format: fmt)
        engine.connect(chain.mixer, to: master, fromBus: 0, toBus: master.nextAvailableInputBus, format: fmt)
    }

    func addSlot(index: Int, buffer: SlotAudioBuffer) {
        removeSlot(index: index)
        let chain = Chain(
            buffer: buffer,
            source: AVAudioSourceNode(format: SlotAudioBuffer.renderFormat, renderBlock: buffer.renderBlock),
            varispeed: AVAudioUnitVarispeed(),
            mixer: AVAudioMixerNode()
        )
        engine.attach(chain.source)
        engine.attach(chain.varispeed)
        engine.attach(chain.mixer)
        connect(chain)
        chains[index] = chain
        startIfNeeded()
    }

    func removeSlot(index: Int) {
        guard let chain = chains.removeValue(forKey: index) else { return }
        engine.disconnectNodeOutput(chain.mixer)
        for node in [chain.source, chain.varispeed, chain.mixer] as [AVAudioNode] {
            engine.detach(node)
        }
    }

    /// Rebuilds connections for the current output device and restarts.
    /// Slot buffers and captures keep running throughout.
    func rebuild() {
        engine.stop()
        if let pinnedDevice, !applyDevice(pinnedDevice) {
            log.error("Pinned output device unavailable; using system output")
            self.pinnedDevice = nil
            _ = applyDevice(OutputDevices.defaultOutputDeviceID())
        }
        connectMasterPath()
        for chain in chains.values {
            engine.disconnectNodeOutput(chain.mixer)
            engine.connect(chain.mixer, to: master, fromBus: 0, toBus: master.nextAvailableInputBus, format: SlotAudioBuffer.renderFormat)
        }
        startIfNeeded()
        onRebuild?()
    }

    func startIfNeeded() {
        guard !engine.isRunning, !chains.isEmpty else { return }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            log.error("Engine failed to start: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() { engine.stop() }

    var isRunning: Bool { engine.isRunning }

    // MARK: Controls

    func setGain(index: Int, volume: Float, pan: Float) {
        guard let chain = chains[index] else { return }
        chain.mixer.outputVolume = volume
        chain.mixer.pan = pan
    }

    func setRate(index: Int, rate: Double) {
        chains[index]?.varispeed.rate = Float(rate)
    }

    var masterVolume: Float {
        get { master.outputVolume }
        set { master.outputVolume = newValue }
    }

    var limiterEnabled: Bool {
        get { !limiter.bypass }
        set { limiter.bypass = !newValue }
    }

    /// Pins a device, or follows the system output when `id` is nil.
    func setOutputDevice(_ id: AudioDeviceID?) {
        pinnedDevice = id
        engine.stop()
        _ = applyDevice(id ?? OutputDevices.defaultOutputDeviceID())
        rebuild()
    }

    /// Re-targets the system default when not pinned.
    func systemDefaultChanged() {
        guard pinnedDevice == nil else { return }
        engine.stop()
        _ = applyDevice(OutputDevices.defaultOutputDeviceID())
        rebuild()
    }

    @discardableResult
    private func applyDevice(_ id: AudioDeviceID?) -> Bool {
        guard let id, id != kAudioObjectUnknown, let unit = engine.outputNode.audioUnit else { return false }
        var device = id
        let status = AudioUnitSetProperty(
            unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
            &device, UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        return status == noErr
    }

    /// Output device latency as reported by the output node, in seconds.
    var outputLatency: TimeInterval {
        engine.outputNode.presentationLatency
    }

    var outputSampleRate: Double { outputFormat.sampleRate }
}
