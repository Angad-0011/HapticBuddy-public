import Foundation
import Speech
import AVFoundation

/// Detailed scoring metrics for pronunciation analysis
struct PronunciationMetrics {
    let finalScore: Double
    let dtwScore: Double
    let rhythmScore: Double
    let stressScore: Double
    
    // Enhanced metrics
    let gopScore: Double? // Goodness of Pronunciation (ASR-based, optional if ASR fails)
    let lsrScore: Double // Lexical Stress Ratio
    let f0RMSE: Double // F0 Root Mean Square Error
    
    /// Human-readable feedback based on scores
    var feedback: String {
        // Check if this is a zero score (likely invalid recording)
        if finalScore == 0 && dtwScore == 0 && rhythmScore == 0 && stressScore == 0 {
            return "Recording too short or silent. Please try again."
        }
        
        if finalScore >= 90 {
            return "Excellent pronunciation!"
        } else if finalScore >= 70 {
            return "Great job! Minor improvements needed."
        } else if finalScore >= 50 {
            return "Good effort. Focus on intonation and stress."
        } else if finalScore > 0 {
            return "Keep practicing. Pay attention to pitch patterns."
        } else {
            return "Recording too short or silent. Please try again."
        }
    }
    
    /// Generate actionable "what to fix next" feedback based on specific metrics and phrase
    /// - Parameter phrase: The phrase that was practiced
    /// - Returns: Specific actionable feedback, or nil if no specific issue
    func actionableFeedback(for phrase: Phrase) -> String? {
        // Check if this is a zero score (likely invalid recording)
        if finalScore == 0 && dtwScore == 0 && rhythmScore == 0 && stressScore == 0 {
            return nil
        }
        
        // Find the lowest scoring component to focus on
        var issues: [(score: Double, message: String)] = []
        
        // Intonation issues
        if dtwScore < 60 {
            switch phrase.intonationType {
            case .rising:
                issues.append((dtwScore, "Your ending pitch fell; try a rising tail."))
            case .falling:
                issues.append((dtwScore, "Your ending pitch rose; try a falling tail."))
            case .flat:
                issues.append((dtwScore, "Your pitch varied too much; keep it steady."))
            }
        }
        
        // Stress issues
        if stressScore < 60 {
            issues.append((stressScore, "Stressed syllables need more emphasis. Make them louder and longer."))
        }
        
        // Rhythm issues
        if rhythmScore < 60 {
            issues.append((rhythmScore, "Match the rhythm pattern. Pay attention to syllable timing."))
        }
        
        // LSR (Lexical Stress Ratio) issues
        if lsrScore < 60 {
            issues.append((lsrScore, "Increase contrast between stressed and unstressed syllables."))
        }
        
        // F0 RMSE issues (pitch accuracy)
        if f0RMSE > 0.5 && !f0RMSE.isInfinite {
            switch phrase.intonationType {
            case .rising:
                issues.append((100 - f0RMSE * 50, "Your pitch contour doesn't match the rising pattern."))
            case .falling:
                issues.append((100 - f0RMSE * 50, "Your pitch contour doesn't match the falling pattern."))
            case .flat:
                issues.append((100 - f0RMSE * 50, "Your pitch should stay more level."))
            }
        }
        
        // Return the most critical issue (lowest score)
        if let worstIssue = issues.min(by: { $0.score < $1.score }) {
            return worstIssue.message
        }
        
        // If all scores are good but not perfect, give general encouragement
        if finalScore >= 70 && finalScore < 90 {
            return "You're doing well! Focus on making the intonation pattern clearer."
        }
        
        return nil
    }
    
    /// Detailed breakdown for display
    var breakdown: ScoreBreakdown {
        return ScoreBreakdown(
            intonation: Int(dtwScore.rounded()),
            rhythm: Int(rhythmScore.rounded()),
            stress: Int(stressScore.rounded()),
            overall: Int(finalScore.rounded()),
            gop: gopScore != nil ? Int(gopScore!.rounded()) : nil,
            lsr: Int(lsrScore.rounded()),
            f0RMSE: f0RMSE
        )
    }
}

/// Score breakdown for UI display
struct ScoreBreakdown {
    let intonation: Int
    let rhythm: Int
    let stress: Int
    let overall: Int
    let gop: Int? // Goodness of Pronunciation (optional)
    let lsr: Int // Lexical Stress Ratio
    let f0RMSE: Double // F0 Root Mean Square Error (raw value, not percentage)
}

/// Engine for calculating pronunciation scores
class ScoringEngine {
    
    /// Computes detailed metrics for a user's recording compared against the target intonation for a phrase.
    ///
    /// - Parameters:
    ///   - phrase: The phrase whose target intonation, stress and rhythm patterns define the goal.
    ///   - pitchHistory: The normalized pitch values collected during recording (0.0–1.0, with -1.0 indicating silence).
    ///   - amplitudeHistory: The normalized RMS amplitude values collected during recording (0.0–1.0).
    ///   - rawPitchHistory: Optional raw pitch values in Hz (for speaker-adaptive normalization using semitones).
    ///   - userId: Optional user ID for speaker-adaptive pitch normalization.
    /// - Returns: PronunciationMetrics containing all scores and feedback
    func calculateMetrics(for phrase: Phrase,
                          pitchHistory: [Float],
                          amplitudeHistory: [Float],
                          rawPitchHistory: [Float]? = nil,
                          userId: String? = nil) -> PronunciationMetrics {
        // 1. Zip pitch and amplitude to keep them synchronized
        let count = min(pitchHistory.count, amplitudeHistory.count)
        guard count > 0 else {
            print("⚠️ Scoring: Empty recording - no data collected")
            return PronunciationMetrics(
                finalScore: 0,
                dtwScore: 0,
                rhythmScore: 0,
                stressScore: 0,
                gopScore: nil,
                lsrScore: 0,
                f0RMSE: Double.infinity
            )
        }
        
        // 2. Validate minimum recording length
        // NOTE: Validation thresholds match RecordingQualityValidator for consistency
        // This ensures practice mode and experiment mode use the same quality standards
        let minimumSamples = 2 // Match RecordingQualityValidator.minimumSamples
        guard count >= minimumSamples else {
            print("⚠️ Scoring: Recording too short - only \(count) samples (expected at least \(minimumSamples))")
            return PronunciationMetrics(
                finalScore: 0,
                dtwScore: 0,
                rhythmScore: 0,
                stressScore: 0,
                gopScore: nil,
                lsrScore: 0,
                f0RMSE: Double.infinity
            )
        }
        
        var validPitch: [Float] = []
        var validAmp: [Float] = []
        
        for i in 0..<count {
            let p = pitchHistory[i]
            let a = amplitudeHistory[i]
            // Filter out silence/invalid pitch (marked as -1.0)
            if p >= 0 {
                validPitch.append(p)
                validAmp.append(a)
            }
        }
        
        // 3. Validate that we have actual audio (not just silence)
        guard !validPitch.isEmpty else {
            print("⚠️ Scoring: No valid pitch data - recording appears to be silence")
            return PronunciationMetrics(
                finalScore: 0,
                dtwScore: 0,
                rhythmScore: 0,
                stressScore: 0,
                gopScore: nil,
                lsrScore: 0,
                f0RMSE: Double.infinity
            )
        }
        
        // 4. Validate minimum number of valid samples
        guard validPitch.count >= minimumSamples else {
            print("⚠️ Scoring: Too few valid samples - only \(validPitch.count) valid samples (expected at least \(minimumSamples))")
            return PronunciationMetrics(
                finalScore: 0,
                dtwScore: 0,
                rhythmScore: 0,
                stressScore: 0,
                gopScore: nil,
                lsrScore: 0,
                f0RMSE: Double.infinity
            )
        }
        
        // 5. Validate that there's actual audio signal (not just noise floor)
        // Use same threshold as RecordingQualityValidator for consistency
        let avgAmplitude = validAmp.reduce(0, +) / Float(validAmp.count)
        let minimumAmplitude: Float = 0.003 // Match RecordingQualityValidator.minimumAmplitude
        guard avgAmplitude >= minimumAmplitude else {
            print("⚠️ Scoring: Audio too quiet - average amplitude \(avgAmplitude) (minimum \(minimumAmplitude))")
            return PronunciationMetrics(
                finalScore: 0,
                dtwScore: 0,
                rhythmScore: 0,
                stressScore: 0,
                gopScore: nil,
                lsrScore: 0,
                f0RMSE: Double.infinity
            )
        }
        
        // 6. Validate pitch variation (silence/noise has no pitch variation)
        // Use same threshold as RecordingQualityValidator for consistency
        let pitchVariance = calculateVariance(validPitch)
        let minimumPitchVariance: Float = 0.001 // Match RecordingQualityValidator.minimumPitchVariation
        guard pitchVariance >= minimumPitchVariance else {
            print("⚠️ Scoring: No pitch variation detected - variance \(pitchVariance) (likely silence or noise)")
            return PronunciationMetrics(
                finalScore: 0,
                dtwScore: 0,
                rhythmScore: 0,
                stressScore: 0,
                gopScore: nil,
                lsrScore: 0,
                f0RMSE: Double.infinity
            )
        }
        
        print("✓ Scoring: Valid recording - \(validPitch.count) samples, avg amplitude: \(String(format: "%.3f", avgAmplitude)), pitch variance: \(String(format: "%.6f", pitchVariance))")
        
        // Use speaker-adaptive pitch normalization if raw pitch data is available
        let userNormalizedPitch: [Float]
        let f0RMSE: Double
        
        if let rawPitch = rawPitchHistory, let userId = userId, !rawPitch.isEmpty {
            // Filter raw pitch to match valid pitch indices
            var validRawPitch: [Float] = []
            var rawIndex = 0
            for i in 0..<count {
                if pitchHistory[i] >= 0 {
                    if rawIndex < rawPitch.count && rawPitch[rawIndex] > 0 {
                        validRawPitch.append(rawPitch[rawIndex])
                    }
                    rawIndex += 1
                } else {
                    rawIndex += 1
                }
            }
            
            // Calculate median F0 for semitones-based normalization
            let medianF0 = calculateMedian(validRawPitch.filter { $0 > 0 })
            
            if medianF0 > 0 && validRawPitch.count == validPitch.count {
                // Use semitones-based normalization (more speaker-robust)
                userNormalizedPitch = validRawPitch.map { pitchHz in
                    SpeakerAdaptivePitchNormalizer.shared.normalizePitchSemitones(
                        pitchHz: pitchHz,
                        relativeTo: medianF0
                    )
                }
                
                // Calculate F0 RMSE using semitones
                let targetPitch = generateTargetPitch(for: phrase, length: validPitch.count)
                let targetSemitones = targetPitch.map { t in
                    // Convert target (0-1) to semitones relative to median
                    let targetHz = medianF0 * pow(2.0, (Float(t) - 0.5) * 6.0 / 12.0) // ±3 semitones range
                    return targetHz
                }
                f0RMSE = calculateF0RMSE(userPitch: validRawPitch, targetPitch: targetSemitones)
            } else {
                // Fallback to z-score normalization
                userNormalizedPitch = normalize(validPitch)
                f0RMSE = calculateF0RMSE(userPitch: validPitch, targetPitch: generateTargetPitch(for: phrase, length: validPitch.count))
            }
        } else {
            // Use standard z-score normalization
            userNormalizedPitch = normalize(validPitch)
            f0RMSE = calculateF0RMSE(userPitch: validPitch, targetPitch: generateTargetPitch(for: phrase, length: validPitch.count))
        }
        
        // Normalize amplitude via z-score
        let userNormalizedAmp = normalize(validAmp)
        
        // 1. Target pitch contour
        let targetPitch = generateTargetPitch(for: phrase, length: validPitch.count)
        let targetNormalizedPitch = normalize(targetPitch)
        
        // 2. DTW-based pitch similarity score
        let dtwScore = calculateDTWScore(userPitch: userNormalizedPitch, targetPitch: targetNormalizedPitch)
        
        // 4. Rhythm score via correlation of amplitude envelopes
        let rhythmScore = calculateRhythmScore(for: phrase, userAmplitude: userNormalizedAmp)
        
        // 5. Enhanced Stress score with LSR (Lexical Stress Ratio)
        let (stressScore, lsrScore) = calculateEnhancedStressScore(
            for: phrase,
            userPitch: userNormalizedPitch,
            userAmplitude: userNormalizedAmp,
            rawPitch: validPitch,
            rawAmplitude: validAmp
        )
        
        // 6. ASR-based Goodness of Pronunciation (GOP) - will be calculated separately
        // Note: GOP requires audio file, so it's calculated asynchronously
        let gopScore: Double? = nil // Will be set by caller if available
        
        // 7. Combine metrics into final score using configurable weights
        let weights = ScoringWeightsManager.shared.getWeights()
        var finalScore = (weights.dtwWeight * dtwScore) +
                        (weights.rhythmWeight * rhythmScore) +
                        (weights.stressWeight * stressScore) +
                        (weights.lsrWeight * lsrScore)
        
        // Note: GOP weight is applied later if GOP score is available
        
        return PronunciationMetrics(
            finalScore: finalScore,
            dtwScore: dtwScore,
            rhythmScore: rhythmScore,
            stressScore: stressScore,
            gopScore: gopScore,
            lsrScore: lsrScore,
            f0RMSE: f0RMSE
        )
    }
    
    // MARK: - Private Helper Methods
    
    private func calculateDTWScore(userPitch: [Float], targetPitch: [Float]) -> Double {
        let dtwDist = dtwDistance(s1: userPitch, s2: targetPitch)
        let normFactor = Double(userPitch.count + targetPitch.count)
        let normalizedDTW = dtwDist / max(normFactor, 1.0)
        // Tunable alpha: controls steepness of exponential decay
        let alpha = 3.0
        var score = 100.0 * exp(-alpha * normalizedDTW)
        return max(0.0, min(100.0, score))
    }
    
    private func calculateRhythmScore(for phrase: Phrase, userAmplitude: [Float]) -> Double {
        var targetAmp: [Float] = []
        let syllableCount = phrase.syllableDurations.count
        let totalDuration = phrase.syllableDurations.reduce(0, +)
        guard totalDuration > 0 && syllableCount > 0 else {
            return 0.0
        }
        
        for (idx, dur) in phrase.syllableDurations.enumerated() {
            let fraction = dur / totalDuration
            guard !fraction.isNaN && !fraction.isInfinite else { continue }
            let framesForSyllable = Int(round(Float(fraction) * Float(userAmplitude.count)))
            let ampValue: Float = phrase.stressIndices.contains(idx) ? 1.0 : 0.5
            let count = max(framesForSyllable, 1)
            targetAmp.append(contentsOf: Array(repeating: ampValue, count: count))
        }
        
        // Adjust length to match user data
        if targetAmp.count < userAmplitude.count {
            let last = targetAmp.last ?? 0.5
            targetAmp.append(contentsOf: Array(repeating: last, count: userAmplitude.count - targetAmp.count))
        } else if targetAmp.count > userAmplitude.count {
            targetAmp = Array(targetAmp.prefix(userAmplitude.count))
        }
        
        let targetNormalizedAmp = normalize(targetAmp)
        let rhythmCorr = calculateCorrelation(x: userAmplitude, y: targetNormalizedAmp)
        var score = ((rhythmCorr + 1.0) / 2.0) * 100.0
        return max(0.0, min(100.0, score))
    }
    
    /// Calculate F0 Root Mean Square Error between user and target pitch contours
    /// Works with both normalized (0-1) and raw Hz values
    private func calculateF0RMSE(userPitch: [Float], targetPitch: [Float]) -> Double {
        guard userPitch.count == targetPitch.count && !userPitch.isEmpty else {
            return Double.infinity
        }
        
        // Calculate RMSE: sqrt(mean((user - target)^2))
        var sumSquaredError: Double = 0.0
        var validCount = 0
        
        for i in 0..<userPitch.count {
            let user = Double(userPitch[i])
            let target = Double(targetPitch[i])
            
            // Skip invalid values
            guard !user.isNaN && !user.isInfinite && !target.isNaN && !target.isInfinite else {
                continue
            }
            
            let error = user - target
            sumSquaredError += error * error
            validCount += 1
        }
        
        guard validCount > 0 else { return Double.infinity }
        
        let meanSquaredError = sumSquaredError / Double(validCount)
        let rmse = sqrt(meanSquaredError)
        
        return rmse.isNaN || rmse.isInfinite ? Double.infinity : rmse
    }
    
    /// Enhanced stress score calculation that also returns LSR (Lexical Stress Ratio)
    private func calculateEnhancedStressScore(
        for phrase: Phrase,
        userPitch: [Float],
        userAmplitude: [Float],
        rawPitch: [Float],
        rawAmplitude: [Float]
    ) -> (stressScore: Double, lsrScore: Double) {
        let syllableCount = phrase.syllableDurations.count
        let totalDuration = phrase.syllableDurations.reduce(0, +)
        guard totalDuration > 0 && userPitch.count > 0 else {
            return (0.0, 0.0)
        }
        
        // Segment the user data into syllables
        var segmentBounds: [Int] = []
        for dur in phrase.syllableDurations {
            let fraction = dur / totalDuration
            let frames = max(1, Int(round(Float(fraction) * Float(userPitch.count))))
            segmentBounds.append(frames)
        }
        
        // Adjust last segment to absorb rounding error
        let totalFrames = userPitch.count
        let sumFrames = segmentBounds.reduce(0, +)
        if sumFrames != totalFrames && segmentBounds.count > 0 {
            let adjustment = totalFrames - sumFrames
            segmentBounds[segmentBounds.count - 1] = max(1, segmentBounds[segmentBounds.count - 1] + adjustment)
        }
        
        var stressedPitch: [Float] = []
        var unstressedPitch: [Float] = []
        var stressedAmp: [Float] = []
        var unstressedAmp: [Float] = []
        var stressedDuration: [Float] = []
        var unstressedDuration: [Float] = []
        var startIndex = 0
        
        for (index, frames) in segmentBounds.enumerated() {
            let validFrames = max(1, frames)
            let endIndex = min(startIndex + validFrames, userPitch.count)
            
            guard startIndex < userPitch.count && startIndex < endIndex else {
                break
            }
            
            let pitchSegment = Array(userPitch[startIndex..<endIndex])
            let ampSegment = Array(userAmplitude[startIndex..<min(endIndex, userAmplitude.count)])
            let rawPitchSegment = Array(rawPitch[startIndex..<min(endIndex, rawPitch.count)])
            let rawAmpSegment = Array(rawAmplitude[startIndex..<min(endIndex, rawAmplitude.count)])
            
            guard !pitchSegment.isEmpty && !ampSegment.isEmpty else {
                startIndex = endIndex
                continue
            }
            
            let pitchMean = pitchSegment.reduce(0, +) / Float(pitchSegment.count)
            let ampMean = ampSegment.reduce(0, +) / Float(ampSegment.count)
            let rawPitchMean = rawPitchSegment.reduce(0, +) / Float(rawPitchSegment.count)
            let rawAmpMean = rawAmpSegment.reduce(0, +) / Float(rawAmpSegment.count)
            let duration = Float(frames) // Duration in frames
            
            guard !pitchMean.isNaN && !ampMean.isNaN && !pitchMean.isInfinite && !ampMean.isInfinite else {
                startIndex = endIndex
                continue
            }
            
            if phrase.stressIndices.contains(index) {
                stressedPitch.append(rawPitchMean)
                stressedAmp.append(rawAmpMean)
                stressedDuration.append(duration)
            } else {
                unstressedPitch.append(rawPitchMean)
                unstressedAmp.append(rawAmpMean)
                unstressedDuration.append(duration)
            }
            startIndex = endIndex
        }
        
        // Compute contrast values for basic stress score
        func mean(_ arr: [Float]) -> Float {
            return arr.isEmpty ? 0.0 : arr.reduce(0, +) / Float(arr.count)
        }
        let pitchContrast = mean(stressedPitch) - mean(unstressedPitch)
        let ampContrast = mean(stressedAmp) - mean(unstressedAmp)
        
        let desiredPitchContrast: Float = 0.5
        let desiredAmpContrast: Float = 0.5
        let pitchScorePart = max(0.0 as Float, min(1.0 as Float, pitchContrast / desiredPitchContrast))
        let ampScorePart = max(0.0 as Float, min(1.0 as Float, ampContrast / desiredAmpContrast))
        let stressScore = Double((0.6 as Float * pitchScorePart + 0.4 as Float * ampScorePart) * 100.0 as Float)
        
        // Calculate LSR (Lexical Stress Ratio)
        // LSR compares duration, intensity (amplitude), and pitch ratios between stressed/unstressed
        // Native English typically has: stressed syllables are 1.5-2x longer, 1.3-1.5x louder, 1.2-1.4x higher pitch
        let lsrScore = calculateLSR(
            stressedPitch: stressedPitch,
            unstressedPitch: unstressedPitch,
            stressedAmp: stressedAmp,
            unstressedAmp: unstressedAmp,
            stressedDuration: stressedDuration,
            unstressedDuration: unstressedDuration
        )
        
        return (max(0.0, min(100.0, stressScore)), lsrScore)
    }
    
    /// Calculate Lexical Stress Ratio (LSR) - compares stressed vs unstressed syllable characteristics
    private func calculateLSR(
        stressedPitch: [Float],
        unstressedPitch: [Float],
        stressedAmp: [Float],
        unstressedAmp: [Float],
        stressedDuration: [Float],
        unstressedDuration: [Float]
    ) -> Double {
        guard !stressedPitch.isEmpty && !unstressedPitch.isEmpty else {
            return 0.0
        }
        
        func mean(_ arr: [Float]) -> Float {
            return arr.isEmpty ? 0.0 : arr.reduce(0, +) / Float(arr.count)
        }
        
        // Calculate mean values
        let meanStressedPitch = mean(stressedPitch)
        let meanUnstressedPitch = mean(unstressedPitch)
        let meanStressedAmp = mean(stressedAmp)
        let meanUnstressedAmp = mean(unstressedAmp)
        let meanStressedDuration = mean(stressedDuration)
        let meanUnstressedDuration = mean(unstressedDuration)
        
        // Calculate ratios (native English norms)
        // Duration ratio: stressed should be 1.5-2.0x longer
        let durationRatio = meanUnstressedDuration > 0 ? meanStressedDuration / meanUnstressedDuration : 0.0
        let durationScore = min(1.0, durationRatio / 1.75) // Normalize to 1.75x target
        
        // Amplitude ratio: stressed should be 1.3-1.5x louder
        let amplitudeRatio = meanUnstressedAmp > 0 ? meanStressedAmp / meanUnstressedAmp : 0.0
        let amplitudeScore = min(1.0, amplitudeRatio / 1.4) // Normalize to 1.4x target
        
        // Pitch ratio: stressed should be 1.2-1.4x higher
        let pitchRatio = meanUnstressedPitch > 0 ? meanStressedPitch / meanUnstressedPitch : 0.0
        let pitchScore = min(1.0, pitchRatio / 1.3) // Normalize to 1.3x target
        
        // Combine ratios (weighted average)
        // Duration is most important for stress perception, then amplitude, then pitch
        let combinedLSR = (0.5 * durationScore) + (0.3 * amplitudeScore) + (0.2 * pitchScore)
        
        // Convert to 0-100 score
        return Double(combinedLSR * 100.0)
    }
    
    
    private func normalize(_ data: [Float]) -> [Float] {
        guard !data.isEmpty else { return [] }
        let mean = data.reduce(0, +) / Float(data.count)
        
        guard !mean.isNaN && !mean.isInfinite else {
            return data.map { _ in 0 }
        }
        
        let variance = data.map { pow($0 - mean, 2) }.reduce(0, +) / Float(data.count)
        let stdDev = sqrt(variance)
        
        guard stdDev > 0 && !stdDev.isNaN && !stdDev.isInfinite else {
            return data.map { _ in 0 }
        }
        
        let normalized = data.map { ($0 - mean) / stdDev }
        return normalized.map { $0.isNaN || $0.isInfinite ? 0 : $0 }
    }
    
    private func generateTargetPitch(for phrase: Phrase, length: Int) -> [Float] {
        guard length > 0 else { return [] }
        var target = [Float](repeating: 0, count: length)
        for i in 0..<length {
            let t = Float(i) / Float(max(length, 1))
            switch phrase.intonationType {
            case .rising:
                target[i] = t
            case .falling:
                target[i] = 1.0 - t
            case .flat:
                target[i] = 0.5
            }
        }
        return target
    }
    
    private func dtwDistance(s1: [Float], s2: [Float]) -> Double {
        let n = s1.count
        let m = s2.count
        guard n > 0 && m > 0 else { return Double.infinity }
        
        let validS1 = s1.filter { !$0.isNaN && !$0.isInfinite }
        let validS2 = s2.filter { !$0.isNaN && !$0.isInfinite }
        
        guard !validS1.isEmpty && !validS2.isEmpty else { return Double.infinity }
        
        var dtw = [[Double]](repeating: [Double](repeating: Double.infinity, count: validS2.count + 1), count: validS1.count + 1)
        dtw[0][0] = 0
        
        for i in 1...validS1.count {
            for j in 1...validS2.count {
                let cost = Double(abs(validS1[i-1] - validS2[j-1]))
                guard !cost.isNaN && !cost.isInfinite else { continue }
                dtw[i][j] = cost + min(dtw[i-1][j], min(dtw[i][j-1], dtw[i-1][j-1]))
            }
        }
        
        let result = dtw[validS1.count][validS2.count]
        return result.isNaN || result.isInfinite ? Double.infinity : result
    }
    
    private func calculateCorrelation(x: [Float], y: [Float]) -> Double {
        let n = Float(x.count)
        guard n > 0 && x.count == y.count else { return 0 }
        
        let validPairs = zip(x, y).filter { !$0.isNaN && !$0.isInfinite && !$1.isNaN && !$1.isInfinite }
        guard validPairs.count > 0 else { return 0 }
        
        let validX = validPairs.map { $0.0 }
        let validY = validPairs.map { $0.1 }
        let validN = Float(validX.count)
        
        let sumX = validX.reduce(0, +)
        let sumY = validY.reduce(0, +)
        let sumXY = zip(validX, validY).map(*).reduce(0, +)
        let sumX2 = validX.map { $0 * $0 }.reduce(0, +)
        let sumY2 = validY.map { $0 * $0 }.reduce(0, +)
        
        guard !sumX.isNaN && !sumY.isNaN && !sumXY.isNaN else { return 0 }
        
        let numerator = (validN * sumXY) - (sumX * sumY)
        let denominator = sqrt(((validN * sumX2) - (sumX * sumX)) * ((validN * sumY2) - (sumY * sumY)))
        
        guard denominator != 0 && !denominator.isNaN && !denominator.isInfinite else { return 0 }
        
        let result = Double(numerator / denominator)
        return result.isNaN || result.isInfinite ? 0 : result
    }
    
    /// Calculate variance of a Float array
    private func calculateVariance(_ data: [Float]) -> Float {
        guard !data.isEmpty else { return 0 }
        let mean = data.reduce(0, +) / Float(data.count)
        let variance = data.map { pow($0 - mean, 2) }.reduce(0, +) / Float(data.count)
        return variance
    }
    
    /// Calculate median of a Float array
    private func calculateMedian(_ data: [Float]) -> Float {
        guard !data.isEmpty else { return 0.0 }
        let sorted = data.sorted()
        let count = sorted.count
        if count % 2 == 0 {
            return (sorted[count / 2 - 1] + sorted[count / 2]) / 2.0
        } else {
            return sorted[count / 2]
        }
    }
    
    // MARK: - ASR-based Goodness of Pronunciation (GOP)
    
    /// Calculate ASR-based Goodness of Pronunciation (GOP) score with enhanced methods:
    /// 1. Phoneme-level scoring (strict mode) - compares phonemes instead of words
    /// 2. MFCC-based audio feature comparison (strictest mode) - compares acoustic features directly
    /// 3. Traditional word-level ASR (fallback mode)
    /// - Parameters:
    ///   - audioURL: URL to the recorded audio file
    ///   - targetText: The expected phrase text
    ///   - referenceAudioURL: Optional URL to reference audio file for MFCC comparison (strictest mode)
    ///   - useStrictMode: If true, use phoneme-level scoring; if false, use traditional word-level
    ///   - useMFCCMode: If true, compare MFCC features directly (requires referenceAudioURL)
    /// - Returns: GOP score (0-100) or nil if calculation fails
    func calculateGOP(audioURL: URL, 
                      targetText: String,
                      referenceAudioURL: URL? = nil,
                      useStrictMode: Bool = true,
                      useMFCCMode: Bool = false) async -> Double? {
        // Check current authorization status
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        
        // MFCC Mode: Direct audio feature comparison (strictest, doesn't need ASR)
        if useMFCCMode, let refURL = referenceAudioURL {
            return await performMFCCGOP(userAudioURL: audioURL, referenceAudioURL: refURL)
        }
        
        // Phoneme-level or word-level ASR mode
        if authStatus == .notDetermined {
            // Request permission
            let status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
            
            if status == .authorized {
                return await performGOPRecognition(
                    audioURL: audioURL,
                    targetText: targetText,
                    useStrictMode: useStrictMode
                )
            } else {
                print("⚠️ Speech recognition permission denied")
                return nil
            }
        } else if authStatus == .authorized {
            // Already authorized, proceed
            return await performGOPRecognition(
                audioURL: audioURL,
                targetText: targetText,
                useStrictMode: useStrictMode
            )
        } else {
            print("⚠️ Speech recognition not authorized (status: \(authStatus.rawValue))")
            return nil
        }
    }
    
    /// Perform MFCC-based GOP calculation (strictest mode - direct audio feature comparison)
    private func performMFCCGOP(userAudioURL: URL, referenceAudioURL: URL) async -> Double? {
        return await Task.detached(priority: .userInitiated) {
            // Extract MFCC features from both audio files
            guard let userMFCCs = MFCCExtractor.shared.extractMFCCs(from: userAudioURL) else {
                print("⚠️ MFCC extraction failed for user audio")
                return nil
            }
            
            guard let refMFCCs = MFCCExtractor.shared.extractMFCCs(from: referenceAudioURL) else {
                print("⚠️ MFCC extraction failed for reference audio")
                return nil
            }
            
            // Calculate DTW distance between MFCC sequences
            let dtwDistance = MFCCExtractor.shared.calculateMFCCDTW(userMFCCs, refMFCCs)
            
            // Convert DTW distance to score (0-100)
            // Lower distance = higher score
            // Use exponential decay: score = 100 * exp(-alpha * normalized_distance)
            let maxFrames = max(userMFCCs.count, refMFCCs.count)
            let normalizedDistance = dtwDistance / Double(maxFrames)
            let alpha = 0.1 // Tuning parameter (lower = more forgiving)
            let mfccScore = 100.0 * exp(-alpha * normalizedDistance)
            let clampedScore = max(0.0, min(100.0, mfccScore))
            
            print("✓ MFCC-based GOP: distance=\(String(format: "%.2f", dtwDistance)), score=\(String(format: "%.1f", clampedScore))%")
            
            return clampedScore
        }.value
    }
    
    private func performGOPRecognition(audioURL: URL, targetText: String, useStrictMode: Bool) async -> Double? {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            print("⚠️ Speech recognizer not available")
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            let request = SFSpeechURLRecognitionRequest(url: audioURL)
            request.shouldReportPartialResults = false
            request.taskHint = .dictation
            
            var task: SFSpeechRecognitionTask?
            task = recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    print("⚠️ Speech recognition error: \(error.localizedDescription)")
                    task?.cancel()
                    continuation.resume(returning: nil)
                    return
                }
                
                guard let result = result else {
                    return // Wait for result
                }
                
                if result.isFinal {
                    let recognizedText = result.bestTranscription.formattedString.lowercased()
                    let targetTextLower = targetText.lowercased()
                    
                    print("✓ ASR recognized: '\(recognizedText)' (target: '\(targetTextLower)')")
                    
                    // Calculate GOP based on mode
                    let gopScore: Double
                    if useStrictMode {
                        // Phoneme-level scoring (strict mode)
                        gopScore = self.computePhonemeGOPScore(recognizedText: recognizedText, targetText: targetTextLower)
                    } else {
                        // Traditional word-level scoring (forgiving mode)
                        gopScore = self.computeGOPScore(recognizedText: recognizedText, targetText: targetTextLower)
                    }
                    
                    task?.cancel()
                    continuation.resume(returning: gopScore)
                }
            }
        }
    }
    
    /// Compute phoneme-level GOP score (strict mode)
    /// Compares phonemes instead of words, making it more sensitive to pronunciation errors
    private func computePhonemeGOPScore(recognizedText: String, targetText: String) -> Double {
        let phonemeMapper = PhonemeMapper.shared
        
        // Convert both texts to phoneme sequences
        let recognizedPhonemes = phonemeMapper.phraseToPhonemes(recognizedText)
        let targetPhonemes = phonemeMapper.phraseToPhonemes(targetText)
        
        guard !targetPhonemes.isEmpty else {
            // Fallback to word-level if phoneme mapping fails
            print("⚠️ Phoneme mapping failed, falling back to word-level scoring")
            return computeGOPScore(recognizedText: recognizedText, targetText: targetText)
        }
        
        // Calculate phoneme-level accuracy
        let phonemeAccuracy = phonemeMapper.calculatePhonemeAccuracy(
            recognizedPhonemes: recognizedPhonemes,
            targetPhonemes: targetPhonemes
        )
        
        // Also calculate word-level accuracy as a secondary metric
        let recognizedWords = recognizedText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let targetWords = targetText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let wordAccuracy = calculateWordAccuracy(recognized: recognizedWords, target: targetWords)
        
        // Combine phoneme accuracy (70%) with word accuracy (30%)
        // Phoneme accuracy is weighted higher because it's more sensitive to pronunciation errors
        let gopScore = (0.7 * phonemeAccuracy) + (0.3 * wordAccuracy)
        
        print("📊 Phoneme-level GOP: phoneme_acc=\(String(format: "%.2f", phonemeAccuracy)), word_acc=\(String(format: "%.2f", wordAccuracy)), final=\(String(format: "%.1f", gopScore * 100))%")
        
        return gopScore * 100.0
    }
    
    /// Compute GOP score from recognized text and target text (traditional word-level, forgiving mode)
    private func computeGOPScore(recognizedText: String, targetText: String) -> Double {
        // Method 1: Word-level accuracy
        let recognizedWords = recognizedText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let targetWords = targetText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        
        guard !targetWords.isEmpty else { return 0.0 }
        
        // Calculate word accuracy using Levenshtein distance
        let wordAccuracy = calculateWordAccuracy(recognized: recognizedWords, target: targetWords)
        
        // Method 2: Character-level similarity (for phoneme-level accuracy proxy)
        let charSimilarity = calculateCharacterSimilarity(str1: recognizedText, str2: targetText)
        
        // Combine both metrics (weight word accuracy higher)
        let gopScore = (0.7 * wordAccuracy) + (0.3 * charSimilarity)
        
        // Convert to 0-100 scale
        return gopScore * 100.0
    }
    
    /// Calculate word-level accuracy using edit distance
    private func calculateWordAccuracy(recognized: [String], target: [String]) -> Double {
        guard !target.isEmpty else { return 0.0 }
        
        // Simple word matching
        var matches = 0
        let minCount = min(recognized.count, target.count)
        
        for i in 0..<minCount {
            // Normalize words (remove punctuation, lowercase)
            let recWord = recognized[i].lowercased().trimmingCharacters(in: .punctuationCharacters)
            let tarWord = target[i].lowercased().trimmingCharacters(in: .punctuationCharacters)
            
            if recWord == tarWord {
                matches += 1
            } else {
                // Check for partial match (e.g., "hello" vs "hello,")
                if recWord.contains(tarWord) || tarWord.contains(recWord) {
                    matches += 1
                }
            }
        }
        
        let accuracy = Double(matches) / Double(target.count)
        return accuracy
    }
    
    /// Calculate character-level similarity (Levenshtein distance normalized)
    private func calculateCharacterSimilarity(str1: String, str2: String) -> Double {
        let distance = levenshteinDistance(str1: str1, str2: str2)
        let maxLen = max(str1.count, str2.count)
        guard maxLen > 0 else { return 0.0 }
        
        let similarity = 1.0 - (Double(distance) / Double(maxLen))
        return max(0.0, min(1.0, similarity))
    }
    
    /// Calculate Levenshtein distance between two strings
    private func levenshteinDistance(str1: String, str2: String) -> Int {
        let s1 = Array(str1)
        let s2 = Array(str2)
        let m = s1.count
        let n = s2.count
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        
        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }
        
        for i in 1...m {
            for j in 1...n {
                if s1[i-1] == s2[j-1] {
                    dp[i][j] = dp[i-1][j-1]
                } else {
                    dp[i][j] = 1 + min(dp[i-1][j], dp[i][j-1], dp[i-1][j-1])
                }
            }
        }
        
        return dp[m][n]
    }
}

