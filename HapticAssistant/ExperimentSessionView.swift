import SwiftUI
import Darwin
import AVFoundation

struct ExperimentSessionView: View {
    @EnvironmentObject var viewModel: HapticViewModel
    @State private var showMetadataForm = true
    @State private var participantMetadata: ParticipantMetadata?
    @State private var sessionConfig: ExperimentSessionConfig?
    @State private var isSessionActive = false
    @State private var currentPhase: ExperimentPhase = .preTest
    @State private var currentTrialIndex = 0
    @State private var showCompletion = false
    @State private var showPostSessionQuestionnaire = false
    @State private var collectedTrialQuestions: [SubjectiveMetrics] = [] // Store all trial questions for end
    @State private var preTestPhrases: [Phrase] = [] // 3 pre-test phrases
    @State private var trainingPhrases: [Phrase] = [] // 10 training phrases (in order)
    @State private var postTestTrainingPhrases: [Phrase] = [] // 3 phrases from training for post-test
    
    // Trial tracking
    @State private var playbackAttempts = 0
    @State private var recordingAttempts = 0
    @State private var trialStartTime: Date?
    @State private var playStartTime: Date?
    @State private var recordStartTime: Date?
    
    var currentCondition: ExperimentCondition {
        guard let config = sessionConfig, isSessionActive else { return .practice }
        
        switch currentPhase {
        case .preTest:
            return .textOnly // Pre-test: no audio or haptics (read only)
        case .postTest:
            return .audioOnly // Post-test: audio only (no haptics)
        case .training:
            // Training phase: always use haptic + audio (all trials have both)
            return .hapticAudio
        case .practice:
            return .practice
        }
    }
    
    var currentPhrase: Phrase? {
        switch currentPhase {
        case .preTest:
            // 3 pre-test phrases
            guard currentTrialIndex < preTestPhrases.count else { return nil }
            return preTestPhrases[currentTrialIndex]
        case .training:
            // 10 training phrases (in order, not randomized)
            guard currentTrialIndex < trainingPhrases.count else { return nil }
            return trainingPhrases[currentTrialIndex]
        case .postTest:
            // First 3 are pre-test phrases, then 3 from training
            if currentTrialIndex < 3 {
                // Pre-test phrases (repeated)
                guard currentTrialIndex < preTestPhrases.count else { return nil }
                return preTestPhrases[currentTrialIndex]
            } else {
                // Training phrases for post-test
                let trainingIndex = currentTrialIndex - 3
                guard trainingIndex < postTestTrainingPhrases.count else { return nil }
                return postTestTrainingPhrases[trainingIndex]
            }
        case .practice:
            // Practice mode - not used in experiment sessions
            return nil
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                if showMetadataForm && participantMetadata == nil {
                    ParticipantMetadataFormView(isPresented: $showMetadataForm) { metadata in
                        participantMetadata = metadata
                        ExperimentManager.shared.saveParticipantMetadata(metadata)
                        initializeSession()
                    }
                } else if !isSessionActive {
                    setupView
                } else if showCompletion {
                    completionView
                } else if showPostSessionQuestionnaire {
                    PostSessionQuestionnaireView(
                        userId: participantMetadata?.userId ?? "",
                        onComplete: { metrics in
                            print("✅ Questionnaire completed, saving metrics...")
                            ExperimentManager.shared.saveSubjectiveMetrics(metrics)
                            print("✅ Metrics saved, showing completion view")
                            showPostSessionQuestionnaire = false
                            showCompletion = true
                        }
                    )
                } else {
                    trialView
                }
            }
            .navigationTitle("Experiment Session")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    var setupView: some View {
        VStack(spacing: 20) {
            Text("Ready to Begin")
                .font(.title)
            
            if let metadata = participantMetadata {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Participant: \(metadata.userId)")
                    Text("Proficiency: \(metadata.englishProficiency.rawValue)")
                    Text("Native Language: \(metadata.nativeLanguage)")
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)
            }
            
            Text("The experiment consists of:\n1. Pre-test (3 recordings)\n2. Training (10 trials)\n3. Post-test (6 recordings)")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            Button("Start Experiment") {
                    startSession()
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .padding()
    }
    
    var trialView: some View {
        VStack(spacing: 20) {
            // Phase and progress display
            VStack(spacing: 8) {
                Text(phaseDisplayName)
                .font(.headline)
            
                Text("Trial \(currentTrialIndex + 1) / \(totalTrialsInPhase)")
                .font(.subheadline)
                .foregroundColor(.secondary)
                
                Text("Condition: \(currentCondition)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Progress bar
                ProgressView(value: Double(currentTrialIndex + 1), total: Double(totalTrialsInPhase))
                    .progressViewStyle(LinearProgressViewStyle())
                    .padding(.horizontal)
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
            
            Divider()
            
            if let phrase = currentPhrase {
                Text(phrase.text)
                    .font(.title2)
                    .multilineTextAlignment(.center)
                    .padding()
                
                // Play button - hide if audioFileName is empty (pre-test/post-test passages)
                if currentCondition != .textOnly && !phrase.audioFileName.isEmpty {
                    Button(action: {
                        playStartTime = Date()
                        playbackAttempts += 1
                        viewModel.playPhrase()
                    }) {
                        Image(systemName: "play.circle.fill")
                            .resizable()
                            .frame(width: 60, height: 60)
                            .foregroundColor(.blue)
                    }
                } else {
                    Text(phrase.audioFileName.isEmpty ? "Read the passage aloud" : "Read the phrase aloud")
                        .font(.caption)
                        .padding()
                }
                
                // Recording Control
                Button(action: {
                    if viewModel.isRecording {
                        // Stopping recording - set stop time
                        // (recordStartTime was already set when starting)
                    } else {
                        // Starting recording - increment attempts and set start time
                        recordingAttempts += 1
                        recordStartTime = Date()
                    }
                    viewModel.toggleRecording()
                }) {
                    ZStack {
                        Circle()
                        .fill(viewModel.isRecording ? Color.red : Color.gray)
                        .frame(width: 80, height: 80)
                    
                    if viewModel.isRecording {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white)
                            .frame(width: 30, height: 30)
                    } else {
                        Circle()
                            .stroke(Color.white, lineWidth: 4)
                            .frame(width: 70, height: 70)
                    }
                }
            }
            }
            
            // Real-time pitch contour overlay (during recording)
            if viewModel.isRecording, let phrase = currentPhrase {
                // Estimate expected length based on phrase duration
                let expectedLength = Int(phrase.syllableDurations.reduce(0, +) * 10) // ~10 samples per second
                let targetPitch = generateTargetPitchContour(for: phrase, expectedLength: max(expectedLength, 50))
                
                RealTimePitchContourView(
                    targetPitch: targetPitch,
                    intonationType: phrase.intonationType
                )
                .padding(.vertical, 10)
            } else {
                // Visualizer for recording feedback - shows voice amplitude changes (when not recording)
                VisualizerView(overrideAmplitude: viewModel.micLevel)
                    .frame(height: 60)
                    .padding(.vertical, 10)
            }
            
            Text(viewModel.feedbackMessage)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            // Quality indicator
            if let quality = viewModel.recordingQuality {
                HStack(spacing: 8) {
                    Image(systemName: qualityIcon(quality.quality))
                        .foregroundColor(qualityColor(quality.quality))
                    Text("Quality: \(quality.quality.rawValue) (\(Int(quality.qualityScore))%)")
                        .font(.caption)
                        .foregroundColor(qualityColor(quality.quality))
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
                .background(qualityColor(quality.quality).opacity(0.1))
                .cornerRadius(8)
        }
        
        Spacer()
        
            Button("Next") {
                completeTrial()
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(viewModel.recordedAudioURL != nil && !viewModel.shouldRetryRecording ? Color.blue : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(10)
            .disabled(viewModel.isRecording || viewModel.recordedAudioURL == nil || viewModel.shouldRetryRecording)
        }
        .padding()
        .overlay {
            // Quality alert overlay
            if viewModel.showQualityAlert {
                RecordingQualityAlertView(
                    isPresented: $viewModel.showQualityAlert,
                    message: viewModel.qualityAlertMessage,
                    onRetry: {
                        // Clear current recording and allow retry
                        viewModel.recordedAudioURL = nil
                        viewModel.shouldRetryRecording = false
                        viewModel.recordingQuality = nil
                        viewModel.feedbackMessage = "Please record again"
                    },
                    onContinue: {
                        // Allow continuing despite poor quality (for research purposes)
                        viewModel.shouldRetryRecording = false
                        viewModel.feedbackMessage = "Continuing with current recording..."
                    },
                    allowContinue: true // Allow researchers to continue if needed
                )
            }
        }
    .onAppear {
        updateViewModelState()
            if trialStartTime == nil {
                trialStartTime = Date()
            }
    }
    .onChange(of: currentTrialIndex) { _ in
        updateViewModelState()
            trialStartTime = Date()
            playbackAttempts = 0
            recordingAttempts = 0
        }
        .onChange(of: currentPhase) { _ in
            updateViewModelState()
        }
        .onChange(of: currentCondition) { _ in
            updateViewModelState()
        }
        .onChange(of: currentTrialIndex) { _ in
            // Clear previous recordings when starting new trial
            viewModel.clearPreviousRecordings()
        }
    }
    
    // MARK: - Helper Functions
    
    private func qualityIcon(_ quality: RecordingQuality) -> String {
        switch quality {
        case .excellent: return "checkmark.circle.fill"
        case .good: return "checkmark.circle"
        case .acceptable: return "exclamationmark.circle"
        case .poor: return "xmark.circle"
        case .invalid: return "xmark.circle.fill"
        }
    }
    
    private func qualityColor(_ quality: RecordingQuality) -> Color {
        switch quality {
        case .excellent: return .green
        case .good: return .blue
        case .acceptable: return .orange
        case .poor: return .red
        case .invalid: return .red
    }
}

var completionView: some View {
    VStack(spacing: 20) {
        Image(systemName: "checkmark.seal.fill")
            .resizable()
            .frame(width: 100, height: 100)
            .foregroundColor(.green)
        
        Text("Session Complete")
            .font(.largeTitle)
        
        Text("Thank you for participating!")
        
        Button("Export Data") {
            if let topVC = findTopViewController() {
                    ExperimentManager.shared.exportData(
                        from: topVC,
                        userId: participantMetadata?.userId,
                        format: .all
                    )
            }
        }
        .padding()
        .background(Color.blue)
        .foregroundColor(.white)
        .cornerRadius(10)
        
        Button("Reset") {
                resetSession()
        }
        .padding(.top)
    }
}

    // MARK: - Computed Properties
    
    var phaseDisplayName: String {
        switch currentPhase {
        case .preTest: return "Pre-Test"
        case .training: return "Training Phase"
        case .postTest: return "Post-Test"
        case .practice: return "Practice"
        }
    }
    
    var totalTrialsInPhase: Int {
        switch currentPhase {
        case .preTest: return 3 // 3 pre-test phrases
        case .training: return 10 // 10 training phrases
        case .postTest: return 6 // 3 pre-test phrases + 3 from training
        case .practice: return 0 // Not used in experiment sessions
        }
    }
    
    // MARK: - Functions
    
    func initializeSession() {
        guard let metadata = participantMetadata else { return }
        
        // Get phrases for each phase
        let allPhrases = viewModel.phrases
        let seed = metadata.userId.hashValue
        
        // Pre-test: 3 custom phrases (not from database)
        preTestPhrases = ExperimentRandomizer.getPreTestPhrases()
        
        // Training: 10 phrases from database (in order, not randomized)
        trainingPhrases = ExperimentRandomizer.getTrainingPhrases(from: allPhrases)
        
        // Post-test: 3 phrases from training set
        postTestTrainingPhrases = ExperimentRandomizer.getPostTestTrainingPhrases(from: trainingPhrases, seed: seed)
        
        // Generate condition order
        let conditionOrder = ExperimentRandomizer.generateConditionOrder(userId: metadata.userId, seed: seed)
        
        // Create phrase order (IDs) - include all phrases used in experiment
        let phraseOrder = (preTestPhrases + trainingPhrases + postTestTrainingPhrases).map { $0.id }
        
        // Generate session UUID for this experiment session
        let sessionUUID = UUID().uuidString
        
        // Create session config
        let config = ExperimentSessionConfig(
            userId: metadata.userId,
            sessionUUID: sessionUUID,
            participantMetadata: metadata,
            conditionOrder: conditionOrder,
            phraseOrder: phraseOrder,
            randomizationSeed: seed,
            sessionStartTime: Date(),
            currentPhase: .preTest,
            currentTrialIndex: 0
        )
        
        sessionConfig = config
        ExperimentManager.shared.saveSessionConfig(config)
    }

func startSession() {
        guard let metadata = participantMetadata else { return }
        viewModel.userId = metadata.userId
        // Set userId in MicrophoneManager for speaker-adaptive pitch normalization
        MicrophoneManager.shared.currentUserId = metadata.userId
        isSessionActive = true
        currentPhase = .preTest
    currentTrialIndex = 0
    loadPhraseForTrial()
}

    func completeTrial() {
        // Log the trial with enhanced metrics
        if let phrase = currentPhrase,
           let config = sessionConfig,
           let recordingURL = viewModel.recordedAudioURL {
            
            // Get audio file info
            var audioDuration: TimeInterval? = nil
            var audioSize: Int64? = nil
            
            // Get file size
            if let attributes = try? FileManager.default.attributesOfItem(atPath: recordingURL.path) {
                audioSize = attributes[.size] as? Int64
            }
            
            // Calculate actual audio duration from file
            do {
                let audioFile = try AVAudioFile(forReading: recordingURL)
                audioDuration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
            } catch {
                // Fallback: try using AVURLAsset (synchronous approach)
                let asset = AVURLAsset(url: recordingURL)
                let duration = asset.duration
                if CMTIME_IS_VALID(duration) && !CMTIME_IS_INDEFINITE(duration) {
                    audioDuration = CMTimeGetSeconds(duration)
                } else {
                    print("⚠️ Could not calculate audio duration: \(error.localizedDescription)")
                }
            }
            
            let trialDuration = trialStartTime.map { Date().timeIntervalSince($0) }
            
            // Get device model
            var systemInfo = utsname()
            uname(&systemInfo)
            let deviceModel = withUnsafePointer(to: &systemInfo.machine) {
                $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                    String(validatingUTF8: $0) ?? "Unknown"
                }
            } ?? "Unknown"
            
            // Get metrics from viewModel and sanitize for JSON encoding
            // Remove NaN and infinite values which cause encoding errors
            let metrics: [String: Double] = {
                guard let lastMetrics = viewModel.lastMetrics else {
                    return [:]
                }
                
                var sanitized: [String: Double] = [:]
                
                // Helper to sanitize a value
                func sanitize(_ value: Double) -> Double {
                    if value.isNaN || value.isInfinite {
                        return -1.0 // Use -1 to indicate invalid/missing
                    }
                    return value
                }
                
                sanitized["dtw_score"] = sanitize(lastMetrics.dtwScore)
                sanitized["rhythm_score"] = sanitize(lastMetrics.rhythmScore)
                sanitized["stress_score"] = sanitize(lastMetrics.stressScore)
                sanitized["lsr_score"] = sanitize(lastMetrics.lsrScore)
                sanitized["f0_rmse"] = sanitize(lastMetrics.f0RMSE)
                sanitized["gop_score"] = lastMetrics.gopScore.map(sanitize) ?? -1.0
                sanitized["final_score"] = sanitize(lastMetrics.finalScore)
                
                // Add quality metrics if available
                if let quality = viewModel.recordingQuality {
                    sanitized["quality_score"] = sanitize(quality.qualityScore)
                    sanitized["quality_rating"] = Double(quality.quality == .excellent ? 5 : quality.quality == .good ? 4 : quality.quality == .acceptable ? 3 : quality.quality == .poor ? 2 : 1)
                    sanitized["pitch_variation"] = sanitize(Double(quality.pitchVariation))
                    sanitized["avg_amplitude"] = sanitize(Double(quality.averageAmplitude))
                    sanitized["max_amplitude"] = sanitize(Double(quality.maxAmplitude))
                    if let snr = quality.signalToNoiseRatio {
                        sanitized["snr_estimate"] = sanitize(Double(snr))
                    }
                }
                
                return sanitized
            }()
            
            // Get mic permission state
            let micPermissionState: String? = {
                switch AVAudioSession.sharedInstance().recordPermission {
                case .granted:
                    return "granted"
                case .denied:
                    return "denied"
                case .undetermined:
                    return "undetermined"
                @unknown default:
                    return "unknown"
                }
            }()
            
            // Get playback rate
            let playbackRate = AudioPlayerManager.shared.playbackRate
            
            // Get quality information
            let qualityLabel = viewModel.recordingQuality?.quality.rawValue
            let qualityIssues = viewModel.recordingQuality?.issues
            let qualityRetryTriggered = viewModel.shouldRetryRecording
            let qualityRetryReason = viewModel.qualityAlertMessage
            
            // Determine trial result status
            let trialResultStatus: String? = {
                if viewModel.shouldRetryRecording {
                    return "retried"
                } else if qualityLabel == "invalid" || qualityLabel == "poor" {
                    // If quality is poor but we're not retrying, it was accepted anyway
                    return "accepted"
                } else {
                    return "accepted"
                }
            }()
            
            ExperimentManager.shared.logTrial(
                userId: config.userId,
                sessionUUID: config.sessionUUID,
                condition: currentCondition.rawValue,
                phase: currentPhase.rawValue,
                phraseId: phrase.id,
                trialIndex: currentTrialIndex,
                metrics: metrics,
                trialDuration: trialDuration,
                playbackAttempts: playbackAttempts,
                recordingAttempts: recordingAttempts,
                audioFileDuration: audioDuration,
                audioFileSize: audioSize,
                hapticIntensity: viewModel.hapticIntensity,
                deviceModel: deviceModel,
                playbackRate: playbackRate,
                micPermissionState: micPermissionState,
                qualityLabel: qualityLabel,
                qualityIssues: qualityIssues,
                qualityRetryTriggered: qualityRetryTriggered,
                qualityRetryReason: qualityRetryReason,
                trialResultStatus: trialResultStatus,
                playStartTime: playStartTime,
                recordStartTime: recordStartTime,
                recordStopTime: Date()
            )
            
            // Save recording
            _ = ExperimentManager.shared.saveRecording(
                sourceURL: recordingURL,
                userId: config.userId,
                condition: currentCondition.rawValue,
                phraseId: phrase.id
            )
        }
        
        // Skip post-trial questionnaires - collect all at the end
        proceedToNextTrial()
    }
    
    func proceedToNextTrial() {
        currentTrialIndex += 1
        
        // Check if phase is complete
        if currentTrialIndex >= totalTrialsInPhase {
            // Move to next phase
            switch currentPhase {
            case .preTest:
                currentPhase = .training
                currentTrialIndex = 0
            case .training:
                currentPhase = .postTest
                currentTrialIndex = 0
            case .postTest:
                // Show post-session questionnaire (includes all trial questions)
                showPostSessionQuestionnaire = true
                return
            case .practice:
                // Practice mode - not used in experiment sessions
                return
            }
        }
        
        // Update session config
        if var config = sessionConfig {
            config.currentPhase = currentPhase
            config.currentTrialIndex = currentTrialIndex
            sessionConfig = config
            ExperimentManager.shared.saveSessionConfig(config)
        }
        
        loadPhraseForTrial()
}

func loadPhraseForTrial() {
        viewModel.currentPhrase = currentPhrase
        updateViewModelState() // Ensure condition is updated when phrase changes
}
    
    func updateViewModelState() {
        viewModel.condition = currentCondition
        print("📱 Updated condition to: \(currentCondition) for phase: \(currentPhase.rawValue), trial: \(currentTrialIndex)")
    }
    
    func resetSession() {
        isSessionActive = false
        showCompletion = false
        currentTrialIndex = 0
        currentPhase = .preTest
        participantMetadata = nil
        sessionConfig = nil
        showMetadataForm = true
    }
    
    func findTopViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else {
            return nil
        }
        
        var topViewController = rootViewController
        while let presented = topViewController.presentedViewController {
            topViewController = presented
        }
        
        if let navController = topViewController as? UINavigationController {
            return navController.topViewController ?? navController
        }
        
        if let tabController = topViewController as? UITabBarController {
            if let selected = tabController.selectedViewController {
                return findTopViewController(from: selected)
            }
        }
        
        return topViewController
    }
    
    private func findTopViewController(from viewController: UIViewController) -> UIViewController {
        if let navController = viewController as? UINavigationController {
            return navController.topViewController ?? navController
        }
        if let tabController = viewController as? UITabBarController {
            if let selected = tabController.selectedViewController {
                return findTopViewController(from: selected)
            }
        }
        return viewController
    }
}
