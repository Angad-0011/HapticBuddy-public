import SwiftUI

struct RecordingQualityAlertView: View {
    @Binding var isPresented: Bool
    let message: String
    let onRetry: () -> Void
    let onContinue: () -> Void
    let allowContinue: Bool // Whether to allow continuing despite poor quality
    
    var body: some View {
        if isPresented {
            ZStack {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        // Don't dismiss on background tap
                    }
                
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .resizable()
                        .frame(width: 50, height: 50)
                        .foregroundColor(.orange)
                    
                    Text("Recording Quality Check")
                        .font(.headline)
                    
                    ScrollView {
                        Text(message)
                            .font(.body)
                            .multilineTextAlignment(.leading)
                            .padding()
                    }
                    .frame(maxHeight: 200)
                    
                    HStack(spacing: 15) {
                        if allowContinue {
                            Button("Continue Anyway") {
                                onContinue()
                                isPresented = false
                            }
                            .padding()
                            .background(Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        
                        Button("Record Again") {
                            onRetry()
                            isPresented = false
                        }
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .font(.system(size: 17, weight: .semibold))
                    }
                }
                .padding(25)
                .background(Color(UIColor.systemBackground))
                .cornerRadius(20)
                .shadow(radius: 20)
                .padding(40)
            }
        }
    }
}

