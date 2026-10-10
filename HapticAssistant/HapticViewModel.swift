import Foundation
import Combine
import AVFoundation

// Model for a learning phrase
struct Phrase: Identifiable, Codable {
    let id: String // Stable identifier for cross-session tracking
    let text: String
    let audioFileName: String
    let intonationType: IntonationType
    let stressIndices: [Int] // Indices of syllables that are stressed
    let syllableDurations: [TimeInterval] // Duration of each syllable (fallback if timestamps not available)
    let syllableTextures: [String]? // Optional textures: "sharp", "soft", "grainy"
    let category: String? // Category for grouping phrases (e.g., "Greetings", "Travel")
    let difficulty: Difficulty? // Difficulty level
    let tags: [String]? // Topical labels
    let sets: [PhraseSet]? // Training/transfer sets
    
    // Forced alignment: exact start/end timestamps for each syllable (in seconds from audio start)
    // Format: [[start, end], [start, end], ...] for each syllable
    // If provided, these override syllableDurations for precise haptic synchronization
    let syllableTimestamps: [[TimeInterval]]? // Optional: [[start, end], ...] for each syllable
    
    enum CodingKeys: String, CodingKey {
        case id, text, audioFileName, intonationType, stressIndices, syllableDurations, syllableTextures, category, difficulty, tags, sets, syllableTimestamps
    }
}

enum Difficulty: String, Codable {
    case beginner = "beginner"
    case intermediate = "intermediate"
    case advanced = "advanced"
}

enum PhraseSet: String, Codable {
    case training = "training"
    case transfer = "transfer"
    case preTest = "preTest"
    case postTest = "postTest"
}

enum IntonationType: String, Codable {
    case rising
    case falling
    case flat
}

@MainActor
class HapticViewModel: ObservableObject {
    @Published var currentPhrase: Phrase?
    @Published var isPlaying = false
    @Published var feedbackMessage = "Ready to practice"
    @Published var phrases: [Phrase] = []
    
    @Published var hapticIntensity: Float = 1.0 {
        didSet {
            hapticManager.intensityMultiplier = hapticIntensity
        }
    }
    
    @Published var playbackRate: Float = 1.0 {
        didSet {
            audioManager.playbackRate = playbackRate
        }
    }
    
    // Experiment State
    @Published var userId: String = "Guest"
    @Published var condition: ExperimentCondition = .practice
    
    private let hapticManager = HapticEngineManager.shared
    private let audioManager = AudioPlayerManager.shared
    private let scoringEngine = ScoringEngine()
    let progressManager = ProgressManager()
    let micManager = MicrophoneManager.shared
    
    // Local State
    @Published var isRecording = false
    @Published var micLevel: Float = 0.0
    @Published var recordedAudioURL: URL?
    @Published var showScorePopup = false
    @Published var lastScore: Int = 0
    @Published var lastMetrics: PronunciationMetrics?
    @Published var lastPitchHistory: [Float] = [] // Store pitch history for visualization
    @Published var recordingQuality: RecordingQualityMetrics?
    @Published var showQualityAlert = false
    @Published var qualityAlertMessage = ""
    @Published var shouldRetryRecording = false
    
    // Track previous recordings for suspicious data detection
    private var previousRecordings: [RecordingQualityMetrics] = []
    
    private var cancellables = Set<AnyCancellable>()
    private var micLevelCancellable: AnyCancellable?
    
    init() {
        loadPhrases()
        setupHapticModulation()
    }
    
    private func setupHapticModulation() {
        $micLevel
            .throttle(for: .milliseconds(50), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] level in
                guard let self = self else { return }
                // Only modulate if we are Playing (haptics active) AND Recording (user speaking)
                if self.isPlaying && self.isRecording {
                    self.hapticManager.updateIntensity(level)
                }
            }
            .store(in: &cancellables)
    }
    
    func loadPhrases() {
        let repository = PhraseRepository.shared
        let result = repository.loadPhrases()
        
        switch result {
        case .success(let loadedPhrases):
            phrases = loadedPhrases
        if let first = phrases.first {
            currentPhrase = first
            }
        case .failure(let error):
            print("Failed to load phrases: \(error.localizedDescription)")
            feedbackMessage = "Error loading phrases. Please restart the app."
            // Fallback to empty array - app will show error state
            phrases = []
        }
    }
    
    func toggleRecording() {
        if isRecording {
            micManager.stopRecording()
            isRecording = false
            feedbackMessage = "Recording stopped."
            
            // Cancel mic level subscription when recording stops
            micLevelCancellable?.cancel()
            micLevelCancellable = nil
            
            // Calculate and save score
            if let phrase = currentPhrase {
                // Capture histories for thread safety
                let pitchHist = micManager.pitchHistory
                let ampHist = micManager.amplitudeHistory
                let recordingURL = recordedAudioURL
                
                // Wait a moment for recording to finalize before validation
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                    guard let self = self else { return }
                    
                    // Comprehensive quality validation
                    let actualDuration = self.micManager.recordingDuration
                    let expectedDuration = self.getExpectedPhraseDuration(phrase: phrase)
                    
                    let qualityMetrics = RecordingQualityValidator.shared.validateRecording(
                        duration: actualDuration,
                        pitchHistory: pitchHist,
                        amplitudeHistory: ampHist,
                        audioFileURL: recordingURL,
                        expectedPhraseDuration: expectedDuration
                    )
                    
                    self.recordingQuality = qualityMetrics
                    
                    // Log quality metrics
                    print("📊 Recording Quality Assessment:")
                    print("   Quality: \(qualityMetrics.quality.rawValue) (Score: \(String(format: "%.1f", qualityMetrics.qualityScore)))")
                    print("   Duration: \(String(format: "%.2f", qualityMetrics.duration))s")
                    print("   Samples: \(qualityMetrics.sampleCount) (Valid pitch: \(qualityMetrics.validPitchSamples))")
                    print("   Amplitude: avg=\(String(format: "%.4f", qualityMetrics.averageAmplitude)), max=\(String(format: "%.4f", qualityMetrics.maxAmplitude))")
                    if let snr = qualityMetrics.signalToNoiseRatio {
                        print("   SNR: \(String(format: "%.1f", snr)) dB")
                    }
                    if !qualityMetrics.issues.isEmpty {
                        print("   Issues: \(qualityMetrics.issues.joined(separator: ", "))")
                    }
                    
                    // Check for suspicious data
                    let suspiciousCheck = RecordingQualityValidator.shared.checkSuspiciousData(
                        currentRecording: qualityMetrics,
                        previousRecordings: self.previousRecordings
                    )
                    
                    if suspiciousCheck.isSuspicious {
                        print("⚠️ SUSPICIOUS DATA DETECTED: \(suspiciousCheck.reason ?? "Unknown")")
                        self.qualityAlertMessage = "⚠️ \(suspiciousCheck.reason ?? "Recording appears to be a duplicate")\n\nPlease record again to ensure data quality."
                        self.shouldRetryRecording = true
                        self.showQualityAlert = true
                        return
                    }
                    
                    // Check if quality is acceptable
                    if qualityMetrics.quality.shouldRetry {
                        // Poor or invalid quality - prompt for retry
                        var message = "\(qualityMetrics.quality.message)\n\n"
                        if !qualityMetrics.issues.isEmpty {
                            message += "Issues found:\n• " + qualityMetrics.issues.joined(separator: "\n• ")
                        }
                        if !qualityMetrics.recommendations.isEmpty {
                            message += "\n\nRecommendations:\n• " + qualityMetrics.recommendations.joined(separator: "\n• ")
                        }
                        
                        self.qualityAlertMessage = message
                        self.shouldRetryRecording = true
                        self.showQualityAlert = true
                        self.feedbackMessage = qualityMetrics.quality.message
                        return
                    }
                    
                    // Quality is acceptable - store for future suspicious data checks
                    self.previousRecordings.append(qualityMetrics)
                    // Keep only last 10 recordings to avoid memory issues
                    if self.previousRecordings.count > 10 {
                        self.previousRecordings.removeFirst()
                    }
                    
                    // Update feedback with quality info
                    if qualityMetrics.quality == .excellent {
                        self.feedbackMessage = "✅ Excellent recording quality!"
                    } else if qualityMetrics.quality == .good {
                        self.feedbackMessage = "✅ Good recording quality"
                    } else {
                        self.feedbackMessage = "Recording quality: \(qualityMetrics.quality.rawValue)"
                    }
                    
                    // Validation passed - proceed with scoring
                    self.performScoring(phrase: phrase, pitchHist: pitchHist, ampHist: ampHist, recordingURL: recordingURL)
                }
                
            }
            
        } else {
            // Practice Mode: Allow recording while playing
            // We do NOT stop playback here anymore.
            
            // Set userId in MicrophoneManager for speaker-adaptive pitch normalization
            micManager.currentUserId = userId.isEmpty ? nil : userId
            
            if let url = micManager.startRecording() {
                isRecording = true
                feedbackMessage = "Recording... (Tap to stop)"
                recordedAudioURL = url
                
                // Observe mic level - cancel previous subscription if any
                micLevelCancellable?.cancel()
                micLevelCancellable = micManager.$audioLevel
                    .receive(on: DispatchQueue.main)
                    .assign(to: \.micLevel, on: self)
                
            } else {
                feedbackMessage = "Microphone access denied."
            }
        }
    }
    
    private func getAudioURL(for fileName: String) -> URL? {
        // Try wav first, then mp3
        if let url = Bundle.main.url(forResource: fileName, withExtension: "wav") {
            return url
        }
        return Bundle.main.url(forResource: fileName, withExtension: "mp3")
    }
    
    // MARK: - Playback
    
    func selectPhrase(_ phrase: Phrase) {
        currentPhrase = phrase
        stopPlayback()
        feedbackMessage = "Ready to practice"
    }
    
    func playPhrase() {
        guard let phrase = currentPhrase else { return }
        
        if isPlaying {
            stopPlayback()
            return
        }
        
        // If the current experiment condition is TextOnly, we don't play audio or haptics.  Instead,
        // provide a prompt instructing the user to read the phrase aloud.  We also avoid
        // toggling the `isPlaying` flag so that other UI elements remain in a ready state.
        if condition == .textOnly {
            feedbackMessage = "Practice reading the phrase: \(phrase.text)"
            isPlaying = false
            return
        }

        isPlaying = true
        feedbackMessage = "Playing..."
        
        // For pre-test/post-test, audio file might be empty - that's okay
        if phrase.audioFileName.isEmpty {
            feedbackMessage = "Read the phrase: \(phrase.text)"
            isPlaying = false
            return
        }
        
        guard let audioURL = getAudioURL(for: phrase.audioFileName) else {
            print("ERROR: Audio file not found for: \(phrase.audioFileName)")
            feedbackMessage = "Audio file not found: \(phrase.audioFileName). Please read the phrase aloud."
            isPlaying = false
            return
        }
        
        print("Playing audio file: \(audioURL.lastPathComponent)")
        
        // Get actual audio file duration for precise haptic synchronization
        var actualAudioDuration: TimeInterval? = nil
        do {
            let audioFile = try AVAudioFile(forReading: audioURL)
            actualAudioDuration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
            print("📊 Audio file duration: \(String(format: "%.3f", actualAudioDuration ?? 0))s")
        } catch {
            print("⚠️ Could not read audio file duration: \(error)")
            // Fallback to syllable durations
            actualAudioDuration = phrase.syllableDurations.reduce(0, +)
        }
        
        // Play Haptics FIRST if condition allows - before audio starts
        // This ensures haptics are ready when audio begins
        let shouldPlayHaptics = condition == .hapticAudio || condition == .practice
        
        print("🎯 Haptic check - Condition: '\(condition)', Should play: \(shouldPlayHaptics)")
        
        // Start haptics and audio simultaneously for perfect synchronization
        if shouldPlayHaptics {
            Task { @MainActor in
                do {
                    // Start haptics immediately
                    print("🎵 Starting haptics and audio simultaneously")
                    
                    // Pass actual audio duration for precise timing
                    try await hapticManager.playPhrasePattern(
                        phrase: phrase,
                        startDelay: 0, // Start haptics immediately
                        actualAudioDuration: actualAudioDuration
                    )
                    print("✅ Haptics started (condition: \(condition))")
            } catch {
                    print("❌ Haptic playback failed: \(error)")
                }
            }
        } else {
            print("⏸️ Haptics disabled for condition: '\(condition)' (expected: 'HapticAudio' or 'Practice')")
        }
        
        // Play Audio - start at the same time as haptics
        // Both start simultaneously for perfect synchronization
        audioManager.play(url: audioURL) { [weak self] in
            Task { @MainActor in
                self?.isPlaying = false
                self?.feedbackMessage = "Ready to practice"
            }
        }
    }
    
    func stopPlayback() {
        audioManager.stop()
        hapticManager.stopPattern()
        isPlaying = false
        feedbackMessage = "Stopped."
    }
    
    // MARK: - Scoring Logic
    // Scoring logic has been moved to ScoringEngine class
    
    @MainActor
    private func performScoring(phrase: Phrase, pitchHist: [Float], ampHist: [Float], recordingURL: URL?) {
        Task {
            // Get raw pitch history for speaker-adaptive normalization
            let rawPitchHist = MicrophoneManager.shared.rawPitchHistory
            
            // Update speaker pitch range based on raw pitch values
            if !rawPitchHist.isEmpty && !self.userId.isEmpty {
                let validRawPitch = rawPitchHist.filter { $0 > 0 }
                if !validRawPitch.isEmpty {
                    SpeakerAdaptivePitchNormalizer.shared.updatePitchRange(
                        for: self.userId,
                        from: validRawPitch
                    )
                }
            }
            
            // Calculate basic metrics first (capture in local variable to avoid race condition)
            // Run calculation in background to avoid blocking UI
            // Capture scoringEngine before entering detached task to avoid actor isolation issues
            let engine = self.scoringEngine
            let capturedUserId = self.userId
            let metrics = await Task.detached(priority: .userInitiated) {
                return engine.calculateMetrics(
                    for: phrase,
                    pitchHistory: pitchHist,
                    amplitudeHistory: ampHist,
                    rawPitchHistory: rawPitchHist.isEmpty ? nil : rawPitchHist,
                    userId: capturedUserId.isEmpty ? nil : capturedUserId
                )
            }.value
            
            // Calculate ASR-based GOP asynchronously if audio file is available
            // Capture metrics in closure to avoid reading self.lastMetrics later (fixes race condition)
            if let url = recordingURL {
                // Capture current metrics (metrics is already awaited, so it's PronunciationMetrics)
                let capturedMetrics = metrics
                
                // Get reference audio URL if available (for MFCC mode)
                let referenceAudioURL = self.getAudioURL(for: phrase.audioFileName)
                
                // Use strict mode (phoneme-level) by default, with MFCC mode if reference audio is available
                let useMFCCMode = referenceAudioURL != nil && !phrase.audioFileName.isEmpty
                
                // Use async/await for GOP calculation
                let gopScore = await self.scoringEngine.calculateGOP(
                    audioURL: url,
                    targetText: phrase.text,
                    referenceAudioURL: referenceAudioURL,
                    useStrictMode: true, // Use phoneme-level scoring (strict mode)
                    useMFCCMode: useMFCCMode // Use MFCC if reference audio available
                )
                
                // Update metrics with GOP score using captured metrics (not self.lastMetrics)
                if let gop = gopScore {
                    // Recalculate final score with GOP weight if available
                    let weights = ScoringWeightsManager.shared.getWeights()
                    var finalScore = capturedMetrics.finalScore
                    
                    if let gopWeight = weights.gopWeight {
                        // Remove GOP weight from other scores and add GOP
                        let nonGOPWeight = 1.0 - gopWeight
                        finalScore = (capturedMetrics.finalScore * nonGOPWeight) + (Double(gop) * gopWeight)
                    }
                    
                    // Create updated metrics with GOP
                    let updatedMetrics = PronunciationMetrics(
                        finalScore: finalScore,
                        dtwScore: capturedMetrics.dtwScore,
                        rhythmScore: capturedMetrics.rhythmScore,
                        stressScore: capturedMetrics.stressScore,
                        gopScore: gop,
                        lsrScore: capturedMetrics.lsrScore,
                        f0RMSE: capturedMetrics.f0RMSE
                    )
                    self.lastMetrics = updatedMetrics
                    
                    print("✓ GOP score calculated: \(String(format: "%.1f", gop))%")
                } else {
                    print("⚠️ GOP calculation failed or unavailable")
                }
            }
            
            let intScore = Int(metrics.finalScore.rounded())
            // Update UI-related state on the main thread
            self.lastScore = intScore
            self.lastMetrics = metrics
            self.lastPitchHistory = pitchHist // Store pitch history for visualization
            self.progressManager.addScore(phraseId: phrase.id, score: intScore)
            
            // Experiment Logging
            if let url = recordingURL {
                _ = ExperimentManager.shared.saveRecording(
                    sourceURL: url,
                    userId: self.userId,
                    condition: self.condition.rawValue,
                    phraseId: phrase.id
                )
                // Log trial (for practice mode, use "Practice" phase)
                // Sanitize metrics before logging (remove NaN/infinite values)
                func sanitize(_ value: Double) -> Double {
                    if value.isNaN || value.isInfinite {
                        return -1.0
                    }
                    return value
                }
                
                // Generate a session UUID for practice mode (or use existing if available)
                let practiceSessionUUID = UUID().uuidString
                
                ExperimentManager.shared.logTrial(
                    userId: self.userId,
                    sessionUUID: practiceSessionUUID,
                    condition: self.condition.rawValue,
                    phase: "Practice",
                    phraseId: phrase.id,
                    trialIndex: 0, // Practice mode doesn't track trial index
                    metrics: [
                        "dtw_score": sanitize(metrics.dtwScore),
                        "rhythm_score": sanitize(metrics.rhythmScore),
                        "stress_score": sanitize(metrics.stressScore),
                        "lsr_score": sanitize(metrics.lsrScore),
                        "f0_rmse": sanitize(metrics.f0RMSE),
                        "gop_score": metrics.gopScore.map(sanitize) ?? -1.0,
                        "final_score": sanitize(metrics.finalScore)
                    ]
                )
            }
            // Show score in feedback message
            self.feedbackMessage = "Score: \(intScore)/100 - \(metrics.feedback)"
            self.showScorePopup = true
        }
    }
    
    func resetProgress() {
        progressManager.resetProgress()
        feedbackMessage = "Progress reset."
    }
    
    /// Get expected duration for a phrase (for quality validation)
    private func getExpectedPhraseDuration(phrase: Phrase) -> TimeInterval? {
        // Sum of syllable durations gives approximate phrase duration
        let totalDuration = phrase.syllableDurations.reduce(0, +)
        return totalDuration > 0 ? totalDuration : nil
    }
    
    /// Clear previous recordings (e.g., when starting new phrase)
    func clearPreviousRecordings() {
        previousRecordings.removeAll()
    }
}
