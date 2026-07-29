import Foundation
import AVFoundation

@MainActor
public class AudioManager: ObservableObject {
    @Published public var audioLevel: Float = 0.0
    @Published public var isTransmitting: Bool = false
    
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    
    private var isCaptureActive = false
    private var voxEnabled = true
    private var voxThreshold: Float = 0.15
    private var onAudioCaptured: ((Data) -> Void)?
    
    public init() {}
    
    public func configureSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
        #endif
    }
    
    public func startCapture(voxEnabled: Bool, voxThreshold: Float, onAudioCaptured: @escaping (Data) -> Void) {
        self.voxEnabled = voxEnabled
        self.voxThreshold = voxThreshold
        self.onAudioCaptured = onAudioCaptured
        self.isCaptureActive = true
        
        configureSession()
        
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Use the hardware's native format for capture
        let desiredFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inputFormat.sampleRate, channels: 1, interleaved: false)!
        
        if !engine.attachedNodes.contains(playerNode) {
            engine.attach(playerNode)
            engine.connect(playerNode, to: engine.mainMixerNode, format: desiredFormat)
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: desiredFormat) { [weak self] buffer, _ in
            guard let self = self, self.isCaptureActive else { return }
            
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            
            // Calculate RMS
            var rms: Float = 0.0
            for i in 0..<frameLength {
                let sample = channelData[i]
                rms += sample * sample
            }
            rms = sqrt(rms / Float(max(frameLength, 1)))
            
            let currentLevel = min(max(rms * 5.0, 0.0), 1.0)
            
            Task { @MainActor in
                self.audioLevel = currentLevel
                
                let shouldTransmit = !self.voxEnabled || currentLevel > self.voxThreshold
                self.isTransmitting = shouldTransmit
                
                if shouldTransmit {
                    let data = Data(bytes: channelData, count: frameLength * MemoryLayout<Float>.size)
                    self.onAudioCaptured?(data)
                }
            }
        }
        
        do {
            try engine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }
    
    public func stopCapture() {
        isCaptureActive = false
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        isTransmitting = false
        audioLevel = 0.0
    }
    
    public func playReceivedAudio(_ data: Data) {
        if !engine.isRunning {
            configureSession()
            
            if !engine.attachedNodes.contains(playerNode) {
                let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
                engine.attach(playerNode)
                engine.connect(playerNode, to: engine.mainMixerNode, format: format)
            }
            
            do {
                try engine.start()
            } catch {
                print("Failed to start engine for playback: \(error)")
            }
        }
        
        if !playerNode.isPlaying {
            playerNode.play()
        }
        
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let frameCount = AVAudioFrameCount(data.count / MemoryLayout<Float>.size)
        guard frameCount > 0 else { return }
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        
        data.withUnsafeBytes { rawBufferPointer in
            if let floats = rawBufferPointer.bindMemory(to: Float.self).baseAddress,
               let channelData = buffer.floatChannelData?[0] {
                channelData.assign(from: floats, count: Int(frameCount))
            }
        }
        
        playerNode.scheduleBuffer(buffer, completionHandler: nil)
    }
}
