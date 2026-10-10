import SwiftUI
import AVFoundation

/// Coordinator class to manage audio engine (needed for closure captures)
class CalibrationCoordinator {
    var audioEngine: AVAudioEngine?
    var playerNode: AVAudioPlayerNode?
}

/// Interactive calibration wizard for measuring device-specific audio-haptic latency.
/// User taps the screen when they hear a beep, and the system calculates the latency offset.
struct CalibrationWizardView: View {
    @Environment(\.dismiss) var dismiss
    @State private var calibrationState: CalibrationState = .instructions
    @State private var tapTimes: [TimeInterval] = []
    @State private var beepStartTime: TimeInterval = 0
    @State private var currentTrial = 0
    @State private var calibrationResult: TimeInterval?
    @State private var coordinator = CalibrationCoordinator()
    
    private let totalTrials = 5 // Number of calibration trials
    
    enum CalibrationState {
        case instructions
        case waitingForBeep
        case beepPlaying
        case waitingForTap
        case completed
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                switch calibrationState {
                case .instructions:
                    instructionsView
                case .waitingForBeep:
                    waitingForBeepView
                case .beepPlaying:
                    beepPlayingView
                case .waitingForTap:
                    waitingForTapView
                case .completed:
                    completedView
                }
            }
            .padding()
            .navigationTitle("Latency Calibration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Views
    
    private var instructionsView: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Calibration Wizard")
                .font(.system(size: 24, weight: .bold))
            
            Text("We'll play a beep sound. Tap the screen **exactly** when you hear it.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Text("This helps us synchronize haptics with audio on your device.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Start Calibration") {
                startCalibration()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
    
    private var waitingForBeepView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Get ready...")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text("A beep will play in a moment")
                .font(.body)
                .foregroundColor(.secondary)
        }
    }
    
    private var beepPlayingView: some View {
        VStack(spacing: 20) {
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
                .symbolEffect(.pulse)
            
            Text("🔊 Beep Playing")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Tap the screen NOW when you hear it!")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            handleTap()
        }
    }
    
    private var waitingForTapView: some View {
        VStack(spacing: 20) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text("Tap when you heard the beep")
                .font(.title2)
            
            Text("Trial \(currentTrial + 1) of \(totalTrials)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            handleTap()
        }
    }
    
    private var completedView: some View {
        VStack(spacing: 30) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
            
            if let result = calibrationResult {
                VStack(spacing: 10) {
                    Text("Calibration Complete")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Measured latency: \(String(format: "%.0f", result * 1000))ms")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    
                    Text("This value has been saved for your device.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            } else {
                Text("Calibration failed")
                    .font(.title)
                    .foregroundColor(.red)
            }
            
            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
    
    // MARK: - Calibration Logic
    
    private func startCalibration() {
        tapTimes = []
        currentTrial = 0
        runNextTrial()
    }
    
    private func runNextTrial() {
        guard currentTrial < totalTrials else {
            completeCalibration()
            return
        }
        
        // Random delay between 1-3 seconds before beep
        let delay = Double.random(in: 1.0...3.0)
        
        calibrationState = .waitingForBeep
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            playBeep()
        }
    }
    
    private func playBeep() {
        // Generate a simple beep tone (440 Hz, 0.1 seconds)
        let sampleRate: Double = 44100
        let frequency: Double = 440.0
        let duration: Double = 0.1
        let samples = Int(sampleRate * duration)
        
        var audioData = [Float](repeating: 0, count: samples)
        for i in 0..<samples {
            let t = Double(i) / sampleRate
            // Apply envelope to avoid clicks
            let envelope = i < 100 ? Float(i) / 100.0 : (i > samples - 100 ? Float(samples - i) / 100.0 : 1.0)
            audioData[i] = Float(sin(2.0 * .pi * frequency * t)) * envelope * 0.5
        }
        
        // Convert to AVAudioPCMBuffer and play
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples)) else {
            print("Failed to create audio buffer")
            calibrationState = .waitingForTap
            return
        }
        
        buffer.frameLength = AVAudioFrameCount(samples)
        if let channelData = buffer.floatChannelData {
            for i in 0..<samples {
                channelData[0][i] = audioData[i]
            }
        }
        
        // Record beep start time
        beepStartTime = CACurrentMediaTime()
        calibrationState = .beepPlaying
        
        // Play beep using AVAudioEngine
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        
        // Store engine and node in coordinator
        coordinator.audioEngine = engine
        coordinator.playerNode = node
        
        do {
            try engine.start()
            node.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            node.play()
            
            // Update state after beep duration completes
            // We use Task.sleep instead of DispatchQueue
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                if calibrationState == .beepPlaying {
                    calibrationState = .waitingForTap
                }
            }
        } catch {
            print("Failed to play beep: \(error)")
            calibrationState = .waitingForTap
        }
    }
    
    private func handleTap() {
        guard calibrationState == .beepPlaying || calibrationState == .waitingForTap else {
            return
        }
        
        let tapTime = CACurrentMediaTime()
        let latency = tapTime - beepStartTime
        
        // Store the measured latency
        tapTimes.append(latency)
        
        // Move to next trial
        currentTrial += 1
        
        if currentTrial < totalTrials {
            // Brief pause before next trial
            calibrationState = .waitingForBeep
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1.0 second
                runNextTrial()
            }
        } else {
            completeCalibration()
        }
    }
    
    private func completeCalibration() {
        guard !tapTimes.isEmpty else {
            calibrationResult = nil
            calibrationState = .completed
            return
        }
        
        // Calculate median latency (more robust than mean for outliers)
        let sortedTimes = tapTimes.sorted()
        let medianIndex = sortedTimes.count / 2
        let medianLatency = sortedTimes.count % 2 == 0
            ? (sortedTimes[medianIndex - 1] + sortedTimes[medianIndex]) / 2.0
            : sortedTimes[medianIndex]
        
        // Store calibration result
        LatencyCalibrationManager.shared.storeCalibration(latency: medianLatency)
        calibrationResult = medianLatency
        calibrationState = .completed
        
        print("📊 Calibration complete: \(medianLatency * 1000)ms (from \(tapTimes.count) trials)")
    }
}

