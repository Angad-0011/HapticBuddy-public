import SwiftUI

/// Mini visualization showing target vs. user pitch contours
struct PitchContourVisualization: View {
    let userPitch: [Float] // Normalized pitch values (0-1, or -1 for silence)
    let targetPitch: [Float] // Target pitch values (0-1)
    let intonationType: IntonationType
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pitch Contour")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
            
            GeometryReader { geometry in
                ZStack {
                    // Background grid
                    Path { path in
                        let width = geometry.size.width
                        let height = geometry.size.height
                        
                        // Horizontal grid lines
                        for i in 0...4 {
                            let y = height * CGFloat(i) / 4.0
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: width, y: y))
                        }
                    }
                    .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                    
                    // Target pitch contour (dashed line)
                    if !targetPitch.isEmpty {
                        Path { path in
                            let width = geometry.size.width
                            let height = geometry.size.height
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
                            Color.blue.opacity(0.6),
                            style: StrokeStyle(
                                lineWidth: 2,
                                lineCap: .round,
                                lineJoin: .round,
                                dash: [5, 3]
                            )
                        )
                    }
                    
                    // User pitch contour (solid line)
                    let validUserPitch = userPitch.filter { $0 >= 0 && !$0.isNaN && !$0.isInfinite }
                    if !validUserPitch.isEmpty {
                        Path { path in
                            let width = geometry.size.width
                            let height = geometry.size.height
                            let stepX = width / CGFloat(max(validUserPitch.count - 1, 1))
                            
                            for (index, pitch) in validUserPitch.enumerated() {
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
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                        )
                    }
                }
            }
            .frame(height: 80)
            .background(Color(UIColor.tertiarySystemBackground))
            .cornerRadius(8)
            
            // Legend
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Rectangle()
                        .fill(Color.green)
                        .frame(width: 20, height: 2)
                    Text("Your pitch")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 4) {
                    Rectangle()
                        .fill(Color.blue.opacity(0.6))
                        .frame(width: 20, height: 2)
                        .overlay(
                            Rectangle()
                                .stroke(Color.blue.opacity(0.6), lineWidth: 1)
                                .frame(width: 20, height: 2)
                        )
                    Text("Target")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

