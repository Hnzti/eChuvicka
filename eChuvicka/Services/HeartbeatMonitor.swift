import Foundation
#if canImport(UIKit)
import UIKit
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
    
    public init() {}
    
    public func start(role: AppRole) {
        isConnectionAlive = true
        lastReceivedTimestamp = Date()
        
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
        lastLatencyMs = latency * 1000.0
    }
    
    private func checkConnectionAlive() {
        guard let lastTimestamp = lastReceivedTimestamp else { return }
        
        // If no data received for 6 seconds (3 missed heartbeats), mark as lost
        if Date().timeIntervalSince(lastTimestamp) > 6.0 {
            if isConnectionAlive {
                isConnectionAlive = false
            }
        }
    }
    
    public static func currentBatteryLevel() -> Float {
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        return UIDevice.current.batteryLevel
        #elseif os(macOS)
        // Simplified fallback for macOS, actual integration requires IOKit or other methods
        return 1.0
        #else
        return 1.0
        #endif
    }
}
