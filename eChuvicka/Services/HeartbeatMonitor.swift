import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(IOKit)
import IOKit.ps
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
    
    private var heartbeatTimer: Timer?
    private var lastReceivedTimestamp: Date?
    private var connectionCheckTimer: Timer?
    
    public var onSendHeartbeat: (() -> Void)?
    
    private var disconnectAlarmDelay: Double = 6.0
    
    public init() {}
    
    public func start(role: AppRole, alarmDelay: Double = 6.0) {
        isConnectionAlive = true
        lastReceivedTimestamp = Date()
        self.disconnectAlarmDelay = alarmDelay
        
        // Send heartbeat every 2 seconds
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.onSendHeartbeat?()
            }
        }
        
        // Check connection alive status every 1 second
        connectionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkConnectionAlive()
            }
        }
    }
    
    public func stop() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        connectionCheckTimer?.invalidate()
        connectionCheckTimer = nil
        isConnectionAlive = false
    }
    
    public func dataReceived() {
        lastReceivedTimestamp = Date()
        if !isConnectionAlive {
            isConnectionAlive = true
        }
    }
    
    public func heartbeatReceived(_ packet: HeartbeatPacket) {
        dataReceived()
        let latency = Date().timeIntervalSince(packet.timestamp)
        lastLatencyMs = max(0, latency * 1000.0)
    }
    
    private func checkConnectionAlive() {
        guard let lastTimestamp = lastReceivedTimestamp else { return }
        
        // If no data received for specified delay, mark as lost
        if Date().timeIntervalSince(lastTimestamp) > disconnectAlarmDelay {
            if isConnectionAlive {
                isConnectionAlive = false
            }
        }
    }
    
    public static func currentBatteryLevel() -> Float {
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        // batteryLevel returns -1.0 if monitoring is not enabled or unknown
        return level >= 0 ? level : 1.0
        #elseif os(macOS)
        return macOSBatteryLevel()
        #else
        return 1.0
        #endif
    }
    
    #if os(macOS)
    private static func macOSBatteryLevel() -> Float {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [Any],
              !sources.isEmpty else {
            return 1.0 // Desktop Mac without battery
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
        
        return 1.0
    }
    #endif
}
