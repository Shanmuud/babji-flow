import Foundation
import Security
import Combine

enum HotkeyChoice: String, CaseIterable, Identifiable, Codable {
    case fn, rightOption, rightCommand, leftControl
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fn: return "fn (Globe)"
        case .rightOption: return "Right Option ⌥"
        case .rightCommand: return "Right Command ⌘"
        case .leftControl: return "Left Control ⌃"
        }
    }
}

enum ModelChoice: String, CaseIterable, Identifiable, Codable {
    case v2, v3
    var id: String { rawValue }
    var label: String {
        switch self {
        case .v2: return "Parakeet TDT v2 · English only"
        case .v3: return "Parakeet TDT v3 · English + 24 languages (2.6% WER, recommended)"
        }
    }
}

enum PolishEngine: String, CaseIterable, Identifiable, Codable {
    case none, apple, claude, auto
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return "Fluid + AI polish (Apple on-device if enabled, else OpenAI/Claude) — recommended"
        case .apple: return "Fluid + Apple Intelligence polish only (on-device)"
        case .claude: return "Fluid + OpenAI/Claude polish only"
        case .none: return "Fluid only · no AI polish (fully offline)"
        }
    }
}

enum StyleCategory: String, CaseIterable, Identifiable, Codable {
    case personal, work, email, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .personal: return "Personal messages"
        case .work: return "Work messages"
        case .email: return "Email"
        case .other: return "Other"
        }
    }
    var blurb: String {
        switch self {
        case .personal: return "This style applies in personal messengers"
        case .work: return "This style applies in work chat apps"
        case .email: return "This style applies in email clients"
        case .other: return "This style applies everywhere else"
        }
    }
}

enum Tone: String, CaseIterable, Identifiable, Codable {
    case formal, casual, veryCasual
    var id: String { rawValue }
    var title: String {
        switch self {
        case .formal: return "Formal."
        case .casual: return "Casual"
        case .veryCasual: return "very casual"
        }
    }
    var subtitle: String {
        switch self {
        case .formal: return "Caps + Punctuation"
        case .casual: return "Caps + Less punctuation"
        case .veryCasual: return "No Caps + Less punctuation"
        }
    }
    var sample: String {
        switch self {
        case .formal: return "Hey, are you free for lunch tomorrow? Let's do 12 if that works for you."
        case .casual: return "Hey are you free for lunch tomorrow? Let's do 12 if that works for you"
        case .veryCasual: return "hey are you free for lunch tomorrow? let's do 12 if that works for you"
        }
    }
}

final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    @Published var hotkey: HotkeyChoice { didSet { d.set(hotkey.rawValue, forKey: "hotkey") } }
    @Published var model: ModelChoice { didSet { d.set(model.rawValue, forKey: "model") } }
    @Published var polishEngine: PolishEngine { didSet { d.set(polishEngine.rawValue, forKey: "polish") } }
    @Published var autoCleanup: Bool { didSet { d.set(autoCleanup, forKey: "autoCleanup") } }
    @Published var meetingDetection: Bool { didSet { d.set(meetingDetection, forKey: "meetingDetection") } }
    @Published var autoLearn: Bool { didSet { d.set(autoLearn, forKey: "autoLearn") } }
    @Published var contextAwareness: Bool { didSet { d.set(contextAwareness, forKey: "contextAwareness") } }
    @Published var commandMode: Bool { didSet { d.set(commandMode, forKey: "commandMode") } }
    @Published var soundCues: Bool { didSet { d.set(soundCues, forKey: "soundCues") } }
    @Published var styleSample: String { didSet { d.set(styleSample, forKey: "styleSample") } }
    @Published var tones: [StyleCategory: Tone] { didSet { saveTones() } }
    @Published var appCategories: [String: StyleCategory] { didSet { saveApps() } }
    @Published var claudeModel: String { didSet { d.set(claudeModel, forKey: "claudeModel") } }
    @Published var hasClaudeKey: Bool = false
    @Published var provider: AIProvider { didSet { d.set(provider.rawValue, forKey: "provider") } }
    @Published var hasOpenAIKey: Bool = false
    @Published var openaiModel: String { didSet { d.set(openaiModel, forKey: "openaiModel") } }
    @Published var openaiFastModel: String { didSet { d.set(openaiFastModel, forKey: "openaiFastModel") } }
    @Published var claudeWorkspace: String { didSet { d.set(claudeWorkspace, forKey: "claudeWorkspace") } }
    @Published var lastPolishError: String?
    @Published var launchCount: Int { didSet { d.set(launchCount, forKey: "launchCount") } }

    private init() {
        hotkey = HotkeyChoice(rawValue: d.string(forKey: "hotkey") ?? "") ?? .fn
        model = ModelChoice(rawValue: d.string(forKey: "model") ?? "") ?? .v3
        polishEngine = PolishEngine(rawValue: d.string(forKey: "polish") ?? "") ?? .auto
        autoCleanup = d.object(forKey: "autoCleanup") as? Bool ?? true
        meetingDetection = d.object(forKey: "meetingDetection") as? Bool ?? true
        autoLearn = d.object(forKey: "autoLearn") as? Bool ?? true
        contextAwareness = d.object(forKey: "contextAwareness") as? Bool ?? true
        commandMode = d.object(forKey: "commandMode") as? Bool ?? true
        soundCues = d.object(forKey: "soundCues") as? Bool ?? true
        styleSample = d.string(forKey: "styleSample") ?? ""
        claudeModel = d.string(forKey: "claudeModel") ?? "claude-opus-5"
        provider = AIProvider(rawValue: d.string(forKey: "provider") ?? "") ?? .openai
        openaiModel = d.string(forKey: "openaiModel") ?? "gpt-5.5"
        openaiFastModel = d.string(forKey: "openaiFastModel") ?? "gpt-5.4-mini"
        claudeWorkspace = d.string(forKey: "claudeWorkspace") ?? ""
        launchCount = d.integer(forKey: "launchCount")
        tones = [:]
        appCategories = [:]
        if let data = d.data(forKey: "tones"), let t = try? JSONDecoder().decode([StyleCategory: Tone].self, from: data) {
            tones = t
        } else {
            tones = [.personal: .veryCasual, .work: .casual, .email: .formal, .other: .casual]
        }
        if let data = d.data(forKey: "appCategories"), let a = try? JSONDecoder().decode([String: StyleCategory].self, from: data) {
            appCategories = a
        } else {
            appCategories = Settings.defaultAppCategories
        }
        hasClaudeKey = Keychain.exists("claude_api_key")
        hasOpenAIKey = Keychain.exists("openai_api_key")
    }

    private func saveTones() { if let data = try? JSONEncoder().encode(tones) { d.set(data, forKey: "tones") } }
    private func saveApps() { if let data = try? JSONEncoder().encode(appCategories) { d.set(data, forKey: "appCategories") } }

    var claudeKey: String? { Keychain.read("claude_api_key") }
    var openaiKey: String? { Keychain.read("openai_api_key") }
    func setOpenAIKey(_ key: String) {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if k.isEmpty { Keychain.delete("openai_api_key") } else { Keychain.write("openai_api_key", k) }
        hasOpenAIKey = !k.isEmpty
    }
    func setClaudeKey(_ key: String) {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if k.isEmpty { Keychain.delete("claude_api_key") } else { Keychain.write("claude_api_key", k) }
        hasClaudeKey = !k.isEmpty
    }

    func tone(for category: StyleCategory) -> Tone { tones[category] ?? .casual }

    func category(forBundle bundle: String?) -> StyleCategory {
        guard let bundle else { return .other }
        return appCategories[bundle] ?? .other
    }

    static let defaultAppCategories: [String: StyleCategory] = [
        "net.whatsapp.WhatsApp": .personal, "ru.keepcoder.Telegram": .personal, "com.hnc.Discord": .personal,
        "com.apple.MobileSMS": .personal, "org.whispersystems.signal-desktop": .personal, "com.facebook.archon": .personal,
        "com.tinyspeck.slackmacgap": .work, "com.microsoft.teams2": .work, "com.linear": .work, "notion.id": .work,
        "com.apple.mail": .email, "com.microsoft.Outlook": .email, "com.readdle.smartemail-Mac": .email, "com.superhuman.electron": .email,
    ]

    static let appSupport: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("BabjiFlow", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
}

/// API keys live in a 0600 file inside the app's data folder. The login Keychain re-prompts for a
/// password every time a self-signed build changes, which made AI features hang silently.
enum Keychain {
    static let service = "com.babji.flow"
    private static var url: URL { Settings.appSupport.appendingPathComponent("keys.json") }
    private static var cache: [String: String]? = nil
    private static func load() -> [String: String] {
        if let c = cache { return c }
        let d = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        cache = d; return d
    }
    private static func store(_ d: [String: String]) {
        cache = d
        if let data = try? JSONEncoder().encode(d) {
            try? data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }
    static func exists(_ account: String) -> Bool { !(load()[account] ?? "").isEmpty }
    static func read(_ account: String) -> String? { let v = load()[account]; return (v ?? "").isEmpty ? nil : v }
    static func write(_ account: String, _ value: String) { var d = load(); d[account] = value; store(d) }
    static func delete(_ account: String) { var d = load(); d.removeValue(forKey: account); store(d) }
}
