import Foundation
import CryptoKit

/// Handles randomization and counterbalancing for experiments
class ExperimentRandomizer {
    
    /// Randomize phrase order
    static func randomizePhrases(_ phrases: [Phrase], seed: Int? = nil) -> [Phrase] {
        var rng: RandomNumberGenerator
        if let seed = seed {
            rng = SeededRandomNumberGenerator(seed: seed)
        } else {
            rng = SystemRandomNumberGenerator()
        }
        return phrases.shuffled(using: &rng)
    }
    
    /// Generate condition order using Latin square counterbalancing
    /// This ensures balanced condition assignment across participants
    /// Returns: ["AudioOnly", "HapticAudio"] or ["HapticAudio", "AudioOnly"]
    /// Note: Returns strings for JSON compatibility, but can be converted to ExperimentCondition enum
    static func generateConditionOrder(userId: String, seed: Int? = nil) -> [String] {
        // Use stable hash for reproducibility
        let stableHash: Int
        if let seed = seed {
            // If seed is provided, use it directly
            stableHash = seed
        } else {
            // Use SHA256 hash of userId for stable, reproducible hashing
            let data = userId.data(using: .utf8) ?? Data()
            let hash = SHA256.hash(data: data)
            // Take first 4 bytes and convert to Int (using Int32 range safety)
            // Convert hash digest to Data first to use withUnsafeBytes
            let hashData = Data(hash.prefix(4))
            stableHash = hashData.withUnsafeBytes { bytes in
                Int(bytes.load(as: Int32.self))
            }
        }
        
        // Latin square counterbalancing: assign based on participant number
        // This ensures balanced distribution across conditions
        // Use absolute value for modulo (handle negative hashes)
        let participantNumber = abs(stableHash) % 4 // 4 possible orders in 2x2 Latin square
        
        // 2x2 Latin square design:
        // Order 0: AudioOnly -> HapticAudio
        // Order 1: HapticAudio -> AudioOnly
        // Order 2: AudioOnly -> HapticAudio (same as 0, for balance)
        // Order 3: HapticAudio -> AudioOnly (same as 1, for balance)
        let useFirstOrder = participantNumber % 2 == 0
        
        if useFirstOrder {
            return ["AudioOnly", "HapticAudio"]
        } else {
            return ["HapticAudio", "AudioOnly"]
        }
    }
    
    /// Get 3 pre-test phrases (not from database, no audio/haptic)
    static func getPreTestPhrases() -> [Phrase] {
        return [
            Phrase(
                id: "pretest_1",
                text: "Hello, how are you?",
                audioFileName: "", // Empty - no audio playback
                intonationType: .rising,
                stressIndices: [1, 4],
                syllableDurations: [0.2, 0.3, 0.2, 0.2, 0.4],
                syllableTextures: nil,
                category: "PreTest",
                difficulty: nil,
                tags: nil,
                sets: [.preTest],
                syllableTimestamps: nil
            ),
            Phrase(
                id: "pretest_2",
                text: "I need help, please.",
                audioFileName: "", // Empty - no audio playback
                intonationType: .falling,
                stressIndices: [1, 3],
                syllableDurations: [0.2, 0.3, 0.2, 0.3, 0.3],
                syllableTextures: nil,
                category: "PreTest",
                difficulty: nil,
                tags: nil,
                sets: [.preTest],
                syllableTimestamps: nil
            ),
            Phrase(
                id: "pretest_3",
                text: "Where is the station?",
                audioFileName: "", // Empty - no audio playback
                intonationType: .rising,
                stressIndices: [0, 3],
                syllableDurations: [0.3, 0.2, 0.2, 0.3, 0.3],
                syllableTextures: nil,
                category: "PreTest",
                difficulty: nil,
                tags: nil,
                sets: [.preTest],
                syllableTimestamps: nil
            )
        ]
    }
    
    /// Get 10 training phrases from database (in order, not randomized)
    static func getTrainingPhrases(from allPhrases: [Phrase]) -> [Phrase] {
        // Take first 10 phrases from database in order (not randomized)
        return Array(allPhrases.prefix(10))
    }
    
    /// Get 3 phrases from training set for post-test
    /// - Parameters:
    ///   - trainingPhrases: The 10 phrases used in training
    ///   - seed: Optional seed for reproducible selection
    /// - Returns: 3 phrases selected from training set
    static func getPostTestTrainingPhrases(from trainingPhrases: [Phrase], seed: Int? = nil) -> [Phrase] {
        guard trainingPhrases.count >= 3 else {
            return Array(trainingPhrases.prefix(3))
        }
        
        // Select 3 phrases from training set (e.g., indices 2, 5, 8 for even distribution)
        // This ensures we test different parts of the training sequence
        let indices = [2, 5, 8].filter { $0 < trainingPhrases.count }
        return indices.map { trainingPhrases[$0] }
    }
}

/// Seeded random number generator for reproducibility
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64
    
    init(seed: Int) {
        // Handle Int.min safely before calling abs()
        // Int.min cannot be made positive with abs() without overflow
        let safeSeed: UInt64
        if seed == Int.min {
            // Use a default seed for Int.min
            safeSeed = 12345
        } else {
            // Use magnitude (absolute value) safely
            let magnitude = seed < 0 ? UInt64(-seed) : UInt64(seed)
            safeSeed = magnitude
        }
        
        // Ensure state is never zero (would make RNG predictable)
        self.state = safeSeed == 0 ? 1 : safeSeed
    }
    
    mutating func next() -> UInt64 {
        state = state &* 1103515245 &+ 12345
        return state
    }
}

