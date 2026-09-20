import SwiftUI
import AppKit
import AVFoundation

/// Native first launch: no Windows runtime or installer is involved.
struct OnboardingView: View {
    @AppStorage("onboardingCompleteV2") private var complete = false
    @AppStorage("landscapeScene") private var scene = "forest"
    @State private var step = 0
    @State private var microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var accessibility = Permissions.accessibilityGranted
    @ObservedObject private var transcriber = Transcriber.shared
    private let paper = Color(red: 0.96, green: 0.94, blue: 0.90)
    private let ink = Color(red: 0.14, green: 0.25, blue: 0.20)

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 22) {
                    Text("BABJI  FLOW").font(.system(size: 13, weight: .semibold)).tracking(4)
                    Spacer(minLength: 8)
                    Text("0\(step + 1) / \(["YOUR COMPUTER", "YOUR ATMOSPHERE", "YOUR FIRST WORDS"][step])")
                        .font(.system(size: 10, weight: .medium)).tracking(2)
                    Text(["A place for\nyour voice.", "Find your\nkind of quiet.", "Let a thought\ntake shape."][step])
                        .font(.custom("Georgia", size: 49)).lineSpacing(-3)
                    if step == 0 {
                        Text("A small companion for your thoughts. Built to feel at home on your Mac.").lineSpacing(5)
                        Divider()
                        Label("macOS detected · native Apple Silicon app", systemImage: "checkmark.circle.fill")
                        Text("This app uses your Mac's local speech engine. No Windows components are installed.")
                            .font(.callout).foregroundStyle(.secondary)
                    } else if step == 1 {
                        ForEach(["forest", "sea", "desert"], id: \.self) { name in
                            Button { scene = name } label: {
                                HStack { Text(name.capitalized).font(.custom("Georgia", size: 24)); Spacer(); if scene == name { Image(systemName: "checkmark.circle.fill") } }
                                    .padding(14).background(scene == name ? ink.opacity(0.08) : .clear)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(ink.opacity(0.25)))
                            }.buttonStyle(.plain)
                        }
                    } else {
                        Button(microphone ? "Microphone allowed" : "Allow microphone") {
                            Task { microphone = await MicRecorder.requestPermission(); if !microphone { Permissions.openMicrophoneSettings() } }
                        }.disabled(microphone)
                        Button(accessibility ? "Accessibility allowed" : "Allow typing into other apps") { Permissions.promptAccessibility(); Permissions.openAccessibilitySettings() }
                        Button("Check permissions again") { accessibility = Permissions.accessibilityGranted; microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }
                            .font(.caption)
                        Button(transcriber.isReady ? "Speech model ready" : "Load local speech model") { transcriber.ensureLoaded() }.disabled(transcriber.isReady)
                        Text(modelStatus).font(.caption).foregroundStyle(.secondary)
                        Text("Hold your configured hotkey in a text field, speak, then release. Screen Recording is only needed for meeting audio.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    HStack {
                        if step > 0 { Button("Back") { step -= 1 } }
                        Spacer()
                        Button(step == 2 ? "Enter my workspace" : "Continue") {
                            if step < 2 { step += 1 }
                            else { complete = true; DictationController.shared.start(); VocabularyBooster.shared.start() }
                        }.buttonStyle(.borderedProminent).tint(ink)
                            .disabled(step == 2 && (!microphone || !accessibility || !transcriber.isReady))
                    }
                }.padding(40).frame(width: geometry.size.width * 0.49)
                ZStack(alignment: .bottomLeading) {
                    if let root = Bundle.main.resourceURL,
                       let artwork = NSImage(contentsOf: root.appendingPathComponent("Scenes/\(scene).png")) {
                        Image(nsImage: artwork).resizable().scaledToFill()
                    } else { paper }
                    Text("Room to breathe.\nSpace to speak.").font(.custom("Georgia", size: 32))
                        .padding(24).background(paper.opacity(0.93)).cornerRadius(12).padding(30)
                }.frame(width: geometry.size.width * 0.51, height: geometry.size.height).clipped()
            }.background(paper).foregroundStyle(ink)
        }.frame(minWidth: 980, minHeight: 640)
    }

    private var modelStatus: String {
        switch transcriber.state {
        case .idle: return "One download, then local speech recognition."
        case .downloading(_, let label): return label
        case .loading: return "Preparing your speech engine…"
        case .ready: return "Ready. Your speech stays on this Mac."
        case .failed(let message): return message
        }
    }
}
