//
//  SettingsWindow.swift
//  Siri Remote Vibe (settings UI)
//
//  Hosts the SwiftUI SettingsView in a clean, borderless-title window from the menu-bar app.
//

import AppKit
import SwiftUI

final class SettingsWindowController {
    private var window: NSWindow?
    private let model: SettingsModel
    private var closeObserver: NSObjectProtocol?

    init(model: SettingsModel) { self.model = model }

    deinit {
        if let obs = closeObserver { NotificationCenter.default.removeObserver(obs) }
    }

    func show() {
        // Menu-bar clicks and manual reopens should use the display the user is working on,
        // even when this cached window was last shown on a different display.
        let targetScreen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main ?? window?.screen
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(model: model))
            // Track the SwiftUI workspace's fitting size. Tuning is intentionally a wide,
            // two-column Mac layout; Layout gets a little more room for its binding matrix.
            hosting.sizingOptions = [.preferredContentSize]
            let win = NSWindow(contentViewController: hosting)
            win.title = AppBrand.name + " Settings"
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            win.titlebarAppearsTransparent = true
            win.titleVisibility = .hidden
            win.isMovableByWindowBackground = true
            win.isReleasedWhenClosed = false
            win.hidesOnDeactivate = false
            win.level = .normal
            win.isExcludedFromWindowsMenu = false
            win.contentMinSize = NSSize(width: 820, height: 620)
            // Stop the device polling when the window closes. The window is cached
            // (`isReleasedWhenClosed = false`), so closing only orders it out and SwiftUI's
            // `.onDisappear` does not run — without this the 60s `system_profiler` poll would keep
            // going for the rest of the app's uptime with nothing on screen to show it.
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: win, queue: .main
            ) { [weak self] _ in
                self?.model.device.stop()
            }

            window = win
        }
        model.device.start()
        NSApp.activate(ignoringOtherApps: true)
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        window?.makeKeyAndOrderFront(nil)
        // SwiftUI's preferred content size settles when the window is shown. Center after that
        // layout pass, on every open, instead of only when the cached window is first created.
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window, window.isVisible,
                  let visible = targetScreen?.visibleFrame else { return }
            window.contentView?.layoutSubtreeIfNeeded()
            var frame = window.frame
            frame.size.width = min(frame.width, max(0, visible.width - 40))
            frame.size.height = min(frame.height, max(0, visible.height - 40))
            frame.origin = NSPoint(x: visible.midX - frame.width / 2,
                                   y: visible.midY - frame.height / 2)
            window.setFrame(frame, display: true)
        }
    }
}
