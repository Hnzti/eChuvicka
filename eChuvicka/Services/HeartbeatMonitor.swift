import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(IOKit)
import IOKit.ps
#endif
#if os(macOS)
import CoreWLAN
#endif
import Combine

public struct HeartbeatPacket: Codable, Sendable {
    public let timestamp: Date
    public let batteryLevel: Float
}

@MainActor
public class HeartbeatMonitor: ObservableObject {
    @Published public var isConnectionAlive: Bool = false
    @Published public var lastLatencyMs: Double = 0
    /// Wi‑Fi RSSI in dBm when the platform exposes it (macOS). `nil` on iOS.
    @Published public var wifiRSSIDbm: Int? = nil
    
    private var heartbeatTimer: Timer?
    private var lastReceivedTimestamp: Date?
    private var connectionCheckTimer: Timer?
    
    public var onSendHeartbeat: (() -> Void)?
    
    private var disconnectAlarmDelay: Double = 10.0
    
    public init() {}
    
    public func start(role _: AppRole, alarmDelay: Double = 6.0) {
        stop()
        isConnectionAlive = true
        lastReceivedTimestamp = Date()
        self.disconnectAlarmDelay = alarmDelay
        lastLatencyMs = 0
        refreshWiFiRSSI()
        
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.onSendHeartbeat?()
            }
        }
        
        connectionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkConnectionAlive()
                self?.refreshWiFiRSSI()
            }
        }
    }
    
    public func updateAlarmDelay(_ delay: Double) {
        disconnectAlarmDelay = max(5, min(30, delay))
    }
    
    public func stop() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        connectionCheckTimer?.invalidate()
        connectionCheckTimer = nil
        isConnectionAlive = false
        wifiRSSIDbm = nil
    }
    
    public func dataReceived() {
        lastReceivedTimestamp = Date()
        if !isConnectionAlive {
            isConnectionAlive = true
        }
    }
    
    public func heartbeatReceived(_ packet: HeartbeatPacket) {
        dataReceived()
        lastLatencyMs = max(0, Date().timeIntervalSince(packet.timestamp) * 1000.0)
    }
    
    private func checkConnectionAlive() {
        guard let lastTimestamp = lastReceivedTimestamp else { return }
        
        if Date().timeIntervalSince(lastTimestamp) > disconnectAlarmDelay {
            if isConnectionAlive {
                isConnectionAlive = false
            }
        }
    }
    
    private func refreshWiFiRSSI() {
        #if os(macOS)
        // CoreWLAN exposes interface RSSI in dBm (e.g. -45). Not available on iOS.
        if let interface = CWWiFiClient.shared().interface() {
            let rssi = interface.rssiValue()
            wifiRSSIDbm = (rssi < 0) ? Int(rssi) : nil
        } else {
            wifiRSSIDbm = nil
        }
        #else
        wifiRSSIDbm = nil
        #endif
    }
    
    public static func currentBatteryLevel() -> Float {
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        return level >= 0 ? level : -1
        #elseif os(macOS)
        return macOSBatteryLevel()
        #else
        return -1
        #endif
    }
    
    #if os(macOS)
    private static func macOSBatteryLevel() -> Float {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [Any],
              !sources.isEmpty else {
            return -1
        }
        
        for source in sources {
            if let info = IOPSGetPowerSourceDescription(snapshot, source as CFTypeRef)?.takeUnretainedValue() as? [String: Any] {
                if let capacity = info[kIOPSCurrentCapacityKey] as? Int,
                   let maxCapacity = info[kIOPSMaxCapacityKey] as? Int,
                   maxCapacity > 0 {
                    return Float(capacity) / Float(maxCapacity)
                }
            }
        }
        
        return -1
    }
    #endif
}
