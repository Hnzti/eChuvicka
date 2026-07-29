import Foundation
import SwiftUI

public enum StreamingMode: String, Codable, CaseIterable, Sendable {
    case continuous = "Continuous"
    case vox = "VOX"
}

@MainActor
public class AppSettings: ObservableObject {
    @AppStorage("isVOXEnabled") public var isVOXEnabled: Bool = true
    @AppStorage("voxSensitivity") public var voxSensitivity: Double = 0.15
    @AppStorage("isDisconnectAlarmEnabled") public var isDisconnectAlarmEnabled: Bool = true
    @AppStorage("streamingMode") public var streamingMode: StreamingMode = .vox
    
    // Nové nastavení (Update 2)
    @AppStorage("isAutoReconnectEnabled") public var isAutoReconnectEnabled: Bool = true
    @AppStorage("isLowBatteryAlertEnabled") public var isLowBatteryAlertEnabled: Bool = true
    @AppStorage("isAutoNightModeEnabled") public var isAutoNightModeEnabled: Bool = true
    @AppStorage("disconnectAlarmDelay") public var disconnectAlarmDelay: Double = 6.0
    @AppStorage("isAudioBoostEnabled") public var isAudioBoostEnabled: Bool = false
    @AppStorage("lastConnectedPIN") public var lastConnectedPIN: String = ""
    
    public init() {}
}
