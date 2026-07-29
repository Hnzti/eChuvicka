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
    @AppStorage("isDisconnectAlarmEnabled") public var isDisconnectAlarmEnabled: Bool = true
    @AppStorage("streamingMode") public var streamingMode: StreamingMode = .vox
    
    public init() {}
}
