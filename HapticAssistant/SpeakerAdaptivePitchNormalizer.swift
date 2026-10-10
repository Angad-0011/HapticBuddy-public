import Foundation

/// Manages speaker-adaptive pitch normalization for fair scoring across different voice types
class SpeakerAdaptivePitchNormalizer {
    static let shared = SpeakerAdaptivePitchNormalizer()
    
    private let userDefaults = UserDefaults.standard
    private let pitchRangeKey = "speaker_pitch_range"
    private let warmupCountKey = "speaker_warmup_count"
    
    // Minimum number of warm-up utterances before using adaptive range
    private let minimumWarmupUtterances = 2
    
    // Default pitch range (Hz) - used before warm-up is complete
    private let defaultMinHz: Float = 70.0
    private let defaultMaxHz: Float = 300.0
    
    private init() {}
    
    /// Normalize pitch to 0-1 range using speaker-adaptive method
    /// - Parameters:
    ///   - pitchHz: Raw pitch in Hz
    ///   - userId: User identifier for storing pitch range
    /// - Returns: Normalized pitch (0.0-1.0) or -1.0 for invalid/silence
    func normalizePitch(pitchHz: Float, userId: String) -> Float {
        guard pitchHz > 0 else { return -1.0 } // Invalid/silence
        
        // Get user's pitch range (or use default if not calibrated)
        let (minHz, maxHz) = getPitchRange(for: userId)
        
        // Clamp to range
        let clamped = max(minHz, min(maxHz, pitchHz))
        
        // Normalize to 0-1
        let normalized = (clamped - minHz) / (maxHz - minHz)
        
        return max(0.0, min(1.0, normalized))
    }
    
    /// Convert pitch to semitones relative to speaker's median F0
    /// This is more speaker-robust than absolute Hz values
    /// - Parameters:
    ///   - pitchHz: Raw pitch in Hz
    ///   - medianF0: Speaker's median F0 for this trial
    /// - Returns: Pitch in semitones relative to median (0 = median, positive = higher, negative = lower)
    func pitchToSemitones(pitchHz: Float, relativeTo medianF0: Float) -> Float {
        guard pitchHz > 0 && medianF0 > 0 else { return 0.0 }
        
        // Convert to semitones: semitones = 12 * log2(pitch / reference)
        let semitones = 12.0 * log2(pitchHz / medianF0)
        
        return semitones
    }
    
    /// Normalize pitch using semitones relative to median (more speaker-robust)
    /// - Parameters:
    ///   - pitchHz: Raw pitch in Hz
    ///   - medianF0: Speaker's median F0 for this trial
    ///   - semitoneRange: Expected semitone range (default: ±6 semitones = one octave)
    /// - Returns: Normalized pitch (0.0-1.0) where 0.5 = median, 0.0 = median - range, 1.0 = median + range
    func normalizePitchSemitones(pitchHz: Float, relativeTo medianF0: Float, semitoneRange: Float = 6.0) -> Float {
        guard pitchHz > 0 && medianF0 > 0 else { return -1.0 }
        
        let semitones = pitchToSemitones(pitchHz: pitchHz, relativeTo: medianF0)
        
        // Normalize to 0-1 range: 0.5 = median (0 semitones), 0.0 = -range, 1.0 = +range
        let normalized = (semitones / semitoneRange) + 0.5
        
        return max(0.0, min(1.0, normalized))
    }
    
    /// Update pitch range based on observed pitch values from a trial
    /// This is called after each recording to gradually adapt to the speaker
    /// - Parameters:
    ///   - userId: User identifier
    ///   - pitchValues: Array of valid pitch values in Hz (excluding -1.0)
    func updatePitchRange(for userId: String, from pitchValues: [Float]) {
        let validPitches = pitchValues.filter { $0 > 0 }
        guard !validPitches.isEmpty else { return }
        
        // Calculate current range
        let currentMin = validPitches.min() ?? defaultMinHz
        let currentMax = validPitches.max() ?? defaultMaxHz
        let currentMedian = calculateMedian(validPitches)
        
        // Get stored range (or use default)
        let (storedMin, storedMax) = getPitchRange(for: userId)
        let warmupCount = getWarmupCount(for: userId)
        
        // Update range using exponential moving average
        // Early utterances have more weight to adapt quickly
        let alpha: Float = warmupCount < minimumWarmupUtterances ? 0.7 : 0.3
        
        let newMin = alpha * currentMin + (1.0 - alpha) * storedMin
        let newMax = alpha * currentMax + (1.0 - alpha) * storedMax
        
        // Ensure reasonable range (at least 50Hz span)
        let minRange: Float = 50.0
        let finalMin = min(newMin, currentMedian - minRange / 2)
        let finalMax = max(newMax, currentMedian + minRange / 2)
        
        // Store updated range
        storePitchRange(for: userId, minHz: finalMin, maxHz: finalMax)
        
        // Increment warmup count
        incrementWarmupCount(for: userId)
        
        print("📊 Updated pitch range for \(userId): \(String(format: "%.1f", finalMin))-\(String(format: "%.1f", finalMax)) Hz (median: \(String(format: "%.1f", currentMedian)) Hz, warmup: \(warmupCount + 1))")
    }
    
    /// Get pitch range for a user (or default if not calibrated)
    private func getPitchRange(for userId: String) -> (minHz: Float, maxHz: Float) {
        if let stored = userDefaults.dictionary(forKey: pitchRangeKey),
           let userData = stored[userId] as? [String: Float],
           let minHz = userData["minHz"],
           let maxHz = userData["maxHz"] {
            return (minHz, maxHz)
        }
        
        // Return default range
        return (defaultMinHz, defaultMaxHz)
    }
    
    /// Store pitch range for a user
    private func storePitchRange(for userId: String, minHz: Float, maxHz: Float) {
        var stored = userDefaults.dictionary(forKey: pitchRangeKey) ?? [:]
        stored[userId] = ["minHz": minHz, "maxHz": maxHz]
        userDefaults.set(stored, forKey: pitchRangeKey)
    }
    
    /// Get warmup count for a user
    private func getWarmupCount(for userId: String) -> Int {
        if let stored = userDefaults.dictionary(forKey: warmupCountKey),
           let count = stored[userId] as? Int {
            return count
        }
        return 0
    }
    
    /// Increment warmup count for a user
    private func incrementWarmupCount(for userId: String) {
        var stored = userDefaults.dictionary(forKey: warmupCountKey) ?? [:]
        let currentCount = getWarmupCount(for: userId)
        stored[userId] = currentCount + 1
        userDefaults.set(stored, forKey: warmupCountKey)
    }
    
    /// Calculate median of an array
    private func calculateMedian(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0.0 }
        let sorted = values.sorted()
        let count = sorted.count
        if count % 2 == 0 {
            return (sorted[count / 2 - 1] + sorted[count / 2]) / 2.0
        } else {
            return sorted[count / 2]
        }
    }
    
    /// Reset pitch range for a user (e.g., for recalibration)
    func resetPitchRange(for userId: String) {
        var pitchRanges = userDefaults.dictionary(forKey: pitchRangeKey) ?? [:]
        pitchRanges.removeValue(forKey: userId)
        userDefaults.set(pitchRanges, forKey: pitchRangeKey)
        
        var warmupCounts = userDefaults.dictionary(forKey: warmupCountKey) ?? [:]
        warmupCounts.removeValue(forKey: userId)
        userDefaults.set(warmupCounts, forKey: warmupCountKey)
        
        print("🔄 Reset pitch range for \(userId)")
    }
}

