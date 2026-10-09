import AppKit
import SwiftUI

/// Value rows and id-based callbacks remain safe when a save removes a row or reloads the config.
struct LayoutLayersManager: View {
    let config: Config
    let onSave: (Config) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pendingDelete: String?

    private var layers: [Config.LayerDefinition] {
        var result = config.settings.layers
        if result.isEmpty { result = [.init(id: "BASE")] }
        let existing = Set(result.map(\.id))
        let legacy = Set(config.modes.values.flatMap { mode in
            mode.bindings.values.compactMap { action -> String? in
                if case .layer(let id) = action, id != "BASE" { return id }
                return nil
            }
        }).subtracting(existing)
        return result + legacy.sorted().map { .init(id: $0, name: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Manage Layers")).font(.title2.bold())
            Text(L("Rename layers and choose whether unassigned inputs inherit the main layer."))
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(layers.enumerated()), id: \.element.id) { index, layer in
                        LayoutLayerNameRow(
                            layer: layer,
                            fallbackName: L("Layer %d", index + 1),
                            onRename: { onSave(config.renameLayer(layer.id, to: $0)) },
                            onDelete: { pendingDelete = layer.id },
                            inheritsBase: config.layerInheritsBaseBindings(layer.id),
                            onInheritance: { onSave(config.setLayerInheritance($0, for: layer.id)) }
                        )
                    }
                }
            }
            Text(L("The base layer is required and can be renamed. Deleting another layer removes its bindings and shortcuts that select it."))
                .font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button(L("Done")) { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(24).frame(width: 620, height: 440)
        .alert(L("Delete Layer?"), isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button(L("Cancel"), role: .cancel) { pendingDelete = nil }
            Button(L("Delete"), role: .destructive) {
                if let id = pendingDelete { onSave(config.removeLayer(id)) }
                pendingDelete = nil
            }
        } message: {
            Text(L("This removes the selected layer and its button mappings. Other layers and shared app profiles are kept."))
        }
    }
}

private struct LayoutLayerNameRow: View {
    let layer: Config.LayerDefinition
    let fallbackName: String
    let onRename: (String) -> Void
    let onDelete: () -> Void
    let inheritsBase: Bool
    let onInheritance: (Bool) -> Void
    @State private var draft: String

    init(layer: Config.LayerDefinition, fallbackName: String,
         onRename: @escaping (String) -> Void, onDelete: @escaping () -> Void,
         inheritsBase: Bool, onInheritance: @escaping (Bool) -> Void) {
        self.layer = layer
        self.fallbackName = fallbackName
        self.onRename = onRename
        self.onDelete = onDelete
        self.inheritsBase = inheritsBase
        self.onInheritance = onInheritance
        _draft = State(initialValue: layer.name ?? fallbackName)
    }

    private var title: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var changed: Bool { !title.isEmpty && title != (layer.name ?? fallbackName) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: layer.icon ?? "square.stack.3d.up.fill").foregroundStyle(.tint)
                TextField(L("Layer name"), text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { if changed { onRename(title) } }
                Button(L("Save")) { onRename(title) }.disabled(!changed)
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .disabled(layer.id == "BASE")
                .help(L("Delete Layer"))
            }
            if layer.id != "BASE" {
                Toggle(L("Inherit unassigned inputs from Main"), isOn: Binding(get: { inheritsBase }, set: onInheritance))
                    .font(.callout)
                Text(L("When off, unassigned inputs do nothing. Layer switching remains available."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .onChange(of: layer.name) { name in draft = name ?? fallbackName }
        .onChange(of: fallbackName) { name in if layer.name == nil { draft = name } }
    }
}

struct LayoutAppsManager: View {
    let config: Config
    let onSave: (Config) -> Void
    @Environment(\.dismiss) private var dismiss
    private enum Removal: Identifiable {
        case app(String), mode(String)
        var id: String {
            switch self { case .app(let id): return "app/" + id; case .mode(let id): return "mode/" + id }
        }
    }
    @State private var pendingDelete: Removal?

    private var profiles: [String] { config.appProfiles.keys.filter { $0 != "default" }.sorted() }
    private var unusedModes: [String] {
        let layerIDs = Set(config.settings.layers.map(\.id))
            .union(config.modes.values.flatMap { mode in
                mode.bindings.values.compactMap { action -> String? in
                    if case .layer(let id) = action { return id }
                    return nil
                }
            })
        return config.modes.keys.filter {
            $0 != config.defaultModeName && $0 != config.settings.defaultMode
                && !config.appProfiles.values.contains($0) && !layerIDs.contains($0)
        }.sorted()
    }

    private func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Manage Apps")).font(.title2.bold())
            Text(L("Choose each app's button profile, or remove apps you don't use."))
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if profiles.isEmpty {
                        Text(L("No app profiles. Add an app from Layout to customize its buttons."))
                            .foregroundStyle(.secondary).padding(.vertical, 16)
                    }
                    ForEach(profiles, id: \.self) { bundleID in
                        appRow(bundleID)
                    }
                    if !unusedModes.isEmpty {
                        Text(L("Unused profiles")).font(.headline).padding(.top, 12)
                        ForEach(unusedModes, id: \.self) { mode in
                            HStack {
                                Text(mode)
                                Spacer()
                                Button(role: .destructive) { pendingDelete = .mode(mode) } label: {
                                    Image(systemName: "trash")
                                }.help(L("Delete profile"))
                            }.padding(12)
                        }
                    }
                }
            }
            Text(L("Removing an app restores Global behavior for it. Shared profiles stay available to their other apps and layers."))
                .font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button(L("Done")) { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(24).frame(width: 700, height: 480)
        .alert(L("Delete App Profile?"), isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button(L("Cancel"), role: .cancel) { pendingDelete = nil }
            Button(L("Delete"), role: .destructive) {
                switch pendingDelete {
                case .app(let id): onSave(config.removeAppProfile(id))
                case .mode(let mode): onSave(config.removeMode(mode))
                case nil: break
                }
                pendingDelete = nil
            }
        } message: {
            Text(L("The app returns to Global bindings. If no other app or layer uses this profile, its custom mappings are also removed."))
        }
    }

    private func appRow(_ bundleID: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(appName(bundleID)).font(.body.weight(.medium))
                Text(bundleID).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Spacer()
            Picker(L("Profile"), selection: Binding(
                get: { config.appProfiles[bundleID] ?? config.defaultModeName },
                set: { mode in
                    guard config.appProfiles[bundleID] != nil, config.modes[mode] != nil else { return }
                    onSave(config.setAppProfile(bundleID: bundleID, mode: mode))
                }
            )) {
                ForEach(config.modes.keys.sorted(), id: \.self) { mode in
                    Text(mode == config.defaultModeName ? L("Global") : mode).tag(mode)
                }
            }.frame(width: 200)
            Button(role: .destructive) { pendingDelete = .app(bundleID) } label: {
                Image(systemName: "trash")
            }.help(L("Remove App"))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

/// Copy is a snapshot of mappings across all app profiles, not an inheritance relationship.
struct LayoutCopyLayerView: View {
    let config: Config
    let target: String
    let onSave: (Config) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var source: String = ""

    private var sources: [Config.LayerDefinition] { config.settings.layers.filter { $0.id != target } }
    private func title(_ id: String) -> String {
        config.settings.layers.first { $0.id == id }?.name ?? id
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Copy From…")).font(.title2.bold())
            Text(L("Copy button mappings into %@", title(target)))
            Picker(L("Source Layer"), selection: $source) {
                ForEach(sources, id: \.id) { layer in Text(title(layer.id)).tag(layer.id) }
            }
            Text(L("This replaces the target layer's mappings for all apps. Names and layer settings stay unchanged. Later edits to the source do not affect the copy."))
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(L("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("Copy")) {
                    onSave(config.copyLayerBindings(from: source, to: target))
                    dismiss()
                }.disabled(!sources.contains { $0.id == source }).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 500)
        .onAppear { source = sources.first?.id ?? "" }
    }
}
