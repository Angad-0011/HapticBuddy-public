import SwiftUI

/// Post-trial questionnaire (shown after each trial)
struct PostTrialQuestionnaireView: View {
    let userId: String
    let trialIndex: Int?
    let phase: String?
    let condition: String
    let onComplete: (SubjectiveMetrics) -> Void
    @Environment(\.dismiss) var dismiss
    
    @State private var confidenceRating: Int = 3
    @State private var hapticHelpfulness: Int? = nil
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("How confident do you feel about your pronunciation?")) {
                    Picker("Confidence", selection: $confidenceRating) {
                        ForEach(1...5, id: \.self) { rating in
                            Text(ratingDescription(rating)).tag(rating)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                if condition == "HapticAudio" {
                    Section(header: Text("How helpful were the haptic cues?")) {
                        Picker("Helpfulness", selection: Binding(
                            get: { hapticHelpfulness ?? 3 },
                            set: { hapticHelpfulness = $0 }
                        )) {
                            ForEach(1...5, id: \.self) { rating in
                                Text(ratingDescription(rating)).tag(rating)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                
                Section {
                    Button("Continue") {
                        let metrics = SubjectiveMetrics(
                            userId: userId,
                            trialIndex: trialIndex,
                            phase: phase,
                            confidenceRating: confidenceRating,
                            hapticHelpfulness: condition == "HapticAudio" ? hapticHelpfulness : nil,
                            ueqResponses: nil,
                            openEndedFeedback: nil,
                            timestamp: Date()
                        )
                        onComplete(metrics)
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Quick Feedback")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func ratingDescription(_ rating: Int) -> String {
        switch rating {
        case 1: return "Not at all"
        case 2: return "Slightly"
        case 3: return "Moderately"
        case 4: return "Very"
        case 5: return "Extremely"
        default: return ""
        }
    }
}

/// Post-session questionnaire focused on experiment feedback
struct PostSessionQuestionnaireView: View {
    let userId: String
    let onComplete: (SubjectiveMetrics) -> Void
    @Environment(\.dismiss) var dismiss
    
    @State private var hapticHelpfulness: Int = 3
    @State private var hapticClarity: Int = 3
    @State private var pronunciationImprovement: Int = 3
    @State private var wouldUseAgain: Int = 3
    @State private var overallSatisfaction: Int = 3
    @State private var openEndedFeedback: String = ""
    @State private var showError = false
    @State private var errorMessage = ""
    
    // Experiment-focused questions
    private let experimentQuestions: [(key: String, question: String)] = [
        ("haptic_helpfulness", "How helpful were the haptic cues for learning pronunciation?"),
        ("haptic_clarity", "How clear and understandable were the haptic patterns?"),
        ("pronunciation_improvement", "Do you feel your pronunciation improved during this session?"),
        ("would_use_again", "Would you use this app again for pronunciation practice?"),
        ("overall_satisfaction", "Overall, how satisfied are you with this learning experience?")
    ]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Experiment Feedback"),
                       footer: Text("Please rate each question on a scale from 1 (Not at all) to 5 (Extremely)")) {
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How helpful were the haptic cues for learning pronunciation?")
                            .font(.system(size: 15, weight: .medium))
                        Picker("Haptic Helpfulness", selection: $hapticHelpfulness) {
                            ForEach(1...5, id: \.self) { rating in
                                Text(ratingDescription(rating)).tag(rating)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How clear and understandable were the haptic patterns?")
                            .font(.system(size: 15, weight: .medium))
                        Picker("Haptic Clarity", selection: $hapticClarity) {
                            ForEach(1...5, id: \.self) { rating in
                                Text(ratingDescription(rating)).tag(rating)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Do you feel your pronunciation improved during this session?")
                            .font(.system(size: 15, weight: .medium))
                        Picker("Pronunciation Improvement", selection: $pronunciationImprovement) {
                            ForEach(1...5, id: \.self) { rating in
                                Text(ratingDescription(rating)).tag(rating)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Would you use this app again for pronunciation practice?")
                            .font(.system(size: 15, weight: .medium))
                        Picker("Would Use Again", selection: $wouldUseAgain) {
                            ForEach(1...5, id: \.self) { rating in
                                Text(ratingDescription(rating)).tag(rating)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Overall, how satisfied are you with this learning experience?")
                            .font(.system(size: 15, weight: .medium))
                        Picker("Overall Satisfaction", selection: $overallSatisfaction) {
                            ForEach(1...5, id: \.self) { rating in
                                Text(ratingDescription(rating)).tag(rating)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)
                }
                
                Section(header: Text("Additional Feedback (Optional)")) {
                    TextEditor(text: $openEndedFeedback)
                        .frame(height: 100)
                }
                
                Section {
                    Button("Submit") {
                        // Create responses dictionary
                        var responses: [String: Int] = [:]
                        responses["haptic_helpfulness"] = hapticHelpfulness
                        responses["haptic_clarity"] = hapticClarity
                        responses["pronunciation_improvement"] = pronunciationImprovement
                        responses["would_use_again"] = wouldUseAgain
                        responses["overall_satisfaction"] = overallSatisfaction
                        
                        let metrics = SubjectiveMetrics(
                            userId: userId,
                            trialIndex: nil,
                            phase: "PostSession",
                            confidenceRating: nil,
                            hapticHelpfulness: hapticHelpfulness,
                            ueqResponses: responses,
                            openEndedFeedback: openEndedFeedback.isEmpty ? nil : openEndedFeedback,
                            timestamp: Date()
                        )
                        
                        print("📝 Submitting questionnaire with responses: \(responses)")
                        onComplete(metrics)
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .navigationTitle("Post-Session Questionnaire")
            .navigationBarTitleDisplayMode(.inline)
            .alert(isPresented: $showError) {
                Alert(title: Text("Error"), message: Text(errorMessage), dismissButton: .default(Text("OK")))
            }
        }
    }
    
    private func ratingDescription(_ rating: Int) -> String {
        switch rating {
        case 1: return "Not at all"
        case 2: return "Slightly"
        case 3: return "Moderately"
        case 4: return "Very"
        case 5: return "Extremely"
        default: return ""
        }
    }
}

