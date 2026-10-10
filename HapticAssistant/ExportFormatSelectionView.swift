import SwiftUI

struct ExportFormatSelectionView: View {
    @Binding var isPresented: Bool
    let onExport: (ExperimentManager.ExportFormat) -> Void
    
    @State private var selectedFormat: ExperimentManager.ExportFormat = .all
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Export Format")) {
                    Picker("Format", selection: $selectedFormat) {
                        Text("All Formats (Recommended)").tag(ExperimentManager.ExportFormat.all)
                        Text("CSV Only").tag(ExperimentManager.ExportFormat.csv)
                        Text("SPSS Only").tag(ExperimentManager.ExportFormat.spss)
                        Text("JSON Only").tag(ExperimentManager.ExportFormat.json)
                    }
                }
                
                Section(header: Text("What's Included")) {
                    if selectedFormat == .all || selectedFormat == .csv {
                        Label("Trials CSV - All trial data with metrics", systemImage: "tablecells")
                        Label("Statistics CSV - Participant-level averages", systemImage: "chart.bar")
                        Label("Improvements CSV - Pre-test vs Post-test", systemImage: "arrow.up.right")
                    }
                    
                    if selectedFormat == .all || selectedFormat == .spss {
                        Label("SPSS File - Ready for statistical analysis", systemImage: "doc.text")
                    }
                    
                    if selectedFormat == .all || selectedFormat == .json {
                        Label("JSON File - Original format", systemImage: "doc.json")
                    }
                    
                    Label("Audio Files - All recordings", systemImage: "waveform")
                }
                
                Section(footer: Text("All formats include audio recordings. CSV exports include pre-calculated statistics and improvement metrics.")) {
                    Button(action: {
                        onExport(selectedFormat)
                        isPresented = false
                    }) {
                        HStack {
                            Spacer()
                            Text("Export")
                                .font(.system(size: 17, weight: .semibold))
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Export Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

