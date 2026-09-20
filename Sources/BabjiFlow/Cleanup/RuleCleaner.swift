import Foundation

/// Deterministic cleanup that runs before any LLM polish: fillers, spoken commands,
/// self-corrections and punctuation normalisation.
enum RuleCleaner {
    static let fillers = ["um", "umm", "uh", "uhm", "uhh", "hmm", "hm", "mm", "mhm", "er", "erm", "ah", "aah", "eh"]

    static func clean(_ raw: String) -> String {
        var t = " " + raw.trimmingCharacters(in: .whitespacesAndNewlines) + " "

        // 1. Fillers (whole word, case-insensitive, with trailing punctuation)
        for f in fillers {
            t = t.replacingOccurrences(of: #"(?i)(?<=\s)\#(f)[,.]?(?=\s)"#, with: "", options: .regularExpression)
        }
        // "you know," / ", you know" as filler when comma-delimited
        t = t.replacingOccurrences(of: #"(?i),?\s+you know,\s+"#, with: " ", options: .regularExpression)

        // 2. "scratch that" / "strike that" drops the clause before it. Softer self-corrections
        //    ("no wait", "I mean") are left for the AI polish, which can keep the right half.
        let correctionMarkers = ["scratch that", "strike that", "delete that"]
        for m in correctionMarkers {
            let pattern = #"(?i)([^.!?\n]*?)[,.]?\s+\#(m)[,.]?\s+"#
            t = t.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        // repeated word stutter: "the the", "I I"
        t = t.replacingOccurrences(of: #"(?i)\b(\w+)(\s+\1\b)+"#, with: "$1", options: .regularExpression)

        // 3. Spoken commands
        let commands: [(String, String)] = [
            (#"(?i)[,.]?\s*\bnew paragraph\b[,.]?"#, "\n\n"),
            (#"(?i)[,.]?\s*\bnext paragraph\b[,.]?"#, "\n\n"),
            (#"(?i)[,.]?\s*\bnew line\b[,.]?"#, "\n"),
            (#"(?i)[,.]?\s*\bnext line\b[,.]?"#, "\n"),
            (#"(?i)[,.]?\s*\bbullet point\b[,.]?"#, "\n- "),
            (#"(?i)[,.]?\s*\bnext bullet\b[,.]?"#, "\n- "),
            (#"(?i)[,.]?\s*\bnext point\b[,.]?"#, "\n- "),
            (#"(?i)\s*\bquestion mark\b[,.]?"#, "?"),
            (#"(?i)\s*\bexclamation (mark|point)\b[,.]?"#, "!"),
            (#"(?i)\s*\bfull stop\b[,.]?"#, "."),
            (#"(?i)\s*\bopen (paren|parenthesis|bracket)\b"#, " ("),
            (#"(?i)\s*\bclose (paren|parenthesis|bracket)\b"#, ")"),
            (#"(?i)\s*\bsmiley face\b[,.]?"#, " :)"),
            (#"(?i)\s*\bthumbs up emoji\b[,.]?"#, " 👍"),
            (#"(?i)\s*\bat sign\b"#, "@"),
            (#"(?i)\s*\bhashtag\b\s*"#, " #"),
        ]
        for (p, r) in commands { t = t.replacingOccurrences(of: p, with: r, options: .regularExpression) }

        // 4. Normalisation
        t = t.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #" ([,.!?;:])"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"([,.!?;:])\1+"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #",\s*\."#, with: ".", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\n "#, with: "\n", options: .regularExpression)
        t = t.replacingOccurrences(of: #" \n"#, with: "\n", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(?<=\s)i(?=[\s'])"#, with: "I", options: .regularExpression)
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        // Leading punctuation left behind by removals
        t = t.replacingOccurrences(of: #"^[,.;:\s]+"#, with: "", options: .regularExpression)
        // Capitalise sentence starts (LLM polish may lower-case later for very casual)
        t = capitaliseSentences(t)
        return t
    }

    static func capitaliseSentences(_ s: String) -> String {
        guard !s.isEmpty else { return s }
        var out = ""
        var capNext = true
        var wordLen = 0          // letters in the current token (to spot abbreviations like p.m., e.g.)
        var pendingCap = false   // saw a terminator; capitalise only if whitespace follows
        for ch in s {
            if pendingCap {
                if ch.isWhitespace { capNext = true }
                pendingCap = false
            }
            if capNext, ch.isLetter {
                out.append(contentsOf: String(ch).uppercased()); capNext = false
            } else {
                out.append(ch)
            }
            if ch == "\n" { capNext = true }
            if ch == "!" || ch == "?" { pendingCap = true }
            if ch == "." { pendingCap = wordLen != 1 }   // "p.m." / "e.g." never end a sentence
            wordLen = ch.isLetter ? wordLen + 1 : (ch.isNumber ? 2 : 0)
        }
        return out
    }

    /// Detects an inline formatting instruction like "write this in points".
    static func wantsBullets(_ s: String) -> Bool {
        s.range(of: #"(?i)\b(in|as) (bullet )?points\b|\bbullet points\b|\bas a list\b"#, options: .regularExpression) != nil
    }
}
