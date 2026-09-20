import Foundation

enum Summarizer {
    static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "title": ["type": "string"],
            "overview": ["type": "string"],
            "sections": ["type": "array", "items": [
                "type": "object",
                "properties": ["heading": ["type": "string"], "bullets": ["type": "array", "items": ["type": "string"]]],
                "required": ["heading", "bullets"], "additionalProperties": false]],
            "next_steps": ["type": "array", "items": [
                "type": "object",
                "properties": ["owner": ["type": "string"], "action": ["type": "string"]],
                "required": ["owner", "action"], "additionalProperties": false]],
            "decisions": ["type": "array", "items": ["type": "string"]],
            "speaker_names": ["type": "array", "items": [
                "type": "object",
                "properties": ["label": ["type": "string"], "name": ["type": "string"]],
                "required": ["label", "name"], "additionalProperties": false]],
        ],
        "required": ["title", "overview", "sections", "next_steps", "decisions", "speaker_names"],
        "additionalProperties": false,
    ]

    static let system = """
    You write meeting notes from a transcript. Be terse, concrete and factual. Write like a sharp chief of staff, not a narrator.
    - title: 3-6 words naming what the meeting was actually about.
    - overview: ONE sentence, max 35 words, saying who talked about what and the main outcome. Refer to people by name when the transcript reveals it, otherwise by speaker label (e.g. "Speaker 2"). Never write "Speaker 2/Samir"; pick one.
    - Write every number as digits with units: 19,000 rupees/month, $100/week, 53%, 10x, ~15k, 24/7, 11 months.
    - Bullets are facts, not reported speech: write "Pays 19,000 rupees/month rent" not "Speaker 5 said they pay...". Attribute only when it matters who said it.
    - sections: 3-6 themed sections. Each heading is a short noun phrase ("Tappr Pivot & GTM"). Each bullet is one fact, number, or claim from the transcript, under 25 words, no fluff, keep the exact figures and names mentioned. 2-5 bullets per section.
    - next_steps: every concrete action someone said they would do, with the owner label and a specific action.
    - decisions: things explicitly decided or settled. Empty array if none.
    - speaker_names: if the transcript makes a speaker's real name clear (introductions, being addressed by name, "this is Samir"), map the label to that name. Only include confident mappings; otherwise an empty array. Never guess.
    Never invent facts. If the transcript is short or unclear, keep the notes short.
    """

    static func summarise(_ meeting: Meeting) async -> Meeting {
        var m = meeting
        m.summaryError = nil
        let transcript = meeting.transcriptText
        guard !transcript.isEmpty else { m.summaryError = "Nothing was transcribed."; return m }
        guard LLM.hasKey else { m.summaryError = LLM.missingKeyMessage + " Summaries need an AI provider."; return m }
        do {
            let raw = try await LLM.complete(
                system: system,
                messages: [ClaudeMessage(role: "user", content: "Meeting recorded via \(meeting.app) on \(meeting.date.formatted()). Transcript:\n\n" + transcript)],
                maxTokens: 6000, effort: "medium", jsonSchema: schema)
            guard let data = raw.data(using: .utf8), let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                m.summaryError = "Could not parse summary."; return m
            }
            let sections = (obj["sections"] as? [[String: Any]] ?? []).map {
                MeetingSummary.Section(heading: $0["heading"] as? String ?? "", bullets: $0["bullets"] as? [String] ?? [])
            }
            let steps = (obj["next_steps"] as? [[String: Any]] ?? []).map {
                MeetingSummary.Step(owner: $0["owner"] as? String ?? "", action: $0["action"] as? String ?? "")
            }
            m.summary = MeetingSummary(title: obj["title"] as? String ?? m.title, overview: obj["overview"] as? String ?? "",
                                       sections: sections, nextSteps: steps, decisions: obj["decisions"] as? [String] ?? [])
            if let t = obj["title"] as? String, !t.isEmpty { m.title = t }
            for pair in obj["speaker_names"] as? [[String: Any]] ?? [] {
                if let l = pair["label"] as? String, let n = pair["name"] as? String, !n.isEmpty, m.speakerNames[l] == nil, l != "You" { m.speakerNames[l] = n }
            }
        } catch {
            m.summaryError = error.localizedDescription
        }
        return m
    }
}

/// Chat grounded in one meeting's transcript. Transcript sits in a cached system block.
enum TranscriptChat {
    static func systemBlocks(for m: Meeting) -> [[String: Any]] {
        var context = "You are a helpful assistant answering questions about a meeting the user attended. Use only the transcript and notes below; if something is not in them, say so. Be direct and specific, quote short bits of the transcript when useful. Refer to people by speaker label or name.\n\nMEETING: \(m.title) on \(m.date.formatted())\n"
        if let s = m.summary {
            context += "\nNOTES:\n\(s.overview)\n"
            for sec in s.sections { context += "\n\(sec.heading)\n" + sec.bullets.map { "- " + $0 }.joined(separator: "\n") + "\n" }
            if !s.nextSteps.isEmpty { context += "\nNext steps:\n" + s.nextSteps.map { "- (\($0.owner)) \($0.action)" }.joined(separator: "\n") + "\n" }
        }
        context += "\nTRANSCRIPT:\n" + m.transcriptText
        return [["type": "text", "text": context, "cache_control": ["type": "ephemeral"]]]
    }

    static func ask(_ meeting: Meeting, history: [ChatTurn]) -> AsyncThrowingStream<String, Error> {
        let msgs = history.map { ClaudeMessage(role: $0.role, content: $0.text) }
        return LLM.stream(system: systemBlocks(for: meeting), messages: msgs, maxTokens: 4000, effort: "medium")
    }

    /// Cross-meeting chat used by the Notetaker home bar.
    static func askAll(_ meetings: [Meeting], question: String) -> AsyncThrowingStream<String, Error> {
        var context = "You answer questions across the user's recent meeting notes. Be specific about which meeting each fact came from. If nothing relevant exists, say so.\n"
        for m in meetings.prefix(15) {
            context += "\n=== \(m.title) · \(m.date.formatted()) ===\n"
            if let s = m.summary {
                context += s.overview + "\n"
                for sec in s.sections { context += sec.heading + ": " + sec.bullets.joined(separator: " | ") + "\n" }
                if !s.nextSteps.isEmpty { context += "Next steps: " + s.nextSteps.map { "(\($0.owner)) \($0.action)" }.joined(separator: " | ") + "\n" }
            } else {
                context += String(m.transcriptText.prefix(4000)) + "\n"
            }
        }
        let system: [[String: Any]] = [["type": "text", "text": context, "cache_control": ["type": "ephemeral"]]]
        return LLM.stream(system: system, messages: [ClaudeMessage(role: "user", content: question)], maxTokens: 3000, effort: "medium")
    }
}
