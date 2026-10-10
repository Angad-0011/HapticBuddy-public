import AVFoundation
import Foundation
import Combine
import Accelerate

@MainActor
class AudioPlayerManager: ObservableObject {
    static let shared = AudioPlayerManager()
    
    private var engine: AVAudioEngine
    private var playerNode: AVAudioPlayerNode
    private var speedControl: AVAudioUnitVarispeed // Node for speed control
    
    @Published var isPlaying = false
    @Published var amplitude: Float = 0.0
    @Published var fftMagnitudes: [Float] = [] // Frequency magnitudes
    
    @Published var playbackRate: Float = 1.0 {
        didSet {
            speedControl.rate = playbackRate
        }
    }
    
    var volume: Float = 1.0 {
        didSet {
            playerNode.volume = volume
        }
    }
    
    // FFT Setup
    private let fftSize = 1024
    private var fftSetup: vDSP_DFT_Setup?
    
    private init() {
        // Check if running in SwiftUI Preview
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            engine = AVAudioEngine()
            playerNode = AVAudioPlayerNode()
            speedControl = AVAudioUnitVarispeed()
            print("AudioPlayerManager: Running in Preview Mode - Audio Engine Disabled")
            return
        }
        
        // Initialize properties first
        engine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        speedControl = AVAudioUnitVarispeed()
        
        // Audio session is configured once at app launch by AudioSessionManager
        // No need to configure here
        
        engine.attach(playerNode)
        engine.attach(speedControl)
        
        // Connect: Player -> SpeedControl -> MainMixer
        engine.connect(playerNode, to: speedControl, format: nil)
        engine.connect(speedControl, to: engine.mainMixerNode, format: nil)
        
        // Setup FFT
        fftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(fftSize), vDSP_DFT_Direction.FORWARD)
        
        do {
            try engine.start()
        } catch {
            print("AudioEngine failed to start: \(error)")
        }
    }
    
    // Audio session configuration removed - handled by AudioSessionManager at app launch
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        
        // 1. Calculate Amplitude (RMS)
        let channelDataValue = stride(from: 0, to: frameLength, by: buffer.stride).map { channelData[$0] }
        let rms = sqrt(channelDataValue.map { $0 * $0 }.reduce(0, +) / Float(frameLength))
        let normalizedAmplitude = min(max(rms * 5.0, 0), 1.0)
        
        // 2. Calculate FFT
        // We need 'fftSize' samples. If buffer is smaller, pad with zeros.
        var realIn = [Float](repeating: 0, count: fftSize)
        var imagIn = [Float](repeating: 0, count: fftSize)
        var realOut = [Float](repeating: 0, count: fftSize)
        var imagOut = [Float](repeating: 0, count: fftSize)
        
        let count = min(frameLength, fftSize)
        for i in 0..<count {
            realIn[i] = channelData[i]
        }
        
        // Perform FFT
        if let setup = fftSetup {
            vDSP_DFT_Execute(setup, &realIn, &imagIn, &realOut, &imagOut)
        }
        
        // Calculate magnitudes
        // Magnitude = sqrt(real^2 + imag^2)
        // We only need the first half (Nyquist frequency)
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)
        
        // Use vDSP for fast calculation
        var complex = DSPSplitComplex(realp: &realOut, imagp: &imagOut)
        vDSP_zvabs(&complex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
        
        // Normalize magnitudes using log scale for better visualization
        // Apply logarithmic scaling to better distribute energy across frequency bands
        var normalizedMagnitudes = magnitudes.map { magnitude in
            // Use log scale: log10(x + 1) to avoid log(0)
            let logMagnitude = log10(max(magnitude, 0.001) + 1.0)
            // Normalize to 0-1 range (log10(1000) ≈ 3, so scale by 3)
            return min(logMagnitude / 3.0, 1.0)
        }
        
        // Downsample to fewer bars (e.g., 20) for UI
        // Use logarithmic frequency distribution for better visualization
        let barCount = 20
        var bars = [Float](repeating: 0.0, count: barCount)
        
        // Distribute frequencies logarithmically (more bars for lower frequencies)
        let totalBins = normalizedMagnitudes.count
        for i in 0..<barCount {
            // Logarithmic distribution: lower frequencies get more bins
            let startRatio = pow(Double(i) / Double(barCount), 1.5)
            let endRatio = pow(Double(i + 1) / Double(barCount), 1.5)
            let startBin = Int(startRatio * Double(totalBins))
            let endBin = min(Int(endRatio * Double(totalBins)), totalBins)
            
            if startBin < endBin {
                let slice = normalizedMagnitudes[startBin..<endBin]
                // Use max instead of average for more dynamic visualization
                bars[i] = slice.max() ?? 0.0
            }
        }
        
        // Apply smoothing and boost lower frequencies slightly for better visibility
        for i in 0..<barCount {
            let boost = 1.0 + (Float(barCount - i) / Float(barCount)) * 0.3
            bars[i] = min(bars[i] * boost, 1.0)
        }
        
        Task { @MainActor in
            self.amplitude = normalizedAmplitude
            self.fftMagnitudes = bars
        }
    }
    
    func play(url: URL, completion: @escaping () -> Void) {
        guard let file = try? AVAudioFile(forReading: url) else {
            print("Could not load file: \(url)")
            return
        }
        
        // Audio session is already configured at app launch - no need to reconfigure
        
        // Stop current playback
        playerNode.stop()
        
        // Remove existing tap if any
        engine.mainMixerNode.removeTap(onBus: 0)
        
        // Stop engine to safely reconfigure
        if engine.isRunning {
            engine.stop()
        }
        
        // Disconnect nodes to clear old format state
        engine.disconnectNodeOutput(playerNode)
        engine.disconnectNodeOutput(speedControl)
        
        // Re-connect with correct format
        engine.connect(playerNode, to: speedControl, format: file.processingFormat)
        engine.connect(speedControl, to: engine.mainMixerNode, format: file.processingFormat)
        
        // Install tap on mixer for visualization (after connecting)
        let mixer = engine.mainMixerNode
        let format = file.processingFormat
        mixer.installTap(onBus: 0, bufferSize: UInt32(fftSize), format: format) { [weak self] (buffer, time) in
            guard let self = self else { return }
            self.processAudioBuffer(buffer)
        }
        
        do {
            try engine.start()
        } catch {
            print("AudioEngine failed to start: \(error)")
            return
        }
        
        // Set current rate and volume
        speedControl.rate = playbackRate
        playerNode.volume = volume
        
        // Reset visualization
        amplitude = 0.0
        fftMagnitudes = []
        
        playerNode.scheduleFile(file, at: nil) {
            Task { @MainActor in
                // Remove tap when done
                self.engine.mainMixerNode.removeTap(onBus: 0)
                self.isPlaying = false
                self.amplitude = 0.0 // Reset visualizer
                self.fftMagnitudes = []
                completion()
            }
        }
        
        playerNode.play()
        isPlaying = true
    }
    
    func stop() {
        playerNode.stop()
        engine.mainMixerNode.removeTap(onBus: 0)
        isPlaying = false
        amplitude = 0.0
        fftMagnitudes = []
    }
}
