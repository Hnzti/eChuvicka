import Foundation
import Network

public enum ConnectionMode: String, Sendable {
    case disconnected = "Odpojeno"
    case searching = "Vyhledávání..."
    case connectedRouter = "Wi-Fi Router"
    case connectedDirect = "Přímé spojení (P2P)"
}

@MainActor
public class NetworkManager: ObservableObject {
    @Published public var connectionMode: ConnectionMode = .disconnected
    @Published public var isConnected: Bool = false
    @Published public var generatedPIN: String = ""
    @Published public var peerBatteryLevel: Float = 1.0
    
    public var onAudioDataReceived: (@Sendable (Data) -> Void)?
    public var onHeartbeatReceived: (@Sendable (HeartbeatPacket) -> Void)?
    
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connection: NWConnection?
    
    private let serviceType = "_echuvicka._tcp"
    
    public init() {}
    
    // MARK: - Child / Transmitter
    public func startHosting() {
        let pin = String(format: "%06d", Int.random(in: 0...999999))
        self.generatedPIN = pin
        
        let tcpOptions = NWProtocolTCP.Options()
        let params = NWParameters(tls: nil, tcp: tcpOptions)
        params.includePeerToPeer = true
        
        do {
            let nwListener = try NWListener(using: params)
            nwListener.service = NWListener.Service(name: pin, type: serviceType)
            
            nwListener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.connectionMode = .searching
                    case .failed, .cancelled:
                        self?.stop()
                    default:
                        break
                    }
                }
            }
            
            nwListener.newConnectionHandler = { [weak self] newConnection in
                Task { @MainActor in
                    self?.setupConnection(newConnection)
                }
            }
            
            nwListener.start(queue: .main)
            self.listener = nwListener
            self.connectionMode = .searching
            
        } catch {
            print("Failed to start listener: \(error)")
        }
    }
    
    // MARK: - Parent / Receiver
    public func startBrowsing(pin: String) {
        let params = NWParameters()
        params.includePeerToPeer = true
        
        let nwBrowser = NWBrowser(for: .bonjour(type: serviceType, domain: "local."), using: params)
        
        nwBrowser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.connectionMode = .searching
                case .failed, .cancelled:
                    self?.stop()
                default:
                    break
                }
            }
        }
        
        nwBrowser.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor in
                guard let self = self else { return }
                for result in results {
                    if case let .service(name, _, _, _) = result.endpoint, name == pin {
                        self.connectTo(endpoint: result.endpoint)
                        self.browser?.cancel()
                        break
                    }
                }
            }
        }
        
        nwBrowser.start(queue: .main)
        self.browser = nwBrowser
        self.connectionMode = .searching
    }
    
    private func connectTo(endpoint: NWEndpoint) {
        let tcpOptions = NWProtocolTCP.Options()
        let params = NWParameters(tls: nil, tcp: tcpOptions)
        params.includePeerToPeer = true
        
        let newConnection = NWConnection(to: endpoint, using: params)
        setupConnection(newConnection)
    }
    
    private func setupConnection(_ newConnection: NWConnection) {
        connection?.cancel()
        connection = newConnection
        
        newConnection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.isConnected = true
                    self.updateConnectionMode(path: newConnection.currentPath)
                    self.startReceiving()
                case .failed, .cancelled:
                    self.isConnected = false
                    self.connectionMode = .disconnected
                    self.connection = nil
                default:
                    break
                }
            }
        }
        
        newConnection.pathUpdateHandler = { [weak self] newPath in
            Task { @MainActor in
                self?.updateConnectionMode(path: newPath)
            }
        }
        
        newConnection.start(queue: .main)
    }
    
    private func updateConnectionMode(path: NWPath?) {
        guard let path = path else { return }
        // Determine if the path uses a direct peer-to-peer interface
        // If the path satisfies Wi-Fi but there are no gateways, it's likely P2P
        if path.usesInterfaceType(.wifi) {
            // Check if this is a direct/peer-to-peer connection
            // NWPath doesn't have isLocal, so we use availableInterfaces to check
            let hasInfrastructure = path.availableInterfaces.contains { $0.type == .wifi }
            if path.availableInterfaces.count == 1 && hasInfrastructure {
                // Simple heuristic: if connected via Wi-Fi and P2P was enabled,
                // we consider it router by default; if the endpoint was discovered
                // via P2P browsing, the framework will prefer that path
                connectionMode = .connectedRouter
            } else {
                connectionMode = .connectedRouter
            }
        } else {
            // Non-Wi-Fi path, likely peer-to-peer direct
            connectionMode = .connectedDirect
        }
    }
    
    public func stop() {
        listener?.cancel()
        listener = nil
        browser?.cancel()
        browser = nil
        connection?.cancel()
        connection = nil
        
        isConnected = false
        connectionMode = .disconnected
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
                print("Failed to send data: \(error)")
            }
        }))
    }
    
    // MARK: - Receive
    
    private func startReceiving() {
        guard let connection = connection else { return }
        
        // Read header: 1 byte type + 4 bytes length = 5 bytes
        connection.receive(minimumIncompleteLength: 5, maximumLength: 5) { [weak self] headerData, _, isComplete, error in
            if let error = error {
                print("Receive header error: \(error)")
                return
            }
            
            guard let headerData = headerData, headerData.count == 5 else {
                if !isComplete {
                    Task { @MainActor in self?.startReceiving() }
                }
                return
            }
            
            let type = headerData[0]
            let lengthData = headerData.subdata(in: 1..<5)
            let length = UInt32(bigEndian: lengthData.withUnsafeBytes { $0.load(as: UInt32.self) })
            
            // Read payload
            connection.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { [weak self] payloadData, _, isComplete2, error2 in
                if let error2 = error2 {
                    print("Receive payload error: \(error2)")
                    return
                }
                
                Task { @MainActor [weak self] in
                    if let payloadData = payloadData {
                        if type == 0x01 { // Audio
                            self?.onAudioDataReceived?(payloadData)
                        } else if type == 0x02 { // Heartbeat
                            if let packet = try? JSONDecoder().decode(HeartbeatPacket.self, from: payloadData) {
                                self?.onHeartbeatReceived?(packet)
                                self?.peerBatteryLevel = packet.batteryLevel
                            }
                        }
                    }
                    
                    // Continue receiving
                    self?.startReceiving()
                }
            }
        }
    }
}

