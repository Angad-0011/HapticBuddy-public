import SwiftUI

struct VisualizerView: View {
    @ObservedObject var audioManager = AudioPlayerManager.shared
    var overrideAmplitude: Float? = nil // Allow external control (e.g., from mic)
    
    let numberOfBars = 20
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<20, id: \.self) { index in
                BarView(
                    magnitude: calculateMagnitude(at: index),
                    isPlaying: audioManager.isPlaying || overrideAmplitude != nil,
                    index: index
                )
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }
    
    private func calculateMagnitude(at index: Int) -> Float {
        if let override = overrideAmplitude {
            // Filter out NaN and infinite values
            guard !override.isNaN && !override.isInfinite && override >= 0 else {
                return 0.0
            }
            // Make visualization more responsive to voice changes
            // Use a more dynamic distribution across bars
            let normalizedAmp = min(1.0, max(0.0, override))
            
            // Create a more natural distribution - center bars respond more
            let centerDistance = abs(Float(index) - Float(numberOfBars) / 2.0)
            let centerWeight = 1.0 - (centerDistance / Float(numberOfBars / 2)) * 0.5
            
            // Add frequency-like variation for more natural look
            let frequency = Float(index) * 0.5
            let variation = sin(frequency) * 0.15 + 0.85
            
            // Combine: amplitude affects all bars, but center bars respond more
            let baseMagnitude = normalizedAmp * centerWeight * variation
            
            // Add some randomness based on amplitude for organic feel
            let randomFactor = sin(normalizedAmp * 10.0 + Float(index)) * 0.1
            
            let result = baseMagnitude + randomFactor
            // Ensure result is valid
            return result.isNaN || result.isInfinite ? 0.0 : max(0.0, min(1.0, result))
        } else if !audioManager.fftMagnitudes.isEmpty && index < audioManager.fftMagnitudes.count {
            let magnitude = audioManager.fftMagnitudes[index]
            // Filter out NaN and infinite values
            return magnitude.isNaN || magnitude.isInfinite ? 0.0 : max(0.0, min(1.0, magnitude))
        } else if audioManager.isPlaying {
            // Show a subtle baseline when playing but no FFT data yet
            return 0.15
        } else {
            return 0.0
        }
    }

}

struct BarView: View {
    var magnitude: Float
    var isPlaying: Bool = false
    var index: Int = 0
    
    var body: some View {
        let maxHeight: CGFloat = 80 // Increased for better visibility
        let minHeight: CGFloat = 4
        
        // Filter out NaN and infinite values, clamp to valid range
        let validMagnitude: Float = {
            if magnitude.isNaN || magnitude.isInfinite || magnitude < 0 {
                return 0.0
            }
            return max(0.0, min(1.0, magnitude))
        }()
        
        // Calculate height with safety checks
        let height: CGFloat = {
            let h = CGFloat(validMagnitude) * maxHeight
            if h.isNaN || h.isInfinite {
                return minHeight
            }
            return max(minHeight, h)
        }()
        
        let safeHeight = height
        
        // Enhanced gradient colors
        let gradientColors: [Color]
        if isPlaying {
            // Active: vibrant gradient from purple to cyan
            gradientColors = [
                Color(red: 0.6, green: 0.2, blue: 1.0), // Purple
                Color(red: 0.2, green: 0.8, blue: 1.0)   // Cyan
            ]
        } else {
            // Idle: subtle gray gradient
            gradientColors = [
                Color.gray.opacity(0.4),
                Color.gray.opacity(0.2)
            ]
        }
        
        return RoundedRectangle(cornerRadius: 4)
            .fill(LinearGradient(
                gradient: Gradient(colors: gradientColors),
                startPoint: .bottom,
                endPoint: .top
            ))
            .frame(width: 8, height: safeHeight) // Wider bars for better visibility
            .shadow(
                color: isPlaying ? Color.purple.opacity(0.4) : Color.clear,
                radius: isPlaying ? 6 : 0,
                x: 0,
                y: isPlaying ? -2 : 0
            )
            .animation(.spring(response: 0.1, dampingFraction: 0.7), value: safeHeight) // Faster, more responsive
    }
}

struct VisualizerView_Previews: PreviewProvider {
    static var previews: some View {
        VisualizerView()
    }
}
