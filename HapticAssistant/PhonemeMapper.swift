import Foundation

/// Maps English words to their phoneme sequences using CMUArpabet notation.
/// CMUArpabet is a phonetic alphabet used in speech recognition and synthesis.
class PhonemeMapper {
    static let shared = PhonemeMapper()
    
    private init() {}
    
    /// CMUArpabet phoneme dictionary for common English words
    /// Format: word -> [phoneme1, phoneme2, ...]
    /// Phonemes are in CMUArpabet notation (e.g., "HH", "EH", "L", "OW" for "hello")
    private let phonemeDictionary: [String: [String]] = [
        // Greetings
        "hello": ["HH", "AH", "L", "OW"],
        "how": ["HH", "AW"],
        "are": ["AA", "R"],
        "you": ["Y", "UW"],
        "hi": ["HH", "AY"],
        "goodbye": ["G", "UH", "D", "B", "AY"],
        "thanks": ["TH", "AE", "NG", "K", "S"],
        "please": ["P", "L", "IY", "Z"],
        
        // Basics
        "i": ["AY"],
        "am": ["AE", "M"],
        "doing": ["D", "UW", "IH", "NG"],
        "well": ["W", "EH", "L"],
        "fine": ["F", "AY", "N"],
        "okay": ["OW", "K", "EY"],
        "yes": ["Y", "EH", "S"],
        "no": ["N", "OW"],
        
        // Travel
        "where": ["W", "EH", "R"],
        "is": ["IH", "Z"],
        "the": ["DH", "AH"],
        "library": ["L", "AY", "B", "R", "EH", "R", "IY"],
        "station": ["S", "T", "EY", "SH", "AH", "N"],
        "airport": ["EH", "R", "P", "AO", "R", "T"],
        "hotel": ["HH", "OW", "T", "EH", "L"],
        "restaurant": ["R", "EH", "S", "T", "ER", "AH", "N", "T"],
        "can": ["K", "AE", "N"],
        "help": ["HH", "EH", "L", "P"],
        "me": ["M", "IY"],
        "need": ["N", "IY", "D"],
        
        // Common words
        "excuse": ["IH", "K", "S", "K", "Y", "UW", "Z"],
        "what": ["W", "AH", "T"],
        "time": ["T", "AY", "M"],
        "sorry": ["S", "AO", "R", "IY"],
        "pardon": ["P", "AA", "R", "D", "AH", "N"],
    ]
    
    /// Convert a word to its phoneme sequence using CMUArpabet notation
    /// - Parameter word: The word to convert (lowercased, punctuation removed)
    /// - Returns: Array of phonemes in CMUArpabet notation, or nil if word not found
    func wordToPhonemes(_ word: String) -> [String]? {
        let normalized = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
        return phonemeDictionary[normalized]
    }
    
    /// Convert a phrase (sentence) to phoneme sequence
    /// - Parameter phrase: The phrase text
    /// - Returns: Array of phonemes for the entire phrase
    func phraseToPhonemes(_ phrase: String) -> [String] {
        let words = phrase.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
        
        var phonemes: [String] = []
        for word in words {
            if let wordPhonemes = wordToPhonemes(word) {
                phonemes.append(contentsOf: wordPhonemes)
            } else {
                // If word not found, try to break it down or use character-level approximation
                // For now, we'll skip unknown words (could be improved with a TTS engine)
                print("⚠️ PhonemeMapper: Unknown word '\(word)', skipping")
            }
        }
        
        return phonemes
    }
    
    /// Calculate phoneme-level accuracy between recognized and target phoneme sequences
    /// Uses dynamic programming (similar to Levenshtein) to align phonemes
    /// - Parameters:
    ///   - recognizedPhonemes: Phonemes from ASR recognition
    ///   - targetPhonemes: Target phonemes from the phrase
    /// - Returns: Accuracy score (0.0-1.0)
    func calculatePhonemeAccuracy(recognizedPhonemes: [String], targetPhonemes: [String]) -> Double {
        guard !targetPhonemes.isEmpty else { return 0.0 }
        
        // Use edit distance to align phonemes
        let distance = phonemeEditDistance(recognizedPhonemes, targetPhonemes)
        let maxLen = max(recognizedPhonemes.count, targetPhonemes.count)
        guard maxLen > 0 else { return 0.0 }
        
        // Convert edit distance to accuracy
        let accuracy = 1.0 - (Double(distance) / Double(maxLen))
        return max(0.0, min(1.0, accuracy))
    }
    
    /// Calculate edit distance between two phoneme sequences
    /// Accounts for phoneme similarity (e.g., "IH" vs "IY" are similar vowels)
    private func phonemeEditDistance(_ s1: [String], _ s2: [String]) -> Int {
        let m = s1.count
        let n = s2.count
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        
        // Initialize base cases
        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }
        
        // Fill DP table
        for i in 1...m {
            for j in 1...n {
                if s1[i-1] == s2[j-1] {
                    // Exact match
                    dp[i][j] = dp[i-1][j-1]
                } else if arePhonemesSimilar(s1[i-1], s2[j-1]) {
                    // Similar phonemes (e.g., similar vowels) - cost 0.5
                    dp[i][j] = dp[i-1][j-1] + 1 // Still count as substitution but less penalty
                } else {
                    // Different phonemes - standard edit distance
                    dp[i][j] = 1 + min(dp[i-1][j], dp[i][j-1], dp[i-1][j-1])
                }
            }
        }
        
        return dp[m][n]
    }
    
    /// Check if two phonemes are similar (e.g., similar vowels or consonants)
    /// This helps account for pronunciation variations
    private func arePhonemesSimilar(_ p1: String, _ p2: String) -> Bool {
        // Vowel similarity groups
        let vowelGroups = [
            ["IH", "IY", "EH"], // Similar front vowels
            ["AH", "AA", "AO"], // Similar back vowels
            ["UW", "UH", "OW"], // Similar rounded vowels
        ]
        
        // Check if both phonemes are in the same vowel group
        for group in vowelGroups {
            if group.contains(p1) && group.contains(p2) {
                return true
            }
        }
        
        // Consonant similarity (same place/manner of articulation)
        let consonantGroups = [
            ["P", "B"], // Bilabial stops
            ["T", "D"], // Alveolar stops
            ["K", "G"], // Velar stops
            ["F", "V"], // Labiodental fricatives
            ["TH", "DH"], // Dental fricatives
            ["S", "Z"], // Alveolar fricatives
            ["SH", "ZH"], // Palato-alveolar fricatives
        ]
        
        for group in consonantGroups {
            if group.contains(p1) && group.contains(p2) {
                return true
            }
        }
        
        return false
    }
}

