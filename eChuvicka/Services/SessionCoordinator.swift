import Foundation
import Combine

@MainActor
public class SessionCoordinator: ObservableObject {
    @Published public var role: AppRole = .none
    
    public let networkManager = NetworkManager()
    public let audioManager = AudioManager()
    public let heartbeatMonitor = HeartbeatMonitor()
    public let appSettings = AppSettings()
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Convenience properties for Views
    
    public var connectionMode: ConnectionMode {
        networkManager.connectionMode
    }
    
    public var isConnected: Bool {
        networkManager.isConnected
    }
    
    public var audioLevel: Float {
        audioManager.audioLevel
    }
    
    public var isConnectionAlive: Bool {
        heartbeatMonitor.isConnectionAlive
    }
    
    public var peerBatteryLevel: Float {
        networkManager.peerBatteryLevel
    }
    
    public var latencyMs: Double {
        heartbeatMonitor.lastLatencyMs
    }
    
    public var generatedPIN: String {
        networkManager.generatedPIN
    }
    
    public var discoveredDevices: [DiscoveredDevice] {
        networkManager.discoveredDevices
    }
    
    public init() {
        setupBindings()
    }
    
    private func setupBindings() {
        // Forward NetworkManager state changes
        networkManager.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        
        // Forward AudioManager state changes
        audioManager.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        
        // Forward HeartbeatMonitor state changes
        heartbeatMonitor.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        
        // Setup NetworkManager callbacks
        networkManager.onAudioDataReceived = { [weak self] data in
            Task { @MainActor in
                self?.heartbeatMonitor.dataReceived()
                self?.audioManager.playReceivedAudio(data)
            }
        }
        
        networkManager.onHeartbeatReceived = { [weak self] packet in
            Task { @MainActor in
                self?.heartbeatMonitor.heartbeatReceived(packet)
            }
        }
        
        // Setup Heartbeat callbacks
        heartbeatMonitor.onSendHeartbeat = { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                if !self.audioManager.isTransmitting {
                    let packet = HeartbeatPacket(timestamp: Date(), batteryLevel: HeartbeatMonitor.currentBatteryLevel())
                    self.networkManager.sendHeartbeat(packet)
                }
            }
        }
    }
    
    public func startAsChild() {
        role = .child
        networkManager.startHosting()
        audioManager.startCapture(
            voxEnabled: appSettings.isVOXEnabled,
            voxThreshold: Float(appSettings.voxSensitivity)
        ) { [weak self] data in
            self?.networkManager.sendAudioData(data)
            self?.heartbeatMonitor.dataReceived()
        }
        heartbeatMonitor.start(role: .child)
    }
    
    public func startBrowsingAsParent() {
        role = .parent
        networkManager.startBrowsing()
    }
    
    public func connectToDevice(_ device: DiscoveredDevice) {
        networkManager.connectToDevice(device)
        audioManager.preparePlayback()
        heartbeatMonitor.start(role: .parent)
    }
    
    public func startPTT() {
        guard role == .parent else { return }
        audioManager.startCapture(voxEnabled: false, voxThreshold: 0.0) { [weak self] data in
            self?.networkManager.sendAudioData(data)
        }
    }
    
    public func stopPTT() {
        guard role == .parent else { return }
        audioManager.stopCapture()
    }
    
    public func stop() {
        role = .none
        networkManager.stop()
        audioManager.stopCapture()
        audioManager.stopPlayback()
        heartbeatMonitor.stop()
    }
}
