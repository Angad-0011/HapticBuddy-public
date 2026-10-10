import SwiftUI

struct IntonationCurveView: View {
    let intonationType: IntonationType
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            
            // Guard against invalid geometry sizes
            if width > 0 && height > 0 && !width.isNaN && !width.isInfinite && !height.isNaN && !height.isInfinite {
                Path { path in
                    switch intonationType {
                    case .rising:
                        // Start Low (0.8), End High (0.2)
                        let startY = height * 0.8
                        let endY = height * 0.2
                        let control1X = width * 0.4
                        let control2X = width * 0.6
                        
                        // Validate all coordinates
                        if !startY.isNaN && !endY.isNaN && !control1X.isNaN && !control2X.isNaN {
                            let start = CGPoint(x: 0, y: startY)
                            let end = CGPoint(x: width, y: endY)
                            let control1 = CGPoint(x: control1X, y: startY)
                            let control2 = CGPoint(x: control2X, y: endY)
                            
                            path.move(to: start)
                            path.addCurve(to: end, control1: control1, control2: control2)
                        }
                        
                    case .falling:
                        // Start High (0.2), End Low (0.8)
                        let startY = height * 0.2
                        let endY = height * 0.8
                        let control1X = width * 0.4
                        let control2X = width * 0.6
                        
                        // Validate all coordinates
                        if !startY.isNaN && !endY.isNaN && !control1X.isNaN && !control2X.isNaN {
                            let start = CGPoint(x: 0, y: startY)
                            let end = CGPoint(x: width, y: endY)
                            let control1 = CGPoint(x: control1X, y: startY)
                            let control2 = CGPoint(x: control2X, y: endY)
                            
                            path.move(to: start)
                            path.addCurve(to: end, control1: control1, control2: control2)
                        }
                        
                    case .flat:
                        // Start Middle, End Middle
                        let middleY = height * 0.5
                        
                        // Validate coordinate
                        if !middleY.isNaN && !middleY.isInfinite {
                            let start = CGPoint(x: 0, y: middleY)
                            let end = CGPoint(x: width, y: middleY)
                            
                            path.move(to: start)
                            path.addLine(to: end)
                        }
                    }
                }
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [.blue.opacity(0.3), .purple.opacity(0.6)]),
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
            } else {
                // Return empty path if geometry is invalid
                Path { _ in }
                    .stroke(Color.clear, lineWidth: 0)
            }
        }
    }
}

struct IntonationCurveView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 50) {
            IntonationCurveView(intonationType: .rising)
                .frame(width: 200, height: 100)
                .border(Color.gray)
            
            IntonationCurveView(intonationType: .falling)
                .frame(width: 200, height: 100)
                .border(Color.gray)
        }
    }
}
