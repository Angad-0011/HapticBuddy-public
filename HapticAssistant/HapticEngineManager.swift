import CoreHaptics
import Foundation
import Combine
import UIKit

class HapticEngineManager: ObservableObject {
    static let shared = HapticEngineManager()
    private var engine: CHHapticEngine?
    
    @Published var isEngineRunning = false
    var intensityMultiplier: Float = 1.0
    var playbackRate: Float = 1.0
    
    private init() {
        prepareHaptics()
        setupObservers()
    }
    
    func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        
        do {
            engine = try CHHapticEngine()
            
            // Handle engine reset
            engine?.resetHandler = { [weak self] in
                print("Haptic engine reset")
                Task { @MainActor in
                    self?.startEngine()
                }
            }
            
            // Handle engine stopped - auto-restart if system kills it
            engine?.stoppedHandler = { [weak self] reason in
                print("⚠️ Haptic engine stopped: \(reason)")
                Task { @MainActor in
                    self?.isEngineRunning = false
                    
                    // Auto-restart engine if it was stopped by the system
                    // CHHapticEngineStoppedReason includes: .audioSessionInterrupt, .applicationSuspended, etc.
                    if reason == .audioSessionInterrupt || 
                       reason == .applicationSuspended ||
                       reason == .systemError {
                        print("🔄 Auto-restarting haptic engine after stop reason: \(reason)")
                        // Small delay to ensure system is ready
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                        self?.startEngine()
                    }
                }
            }
            
            startEngine()
        } catch {
            print("There was an error creating the engine: \(error.localizedDescription)")
        }
    }
    
    func startEngine() {
        guard let engine = engine else { return }
        
        do {
            try engine.start()
            isEngineRunning = true
            print("✅ Haptic engine started successfully")
            
            // Test haptic to verify engine is working
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                self?.testHaptic()
            }
        } catch {
            print("❌ Failed to start haptic engine: \(error)")
            isEngineRunning = false
        }
    }
    
    /// Simple test haptic to verify engine is working
    private func testHaptic() {
        guard let engine = engine, isEngineRunning else { return }
        
        do {
            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                ],
                relativeTime: 0
            )
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
            print("🔔 Test haptic played - if you felt this, engine is working!")
        } catch {
            print("⚠️ Test haptic failed: \(error)")
        }
    }
    
    private func setupObservers() {
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            print("App entering foreground, restarting haptic engine")
            self?.startEngine()
        }
    }
    
    // MARK: - Intonation Patterns
    
    /// Plays a continuous haptic event simulating rising intonation (Question/Uncertainty)
    /// - Parameter duration: Duration of the syllable in seconds
    func playRisingIntonation(duration: TimeInterval) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        
        if !isEngineRunning { startEngine() }
        
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.3 * intensityMultiplier)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
        
        let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [intensity, sharpness], relativeTime: 0, duration: duration)
        
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine?.makeAdvancedPlayer(with: pattern)
            try player?.start(atTime: 0)
            
            // Dynamic modulation: Ramp up intensity and sharpness
            let intensityParameter = CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: 1.0 * intensityMultiplier, relativeTime: duration)
            let sharpnessParameter = CHHapticDynamicParameter(parameterID: .hapticSharpnessControl, value: 0.8, relativeTime: duration)
            
            try player?.sendParameters([intensityParameter, sharpnessParameter], atTime: 0)
            
        } catch {
            print("Failed to play rising intonation: \(error.localizedDescription)")
        }
    }
    
    /// Plays a continuous haptic event simulating falling intonation (Statement/Certainty)
    func playFallingIntonation(duration: TimeInterval) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        
        if !isEngineRunning { startEngine() }
        
        // Start high
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8 * intensityMultiplier)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)
        
        let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [intensity, sharpness], relativeTime: 0, duration: duration)
        
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine?.makeAdvancedPlayer(with: pattern)
            try player?.start(atTime: 0)
            
            // Ramp down
            let intensityParameter = CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: 0.2 * intensityMultiplier, relativeTime: duration)
            let sharpnessParameter = CHHapticDynamicParameter(parameterID: .hapticSharpnessControl, value: 0.1, relativeTime: duration)
            
            try player?.sendParameters([intensityParameter, sharpnessParameter], atTime: 0)
            
        } catch {
            print("Failed to play falling intonation: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Stress & Rhythm Patterns
    
    /// Plays a strong transient followed by a short decay for stressed syllables
    func playStressedSyllable() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        
        if !isEngineRunning { startEngine() }
        
        // Strong transient
        let transientEvent = CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0 * intensityMultiplier),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
        ], relativeTime: 0)
        
        // Short continuous decay
        let continuousEvent = CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5 * intensityMultiplier),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4)
        ], relativeTime: 0.01, duration: 0.15)
        
        do {
            let pattern = try CHHapticPattern(events: [transientEvent, continuousEvent], parameters: [])
            let player = try engine?.makePlayer(with: pattern)
            try player?.start(atTime: 0)
        } catch {
            print("Failed to play stressed syllable: \(error.localizedDescription)")
        }
    }
    
    /// Plays a weak transient for unstressed syllables
    func playUnstressedSyllable() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        
        if !isEngineRunning { startEngine() }
        
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.3 * intensityMultiplier),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
        ], relativeTime: 0)
        
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine?.makePlayer(with: pattern)
            try player?.start(atTime: 0)
        } catch {
            print("Failed to play unstressed syllable: \(error.localizedDescription)")
        }
    }

    // MARK: - Advanced Pattern Playback
    
    private var activePlayer: CHHapticAdvancedPatternPlayer?
    
    // ... (existing code)

    /// Plays a complete haptic pattern for a phrase, synchronized with audio.
    /// Uses improved pattern generation for more natural, sentence-appropriate haptics.
    /// - Parameter phrase: The phrase to generate haptics for
    /// - Parameter startDelay: Optional delay in seconds to sync with audio (default: 0)
    /// - Parameter actualAudioDuration: Actual duration of the audio file (if available, used for precise timing)
    func playPhrasePattern(phrase: Phrase, startDelay: TimeInterval = 0, actualAudioDuration: TimeInterval? = nil) async throws {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            print("⚠️ Haptics not supported on this device")
            return
        }
        
        guard let engine = engine else {
            print("⚠️ Haptic engine not initialized")
            return
        }
        
        // Ensure engine is running - restart if needed
        if !isEngineRunning {
            print("🔄 Haptic engine not running, starting...")
            startEngine()
            // Wait for engine to start asynchronously (avoid blocking UI thread)
            // Use Task.sleep instead of DispatchQueue
            try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
        }
        
        // Double-check engine is running before playing
        guard isEngineRunning else {
            print("⚠️ Haptic engine failed to start")
            return
        }
        
        print("✅ Playing haptics for phrase: \(phrase.text) (condition check should happen in caller)")
        
        // Stop any currently playing pattern
        do {
            try activePlayer?.stop(atTime: CHHapticTimeImmediate)
        } catch {
            // Ignore errors when stopping
        }
        
        // Use the improved pattern generator with actual audio duration if available
        let (events, curves) = HapticPatternGenerator.generatePattern(
            for: phrase,
            intensityMultiplier: intensityMultiplier,
            playbackRate: playbackRate,
            actualAudioDuration: actualAudioDuration
        )
        
        print("📊 Generated \(events.count) haptic events, \(curves.count) parameter curves")
        
        guard !events.isEmpty else {
            print("⚠️ Warning: No haptic events generated for phrase")
            return
        }
        
        // Log first few events for debugging
        if events.count > 0 {
            let firstEvent = events[0]
            print("📝 First event: time=\(firstEvent.relativeTime), duration=\(firstEvent.duration)")
        }
        
        // Create and play the pattern
        do {
            let pattern = try CHHapticPattern(events: events, parameterCurves: curves)
            print("✅ Pattern created successfully")
            
            let player = try engine.makeAdvancedPlayer(with: pattern)
            activePlayer = player
            print("✅ Advanced player created successfully")
            
            // Start with optional delay for synchronization
            // Note: CoreHaptics requires startTime >= 0.0, so we can't use negative delays
            // Instead, we start haptics immediately and delay audio playback
            let startTime: TimeInterval
            if startDelay > 0 {
                // Positive delay: start haptics after a delay
                startTime = CHHapticTimeImmediate + startDelay
                print("⏰ Starting haptics \(startDelay * 1000)ms AFTER immediate")
            } else {
                // Start immediately (negative delays are handled by delaying audio instead)
                startTime = CHHapticTimeImmediate
                if startDelay < 0 {
                    print("⏰ Starting haptics immediately (audio will be delayed by \(abs(startDelay) * 1000)ms to sync)")
                } else {
                    print("⏰ Starting haptics immediately (no delay)")
                }
            }
            
            // Ensure startTime is non-negative (CoreHaptics requirement)
            let safeStartTime = max(0.0, startTime)
            try player.start(atTime: safeStartTime)
            print("🎯 Haptic player started at time: \(startTime)")
            
            // Verify player is actually playing
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                if self?.activePlayer != nil {
                    print("✅ Haptic player still active after 100ms")
                } else {
                    print("⚠️ Haptic player stopped unexpectedly")
                }
            }
            
        } catch {
            print("❌ Error creating/starting haptic pattern: \(error.localizedDescription)")
            print("   Error details: \(error)")
            throw error
        }
    }
    
    /// Stops the currently playing haptic pattern
    func stopPattern() {
        do {
            try activePlayer?.stop(atTime: CHHapticTimeImmediate)
        } catch {
            print("Failed to stop haptic pattern: \(error)")
        }
        activePlayer = nil
    }
    
    /// Updates the intensity of the currently playing pattern in real-time.
    /// Useful for "Practice Mode" where mic input modulates haptics.
    func updateIntensity(_ intensity: Float) {
        guard let player = activePlayer else { return }
        
        // Map 0.0-1.0 to a reasonable range (e.g., 0.5 to 1.5 multiplier)
        // We don't want to kill the haptics completely if they speak softly
        let dynamicValue = 0.5 + (intensity * 1.0)
        
        let parameter = CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: dynamicValue, relativeTime: 0)
        
        do {
            try player.sendParameters([parameter], atTime: 0)
        } catch {
            print("Failed to update intensity: \(error)")
        }
    }
    
    // MARK: - Feedback Patterns
    
    func playSuccessFeedback() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        
        if !isEngineRunning { startEngine() }
        
        let event1 = CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8 * intensityMultiplier),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9)
        ], relativeTime: 0)
        
        let event2 = CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0 * intensityMultiplier),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9)
        ], relativeTime: 0.1)
        
        do {
            let pattern = try CHHapticPattern(events: [event1, event2], parameters: [])
            let player = try engine?.makePlayer(with: pattern)
            try player?.start(atTime: 0)
        } catch {
            print("Failed to play success feedback: \(error.localizedDescription)")
        }
    }
}
