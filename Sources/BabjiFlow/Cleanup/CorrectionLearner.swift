import Foundation
import ApplicationServices
import AppKit

/// After a paste, reads the focused text field back through Accessibility and diffs
/// it against what was pasted. Substituted words with a small edit distance become
/// learned dictionary entries (misheard -> corrected).
final class CorrectionLearner {
    static let shared = CorrectionLearner()
    private var pending: (text: String, pid: pid_t, at: Date)?
    private var timer: Timer?

    func didPaste(_ text: String) {
        guard Settings.shared.autoLearn else { return }
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        pending = (text, pid, Date())
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: false) { [weak self] _ in self?.check() }
    }

    /// Called right before the next dictation starts so late corrections are still caught.
    func flush() { check() }

    private func check() {
        timer?.invalidate(); timer = nil
        guard let p = pending else { return }
        pending = nil
        guard let fieldText = FocusedField.readValue(pid: p.pid), !fieldText.isEmpty else { return }
        let learned = Self.diff(pasted: p.text, field: fieldText)
        for (wrong, right) in learned {
            DictionaryStore.shared.add(word: right, misheard: [wrong], source: .learned)
        }
    }

    static func tokens(_ s: String) -> [String] {
        s.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "'" || $0 == "-") }).map(String.init)
    }

    /// Returns (misheard, corrected) pairs.
    static func diff(pasted: String, field: String) -> [(String, String)] {
        let a = tokens(pasted), b = tokens(field)
        guard !a.isEmpty, !b.isEmpty, a != b else { return [] }
        // LCS table on lowercased tokens
        let la = a.map { $0.lowercased() }, lb = b.map { $0.lowercased() }
        let n = la.count, m = lb.count
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                dp[i][j] = la[i] == lb[j] ? dp[i+1][j+1] + 1 : max(dp[i+1][j], dp[i][j+1])
            }
        }
        var i = 0, j = 0
        var deleted: [String] = [], inserted: [String] = []
        var pairs: [(String, String)] = []
        func settle() {
            // pair up deleted/inserted runs by best edit distance
            for d in deleted {
                guard d.count >= 3 else { continue }
                var best: (String, Int)? = nil
                for ins in inserted {
                    let dist = Levenshtein.distance(d.lowercased(), ins.lowercased())
                    if dist > 0, dist <= max(1, ins.count / 3), best == nil || dist < best!.1 { best = (ins, dist) }
                }
                if let b = best, b.0.lowercased() != d.lowercased(), !Common.words.contains(b.0.lowercased()) {
                    pairs.append((d, b.0))
                    inserted.removeAll { $0 == b.0 }
                }
            }
            deleted = []; inserted = []
        }
        while i < n && j < m {
            if la[i] == lb[j] { settle(); i += 1; j += 1 }
            else if dp[i+1][j] >= dp[i][j+1] { deleted.append(a[i]); i += 1 }
            else { inserted.append(b[j]); j += 1 }
        }
        while i < n { deleted.append(a[i]); i += 1 }
        while j < m { inserted.append(b[j]); j += 1 }
        settle()
        return pairs
    }
}

enum FocusedField {
    static func readValue(pid: pid_t) -> String? {
        let app: AXUIElement = pid > 0 ? AXUIElementCreateApplication(pid) : AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let el = focused else { return nil }
        let element = el as! AXUIElement
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success, let s = value as? String {
            return s
        }
        return nil
    }
}
