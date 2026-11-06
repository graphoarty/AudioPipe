import AppKit
import SwiftUI

@main
struct AudioPipeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: delegate.model)
        } label: {
            MenuBarLabel(model: delegate.model)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    let model: AppModel
    var body: some View {
        Image(systemName: MenuBarIcon.symbol(for: model.menuBarState))
            .accessibilityLabel("AudioPipe")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = ProcessInfo.processInfo.arguments
        if !model.prefs.onboardingCompleted && !args.contains("--skip-onboarding") {
            WindowManager.shared.showOnboarding(model: model)
        } else if model.prefs.startAtLaunch {
            model.setOn(true)
        }
        if args.contains("--show-settings") {
            WindowManager.shared.showSettings(model: model)
        }
        // Development aid: the popover's content in a normal window (for screenshots).
        if args.contains("--preview-popover") {
            WindowManager.shared.showPopoverPreview(model: model)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
    }
}

/// Settings and onboarding are plain AppKit windows hosting SwiftUI, so a
/// menu-bar-only (LSUIElement) app can show and focus them reliably.
@MainActor
final class WindowManager {
    static let shared = WindowManager()
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private let settingsNav = SettingsNavigation()

    func showSettings(model: AppModel, tab: SettingsTab? = nil) {
        if let tab { settingsNav.tab = tab }
        if settingsWindow == nil {
            settingsWindow = makeWindow(
                title: "AudioPipe Settings",
                content: SettingsView(model: model, nav: settingsNav)
            )
        }
        present(settingsWindow)
    }

    func showOnboarding(model: AppModel) {
        if onboardingWindow == nil {
            onboardingWindow = makeWindow(
                title: "Welcome to AudioPipe",
                content: OnboardingView(model: model) { [weak self] in
                    self?.onboardingWindow?.close()
                }
            )
        }
        present(onboardingWindow)
    }

    private var previewWindow: NSWindow?

    func showPopoverPreview(model: AppModel) {
        if previewWindow == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.standardWindowButton(.closeButton)?.isHidden = true
            w.standardWindowButton(.miniaturizeButton)?.isHidden = true
            w.standardWindowButton(.zoomButton)?.isHidden = true
            w.contentView = NSHostingView(rootView: PopoverView(model: model).background(.regularMaterial))
            w.setContentSize(w.contentView!.fittingSize)
            w.center()
            previewWindow = w
        }
        present(previewWindow)
    }

    private func present(_ window: NSWindow?) {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow<V: View>(title: String, content: V) -> NSWindow {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = title
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        // Not movable by the background: AppKit can't tell the custom SwiftUI
        // sliders' drags from background drags, so dragging one moved the
        // window. The transparent title bar strip still moves it.
        window.isMovableByWindowBackground = false
        // No round traffic lights: a flat square close control instead.
        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(kind)?.isHidden = true
        }
        let chrome = ZStack(alignment: .topTrailing) {
            content
            FlatIconButton(systemImage: "xmark", help: "Close", size: 26) { [weak window] in window?.performClose(nil) }
                .keyboardShortcut("w", modifiers: .command)
                .padding(8)
        }
        window.contentView = NSHostingView(rootView: chrome)
        window.setContentSize(window.contentView!.fittingSize)
        window.center()
        return window
    }
}
