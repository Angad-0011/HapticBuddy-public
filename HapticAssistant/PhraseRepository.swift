import Foundation

/// Repository for loading and managing learning phrases
class PhraseRepository {
    static let shared = PhraseRepository()
    
    private let phrasesFileName = "phrases"
    private var cachedPhrases: [Phrase]?
    
    private init() {}
    
    /// Loads phrases from the phrases.json file in the app bundle
    func loadPhrases() -> Result<[Phrase], PhraseLoadingError> {
        // Return cached phrases if available
        if let cached = cachedPhrases {
            return .success(cached)
        }
        
        guard let url = Bundle.main.url(forResource: phrasesFileName, withExtension: "json") else {
            return .failure(.fileNotFound)
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            
            // Decode JSON array
            let jsonPhrases = try decoder.decode([JSONPhrase].self, from: data)
            
            // Convert to Phrase models
            let phrases = jsonPhrases.compactMap { jsonPhrase -> Phrase? in
                guard let intonationType = IntonationType(rawValue: jsonPhrase.intonationType) else {
                    print("Warning: Invalid intonation type '\(jsonPhrase.intonationType)' for phrase: \(jsonPhrase.text)")
                    return nil
                }
                
                // Parse difficulty
                let difficulty = jsonPhrase.difficulty.flatMap { Difficulty(rawValue: $0) }
                
                // Parse sets
                let sets = jsonPhrase.sets?.compactMap { PhraseSet(rawValue: $0) }
                
                return Phrase(
                    id: jsonPhrase.id,
                    text: jsonPhrase.text,
                    audioFileName: jsonPhrase.audioFileName,
                    intonationType: intonationType,
                    stressIndices: jsonPhrase.stressIndices,
                    syllableDurations: jsonPhrase.syllableDurations,
                    syllableTextures: jsonPhrase.syllableTextures,
                    category: jsonPhrase.category,
                    difficulty: difficulty,
                    tags: jsonPhrase.tags,
                    sets: sets,
                    syllableTimestamps: jsonPhrase.syllableTimestamps
                )
            }
            
            guard !phrases.isEmpty else {
                return .failure(.noValidPhrases)
            }
            
            // Cache the phrases
            cachedPhrases = phrases
            
            return .success(phrases)
        } catch let error as DecodingError {
            return .failure(.decodingError(error.localizedDescription))
        } catch {
            return .failure(.unknownError(error.localizedDescription))
        }
    }
    
    /// Get all unique categories from loaded phrases
    func getCategories() -> [String] {
        guard let phrases = cachedPhrases ?? (try? loadPhrases().get()) else {
            return []
        }
        return Array(Set(phrases.compactMap { $0.category })).sorted()
    }
    
    /// Filter phrases by category
    func filterPhrases(by category: String?) -> [Phrase] {
        guard let phrases = cachedPhrases ?? (try? loadPhrases().get()) else {
            return []
        }
        
        guard let category = category, !category.isEmpty else {
            return phrases
        }
        
        return phrases.filter { $0.category == category }
    }
    
    /// Clear cache (useful for testing or reloading)
    func clearCache() {
        cachedPhrases = nil
    }
}

// MARK: - JSON Decoding Models

private struct JSONPhrase: Codable {
    let id: String
    let text: String
    let audioFileName: String
    let intonationType: String
    let stressIndices: [Int]
    let syllableDurations: [TimeInterval]
    let syllableTextures: [String]?
    let category: String?
    let difficulty: String?
    let tags: [String]?
    let sets: [String]?
    let syllableTimestamps: [[TimeInterval]]? // Optional: forced alignment timestamps
}

// MARK: - Error Types

enum PhraseLoadingError: LocalizedError {
    case fileNotFound
    case decodingError(String)
    case unknownError(String)
    case noValidPhrases
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Phrases file not found. Please ensure phrases.json exists in the app bundle."
        case .decodingError(let message):
            return "Failed to decode phrases: \(message)"
        case .unknownError(let message):
            return "Error loading phrases: \(message)"
        case .noValidPhrases:
            return "No valid phrases found in the file."
        }
    }
}

