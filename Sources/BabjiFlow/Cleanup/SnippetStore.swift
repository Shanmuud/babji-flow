import Foundation
import Combine

/// Say the trigger, get the expansion (emails, links, addresses, bios).
struct Snippet: Identifiable, Codable, Equatable {
    var id = UUID()
    var trigger: String
    var expansion: String
    var createdAt = Date()
}

final class SnippetStore: ObservableObject {
    static let shared = SnippetStore()
    @Published private(set) var snippets: [Snippet] = []
    private let url = Settings.appSupport.appendingPathComponent("snippets.json")

    private init() {
        if let d = try? Data(contentsOf: url), let s = try? JSONDecoder().decode([Snippet].self, from: d) { snippets = s }
    }
    private func save() { if let d = try? JSONEncoder().encode(snippets) { try? d.write(to: url, options: .atomic) } }

    func add(trigger: String, expansion: String) {
        let t = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !expansion.isEmpty else { return }
        if let i = snippets.firstIndex(where: { $0.trigger.caseInsensitiveCompare(t) == .orderedSame }) { snippets[i].expansion = expansion }
        else { snippets.insert(Snippet(trigger: t, expansion: expansion), at: 0) }
        save()
    }
    func update(_ s: Snippet) { if let i = snippets.firstIndex(where: { $0.id == s.id }) { snippets[i] = s; save() } }
    func remove(_ s: Snippet) { snippets.removeAll { $0.id == s.id }; save() }

    /// Replace spoken triggers (whole phrase, case-insensitive, tolerant of trailing punctuation).
    func apply(to text: String) -> String {
        var t = text
        for s in snippets.sorted(by: { $0.trigger.count > $1.trigger.count }) {
            let words = s.trigger.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }
            let pattern = "(?i)\\b" + words.joined(separator: "[\\s,]+") + "\\b[.,]?"
            t = t.replacingOccurrences(of: pattern, with: s.expansion.replacingOccurrences(of: "$", with: "\\$"), options: .regularExpression)
        }
        return t
    }
}
