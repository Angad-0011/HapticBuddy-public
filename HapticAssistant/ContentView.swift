import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = HapticViewModel()
    @State private var showingSettings = false
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    
    // Custom Colors
    let bgGradient = LinearGradient(
        gradient: Gradient(colors: [Color(UIColor.systemGroupedBackground), Color(UIColor.systemBackground)]),
        startPoint: .top,
        endPoint: .bottom
    )
    
    var body: some View {
        NavigationView {
            ZStack {
                bgGradient.ignoresSafeArea()
                
                VStack(spacing: 25) {
                // Header
                HStack {
                    VStack(alignment: .leading) {
                        Text("Haptic Assistant")
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                            .foregroundColor(.primary)
                        Text("Learn intonation through touch")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Stats View
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(viewModel.progressManager.getAverageScore())%")
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .foregroundColor(.blue)
                        Text("Avg Score")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.white)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                    .onTapGesture {
                        showingSettings = true
                    }
                }
                .padding(.horizontal)
                .padding(.top, 20)
                .sheet(isPresented: $showingSettings) {
                    SettingsView(viewModel: viewModel)
                }
                    
                // Phrases List
                GeometryReader { geo in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 20) {
                            ForEach(viewModel.phrases) { phrase in
                                PhraseCard(
                                    phrase: phrase,
                                    isSelected: viewModel.currentPhrase?.id == phrase.id,
                                    width: {
                                        let calculatedWidth = geo.size.width * 0.45
                                        // Guard against NaN or invalid width
                                        if calculatedWidth.isNaN || calculatedWidth.isInfinite || calculatedWidth <= 0 {
                                            return 150 // Default width
                                        }
                                        return calculatedWidth
                                    }()
                                )
                                    .onTapGesture {
                                        withAnimation {
                                            viewModel.selectPhrase(phrase)
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                }
                .frame(height: 160) // Constrain height for GeometryReader
                    
                    Spacer()
                    
                    // Active Phrase Display
                    if let phrase = viewModel.currentPhrase {
                        VStack(spacing: 30) {
                            // Phrase text without background
                            Text(phrase.text)
                                .font(.system(size: 32, weight: .semibold, design: .rounded))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                                .transition(.opacity.combined(with: .scale))
                                .id("phraseText" + phrase.id) // Force transition on change
                            
                            // Real-time pitch contour overlay (during recording)
                            if viewModel.isRecording, let phrase = viewModel.currentPhrase {
                                // Estimate expected length based on phrase duration
                                let expectedLength = Int(phrase.syllableDurations.reduce(0, +) * 10) // ~10 samples per second
                                let targetPitch = generateTargetPitchContour(for: phrase, expectedLength: max(expectedLength, 50))
                                
                                RealTimePitchContourView(
                                    targetPitch: targetPitch,
                                        intonationType: phrase.intonationType
                                    )
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                            } else {
                                // Visualizer - improved design (when not recording)
                                VisualizerView(overrideAmplitude: viewModel.isRecording ? viewModel.micLevel : nil)
                                    .frame(height: 80)
                                    .padding(.horizontal, 20)
                            }
                            
                            Text(viewModel.feedbackMessage)
                                .font(.system(.headline, design: .rounded))
                                .foregroundColor(viewModel.feedbackMessage.contains("Great") || viewModel.feedbackMessage.contains("Excellent") ? .green : .secondary)
                                .lineLimit(3)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill(viewModel.feedbackMessage.contains("Great") || viewModel.feedbackMessage.contains("Excellent") ? Color.green.opacity(0.1) : Color.clear)
                                )
                                .animation(.easeInOut, value: viewModel.feedbackMessage)
                        }
                    }
                    
                    Spacer()
                    
                    // Controls
                    HStack(spacing: 30) {
                        // Play Button
                        Button(action: {
                            viewModel.playPhrase()
                        }) {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(Color.blue)
                                        .frame(width: 60, height: 60)
                                        .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
                                    
                                    Image(systemName: "speaker.wave.2.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(.white)
                                }
                                
                                Text("Listen")
                                    .font(.system(.caption, design: .rounded).weight(.medium))
                                    .foregroundColor(.primary)
                            }
                        }
                        .disabled(viewModel.isPlaying || viewModel.isRecording)
                        .opacity(viewModel.isPlaying || viewModel.isRecording ? 0.6 : 1.0)
                        
                        // Speed Selector
                        Menu {
                            Button("0.5x") { viewModel.playbackRate = 0.5 }
                            Button("0.75x") { viewModel.playbackRate = 0.75 }
                            Button("1.0x") { viewModel.playbackRate = 1.0 }
                        } label: {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 50, height: 50)
                                        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
                                    
                                    Text({
                                        let rate = viewModel.playbackRate
                                        if rate.isNaN || rate.isInfinite {
                                            return "1.0x"
                                        }
                                        return String(format: "%.2gx", rate)
                                    }())
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundColor(.blue)
                                }
                                
                                Text("Speed")
                                    .font(.system(.caption, design: .rounded).weight(.medium))
                                    .foregroundColor(.primary)
                            }
                        }
                        

                        
                        // Record Button
                        Button(action: {
                            withAnimation(.easeInOut) {
                                viewModel.toggleRecording()
                            }
                        }) {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(viewModel.isRecording ? Color.red.opacity(0.1) : Color.red.opacity(0.05))
                                        .frame(width: 80, height: 80)
                                        .scaleEffect({
                                            let scale: CGFloat = viewModel.isRecording ? 1.1 : 1.0
                                            return scale.isNaN || scale.isInfinite ? 1.0 : scale
                                        }())
                                    
                                    Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                                        .font(.system(size: 32))
                                        .foregroundColor(.red)
                                }
                                .shadow(color: .red.opacity(0.2), radius: 10, x: 0, y: 5)
                                
                                Text(viewModel.isRecording ? "Stop" : "Speak")
                                    .font(.system(.caption, design: .rounded).weight(.medium))
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                    .padding(.bottom, 50)
                }
            }
            .navigationBarHidden(true)
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView()
            }
            
            if viewModel.showScorePopup {
                ScorePopupView(
                    score: viewModel.lastScore,
                    metrics: viewModel.lastMetrics,
                    phrase: viewModel.currentPhrase,
                    userPitchHistory: viewModel.lastPitchHistory.isEmpty ? nil : viewModel.lastPitchHistory
                ) {
                    withAnimation {
                        viewModel.showScorePopup = false
                    }
                }
                .transition(.opacity)
                .zIndex(100)
            }
        }
    }
}

struct PhraseCard: View {
    let phrase: Phrase
    let isSelected: Bool
    let width: CGFloat
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(phrase.text)
                .font(.system(.headline, design: .rounded))
                .foregroundColor(isSelected ? .white : .primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
            
            HStack {
                Image(systemName: phrase.intonationType == .rising ? "arrow.up.forward" : "arrow.down.forward")
                Text(phrase.intonationType == .rising ? "Rising" : "Falling")
            }
            .font(.system(.caption, design: .rounded).weight(.medium))
            .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.white.opacity(0.2) : Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
        .padding(16)
        .frame(width: width, height: 120)
        .background(
            ZStack {
                if isSelected {
                    LinearGradient(gradient: Gradient(colors: [Color.blue, Color.purple]), startPoint: .topLeading, endPoint: .bottomTrailing)
                } else {
                    Color.white
                }
            }
        )
        .cornerRadius(20)
        .shadow(color: isSelected ? Color.blue.opacity(0.3) : Color.black.opacity(0.05), radius: 15, x: 0, y: 8)
        .scaleEffect({
            let scale: CGFloat = isSelected ? 1.05 : 1.0
            return scale.isNaN || scale.isInfinite ? 1.0 : scale
        }())
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

@main
struct HapticAssistantApp: App {
    init() {
        // Configure audio session once at app launch
        AudioSessionManager.shared.configureAudioSession()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
