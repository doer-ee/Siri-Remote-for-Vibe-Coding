public protocol ActionExecutor: AnyObject {
    func execute(_ action: Action, payload: EventPayload?)
}

/// Ties input events to the engine and executor. `mode` actions are handled
/// internally (they switch the engine's active mode) and never reach the executor.
public final class Controller {
    /// A binding that resolved successfully and is about to be handled. App-level presentation
    /// features can observe this without duplicating MappingEngine's layer/app inheritance rules.
    public struct HandledAction: Equatable {
        public let key: String
        public let action: Action
        public let presentation: Config.Presentation?

        public init(key: String, action: Action, presentation: Config.Presentation?) {
            self.key = key
            self.action = action
            self.presentation = presentation
        }
    }

    public enum LayerCycleTarget: Equatable {
        case unavailable
        case base
        case layer(String)
    }

    private var engine: MappingEngine
    private let executor: ActionExecutor

    /// The active layer (from a `.layer` button — held momentary or tap-toggled sticky). While set,
    /// a key `K` resolves PER-APP first — the layer-namespaced key `"<layer>.K"` looked up in the
    /// active app mode's `inherits` chain — so the same layer can do different things in different
    /// apps (e.g. `L1.ring.left` = switch tab in a terminal mode, something else in a browser mode).
    /// It then falls back to the standalone layer mode `<layer>` for app-agnostic layer bindings,
    /// and, for legacy overlay layers, to the unlayered binding in the current app.
    private var activeLayer: String? {
        didSet {
            guard activeLayer != oldValue else { return }
            onLayerChanged?(activeLayer)
        }
    }

    /// Notifies app-level features whenever the effective layer changes. This covers both sticky
    /// toggles and momentary holds because every layer transition flows through `pushLayer`/`popLayer`.
    public var onLayerChanged: ((String?) -> Void)?

    /// Fires exactly once for every binding `handle` accepts, immediately before the action is
    /// executed (or an internal mode switch is applied). Unbound input never reaches this hook.
    public var onActionHandled: ((HandledAction) -> Void)?

    public init(engine: MappingEngine, executor: ActionExecutor) {
        self.engine = engine
        self.executor = executor
    }

    /// Push a momentary layer (e.g. from a held `.layer` button). A second push simply replaces
    /// the active layer — there is only ever one at a time.
    public func pushLayer(_ name: String) {
        activeLayer = name
    }

    /// Pop the momentary layer, reverting resolution to the active app mode.
    public func popLayer() {
        activeLayer = nil
    }

    /// The layer mode currently overriding resolution, or nil when resolving against the app mode.
    public var currentLayer: String? { activeLayer }

    /// Destination after `current` in the user-authored cycle. A missing current id deliberately
    /// resets to the first entry (which validation guarantees is BASE) rather than guessing which
    /// custom layer should follow a stale id after hot reload.
    public func nextLayerInCycle(after current: String?) -> LayerCycleTarget {
        let layers = engine.configuredLayers
        guard !layers.isEmpty else { return .unavailable }
        let currentID = current ?? "BASE"
        let nextIndex: Int
        if let index = layers.firstIndex(where: {
            $0.id.caseInsensitiveCompare(currentID) == .orderedSame
        }) {
            nextIndex = (index + 1) % layers.count
        } else {
            nextIndex = 0
        }
        let id = layers[nextIndex].id
        return id == "BASE" ? .base : .layer(id)
    }

    private func site(_ key: String) -> MappingEngine.ResolvedBinding? {
        engine.resolveBinding(key, layer: activeLayer)
    }

    /// Native fallbacks (click, media keys, touch and built-in Voice) are also disabled in an
    /// independent layer. Explicit bindings still dispatch normally; release cleanup stays active.
    public func suppressesNativeBehavior(for key: String) -> Bool {
        guard let layer = activeLayer, !engine.layerInheritsBaseBindings(layer) else { return false }
        return site(key) == nil
    }

    private func resolve(_ key: String) -> Action? { site(key)?.action }

    /// Display overrides for `key`, taken from the very binding `resolve` would fire.
    public func resolvedPresentation(for key: String) -> Config.Presentation? {
        site(key)?.presentation
    }

    /// When this hold stage should fire, if its binding says so. Nil means fall back to the global
    /// threshold for that stage. Read from the SAME binding `resolve` would dispatch.
    public func resolvedHoldDelay(for key: String) -> Double? {
        site(key)?.holdDelay
    }

    /// Resolve and dispatch. Returns `true` if a binding matched (action dispatched or mode
    /// switched), `false` if the active mode has no binding for this event — letting the caller
    /// fall back to native behavior. While a layer is active, resolves against the layer instead.
    @discardableResult
    public func handle(_ event: InputEvent) -> Bool {
        guard let resolved = site(event.key) else { return false }
        reportHandled(HandledAction(key: event.key, action: resolved.action,
                                    presentation: resolved.presentation))
        if case let .mode(to) = resolved.action {
            engine.switchMode(to: to)
            return true
        }
        executor.execute(resolved.action, payload: event.payload)
        return true
    }

    /// Report a config action that an app-specific fast path executes directly instead of routing
    /// through `handle` (push-to-talk raw edges and genuine held-key repeat are the two macOS cases).
    /// Keeping the notification here preserves one observer contract without executing it twice.
    public func reportHandled(_ handled: HandledAction) {
        onActionHandled?(handled)
    }

    /// Resolve and report a directly-handled action using the same app/layer/presentation lookup as
    /// `handle`. Returns false when the binding disappeared before the direct path ran.
    @discardableResult
    public func reportResolvedAction(for eventKey: String) -> Bool {
        guard let resolved = site(eventKey) else { return false }
        reportHandled(HandledAction(key: eventKey, action: resolved.action,
                                    presentation: resolved.presentation))
        return true
    }

    public func frontmostAppChanged(bundleID: String) {
        engine.applyApp(bundleID: bundleID)
    }

    /// Whether the active mode/layer (or its inherits chain) binds this event. Used to decide if a
    /// button needs long-press discrimination (only defer the tap if a `.hold*` binding exists).
    public func hasBinding(for eventKey: String) -> Bool {
        resolve(eventKey) != nil
    }

    /// The action bound to `eventKey` in the active mode/layer (walking the inherits chain), without
    /// dispatching it — so the input handler can inspect the resolved action (e.g. detect a
    /// `.repeatKey`/`.layer` that needs press/release-driven handling). Same resolution as `handle`.
    public func resolvedAction(for eventKey: String) -> Action? {
        resolve(eventKey)
    }

    /// Hot-swap the config (e.g. after the config file changes on disk).
    public func reload(config: Config) {
        engine = MappingEngine(config: config)
    }
}
