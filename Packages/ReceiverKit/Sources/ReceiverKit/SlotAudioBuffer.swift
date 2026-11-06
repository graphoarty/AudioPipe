import CAudioCore
import Foundation

/// One device's audio buffer: owns the C ring buffer that the render callback
/// reads, and tracks levels and activity for the UI.
public final class SlotAudioBuffer: @unchecked Sendable {
    /// Opaque pointer handed to the render block. Valid for the object's lifetime.
    public let core: OpaquePointer

    private let lock = NSLock()
    private var levels = AudioLevels.silent
    private var lastAudio: Date = .distantPast
    private var lastSound: Date = .distantPast

    /// Peak above which a block counts as sound rather than silence (about -70 dBFS).
    public static let soundThreshold: Float = 0.0003

    public init(capacitySeconds: Double = 1.0) {
        let frames = UInt32(SlotAudioFormat.sampleRate * capacitySeconds)
        guard let p = ap_slot_create(frames, UInt32(SlotAudioFormat.sampleRate)) else {
            fatalError("Could not allocate slot ring buffer")
        }
        core = p
    }

    deinit { ap_slot_destroy(core) }

    // MARK: Producer

    /// Writes planar frames in `SlotAudioFormat`. Call it from one thread only:
    /// the ring buffer has a single producer.
    public func push(left: UnsafePointer<Float>, right: UnsafePointer<Float>, frames: Int) {
        guard frames > 0 else { return }
        let measured = AudioLevels.measure(left: left, right: right, frames: frames)
        _ = ap_slot_write(core, left, right, UInt32(frames))
        let now = Date()
        lock.lock()
        // Peak hold between UI polls; RMS keeps the latest block.
        levels.peak = max(levels.peak, measured.peak)
        levels.rms = measured.rms
        lastAudio = now
        if measured.peak > Self.soundThreshold { lastSound = now }
        lock.unlock()
    }

    // MARK: Polling (UI / drift controller, ~10 Hz)

    /// Returns levels since the last call and resets the peak hold.
    public func takeLevels() -> AudioLevels {
        lock.lock()
        defer { lock.unlock() }
        let l = levels
        if Date().timeIntervalSince(lastAudio) > 0.25 {
            levels = .silent
        } else {
            levels.peak = 0
        }
        return l
    }

    /// Time since any frames arrived, silent or not.
    public var secondsSinceAudio: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return Date().timeIntervalSince(lastAudio)
    }

    /// Time since a block louder than `soundThreshold` arrived. Devices can send
    /// quiet frames around playback, so this is what "playing" means.
    public var secondsSinceSound: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return Date().timeIntervalSince(lastSound)
    }

    public var depthFrames: UInt32 { ap_slot_available(core) }
    public var depthSeconds: Double { Double(depthFrames) / SlotAudioFormat.sampleRate }
    public var isPrimed: Bool { ap_slot_is_primed(core) != 0 }
    public var underruns: UInt64 { ap_slot_underruns(core) }
    public var droppedFrames: UInt64 { ap_slot_dropped_frames(core) }

    public func setTarget(seconds: Double) {
        // 0 is allowed: the render callback then starts playing as soon as
        // any audio is buffered.
        ap_slot_set_target(core, UInt32(max(0, seconds) * SlotAudioFormat.sampleRate))
    }

    /// Fade out over 20 ms and clear.
    public func flush() { ap_slot_request_flush(core) }
}
