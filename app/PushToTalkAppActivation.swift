import AppKit

/// An activation request is asynchronous. Only start the shortcut after the intended process is
/// actually frontmost; cancellation invalidates every pending callback from a previous press.
final class PushToTalkAppActivation {
    private var completion: ((NSRunningApplication?) -> Void)?
    private var work: DispatchWorkItem?
    private var generation = 0

    func start(target: String, completion: @escaping (NSRunningApplication?) -> Void) {
        cancel()
        let query = target.trimmingCharacters(in: .whitespacesAndNewlines)
        let running = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        guard let app = running.first(where: { $0.bundleIdentifier == query })
                ?? running.first(where: { $0.localizedName?.caseInsensitiveCompare(query) == .orderedSame }) else {
            rmDebug("🎙 PTT target not running: \(query)")
            completion(nil)
            return
        }
        self.completion = completion
        let token = generation
        rmDebug("🎙 PTT activation requested: \(query) pid=\(app.processIdentifier) front=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown")")
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
            finish(app)
            return
        }
        app.unhide()
        let accepted = app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        rmDebug("🎙 PTT activate accepted=\(accepted)")
        // LaunchServices can raise/reopen an existing window even if activate() alone leaves its
        // application behind another Space or a stale activation state. Do not launch a new copy.
        if let url = app.bundleURL {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            config.createsNewApplicationInstance = false
            NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] _, error in
                DispatchQueue.main.async {
                    guard let self, self.generation == token, self.completion != nil else { return }
                    if let error { rmDebug("🎙 PTT reopen error: \(error.localizedDescription)") }
                }
            }
        }
        poll(app, token: token, deadline: ProcessInfo.processInfo.systemUptime + 2,
             activeSince: nil)
    }

    private func poll(_ app: NSRunningApplication, token: Int, deadline: TimeInterval,
                      activeSince: TimeInterval?) {
        guard generation == token, completion != nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let active = NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
        let since = active ? (activeSince ?? now) : nil
        if app.isTerminated || now >= deadline {
            rmDebug("🎙 PTT activation failed/timed out: target=\(app.bundleIdentifier ?? "unknown") front=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown")")
            finish(nil)
        } else if let since, now - since >= 0.08 {
            rmDebug("🎙 PTT activation confirmed: \(app.bundleIdentifier ?? "unknown")")
            finish(app)
        } else {
            let item = DispatchWorkItem { [weak self] in
                self?.poll(app, token: token, deadline: deadline, activeSince: since)
            }
            work = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: item)
        }
    }

    private func finish(_ app: NSRunningApplication?) {
        let callback = completion
        completion = nil
        work?.cancel()
        work = nil
        callback?(app)
    }

    func cancel() {
        generation += 1
        work?.cancel()
        work = nil
        completion = nil
    }

    deinit { work?.cancel() }
}
