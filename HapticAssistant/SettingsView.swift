import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: HapticViewModel
    @Environment(\.dismiss) var dismiss
    @State private var showingResetAlert = false
    @State private var showingExperiment = false
    @State private var showingResults = false
    @State private var showingOnboarding = false
    @State private var showingCalibration = false
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("General")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    Button(action: {
                        showingOnboarding = true
                    }) {
                        HStack {
                            Image(systemName: "book.fill")
                                .foregroundColor(.blue)
                            Text("Learn Haptic Language")
                                .foregroundColor(.primary)
                        }
                    }
                    .fullScreenCover(isPresented: $showingOnboarding) {
                        OnboardingView()
                    }
                }
                
                Section(header: Text("Customization")) {
                    VStack(alignment: .leading) {
                        Text("Haptic Intensity: \(Int(viewModel.hapticIntensity * 100))%")
                        Slider(value: $viewModel.hapticIntensity, in: 0.0...1.0, step: 0.1)
                    }
                    .padding(.vertical, 4)
                    
                    Button(action: {
                        showingCalibration = true
                    }) {
                        HStack {
                            Image(systemName: "waveform.circle.fill")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Calibrate Audio-Haptic Sync")
                                    .foregroundColor(.primary)
                                if let latency = LatencyCalibrationManager.shared.getStoredCalibration() {
                                    Text("Current: \(String(format: "%.0f", latency * 1000))ms")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Not calibrated")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .sheet(isPresented: $showingCalibration) {
                        CalibrationWizardView()
                    }
                }
                
                Section(header: Text("Data")) {
                    Button(action: {
                        showingResetAlert = true
                    }) {
                        Text("Reset Progress")
                            .foregroundColor(.red)
                    }
                }
                
                Section(header: Text("Experiment")) {
                    Button(action: {
                        showingExperiment = true
                    }) {
                        HStack {
                            Image(systemName: "flask.fill")
                                .foregroundColor(.purple)
                            Text("Enter Experiment Mode")
                                .foregroundColor(.primary)
                        }
                    }
                    .fullScreenCover(isPresented: $showingExperiment) {
                        ExperimentSessionView()
                            .environmentObject(viewModel)
                    }
                    
                    Button(action: {
                        showingResults = true
                    }) {
                        HStack {
                            Image(systemName: "chart.bar.fill")
                                .foregroundColor(.blue)
                            Text("View Participant Results")
                                .foregroundColor(.primary)
                        }
                    }
                    .sheet(isPresented: $showingResults) {
                        ParticipantResultsView()
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert(isPresented: $showingResetAlert) {
                Alert(
                    title: Text("Reset Progress"),
                    message: Text("Are you sure you want to delete all your practice history? This cannot be undone."),
                    primaryButton: .destructive(Text("Reset")) {
                        viewModel.resetProgress()
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }
}
