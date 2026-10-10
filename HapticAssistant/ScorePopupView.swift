import SwiftUI

struct ScorePopupView: View {
    let score: Int
    let metrics: PronunciationMetrics?
    let phrase: Phrase? // Optional phrase for actionable feedback and visualization
    let userPitchHistory: [Float]? // Optional user pitch history for visualization
    let onDismiss: () -> Void
    
    var stars: Int {
        if score >= 90 { return 3 }
        if score >= 70 { return 2 }
        if score >= 50 { return 1 }
        return 0
    }
    
    var message: String {
        if let metrics = metrics {
            return metrics.feedback
        }
        if score >= 90 { return "Perfect Intonation!" }
        if score >= 70 { return "Great Job!" }
        if score >= 50 { return "Good Effort" }
        return "Keep Practicing"
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
            
            ScrollView {
            VStack(spacing: 20) {
                Text(message)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                
                    // Actionable feedback ("what to fix next")
                    if let metrics = metrics, let phrase = phrase, let actionableFeedback = metrics.actionableFeedback(for: phrase) {
                        HStack(spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 16))
                            Text(actionableFeedback)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(10)
                    }
                    
                HStack(spacing: 10) {
                    ForEach(0..<3) { index in
                        Image(systemName: index < stars ? "star.fill" : "star")
                            .font(.system(size: 40))
                            .foregroundColor(index < stars ? .yellow : .gray.opacity(0.3))
                            .scaleEffect(index < stars ? 1.1 : 1.0)
                            .animation(.spring().delay(Double(index) * 0.1), value: stars)
                    }
                }
                
                Text("\(score)%")
                    .font(.system(size: 60, weight: .heavy, design: .rounded))
                    .foregroundColor(score >= 70 ? .green : .orange)
                
                    // Pitch Contour Visualization
                    if let phrase = phrase, let userPitch = userPitchHistory, !userPitch.isEmpty {
                        // Generate target pitch contour
                        let targetPitch = generateTargetPitch(for: phrase, length: userPitch.count)
                        
                        PitchContourVisualization(
                            userPitch: userPitch,
                            targetPitch: targetPitch,
                            intonationType: phrase.intonationType
                        )
                        .padding(.vertical, 8)
                    }
                    
                    // Detailed Score Breakdown
                    if let metrics = metrics {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Score Breakdown")
                                .font(.system(.headline, design: .rounded))
                                .foregroundColor(.secondary)
                            
                            ScoreRow(label: "Intonation", score: metrics.breakdown.intonation, color: .blue)
                            ScoreRow(label: "Rhythm", score: metrics.breakdown.rhythm, color: .purple)
                            ScoreRow(label: "Stress", score: metrics.breakdown.stress, color: .orange)
                            ScoreRow(label: "Stress Ratio (LSR)", score: metrics.breakdown.lsr, color: .green)
                            
                            // F0 RMSE (display as error value, lower is better)
                            HStack {
                                Text("Pitch Error (F0 RMSE)")
                                    .font(.system(.body, design: .rounded))
                                Spacer()
                                if metrics.breakdown.f0RMSE.isInfinite {
                                    Text("N/A")
                                        .font(.system(.body, design: .rounded).monospacedDigit())
                                        .foregroundColor(.secondary)
                                } else {
                                    Text(String(format: "%.3f", metrics.breakdown.f0RMSE))
                                        .font(.system(.body, design: .rounded).monospacedDigit())
                                        .foregroundColor(metrics.breakdown.f0RMSE < 0.5 ? .green : metrics.breakdown.f0RMSE < 1.0 ? .orange : .red)
                                }
                            }
                            
                            // GOP Score (if available)
                            if let gop = metrics.breakdown.gop {
                                ScoreRow(label: "Pronunciation (GOP)", score: gop, color: .indigo)
                            }
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                    
                Button(action: onDismiss) {
                    Text("Continue")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .cornerRadius(25)
                }
            }
            .padding(30)
            }
            .background(Color(UIColor.systemBackground))
            .cornerRadius(20)
            .shadow(radius: 20)
            .padding(40)
        }
    }
    
    /// Generate target pitch contour for visualization
    private func generateTargetPitch(for phrase: Phrase, length: Int) -> [Float] {
        guard length > 0 else { return [] }
        var target = [Float](repeating: 0, count: length)
        for i in 0..<length {
            let t = Float(i) / Float(max(length - 1, 1))
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
}

struct ScoreRow: View {
    let label: String
    let score: Int
    let color: Color
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(.body, design: .rounded))
            Spacer()
            HStack(spacing: 8) {
                ProgressView(value: Double(score), total: 100)
                    .progressViewStyle(LinearProgressViewStyle(tint: color))
                    .frame(width: 100)
                Text("\(score)%")
                    .font(.system(.body, design: .rounded).monospacedDigit())
                    .foregroundColor(color)
                    .frame(width: 45, alignment: .trailing)
            }
        }
    }
}
