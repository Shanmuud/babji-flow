import Foundation
import Combine

struct TranscriptSegment: Codable, Identifiable, Equatable {
    var id = UUID()
    var speaker: String
    var start: Double
    var end: Double
    var text: String
}

struct MeetingSummary: Codable, Equatable {
    struct Section: Codable, Equatable, Identifiable {
        var id: String { heading }
        var heading: String
        var bullets: [String]
    }
    struct Step: Codable, Equatable, Identifiable {
        var id: String { owner + action }
        var owner: String
        var action: String
    }
    var title: String
    var overview: String
    var sections: [Section]
    var nextSteps: [Step]
    var decisions: [String]
}

struct ChatTurn: Codable, Identifiable, Equatable {
    var id = UUID()
    var role: String
    var text: String
}

struct Meeting: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var date: Date
    var duration: Double
    var app: String
    var segments: [TranscriptSegment] = []
    var summary: MeetingSummary?
    var summaryError: String?
    var speakerNames: [String: String] = [:]
    var chat: [ChatTurn] = []
    var audioFile: String?

    func displayName(for speaker: String) -> String { speakerNames[speaker] ?? speaker }

    var transcriptText: String {
        segments.map { s in
            let t = String(format: "[%02d:%02d]", Int(s.start) / 60, Int(s.start) % 60)
            return "\(t) \(displayName(for: s.speaker)): \(s.text)"
        }.joined(separator: "\n")
    }
    var readMinutes: Int { max(1, segments.reduce(0) { $0 + $1.text.split(separator: " ").count } / 220) }
}

final class MeetingStore: ObservableObject {
    static let shared = MeetingStore()
    @Published private(set) var meetings: [Meeting] = []
    private let url = Settings.appSupport.appendingPathComponent("meetings.json")
    static let audioDir: URL = {
        let d = Settings.appSupport.appendingPathComponent("recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private init() {
        if let d = try? Data(contentsOf: url), let m = try? JSONDecoder().decode([Meeting].self, from: d) { meetings = m }
    }
    private func save() {
        if let d = try? JSONEncoder().encode(meetings) { try? d.write(to: url, options: .atomic) }
    }
    func upsert(_ m: Meeting) {
        if let i = meetings.firstIndex(where: { $0.id == m.id }) { meetings[i] = m } else { meetings.insert(m, at: 0) }
        meetings.sort { $0.date > $1.date }
        save()
    }
    func delete(_ m: Meeting) {
        meetings.removeAll { $0.id == m.id }
        if let f = m.audioFile { try? FileManager.default.removeItem(at: Self.audioDir.appendingPathComponent(f)) }
        save()
    }
    func meeting(_ id: UUID) -> Meeting? { meetings.first { $0.id == id } }

    var grouped: [(String, [Meeting])] {
        let cal = Calendar.current
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"
        var out: [(String, [Meeting])] = []
        for m in meetings {
            let label: String
            if cal.isDateInToday(m.date) { label = "Today" }
            else if cal.isDateInYesterday(m.date) { label = "Yesterday, " + f.string(from: m.date) }
            else { label = f.string(from: m.date) }
            if let i = out.firstIndex(where: { $0.0 == label }) { out[i].1.append(m) } else { out.append((label, [m])) }
        }
        return out
    }
}
