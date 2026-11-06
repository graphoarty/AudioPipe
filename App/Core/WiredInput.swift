import AVFoundation
import CoreMediaIO
import Observation
import ReceiverKit

/// iPhones and iPads plugged into this Mac by USB, seen as capture devices.
///
/// macOS hides them unless the process opts in through CoreMediaIO's "allow
/// screen capture devices" property, the same switch QuickTime's New Movie
/// Recording uses. Each device then appears as a muxed (video + audio)
/// `AVCaptureDevice` whose model ID is "iOS Device". This is public API; the
/// Audio MIDI Setup "Enable" route (IDAM) needs a private framework instead.
@MainActor
@Observable
final class WiredDeviceWatcher {
    struct Device: Equatable, Identifiable {
        let uid: String
        let name: String
        var id: String { uid }
    }

    private(set) var devices: [Device] = []
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var started = false

    /// Opts in and starts watching. The opt-in is per process, so it does not
    /// change anything for other apps.
    func start() {
        guard !started else { return }
        started = true
        Self.allowScreenCaptureDevices()
        let nc = NotificationCenter.default
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.rescan() }
            })
        }
        rescan()
        // Devices show up a moment after the opt-in. The notifications
        // usually cover it; these are a backstop.
        for delay in [1.0, 3.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated { self?.rescan() }
            }
        }
    }

    func rescan() {
        let found = AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .muxed, position: .unspecified)
            .devices
            .filter { $0.modelID == "iOS Device" }
            .map { Device(uid: $0.uniqueID, name: $0.localizedName) }
        guard found != devices else { return }
        devices = found
        onChange?()
    }

    private static func allowScreenCaptureDevices() {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var allow: UInt32 = 1
        CMIOObjectSetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil,
            UInt32(MemoryLayout<UInt32>.size), &allow
        )
    }
}

/// Captures one wired iOS device's audio into a slot buffer.
///
/// While a session runs, the device sends its sound to the Mac instead of its
/// own speakers. macOS counts these devices as cameras, so capturing needs
/// Camera access even though only the audio port is used: without it the
/// session runs but no buffers arrive.
final class WiredCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    enum Status: Equatable {
        case starting
        case running
        case failed(String)
        case stopped
    }

    static let cameraDeniedMessage = "Camera access is off for AudioPipe. macOS treats iPhones and iPads as cameras; turn it on in Privacy & Security → Camera."

    let uid: String
    let name: String
    private let buffer: SlotAudioBuffer
    private let log: RotatingLog
    private let session = AVCaptureSession()
    private let control = DispatchQueue(label: "com.audiopipe.wired.control")
    private let audioQueue = DispatchQueue(label: "com.audiopipe.wired.audio", qos: .userInteractive)

    private let lock = NSLock()
    private var _status: Status = .stopped
    private var _startedAt: Date?
    private var observers: [NSObjectProtocol] = []

    /// The device sends a backlog of about 100 ms when capture starts. Feeding
    /// it to the ring buffer would leave the slot that far behind until the
    /// ±0.1 % drift controller drains it (about a minute), so it is dropped.
    static let startupDiscardSeconds = 0.5

    // Audio queue only.
    private let bufferList = AudioBufferList.allocate(maximumBuffers: 2)
    private var scratchL: [Float] = []
    private var scratchR: [Float] = []
    private var framesSeen = 0
    private var buffersSinceLog = 0
    private var lastStatsLog = Date()
    private var loggedFormat = false
    private var unsupportedFormat = false

    init(uid: String, name: String, buffer: SlotAudioBuffer, log: RotatingLog) {
        self.uid = uid
        self.name = name
        self.buffer = buffer
        self.log = log
        super.init()
    }

    deinit {
        for o in observers { NotificationCenter.default.removeObserver(o) }
        free(bufferList.unsafeMutablePointer)
    }

    // MARK: State (any thread)

    var status: Status {
        lock.lock(); defer { lock.unlock() }
        return _status
    }

    var secondsRunning: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return _startedAt.map { Date().timeIntervalSince($0) } ?? 0
    }

    private func setStatus(_ s: Status) {
        lock.lock()
        _status = s
        _startedAt = s == .running ? Date() : nil
        lock.unlock()
    }

    private func fail(_ reason: String) {
        log.note("Capture failed: \(reason)")
        setStatus(.failed(reason))
    }

    // MARK: Start / stop

    func start() {
        setStatus(.starting)
        log.note("Starting capture from \(name) (\(uid))")
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            control.async { self.configureAndRun() }
        case .notDetermined:
            log.note("Asking for Camera access (required by macOS for iOS devices)")
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    self.control.async { self.configureAndRun() }
                } else {
                    self.fail(Self.cameraDeniedMessage)
                }
            }
        default:
            fail(Self.cameraDeniedMessage)
        }
    }

    func stop() {
        setStatus(.stopped)
        control.async { self.teardown() }
    }

    /// Blocking stop, for app termination.
    func stopAndWait() {
        setStatus(.stopped)
        control.sync { teardown() }
    }

    private func teardown() {
        if session.isRunning { session.stopRunning() }
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers.removeAll()
    }

    private func configureAndRun() {
        guard status == .starting else { return }  // stopped while waiting for permission
        guard let device = AVCaptureDevice(uniqueID: uid) else {
            fail("\(name) was disconnected.")
            return
        }

        session.beginConfiguration()
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            session.commitConfiguration()
            fail("Couldn't open \(name): \(error.localizedDescription)")
            return
        }
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            fail("Couldn't open \(name).")
            return
        }
        session.addInput(input)

        // Ask Core Media for the slot format directly: 44.1 kHz planar Float32 stereo.
        let output = AVCaptureAudioDataOutput()
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: SlotAudioFormat.sampleRate,
            AVNumberOfChannelsKey: SlotAudioFormat.channels,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: true,
            AVLinearPCMIsBigEndianKey: false,
        ]
        output.setSampleBufferDelegate(self, queue: audioQueue)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            fail("Couldn't capture audio from \(name).")
            return
        }
        session.addOutput(output)
        session.commitConfiguration()

        observers.append(NotificationCenter.default.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil
        ) { [weak self] note in
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? Error
            self?.fail("Capture stopped: \(error?.localizedDescription ?? "unknown error")")
        })

        session.startRunning()
        guard status == .starting else { teardown(); return }  // stopped meanwhile
        if session.isRunning {
            setStatus(.running)
            log.note("Capture running")
        } else {
            fail("Capture didn't start. Unlock \(name) and tap Trust if it asks.")
        }
    }

    // MARK: Audio queue

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frames > 0, !unsupportedFormat,
              let fd = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd)?.pointee else { return }

        let isFloat = asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let planar = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        if !loggedFormat {
            loggedFormat = true
            log.note(String(format: "First audio: %.0f Hz, %u ch, %u-bit %@ %@, %d frames per buffer",
                            asbd.mSampleRate, asbd.mChannelsPerFrame, asbd.mBitsPerChannel,
                            isFloat ? "float" : "int", planar ? "planar" : "interleaved", frames))
            if asbd.mSampleRate != SlotAudioFormat.sampleRate || !isFloat || asbd.mBitsPerChannel != 32 {
                unsupportedFormat = true
                fail("\(name) sent an unexpected audio format (\(Int(asbd.mSampleRate)) Hz).")
                return
            }
        }

        framesSeen += frames
        guard Double(framesSeen) > Self.startupDiscardSeconds * asbd.mSampleRate else { return }

        var block: CMBlockBuffer?
        let st = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: bufferList.unsafeMutablePointer,
            bufferListSize: AudioBufferList.sizeInBytes(maximumBuffers: 2),
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &block
        )
        guard st == noErr, bufferList.count >= 1,
              let first = bufferList[0].mData?.assumingMemoryBound(to: Float.self) else { return }

        if planar {
            let second = bufferList.count > 1 ? bufferList[1].mData?.assumingMemoryBound(to: Float.self) ?? first : first
            buffer.push(left: first, right: second, frames: frames)
        } else {
            // Interleaved: split into planar scratch buffers.
            let ch = Int(max(asbd.mChannelsPerFrame, 1))
            if scratchL.count < frames {
                scratchL = [Float](repeating: 0, count: frames)
                scratchR = [Float](repeating: 0, count: frames)
            }
            for i in 0..<frames {
                scratchL[i] = first[i * ch]
                scratchR[i] = first[i * ch + (ch > 1 ? 1 : 0)]
            }
            scratchL.withUnsafeBufferPointer { l in
                scratchR.withUnsafeBufferPointer { r in
                    buffer.push(left: l.baseAddress!, right: r.baseAddress!, frames: frames)
                }
            }
        }

        // Buffer timestamps are assigned on arrival at the Mac, so they can't
        // show the device's own delay; log what the Mac side can see instead.
        buffersSinceLog += 1
        if Date().timeIntervalSince(lastStatsLog) > 10 {
            lastStatsLog = Date()
            log.note(String(format: "%d buffers in the last 10 s; ring depth %.1f ms; underruns %llu; dropped %llu",
                            buffersSinceLog, buffer.depthSeconds * 1000, buffer.underruns, buffer.droppedFrames))
            buffersSinceLog = 0
        }
    }
}
