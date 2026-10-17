import AppKit

/// Push-to-talk keys. Modifier keys are used so holding them doesn't type anything.
enum Hotkey: String, CaseIterable, Codable {
    case rightOption
    case rightCommand
    case rightControl
    case fn

    var title: String {
        switch self {
        case .rightOption: return "Right Option ⌥"
        case .rightCommand: return "Right Command ⌘"
        case .rightControl: return "Right Control ⌃"
        case .fn: return "Fn / Globe 🌐"
        }
    }

    var keyCode: UInt16 {
        switch self {
        case .rightOption: return 61
        case .rightCommand: return 54
        case .rightControl: return 62
        case .fn: return 63
        }
    }

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .rightOption: return .option
        case .rightCommand: return .command
        case .rightControl: return .control
        case .fn: return .function
        }
    }
}

/// Watches a modifier key globally and reports press / release.
/// Needs Accessibility permission to see key events from other apps.
final class HotkeyMonitor {
    var key: Hotkey = .rightOption
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var isDown = false
    private var monitors: [Any] = []

    func start() {
        let handler: (NSEvent) -> Void = { [weak self] event in self?.handle(event) }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { event in
            handler(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    private func handle(_ event: NSEvent) {
        guard event.keyCode == key.keyCode else { return }
        let pressed = event.modifierFlags.contains(key.flag)
        if pressed && !isDown {
            isDown = true
            onPress?()
        } else if !pressed && isDown {
            isDown = false
            onRelease?()
        }
    }
}
