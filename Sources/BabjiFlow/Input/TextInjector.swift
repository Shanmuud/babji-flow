import AppKit
import Carbon.HIToolbox

enum TextInjector {
    /// Pastes text into the focused app via the clipboard + Cmd-V, then restores the clipboard.
    static func paste(_ text: String) {
        let pb = NSPasteboard.general
        let saved = pb.pasteboardItems?.compactMap { item -> [NSPasteboard.PasteboardType: Data]? in
            var d: [NSPasteboard.PasteboardType: Data] = [:]
            for t in item.types { if let data = item.data(forType: t) { d[t] = data } }
            return d.isEmpty ? nil : d
        } ?? []
        pb.clearContents()
        pb.setString(text, forType: .string)

        let src = CGEventSource(stateID: .combinedSessionState)
        let vDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let vUp = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        vDown?.flags = .maskCommand; vUp?.flags = .maskCommand
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard pb.string(forType: .string) == text else { return }
            pb.clearContents()
            if !saved.isEmpty {
                let items = saved.map { dict -> NSPasteboardItem in
                    let item = NSPasteboardItem()
                    for (t, d) in dict { item.setData(d, forType: t) }
                    return item
                }
                pb.writeObjects(items)
            }
        }
    }
}

enum FrontmostApp {
    static var bundleID: String? { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
    static var name: String? { NSWorkspace.shared.frontmostApplication?.localizedName }
    static var category: StyleCategory { Settings.shared.category(forBundle: bundleID) }
}
