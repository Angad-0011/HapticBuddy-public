import Foundation

/// Participant metadata collected at the start of the experiment
struct ParticipantMetadata: Codable {
    let userId: String
    let age: Int?
    let gender: String? // Optional for privacy
    let nativeLanguage: String
    let englishProficiency: ProficiencyLevel
    let yearsOfEnglishStudy: Int?
    let previousPronunciationTraining: Bool
    let deviceModel: String
    let iosVersion: String
    let consentGiven: Bool
    let timestamp: Date
    
    enum ProficiencyLevel: String, Codable, CaseIterable {
        case beginner = "Beginner"
        case intermediate = "Intermediate"
        case advanced = "Advanced"
    }
}

// ExperimentPhase moved to ExperimentTypes.swift

/// Experiment session configuration
struct ExperimentSessionConfig: Codable {
    let userId: String
    let sessionUUID: String // Unique session identifier
    let participantMetadata: ParticipantMetadata
    let conditionOrder: [String] // Order of conditions (e.g., ["AudioOnly", "HapticAudio"]) - stored as strings for JSON compatibility
    let phraseOrder: [String] // Phrase IDs in order
    let randomizationSeed: Int? // For reproducibility
    let sessionStartTime: Date
    var currentPhase: ExperimentPhase
    var currentTrialIndex: Int
}

