import SwiftUI

/// Real-time pitch contour visualization showing target (ghost) and user (live) pitch curves during recording
struct RealTimePitchContourView: View {
    @ObservedObject var micManager = MicrophoneManager.shared
    let targetPitch: [Float] // Target pitch contour (0-1 normalized)
    let intonationType: IntonationType
    
    // Use observed pitch history for real-time updates
    private var userPitch: [Float] {
        micManager.pitchHistory
    }
    
    // Animation and visual properties
    @State private var animationPhase: Double = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title
            HStack {
                Text("Pitch Guide")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                // Legend
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(Color.blue.opacity(0.5))
                            .frame(width: 16, height: 1.5)
                            .overlay(
                                Rectangle()
                                    .stroke(Color.blue.opacity(0.7), lineWidth: 0.5)
                                    .frame(width: 16, height: 1.5)
                            )
                        Text("Target")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(Color.green)
                            .frame(width: 16, height: 2)
                        Text("Your pitch")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            GeometryReader { geometry in
                ZStack {
                    // Background grid
                    drawGrid(width: geometry.size.width, height: geometry.size.height)
                    
                    // Target pitch contour (ghost/dashed line) - always visible
                    if !targetPitch.isEmpty {
                        drawTargetContour(
                            targetPitch: targetPitch,
                            width: geometry.size.width,
                            height: geometry.size.height
                        )
                    }
                    
                    // User pitch contour (solid line) - updates in real-time
                    let validUserPitch = userPitch.filter { $0 >= 0 && !$0.isNaN && !$0.isInfinite }
                    if !validUserPitch.isEmpty {
                        drawUserContour(
                            userPitch: validUserPitch,
                            width: geometry.size.width,
                            height: geometry.size.height
                        )
                    }
                }
            }
            .frame(height: 100)
            .background(Color(UIColor.tertiarySystemBackground))
            .cornerRadius(8)
        }
    }
    
    // MARK: - Drawing Functions
    
    private func drawGrid(width: CGFloat, height: CGFloat) -> some View {
        Path { path in
            // Horizontal grid lines
            for i in 0...4 {
                let y = height * CGFloat(i) / 4.0
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: width, y: y))
            }
        }
        .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
    }
    
    private func drawTargetContour(targetPitch: [Float], width: CGFloat, height: CGFloat) -> some View {
        Path { path in
            let stepX = width / CGFloat(max(targetPitch.count - 1, 1))
            
            for (index, pitch) in targetPitch.enumerated() {
                let clampedPitch = max(0.0, min(1.0, pitch))
                let x = CGFloat(index) * stepX
                let y = height - (CGFloat(clampedPitch) * height)
                
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
        .stroke(
            Color.blue.opacity(0.5),
            style: StrokeStyle(
                lineWidth: 2,
                lineCap: .round,
                lineJoin: .round,
                dash: [6, 4] // Dashed line for ghost effect
            )
        )
    }
    
    private func drawUserContour(userPitch: [Float], width: CGFloat, height: CGFloat) -> some View {
        Path { path in
            let stepX = width / CGFloat(max(userPitch.count - 1, 1))
            
            for (index, pitch) in userPitch.enumerated() {
                let clampedPitch = max(0.0, min(1.0, pitch))
                let x = CGFloat(index) * stepX
                let y = height - (CGFloat(clampedPitch) * height)
                
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
        .stroke(
            Color.green,
            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
        )
        .shadow(color: Color.green.opacity(0.3), radius: 2, x: 0, y: 0)
        .animation(.linear(duration: 0.1), value: userPitch.count) // Smooth updates
    }
}

/// Helper function to generate target pitch contour from phrase
func generateTargetPitchContour(for phrase: Phrase, expectedLength: Int) -> [Float] {
    guard expectedLength > 0 else { return [] }
    
    var target = [Float](repeating: 0, count: expectedLength)
    for i in 0..<expectedLength {
        let t = Float(i) / Float(max(expectedLength - 1, 1))
        switch phrase.intonationType {
        case .rising:
            target[i] = t // 0.0 to 1.0
        case .falling:
            target[i] = 1.0 - t // 1.0 to 0.0
        case .flat:
            target[i] = 0.5 // Constant
        }
    }
    return target
}

