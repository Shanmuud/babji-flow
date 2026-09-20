import SwiftUI
import AppKit
import Combine
import ScreenCaptureKit

struct BabjiFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
        } label: {
            Image(systemName: "waveform")
        }
    }
}

struct MenuContent: View {
    @ObservedObject var dictation = DictationController.shared
    @ObservedObject var recorder = MeetingRecorder.shared
    @ObservedObject var settings = Settings.shared
    var body: some View {
        Text("Hold \(settings.hotkey.label) to dictate")
        Divider()
        Button("Open Babji Flow") { AppDelegate.shared?.openMain(.home) }
        Button("Dictionary") { AppDelegate.shared?.openMain(.dictionary) }
        Button("Style") { AppDelegate.shared?.openMain(.style) }
        Button("Notetaker") { AppDelegate.shared?.openMain(.notetaker) }
        Divider()
        if recorder.isRecording {
            Button("Stop meeting recording") { Task { _ = await recorder.stop(); AppDelegate.shared?.openMain(.notetaker) } }
        } else {
            Button("Start meeting recording") { Task { await recorder.start(app: MicActivityMonitor.likelyMeetingApp() ?? "Manual") } }
        }
        Divider()
        Button("Settings…") { AppDelegate.shared?.openMain(.settings) }
        Button("Quit Babji Flow") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    private var window: NSWindow?
    private let micMonitor = MicActivityMonitor()
    private var subs = Set<AnyCancellable>()
    private var meetingDismissedAt: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.accessory)
        Settings.shared.launchCount += 1

        let notch = NotchController.shared
        notch.onRecordMeeting = { [weak self] in self?.startMeeting() }
        notch.onDismissMeeting = { [weak self] in self?.meetingDismissedAt = Date(); notch.hide() }
        notch.onStopMeeting = { [weak self] in self?.stopMeeting() }

        DictationController.shared.micMonitor = micMonitor
        MeetingRecorder.shared.micMonitor = micMonitor
        micMonitor.start()
        micMonitor.$externalMicInUse.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] inUse in
            self?.micChanged(inUse)
        }.store(in: &subs)

        NSLog("BabjiFlow launched; accessibility=\(Permissions.accessibilityGranted)")
        for sc in NSScreen.screens { NSLog("screen \(sc.localizedName) frame=\(sc.frame) safeTop=\(sc.safeAreaInsets.top) auxL=\(String(describing: sc.auxiliaryTopLeftArea)) auxR=\(String(describing: sc.auxiliaryTopRightArea))") }
        if UserDefaults.standard.bool(forKey: "onboardingCompleteV2") {
            Transcriber.shared.ensureLoaded()
            VocabularyBooster.shared.start()
        }
        Transcriber.shared.$state.receive(on: DispatchQueue.main).sink { st in
            NSLog("Transcriber state: \(st)")
            switch st {
            case .downloading(let p, let l): NotchController.shared.show(.downloading(p, l))
            case .loading: NotchController.shared.show(.processing("Building"))
            case .ready:
                if case .downloading = NotchController.shared.state { NotchController.shared.show(.done("Ready"), autoHideAfter: 1.5) }
                else if case .processing = NotchController.shared.state { NotchController.shared.show(.done("Ready"), autoHideAfter: 1.5) }
            case .failed(let e): NotchController.shared.show(.error(e), autoHideAfter: 6)
            case .idle: break
            }
        }.store(in: &subs)
        Task {
            guard UserDefaults.standard.bool(forKey: "onboardingCompleteV2") else { return }
            let ok = await MicRecorder.requestPermission()
            NSLog("Mic permission: \(ok)")
            if !ok { NotchController.shared.show(.error("Microphone access denied. Enable it in System Settings."), autoHideAfter: 5) }
            if !Permissions.accessibilityGranted { Permissions.promptAccessibility() }
            DictationController.shared.start()
            // Trigger the Screen Recording prompt once so meeting capture just works later.
            if !UserDefaults.standard.bool(forKey: "askedScreen") {
                UserDefaults.standard.set(true, forKey: "askedScreen")
                _ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            }
        }
        if let i = CommandLine.arguments.firstIndex(of: "--demo-notch"), i + 1 < CommandLine.arguments.count {
            // Debug: hold the notch in a given state for screenshots.
            let which = CommandLine.arguments[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                switch which {
                case "listening": NotchController.shared.show(.listening); NotchController.shared.level = 0.7
                case "meeting": NotchController.shared.show(.meetingDetected("Zoom"))
                case "recording": NotchController.shared.show(.meetingRecording)
                case "done": NotchController.shared.show(.done("hey are you free for lunch tomorrow?"))
                default: NotchController.shared.show(.processing("Polishing…"))
                }
            }
        }
        if let i = CommandLine.arguments.firstIndex(of: "--open"), i + 1 < CommandLine.arguments.count, let p = Page(rawValue: CommandLine.arguments[i + 1]) {
            openMain(p)
        } else if !UserDefaults.standard.bool(forKey: "onboardingCompleteV2") { openMain(.home) }
    }

    private func micChanged(_ inUse: Bool) {
        NSLog("External mic in use: \(inUse) (likely app: \(MicActivityMonitor.likelyMeetingApp() ?? "-"))")
        guard Settings.shared.meetingDetection else { return }
        if inUse {
            guard !MeetingRecorder.shared.isRecording, !DictationController.shared.isListening else { return }
            if let d = meetingDismissedAt, Date().timeIntervalSince(d) < 120 { return }
            NotchController.shared.show(.meetingDetected(MicActivityMonitor.likelyMeetingApp() ?? ""))
        } else {
            if case .meetingDetected = NotchController.shared.state { NotchController.shared.hide() }
            meetingDismissedAt = nil
        }
    }

    private func startMeeting() {
        Task { await MeetingRecorder.shared.start(app: MicActivityMonitor.likelyMeetingApp() ?? "Meeting") }
    }
    private func stopMeeting() {
        Task { if let m = await MeetingRecorder.shared.stop() { _ = m; openMain(.notetaker) } }
    }

    func openMain(_ page: Page) {
        Navigation.shared.page = page
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 700), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = "Babji Flow"
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.contentView = NSHostingView(rootView: MainWindow())
            w.center()
            w.isReleasedWhenClosed = false
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openMain(Navigation.shared.page); return true }
}
