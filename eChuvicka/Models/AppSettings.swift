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
    @AppStorage("voxHoldTime") public var voxHoldTime: Double = 15.0
    @AppStorage("streamingMode") public var streamingMode: StreamingMode = .vox
    
    @AppStorage("isDisconnectAlarmEnabled") public var isDisconnectAlarmEnabled: Bool = true
    @AppStorage("disconnectAlarmDelay") public var disconnectAlarmDelay: Double = 10.0
    @AppStorage("isLowBatteryAlertEnabled") public var isLowBatteryAlertEnabled: Bool = true
    /// Fraction 0.05…0.30 (5–30 %), step 5 %
    @AppStorage("lowBatteryThreshold") public var lowBatteryThreshold: Double = 0.20
    @AppStorage("isAutoReconnectEnabled") public var isAutoReconnectEnabled: Bool = true
    
    @AppStorage("isPinRequired") public var isPinRequired: Bool = true
    @AppStorage("deviceName") public var deviceName: String = ""
    @AppStorage("lastConnectedPIN") public var lastConnectedPIN: String = ""
    
    public init() {}
}
