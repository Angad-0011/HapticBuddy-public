import Foundation

/// Experiment condition types
enum ExperimentCondition: String, Codable {
    case practice = "Practice"
    case textOnly = "TextOnly"
    case audioOnly = "AudioOnly"
    case hapticAudio = "HapticAudio"
}

/// Experiment phase types
enum ExperimentPhase: String, Codable {
    case preTest = "PreTest"
    case training = "Training"
    case postTest = "PostTest"
    case practice = "Practice"
}

