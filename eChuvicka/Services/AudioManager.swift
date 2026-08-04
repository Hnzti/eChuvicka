import Foundation
import AVFoundation

@MainActor
public class AudioManager: ObservableObject {
    @Published public var audioLevel: Float = 0.0
    @Published public var isTransmitting: Bool = false
    /// Parent is currently receiving audible packets from the child.
    @Published public var isReceiving: Bool = false
    
    private var captureEngine: AVAudioEngine?
    private var playbackEngine: AVAudioEngine?
    private let playerNode = AVAudioPlayerNode()
    
    private var isCaptureActive = false
    private var voxEnabled = true
    private var voxThreshold: Float = 0.15
    private var voxHoldTime: Double = 15.0
    private var lastVOXTriggerDate: Date?
    private var onAudioCaptured: ((Data) -> Void)?
    private var audioConverter: AVAudioConverter?
    private var receivingClearTask: Task<Void, Never>?
    
    // Fixed sample rate for network transmission (both sides must agree)
    private let networkSampleRate: Double = 16000
    private let networkFormat: AVAudioFormat
    
    public init() {
        networkFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    }
    
    public func configureSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            // .default režim nevynucuje agresivní potlačení šumu a echa jako .voiceChat
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try session.setPreferredSampleRate(networkSampleRate)
            try session.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
        #endif
    }
    
    public func startCapture(voxEnabled: Bool, voxThreshold: Float, voxHoldTime: Double, onAudioCaptured: @escaping (Data) -> Void) {
        // Stop any existing capture first
        stopCapture()
        
        self.voxEnabled = voxEnabled
        self.voxThreshold = voxThreshold
        self.voxHoldTime = voxHoldTime
        self.onAudioCaptured = onAudioCaptured
        self.isCaptureActive = true
        
        configureSession()
        
        let engine = AVAudioEngine()
        self.captureEngine = engine
        
        let inputNode = engine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        
        if hardwareFormat.sampleRate != self.networkSampleRate || hardwareFormat.channelCount != 1 {
            self.audioConverter = AVAudioConverter(from: hardwareFormat, to: self.networkFormat)
        } else {
            self.audioConverter = nil
        }
        
        // Install tap using the hardware's native format
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { [weak self] buffer, _ in
            guard let self = self, self.isCaptureActive else { return }
            
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { return }
            
            // Zesílení surového zvuku (nahrazuje vypnuté systémové AGC)
            let softwareGain: Float = 4.0
            
            var rms: Float = 0.0
            for i in 0..<frameLength {
                // Aplikace zisku a oříznutí proti praskání (clipping)
                var sample = channelData[i] * softwareGain
                if sample > 1.0 { sample = 1.0 }
                else if sample < -1.0 { sample = -1.0 }
                
                channelData[i] = sample
                rms += sample * sample
            }
            rms = sqrt(rms / Float(frameLength))
            
            // AudioLevel pro vizualizér a VOX (už je zesíleno 4x nahoře, takže stačí malý dodatečný multiplikátor)
            let currentLevel = min(max(rms * 2.0, 0.0), 1.0)
            
            // Convert to network format (16kHz mono) if needed
            let dataToSend: Data
            if self.audioConverter != nil {
                if let converted = self.convertBuffer(buffer) {
                    let convertedLength = Int(converted.frameLength)
                    if let convertedData = converted.floatChannelData?[0], convertedLength > 0 {
                        dataToSend = Data(bytes: convertedData, count: convertedLength * MemoryLayout<Float>.size)
                    } else {
                        dataToSend = Data()
                    }
                } else {
                    dataToSend = Data()
                }
            } else {
                dataToSend = Data(bytes: channelData, count: frameLength * MemoryLayout<Float>.size)
            }
            
            Task { @MainActor in
                self.audioLevel = currentLevel
                
                // Slider 0 % → threshold 0.5 (less sensitive)
                // Slider 100 % → threshold 0.005 (very sensitive)
                let actualThreshold = (1.0 - self.voxThreshold) * 0.495 + 0.005
                
                var shouldTransmit = false
                
                if !self.voxEnabled {
                    shouldTransmit = true
                } else {
                    if currentLevel > actualThreshold {
                        self.lastVOXTriggerDate = Date()
                        shouldTransmit = true
                    } else if let lastTrigger = self.lastVOXTriggerDate, Date().timeIntervalSince(lastTrigger) < self.voxHoldTime {
                        shouldTransmit = true
                    } else {
                        shouldTransmit = false
                    }
                }
                
                self.isTransmitting = shouldTransmit
                
                if shouldTransmit && !dataToSend.isEmpty {
                    self.onAudioCaptured?(dataToSend)
                }
            }
        }
        
        do {
            try engine.start()
        } catch {
            print("Failed to start capture engine: \(error)")
        }
    }
    
    public func stopCapture() {
        isCaptureActive = false
        if let engine = captureEngine, engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        captureEngine = nil
        isTransmitting = false
        audioLevel = 0.0
    }
    
    /// Ensure playback engine is running (called by parent on connect)
    public func preparePlayback() {
        guard playbackEngine == nil else { return }
        
        configureSession()
        
        let engine = AVAudioEngine()
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: networkFormat)
        
        do {
            try engine.start()
            playerNode.play()
            self.playbackEngine = engine
        } catch {
            print("Failed to start playback engine: \(error)")
        }
    }
    
    public func playReceivedAudio(_ data: Data) {
        // Ensure playback engine is ready
        if playbackEngine == nil {
            preparePlayback()
        }
        
        guard let engine = playbackEngine, engine.isRunning else { return }
        
        if !playerNode.isPlaying {
            playerNode.play()
        }
        
        let frameCount = AVAudioFrameCount(data.count / MemoryLayout<Float>.size)
        guard frameCount > 0 else { return }
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: networkFormat, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        
        var rms: Float = 0.0
        data.withUnsafeBytes { rawBufferPointer in
            if let floats = rawBufferPointer.bindMemory(to: Float.self).baseAddress,
               let bufferData = buffer.floatChannelData?[0] {
                bufferData.update(from: floats, count: Int(frameCount))
                let count = Int(frameCount)
                for i in 0..<count {
                    let sample = floats[i]
                    rms += sample * sample
                }
                if count > 0 {
                    rms = sqrt(rms / Float(count))
                }
            }
        }
        
        playerNode.scheduleBuffer(buffer, completionHandler: nil)
        
        let receivedLevel = min(max(rms * 2.0, 0.0), 1.0)
        // While PTT capture is active, keep showing the parent's mic level.
        if !isCaptureActive {
            audioLevel = receivedLevel
        }
        isReceiving = true
        receivingClearTask?.cancel()
        receivingClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            isReceiving = false
            if !isCaptureActive {
                audioLevel = 0.0
            }
        }
    }
    
    public func stopPlayback() {
        receivingClearTask?.cancel()
        receivingClearTask = nil
        isReceiving = false
        playerNode.stop()
        playbackEngine?.stop()
        playbackEngine = nil
        if !isCaptureActive {
            audioLevel = 0.0
        }
    }
    
    // MARK: - Sample Rate Conversion
    
    private func convertBuffer(_ inputBuffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter = self.audioConverter else { return nil }
        
        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio)
        guard outputFrameCount > 0 else { return nil }
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: outputFrameCount) else { return nil }
        
        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }
        
        if let error = error {
            print("Audio conversion error: \(error)")
            return nil
        }
        
        return outputBuffer
    }
}
