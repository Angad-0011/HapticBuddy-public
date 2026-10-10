import Foundation
import Combine

struct SessionScore: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let phraseId: String // Stable phrase ID for cross-session tracking
    let score: Int // 0-100
}

class ProgressManager: ObservableObject {
    @Published var scores: [SessionScore] = []
    
    private let saveKey = "user_progress_scores"
    
    init() {
        loadScores()
    }
    
    func addScore(phraseId: String, score: Int) {
        let newScore = SessionScore(date: Date(), phraseId: phraseId, score: score)
        scores.append(newScore)
        saveScores()
    }
    
    func getAverageScore() -> Int {
        guard !scores.isEmpty else { return 0 }
        let total = scores.reduce(0) { $0 + $1.score }
        return total / scores.count
    }
    
    func getRecentScores(limit: Int = 10) -> [SessionScore] {
        let sorted = scores.sorted { $0.date > $1.date }
        return Array(sorted.prefix(limit))
    }
    
    private func saveScores() {
        if let encoded = try? JSONEncoder().encode(scores) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }
    
    private func loadScores() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([SessionScore].self, from: data) {
            scores = decoded
        }
    }
    
    func resetProgress() {
        scores.removeAll()
        UserDefaults.standard.removeObject(forKey: saveKey)
    }
}
