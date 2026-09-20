import AppKit
import Carbon.HIToolbox

/// Hold-to-talk hotkey. Uses a CGEvent tap (needs Accessibility) so the fn key can be
/// caught reliably; falls back to NSEvent global monitors.
final class HotkeyMonitor {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isDown = false

    func start() {
        stop()
        let mask = (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = monitor.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            monitor.handle(flags: event.flags, keyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)))
            return Unmanaged.passUnretained(event)
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        if let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                       eventsOfInterest: CGEventMask(mask), callback: callback, userInfo: refcon) {
            self.tap = tap
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        } else {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
                self?.handle(flags: e.cgEvent?.flags ?? [], keyCode: Int(e.keyCode))
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
            self?.handle(flags: e.cgEvent?.flags ?? [], keyCode: Int(e.keyCode)); return e
        }
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        tap = nil; runLoopSource = nil
        if let g = globalMonitor { NSEvent.removeMonitor(g) }
        if let l = localMonitor { NSEvent.removeMonitor(l) }
        globalMonitor = nil; localMonitor = nil
    }

    private func handle(flags: CGEventFlags, keyCode: Int) {
        let choice = Settings.shared.hotkey
        let down: Bool
        switch choice {
        case .fn: down = flags.contains(.maskSecondaryFn)
        case .rightOption: down = flags.contains(.maskAlternate) && (keyCode == 61 || isDown)
        case .rightCommand: down = flags.contains(.maskCommand) && (keyCode == 54 || isDown)
        case .leftControl: down = flags.contains(.maskControl) && (keyCode == 59 || isDown)
        }
        // Ignore combos where other modifiers are held (e.g. fn+arrow) at press time.
        if down && !isDown {
            let others: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]
            let combo = flags.intersection(others)
            if choice == .fn && !combo.isEmpty { return }
            isDown = true
            DispatchQueue.main.async { self.onPress?() }
        } else if !down && isDown {
            isDown = false
            DispatchQueue.main.async { self.onRelease?() }
        }
    }
}

enum Permissions {
    static var accessibilityGranted: Bool { AXIsProcessTrusted() }
    static func promptAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }
    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    static func openScreenRecordingSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
    static func openMicrophoneSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }
}
