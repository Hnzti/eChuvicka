import Foundation
import Network

public enum ConnectionMode: String, Sendable {
    case disconnected = "Odpojeno"
    case searching = "Vyhledávání..."
    case connectedRouter = "Wi-Fi Router"
    case connectedDirect = "Přímé spojení (P2P)"
}

/// Represents a discovered child device
public struct DiscoveredDevice: Identifiable, Hashable {
    public let id: String  // PIN
    public let name: String
    public let endpoint: NWEndpoint
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
public class NetworkManager: ObservableObject {
    @Published public var connectionMode: ConnectionMode = .disconnected
    @Published public var isConnected: Bool = false
    @Published public var generatedPIN: String = ""
    @Published public var peerBatteryLevel: Float = 1.0
    @Published public var discoveredDevices: [DiscoveredDevice] = []
    
    public var onAudioDataReceived: (@Sendable (Data) -> Void)?
    public var onHeartbeatReceived: (@Sendable (HeartbeatPacket) -> Void)?
    
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connection: NWConnection?
    
    private let serviceType = "_echuvicka._tcp"
    
    public init() {}
    
    // MARK: - Child / Transmitter
    
    public func startHosting() {
        stop() // Clean up any previous state
        
        let pin = String(format: "%06d", Int.random(in: 0...999999))
        self.generatedPIN = pin
        
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        
        do {
            let nwListener = try NWListener(using: params)
            nwListener.service = NWListener.Service(name: "eChuvicka-\(pin)", type: serviceType)
            
            nwListener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self = self else { return }
                    switch state {
                    case .ready:
                        self.connectionMode = .searching
                        print("[Child] Listener ready, waiting for parent...")
                    case .failed(let error):
                        print("[Child] Listener failed: \(error)")
                        self.connectionMode = .disconnected
                    case .cancelled:
                        break
                    default:
                        break
                    }
                }
            }
            
            nwListener.newConnectionHandler = { [weak self] newConnection in
                Task { @MainActor in
                    print("[Child] Parent connected!")
                    self?.setupConnection(newConnection)
                }
            }
            
            nwListener.start(queue: .main)
            self.listener = nwListener
            self.connectionMode = .searching
            
        } catch {
            print("[Child] Failed to start listener: \(error)")
        }
    }
    
    // MARK: - Parent / Receiver
    
    /// Start browsing for child devices — populates discoveredDevices list
    public func startBrowsing() {
        stop() // Clean up any previous state
        
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        
        let nwBrowser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: params)
        
        nwBrowser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.connectionMode = .searching
                    print("[Parent] Browser ready, searching for children...")
                case .failed(let error):
                    print("[Parent] Browser failed: \(error)")
                    self.connectionMode = .disconnected
                case .cancelled:
                    break
                default:
                    break
                }
            }
        }
        
        nwBrowser.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor in
                guard let self = self else { return }
                var devices: [DiscoveredDevice] = []
                for result in results {
                    if case let .service(name, _, _, _) = result.endpoint {
                        // Service name format: "eChuvicka-XXXXXX"
                        let pin = name.replacingOccurrences(of: "eChuvicka-", with: "")
                        devices.append(DiscoveredDevice(
                            id: pin,
                            name: name,
                            endpoint: result.endpoint
                        ))
                    }
                }
                self.discoveredDevices = devices
                print("[Parent] Found \(devices.count) device(s)")
            }
        }
        
        nwBrowser.start(queue: .main)
        self.browser = nwBrowser
        self.connectionMode = .searching
    }
    
    /// Connect to a specific discovered device
    public func connectToDevice(_ device: DiscoveredDevice) {
        print("[Parent] Connecting to device: \(device.name)")
        
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        
        let newConnection = NWConnection(to: device.endpoint, using: params)
        
        // Stop browsing once we're connecting
        browser?.cancel()
        browser = nil
        
        setupConnection(newConnection)
    }
    
    // MARK: - Connection Setup
    
    private func setupConnection(_ newConnection: NWConnection) {
        // Cancel old connection if any
        if let old = connection {
            old.stateUpdateHandler = nil
            old.cancel()
        }
        connection = newConnection
        
        newConnection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self = self else { return }
                switch state {
                case .preparing:
                    print("[Connection] Preparing...")
                case .ready:
                    print("[Connection] Ready!")
                    self.isConnected = true
                    self.connectionMode = .connectedRouter
                    self.startReceiving()
                case .failed(let error):
                    print("[Connection] Failed: \(error)")
                    self.handleDisconnect()
                case .cancelled:
                    print("[Connection] Cancelled")
                    self.handleDisconnect()
                default:
                    break
                }
            }
        }
        
        newConnection.pathUpdateHandler = { [weak self] newPath in
            Task { @MainActor in
                guard let self = self, self.isConnected else { return }
                if newPath.usesInterfaceType(.wifi) {
                    self.connectionMode = .connectedRouter
                } else {
                    self.connectionMode = .connectedDirect
                }
            }
        }
        
        newConnection.start(queue: .main)
    }
    
    private func handleDisconnect() {
        isConnected = false
        connectionMode = .disconnected
        connection = nil
    }
    
    public func stop() {
        listener?.cancel()
        listener = nil
        
        browser?.cancel()
        browser = nil
        
        if let conn = connection {
            conn.stateUpdateHandler = nil
            conn.cancel()
        }
        connection = nil
        
        isConnected = false
        connectionMode = .disconnected
        discoveredDevices = []
    }
    
    // MARK: - Data Transfer
    
    public func sendAudioData(_ data: Data) {
        sendFramedMessage(type: 0x01, payload: data)
    }
    
    public func sendHeartbeat(_ packet: HeartbeatPacket) {
        guard let data = try? JSONEncoder().encode(packet) else { return }
        sendFramedMessage(type: 0x02, payload: data)
    }
    
    private func sendFramedMessage(type: UInt8, payload: Data) {
        guard let connection = connection, isConnected else { return }
        
        var message = Data()
        message.append(type)
        var length = UInt32(payload.count).bigEndian
        message.append(Data(bytes: &length, count: MemoryLayout<UInt32>.size))
        message.append(payload)
        
        connection.send(content: message, completion: .contentProcessed({ error in
            if let error = error {
                print("[Send] Error: \(error)")
            }
        }))
    }
    
    // MARK: - Receive
    
    private func startReceiving() {
        guard let connection = connection else { return }
        
        connection.receive(minimumIncompleteLength: 5, maximumLength: 5) { [weak self] headerData, _, isComplete, error in
            if let error = error {
                print("[Receive] Header error: \(error)")
                Task { @MainActor in self?.handleDisconnect() }
                return
            }
            
            guard let headerData = headerData, headerData.count == 5 else {
                if isComplete {
                    Task { @MainActor in self?.handleDisconnect() }
                }
                return
            }
            
            let type = headerData[0]
            let lengthData = headerData.subdata(in: 1..<5)
            let length = UInt32(bigEndian: lengthData.withUnsafeBytes { $0.load(as: UInt32.self) })
            
            connection.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { [weak self] payloadData, _, _, error2 in
                if let error2 = error2 {
                    print("[Receive] Payload error: \(error2)")
                    Task { @MainActor in self?.handleDisconnect() }
                    return
                }
                
                Task { @MainActor [weak self] in
                    if let payloadData = payloadData {
                        if type == 0x01 {
                            self?.onAudioDataReceived?(payloadData)
                        } else if type == 0x02 {
                            if let packet = try? JSONDecoder().decode(HeartbeatPacket.self, from: payloadData) {
                                self?.onHeartbeatReceived?(packet)
                                self?.peerBatteryLevel = packet.batteryLevel
                            }
                        }
                    }
                    self?.startReceiving()
                }
            }
        }
    }
}
