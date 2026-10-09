import Foundation
import CoreGraphics

/// A synthetic key-down changes the event stream, but hardware mouse events can still arrive
/// without its modifier flags. Apps that infer shortcut release from those flags then end PTT.
/// Keep synthetic held modifiers present until the matching remote release or teardown.
final class HeldModifierState {
    static let syntheticMarker: Int64 = 0x48564B455953
    private let lock = NSLock()
    private var held: [CGKeyCode: (flag: CGEventFlags, count: Int)] = [:]

    func begin(_ modifiers: [(keyCode: CGKeyCode, flag: CGEventFlags)]) {
        lock.lock(); defer { lock.unlock() }
        for modifier in modifiers {
            let count = held[modifier.keyCode]?.count ?? 0
            held[modifier.keyCode] = (modifier.flag, count + 1)
        }
    }

    func end(_ modifiers: [(keyCode: CGKeyCode, flag: CGEventFlags)]) {
        lock.lock(); defer { lock.unlock() }
        for modifier in modifiers {
            guard let entry = held[modifier.keyCode] else { continue }
            if entry.count == 1 { held.removeValue(forKey: modifier.keyCode) }
            else { held[modifier.keyCode] = (entry.flag, entry.count - 1) }
        }
    }

    var flags: CGEventFlags {
        lock.lock(); defer { lock.unlock() }
        return held.values.reduce(CGEventFlags()) { $0.union($1.flag) }
    }

    /// Mutate the existing event: never drop mouse movement, invent a key-up, or repeat a shortcut.
    /// Physical modifiers stay intact. With no remote hold, the event is returned unchanged.
    func apply(to event: CGEvent) {
        // Our keyboard events already capture the correct flags at creation. In particular,
        // queued onPress events must not acquire modifiers belonging to the later PTT key-down.
        guard event.getIntegerValueField(.eventSourceUserData) != Self.syntheticMarker else { return }
        event.flags.formUnion(flags)
    }

    func prepareSynthetic(_ event: CGEvent) {
        event.flags.formUnion(flags)
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
    }
}

final class HeldShortcutModifiers {
    static let shared = HeldShortcutModifiers()
    private let state = HeldModifierState()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Called before the first held key-down. Existing Accessibility authorization covers this tap.
    func begin(_ modifiers: [(keyCode: CGKeyCode, flag: CGEventFlags)]) {
        guard !modifiers.isEmpty else { return }
        if Thread.isMainThread { startIfNeeded() }
        else { DispatchQueue.main.sync { self.startIfNeeded() } }
        state.begin(modifiers)
    }

    func prepareSynthetic(_ event: CGEvent) { state.prepareSynthetic(event) }

    /// Called before posting the matching key-up so later mouse events no longer carry the hold.
    func end(_ modifiers: [(keyCode: CGKeyCode, flag: CGEventFlags)]) {
        state.end(modifiers)
    }

    private func startIfNeeded() {
        if let tap = eventTap {
            if !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        let types: [CGEventType] = [
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp, .scrollWheel, .keyDown, .keyUp, .flagsChanged
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context = context else { return Unmanaged.passUnretained(event) }
                let owner = Unmanaged<HeldShortcutModifiers>.fromOpaque(context).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = owner.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                } else {
                    owner.state.apply(to: event)
                }
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("[Siri Remote Vibe] held shortcut modifier tap unavailable; check Accessibility")
            return
        }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        if let source = source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("[Siri Remote Vibe] held shortcut modifier tap enabled")
    }
}
