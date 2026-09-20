import Foundation
import Combine

struct DictationRecord: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var words: Int
    var seconds: Double
    var app: String
    var category: StyleCategory
}

final class StatsStore: ObservableObject {
    static let shared = StatsStore()
    @Published private(set) var records: [DictationRecord] = []
    private let url = Settings.appSupport.appendingPathComponent("stats.json")
    static let typingWPM = 40.0

    private init() {
        if let d = try? Data(contentsOf: url), let r = try? JSONDecoder().decode([DictationRecord].self, from: d) { records = r }
    }
    func add(words: Int, seconds: Double, app: String, category: StyleCategory) {
        records.append(DictationRecord(date: Date(), words: words, seconds: seconds, app: app, category: category))
        if let d = try? JSONEncoder().encode(records) { try? d.write(to: url, options: .atomic) }
    }

    var totalWords: Int { records.reduce(0) { $0 + $1.words } }
    var totalSeconds: Double { records.reduce(0) { $0 + $1.seconds } }
    var averageWPM: Double { totalSeconds > 0 ? Double(totalWords) / (totalSeconds / 60) : 0 }
    /// Minutes saved vs typing at 40 wpm.
    var minutesSaved: Double { max(0, Double(totalWords) / Self.typingWPM - totalSeconds / 60) }
    var wordsThisWeek: Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        return records.filter { $0.date >= cutoff }.reduce(0) { $0 + $1.words }
    }
    var streakDays: Int {
        let cal = Calendar.current
        let days = Set(records.map { cal.startOfDay(for: $0.date) })
        var streak = 0
        var day = cal.startOfDay(for: Date())
        if !days.contains(day) { day = cal.date(byAdding: .day, value: -1, to: day)! }
        while days.contains(day) { streak += 1; day = cal.date(byAdding: .day, value: -1, to: day)! }
        return streak
    }
    var topApps: [(String, Int)] {
        var m: [String: Int] = [:]
        for r in records { m[r.app, default: 0] += r.words }
        return m.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) }
    }
    /// Words per day for the last `n` days, oldest first.
    func daily(_ n: Int = 30) -> [(Date, Int)] {
        let cal = Calendar.current
        var m: [Date: Int] = [:]
        for r in records { m[cal.startOfDay(for: r.date), default: 0] += r.words }
        return (0..<n).reversed().map { i in
            let d = cal.date(byAdding: .day, value: -i, to: cal.startOfDay(for: Date()))!
            return (d, m[d] ?? 0)
        }
    }
}
