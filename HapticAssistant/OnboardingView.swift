import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var hapticManager = HapticEngineManager.shared
    @State private var currentStep = 0
    @State private var isPlayingHaptic = false
    
    // Example phrases for each intonation type
    private let examplePhrases: [OnboardingStep] = [
        OnboardingStep(
            title: "Welcome to Haptic Learning",
            description: "You'll learn to feel pronunciation patterns through vibrations. Let's start!",
            phrase: nil,
            intonationType: nil,
            isIntroduction: true
        ),
        OnboardingStep(
            title: "Rising Intonation ↗️",
            description: "Rising intonation feels like vibrations getting stronger and higher. It's used in questions.",
            phrase: Phrase(
                id: "onboarding_rising",
                text: "How are you?",
                audioFileName: "",
                intonationType: .rising,
                stressIndices: [1, 3],
                syllableDurations: [0.3, 0.2, 0.3, 0.2],
                syllableTextures: nil,
                category: "Onboarding",
                difficulty: nil,
                tags: nil,
                sets: nil,
                syllableTimestamps: nil
            ),
            intonationType: .rising,
            isIntroduction: false
        ),
        OnboardingStep(
            title: "Falling Intonation ↘️",
            description: "Falling intonation feels like vibrations getting softer and lower. It's used in statements.",
            phrase: Phrase(
                id: "onboarding_falling",
                text: "I am doing well.",
                audioFileName: "",
                intonationType: .falling,
                stressIndices: [1, 3],
                syllableDurations: [0.2, 0.3, 0.2, 0.2, 0.4],
                syllableTextures: nil,
                category: "Onboarding",
                difficulty: nil,
                tags: nil,
                sets: nil,
                syllableTimestamps: nil
            ),
            intonationType: .falling,
            isIntroduction: false
        ),
        OnboardingStep(
            title: "Stressed Syllables 💪",
            description: "Stressed syllables feel stronger and longer. Try to feel the difference!",
            phrase: Phrase(
                id: "onboarding_stress",
                text: "Hello, how are you?",
                audioFileName: "",
                intonationType: .rising,
                stressIndices: [1, 4],
                syllableDurations: [0.2, 0.3, 0.2, 0.2, 0.4],
                syllableTextures: nil,
                category: "Onboarding",
                difficulty: nil,
                tags: nil,
                sets: nil,
                syllableTimestamps: nil
            ),
            intonationType: .rising,
            isIntroduction: false
        ),
        OnboardingStep(
            title: "Try Matching the Pattern",
            description: "Listen to the phrase and try to match the haptic pattern you feel.",
            phrase: Phrase(
                id: "onboarding_practice",
                text: "Nice to meet you.",
                audioFileName: "",
                intonationType: .falling,
                stressIndices: [0, 3],
                syllableDurations: [0.3, 0.1, 0.2, 0.3],
                syllableTextures: nil,
                category: "Onboarding",
                difficulty: nil,
                tags: nil,
                sets: nil,
                syllableTimestamps: nil
            ),
            intonationType: .falling,
            isIntroduction: false
        )
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.blue.opacity(0.1),
                        Color.purple.opacity(0.1)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 30) {
                    // Progress indicator
                    ProgressView(value: Double(currentStep + 1), total: Double(examplePhrases.count))
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                        .padding(.horizontal, 40)
                        .padding(.top, 20)
                    
                    // Content
                    if currentStep < examplePhrases.count {
                        let step = examplePhrases[currentStep]
                        
                        VStack(spacing: 25) {
                            // Title
                            Text(step.title)
                                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            
                            // Description
                            Text(step.description)
                                .font(.system(.body, design: .rounded))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 30)
                            
                            // Phrase display (if not introduction)
                            if let phrase = step.phrase, !step.isIntroduction {
                                VStack(spacing: 20) {
                                    // Phrase text
                                    Text(phrase.text)
                                        .font(.system(.title2, design: .rounded).weight(.medium))
                                        .padding()
                                        .frame(maxWidth: .infinity)
                                        .background(Color.white)
                                        .cornerRadius(16)
                                        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                                    
                                    // Haptic preview button
                                    Button(action: {
                                        playHapticPreview(for: phrase)
                                    }) {
                                        HStack(spacing: 12) {
                                            Image(systemName: isPlayingHaptic ? "pause.circle.fill" : "hand.tap.fill")
                                                .font(.title2)
                                            Text(isPlayingHaptic ? "Playing..." : "Feel the Pattern")
                                                .font(.system(.headline, design: .rounded))
                                        }
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 30)
                                        .padding(.vertical, 16)
                                        .background(
                                            LinearGradient(
                                                gradient: Gradient(colors: [Color.blue, Color.purple]),
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .cornerRadius(25)
                                        .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
                                    }
                                    .disabled(isPlayingHaptic)
                                    
                                    // Visual indicator
                                    if let intonationType = step.intonationType {
                                        IntonationVisualizer(type: intonationType)
                                            .frame(height: 80)
                                            .padding(.horizontal, 40)
                                    }
                                }
                                .padding(.vertical, 20)
                            }
                            
                            Spacer()
                            
                            // Navigation buttons
                            HStack(spacing: 20) {
                                if currentStep > 0 {
                                    Button("Back") {
                                        withAnimation {
                                            currentStep -= 1
                                        }
                                    }
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 30)
                                    .padding(.vertical, 12)
                                    .background(Color.white)
                                    .cornerRadius(25)
                                }
                                
                                Spacer()
                                
                                Button(currentStep == examplePhrases.count - 1 ? "Get Started" : "Next") {
                                    if currentStep == examplePhrases.count - 1 {
                                        // Mark onboarding as complete
                                        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                                        dismiss()
                                    } else {
                                        withAnimation {
                                            currentStep += 1
                                        }
                                    }
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 30)
                                .padding(.vertical, 12)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.blue, Color.purple]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(25)
                            }
                            .padding(.horizontal, 30)
                            .padding(.bottom, 30)
                        }
                        .padding(.top, 40)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Skip") {
                        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func playHapticPreview(for phrase: Phrase) {
        isPlayingHaptic = true
        
        // Ensure haptic engine is started
        hapticManager.startEngine()
        
        Task { @MainActor in
            do {
                try await hapticManager.playPhrasePattern(phrase: phrase, startDelay: 0)
                
                // Estimate duration from syllable durations
                let duration = phrase.syllableDurations.reduce(0, +)
                
                // Reset button after haptic completes (add buffer for haptic tail)
                try? await Task.sleep(nanoseconds: UInt64((duration + 0.8) * 1_000_000_000))
                isPlayingHaptic = false
            } catch {
                print("Failed to play haptic preview: \(error)")
                isPlayingHaptic = false
            }
        }
    }
}

// MARK: - Supporting Types

struct OnboardingStep {
    let title: String
    let description: String
    let phrase: Phrase?
    let intonationType: IntonationType?
    let isIntroduction: Bool
}

// MARK: - Intonation Visualizer

struct IntonationVisualizer: View {
    let type: IntonationType
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<10, id: \.self) { index in
                RoundedRectangle(cornerRadius: 4)
                    .fill(colorForIndex(index))
                    .frame(width: 8, height: heightForIndex(index))
                    .animation(
                        .easeInOut(duration: 0.3)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.05),
                        value: isAnimating
                    )
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
    
    private func heightForIndex(_ index: Int) -> CGFloat {
        let normalizedIndex = Double(index) / 9.0
        
        switch type {
        case .rising:
            // Rising: starts low, ends high
            return CGFloat(20 + normalizedIndex * 40)
        case .falling:
            // Falling: starts high, ends low
            return CGFloat(60 - normalizedIndex * 40)
        case .flat:
            // Flat: constant height
            return 40
        }
    }
    
    private func colorForIndex(_ index: Int) -> Color {
        let normalizedIndex = Double(index) / 9.0
        
        switch type {
        case .rising:
            // Rising: blue to purple
            return Color.blue.interpolate(to: Color.purple, amount: normalizedIndex)
        case .falling:
            // Falling: purple to blue
            return Color.purple.interpolate(to: Color.blue, amount: normalizedIndex)
        case .flat:
            return Color.gray
        }
    }
}

// MARK: - Color Interpolation Extension

extension Color {
    func interpolate(to: Color, amount: Double) -> Color {
        let amount = max(0, min(1, amount))
        // For visual purposes, we'll use a gradient effect
        // In a real implementation, you'd use proper color space interpolation
        if amount < 0.33 {
            return self
        } else if amount < 0.67 {
            return Color(red: 0.5, green: 0.3, blue: 0.8) // Intermediate purple-blue
        } else {
            return to
        }
    }
}

