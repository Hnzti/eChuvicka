import Foundation
import AVFoundation

@MainActor
public class AudioManager: ObservableObject {
    @Published public var audioLevel: Float = 0.0
    @Published public var isTransmitting: Bool = false
    
    private var captureEngine: AVAudioEngine?
    private var playbackEngine: AVAudioEngine?
    private let playerNode = AVAudioPlayerNode()
    
    private var isCaptureActive = false
    private var voxEnabled = true
    private var voxThreshold: Float = 0.15
    private var onAudioCaptured: ((Data) -> Void)?
    
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
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try session.setPreferredSampleRate(networkSampleRate)
            try session.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
        #endif
    }
    
    public func startCapture(voxEnabled: Bool, voxThreshold: Float, onAudioCaptured: @escaping (Data) -> Void) {
        // Stop any existing capture first
        stopCapture()
        
        self.voxEnabled = voxEnabled
        self.voxThreshold = voxThreshold
        self.onAudioCaptured = onAudioCaptured
        self.isCaptureActive = true
        
        configureSession()
        
        let engine = AVAudioEngine()
        self.captureEngine = engine
        
        let inputNode = engine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        
        // Install tap using the hardware's native format
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { [weak self] buffer, _ in
            guard let self = self, self.isCaptureActive else { return }
            
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { return }
            
            // Calculate RMS for level metering
            var rms: Float = 0.0
            for i in 0..<frameLength {
                let sample = channelData[i]
                rms += sample * sample
            }
            rms = sqrt(rms / Float(frameLength))
            let currentLevel = min(max(rms * 5.0, 0.0), 1.0)
            
            // Convert to network format (16kHz mono) if needed
            let dataToSend: Data
            if hardwareFormat.sampleRate != self.networkSampleRate || hardwareFormat.channelCount != 1 {
                if let converted = self.convertBuffer(buffer, from: hardwareFormat, to: self.networkFormat) {
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
                
                let shouldTransmit = !self.voxEnabled || currentLevel > self.voxThreshold
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
    
    public var isAudioBoostEnabled: Bool = false
    
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
        
        data.withUnsafeBytes { rawBufferPointer in
            if let floats = rawBufferPointer.bindMemory(to: Float.self).baseAddress,
               let bufferData = buffer.floatChannelData?[0] {
                
                if isAudioBoostEnabled {
                    // Multiply samples by 2.0 (boost volume)
                    for i in 0..<Int(frameCount) {
                        bufferData[i] = floats[i] * 2.0
                    }
                } else {
                    bufferData.update(from: floats, count: Int(frameCount))
                }
            }
        }
        
        playerNode.scheduleBuffer(buffer, completionHandler: nil)
    }
    
    public func stopPlayback() {
        playerNode.stop()
        playbackEngine?.stop()
        playbackEngine = nil
    }
    
    // MARK: - Sample Rate Conversion
    
    private func convertBuffer(_ inputBuffer: AVAudioPCMBuffer, from inputFormat: AVAudioFormat, to outputFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else { return nil }
        
        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio)
        guard outputFrameCount > 0 else { return nil }
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCount) else { return nil }
        
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
