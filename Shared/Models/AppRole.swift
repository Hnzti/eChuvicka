import Foundation
import Combine

enum AppRole: String, Codable, CaseIterable {
    case none = "Neurčeno"
    case child = "Dítě (Vysílač)"
    case parent = "Rodič (Přijímač)"
}

enum ConnectionMode: String, Codable {
    case disconnected = "Odpojeno"
    case searching = "Vyhledávání"
    case routerDRD = "Wi-Fi Router (DRD)"
    case directD2D = "Direct Peer-to-Peer (D2D)"
}

struct ConnectionQuality: Equatable {
    var latencyMs: Double = 0.0
    var packetLossRatio: Double = 0.0
    var isStable: Bool = true
}
