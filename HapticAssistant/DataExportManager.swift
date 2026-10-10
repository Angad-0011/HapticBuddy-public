import Foundation

/// Statistics calculated for a set of trials
struct TrialStatistics: Codable {
    let mean: Double
    let standardDeviation: Double
    let min: Double
    let max: Double
    let median: Double
    let count: Int
}

/// Improvement metrics comparing pre-test vs post-test
struct ImprovementMetrics: Codable {
    let metricName: String
    let preTestMean: Double
    let postTestMean: Double
    let improvement: Double // postTest - preTest
    let improvementPercent: Double // (improvement / preTestMean) * 100
    let effectSize: Double? // Cohen's d if calculable
}

/// Participant-level aggregated statistics
struct ParticipantStatistics: Codable {
    let userId: String
    let totalTrials: Int
    let trialsByPhase: [String: Int] // Phase -> count
    let trialsByCondition: [String: Int] // Condition -> count
    let averageScores: [String: Double] // Metric name -> average
    let standardDeviations: [String: Double] // Metric name -> SD
    let improvementMetrics: [ImprovementMetrics] // Pre-test vs post-test comparisons
}

/// DataExportManager handles exporting experiment data in various formats
class DataExportManager {
    static let shared = DataExportManager()
    
    private init() {}
    
    // MARK: - CSV Export
    
    /// Export trial logs to CSV format with all metrics in columns
    func exportTrialsToCSV(logs: [TrialLog], metadata: [String: ParticipantMetadata], subjectiveMetrics: [SubjectiveMetrics]) -> String {
        var csv = ""
        
        // Header row
        let headers = [
            "userId",
            "sessionUUID",
            "condition",
            "phase",
            "phraseId",
            "trialIndex",
            "timestamp",
            "dtw_score",
            "rhythm_score",
            "stress_score",
            "lsr_score",
            "f0_rmse",
            "gop_score",
            "final_score",
            "trialDuration",
            "playbackAttempts",
            "recordingAttempts",
            "audioFileDuration",
            "audioFileSize",
            "hapticIntensity",
            "deviceModel",
            "playbackRate",
            "micPermissionState",
            "qualityLabel",
            "qualityIssues",
            "qualityRetryTriggered",
            "qualityRetryReason",
            "trialResultStatus",
            "playStartTime",
            "recordStartTime",
            "recordStopTime",
            // Participant metadata columns
            "age",
            "gender",
            "nativeLanguage",
            "englishProficiency",
            "yearsOfEnglishStudy",
            "previousPronunciationTraining",
            "iosVersion",
            // Subjective metrics (join on userId and trialIndex)
            "confidenceRating",
            "hapticHelpfulness"
        ]
        
        csv += headers.joined(separator: ",") + "\n"
        
        // Data rows
        for log in logs {
            let metadata = metadata[log.userId]
            
            // Find matching subjective metrics (if any)
            let subjective = subjectiveMetrics.first { metric in
                metric.userId == log.userId && metric.trialIndex == log.trialIndex
            }
            
            let row = [
                escapeCSV(log.userId),
                escapeCSV(log.sessionUUID),
                escapeCSV(log.condition),
                escapeCSV(log.phase),
                escapeCSV(log.phraseId),
                String(log.trialIndex),
                formatDate(log.timestamp),
                formatDouble(log.metrics["dtw_score"]),
                formatDouble(log.metrics["rhythm_score"]),
                formatDouble(log.metrics["stress_score"]),
                formatDouble(log.metrics["lsr_score"]),
                formatDouble(log.metrics["f0_rmse"]),
                formatDouble(log.metrics["gop_score"]),
                formatDouble(log.metrics["final_score"]),
                formatDouble(log.trialDuration),
                String(log.playbackAttempts),
                String(log.recordingAttempts),
                formatDouble(log.audioFileDuration),
                formatInt64(log.audioFileSize),
                formatFloat(log.hapticIntensity),
                escapeCSV(log.deviceModel ?? ""),
                formatFloat(log.playbackRate),
                escapeCSV(log.micPermissionState ?? ""),
                escapeCSV(log.qualityLabel ?? ""),
                escapeCSV(log.qualityIssues?.joined(separator: "; ") ?? ""),
                formatBool(log.qualityRetryTriggered),
                escapeCSV(log.qualityRetryReason ?? ""),
                escapeCSV(log.trialResultStatus ?? ""),
                formatDate(log.playStartTime),
                formatDate(log.recordStartTime),
                formatDate(log.recordStopTime),
                // Metadata
                formatInt(metadata?.age),
                escapeCSV(metadata?.gender ?? ""),
                escapeCSV(metadata?.nativeLanguage ?? ""),
                escapeCSV(metadata?.englishProficiency.rawValue ?? ""),
                formatInt(metadata?.yearsOfEnglishStudy),
                formatBool(metadata?.previousPronunciationTraining),
                escapeCSV(metadata?.iosVersion ?? ""),
                // Subjective metrics
                formatInt(subjective?.confidenceRating),
                formatInt(subjective?.hapticHelpfulness)
            ]
            
            csv += row.joined(separator: ",") + "\n"
        }
        
        return csv
    }
    
    /// Export participant-level statistics to CSV
    func exportStatisticsToCSV(statistics: [ParticipantStatistics]) -> String {
        var csv = ""
        
        // Header row
        let headers = [
            "userId",
            "totalTrials",
            "preTestTrials",
            "trainingTrials",
            "postTestTrials",
            "audioOnlyTrials",
            "hapticAudioTrials",
            "avg_dtw_score",
            "avg_rhythm_score",
            "avg_stress_score",
            "avg_lsr_score",
            "avg_f0_rmse",
            "avg_gop_score",
            "avg_final_score",
            "sd_dtw_score",
            "sd_rhythm_score",
            "sd_stress_score",
            "sd_lsr_score",
            "sd_f0_rmse",
            "sd_gop_score",
            "sd_final_score"
        ]
        
        csv += headers.joined(separator: ",") + "\n"
        
        // Data rows
        for stat in statistics {
            let row = [
                escapeCSV(stat.userId),
                String(stat.totalTrials),
                String(stat.trialsByPhase["PreTest"] ?? 0),
                String(stat.trialsByPhase["Training"] ?? 0),
                String(stat.trialsByPhase["PostTest"] ?? 0),
                String(stat.trialsByCondition["AudioOnly"] ?? 0),
                String(stat.trialsByCondition["HapticAudio"] ?? 0),
                formatDouble(stat.averageScores["dtw_score"]),
                formatDouble(stat.averageScores["rhythm_score"]),
                formatDouble(stat.averageScores["stress_score"]),
                formatDouble(stat.averageScores["lsr_score"]),
                formatDouble(stat.averageScores["f0_rmse"]),
                formatDouble(stat.averageScores["gop_score"]),
                formatDouble(stat.averageScores["final_score"]),
                formatDouble(stat.standardDeviations["dtw_score"]),
                formatDouble(stat.standardDeviations["rhythm_score"]),
                formatDouble(stat.standardDeviations["stress_score"]),
                formatDouble(stat.standardDeviations["lsr_score"]),
                formatDouble(stat.standardDeviations["f0_rmse"]),
                formatDouble(stat.standardDeviations["gop_score"]),
                formatDouble(stat.standardDeviations["final_score"])
            ]
            
            csv += row.joined(separator: ",") + "\n"
        }
        
        return csv
    }
    
    /// Export improvement metrics to CSV
    func exportImprovementToCSV(improvements: [String: [ImprovementMetrics]]) -> String {
        var csv = ""
        
        // Header row
        let headers = [
            "userId",
            "metricName",
            "preTestMean",
            "postTestMean",
            "improvement",
            "improvementPercent",
            "effectSize"
        ]
        
        csv += headers.joined(separator: ",") + "\n"
        
        // Data rows
        for (userId, metrics) in improvements {
            for metric in metrics {
                let row = [
                    escapeCSV(userId),
                    escapeCSV(metric.metricName),
                    formatDouble(metric.preTestMean),
                    formatDouble(metric.postTestMean),
                    formatDouble(metric.improvement),
                    formatDouble(metric.improvementPercent),
                    formatDouble(metric.effectSize)
                ]
                
                csv += row.joined(separator: ",") + "\n"
            }
        }
        
        return csv
    }
    
    // MARK: - Statistics Calculation
    
    /// Calculate statistics for a set of metric values
    func calculateStatistics(values: [Double]) -> TrialStatistics {
        guard !values.isEmpty else {
            return TrialStatistics(mean: 0, standardDeviation: 0, min: 0, max: 0, median: 0, count: 0)
        }
        
        let validValues = values.filter { !$0.isNaN && !$0.isInfinite && $0 != -1.0 }
        guard !validValues.isEmpty else {
            return TrialStatistics(mean: 0, standardDeviation: 0, min: 0, max: 0, median: 0, count: 0)
        }
        
        let sorted = validValues.sorted()
        let count = validValues.count
        let sum = validValues.reduce(0, +)
        let mean = sum / Double(count)
        
        // Standard deviation
        let variance = validValues.map { pow($0 - mean, 2) }.reduce(0, +) / Double(count)
        let sd = sqrt(variance)
        
        // Min, max, median
        let min = sorted.first ?? 0
        let max = sorted.last ?? 0
        let median = count % 2 == 0
            ? (sorted[count/2 - 1] + sorted[count/2]) / 2.0
            : sorted[count/2]
        
        return TrialStatistics(
            mean: mean,
            standardDeviation: sd,
            min: min,
            max: max,
            median: median,
            count: count
        )
    }
    
    /// Calculate participant-level statistics
    func calculateParticipantStatistics(
        userId: String,
        logs: [TrialLog]
    ) -> ParticipantStatistics {
        let userLogs = logs.filter { $0.userId == userId }
        
        // Count by phase and condition
        var trialsByPhase: [String: Int] = [:]
        var trialsByCondition: [String: Int] = [:]
        
        for log in userLogs {
            trialsByPhase[log.phase, default: 0] += 1
            trialsByCondition[log.condition, default: 0] += 1
        }
        
        // Calculate averages and SDs for each metric
        let metricNames = ["dtw_score", "rhythm_score", "stress_score", "lsr_score", "f0_rmse", "gop_score", "final_score"]
        var averageScores: [String: Double] = [:]
        var standardDeviations: [String: Double] = [:]
        
        for metricName in metricNames {
            let values = userLogs.compactMap { log -> Double? in
                let value = log.metrics[metricName]
                // Filter out invalid values
                if let val = value, !val.isNaN && !val.isInfinite && val != -1.0 {
                    return val
                }
                return nil
            }
            
            let stats = calculateStatistics(values: values)
            averageScores[metricName] = stats.mean
            standardDeviations[metricName] = stats.standardDeviation
        }
        
        // Calculate improvement metrics (pre-test vs post-test)
        let preTestLogs = userLogs.filter { $0.phase == "PreTest" }
        let postTestLogs = userLogs.filter { $0.phase == "PostTest" }
        
        var improvementMetrics: [ImprovementMetrics] = []
        
        if !preTestLogs.isEmpty && !postTestLogs.isEmpty {
            for metricName in metricNames {
                let preTestValues = preTestLogs.compactMap { log -> Double? in
                    let value = log.metrics[metricName]
                    if let val = value, !val.isNaN && !val.isInfinite && val != -1.0 {
                        return val
                    }
                    return nil
                }
                
                let postTestValues = postTestLogs.compactMap { log -> Double? in
                    let value = log.metrics[metricName]
                    if let val = value, !val.isNaN && !val.isInfinite && val != -1.0 {
                        return val
                    }
                    return nil
                }
                
                if !preTestValues.isEmpty && !postTestValues.isEmpty {
                    let preTestMean = preTestValues.reduce(0, +) / Double(preTestValues.count)
                    let postTestMean = postTestValues.reduce(0, +) / Double(postTestValues.count)
                    let improvement = postTestMean - preTestMean
                    let improvementPercent = preTestMean != 0 ? (improvement / preTestMean) * 100 : 0
                    
                    // Calculate Cohen's d (effect size)
                    let preTestSD = calculateStatistics(values: preTestValues).standardDeviation
                    let postTestSD = calculateStatistics(values: postTestValues).standardDeviation
                    let pooledSD = sqrt((pow(preTestSD, 2) + pow(postTestSD, 2)) / 2.0)
                    let effectSize = pooledSD != 0 ? improvement / pooledSD : nil
                    
                    improvementMetrics.append(ImprovementMetrics(
                        metricName: metricName,
                        preTestMean: preTestMean,
                        postTestMean: postTestMean,
                        improvement: improvement,
                        improvementPercent: improvementPercent,
                        effectSize: effectSize
                    ))
                }
            }
        }
        
        return ParticipantStatistics(
            userId: userId,
            totalTrials: userLogs.count,
            trialsByPhase: trialsByPhase,
            trialsByCondition: trialsByCondition,
            averageScores: averageScores,
            standardDeviations: standardDeviations,
            improvementMetrics: improvementMetrics
        )
    }
    
    // MARK: - SPSS-Compatible Export
    
    /// Export data in SPSS-compatible format (tab-delimited with variable labels)
    func exportToSPSS(logs: [TrialLog], metadata: [String: ParticipantMetadata]) -> String {
        var spss = ""
        
        // Variable labels (SPSS format)
        spss += "* Variable Labels.\n"
        spss += "USERID \"Participant User ID\"\n"
        spss += "CONDITION \"Experimental Condition\"\n"
        spss += "PHASE \"Experiment Phase\"\n"
        spss += "PHRASEID \"Phrase Identifier\"\n"
        spss += "TRIALINDEX \"Trial Index\"\n"
        spss += "DTW_SCORE \"Dynamic Time Warping Score (0-100)\"\n"
        spss += "RHYTHM_SCORE \"Rhythm Score (0-100)\"\n"
        spss += "STRESS_SCORE \"Stress Score (0-100)\"\n"
        spss += "LSR_SCORE \"Lexical Stress Ratio (0-100)\"\n"
        spss += "F0_RMSE \"F0 Root Mean Square Error\"\n"
        spss += "GOP_SCORE \"Goodness of Pronunciation (0-100)\"\n"
        spss += "FINAL_SCORE \"Final Aggregate Score (0-100)\"\n"
        spss += "TRIALDUR \"Trial Duration (seconds)\"\n"
        spss += "PLAYBACK_ATTEMPTS \"Number of Playback Attempts\"\n"
        spss += "RECORDING_ATTEMPTS \"Number of Recording Attempts\"\n"
        spss += "AUDIO_DUR \"Audio File Duration (seconds)\"\n"
        spss += "AUDIO_SIZE \"Audio File Size (bytes)\"\n"
        spss += "HAPTIC_INTENSITY \"Haptic Intensity Setting\"\n"
        spss += "DEVICE_MODEL \"Device Model\"\n"
        spss += ".\n\n"
        
        // Value labels for categorical variables
        spss += "* Value Labels.\n"
        spss += "/CONDITION \"AudioOnly\" \"Audio Only\" \"HapticAudio\" \"Haptic + Audio\" \"TextOnly\" \"Text Only\" \"Practice\" \"Practice Mode\".\n"
        spss += "/PHASE \"PreTest\" \"Pre-Test\" \"Training\" \"Training Phase\" \"PostTest\" \"Post-Test\".\n"
        spss += ".\n\n"
        
        // Data (tab-delimited)
        spss += "* Data.\n"
        
        // Header row
        let headers = [
            "USERID", "CONDITION", "PHASE", "PHRASEID", "TRIALINDEX",
            "DTW_SCORE", "RHYTHM_SCORE", "STRESS_SCORE", "LSR_SCORE",
            "F0_RMSE", "GOP_SCORE", "FINAL_SCORE",
            "TRIALDUR", "PLAYBACK_ATTEMPTS", "RECORDING_ATTEMPTS",
            "AUDIO_DUR", "AUDIO_SIZE", "HAPTIC_INTENSITY", "DEVICE_MODEL"
        ]
        spss += headers.joined(separator: "\t") + "\n"
        
        // Data rows (tab-delimited)
        for log in logs {
            let row = [
                log.userId,
                log.condition,
                log.phase,
                log.phraseId,
                String(log.trialIndex),
                formatDoubleForSPSS(log.metrics["dtw_score"]),
                formatDoubleForSPSS(log.metrics["rhythm_score"]),
                formatDoubleForSPSS(log.metrics["stress_score"]),
                formatDoubleForSPSS(log.metrics["lsr_score"]),
                formatDoubleForSPSS(log.metrics["f0_rmse"]),
                formatDoubleForSPSS(log.metrics["gop_score"]),
                formatDoubleForSPSS(log.metrics["final_score"]),
                formatDoubleForSPSS(log.trialDuration),
                String(log.playbackAttempts),
                String(log.recordingAttempts),
                formatDoubleForSPSS(log.audioFileDuration),
                formatInt64ForSPSS(log.audioFileSize),
                formatFloatForSPSS(log.hapticIntensity),
                log.deviceModel ?? ""
            ]
            
            spss += row.joined(separator: "\t") + "\n"
        }
        
        return spss
    }
    
    // MARK: - Helper Functions
    
    private func escapeCSV(_ value: String) -> String {
        // If value contains comma, quote, or newline, wrap in quotes and escape quotes
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
    
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }
    
    private func formatDouble(_ value: Double?) -> String {
        guard let value = value else { return "" }
        if value.isNaN || value.isInfinite || value == -1.0 {
            return ""
        }
        return String(format: "%.4f", value)
    }
    
    private func formatDoubleForSPSS(_ value: Double?) -> String {
        guard let value = value else { return "." } // SPSS uses . for missing
        if value.isNaN || value.isInfinite || value == -1.0 {
            return "."
        }
        return String(format: "%.4f", value)
    }
    
    private func formatFloat(_ value: Float?) -> String {
        guard let value = value else { return "" }
        return String(format: "%.2f", value)
    }
    
    private func formatFloatForSPSS(_ value: Float?) -> String {
        guard let value = value else { return "." }
        return String(format: "%.2f", value)
    }
    
    private func formatInt(_ value: Int?) -> String {
        guard let value = value else { return "" }
        return String(value)
    }
    
    private func formatInt64(_ value: Int64?) -> String {
        guard let value = value else { return "" }
        return String(value)
    }
    
    private func formatInt64ForSPSS(_ value: Int64?) -> String {
        guard let value = value else { return "." }
        return String(value)
    }
    
    private func formatBool(_ value: Bool?) -> String {
        guard let value = value else { return "" }
        return value ? "1" : "0"
    }
}

