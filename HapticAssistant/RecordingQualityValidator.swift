import Foundation
import AVFoundation
import Darwin

/// Quality assessment result for a recording
enum RecordingQuality: String {
    case excellent = "Excellent"
    case good = "Good"
    case acceptable = "Acceptable"
    case poor = "Poor"
    case invalid = "Invalid"
    
    var shouldRetry: Bool {
        return self == .poor || self == .invalid
    }
    
    var message: String {
        switch self {
        case .excellent:
            return "Recording quality is excellent"
        case .good:
            return "Recording quality is good"
        case .acceptable:
            return "Recording quality is acceptable"
        case .poor:
            return "Recording quality is poor. Please try again."
        case .invalid:
            return "Recording is invalid. Please record again."
        }
    }
}

/// Comprehensive quality metrics for a recording
struct RecordingQualityMetrics {
    let duration: TimeInterval
    let sampleCount: Int
    let validPitchSamples: Int
    let averageAmplitude: Float
    let maxAmplitude: Float
    let pitchVariation: Float
    let signalToNoiseRatio: Float?
    let audioFileSize: Int64?
    let audioFileDuration: TimeInterval?
    let hasValidAudioFile: Bool
    let qualityScore: Double // 0-100
    let quality: RecordingQuality
    
    /// Issues found in the recording
    let issues: [String]
    
    /// Recommendations for improvement
    let recommendations: [String]
}

/// Validator for recording quality and data integrity
class RecordingQualityValidator {
    static let shared = RecordingQualityValidator()
    
    // Quality thresholds
    private let minimumDuration: TimeInterval = 0.5 // Minimum 0.5 seconds
    private let minimumSamples = 2 // Minimum number of samples
    private let minimumValidPitchSamples = 2 // Minimum valid pitch samples
    private let minimumAmplitude: Float = 0.003 // Minimum average amplitude
    private let minimumMaxAmplitude: Float = 0.01 // Minimum peak amplitude
    private let minimumPitchVariation: Float = 0.001 // Minimum pitch variation
    private let minimumFileSize: Int64 = 1000 // Minimum file size in bytes (1KB)
    
    // Quality score thresholds
    private let excellentThreshold: Double = 85.0
    private let goodThreshold: Double = 70.0
    private let acceptableThreshold: Double = 50.0
    
    private init() {}
    
    /// Validate recording quality and return comprehensive metrics
    func validateRecording(
        duration: TimeInterval,
        pitchHistory: [Float],
        amplitudeHistory: [Float],
        audioFileURL: URL?,
        expectedPhraseDuration: TimeInterval? = nil
    ) -> RecordingQualityMetrics {
        var issues: [String] = []
        var recommendations: [String] = []
        var qualityScore: Double = 100.0
        
        // 1. Duration validation
        let durationScore = validateDuration(
            duration: duration,
            expectedDuration: expectedPhraseDuration,
            issues: &issues,
            recommendations: &recommendations
        )
        qualityScore = min(qualityScore, durationScore)
        
        // 2. Sample count validation
        let sampleCount = min(pitchHistory.count, amplitudeHistory.count)
        let sampleScore = validateSampleCount(
            sampleCount: sampleCount,
            issues: &issues,
            recommendations: &recommendations
        )
        qualityScore = min(qualityScore, sampleScore)
        
        // 3. Valid pitch samples
        let validPitchSamples = pitchHistory.filter { $0 >= 0 }.count
        let pitchScore = validatePitchSamples(
            validCount: validPitchSamples,
            totalCount: sampleCount,
            issues: &issues,
            recommendations: &recommendations
        )
        qualityScore = min(qualityScore, pitchScore)
        
        // 4. Amplitude validation
        let validAmplitudes = amplitudeHistory.filter { $0 > 0 }
        let avgAmplitude = validAmplitudes.isEmpty ? 0.0 : validAmplitudes.reduce(0, +) / Float(validAmplitudes.count)
        let maxAmplitude = validAmplitudes.max() ?? 0.0
        let amplitudeScore = validateAmplitude(
            average: avgAmplitude,
            max: maxAmplitude,
            issues: &issues,
            recommendations: &recommendations
        )
        qualityScore = min(qualityScore, amplitudeScore)
        
        // 5. Pitch variation validation
        let validPitch = pitchHistory.filter { $0 >= 0 }
        let pitchVariation = calculatePitchVariation(validPitch)
        let variationScore = validatePitchVariation(
            variation: pitchVariation,
            issues: &issues,
            recommendations: &recommendations
        )
        qualityScore = min(qualityScore, variationScore)
        
        // 6. Audio file integrity
        var audioFileSize: Int64? = nil
        var audioFileDuration: TimeInterval? = nil
        var hasValidAudioFile = false
        
        if let url = audioFileURL {
            let fileCheck = validateAudioFile(url: url)
            audioFileSize = fileCheck.fileSize
            audioFileDuration = fileCheck.duration
            hasValidAudioFile = fileCheck.isValid
            
            if !fileCheck.isValid {
                issues.append("Audio file is corrupted or invalid")
                recommendations.append("Please record again")
                qualityScore = min(qualityScore, 0)
            } else if let size = fileCheck.fileSize, size < minimumFileSize {
                issues.append("Audio file is too small (\(size) bytes)")
                recommendations.append("Recording may be incomplete. Please try again.")
                qualityScore = min(qualityScore, 30)
            }
        } else {
            issues.append("No audio file found")
            recommendations.append("Please record again")
            qualityScore = min(qualityScore, 0)
        }
        
        // 7. Signal-to-noise ratio estimation
        let snr = estimateSignalToNoiseRatio(amplitudeHistory: amplitudeHistory)
        
        // Determine overall quality
        let quality: RecordingQuality
        if qualityScore >= excellentThreshold {
            quality = .excellent
        } else if qualityScore >= goodThreshold {
            quality = .good
        } else if qualityScore >= acceptableThreshold {
            quality = .acceptable
        } else if qualityScore > 0 {
            quality = .poor
        } else {
            quality = .invalid
        }
        
        return RecordingQualityMetrics(
            duration: duration,
            sampleCount: sampleCount,
            validPitchSamples: validPitchSamples,
            averageAmplitude: avgAmplitude,
            maxAmplitude: maxAmplitude,
            pitchVariation: pitchVariation,
            signalToNoiseRatio: snr,
            audioFileSize: audioFileSize,
            audioFileDuration: audioFileDuration,
            hasValidAudioFile: hasValidAudioFile,
            qualityScore: qualityScore,
            quality: quality,
            issues: issues,
            recommendations: recommendations
        )
    }
    
    /// Check if a recording is suspicious (e.g., identical to previous recordings)
    func checkSuspiciousData(
        currentRecording: RecordingQualityMetrics,
        previousRecordings: [RecordingQualityMetrics]
    ) -> (isSuspicious: Bool, reason: String?) {
        guard !previousRecordings.isEmpty else {
            return (false, nil)
        }
        
        // Check for identical file sizes (might indicate same file)
        if let currentSize = currentRecording.audioFileSize {
            let identicalSizes = previousRecordings.filter { $0.audioFileSize == currentSize }
            if identicalSizes.count >= 2 {
                return (true, "Recording file size matches previous recordings - possible duplicate")
            }
        }
        
        // Check for identical durations (within 0.01s tolerance)
        let similarDurations = previousRecordings.filter {
            abs($0.duration - currentRecording.duration) < 0.01
        }
        if similarDurations.count >= 2 {
            return (true, "Recording duration is identical to previous recordings - possible duplicate")
        }
        
        // Check for identical quality scores (within 0.1 tolerance)
        let similarScores = previousRecordings.filter {
            abs($0.qualityScore - currentRecording.qualityScore) < 0.1
        }
        if similarScores.count >= 3 {
            return (true, "Multiple recordings have identical quality scores - possible issue")
        }
        
        return (false, nil)
    }
    
    // MARK: - Private Validation Methods
    
    private func validateDuration(
        duration: TimeInterval,
        expectedDuration: TimeInterval?,
        issues: inout [String],
        recommendations: inout [String]
    ) -> Double {
        var score: Double = 100.0
        
        if duration < minimumDuration {
            issues.append("Recording too short (\(String(format: "%.2f", duration))s)")
            recommendations.append("Please record the full phrase")
            return 0
        }
        
        // If we have expected duration, check if recording is reasonable
        if let expected = expectedDuration {
            let ratio = duration / expected
            if ratio < 0.3 {
                issues.append("Recording is much shorter than expected")
                recommendations.append("Please speak at a normal pace")
                score = 30
            } else if ratio > 3.0 {
                issues.append("Recording is much longer than expected")
                recommendations.append("Please speak at a normal pace")
                score = 50
            } else if ratio < 0.5 {
                score = 60
            } else if ratio > 2.0 {
                score = 70
            }
        }
        
        return score
    }
    
    private func validateSampleCount(
        sampleCount: Int,
        issues: inout [String],
        recommendations: inout [String]
    ) -> Double {
        if sampleCount < minimumSamples {
            issues.append("Too few samples collected (\(sampleCount))")
            recommendations.append("Please record again")
            return 0
        }
        
        if sampleCount < 5 {
            return 50
        } else if sampleCount < 10 {
            return 75
        }
        
        return 100
    }
    
    private func validatePitchSamples(
        validCount: Int,
        totalCount: Int,
        issues: inout [String],
        recommendations: inout [String]
    ) -> Double {
        if validCount < minimumValidPitchSamples {
            issues.append("No valid pitch detected (\(validCount) valid samples)")
            recommendations.append("Please speak clearly into the microphone")
            return 0
        }
        
        let validRatio = Float(validCount) / Float(max(totalCount, 1))
        // More lenient thresholds - allow lower valid pitch ratios
        if validRatio < 0.15 {
            issues.append("Too much silence in recording")
            recommendations.append("Please speak continuously")
            return 30
        } else if validRatio < 0.3 {
            return 50  // Acceptable if at least 30% valid
        } else if validRatio < 0.5 {
            return 70  // Good if at least 50% valid
        } else if validRatio < 0.7 {
            return 85  // Very good if at least 70% valid
        }
        
        return 100
    }
    
    private func validateAmplitude(
        average: Float,
        max: Float,
        issues: inout [String],
        recommendations: inout [String]
    ) -> Double {
        var score: Double = 100.0
        
        if average < minimumAmplitude {
            issues.append("Audio too quiet (average: \(String(format: "%.4f", average)))")
            recommendations.append("Please speak louder or move closer to the microphone")
            return 0
        }
        
        if max < minimumMaxAmplitude {
            issues.append("Peak amplitude too low")
            recommendations.append("Please speak louder")
            score = 40
        } else if average < minimumAmplitude * 2 {
            score = 60
        } else if average < minimumAmplitude * 5 {
            score = 80
        }
        
        return score
    }
    
    private func validatePitchVariation(
        variation: Float,
        issues: inout [String],
        recommendations: inout [String]
    ) -> Double {
        if variation < minimumPitchVariation {
            issues.append("No pitch variation detected (monotone or silence)")
            recommendations.append("Please speak with natural intonation")
            return 20
        }
        
        if variation < minimumPitchVariation * 2 {
            return 50
        } else if variation < minimumPitchVariation * 5 {
            return 75
        }
        
        return 100
    }
    
    private func validateAudioFile(url: URL) -> (isValid: Bool, fileSize: Int64?, duration: TimeInterval?) {
        let fileManager = FileManager.default
        
        // Check if file exists
        guard fileManager.fileExists(atPath: url.path) else {
            return (false, nil, nil)
        }
        
        // Get file size
        var fileSize: Int64? = nil
        if let attributes = try? fileManager.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? Int64 {
            fileSize = size
        }
        
        // Try to read audio file to verify integrity
        var duration: TimeInterval? = nil
        var isValid = false
        
        do {
            let audioFile = try AVAudioFile(forReading: url)
            duration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
            isValid = true
        } catch {
            print("⚠️ Audio file validation error: \(error.localizedDescription)")
            isValid = false
        }
        
        return (isValid, fileSize, duration)
    }
    
    private func calculatePitchVariation(_ pitchValues: [Float]) -> Float {
        guard pitchValues.count > 1 else { return 0 }
        
        let mean = pitchValues.reduce(0, +) / Float(pitchValues.count)
        let variance = pitchValues.map { pow($0 - mean, 2) }.reduce(0, +) / Float(pitchValues.count)
        return sqrt(variance)
    }
    
    private func estimateSignalToNoiseRatio(amplitudeHistory: [Float]) -> Float? {
        guard amplitudeHistory.count > 10 else { return nil }
        
        // Simple SNR estimation: compare peak to average
        let sorted = amplitudeHistory.sorted()
        let noiseFloor = sorted.prefix(sorted.count / 4).reduce(0, +) / Float(sorted.count / 4)
        let signalPeak = sorted.suffix(sorted.count / 4).reduce(0, +) / Float(sorted.count / 4)
        
        guard noiseFloor > 0 else { return nil }
        
        let snr = 20 * log10(Double(signalPeak / noiseFloor))
        return Float(snr)
    }
}

