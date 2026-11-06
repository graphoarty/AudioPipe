import AppKit
import IOKit.pwr_mgt
import ServiceManagement

/// Holds an IOKit assertion against idle sleep while any device is playing.
final class SleepAssertion {
    private var id: IOPMAssertionID = 0
    private(set) var isHeld = false

    func set(_ hold: Bool) {
        guard hold != isHeld else { return }
        if hold {
            let reason = "AudioPipe is playing audio from a USB device" as CFString
            isHeld = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &id
            ) == kIOReturnSuccess
        } else {
            IOPMAssertionRelease(id)
            isHeld = false
        }
    }

    deinit { set(false) }
}

/// Reports wake from sleep, so captures can start fresh.
final class WakeMonitor {
    var onWake: (() -> Void)?
    private var observer: NSObjectProtocol?

    func start() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.onWake?() }
    }

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
