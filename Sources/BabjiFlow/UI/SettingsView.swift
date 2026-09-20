import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = Settings.shared
    @ObservedObject var transcriber = Transcriber.shared
    @State private var key = ""
    @State private var keySaved = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageTitle(text: "Settings")
                Card {
                    Text("DICTATION").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                    Picker("Hold to talk", selection: $settings.hotkey) { ForEach(HotkeyChoice.allCases) { Text($0.label).tag($0) } }
                        .onChange(of: settings.hotkey) { _, _ in DictationController.shared.restartHotkey() }
                    if settings.hotkey == .fn {
                        Text("Tip: set System Settings → Keyboard → “Press 🌐 key to” = Do Nothing, so the emoji picker does not pop up.").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                    Picker("Speech model", selection: $settings.model) { ForEach(ModelChoice.allCases) { Text($0.label).tag($0) } }
                        .onChange(of: settings.model) { _, _ in Transcriber.shared.ensureLoaded() }
                    Text(modelStatus).font(.system(size: 11)).foregroundStyle(Theme.muted)
                    Toggle("Detect meetings when another app opens the mic", isOn: $settings.meetingDetection)
                    Toggle("Command Mode (hold \(settings.hotkey.label) + Control, say an instruction, it edits the selected text)", isOn: $settings.commandMode)
                    Toggle("Context awareness (read the text around the cursor so names and sentences continue correctly)", isOn: $settings.contextAwareness)
                    Text("Hands-free: double-tap the hotkey to lock, tap again to finish, Esc to cancel.").font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                Card {
                    Text("AI PROVIDER (meeting notes, chat, optional dictation polish)").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                    Picker("Provider", selection: $settings.provider) { ForEach(AIProvider.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented).frame(width: 220)
                    if settings.provider == .openai {
                        HStack {
                            SecureField(settings.hasOpenAIKey ? "Key saved. Paste a new one to replace." : "sk-proj-…", text: $key)
                            Button("Save") { settings.setOpenAIKey(key); key = ""; keySaved = true }.disabled(key.isEmpty)
                            if settings.hasOpenAIKey { Button("Remove") { settings.setOpenAIKey(""); keySaved = false } }
                        }
                        Picker("Notes & chat model", selection: $settings.openaiModel) {
                            Text("GPT-5.5 (best)").tag("gpt-5.5"); Text("GPT-5.4").tag("gpt-5.4"); Text("GPT-5.4 mini").tag("gpt-5.4-mini")
                        }
                        Picker("Dictation polish model", selection: $settings.openaiFastModel) {
                            Text("GPT-5.4 mini (fast)").tag("gpt-5.4-mini"); Text("GPT-5.4 nano (fastest)").tag("gpt-5.4-nano"); Text("GPT-5.5").tag("gpt-5.5")
                        }
                    } else {
                        HStack {
                            SecureField(settings.hasClaudeKey ? "Key saved. Paste a new one to replace." : "sk-ant-…", text: $key)
                            Button("Save") { settings.setClaudeKey(key); key = ""; keySaved = true }.disabled(key.isEmpty)
                            if settings.hasClaudeKey { Button("Remove") { settings.setClaudeKey(""); keySaved = false } }
                        }
                        TextField("Workspace ID (wrkspc_…) — needed if your key is not scoped to a workspace", text: $settings.claudeWorkspace)
                        Picker("Model", selection: $settings.claudeModel) {
                            Text("Claude Opus 5 (best)").tag("claude-opus-5")
                            Text("Claude Sonnet 5 (cheaper)").tag("claude-sonnet-5")
                        }
                    }
                    if keySaved { Text("Saved.").font(.system(size: 11)).foregroundStyle(.green) }
                    if let e = settings.lastPolishError { Text(e).font(.system(size: 11)).foregroundStyle(.orange) }
                }
                Card {
                    Text("PERMISSIONS").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                    PermissionRow(name: "Accessibility", why: "hotkey, pasting, learning corrections", ok: Permissions.accessibilityGranted) { Permissions.promptAccessibility(); Permissions.openAccessibilitySettings() }
                    PermissionRow(name: "Microphone", why: "dictation and meeting audio", ok: nil) { Permissions.openMicrophoneSettings() }
                    PermissionRow(name: "Screen Recording", why: "the other side of calls (system audio)", ok: nil) { Permissions.openScreenRecordingSettings() }
                    Text("The app is signed with a local identity, so these grants survive rebuilds.").font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                Card {
                    Text("DATA").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                    HStack { Text(Settings.appSupport.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.muted); Spacer(); Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([Settings.appSupport]) } }
                    Text("Dictionary, stats, meeting notes and recordings live here as JSON/WAV. Audio never leaves the Mac except transcripts sent to Claude for summaries and chat.").font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
            }.padding(24)
        }
    }
    var modelStatus: String {
        switch transcriber.state {
        case .ready: return "Loaded. Models are cached in ~/Library/Application Support/FluidAudio."
        case .downloading(let p, let l): return "\(l)… \(Int(p * 100))%"
        case .loading: return "Building…"
        case .failed(let e): return "Failed: \(e)"
        case .idle: return "Not loaded"
        }
    }
}

struct PermissionRow: View {
    var name: String; var why: String; var ok: Bool?; var action: () -> Void
    var body: some View {
        HStack {
            if let ok { GradientDot(ok: ok) }
            Text(name).font(.system(size: 13, weight: .medium)); Text(why).font(.system(size: 12)).foregroundStyle(Theme.muted); Spacer()
            Button("Open Settings", action: action).font(.system(size: 12))
        }
    }
}
