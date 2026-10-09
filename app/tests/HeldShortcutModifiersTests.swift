import Foundation
import CoreGraphics
import Carbon.HIToolbox

/// No event taps or posted input: test the exact flag transformation used by the live tap.
@main
struct HeldShortcutModifiersTests {
    static func main() {
        let state = HeldModifierState()
        let control = CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | 0x1)
        let rightControl = CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | 0x2000)
        let mods: [(keyCode: CGKeyCode, flag: CGEventFlags)] = [(CGKeyCode(kVK_Control), control)]
        let rightMods: [(keyCode: CGKeyCode, flag: CGEventFlags)] = [(CGKeyCode(kVK_RightControl), rightControl)]
        let opener = CGEvent(source: nil)!
        opener.type = .keyDown
        opener.flags = .maskAlternate
        state.prepareSynthetic(opener)
        state.begin(mods)
        state.apply(to: opener)
        precondition(opener.flags == .maskAlternate, "Queued onPress keeps its original shortcut")
        let duringHold = CGEvent(source: nil)!
        duringHold.flags = .maskAlternate
        state.prepareSynthetic(duringHold)
        precondition(duringHold.flags.contains(.maskControl), "Other synthetic keys preserve the held modifier")
        for type: CGEventType in [.mouseMoved, .leftMouseDragged, .scrollWheel, .flagsChanged, .keyDown, .keyUp] {
            let event = CGEvent(source: nil)!
            event.type = type
            event.flags = .maskShift
            event.location = CGPoint(x: 200, y: 300)
            state.apply(to: event)
            precondition(event.flags.contains(.maskControl), "Mouse/keyboard events must retain held Ctrl")
            precondition(event.flags.contains(.maskShift), "Physical Shift must survive")
            precondition(event.type == type && event.location == CGPoint(x: 200, y: 300), "Original event is preserved")
        }
        // Two simultaneous remote holds sharing Ctrl: one release cannot clear the other.
        state.begin(mods)
        state.end(mods)
        precondition(state.flags == control)
        state.begin(rightMods)
        state.end(mods)
        precondition(state.flags == rightControl, "Releasing left Ctrl retains the other held side")
        state.end(rightMods)
        precondition(state.flags.isEmpty, "Final release clears all synthetic modifiers")
        let afterRelease = CGEvent(source: nil)!
        afterRelease.type = .mouseMoved
        afterRelease.flags = .maskAlternate
        state.apply(to: afterRelease)
        precondition(afterRelease.flags == .maskAlternate, "No stuck Ctrl after release/teardown")
        state.end(mods)
        state.begin([])
        precondition(state.flags.isEmpty, "Unmatched cleanup and modifier-free holds stay neutral")
        print("PASS: held Ctrl survives mouse/keyboard events; physical flags and overlapping holds preserved; release clears state")
    }
}
