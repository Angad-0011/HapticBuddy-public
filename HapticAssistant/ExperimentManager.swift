import Foundation
import UIKit
import Combine

struct TrialLog: Codable {
    let userId: String
    let sessionUUID: String // Unique session identifier for grouping trials
    let condition: String // "TextOnly", "AudioOnly", "HapticAudio", or "Practice"
    let phase: String // "PreTest", "Training", "PostTest"
    let phraseId: String
    let trialIndex: Int // Index within the phase
    /// A dictionary of recorded metrics for this trial.  Keys include:
    ///  - "dtw_score": similarity of pitch contour via dynamic time warping (0–100)
    ///  - "rhythm_score": correspondence of amplitude envelope to target rhythm (0–100)
    ///  - "stress_score": realization of stressed vs. unstressed syllables (0–100)
    ///  - "lsr_score": Lexical Stress Ratio (0–100)
    ///  - "f0_rmse": F0 Root Mean Square Error
    ///  - "gop_score": Goodness of Pronunciation (0–100, -1 if unavailable)
    ///  - "final_score": weighted aggregate of the above metrics (0–100)
    let metrics: [String: Double]
    
    // Enhanced logging fields
    let trialDuration: TimeInterval? // Time spent on this trial
    let playbackAttempts: Int // Number of times audio was played
    let recordingAttempts: Int // Number of recording attempts
    let audioFileDuration: TimeInterval? // Duration of recorded audio
    let audioFileSize: Int64? // Size of audio file in bytes
    let hapticIntensity: Float? // Haptic intensity setting used
    let deviceModel: String? // Device model for haptic variance tracking
    
    // Audio-haptic synchronization fields
    let playbackRate: Float? // Playback rate used for this trial
    let micPermissionState: String? // Microphone permission state ("granted", "denied", "undetermined")
    
    // Quality validation fields
    let qualityLabel: String? // Quality rating ("excellent", "good", "acceptable", "poor", "invalid")
    let qualityIssues: [String]? // List of quality issues found
    let qualityRetryTriggered: Bool? // Whether a quality retry was triggered
    let qualityRetryReason: String? // Reason code for quality retry
    
    // Trial result status
    let trialResultStatus: String? // "accepted", "retried", "skipped", "aborted"
    
    // Action timestamps
    let playStartTime: Date?
    let recordStartTime: Date?
    let recordStopTime: Date?
    let timestamp: Date // Overall trial timestamp
}

/// Subjective metrics collected from questionnaires
struct SubjectiveMetrics: Codable {
    let userId: String
    let trialIndex: Int?
    let phase: String?
    let confidenceRating: Int? // 1-5 Likert scale
    let hapticHelpfulness: Int? // 1-5 Likert scale (if applicable)
    let ueqResponses: [String: Int]? // UEQ questionnaire responses
    let openEndedFeedback: String?
    let timestamp: Date
}

class ExperimentManager: ObservableObject {
    static let shared = ExperimentManager()
    
    private let fileManager = FileManager.default
    private let logsFileName = "experiment_logs.json"
    private var isExporting = false // Flag to prevent multiple export calls
    
    @Published var logs: [TrialLog] = []
    @Published var participantMetadata: [String: ParticipantMetadata] = [:] // userId -> metadata
    @Published var subjectiveMetrics: [SubjectiveMetrics] = []
    @Published var sessionConfigs: [String: ExperimentSessionConfig] = [:] // userId -> config
    
    private let metadataFileName = "participant_metadata.json"
    private let subjectiveFileName = "subjective_metrics.json"
    private let configFileName = "session_configs.json"
    
    private init() {
        loadLogs()
        loadParticipantMetadata()
        loadSubjectiveMetrics()
        loadSessionConfigs()
    }
    
    // MARK: - Logging
    
    func logTrial(
        userId: String,
        sessionUUID: String,
        condition: String,
        phase: String,
        phraseId: String,
        trialIndex: Int,
        metrics: [String: Double],
        trialDuration: TimeInterval? = nil,
        playbackAttempts: Int = 0,
        recordingAttempts: Int = 0,
        audioFileDuration: TimeInterval? = nil,
        audioFileSize: Int64? = nil,
        hapticIntensity: Float? = nil,
        deviceModel: String? = nil,
        playbackRate: Float? = nil,
        micPermissionState: String? = nil,
        qualityLabel: String? = nil,
        qualityIssues: [String]? = nil,
        qualityRetryTriggered: Bool? = nil,
        qualityRetryReason: String? = nil,
        trialResultStatus: String? = nil,
        playStartTime: Date? = nil,
        recordStartTime: Date? = nil,
        recordStopTime: Date? = nil
    ) {
        let log = TrialLog(
            userId: userId,
            sessionUUID: sessionUUID,
            condition: condition,
            phase: phase,
            phraseId: phraseId,
            trialIndex: trialIndex,
            metrics: metrics,
            trialDuration: trialDuration,
            playbackAttempts: playbackAttempts,
            recordingAttempts: recordingAttempts,
            audioFileDuration: audioFileDuration,
            audioFileSize: audioFileSize,
            hapticIntensity: hapticIntensity,
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
            recordStopTime: recordStopTime,
            timestamp: Date()
        )
        logs.append(log)
        saveLogs()
    }
    
    // MARK: - Participant Metadata
    
    func saveParticipantMetadata(_ metadata: ParticipantMetadata) {
        participantMetadata[metadata.userId] = metadata
        saveParticipantMetadata()
    }
    
    func getParticipantMetadata(userId: String) -> ParticipantMetadata? {
        return participantMetadata[userId]
    }
    
    private func saveParticipantMetadata() {
        do {
            let data = try JSONEncoder().encode(participantMetadata)
            let url = getDocumentsDirectory().appendingPathComponent(metadataFileName)
            try data.write(to: url)
            print("Participant metadata saved successfully.")
        } catch {
            print("Failed to save participant metadata: \(error.localizedDescription)")
        }
    }
    
    private func loadParticipantMetadata() {
        let url = getDocumentsDirectory().appendingPathComponent(metadataFileName)
        guard fileManager.fileExists(atPath: url.path) else { return }
        
        do {
            let data = try Data(contentsOf: url)
            participantMetadata = try JSONDecoder().decode([String: ParticipantMetadata].self, from: data)
        } catch {
            print("Failed to load participant metadata: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Subjective Metrics
    
    func saveSubjectiveMetrics(_ metrics: SubjectiveMetrics) {
        subjectiveMetrics.append(metrics)
        saveSubjectiveMetrics()
    }
    
    private func saveSubjectiveMetrics() {
        do {
            let data = try JSONEncoder().encode(subjectiveMetrics)
            let url = getDocumentsDirectory().appendingPathComponent(subjectiveFileName)
            try data.write(to: url)
            print("Subjective metrics saved successfully.")
        } catch {
            print("Failed to save subjective metrics: \(error.localizedDescription)")
        }
    }
    
    private func loadSubjectiveMetrics() {
        let url = getDocumentsDirectory().appendingPathComponent(subjectiveFileName)
        guard fileManager.fileExists(atPath: url.path) else { return }
        
        do {
            let data = try Data(contentsOf: url)
            subjectiveMetrics = try JSONDecoder().decode([SubjectiveMetrics].self, from: data)
        } catch {
            print("Failed to load subjective metrics: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Session Configuration
    
    func saveSessionConfig(_ config: ExperimentSessionConfig) {
        sessionConfigs[config.userId] = config
        saveSessionConfigs()
    }
    
    func getSessionConfig(userId: String) -> ExperimentSessionConfig? {
        return sessionConfigs[userId]
    }
    
    private func saveSessionConfigs() {
        do {
            let data = try JSONEncoder().encode(sessionConfigs)
            let url = getDocumentsDirectory().appendingPathComponent(configFileName)
            try data.write(to: url)
            print("Session configs saved successfully.")
        } catch {
            print("Failed to save session configs: \(error.localizedDescription)")
        }
    }
    
    private func loadSessionConfigs() {
        let url = getDocumentsDirectory().appendingPathComponent(configFileName)
        guard fileManager.fileExists(atPath: url.path) else { return }
        
        do {
            let data = try Data(contentsOf: url)
            sessionConfigs = try JSONDecoder().decode([String: ExperimentSessionConfig].self, from: data)
        } catch {
            print("Failed to load session configs: \(error.localizedDescription)")
        }
    }
    
    private func getDocumentsDirectory() -> URL {
        return fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    private func getLogsURL() -> URL {
        return getDocumentsDirectory().appendingPathComponent(logsFileName)
    }
    
    private func saveLogs() {
        do {
            let data = try JSONEncoder().encode(logs)
            try data.write(to: getLogsURL())
            print("Logs saved successfully.")
        } catch {
            print("Failed to save logs: \(error.localizedDescription)")
        }
    }
    
    private func loadLogs() {
        let url = getLogsURL()
        guard fileManager.fileExists(atPath: url.path) else { return }
        
        do {
            let data = try Data(contentsOf: url)
            logs = try JSONDecoder().decode([TrialLog].self, from: data)
        } catch {
            print("Failed to load logs: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Audio Storage
    
    func saveRecording(sourceURL: URL, userId: String, condition: String, phraseId: String) -> URL? {
        let timestamp = Int(Date().timeIntervalSince1970)
        // Keep original extension (.m4a from AVAudioRecorder)
        let sourceExtension = sourceURL.pathExtension
        let fileName = "User_\(userId)_Condition_\(condition)_\(phraseId)_\(timestamp).\(sourceExtension)"
        let destinationURL = getDocumentsDirectory().appendingPathComponent(fileName)
        
        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            print("Recording saved to: \(destinationURL.lastPathComponent)")
            return destinationURL
        } catch {
            print("Failed to save recording: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Export
    
    /// Export format options
    enum ExportFormat {
        case json
        case csv
        case spss
        case all // All formats
    }
    
    /// Enhanced export with format selection
    func exportData(
        from viewController: UIViewController,
        userId: String? = nil,
        format: ExportFormat = .all
    ) {
        // Prevent multiple simultaneous export calls
        guard !isExporting else {
            print("Export already in progress. Please wait.")
            return
        }
        
        // Check if view controller is already presenting something
        if viewController.presentedViewController != nil {
            print("Cannot present export: Another view controller is already being presented.")
            return
        }
        
        isExporting = true
        
        // Generate export files based on format
        var itemsToShare: [Any] = []
        let exportManager = DataExportManager.shared
        
        // Filter logs and metadata
        let filteredLogs = userId != nil && !userId!.isEmpty
            ? logs.filter { $0.userId == userId! }
            : logs
        
        let filteredMetadata = userId != nil && !userId!.isEmpty
            ? [userId!: participantMetadata[userId!]].compactMapValues { $0 }
            : participantMetadata
        
        let filteredSubjective = userId != nil && !userId!.isEmpty
            ? subjectiveMetrics.filter { $0.userId == userId! }
            : subjectiveMetrics
        
        guard !filteredLogs.isEmpty else {
            print("No data to export\(userId != nil ? " for user: \(userId!)" : "").")
            isExporting = false
            return
        }
        
        // Generate export files
        let tempDir = fileManager.temporaryDirectory
        let timestamp = Int(Date().timeIntervalSince1970)
        let prefix = userId != nil ? "\(userId!)_" : "all_participants_"
        
        do {
            // Always include JSON (original format)
            if format == .json || format == .all {
                let jsonURL = tempDir.appendingPathComponent("\(prefix)experiment_logs_\(timestamp).json")
                            let data = try JSONEncoder().encode(filteredLogs)
                try data.write(to: jsonURL)
                itemsToShare.append(jsonURL)
            }
            
            // CSV exports
            if format == .csv || format == .all {
                // Trials CSV
                let trialsCSV = exportManager.exportTrialsToCSV(
                    logs: filteredLogs,
                    metadata: filteredMetadata,
                    subjectiveMetrics: filteredSubjective
                )
                let trialsCSVURL = tempDir.appendingPathComponent("\(prefix)trials_\(timestamp).csv")
                try trialsCSV.write(to: trialsCSVURL, atomically: true, encoding: .utf8)
                itemsToShare.append(trialsCSVURL)
                
                // Statistics CSV (participant-level)
                let allUserIds = Set(filteredLogs.map { $0.userId })
                var participantStats: [ParticipantStatistics] = []
                var improvementMetrics: [String: [ImprovementMetrics]] = [:]
                
                for uid in allUserIds {
                    let stats = exportManager.calculateParticipantStatistics(
                        userId: uid,
                        logs: filteredLogs
                    )
                    participantStats.append(stats)
                    if !stats.improvementMetrics.isEmpty {
                        improvementMetrics[uid] = stats.improvementMetrics
                    }
                }
                
                let statsCSV = exportManager.exportStatisticsToCSV(statistics: participantStats)
                let statsCSVURL = tempDir.appendingPathComponent("\(prefix)statistics_\(timestamp).csv")
                try statsCSV.write(to: statsCSVURL, atomically: true, encoding: .utf8)
                itemsToShare.append(statsCSVURL)
                
                // Improvement metrics CSV
                if !improvementMetrics.isEmpty {
                    let improvementCSV = exportManager.exportImprovementToCSV(improvements: improvementMetrics)
                    let improvementCSVURL = tempDir.appendingPathComponent("\(prefix)improvements_\(timestamp).csv")
                    try improvementCSV.write(to: improvementCSVURL, atomically: true, encoding: .utf8)
                    itemsToShare.append(improvementCSVURL)
                        }
                    }
                    
            // SPSS export
            if format == .spss || format == .all {
                let spssContent = exportManager.exportToSPSS(
                    logs: filteredLogs,
                    metadata: filteredMetadata
                )
                let spssURL = tempDir.appendingPathComponent("\(prefix)experiment_data_\(timestamp).sps")
                try spssContent.write(to: spssURL, atomically: true, encoding: .utf8)
                itemsToShare.append(spssURL)
                    }
                    
            // Add audio files
            let audioFiles = getAudioFiles(userId: userId)
            itemsToShare.append(contentsOf: audioFiles)
            
        } catch {
            print("Failed to create export files: \(error.localizedDescription)")
            isExporting = false
            return
        }
        
        guard !itemsToShare.isEmpty else {
            print("No data to export\(userId != nil ? " for user: \(userId!)" : "").")
            isExporting = false
            return
        }
        
        print("Preparing to export \(itemsToShare.count) item(s)\(userId != nil ? " for user: \(userId!)" : ""):")
        for item in itemsToShare.prefix(10) {
            if let url = item as? URL {
                print("  - \(url.lastPathComponent)")
            }
        }
        if itemsToShare.count > 10 {
            print("  ... and \(itemsToShare.count - 10) more files")
        }
        
        // Present on main thread
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            guard viewController.presentedViewController == nil else {
                print("Cannot present export: Another view controller is already being presented.")
                self.isExporting = false
                return
            }
            
            let activityVC = UIActivityViewController(activityItems: itemsToShare, applicationActivities: nil)
            
            activityVC.excludedActivityTypes = [
                .assignToContact,
                .addToReadingList,
                .openInIBooks
            ]
            
            if let popoverController = activityVC.popoverPresentationController {
                popoverController.sourceView = viewController.view
                popoverController.sourceRect = CGRect(x: viewController.view.bounds.midX, y: viewController.view.bounds.midY, width: 0, height: 0)
                popoverController.permittedArrowDirections = []
            }
            
            activityVC.completionWithItemsHandler = { _, _, _, _ in
                self.isExporting = false
            }
            
            viewController.present(activityVC, animated: true) {
                if viewController.presentedViewController != activityVC {
                    self.isExporting = false
                }
            }
        }
    }
    
    /// Legacy export method (maintains backward compatibility - exports JSON only)
    func exportData(from viewController: UIViewController, userId: String? = nil) {
        exportData(from: viewController, userId: userId, format: .json)
    }
    
    /// Get audio files for export
    private func getAudioFiles(userId: String?) -> [URL] {
        var audioFiles: [URL] = []
        
        do {
            let documentsURL = getDocumentsDirectory()
            let fileURLs = try fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: [.isReadableKey, .fileSizeKey])
            
            for fileURL in fileURLs {
                if fileURL.lastPathComponent.hasPrefix("User_") && (fileURL.pathExtension == "m4a" || fileURL.pathExtension == "caf") {
                    if let userId = userId, !userId.isEmpty {
                        let fileName = fileURL.lastPathComponent
                        if !fileName.hasPrefix("User_\(userId)_") {
                            continue
                        }
                    }
                    
                    guard fileManager.fileExists(atPath: fileURL.path),
                          fileManager.isReadableFile(atPath: fileURL.path) else {
                        continue
                    }
                    
                    if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                       fileSize ?? 0 > 0 {
                        audioFiles.append(fileURL)
                    }
                }
            }
        } catch {
            print("Error listing audio files: \(error.localizedDescription)")
        }
        
        return audioFiles
    }
    
    /// Batch export all participants' data
    func exportAllParticipants(from viewController: UIViewController, format: ExportFormat = .all) {
        exportData(from: viewController, userId: nil, format: format)
    }
    
    /// Get participant statistics for a specific user
    func getParticipantStatistics(userId: String) -> ParticipantStatistics? {
        let userLogs = logs.filter { $0.userId == userId }
        guard !userLogs.isEmpty else { return nil }
        
        return DataExportManager.shared.calculateParticipantStatistics(
            userId: userId,
            logs: userLogs
        )
    }
    
    /// Get all participant statistics
    func getAllParticipantStatistics() -> [ParticipantStatistics] {
        let allUserIds = Set(logs.map { $0.userId })
        return allUserIds.map { userId in
            DataExportManager.shared.calculateParticipantStatistics(
                userId: userId,
                logs: logs
            )
        }
    }
    
    /// Delete all data for a specific user
    func deleteUserData(userId: String) {
        // Remove logs
        logs.removeAll { $0.userId == userId }
        saveLogs()
        
        // Remove metadata
        participantMetadata.removeValue(forKey: userId)
        saveParticipantMetadata()
        
        // Remove subjective metrics
        subjectiveMetrics.removeAll { $0.userId == userId }
        saveSubjectiveMetrics()
        
        // Remove session configs
        sessionConfigs.removeValue(forKey: userId)
        saveSessionConfigs()
        
        // Delete audio files for this user
        do {
            let documentsURL = getDocumentsDirectory()
            let fileURLs = try fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
            
            for fileURL in fileURLs {
                // Support both .m4a (current) and .caf (legacy) formats
                let fileName = fileURL.lastPathComponent
                if fileName.hasPrefix("User_\(userId)_") && (fileURL.pathExtension == "m4a" || fileURL.pathExtension == "caf") {
                    try fileManager.removeItem(at: fileURL)
                    print("Deleted audio file: \(fileName)")
                }
            }
            print("✅ All data deleted for user: \(userId)")
        } catch {
            print("Error deleting audio files for user \(userId): \(error.localizedDescription)")
        }
    }
    
    func clearAllData() {
        logs.removeAll()
        saveLogs()
        
        // Delete audio files
        do {
            let documentsURL = getDocumentsDirectory()
            let fileURLs = try fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
            
            for fileURL in fileURLs {
                // Support both .m4a (current) and .caf (legacy) formats
                if fileURL.lastPathComponent.hasPrefix("User_") && (fileURL.pathExtension == "m4a" || fileURL.pathExtension == "caf") {
                    try fileManager.removeItem(at: fileURL)
                }
            }
            print("All experiment data cleared.")
        } catch {
            print("Error clearing data: \(error.localizedDescription)")
        }
    }
}
