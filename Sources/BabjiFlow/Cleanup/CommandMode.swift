import Foundation
import AppKit
import Carbon.HIToolbox

/// Command Mode: hold fn+ctrl, say an instruction, release. The selected text (or the whole
/// field if nothing is selected) is rewritten by the AI and replaces the selection.
enum CommandMode {
    struct Target { var selected: String; var whole: String; var hadSelection: Bool }

    /// Grab selection via Accessibility, falling back to Cmd-C.
    static func captureTarget(pid: pid_t) -> Target {
        let whole = FocusedField.readValue(pid: pid) ?? ""
        if let sel = FocusedField.readSelectedText(pid: pid), !sel.isEmpty { return Target(selected: sel, whole: whole, hadSelection: true) }
        // Fallback: copy
        let pb = NSPasteboard.general
        let before = pb.changeCount
        let src = CGEventSource(stateID: .combinedSessionState)
        let d = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true); d?.flags = .maskCommand; d?.post(tap: .cghidEventTap)
        let u = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false); u?.flags = .maskCommand; u?.post(tap: .cghidEventTap)
        usleep(120_000)
        if pb.changeCount != before, let s = pb.string(forType: .string), !s.isEmpty { return Target(selected: s, whole: whole, hadSelection: true) }
        return Target(selected: whole, whole: whole, hadSelection: false)
    }

    static func run(instruction: String, target: Target, appName: String) async throws -> String {
        let system = """
        You edit text on the user's behalf. You receive an INSTRUCTION spoken by the user and the TEXT it applies to.
        Apply the instruction and return ONLY the resulting text: no preamble, no quotes, no explanation, no markdown fences.
        Keep everything the instruction does not ask to change. Preserve line breaks and list formatting. Keep the language of the text.
        If the instruction asks a question about the text rather than an edit, answer briefly in place of the text.
        App: \(appName).
        """
        let user = "INSTRUCTION: \(instruction)\n\nTEXT:\n\(target.selected)"
        return try await LLM.complete(system: system, messages: [ClaudeMessage(role: "user", content: user)], maxTokens: 4000, effort: "low", fast: true)
    }

    /// Replace the selection (or select all first when nothing was selected) with `text`.
    static func replace(with text: String, target: Target) {
        if !target.hadSelection {
            let src = CGEventSource(stateID: .combinedSessionState)
            let d = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_A), keyDown: true); d?.flags = .maskCommand; d?.post(tap: .cghidEventTap)
            let u = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_A), keyDown: false); u?.flags = .maskCommand; u?.post(tap: .cghidEventTap)
            usleep(80_000)
        }
        TextInjector.paste(text)
    }
}

extension FocusedField {
    static func readSelectedText(pid: pid_t) -> String? {
        let app: AXUIElement = pid > 0 ? AXUIElementCreateApplication(pid) : AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success, let el = focused else { return nil }
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(el as! AXUIElement, kAXSelectedTextAttribute as CFString, &value) == .success, let s = value as? String { return s }
        return nil
    }
    /// Text before and after the cursor/selection, for context.
    static func readAround(pid: pid_t, limit: Int = 400) -> (before: String, selected: String, after: String) {
        let app: AXUIElement = pid > 0 ? AXUIElementCreateApplication(pid) : AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success, let el = focused else { return ("", "", "") }
        let element = el as! AXUIElement
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &v) == .success, let whole = v as? String else { return ("", "", "") }
        var r: CFTypeRef?
        var range = CFRange(location: 0, length: 0)
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &r) == .success, let rv = r, CFGetTypeID(rv) == AXValueGetTypeID() {
            AXValueGetValue(rv as! AXValue, .cfRange, &range)
        } else {
            range = CFRange(location: whole.utf16.count, length: 0)
        }
        let u = Array(whole.utf16)
        let loc = max(0, min(range.location, u.count)), end = max(loc, min(range.location + range.length, u.count))
        func s(_ a: Int, _ b: Int) -> String { String(utf16CodeUnits: Array(u[a..<b]), count: b - a) }
        return (String(s(0, loc).suffix(limit)), s(loc, end), String(s(end, u.count).prefix(limit)))
    }
}
