import AVFoundation
import Foundation

/// Centralized audio session management - configures audio session once at app launch
/// to avoid glitches from constantly changing the category
class AudioSessionManager {
    static let shared = AudioSessionManager()
    
    private var isConfigured = false
    
    private init() {}
    
    /// Configure audio session once at app launch
    /// Sets category to .playAndRecord with .defaultToSpeaker for simultaneous playback and recording
    func configureAudioSession() {
        guard !isConfigured else {
            // Already configured, just ensure it's active
            do {
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                print("⚠️ Failed to activate audio session: \(error)")
            }
            return
        }
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // Set category once for the entire app lifecycle
            // .playAndRecord allows simultaneous playback and recording
            // .defaultToSpeaker ensures audio plays through speaker (not earpiece) when recording
            // .allowBluetooth allows Bluetooth audio devices
            try audioSession.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetooth]
            )
            try audioSession.setActive(true)
            isConfigured = true
            print("✅ Audio session configured: .playAndRecord with .defaultToSpeaker")
        } catch {
            print("❌ Failed to configure audio session: \(error)")
        }
    }
    
    /// Deactivate audio session (only if absolutely necessary)
    func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false)
            print("Audio session deactivated")
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
    }
}

