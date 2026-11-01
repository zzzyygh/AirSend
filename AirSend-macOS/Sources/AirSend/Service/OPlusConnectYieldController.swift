import AppKit
import Foundation

/// Pauses AirSend clipboard sync while O+ Connect (OPPO/HeyTap互联) is running,
/// so the two tools do not fight over the system pasteboard.
@MainActor
final class OPlusConnectYieldController {
    static let defaultsKey = "clipboard_yield_to_oplus_enabled"
    /// Bundle ID of /Applications/O+Connect.app (OPPO 互联 / O+互联).
    static let oplusBundleIdentifier = "com.oplus.devicespace"

    var onChange: ((Bool) -> Void)?

    private(set) var isYielding = false

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.defaultsKey) as? Bool ?? true }
        set {
            let previous = isEnabled
            UserDefaults.standard.set(newValue, forKey: Self.defaultsKey)
            if previous != newValue {
                refresh()
            }
        }
    }

    init() {
        refresh()
        startObserving()
    }

    // Lifetime equals AppDelegate; observers live for the process and need no teardown.

    private func startObserving() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ]
        for name in names {
            workspaceCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refresh()
                }
            }
        }

        // Fallback poll for processes we may miss (e.g. root-level Service daemon).
        let timer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        timer.tolerance = 1.5
        // Intentionally not stored: lives for app lifetime.
        RunLoop.main.add(timer, forMode: .common)
    }

    func refresh() {
        let shouldYield = isEnabled && Self.isOPlusConnectRunning()
        guard shouldYield != isYielding else { return }
        isYielding = shouldYield
        onChange?(shouldYield)
    }

    private static func isOPlusConnectRunning() -> Bool {
        if !NSRunningApplication.runningApplications(withBundleIdentifier: oplusBundleIdentifier).isEmpty {
            return true
        }
        // Fallback by localized/process name: O+Connect, OPPO 互联, O+Connect Service.
        return NSWorkspace.shared.runningApplications.contains { app in
            let names = [app.localizedName, app.bundleURL?.lastPathComponent]
            return names.contains { name in
                guard let name else { return false }
                return name == "O+Connect"
                    || name == "O+Connect.app"
                    || name == "O+Connect Service"
                    || name == "OPPO 互联"
                    || name == "O+互联"
            }
        }
    }
}
