import Foundation
import FluidAudio

/// FluidAudio's NeMo inverse-text-normalisation: spoken numbers, times, money,
/// dates and ordinals become written form ("nineteen thousand" -> "19,000",
/// "five pm" -> "5 p.m."). Runs fully offline; no LLM involved.
enum Normalizer {
    static var isAvailable: Bool { TextNormalizer.shared.isNativeAvailable }

    static func apply(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var text = scaleWords(text)
        guard isAvailable else { return text }
        // Normalise per line so list markers and paragraph breaks survive.
        text = text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let s = String(line)
            guard !s.trimmingCharacters(in: .whitespaces).isEmpty else { return s }
            let out = TextNormalizer.shared.normalizeSentence(s)
            return out.isEmpty ? s : out
        }.joined(separator: "\n")
        // NeMo sometimes leaves "19 thousand"; finish the job.
        return scaleWords(text)
    }

    /// "19 thousand" -> "19,000", "2.5 million" -> "2,500,000" (Parakeet emits digits but keeps the scale word).
    static func scaleWords(_ s: String) -> String {
        let scales: [(String, Double)] = [("thousand", 1e3), ("k", 1e3), ("million", 1e6), ("billion", 1e9), ("lakh", 1e5), ("crore", 1e7)]
        var t = s
        for (w, m) in scales {
            let re = try! NSRegularExpression(pattern: #"(?i)\b(\d+(?:\.\d+)?)\s*"# + w + #"\b"#)
            let ns = t as NSString
            for match in re.matches(in: t, range: NSRange(location: 0, length: ns.length)).reversed() {
                guard let v = Double(ns.substring(with: match.range(at: 1))) else { continue }
                let n = v * m
                guard n < 1e15, n == n.rounded() else { continue }
                let f = NumberFormatter(); f.numberStyle = .decimal; f.usesGroupingSeparator = true
                t = ns.replacingCharacters(in: match.range, with: f.string(from: NSNumber(value: n)) ?? String(Int(n)))
            }
        }
        return t
    }
}
