import Foundation
import CoreHaptics

/// Safe array subscript extension
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

/// Generates sophisticated haptic patterns that better match natural speech
class HapticPatternGenerator {
    
    /// Generates a complete haptic pattern for a phrase with improved naturalness
    /// - Parameters:
    ///   - phrase: The phrase to generate haptics for
    ///   - intensityMultiplier: User-adjustable intensity (0.0-1.0)
    ///   - playbackRate: Speed multiplier (affects timing)
    ///   - actualAudioDuration: Actual duration of the audio file (if available, used for precise timing)
    /// - Returns: Tuple of events and parameter curves for the haptic pattern
    static func generatePattern(
        for phrase: Phrase,
        intensityMultiplier: Float = 1.0,
        playbackRate: Float = 1.0,
        actualAudioDuration: TimeInterval? = nil
    ) -> (events: [CHHapticEvent], curves: [CHHapticParameterCurve]) {
        
        var events: [CHHapticEvent] = []
        var curves: [CHHapticParameterCurve] = []
        
        let speedMultiplier = Double(1.0 / playbackRate)
        
        // FORCED ALIGNMENT: Use syllable timestamps if available (precise timing from forced alignment)
        // Otherwise fall back to estimated durations
        let useForcedAlignment = phrase.syllableTimestamps != nil && 
                                 phrase.syllableTimestamps?.count == phrase.syllableDurations.count
        
        // Calculate total duration
        let totalDuration: TimeInterval
        if useForcedAlignment, let timestamps = phrase.syllableTimestamps, let lastSyllable = timestamps.last {
            // Use last syllable's end time as total duration
            totalDuration = (lastSyllable.count >= 2 ? lastSyllable[1] : 0) * speedMultiplier
        } else {
            // Fall back to estimated durations
            let syllableBasedDuration = phrase.syllableDurations.reduce(0, +) * speedMultiplier
            totalDuration = actualAudioDuration ?? syllableBasedDuration
        }
        
        // Phrase-specific adjustments based on text and category
        let phraseMultiplier = getPhraseSpecificMultiplier(for: phrase)
        
        // Calculate phrase-level intonation curve
        // This will be applied gradually across the entire phrase
        let intonationCurve = calculateIntonationCurve(
            for: phrase,
            totalDuration: totalDuration
        )
        
        // Calculate timing scale once (used for all syllables)
        let syllableBasedDuration = phrase.syllableDurations.reduce(0, +) * speedMultiplier
        let timingScale = actualAudioDuration != nil ? (totalDuration / syllableBasedDuration) : 1.0
        
        // Track accumulated time for rhythm pulses
        var accumulatedTime: TimeInterval = 0
        
        // Generate haptic events for each syllable
        for (index, baseDuration) in phrase.syllableDurations.enumerated() {
            // Use forced alignment timestamps if available, otherwise use estimated durations
            let (duration, relativeTime): (TimeInterval, TimeInterval)
            
            if useForcedAlignment, let timestamps = phrase.syllableTimestamps, index < timestamps.count {
                let syllableTimestamp = timestamps[index]
                if syllableTimestamp.count >= 2 {
                    // Use exact start and end times from forced alignment
                    let startTime = syllableTimestamp[0] * speedMultiplier
                    let endTime = syllableTimestamp[1] * speedMultiplier
                    relativeTime = startTime
                    duration = endTime - startTime
                    accumulatedTime = endTime // Update to end time for next calculation
                } else {
                    // Fallback if timestamp format is invalid - use scaled durations
                    relativeTime = accumulatedTime
                    duration = (baseDuration * speedMultiplier) * timingScale
                    accumulatedTime += duration
                }
            } else {
                // Fallback to estimated durations (original behavior) - use scaled durations
                relativeTime = accumulatedTime
                duration = (baseDuration * speedMultiplier) * timingScale
                accumulatedTime += duration
            }
            
            // Ensure we don't exceed totalDuration
            let clampedRelativeTime = min(relativeTime, totalDuration)
            let clampedDuration = min(duration, max(0, totalDuration - clampedRelativeTime))
            
            // Calculate position in phrase (0.0 to 1.0)
            let phrasePosition = clampedRelativeTime / totalDuration
            
            // 1. Generate syllable-level haptic (stress/rhythm) with phrase-specific adjustment and texture
            let adjustedIntensity = intensityMultiplier * phraseMultiplier
            let texture = phrase.syllableTextures?[safe: index] ?? "soft" // Default to "soft" if not specified
            let syllableResult = generateSyllableHaptics(
                index: index,
                duration: clampedDuration,
                relativeTime: clampedRelativeTime,
                isStressed: phrase.stressIndices.contains(index),
                intensityMultiplier: adjustedIntensity,
                phrasePosition: phrasePosition,
                texture: texture
            )
            events.append(contentsOf: syllableResult.events)
            curves.append(contentsOf: syllableResult.curves)
            
            // 2. Apply phrase-level intonation overlay with phrase-specific adjustment
            let intonationOverlay = generateIntonationOverlay(
                phrasePosition: phrasePosition,
                duration: clampedDuration,
                relativeTime: clampedRelativeTime,
                intonationType: phrase.intonationType,
                intonationCurve: intonationCurve,
                intensityMultiplier: adjustedIntensity,
                isLastSyllable: index == phrase.syllableDurations.count - 1
            )
            events.append(contentsOf: intonationOverlay.events)
            curves.append(contentsOf: intonationOverlay.curves)
            
            // 3. Add stronger decay curve for stressed syllables with phrase adjustment
            if phrase.stressIndices.contains(index) {
                let decayDuration = min(clampedDuration * 0.6, 0.3, max(0, totalDuration - clampedRelativeTime)) // Clamp to remaining duration
                if decayDuration > 0 {
                    let decayCurve = CHHapticParameterCurve(
                        parameterID: .hapticIntensityControl,
                        controlPoints: [
                            .init(relativeTime: 0, value: 0.9 * adjustedIntensity), // Higher start
                            .init(relativeTime: decayDuration * 0.3, value: 0.7 * adjustedIntensity),
                            .init(relativeTime: decayDuration * 0.6, value: 0.4 * adjustedIntensity),
                            .init(relativeTime: decayDuration, value: 0.2 * adjustedIntensity) // More gradual
                        ],
                        relativeTime: clampedRelativeTime + 0.015
                    )
                    curves.append(decayCurve)
                }
            }
            
            // 4. Add rhythm pulse between syllables for better flow perception
            // Make it more noticeable for clearer rhythm with phrase adjustment
            if index < phrase.syllableDurations.count - 1 {
                let nextSyllableTime = accumulatedTime
                let gapDuration = 0.03 // 30ms pulse
                let pulseTime = max(0, min(nextSyllableTime - gapDuration, totalDuration - 0.01))
                if pulseTime >= 0 {
                    let rhythmPulse = CHHapticEvent(
                        eventType: .hapticTransient,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.15 * adjustedIntensity),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
                        ],
                        relativeTime: pulseTime
                    )
                    events.append(rhythmPulse)
                }
            }
        }
        
        // 5. Add special emphasis for last syllable in questions (rising intonation)
        // This makes the question intonation very clear and helpful
        // Use scaled timing to match the rest of the pattern
        if phrase.intonationType == .rising && !phrase.syllableDurations.isEmpty {
            let adjustedIntensity = intensityMultiplier * phraseMultiplier
            let lastIndex = phrase.syllableDurations.count - 1
            
            // Calculate last syllable timing using the same scaling as the loop
            var lastSyllableStart: TimeInterval = 0
            for i in 0..<lastIndex {
                if useForcedAlignment, let timestamps = phrase.syllableTimestamps, i < timestamps.count,
                   timestamps[i].count >= 2 {
                    lastSyllableStart = timestamps[i][1] * speedMultiplier
                } else {
                    lastSyllableStart += phrase.syllableDurations[i] * speedMultiplier * timingScale
                }
            }
            
            let lastSyllableDuration: TimeInterval
            if useForcedAlignment, let timestamps = phrase.syllableTimestamps, lastIndex < timestamps.count,
               timestamps[lastIndex].count >= 2 {
                lastSyllableDuration = (timestamps[lastIndex][1] - timestamps[lastIndex][0]) * speedMultiplier
            } else {
                lastSyllableDuration = phrase.syllableDurations[lastIndex] * speedMultiplier * timingScale
            }
            
            // Clamp to totalDuration
            let clampedLastStart = min(lastSyllableStart, totalDuration)
            let clampedLastDuration = min(lastSyllableDuration, max(0, totalDuration - clampedLastStart))
            
            // Add a strong final pulse for questions (within audio duration)
            let pulseTime = clampedLastStart + clampedLastDuration * 0.7
            if pulseTime < totalDuration {
                let questionPulse = CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.9 * adjustedIntensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.85)
                    ],
                    relativeTime: pulseTime
                )
                events.append(questionPulse)
            }
            
            // Add rising continuous haptic at the end (within audio duration)
            let tailStart = clampedLastStart + clampedLastDuration * 0.8
            let tailDuration = min(clampedLastDuration * 0.2, 0.15, max(0, totalDuration - tailStart))
            if tailStart < totalDuration && tailDuration > 0 {
                let risingTail = CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6 * adjustedIntensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)
                    ],
                    relativeTime: tailStart,
                    duration: tailDuration
                )
                events.append(risingTail)
            }
        }
        
        // Final safety check: Filter out any events that extend beyond totalDuration
        let filteredEvents = events.filter { event in
            let eventEnd = event.relativeTime + event.duration
            return event.relativeTime >= 0 && eventEnd <= totalDuration
        }
        
        // Filter curves that extend beyond totalDuration
        let filteredCurves = curves.filter { curve in
            let curveEnd = curve.relativeTime + (curve.controlPoints.last?.relativeTime ?? 0)
            return curve.relativeTime >= 0 && curveEnd <= totalDuration
        }
        
        print("📊 Pattern duration: \(totalDuration)s, Events: \(filteredEvents.count)/\(events.count), Curves: \(filteredCurves.count)/\(curves.count)")
        
        return (filteredEvents, filteredCurves)
    }
    
    // MARK: - Syllable-Level Haptics
    
    /// Generates haptic events for a single syllable with improved naturalness and texture variety
    private static func generateSyllableHaptics(
        index: Int,
        duration: TimeInterval,
        relativeTime: TimeInterval,
        isStressed: Bool,
        intensityMultiplier: Float,
        phrasePosition: Double,
        texture: String
    ) -> (events: [CHHapticEvent], curves: [CHHapticParameterCurve]) {
        var events: [CHHapticEvent] = []
        var curves: [CHHapticParameterCurve] = []
        
        // Generate texture-specific haptics based on syllableTextures
        let textureEvents = generateTextureHaptics(
            texture: texture,
            duration: duration,
            relativeTime: relativeTime,
            isStressed: isStressed,
            intensityMultiplier: intensityMultiplier
        )
        events.append(contentsOf: textureEvents.events)
        curves.append(contentsOf: textureEvents.curves)
        
        // Add stress-specific enhancements on top of texture
        if isStressed {
            // PRIMARY STRESS: Much more pronounced and noticeable
            // Use maximum intensity for clear distinction
            let impactIntensity: Float = 1.0 * intensityMultiplier
            let impactSharpness: Float = 0.9 // Very sharp for clear definition
            
            // 1. Strong initial impact (primary beat) - make it really stand out
            let primaryImpact = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: impactIntensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: impactSharpness)
                ],
                relativeTime: relativeTime
            )
            events.append(primaryImpact)
            
            // 2. Secondary impact for depth and emphasis (10ms after primary)
            let secondaryIntensity: Float = 0.6 * intensityMultiplier
            let secondaryImpact = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: secondaryIntensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)
                ],
                relativeTime: relativeTime + 0.01
            )
            events.append(secondaryImpact)
            
            // 3. Strong continuous resonance for sustained presence
            let decayDuration = min(duration * 0.7, 0.3) // Longer, more noticeable decay
            let continuous = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.85 * intensityMultiplier),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7) // Stronger tone
                ],
                relativeTime: relativeTime + 0.015,
                duration: decayDuration
            )
            events.append(continuous)
            
        } else {
            // UNSTRESSED: Clear but softer - still noticeable for rhythm
            // Make unstressed syllables more distinct from stressed ones
            let baseIntensity: Float = 0.35 * intensityMultiplier // Increased from 0.28
            // Add subtle position-based variation for natural flow
            let positionVariation = Float(sin(phrasePosition * .pi * 2.5) * 0.1)
            // Add slight variation based on index for organic feel
            let indexVariation = Float(sin(Double(index) * 0.7) * 0.08)
            let intensity = baseIntensity + positionVariation + indexVariation
            
            // Use moderate sharpness - not too soft, still clear
            let sharpness: Float = 0.35 // Increased from 0.25
            
            let tap = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: max(0.2, min(0.5, intensity))),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
                ],
                relativeTime: relativeTime
            )
            events.append(tap)
            
            // Add subtle continuous tail for better flow and rhythm perception
            if duration > 0.12 {
                let tailDuration = min(duration * 0.3, 0.1) // Longer tail
                let tail = CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity * 0.4),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
                    ],
                    relativeTime: relativeTime + 0.008,
                    duration: tailDuration
                )
                events.append(tail)
            }
        }
        
        return (events, curves)
    }
    
    // MARK: - Texture-Specific Haptics
    
    /// Generates texture-specific haptic patterns using modulating parameters
    /// - Parameters:
    ///   - texture: Texture type ("sharp", "soft", "grainy", etc.)
    ///   - duration: Duration of the syllable
    ///   - relativeTime: Start time relative to phrase start
    ///   - isStressed: Whether the syllable is stressed
    ///   - intensityMultiplier: Base intensity multiplier
    /// - Returns: Tuple of events and curves for the texture
    private static func generateTextureHaptics(
        texture: String,
        duration: TimeInterval,
        relativeTime: TimeInterval,
        isStressed: Bool,
        intensityMultiplier: Float
    ) -> (events: [CHHapticEvent], curves: [CHHapticParameterCurve]) {
        var events: [CHHapticEvent] = []
        var curves: [CHHapticParameterCurve] = []
        
        let baseIntensity = isStressed ? intensityMultiplier : intensityMultiplier * 0.6
        
        switch texture.lowercased() {
        case "sharp":
            // Sharp taps for plosives (p, t, k) - quick, percussive
            let sharpTap = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: baseIntensity * 0.9),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.95) // Very sharp
                ],
                relativeTime: relativeTime
            )
            events.append(sharpTap)
            
            // Add a quick decay for plosive feel
            if duration > 0.05 {
                let decayCurve = CHHapticParameterCurve(
                    parameterID: .hapticIntensityControl,
                    controlPoints: [
                        .init(relativeTime: 0, value: baseIntensity * 0.8),
                        .init(relativeTime: min(duration * 0.3, 0.1), value: 0.0)
                    ],
                    relativeTime: relativeTime + 0.01
                )
                curves.append(decayCurve)
            }
            
        case "grainy", "rough", "guttural":
            // Rough texture for guttural sounds - modulating continuous haptic
            // Create a "grainy" effect with rapid intensity modulation
            let grainyDuration = min(duration, 0.3)
            let modulationFrequency: Double = 15.0 // Hz - rapid modulation for roughness
            
            // Base continuous event
            let grainyBase = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: baseIntensity * 0.7),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6) // Moderate sharpness
                ],
                relativeTime: relativeTime,
                duration: grainyDuration
            )
            events.append(grainyBase)
            
            // Add modulating intensity curve for "grainy" feel
            let modulationPoints = generateModulationPoints(
                frequency: modulationFrequency,
                duration: grainyDuration,
                baseIntensity: baseIntensity * 0.7,
                modulationDepth: 0.3
            )
            let intensityCurve = CHHapticParameterCurve(
                parameterID: .hapticIntensityControl,
                controlPoints: modulationPoints,
                relativeTime: relativeTime
            )
            curves.append(intensityCurve)
            
            // Also modulate sharpness for more texture variation
            let sharpnessPoints = generateModulationPoints(
                frequency: modulationFrequency * 0.7, // Slightly different frequency
                duration: grainyDuration,
                baseIntensity: 0.6,
                modulationDepth: 0.2
            )
            let sharpnessCurve = CHHapticParameterCurve(
                parameterID: .hapticSharpnessControl,
                controlPoints: sharpnessPoints,
                relativeTime: relativeTime
            )
            curves.append(sharpnessCurve)
            
        case "soft", "smooth", "vowel":
            // Smooth swells for vowels - gentle, flowing continuous haptic
            let swellDuration = min(duration, 0.4)
            
            // Smooth continuous event with gentle swell
            let smoothSwell = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: baseIntensity * 0.6),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.25) // Soft, smooth
                ],
                relativeTime: relativeTime,
                duration: swellDuration
            )
            events.append(smoothSwell)
            
            // Add smooth swell curve (gentle rise and fall)
            let swellCurve = CHHapticParameterCurve(
                parameterID: .hapticIntensityControl,
                controlPoints: [
                    .init(relativeTime: 0, value: baseIntensity * 0.4), // Start soft
                    .init(relativeTime: swellDuration * 0.3, value: baseIntensity * 0.7), // Peak
                    .init(relativeTime: swellDuration * 0.7, value: baseIntensity * 0.6), // Sustain
                    .init(relativeTime: swellDuration, value: baseIntensity * 0.3) // Gentle fade
                ],
                relativeTime: relativeTime
            )
            curves.append(swellCurve)
            
            // Gentle sharpness variation for smoothness
            let smoothSharpnessCurve = CHHapticParameterCurve(
                parameterID: .hapticSharpnessControl,
                controlPoints: [
                    .init(relativeTime: 0, value: 0.2),
                    .init(relativeTime: swellDuration * 0.5, value: 0.3),
                    .init(relativeTime: swellDuration, value: 0.2)
                ],
                relativeTime: relativeTime
            )
            curves.append(smoothSharpnessCurve)
            
        default:
            // Default: balanced texture (fallback)
            let defaultEvent = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: baseIntensity * 0.7),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                ],
                relativeTime: relativeTime
            )
            events.append(defaultEvent)
        }
        
        return (events, curves)
    }
    
    /// Generates modulation points for creating grainy/rough textures
    private static func generateModulationPoints(
        frequency: Double,
        duration: TimeInterval,
        baseIntensity: Float,
        modulationDepth: Float
    ) -> [CHHapticParameterCurve.ControlPoint] {
        var points: [CHHapticParameterCurve.ControlPoint] = []
        let sampleRate = 60.0 // 60 samples per second for smooth modulation
        let numSamples = Int(duration * sampleRate)
        
        for i in 0..<numSamples {
            let t = Double(i) / Double(max(numSamples - 1, 1))
            let time = t * duration
            
            // Create modulation using sine wave with some randomness for graininess
            let modulation = sin(2.0 * .pi * frequency * t)
            let randomVariation = sin(2.0 * .pi * frequency * 1.7 * t) * 0.3 // Secondary frequency
            let combinedModulation = modulation + randomVariation
            
            let intensity = baseIntensity + Float(combinedModulation) * modulationDepth
            let clampedIntensity = max(0.0, min(1.0, intensity))
            
            points.append(.init(relativeTime: time, value: clampedIntensity))
        }
        
        return points
    }
    
    // MARK: - Phrase-Level Intonation
    
    /// Calculates the intonation curve for the entire phrase with improved naturalness
    private static func calculateIntonationCurve(
        for phrase: Phrase,
        totalDuration: TimeInterval
    ) -> [Double] {
        // Generate a smooth curve across the phrase with higher resolution
        let sampleCount = max(20, Int(totalDuration * 20)) // 20 samples per second for smoother curves
        var curve: [Double] = []
        
        for i in 0..<sampleCount {
            let t = Double(i) / Double(sampleCount - 1) // 0.0 to 1.0
            
            switch phrase.intonationType {
            case .rising:
                // Enhanced rising: more dramatic and noticeable
                // Use cubic easing for natural speech-like rise
                let cubic = easeInOutCubic(t)
                // Add stronger overshoot at the end for clear question intonation
                let overshoot = t > 0.8 ? (t - 0.8) * 0.5 : 0.0 // Increased overshoot
                curve.append(min(1.0, cubic + overshoot))
                
            case .falling:
                // Enhanced falling: more dramatic and noticeable
                // Use cubic easing for natural fall
                let cubic = easeInOutCubic(t)
                // Start stronger for emphasis, then fall more dramatically
                let startBoost = (1.0 - t) * 0.25 // Increased from 0.15
                curve.append(max(0.0, 1.0 - cubic + startBoost))
                
            case .flat:
                // Maintain constant level with subtle natural variation
                // Add micro-variations that mimic natural speech (not perfectly flat)
                let base = 0.5
                let slowWave = sin(t * .pi * 2) * 0.08 // Slow overall wave
                let fastWave = sin(t * .pi * 8) * 0.03 // Fast micro-variations
                curve.append(base + slowWave + fastWave)
            }
        }
        
        return curve
    }
    
    /// Generates intonation overlay that flows across the phrase with improved smoothness
    private static func generateIntonationOverlay(
        phrasePosition: Double,
        duration: TimeInterval,
        relativeTime: TimeInterval,
        intonationType: IntonationType,
        intonationCurve: [Double],
        intensityMultiplier: Float,
        isLastSyllable: Bool
    ) -> (events: [CHHapticEvent], curves: [CHHapticParameterCurve]) {
        var events: [CHHapticEvent] = []
        var curves: [CHHapticParameterCurve] = []
        
        // Get intonation value at start, middle, and end of this syllable for smoother interpolation
        let curveIndexStart = Int(phrasePosition * Double(intonationCurve.count - 1))
        let curveIndexMid = min(curveIndexStart + Int(duration * 10), intonationCurve.count - 1)
        let curveIndexEnd = min(curveIndexStart + Int(duration * 20), intonationCurve.count - 1)
        
        let startValue = intonationCurve[min(curveIndexStart, intonationCurve.count - 1)]
        let midValue = intonationCurve[min(curveIndexMid, intonationCurve.count - 1)]
        let endValue = intonationCurve[min(curveIndexEnd, intonationCurve.count - 1)]
        
        // Enhanced intonation strength calculation with smoother transitions
        let intonationStrength: Double
        switch intonationType {
        case .rising:
            // Gradual increase starting earlier, stronger on last 50%
            if phrasePosition > 0.5 {
                intonationStrength = (phrasePosition - 0.5) * 2.0 + 0.2
            } else {
                intonationStrength = phrasePosition * 0.4 // Gentle start
            }
        case .falling:
            // Start strong, maintain through middle, fade at end
            if phrasePosition < 0.3 {
                intonationStrength = 0.8
            } else if phrasePosition < 0.7 {
                intonationStrength = 0.9
            } else {
                intonationStrength = (1.0 - phrasePosition) * 3.0
            }
        case .flat:
            intonationStrength = 0.15 // Subtle constant overlay
        }
        
        // Apply intonation overlay with stronger intensity for better perception
        // Increased multiplier from 0.6 to 0.9 for more noticeable intonation
        let baseIntensity = Float(startValue) * intensityMultiplier * Float(intonationStrength) * 0.9
        let midIntensity = Float(midValue) * intensityMultiplier * Float(intonationStrength) * 0.9
        let endIntensity = Float(endValue) * intensityMultiplier * Float(intonationStrength) * 0.9
        
        // Only add if intensity is meaningful (lowered threshold to include more)
        if baseIntensity > 0.05 || endIntensity > 0.05 {
            let continuous = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: baseIntensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(startValue * 0.4 + 0.35))
                ],
                relativeTime: relativeTime,
                duration: duration
            )
            events.append(continuous)
            
            // Add multi-point parameter curves for smoother transitions
            let midTime = duration * 0.5
            let intensityCurve = CHHapticParameterCurve(
                parameterID: .hapticIntensityControl,
                controlPoints: [
                    .init(relativeTime: 0, value: baseIntensity),
                    .init(relativeTime: midTime, value: midIntensity),
                    .init(relativeTime: duration, value: endIntensity)
                ],
                relativeTime: relativeTime
            )
            
            let sharpnessStart = Float(startValue * 0.4 + 0.35)
            let sharpnessMid = Float(midValue * 0.4 + 0.35)
            let sharpnessEnd = Float(endValue * 0.4 + 0.35)
            let sharpnessCurve = CHHapticParameterCurve(
                parameterID: .hapticSharpnessControl,
                controlPoints: [
                    .init(relativeTime: 0, value: sharpnessStart),
                    .init(relativeTime: midTime, value: sharpnessMid),
                    .init(relativeTime: duration, value: sharpnessEnd)
                ],
                relativeTime: relativeTime
            )
            
            curves.append(contentsOf: [intensityCurve, sharpnessCurve])
        }
        
        return (events, curves)
    }
    
    // MARK: - Phrase-Specific Personalization
    
    /// Returns a multiplier to personalize haptics based on phrase characteristics
    private static func getPhraseSpecificMultiplier(for phrase: Phrase) -> Float {
        let text = phrase.text.lowercased()
        var multiplier: Float = 1.0
        
        // Questions get stronger emphasis (rising intonation should be very clear)
        if text.contains("?") || phrase.intonationType == .rising {
            multiplier = 1.15 // 15% stronger for questions
        }
        
        // Greetings get warm, friendly haptics (slightly softer but still clear)
        if phrase.category == "Greetings" {
            multiplier *= 1.1
        }
        
        // Travel/urgent phrases get sharper, more attention-grabbing haptics
        if phrase.category == "Travel" {
            multiplier *= 1.2
        }
        
        // Short phrases need stronger haptics to be noticeable
        if phrase.syllableDurations.count <= 4 {
            multiplier *= 1.1
        }
        
        // Long phrases can be slightly softer to avoid overwhelming
        if phrase.syllableDurations.count >= 6 {
            multiplier *= 0.95
        }
        
        return multiplier
    }
    
    // MARK: - Helper Functions
    
    /// Ease-in-out quadratic easing function for smooth curves
    private static func easeInOutQuad(_ t: Double) -> Double {
        if t < 0.5 {
            return 2 * t * t
        } else {
            return -1 + (4 - 2 * t) * t
        }
    }
    
    /// Ease-in-out cubic easing function for more natural speech-like curves
    private static func easeInOutCubic(_ t: Double) -> Double {
        if t < 0.5 {
            return 4 * t * t * t
        } else {
            let f = 2 * t - 2
            return 1 + f * f * f / 2
        }
    }
}

