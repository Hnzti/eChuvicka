import Foundation
import Combine

@MainActor
public class AppSettings: ObservableObject {
    private let defaults: UserDefaults
    
    @Published public var isVOXEnabled: Bool {
        didSet { defaults.set(isVOXEnabled, forKey: Keys.isVOXEnabled) }
    }
    @Published public var voxSensitivity: Double {
        didSet { defaults.set(voxSensitivity, forKey: Keys.voxSensitivity) }
    }
    @Published public var voxHoldTime: Double {
        didSet { defaults.set(voxHoldTime, forKey: Keys.voxHoldTime) }
    }
    
    @Published public var isDisconnectAlarmEnabled: Bool {
        didSet { defaults.set(isDisconnectAlarmEnabled, forKey: Keys.isDisconnectAlarmEnabled) }
    }
    @Published public var disconnectAlarmDelay: Double {
        didSet { defaults.set(disconnectAlarmDelay, forKey: Keys.disconnectAlarmDelay) }
    }
    @Published public var isLowBatteryAlertEnabled: Bool {
        didSet { defaults.set(isLowBatteryAlertEnabled, forKey: Keys.isLowBatteryAlertEnabled) }
    }
    /// Fraction 0.05…0.30 (5–30 %), step 5 %
    @Published public var lowBatteryThreshold: Double {
        didSet { defaults.set(lowBatteryThreshold, forKey: Keys.lowBatteryThreshold) }
    }
    @Published public var isAutoReconnectEnabled: Bool {
        didSet { defaults.set(isAutoReconnectEnabled, forKey: Keys.isAutoReconnectEnabled) }
    }
    
    /// Child-only: whether Bonjour advertises PIN pairing. Never overwritten by parent sync.
    @Published public var isPinRequired: Bool {
        didSet { defaults.set(isPinRequired, forKey: Keys.isPinRequired) }
    }
    @Published public var deviceName: String {
        didSet { defaults.set(deviceName, forKey: Keys.deviceName) }
    }
    
    @Published public var stableDeviceId: String {
        didSet { defaults.set(stableDeviceId, forKey: Keys.stableDeviceId) }
    }
    @Published public var hostedPairingPIN: String {
        didSet { defaults.set(hostedPairingPIN, forKey: Keys.hostedPairingPIN) }
    }
    
    @Published public var lastConnectedDeviceId: String {
        didSet { defaults.set(lastConnectedDeviceId, forKey: Keys.lastConnectedDeviceId) }
    }
    @Published public var lastConnectedPIN: String {
        didSet { defaults.set(lastConnectedPIN, forKey: Keys.lastConnectedPIN) }
    }
    @Published public var lastConnectedAt: Double {
        didSet { defaults.set(lastConnectedAt, forKey: Keys.lastConnectedAt) }
    }
    
    public static let reconnectTrustDuration: TimeInterval = 24 * 60 * 60
    
    private enum Keys {
        static let isVOXEnabled = "isVOXEnabled"
        static let voxSensitivity = "voxSensitivity"
        static let voxHoldTime = "voxHoldTime"
        static let isDisconnectAlarmEnabled = "isDisconnectAlarmEnabled"
        static let disconnectAlarmDelay = "disconnectAlarmDelay"
        static let isLowBatteryAlertEnabled = "isLowBatteryAlertEnabled"
        static let lowBatteryThreshold = "lowBatteryThreshold"
        static let isAutoReconnectEnabled = "isAutoReconnectEnabled"
        static let isPinRequired = "isPinRequired"
        static let deviceName = "deviceName"
        static let stableDeviceId = "stableDeviceId"
        static let hostedPairingPIN = "hostedPairingPIN"
        static let lastConnectedDeviceId = "lastConnectedDeviceId"
        static let lastConnectedPIN = "lastConnectedPIN"
        static let lastConnectedAt = "lastConnectedAt"
    }
    
    public var isLastConnectionWithinTrustWindow: Bool {
        guard !lastConnectedDeviceId.isEmpty, lastConnectedAt > 0 else { return false }
        return Date().timeIntervalSince1970 - lastConnectedAt < Self.reconnectTrustDuration
    }
    
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        
        self.isVOXEnabled = defaults.object(forKey: Keys.isVOXEnabled) as? Bool ?? true
        self.voxSensitivity = defaults.object(forKey: Keys.voxSensitivity) as? Double ?? 0.15
        self.voxHoldTime = defaults.object(forKey: Keys.voxHoldTime) as? Double ?? 15.0
        self.isDisconnectAlarmEnabled = defaults.object(forKey: Keys.isDisconnectAlarmEnabled) as? Bool ?? true
        self.disconnectAlarmDelay = defaults.object(forKey: Keys.disconnectAlarmDelay) as? Double ?? 10.0
        self.isLowBatteryAlertEnabled = defaults.object(forKey: Keys.isLowBatteryAlertEnabled) as? Bool ?? true
        self.lowBatteryThreshold = defaults.object(forKey: Keys.lowBatteryThreshold) as? Double ?? 0.20
        self.isAutoReconnectEnabled = defaults.object(forKey: Keys.isAutoReconnectEnabled) as? Bool ?? true
        self.isPinRequired = defaults.object(forKey: Keys.isPinRequired) as? Bool ?? true
        self.deviceName = defaults.string(forKey: Keys.deviceName) ?? ""
        self.stableDeviceId = defaults.string(forKey: Keys.stableDeviceId) ?? ""
        self.hostedPairingPIN = defaults.string(forKey: Keys.hostedPairingPIN) ?? ""
        self.lastConnectedDeviceId = defaults.string(forKey: Keys.lastConnectedDeviceId) ?? ""
        self.lastConnectedPIN = defaults.string(forKey: Keys.lastConnectedPIN) ?? ""
        self.lastConnectedAt = defaults.object(forKey: Keys.lastConnectedAt) as? Double ?? 0
        
        _ = ensureStableDeviceId()
    }
    
    public func ensureStableDeviceId() -> String {
        if stableDeviceId.isEmpty {
            stableDeviceId = UUID().uuidString
        }
        return stableDeviceId
    }
    
    public func currentOrCreateHostedPIN() -> String {
        if hostedPairingPIN.count == 4, hostedPairingPIN.allSatisfy(\.isNumber) {
            return hostedPairingPIN
        }
        let pin = String(format: "%04d", Int.random(in: 0...9999))
        hostedPairingPIN = pin
        return pin
    }
    
    public func rememberSuccessfulConnection(deviceId: String, pin: String) {
        lastConnectedDeviceId = deviceId
        lastConnectedPIN = pin
        lastConnectedAt = Date().timeIntervalSince1970
    }
    
    public func canSkipPin(forDeviceId deviceId: String) -> Bool {
        isLastConnectionWithinTrustWindow && lastConnectedDeviceId == deviceId
    }
    
    /// Force immediate write to disk (useful before process suspension).
    public func synchronize() {
        defaults.synchronize()
    }
}
