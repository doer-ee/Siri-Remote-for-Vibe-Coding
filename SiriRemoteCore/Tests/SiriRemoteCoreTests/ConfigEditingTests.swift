import XCTest
@testable import SiriRemoteCore

/// Tests for the value-semantic config mutators the editor uses (`setBinding`, `addMode`,
/// `removeMode`, `setInherits`, `setAppProfile`, `withSettingsUpdated`). The key invariant: every
/// mutator's output must still LOAD — `ConfigLoader.load(ConfigWriter.serialize(c))` must succeed —
/// so a UI edit can never write a config that the app then rejects.
final class ConfigEditingTests: XCTestCase {

    private func load(_ json: String) throws -> Config { try ConfigLoader.load(json) }

    private func base() throws -> Config {
        try load("""
        { "settings": { "defaultMode": "global" },
          "appProfiles": { "com.apple.Music": "music", "default": "global" },
          "modes": {
            "global": {},
            "music":  { "inherits": "global" },
            "child":  { "inherits": "music" }
          } }
        """)
    }

    /// A mutator result must survive a serialize → load round-trip (never produce an invalid config).
    private func assertReloads(_ c: Config, _ msg: String = "", file: StaticString = #filePath, line: UInt = #line) {
        do { _ = try ConfigLoader.load(try ConfigWriter.serialize(c)) }
        catch { XCTFail("mutated config failed to reload: \(error) \(msg)", file: file, line: line) }
    }

    func testSetBindingCreatesMissingModeInheritingDefault() throws {
        let c = try base().setBinding("ring.up", to: .keystroke(keys: "up"), inMode: "newapp")
        XCTAssertEqual(c.modes["newapp"]?.inherits, "global")
        XCTAssertEqual(c.modes["newapp"]?.bindings["ring.up"], .keystroke(keys: "up"))
        assertReloads(c)
    }

    func testSetBindingNilRemoves() throws {
        var c = try base().setBinding("ring.up", to: .media(key: "playpause"), inMode: "global")
        XCTAssertNotNil(c.modes["global"]?.bindings["ring.up"])
        c = c.setBinding("ring.up", to: nil, inMode: "global")
        XCTAssertNil(c.modes["global"]?.bindings["ring.up"])
        assertReloads(c)
    }

    func testRemoveModeReparentsDanglingInherits() throws {
        // Removing "music" must not leave "child" inheriting a mode that no longer exists.
        let c = try base().removeMode("music")
        XCTAssertNil(c.modes["music"])
        XCTAssertNil(c.modes["child"]?.inherits, "child should be re-parented to nil, not left dangling")
        XCTAssertNil(c.appProfiles["com.apple.Music"], "appProfiles pointing at the removed mode are dropped")
        assertReloads(c, "removeMode output must still load")
    }

    func testRemoveModeRefusesToRemoveDefault() throws {
        let c = try base().removeMode("global")
        XCTAssertNotNil(c.modes["global"], "the default mode must not be removable")
        assertReloads(c)
    }

    func testAddAndRemoveOrderedLayerStayValid() throws {
        var c = try base().addLayer(id: "EDIT", name: "Editing", color: "orange",
                                    inherits: "global")
        XCTAssertEqual(c.settings.layers.map(\.id), ["BASE", "EDIT"])
        XCTAssertEqual(c.settings.layers[1].name, "Editing")
        XCTAssertEqual(c.modes["EDIT"]?.inherits, "global")
        assertReloads(c)

        c = c.removeMode("EDIT")
        XCTAssertEqual(c.settings.layers.map(\.id), ["BASE"])
        XCTAssertNil(c.modes["EDIT"])
        assertReloads(c)
    }

    func testAddLayerHonoursTenLayerLimit() throws {
        var c = try base()
        for i in 1...9 {
            c = c.addLayer(id: "L\(i)", name: nil, color: nil, inherits: "global")
        }
        XCTAssertEqual(c.settings.layers.count, 10)
        let unchanged = c.addLayer(id: "L10", name: nil, color: nil, inherits: "global")
        XCTAssertEqual(unchanged, c)
        XCTAssertNil(unchanged.modes["L10"])
        assertReloads(unchanged)
    }

    func testWithSettingsUpdatedRoundTrips() throws {
        let c = try base().withSettingsUpdated { s in
            s.cursorSpeed = 2.5
            s.holdThreshold = 0.8
            s.findCursorEnabled = false
        }
        XCTAssertEqual(c.settings.cursorSpeed, 2.5)
        XCTAssertEqual(c.settings.holdThreshold, 0.8)
        XCTAssertEqual(c.settings.findCursorEnabled, false)
        XCTAssertEqual(c.settings.defaultMode, "global", "untouched fields are preserved")
        // The written value must survive a serialize → load round-trip.
        let reloaded = try ConfigLoader.load(try ConfigWriter.serialize(c))
        XCTAssertEqual(reloaded.settings.cursorSpeed, 2.5)
        XCTAssertEqual(reloaded, c)
    }

    func testSetAppProfileAddAndRemove() throws {
        var c = try base().setAppProfile(bundleID: "com.google.Chrome", mode: "global")
        XCTAssertEqual(c.appProfiles["com.google.Chrome"], "global")
        c = c.setAppProfile(bundleID: "com.google.Chrome", mode: nil)
        XCTAssertNil(c.appProfiles["com.google.Chrome"])
        assertReloads(c)
    }

    func testRenameLayerPreservesIDBindingsAndVoiceSettings() throws {
        var c = try base().addLayer(id: "EDIT", name: "Editing", color: "orange", inherits: "global")
        c = c.setBinding("button.siri", to: .pushToTalk(keys: "ctrl+m"), inMode: "EDIT")
        let originalModes = c.modes
        let originalVoice = c.settings.dictation
        c = c.renameLayer("EDIT", to: "  Coding  ")
        XCTAssertEqual(c.settings.layers[1].name, "Coding")
        XCTAssertEqual(c.settings.layers[1].id, "EDIT")
        XCTAssertEqual(c.settings.layers[1].color, "orange")
        XCTAssertEqual(c.modes, originalModes)
        XCTAssertEqual(c.settings.dictation, originalVoice)
        XCTAssertEqual(c.renameLayer("EDIT", to: " \n "), c)
        assertReloads(c)
    }

    func testBaseLayerCanBeRenamedButNotDeleted() throws {
        let c = try base().renameLayer("BASE", to: "Main")
        XCTAssertEqual(c.settings.layers.first?.name, "Main")
        XCTAssertEqual(c.removeLayer("BASE"), c)
        assertReloads(c)
    }

    func testDeleteLayerRemovesSelectorsAndScopedOverridesWithoutResurrection() throws {
        var c = try base().addLayer(id: "EDIT", name: "Editing", inherits: "global")
        c = c.setBinding("button.tv", to: .layer("EDIT"), inMode: "global")
        c = c.setBinding("button.menu", to: .mode(to: "EDIT"), inMode: "music")
        c = c.setBinding("EDIT.button.siri", to: .keystroke(keys: "ctrl+m"), inMode: "music")
        c = c.setBinding("button.playPause", to: .media(key: "playpause"), inMode: "music")
        c.modes["music"]?.presentation["EDIT.button.siri"] = .init(label: "Talk")
        c.modes["music"]?.holdDelay["EDIT.button.siri"] = 0.5
        c.settings.dictation.layerModes["EDIT"] = .final
        let deleted = c.removeLayer("EDIT")
        XCTAssertEqual(deleted.settings.layers.map(\.id), ["BASE"])
        XCTAssertNil(deleted.modes["EDIT"])
        XCTAssertNil(deleted.modes["global"]?.bindings["button.tv"])
        XCTAssertNil(deleted.modes["music"]?.bindings["button.menu"])
        XCTAssertNil(deleted.modes["music"]?.bindings["EDIT.button.siri"])
        XCTAssertNil(deleted.modes["music"]?.presentation["EDIT.button.siri"])
        XCTAssertNil(deleted.modes["music"]?.holdDelay["EDIT.button.siri"])
        XCTAssertNil(deleted.settings.dictation.layerModes["EDIT"])
        XCTAssertEqual(deleted.modes["music"]?.bindings["button.playPause"], .media(key: "playpause"))
        assertReloads(deleted)
    }

    func testDeleteSharedLayerPreservesAppBindings() throws {
        let c = try base().addLayer(id: "music", name: "Music layer", inherits: "global")
            .setBinding("button.playPause", to: .media(key: "playpause"), inMode: "music")
            .setBinding("music.button.menu", to: .keystroke(keys: "esc"), inMode: "global")
            .setBinding("button.tv", to: .layer("music"), inMode: "global")
        let deleted = c.removeLayer("music")
        XCTAssertEqual(deleted.appProfiles["com.apple.Music"], "music")
        XCTAssertEqual(deleted.modes["music"]?.bindings["button.playPause"], .media(key: "playpause"))
        XCTAssertNil(deleted.modes["global"]?.bindings["music.button.menu"])
        XCTAssertNil(deleted.modes["global"]?.bindings["button.tv"])
        XCTAssertEqual(deleted.settings.layers.map(\.id), ["BASE"])
        assertReloads(deleted)
    }

    func testRemoveIndividualAppKeepsSharedProfileThenPrunesLastChip() throws {
        let c = try base().setAppProfile(bundleID: "com.other.Player", mode: "music")
        let first = c.removeAppProfile("com.apple.Music")
        XCTAssertNil(first.appProfiles["com.apple.Music"])
        XCTAssertEqual(first.appProfiles["com.other.Player"], "music")
        XCTAssertNotNil(first.modes["music"])
        assertReloads(first)
        let last = first.removeAppProfile("com.other.Player")
        XCTAssertNil(last.modes["music"])
        XCTAssertNil(last.modes["child"]?.inherits)
        assertReloads(last)
    }

    func testRemovingAppDoesNotRemoveLayerOrGlobalModes() throws {
        let c = try base().addLayer(id: "music", name: "Music layer", inherits: "global")
            .setAppProfile(bundleID: "com.apple.Notes", mode: "global")
        let deleted = c.removeAppProfile("com.apple.Music").removeAppProfile("com.apple.Notes")
        XCTAssertNotNil(deleted.modes["music"])
        XCTAssertNotNil(deleted.modes["global"])
        XCTAssertEqual(deleted.removeAppProfile("default"), deleted)
        assertReloads(deleted)
    }

    func testDefaultOverrideModeIsProtectedFromDeletion() throws {
        let c = try base().setAppProfile(bundleID: "default", mode: "music")
        XCTAssertEqual(c.removeMode("music"), c)
        assertReloads(c)
    }
    func testNewLayersAreIndependentAndLegacyLayersRetainOverlayBehavior() throws {
        let legacy = try base().withSettingsUpdated { $0.layers = [.init(id: "BASE"), .init(id: "child")] }
        XCTAssertTrue(legacy.layerInheritsBaseBindings("child"))
        let independent = legacy.setLayerInheritance(false, for: "child")
        XCTAssertFalse(independent.layerInheritsBaseBindings("child"))
        let reloaded = try load(ConfigWriter.serialize(independent))
        XCTAssertFalse(reloaded.layerInheritsBaseBindings("child"))
        let added = legacy.addLayer(id: "L2", inherits: "global")
        XCTAssertFalse(added.layerInheritsBaseBindings("L2"))
        XCTAssertTrue(added.layerInheritsBaseBindings("BASE"))
        assertReloads(added)
    }

    func testCopyLayerReplacesTargetAcrossAppsAndRetainsMetadataWithoutLiveLink() throws {
        let original = try load("""
        {"settings":{"defaultMode":"global","layers":[{"id":"BASE","name":"Main"},{"id":"L1","name":"Aux","inheritsBaseBindings":false}]},
         "appProfiles":{"default":"global","app":"editor"},
         "modes":{"global":{
            "button.menu":{"action":"keystroke","keys":"cmd+a","label":"Select all","icon":"command"},
            "button.siri.hold":{"action":"pushToTalk","keys":"ctrl+m","onPress":"opt+l","onRelease":"enter","after":0.2},
            "L1.button.menu":{"action":"keystroke","keys":"a"},
            "L1.ring.down":{"action":"keystroke","keys":"z"}},
            "editor":{"inherits":"global","button.menu":{"action":"keystroke","keys":"cmd+c"}},
            "L1":{"inherits":"global","ring.left":{"action":"keystroke","keys":"x"}}}}
        """)
        let copied = original.copyLayerBindings(from: "BASE", to: "L1")
        XCTAssertEqual(copied.settings, original.settings)
        XCTAssertEqual(copied.modes["global"]?.bindings["button.menu"], original.modes["global"]?.bindings["button.menu"])
        XCTAssertEqual(copied.modes["global"]?.bindings["L1.button.menu"], .keystroke(keys: "cmd+a"))
        XCTAssertEqual(copied.modes["editor"]?.bindings["L1.button.menu"], .keystroke(keys: "cmd+c"))
        XCTAssertNil(copied.modes["global"]?.bindings["L1.ring.down"])
        XCTAssertNil(copied.modes["L1"]?.bindings["ring.left"])
        XCTAssertEqual(copied.modes["global"]?.presentation["L1.button.menu"], original.modes["global"]?.presentation["button.menu"])
        XCTAssertEqual(copied.modes["global"]?.holdDelay["L1.button.siri.hold"], 0.2)
        XCTAssertEqual(copied.modes["global"]?.bindings["L1.button.siri.hold"], original.modes["global"]?.bindings["button.siri.hold"])
        let edited = copied.setBinding("button.menu", to: .keystroke(keys: "b"), inMode: "global")
        XCTAssertEqual(edited.modes["global"]?.bindings["L1.button.menu"], .keystroke(keys: "cmd+a"))
        assertReloads(copied)
        XCTAssertEqual(original.copyLayerBindings(from: "L1", to: "L1"), original)
        XCTAssertEqual(original.copyLayerBindings(from: "missing", to: "L1"), original)
    }

    func testCopyIndependentLayerToBaseDoesNotCopyItsMissingInputs() throws {
        let original = try base().addLayer(id: "L1", name: "Aux", inherits: "global")
            .setBinding("button.menu", to: .keystroke(keys: "b"), inMode: "global")
            .setBinding("L1.ring.up", to: .keystroke(keys: "a"), inMode: "global")
        let copied = original.copyLayerBindings(from: "L1", to: "BASE")
        XCTAssertNil(copied.modes["global"]?.bindings["button.menu"])
        XCTAssertEqual(copied.modes["global"]?.bindings["ring.up"], .keystroke(keys: "a"))
        XCTAssertEqual(copied.modes["global"]?.bindings["L1.ring.up"], .keystroke(keys: "a"))
        assertReloads(copied)
    }

}
