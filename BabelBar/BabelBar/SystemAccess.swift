import Foundation
import AppKit
import ServiceManagement
import ApplicationServices
import IOKit.hid
import CoreGraphics
import AVFoundation
import CoreAudio
import AudioToolbox

/// Launch-at-login via SMAppService (macOS 13+).
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            NSLog("BabelBar: login item toggle failed: \(error)")
        }
    }
}

/// Read-only checks for the permissions the app relies on.
enum Permissions {
    static func accessibility() -> Bool { AXIsProcessTrusted() }

    static func inputMonitoring() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    static func screenRecording() -> Bool { CGPreflightScreenCaptureAccess() }

    static func microphone() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Open the relevant Privacy & Security pane in System Settings.
    static func openSettings(_ kind: Kind) {
        let anchor: String
        switch kind {
        case .accessibility:     anchor = "Privacy_Accessibility"
        case .inputMonitoring:   anchor = "Privacy_ListenEvent"
        case .screenRecording:   anchor = "Privacy_ScreenCapture"
        case .microphone:        anchor = "Privacy_Microphone"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    enum Kind { case accessibility, inputMonitoring, screenRecording, microphone }
}

/// Built-in macOS alert sounds (from /System/Library/Sounds).
enum SystemSounds {
    static let names: [String] = {
        let dir = "/System/Library/Sounds"
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return files.compactMap { $0.hasSuffix(".aiff") ? String($0.dropLast(5)) : nil }.sorted()
    }()

    static func play(_ name: String, volume: Float = 1.0) {
        guard let sound = NSSound(named: NSSound.Name(name)) else { return }
        sound.volume = max(0, min(1, volume))
        sound.play()
    }
}

/// Ducks the system output volume during dictation so music/other audio playing through the
/// speakers doesn't bleed into the microphone, then restores it. macOS has no per-app ducking,
/// so this lowers the default output device's main volume and puts it back on stop.
enum SystemAudio {
    private static var saved: Float32?
    private static let duckFactor: Float32 = 0.2   // duck to 20% of the current level

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let st = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return (st == noErr && id != 0) ? id : nil
    }

    private static func volumeAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
    }

    private static func volume() -> Float32? {
        guard let dev = defaultOutputDevice() else { return nil }
        var addr = volumeAddress()
        guard AudioObjectHasProperty(dev, &addr) else { return nil }
        var vol = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &vol) == noErr ? vol : nil
    }

    private static func setVolume(_ v: Float32) {
        guard let dev = defaultOutputDevice() else { return }
        var addr = volumeAddress()
        var settable = DarwinBoolean(false)
        guard AudioObjectHasProperty(dev, &addr),
              AudioObjectIsPropertySettable(dev, &addr, &settable) == noErr, settable.boolValue else { return }
        var vol = max(0, min(1, v))
        AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &vol)
    }

    /// Lower the output volume (remembering the current level). No-op if already ducked or
    /// the device has no settable main volume.
    static func duck() {
        guard saved == nil, let cur = volume() else { return }
        saved = cur
        setVolume(cur * duckFactor)
    }

    /// Restore the volume saved by `duck()`.
    static func restore() {
        guard let s = saved else { return }
        setVolume(s)
        saved = nil
    }
}
