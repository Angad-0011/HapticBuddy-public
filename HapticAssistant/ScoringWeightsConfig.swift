import Foundation

/// Configurable weights for final score calculation
/// Allows adjustment for pilot vs. final study without code edits
struct ScoringWeightsConfig: Codable {
    /// Weight for DTW (Dynamic Time Warping) pitch similarity score (0.0-1.0)
    var dtwWeight: Double
    
    /// Weight for rhythm score (0.0-1.0)
    var rhythmWeight: Double
    
    /// Weight for stress score (0.0-1.0)
    var stressWeight: Double
    
    /// Weight for LSR (Lexical Stress Ratio) score (0.0-1.0)
    var lsrWeight: Double
    
    /// Weight for GOP (Goodness of Pronunciation) score (0.0-1.0, optional)
    var gopWeight: Double?
    
    /// Default weights (original hardcoded values)
    static let `default` = ScoringWeightsConfig(
        dtwWeight: 0.5,
        rhythmWeight: 0.2,
        stressWeight: 0.15,
        lsrWeight: 0.15,
        gopWeight: nil
    )
    
    /// Pilot study weights (may emphasize different aspects)
    static let pilot = ScoringWeightsConfig(
        dtwWeight: 0.4,
        rhythmWeight: 0.25,
        stressWeight: 0.2,
        lsrWeight: 0.15,
        gopWeight: nil
    )
    
    /// Final study weights (optimized based on pilot results)
    static let final = ScoringWeightsConfig(
        dtwWeight: 0.5,
        rhythmWeight: 0.2,
        stressWeight: 0.15,
        lsrWeight: 0.15,
        gopWeight: nil
    )
    
    /// Weights with GOP included (if available)
    static let withGOP = ScoringWeightsConfig(
        dtwWeight: 0.4,
        rhythmWeight: 0.15,
        stressWeight: 0.1,
        lsrWeight: 0.1,
        gopWeight: 0.25
    )
    
    /// Validate that weights sum to approximately 1.0 (within tolerance)
    func validate() -> Bool {
        let sum = dtwWeight + rhythmWeight + stressWeight + lsrWeight + (gopWeight ?? 0.0)
        return abs(sum - 1.0) < 0.01 // Allow 1% tolerance
    }
    
    /// Normalize weights to sum to 1.0
    mutating func normalize() {
        let sum = dtwWeight + rhythmWeight + stressWeight + lsrWeight + (gopWeight ?? 0.0)
        guard sum > 0 else { return }
        
        dtwWeight /= sum
        rhythmWeight /= sum
        stressWeight /= sum
        lsrWeight /= sum
        if let gop = gopWeight {
            gopWeight = gop / sum
        }
    }
}

/// Manager for scoring weights configuration
class ScoringWeightsManager {
    static let shared = ScoringWeightsManager()
    
    private let userDefaults = UserDefaults.standard
    private let weightsKey = "scoring_weights_config"
    
    private init() {}
    
    /// Get current scoring weights configuration
    func getWeights() -> ScoringWeightsConfig {
        if let data = userDefaults.data(forKey: weightsKey),
           let config = try? JSONDecoder().decode(ScoringWeightsConfig.self, from: data) {
            return config
        }
        
        // Return default weights
        return .default
    }
    
    /// Set scoring weights configuration
    func setWeights(_ config: ScoringWeightsConfig) {
        var normalizedConfig = config
        normalizedConfig.normalize()
        
        if let data = try? JSONEncoder().encode(normalizedConfig) {
            userDefaults.set(data, forKey: weightsKey)
            print("📊 Scoring weights updated: DTW=\(normalizedConfig.dtwWeight), Rhythm=\(normalizedConfig.rhythmWeight), Stress=\(normalizedConfig.stressWeight), LSR=\(normalizedConfig.lsrWeight), GOP=\(normalizedConfig.gopWeight?.description ?? "nil")")
        }
    }
    
    /// Reset to default weights
    func resetToDefault() {
        setWeights(.default)
    }
}

