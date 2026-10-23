//
//  MenuBarManager.swift
//  siriRemote
//
//  The menu-bar status item: a Siri Remote icon, a connection-status line, and
//  Settings… / Quit. All button / ring / gesture mapping lives in Settings → Layout, driven by
//  the config engine — there are no mapping submenus here.
//

import AppKit

/// Trackpad two-finger scroll speed → pixels-per-unit scale (used by TouchHandler).
enum ScrollSpeed: String, CaseIterable {
    case slow = "Slow"
    case medium = "Medium"
    case fast = "Fast"

    var scale: CGFloat {
        switch self {
        case .slow:   return 150.0
        case .medium: return 300.0
        case .fast:   return 500.0
        }
    }
}

final class MenuBarManager {

    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private let statusMenuItem: NSMenuItem
    private let permissionMenuItem: NSMenuItem
    private var isConnected = false
    private var permissionsReady = false
    private var demoRemoteVisible = false
    private var availableUpdateVersion: String?
    private var localeObserver: NSObjectProtocol?

    /// Two-finger scroll scale (see `ScrollSpeed`).
    private(set) var scrollSpeed: ScrollSpeed = .medium

    /// Set by the AppDelegate to open the SwiftUI settings window.
    var onOpenSettings: (() -> Void)?
    /// Set by the AppDelegate to re-open the first-run setup guide.
    var onOpenSetup: (() -> Void)?
    /// Set by the AppDelegate to present Sparkle's standard update UI.
    var onCheckForUpdates: (() -> Void)?
    /// Set by the AppDelegate to show/hide the live, presentation-oriented remote visualiser.
    var onToggleDemoMode: (() -> Void)?

    init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
        self.menu = NSMenu()
        self.statusMenuItem = NSMenuItem(title: L("Status: Disconnected"), action: nil, keyEquivalent: "")
        self.permissionMenuItem = NSMenuItem(
            title: L("Permissions: Checking…"), action: nil, keyEquivalent: ""
        )
        setupMenuBar()
        localeObserver = NotificationCenter.default.addObserver(
            forName: Loc.didChange, object: nil, queue: .main
        ) { [weak self] _ in self?.relocalize() }
    }

    deinit {
        if let observer = localeObserver { NotificationCenter.default.removeObserver(observer) }
    }

    /// Rebuild the menu and refresh the status line in the current language.
    private func relocalize() {
        rebuildMenu()
        statusMenuItem.title = isConnected ? L("Status: Connected ✓") : L("Status: Disconnected")
        updatePermissionStatus(ready: permissionsReady)
    }

    // MARK: - Icon

    /// Use the same Siri Remote symbol as Settings, with a separate update indicator.
    /// The template image follows the menu bar's light, dark and selected appearances.
    private static func makeRemoteIcon(updateAvailable: Bool = false) -> NSImage {
        let pt: CGFloat = 18
        let remote = NSImage(systemSymbolName: "appletvremote.gen4.fill",
                             accessibilityDescription: AppBrand.name)?
            .withSymbolConfiguration(.init(pointSize: pt, weight: .regular))
        let image = NSImage(size: NSSize(width: pt, height: pt), flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            if let remote, remote.size.width > 0, remote.size.height > 0 {
                let scale = min(rect.width / remote.size.width, rect.height / remote.size.height)
                let size = NSSize(width: remote.size.width * scale, height: remote.size.height * scale)
                remote.draw(in: NSRect(x: rect.midX - size.width / 2,
                                       y: rect.midY - size.height / 2,
                                       width: size.width, height: size.height),
                            from: .zero, operation: .sourceOver, fraction: 1,
                            respectFlipped: true, hints: nil)
            }
            if updateAvailable {
                // A compact status dot remains legible in both menu-bar appearances because the
                // whole image is a template. It does not resize or shift the familiar remote mark.
                ctx.setFillColor(NSColor.black.cgColor)
                ctx.fillEllipse(in: CGRect(x: rect.maxX - 3.5, y: rect.minY + 1,
                                           width: 3, height: 3))
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: - Menu

    private func setupMenuBar() {
        guard let button = statusItem.button else { return }
        button.image = Self.makeRemoteIcon()
        button.title = ""
        button.toolTip = AppBrand.name
        rebuildMenu()
        statusItem.menu = menu
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let titleItem = NSMenuItem(title: AppBrand.shortName, action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(.separator())
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        if let version = availableUpdateVersion {
            let updateItem = NSMenuItem(
                title: L("Update %@ Available…", version),
                action: #selector(checkForUpdates), keyEquivalent: ""
            )
            updateItem.image = NSImage(systemSymbolName: "arrow.down.circle.fill",
                                       accessibilityDescription: nil)
            updateItem.target = self
            menu.addItem(updateItem)
        }

        permissionMenuItem.title = permissionsReady
            ? L("Permissions: Ready ✓") : L("Permissions: Action needed")
        permissionMenuItem.action = permissionsReady ? nil : #selector(openSetup)
        permissionMenuItem.target = permissionsReady ? nil : self
        permissionMenuItem.isEnabled = !permissionsReady
        menu.addItem(permissionMenuItem)

        menu.addItem(.separator())
        let setupItem = NSMenuItem(
            title: L("Open System Check…"), action: #selector(openSetup), keyEquivalent: ""
        )
        setupItem.target = self
        menu.addItem(setupItem)

        let settingsItem = NSMenuItem(title: L("Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let demoItem = NSMenuItem(
            title: L("Demo Remote"), action: #selector(toggleDemoMode), keyEquivalent: ""
        )
        demoItem.image = NSImage(systemSymbolName: "appletvremote.gen4.fill",
                                 accessibilityDescription: nil)
        demoItem.state = demoRemoteVisible ? .on : .off
        demoItem.target = self
        menu.addItem(demoItem)

        let updatesItem = NSMenuItem(
            title: L("Check for Updates…"), action: #selector(checkForUpdates), keyEquivalent: ""
        )
        updatesItem.target = self
        menu.addItem(updatesItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: L("Quit"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func openSettings() { onOpenSettings?() }

    @objc private func openSetup() { onOpenSetup?() }

    @objc private func checkForUpdates() { onCheckForUpdates?() }

    @objc private func toggleDemoMode() { onToggleDemoMode?() }

    func updateDemoModeVisibility(_ visible: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.demoRemoteVisible = visible
            self.rebuildMenu()
        }
    }

    func setAvailableUpdate(version: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.availableUpdateVersion = version
            self.statusItem.button?.image = Self.makeRemoteIcon(updateAvailable: version != nil)
            self.statusItem.button?.toolTip = version.map { AppBrand.shortName + " · " + L("Update %@ Available", $0) } ?? AppBrand.name
            self.rebuildMenu()
        }
    }

    func updateConnectionStatus(connected: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isConnected = connected
            self.statusMenuItem.title = connected ? L("Status: Connected ✓") : L("Status: Disconnected")
            self.statusItem.button?.appearsDisabled = !connected
        }
    }

    func updatePermissionStatus(ready: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.permissionsReady = ready
            self.permissionMenuItem.title = ready
                ? L("Permissions: Ready ✓") : L("Permissions: Action needed")
            self.permissionMenuItem.action = ready ? nil : #selector(openSetup)
            self.permissionMenuItem.target = ready ? nil : self
            self.permissionMenuItem.isEnabled = !ready
        }
    }

    @objc private func quitApp() {
        NSStatusBar.system.removeStatusItem(statusItem)
        NSApp.terminate(nil)
    }
}
