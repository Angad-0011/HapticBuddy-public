import SwiftUI

struct PitchComparisonOverlay: View {
    var pitchHistory: [Float]
    var intonationType: IntonationType
    
    var body: some View {
        GeometryReader { geometry in
            // Draw User Pitch Path
            // Filter out invalid pitch values (NaN, infinite, or negative values used for silence)
            let validPitchHistory = pitchHistory.filter { $0 >= 0 && !$0.isNaN && !$0.isInfinite }
            
            let width = geometry.size.width
            let height = geometry.size.height
            
            // Guard against invalid geometry sizes
            if !validPitchHistory.isEmpty && width > 0 && height > 0 && !width.isNaN && !width.isInfinite && !height.isNaN && !height.isInfinite {
                Path { path in
                    let stepX = width / CGFloat(max(validPitchHistory.count, 1))
                    
                    // Validate stepX
                    guard !stepX.isNaN && !stepX.isInfinite && stepX > 0 else {
                        return
                    }
                    
                    var hasValidPoint = false
                    
                    for (index, pitch) in validPitchHistory.enumerated() {
                        // Clamp pitch to valid range [0, 1]
                        let clampedPitch = max(0.0, min(1.0, pitch))
                        let x = CGFloat(index) * stepX
                        // Map pitch (0-1) to height (bottom-up)
                        // 0.0 -> height (bottom), 1.0 -> 0 (top)
                        let y = height - (CGFloat(clampedPitch) * height)
                        
                        // Ensure coordinates are valid
                        guard !x.isNaN && !x.isInfinite && !y.isNaN && !y.isInfinite else {
                            continue
                        }
                        
                        let point = CGPoint(x: x, y: y)
                        guard !point.x.isNaN && !point.y.isNaN && !point.x.isInfinite && !point.y.isInfinite else {
                            continue
                        }
                        
                        if !hasValidPoint {
                            path.move(to: point)
                            hasValidPoint = true
                        } else {
                            path.addLine(to: point)
                        }
                    }
                }
                .stroke(
                    Color.green,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                )
                .shadow(color: .green.opacity(0.5), radius: 4, x: 0, y: 0)
            } else {
                // Return empty path if geometry or data is invalid
                Path { _ in }
                    .stroke(Color.clear, lineWidth: 0)
            }
        }
    }
}
