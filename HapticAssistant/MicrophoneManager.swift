import AVFoundation
import Foundation
import Combine

class MicrophoneManager: NSObject, ObservableObject, AVAudioRecorderDelegate {
    static let shared = MicrophoneManager()
    
    private var audioEngine: AVAudioEngine
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var isStopping = false // Flag to prevent multiple stop calls
    private var bufferCount = 0 // Debug counter for tracking tap callbacks
    
    @Published var isRecording = false
    @Published var permissionGranted = false
    @Published var audioLevel: Float = 0.0
    @Published var recordingDuration: TimeInterval = 0.0 // Actual recording duration

    /// History of normalized amplitude values (RMS) over the course of a recording. Each
    /// element corresponds to a buffer of audio processed in ``startRecording()``. This
    /// can be used for rhythm and stress analysis in the scoring pipeline. Values
    /// range roughly between 0.0 (silence) and 1.0 (very loud), with the same
    /// temporal spacing as entries in ``pitchHistory``.
    @Published var amplitudeHistory: [Float] = []
    
    private var pitchDetector: PitchDetector?
    @Published var pitchHistory: [Float] = [] // Normalized pitch (0-1 or -1 for silence)
    @Published var rawPitchHistory: [Float] = [] // Raw pitch in Hz (for speaker adaptation)
    
    /// Current user ID for speaker-adaptive pitch normalization
    var currentUserId: String? = nil
    
    override private init() {
        audioEngine = AVAudioEngine()
        super.init()
        
        // Check if running in SwiftUI Preview
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            print("MicrophoneManager: Running in Preview Mode - Recording Disabled")
            return
        }
        checkPermission()
    }
    
    func checkPermission() {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            permissionGranted = true
        case .denied:
            permissionGranted = false
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                Task { @MainActor in
                    self.permissionGranted = allowed
                }
            }
        @unknown default:
            break
        }
    }
    
    func startRecording() -> URL? {
        guard permissionGranted else {
            checkPermission()
            return nil
        }
        
        // Use .m4a format with AVAudioRecorder for reliable recording
        let fileName = "user_recording.m4a"
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(fileName)
        
        // Delete old file if it exists
        if FileManager.default.fileExists(atPath: path.path) {
            try? FileManager.default.removeItem(at: path)
        }
        
        // Audio session is configured once at app launch by AudioSessionManager
        // Just ensure it's active and allow mixing if needed
        do {
            let audioSession = AVAudioSession.sharedInstance()
            // Allow mixing so both AVAudioRecorder and AVAudioEngine can access the mic
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
            try audioSession.setActive(true, options: [])
            print("✅ Audio session activated for recording")
        } catch {
            print("⚠️ Failed to activate audio session: \(error)")
            return nil
        }
        
        // Setup AVAudioRecorder for reliable file recording
        let recorderSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 128000
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: path, settings: recorderSettings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true // Enable metering for audio level
            audioRecorder?.prepareToRecord()
            
            if audioRecorder?.record() == true {
                print("Recording started with AVAudioRecorder")
                print("Recording to: \(path.lastPathComponent)")
            } else {
                print("Failed to start AVAudioRecorder")
                return nil
            }
        } catch {
            print("Failed to create AVAudioRecorder: \(error.localizedDescription)")
            return nil
        }
        
        // Also setup audio engine for pitch/amplitude analysis
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        
        // Setup Pitch Detector
        pitchDetector = PitchDetector(sampleRate: Float(format.sampleRate))
        pitchHistory = []
        rawPitchHistory = []
        amplitudeHistory = []
        recordingDuration = 0.0 // Reset duration
        
        // Install tap for analysis only (not for recording - AVAudioRecorder handles that)
        inputNode.removeTap(onBus: 0)
        // Use smaller buffer size for more frequent callbacks (better real-time analysis)
        let bufferSize: AVAudioFrameCount = 2048  // Reduced from 4096 for more frequent updates
        isStopping = false
        bufferCount = 0 // Reset counter for new recording
        
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] (buffer, time) in
            guard let self = self, !self.isStopping else { return }
            
            self.bufferCount += 1
            // Log every 20th buffer to avoid spam
            if self.bufferCount % 20 == 0 {
                print("🎤 Audio tap: buffer #\(self.bufferCount), frames: \(buffer.frameLength), sampleRate: \(buffer.format.sampleRate)")
            }
            
            // Analyze Audio Level (RMS) for visualization
            if let channelData = buffer.floatChannelData?[0] {
                let channelDataValue = stride(from: 0, to: Int(buffer.frameLength), by: buffer.stride).map { channelData[$0] }
                let rms = sqrt(channelDataValue.map { $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))
                let level = min(max(rms * 5.0, 0), 1.0)
                
                // Update on main thread but use async to avoid blocking audio callback
                DispatchQueue.main.async {
                    self.audioLevel = level
                    self.amplitudeHistory.append(level)
                }
            }
            
            // Detect Pitch - capture pitchDetector to avoid potential actor isolation issues
            let detector = self.pitchDetector
            if let pitchHz = detector?.estimatePitch(from: buffer) {
                // Update on main thread
                DispatchQueue.main.async {
                    // Store raw pitch for speaker adaptation
                    self.rawPitchHistory.append(pitchHz)
                    
                    // Normalize using speaker-adaptive method (requires userId, will use default if not available)
                    // Note: userId should be set before recording starts
                    // For now, use default normalization if userId is not available
                    let normalizedPitch = SpeakerAdaptivePitchNormalizer.shared.normalizePitch(
                        pitchHz: pitchHz,
                        userId: self.currentUserId ?? "default"
                    )
                    self.pitchHistory.append(normalizedPitch)
                }
            } else {
                // Still record -1.0 for unvoiced segments to maintain timing alignment
                DispatchQueue.main.async {
                    self.pitchHistory.append(-1.0)
                    self.rawPitchHistory.append(-1.0)
                }
            }
        }
        
        do {
            try audioEngine.start()
            print("✅ Audio engine started for pitch detection")
            recordingURL = path
            isRecording = true
            return path
        } catch {
            print("Could not start audio engine: \(error)")
            audioRecorder?.stop()
            audioRecorder = nil
            return nil
        }
    }
    
    func stopRecording() {
        guard isRecording && !isStopping else { return }
        isStopping = true
        
        print("Stopping recording...")
        
        // Stop audio engine tap first to prevent further callbacks
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        print("🎤 Audio tap removed, total buffers processed: \(bufferCount)")
        
        // Stop AVAudioRecorder first - this ensures the file is properly finalized
        // IMPORTANT: Capture duration BEFORE stopping, as currentTime resets to 0 after stop()
        var capturedDuration: TimeInterval = 0.0
        if let recorder = audioRecorder {
            capturedDuration = recorder.currentTime // Capture BEFORE stopping
            recorder.stop()
            recordingDuration = capturedDuration
            print("AVAudioRecorder stopped. Duration: \(String(format: "%.3f", capturedDuration))s")
            
            // Verify file was written and calculate actual duration from file if needed
            if let url = recordingURL {
                // Give a moment for file to be finalized
                Task.detached(priority: .userInitiated) { [weak self] in
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                    guard let self = self else { return }
                    
                    if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) {
                        let fileSize = attributes[.size] as? Int64 ?? 0
                        print("Recorded file size: \(fileSize) bytes (\(String(format: "%.2f", Double(fileSize) / 1024.0)) KB)")
                        
                        // If duration was 0, try to get it from the audio file
                        if capturedDuration < 0.1 {
                            do {
                                let audioFile = try AVAudioFile(forReading: url)
                                let fileDuration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
                                Task { @MainActor in
                                    self.recordingDuration = fileDuration
                                }
                                print("Calculated duration from file: \(String(format: "%.3f", fileDuration))s")
                            } catch {
                                print("Could not read audio file duration: \(error)")
                            }
                        }
                        
                        if fileSize < 1000 {
                            print("WARNING: File size is very small! Recording may be incomplete.")
                        } else {
                            print("✓ Recording saved successfully")
                        }
                    } else {
                        print("WARNING: Could not read file attributes")
                    }
                }
            }
        }
        audioRecorder = nil
        
        // Stop audio engine for analysis
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        Task { @MainActor in
            self.isRecording = false
            self.isStopping = false
        }
    }
    
    // MARK: - AVAudioRecorderDelegate
    
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if flag {
            print("Recording finished successfully")
            if let url = recordingURL {
                if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) {
                    let fileSize = attributes[.size] as? Int64 ?? 0
                    print("Final file size: \(fileSize) bytes")
                }
            }
        } else {
            print("Recording finished with error")
        }
    }
}
