import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// LLM polish of already rule-cleaned text, in the user's chosen tone for the current app.
enum StylePolisher {
    enum Engine { case apple, claude, none }

    static var appleAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// Human-readable reason when Apple Intelligence cannot be used.
    static var appleUnavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return nil
            case .unavailable(let r):
                switch r {
                case .deviceNotEligible: return "This Mac is not eligible for Apple Intelligence."
                case .appleIntelligenceNotEnabled: return "Apple Intelligence is off. Enable it in System Settings → Apple Intelligence & Siri."
                case .modelNotReady: return "Apple Intelligence model is still downloading."
                @unknown default: return "Apple Intelligence unavailable."
                }
            }
        }
        #endif
        return "Requires macOS 26."
    }

    static func resolveEngine() -> Engine {
        switch Settings.shared.polishEngine {
        case .none: return .none
        case .apple: return appleAvailable ? .apple : .none
        case .claude: return LLM.hasKey ? .claude : .none
        case .auto:
            if appleAvailable { return .apple }
            if LLM.hasKey { return .claude }
            return .none
        }
    }

    static func instructions(tone: Tone, category: StyleCategory, wantsBullets: Bool) -> String {
        var s = """
        You clean up voice dictation into text that will be typed into another app. Return ONLY the cleaned text, nothing else: no preamble, no quotes, no explanations.
        Rules:
        - Keep the speaker's meaning and words. Do not add content, do not answer questions in the text, do not summarise.
        - Remove filler words (um, uh, like, you know, so basically) and false starts. If the speaker corrects themselves ("no wait", "I mean", "actually"), keep only the corrected version.
        - Fix grammar lightly and add sensible punctuation. Convert spoken numbers to digits where natural (nineteen thousand -> 19,000; five pm -> 5pm).
        - If the speaker says how to format (for example "in points", "as a list", "new paragraph", "numbered list"), apply that formatting and remove the instruction itself.
        - Preserve line breaks and bullet markers that are already present.
        - Never wrap the output in quotes or code fences.
        """
        switch tone {
        case .formal:
            s += "\nTone: formal. Proper capitalisation and full punctuation, including a final period. Example: \"Hey, are you free for lunch tomorrow? Let's do 12 if that works for you.\""
        case .casual:
            s += "\nTone: casual. Normal capitalisation, lighter punctuation: skip commas that are not needed and do not put a period at the very end of the message. Example: \"Hey are you free for lunch tomorrow? Let's do 12 if that works for you\""
        case .veryCasual:
            s += "\nTone: very casual texting. Everything lowercase (including 'i' and names unless they are product names from the dictionary), minimal punctuation, no period at the end. Keep question marks. Example: \"hey are you free for lunch tomorrow? let's do 12 if that works for you\""
        }
        switch category {
        case .email: s += "\nContext: an email. Keep greeting and sign-off on their own lines if spoken."
        case .work: s += "\nContext: a work chat message (Slack/Teams)."
        case .personal: s += "\nContext: a personal chat message to a friend."
        case .other: s += "\nContext: a general text field (document, notes, search box, code comment)."
        }
        let words = DictionaryStore.shared.words
        if !words.isEmpty {
            s += "\nSpell these names/terms exactly like this when they appear (the speech engine often gets them wrong): " + words.joined(separator: ", ")
        }
        let sample = Settings.shared.styleSample.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sample.isEmpty {
            s += "\nMatch the writing style of these examples written by the user:\n" + sample
        }
        if wantsBullets { s += "\nThe speaker asked for points: output a bullet list, one idea per line, starting each line with '- '." }
        return s
    }

    static func polish(_ text: String, tone: Tone, category: StyleCategory) async -> String {
        let wantsBullets = RuleCleaner.wantsBullets(text)
        let engine = resolveEngine()
        let instr = instructions(tone: tone, category: category, wantsBullets: wantsBullets)
        var out: String? = nil
        switch engine {
        case .apple:
            #if canImport(FoundationModels)
            if #available(macOS 26, *) {
                do {
                    let session = LanguageModelSession(instructions: instr)
                    let r = try await session.respond(to: "Dictation:\n" + text)
                    out = r.content
                } catch {
                    out = nil
                }
            }
            #endif
            if out == nil, LLM.hasKey {
                do { out = try await claudePolish(text, instr) } catch { NSLog("AI polish failed: %@", error.localizedDescription); await MainActor.run { Settings.shared.lastPolishError = error.localizedDescription } }
            }
        case .claude:
            do { out = try await claudePolish(text, instr); await MainActor.run { Settings.shared.lastPolishError = nil } }
            catch {
                NSLog("AI polish failed: %@", error.localizedDescription)
                await MainActor.run { Settings.shared.lastPolishError = error.localizedDescription }
                out = nil
            }
        case .none:
            out = nil
        }
        if let o = out?.trimmingCharacters(in: .whitespacesAndNewlines), !o.isEmpty, Self.sane(o, original: text) {
            return stripQuotes(o)
        }
        return fallback(text, tone: tone)
    }

    static func claudePolish(_ text: String, _ instr: String) async throws -> String {
        try await LLM.complete(system: instr, messages: [ClaudeMessage(role: "user", content: "Dictation:\n" + text)], maxTokens: 2000, effort: "low", fast: true)
    }

    /// Guard against the model answering the dictation instead of cleaning it.
    private static func sane(_ out: String, original: String) -> Bool {
        let a = Double(out.split(separator: " ").count), b = Double(max(original.split(separator: " ").count, 1))
        return a <= b * 1.6 + 6 && a >= b * 0.3
    }

    private static func stripQuotes(_ s: String) -> String {
        var t = s
        if t.hasPrefix("\"") && t.hasSuffix("\"") && t.count > 2 { t = String(t.dropFirst().dropLast()) }
        if t.hasPrefix("```") { t = t.replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
        return t
    }

    /// Tone shaping without an LLM.
    static func fallback(_ text: String, tone: Tone) -> String {
        var t = text
        if RuleCleaner.wantsBullets(t) {
            t = t.replacingOccurrences(of: #"(?i)[,.]?\s*\b(write|put|give|do)( it| this| that)? (in|as) (bullet )?points\b[,.:]?\s*"#, with: "\n", options: .regularExpression)
            t = t.replacingOccurrences(of: #"(?i)[,.]?\s*\b(in|as) (bullet )?points\b[,.:]?\s*"#, with: "\n", options: .regularExpression)
            t = t.replacingOccurrences(of: #"(?i)^\s*(so |ok |okay |basically |so basically )+"#, with: "", options: .regularExpression)
            var parts = t.split(whereSeparator: { $0 == "." || $0 == "\n" }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            parts = parts.flatMap { part -> [String] in
                guard part.filter({ $0 == "," }).count >= 2 else { return [part] }
                return part.split(whereSeparator: { $0 == "," || $0 == ";" }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            }
            parts = parts.map { $0.replacingOccurrences(of: #"(?i)^(and |then |also )"#, with: "", options: .regularExpression) }
                         .map { $0.replacingOccurrences(of: #"[.,;]+$"#, with: "", options: .regularExpression) }
                         .map { RuleCleaner.capitaliseSentences($0) }
            if parts.count > 1 { t = parts.map { "- " + $0 }.joined(separator: "\n") }
        }
        switch tone {
        case .formal:
            if let last = t.last, !".!?".contains(last), !t.contains("\n") { t += "." }
        case .casual:
            if t.hasSuffix(".") { t.removeLast() }
        case .veryCasual:
            t = t.lowercased()
            if t.hasSuffix(".") { t.removeLast() }
            for w in DictionaryStore.shared.words {
                t = t.replacingOccurrences(of: "(?i)\\b" + NSRegularExpression.escapedPattern(for: w) + "\\b", with: w, options: .regularExpression)
            }
        }
        return t
    }
}
