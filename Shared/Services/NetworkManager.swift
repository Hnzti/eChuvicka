import Foundation
import Network
import Combine

final class NetworkManager: ObservableObject {
    @Published var connectionMode: ConnectionMode = .disconnected
    @Published var quality: ConnectionQuality = ConnectionQuality()
    @Published var generatedPIN: String = ""
    @Published var isConnected: Bool = false
    
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private let serviceType = "_echuvicka._tcp"
    
    init() {
        self.generatedPIN = String(format: "%06d", Int.random(in: 100000...999999))
    }
    
    /// Spustí poslech na dětské jednotce (Vysílač) s podporou P2P i Routeru
    func startHost(pin: String) {
        do {
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true // Povoluje D2D Wi-Fi Direct i DRD
            
            listener = try NWListener(using: parameters)
            listener?.service = NWListener.Service(name: "eChuvicka-\(pin)", type: serviceType)
            
            listener?.newConnectionHandler = { [weak self] newConn in
                self?.setupConnection(newConn)
            }
            
            listener?.start(queue: .main)
            self.connectionMode = .searching
        } catch {
            print("Chyba při startu hosta: \(error)")
        }
    }
    
    /// Spustí vyhledávání z rodičovské jednotky (Přijímač)
    func startBrowsing(targetPIN: String) {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true // Povoluje P2P i Router
        
        let browserDescriptor = NWBrowser.Descriptor.bonjour(type: serviceType, domain: nil)
        browser = NWBrowser(for: browserDescriptor, using: parameters)
        
        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            for result in results {
                if case let .bonjour(endpoint) = result.endpoint {
                    if endpoint.name.contains(targetPIN) {
                        self?.connect(to: result.endpoint)
                        self?.browser?.cancel()
                        break
                    }
                }
            }
        }
        
        browser?.start(queue: .main)
        self.connectionMode = .searching
    }
    
    private func connect(to endpoint: NWEndpoint) {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let conn = NWConnection(to: endpoint, using: parameters)
        setupConnection(conn)
    }
    
    private func setupConnection(_ conn: NWConnection) {
        self.connection = conn
        conn.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.isConnected = true
                    self?.updateConnectionMode(conn: conn)
                case .failed, .cancelled:
                    self?.isConnected = false
                    self?.connectionMode = .disconnected
                default:
                    break
                }
            }
        }
        conn.start(queue: .main)
    }
    
    private func updateConnectionMode(conn: NWConnection) {
        if let path = conn.currentPath {
            if path.usesInterfaceType(.wifi) {
                self.connectionMode = .routerDRD
            } else if path.isDirect {
                self.connectionMode = .directD2D
            } else {
                self.connectionMode = .directD2D
            }
        }
    }
    
    func stop() {
        listener?.cancel()
        browser?.cancel()
        connection?.cancel()
        isConnected = false
        connectionMode = .disconnected
    }
}
