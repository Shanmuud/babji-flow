import Foundation
import CoreAudio
import AppKit
import Combine

/// Watches whether any process is using the default input device. When some other app
/// opens the mic (Zoom, Meet, FaceTime...), we surface the "Meeting detected" bar.
final class MicActivityMonitor: ObservableObject {
    @Published private(set) var externalMicInUse = false
    /// Set true while Babji itself is recording so we do not detect ourselves.
    var selfRecording = false { didSet { refresh() } }
    private var device: AudioDeviceID = kAudioObjectUnknown
    private var listenerBlock: AudioObjectPropertyListenerBlock?
    private var defaultListener: AudioObjectPropertyListenerBlock?

    static let meetingApps: [String: String] = [
        "us.zoom.xos": "Zoom", "com.apple.FaceTime": "FaceTime", "com.microsoft.teams2": "Microsoft Teams",
        "com.microsoft.teams": "Microsoft Teams", "com.google.Chrome": "Chrome", "com.apple.Safari": "Safari",
        "company.thebrowser.Browser": "Arc", "com.tinyspeck.slackmacgap": "Slack", "com.hnc.Discord": "Discord",
        "com.cisco.webexmeetingsapp": "Webex", "net.whatsapp.WhatsApp": "WhatsApp", "ru.keepcoder.Telegram": "Telegram",
        "com.brave.Browser": "Brave", "org.mozilla.firefox": "Firefox", "com.loom.desktop": "Loom", "com.skype.skype": "Skype",
    ]

    /// Best guess at the app that is on a call: a known meeting app that is running, frontmost preferred.
    static func likelyMeetingApp() -> String? {
        let running = NSWorkspace.shared.runningApplications
        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, let n = meetingApps[front] { return n }
        for app in running { if let id = app.bundleIdentifier, let n = meetingApps[id], !["Chrome", "Safari", "Arc", "Brave", "Firefox", "Slack", "Discord", "WhatsApp", "Telegram"].contains(n) { return n } }
        for app in running { if let id = app.bundleIdentifier, let n = meetingApps[id] { return n } }
        return nil
    }

    func start() {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        defaultListener = { [weak self] _, _ in self?.attachToDefaultDevice() }
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main, defaultListener!)
        attachToDefaultDevice()
    }

    private func attachToDefaultDevice() {
        detach()
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var dev = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr, dev != kAudioObjectUnknown else { return }
        device = dev
        var runAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        listenerBlock = { [weak self] _, _ in self?.refresh() }
        AudioObjectAddPropertyListenerBlock(device, &runAddr, DispatchQueue.main, listenerBlock!)
        refresh()
    }

    private func detach() {
        guard device != kAudioObjectUnknown, let block = listenerBlock else { return }
        var runAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectRemovePropertyListenerBlock(device, &runAddr, DispatchQueue.main, block)
        listenerBlock = nil
    }

    private func refresh() {
        guard device != kAudioObjectUnknown else { return }
        var runAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &runAddr, 0, nil, &size, &running) == noErr else { return }
        let inUse = running != 0 && !selfRecording
        DispatchQueue.main.async {
            if self.externalMicInUse != inUse { self.externalMicInUse = inUse }
        }
    }
}
