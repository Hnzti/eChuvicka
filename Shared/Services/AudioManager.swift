import Foundation
import Combine
import AVFoundation

final class AudioManager: ObservableObject {
    @Published var isTransmitting: Bool = false
    @Published var audioLevel: Float = 0.0
    @Published var isTalkingToChild: Bool = false
    
    private let audioEngine = AVAudioEngine()
    private var voxThreshold: Float = 0.15
    
    func startRecording(voxEnabled: Bool, threshold: Float) {
        self.voxThreshold = threshold
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, time in
            guard let self = self else { return }
            let level = self.calculateRMS(buffer: buffer)
            
            DispatchQueue.main.async {
                self.audioLevel = level
                if voxEnabled {
                    self.isTransmitting = level > self.voxThreshold
                } else {
                    self.isTransmitting = true
                }
            }
        }
        
        do {
            try audioEngine.start()
        } catch {
            print("Chyba při spuštění AVAudioEngine: \(error)")
        }
    }
    
    func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isTransmitting = false
    }
    
    private func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0.0 }
        let channelDataLength = Int(buffer.frameLength)
        var sum: Float = 0.0
        for i in 0..<channelDataLength {
            sum += channelData[i] * channelData[i]
        }
        return sqrt(sum / Float(channelDataLength))
    }
}
