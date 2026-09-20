import Foundation
import Combine

struct DictionaryEntry: Identifiable, Codable, Equatable {
    enum Source: String, Codable { case manual, learned }
    var id = UUID()
    var word: String
    var misheard: [String] = []
    var source: Source = .manual
    var starred = false
    var createdAt = Date()
}

final class DictionaryStore: ObservableObject {
    static let shared = DictionaryStore()
    @Published private(set) var entries: [DictionaryEntry] = []
    private let url = Settings.appSupport.appendingPathComponent("dictionary.json")

    private init() { load() }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let e = try? JSONDecoder().decode([DictionaryEntry].self, from: data) else { return }
        entries = e
    }
    private func save() {
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: url, options: .atomic) }
    }

    func add(word: String, misheard: [String] = [], source: DictionaryEntry.Source = .manual) {
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty else { return }
        if let i = entries.firstIndex(where: { $0.word.caseInsensitiveCompare(w) == .orderedSame }) {
            var e = entries[i]
            for m in misheard where !e.misheard.contains(where: { $0.caseInsensitiveCompare(m) == .orderedSame }) { e.misheard.append(m) }
            entries[i] = e
        } else {
            entries.insert(DictionaryEntry(word: w, misheard: misheard, source: source), at: 0)
        }
        save()
    }
    func update(_ entry: DictionaryEntry) {
        if let i = entries.firstIndex(where: { $0.id == entry.id }) { entries[i] = entry; save() }
    }
    func remove(_ entry: DictionaryEntry) { entries.removeAll { $0.id == entry.id }; save() }
    func toggleStar(_ entry: DictionaryEntry) { var e = entry; e.starred.toggle(); update(e) }

    var words: [String] { entries.map(\.word) }

    /// Apply exact misheard replacements, then fuzzy matches against dictionary words.
    func apply(to text: String) -> String {
        var t = text
        for e in entries {
            for m in e.misheard where !m.isEmpty {
                let pattern = "(?i)\\b" + NSRegularExpression.escapedPattern(for: m) + "\\b"
                t = t.replacingOccurrences(of: pattern, with: e.word, options: .regularExpression)
            }
        }
        // Fuzzy: token within edit distance 1 (len>=5) of a dictionary word, not a common English word.
        let dict = entries.map(\.word).filter { $0.count >= 4 }
        guard !dict.isEmpty else { return t }
        var out = ""
        var token = ""
        func flush() {
            guard !token.isEmpty else { return }
            let lower = token.lowercased()
            if token.count >= 5, !Common.words.contains(lower) {
                for w in dict where abs(w.count - token.count) <= 1 {
                    if w.lowercased() == lower { out += w; token = ""; return }
                    if Levenshtein.distance(w.lowercased(), lower) <= 1 { out += w; token = ""; return }
                }
            }
            out += token; token = ""
        }
        for ch in t {
            if ch.isLetter || ch.isNumber || ch == "'" { token.append(ch) } else { flush(); out.append(ch) }
        }
        flush()
        return out
    }
}

enum Levenshtein {
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }; if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                let cost = a[i-1] == b[j-1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j-1] + 1, prev[j-1] + cost)
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }
}

enum Common {
    /// Guard list so fuzzy dictionary matching never rewrites everyday words.
    static let words: Set<String> = Set("""
    about above after again against almost along already also although always among another anyone anything around because become before began begin being below better between beyond bring build built called cannot carry cause change check child children close comes coming could country course create current daily doing during early earth either enough entire every everything example first found friend front further getting given going great group happen having heard heart hello house human ideas image important inside itself known large later learn least leave light little living local longer looking maybe might money month morning mother moving music myself never night nothing number often order other others outside people person place plans point power pretty probably problem public quite rather ready really reason right round school second seems sense should since small something sometimes sound speak spend start state still story study stuff sure system taken teach thank their there these thing think third those though thought three through today together took toward trying under until using usually value video visit voice watch water where which while white whole whose woman women words working world would write wrong years young thanks please meeting tomorrow yesterday everyone somebody someone anyway actually basically literally honestly obviously definitely absolutely exactly totally pretty little bigger smaller faster slower better worse happy sorry great awesome cool nice super weird crazy funny serious simple quick slowly quickly finally maybe perhaps whatever whenever wherever whoever yourself himself herself ourselves themselves message messages email emails call calls phone number project product feature features update updates design designs build builds launch launches
    """.split(whereSeparator: { $0.isWhitespace }).map(String.init))
}
