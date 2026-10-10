import SwiftUI

struct ParticipantResultsView: View {
    @StateObject private var experimentManager = ExperimentManager.shared
    @State private var selectedParticipant: String? = nil
    @State private var sortOption: SortOption = .userId
    @State private var filterPhase: String? = nil
    @State private var showExportFormatSelection = false
    @State private var showDeleteConfirmation = false
    @State private var userToDelete: String? = nil
    
    enum SortOption: String, CaseIterable {
        case userId = "User ID"
        case averageScore = "Average Score"
        case proficiency = "Proficiency"
        case date = "Date"
    }
    
    var body: some View {
        NavigationView {
            VStack {
                // Filters and sorting
                HStack {
                    Picker("Sort by", selection: $sortOption) {
                        ForEach(SortOption.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    Picker("Phase", selection: $filterPhase) {
                        Text("All Phases").tag(nil as String?)
                        Text("Pre-Test").tag("PreTest" as String?)
                        Text("Training").tag("Training" as String?)
                        Text("Post-Test").tag("PostTest" as String?)
                    }
                    .pickerStyle(.menu)
                }
                .padding()
                
                // Participant list
                if participants.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No participants yet")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Participants will appear here after they complete the experiment")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(participants, id: \.userId) { participant in
                            ParticipantRowView(
                                participant: participant,
                                isExpanded: selectedParticipant == participant.userId,
                                onDelete: {
                                    deleteUserData(userId: participant.userId)
                                }
                            ) {
                                withAnimation {
                                    if selectedParticipant == participant.userId {
                                        selectedParticipant = nil
                                    } else {
                                        selectedParticipant = participant.userId
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Participant Results")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Export All") {
                        showExportFormatSelection = true
                    }
                }
            }
            .sheet(isPresented: $showExportFormatSelection) {
                ExportFormatSelectionView(isPresented: $showExportFormatSelection) { format in
                    exportAllData(format: format)
                }
            }
            .alert("Delete Participant Data", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    userToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    confirmDelete()
                }
            } message: {
                if let userId = userToDelete {
                    Text("Are you sure you want to delete all data for participant '\(userId)'? This will permanently delete all trial logs, metadata, recordings, and session data. This action cannot be undone.")
                } else {
                    Text("Are you sure you want to delete this participant's data? This action cannot be undone.")
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    var participants: [ParticipantSummary] {
        var summaries: [ParticipantSummary] = []
        
        // Get all unique user IDs from logs and metadata
        let allUserIds = Set(experimentManager.logs.map { $0.userId } + experimentManager.participantMetadata.keys)
        
        for userId in allUserIds {
            let metadata = experimentManager.participantMetadata[userId]
            let userLogs = experimentManager.logs.filter { $0.userId == userId }
            
            // Filter by phase if selected
            let filteredLogs = filterPhase != nil
                ? userLogs.filter { $0.phase == filterPhase }
                : userLogs
            
            if !filteredLogs.isEmpty || metadata != nil {
                let summary = ParticipantSummary(
                    userId: userId,
                    metadata: metadata,
                    logs: filteredLogs
                )
                summaries.append(summary)
            }
        }
        
        // Sort
        switch sortOption {
        case .userId:
            summaries.sort { $0.userId < $1.userId }
        case .averageScore:
            summaries.sort { $0.averageScore > $1.averageScore }
        case .proficiency:
            summaries.sort { $0.proficiencyLevel.rawValue < $1.proficiencyLevel.rawValue }
        case .date:
            summaries.sort { $0.lastActivityDate > $1.lastActivityDate }
        }
        
        return summaries
    }
    
    // MARK: - Functions
    
    func exportAllData(format: ExperimentManager.ExportFormat = .all) {
        if let topVC = findTopViewController() {
            experimentManager.exportData(from: topVC, userId: nil, format: format)
        }
    }
    
    func deleteUserData(userId: String) {
        userToDelete = userId
        showDeleteConfirmation = true
    }
    
    func confirmDelete() {
        guard let userId = userToDelete else { return }
        experimentManager.deleteUserData(userId: userId)
        userToDelete = nil
        showDeleteConfirmation = false
        
        // Deselect if the deleted user was selected
        if selectedParticipant == userId {
            selectedParticipant = nil
        }
    }
    
    func findTopViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else {
            return nil
        }
        
        var topViewController = rootViewController
        while let presented = topViewController.presentedViewController {
            topViewController = presented
        }
        
        if let navController = topViewController as? UINavigationController {
            return navController.topViewController ?? navController
        }
        
        if let tabController = topViewController as? UITabBarController {
            if let selected = tabController.selectedViewController {
                return findTopViewController(from: selected)
            }
        }
        
        return topViewController
    }
    
    private func findTopViewController(from viewController: UIViewController) -> UIViewController {
        if let navController = viewController as? UINavigationController {
            return navController.topViewController ?? navController
        }
        if let tabController = viewController as? UITabBarController {
            if let selected = tabController.selectedViewController {
                return findTopViewController(from: selected)
            }
        }
        return viewController
    }
}

// MARK: - Participant Summary

struct ParticipantSummary {
    let userId: String
    let metadata: ParticipantMetadata?
    let logs: [TrialLog]
    
    var proficiencyLevel: ParticipantMetadata.ProficiencyLevel {
        metadata?.englishProficiency ?? .intermediate
    }
    
    var nativeLanguage: String {
        metadata?.nativeLanguage ?? "Unknown"
    }
    
    var averageScore: Double {
        let scores = logs.compactMap { $0.metrics["final_score"] }
        guard !scores.isEmpty else { return 0.0 }
        return scores.reduce(0, +) / Double(scores.count)
    }
    
    var preTestScore: Double? {
        let preTestLogs = logs.filter { $0.phase == "PreTest" }
        return preTestLogs.compactMap { $0.metrics["final_score"] }.first
    }
    
    var postTestScore: Double? {
        let postTestLogs = logs.filter { $0.phase == "PostTest" }
        let scores = postTestLogs.compactMap { $0.metrics["final_score"] }
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }
    
    var improvement: Double? {
        guard let pre = preTestScore, let post = postTestScore else { return nil }
        return post - pre
    }
    
    var totalTrials: Int {
        logs.count
    }
    
    var lastActivityDate: Date {
        logs.map { $0.timestamp }.max() ?? Date()
    }
    
    var phaseBreakdown: [String: Int] {
        var breakdown: [String: Int] = [:]
        for log in logs {
            breakdown[log.phase, default: 0] += 1
        }
        return breakdown
    }
    
    var metricsBreakdown: [String: Double] {
        var metrics: [String: Double] = [:]
        let allKeys = Set(logs.flatMap { $0.metrics.keys })
        
        for key in allKeys {
            let values = logs.compactMap { $0.metrics[key] }
            guard !values.isEmpty else { continue }
            metrics[key] = values.reduce(0, +) / Double(values.count)
        }
        
        return metrics
    }
}

// MARK: - Participant Row View

struct ParticipantRowView: View {
    let participant: ParticipantSummary
    let isExpanded: Bool
    let onDelete: () -> Void
    let onTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header (always visible) - tappable area
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(participant.userId)
                        .font(.headline)
                    
                    if let metadata = participant.metadata {
                        Text("\(metadata.nativeLanguage) • \(participant.proficiencyLevel.rawValue)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(Int(participant.averageScore))%")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(scoreColor(participant.averageScore))
                    
                    Text("\(participant.totalTrials) trials")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onTap()
            }
            
            // Expanded details
            if isExpanded {
                Divider()
                
                VStack(alignment: .leading, spacing: 12) {
                    // Score breakdown
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Score Breakdown")
                            .font(.system(size: 15, weight: .semibold))
                        
                        HStack(spacing: 20) {
                            if let preTest = participant.preTestScore {
                                VStack(alignment: .leading) {
                                    Text("Pre-Test")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(Int(preTest))%")
                                        .font(.headline)
                                }
                            }
                            
                            if let postTest = participant.postTestScore {
                                VStack(alignment: .leading) {
                                    Text("Post-Test")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(Int(postTest))%")
                                        .font(.headline)
                                }
                            }
                            
                            if let improvement = participant.improvement {
                                VStack(alignment: .leading) {
                                    Text("Improvement")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(improvement >= 0 ? "+" : "")\(Int(improvement))%")
                                        .font(.headline)
                                        .foregroundColor(improvement >= 0 ? .green : .red)
                                }
                            }
                        }
                    }
                    
                    // Phase breakdown
                    if !participant.phaseBreakdown.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Trials by Phase")
                                .font(.system(size: 15, weight: .semibold))
                            
                            ForEach(Array(participant.phaseBreakdown.keys.sorted()), id: \.self) { phase in
                                HStack {
                                    Text(phase)
                                        .font(.caption)
                                    Spacer()
                                    Text("\(participant.phaseBreakdown[phase] ?? 0)")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                            }
                        }
                    }
                    
                    // Detailed metrics
                    if !participant.metricsBreakdown.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Average Metrics")
                                .font(.system(size: 15, weight: .semibold))
                            
                            ForEach(["dtw_score", "rhythm_score", "stress_score", "lsr_score", "gop_score"], id: \.self) { key in
                                if let value = participant.metricsBreakdown[key] {
                                    HStack {
                                        Text(metricName(key))
                                            .font(.caption)
                                        Spacer()
                                        Text("\(Int(value))%")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(scoreColor(value))
                                    }
                                }
                            }
                        }
                    }
                    
                    // Metadata
                    if let metadata = participant.metadata {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Participant Info")
                                .font(.system(size: 15, weight: .semibold))
                            
                            if let age = metadata.age {
                                Text("Age: \(age)")
                                    .font(.caption)
                            }
                            
                            if let years = metadata.yearsOfEnglishStudy {
                                Text("Years of English: \(years)")
                                    .font(.caption)
                            }
                        }
                    }
                    
                    // Delete button
                    Divider()
                    
                    HStack {
                        Spacer()
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Participant Data")
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.red)
                        .cornerRadius(8)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onDelete()
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(.vertical, 8)
    }
    
    private func scoreColor(_ score: Double) -> Color {
        if score >= 80 { return .green }
        if score >= 60 { return .orange }
        return .red
    }
    
    private func metricName(_ key: String) -> String {
        switch key {
        case "dtw_score": return "Intonation"
        case "rhythm_score": return "Rhythm"
        case "stress_score": return "Stress"
        case "lsr_score": return "Stress Ratio (LSR)"
        case "gop_score": return "Pronunciation (GOP)"
        default: return key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

