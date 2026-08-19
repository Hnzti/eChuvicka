import Foundation
import AudioToolbox
#if canImport(AppKit)
import AppKit
#endif

/// Plays short system alerts for disconnect / low battery (respects user toggles in UI).
@MainActor
enum MonitorAlertPlayer {
    private static var lastDisconnectBeepAt: Date?
    private static var lastBatteryBeepAt: Date?
    
    static func playDisconnectAlarmIfNeeded(enabled: Bool) {
        guard enabled else { return }
        let now = Date()
        if let last = lastDisconnectBeepAt, now.timeIntervalSince(last) < 2.0 { return }
        lastDisconnectBeepAt = now
        playSystemSound()
    }
    
    static func playLowBatteryAlarmIfNeeded(enabled: Bool) {
        guard enabled else { return }
        let now = Date()
        if let last = lastBatteryBeepAt, now.timeIntervalSince(last) < 30.0 { return }
        lastBatteryBeepAt = now
        playSystemSound()
    }
    
    static func reset() {
        lastDisconnectBeepAt = nil
        lastBatteryBeepAt = nil
    }
    
    private static func playSystemSound() {
        #if os(iOS)
        AudioServicesPlaySystemSound(1005)
        AudioServicesPlayAlertSound(kSystemSoundID_Vibrate)
        #elseif os(macOS)
        NSSound.beep()
        #endif
    }
}
