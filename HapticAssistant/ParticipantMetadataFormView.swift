import SwiftUI
import Darwin

struct ParticipantMetadataFormView: View {
    @Binding var isPresented: Bool
    let onComplete: (ParticipantMetadata) -> Void
    
    @State private var userId: String = ""
    @State private var consentGiven: Bool = false
    
    private var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let modelCode = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0)
            }
        }
        return modelCode ?? "Unknown"
    }
    
    private var iosVersion: String {
        return UIDevice.current.systemVersion
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Participant Information")) {
                    TextField("Name or User ID", text: $userId)
                        .autocapitalization(.none)
                }
                
                Section(header: Text("Consent"),
                       footer: Text("By checking this box, you consent to participate in this research study. Your data will be anonymized and used for research purposes only.")) {
                    Toggle("I consent to participate", isOn: $consentGiven)
                }
                
                Section {
                    Button("Start Experiment") {
                        let metadata = ParticipantMetadata(
                            userId: userId,
                            age: nil,
                            gender: nil,
                            nativeLanguage: "Unknown",
                            englishProficiency: .intermediate,
                            yearsOfEnglishStudy: nil,
                            previousPronunciationTraining: false,
                            deviceModel: deviceModel,
                            iosVersion: iosVersion,
                            consentGiven: consentGiven,
                            timestamp: Date()
                        )
                        onComplete(metadata)
                        isPresented = false
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(userId.isEmpty || !consentGiven)
                }
            }
            .navigationTitle("Participant Information")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

