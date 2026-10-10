import Foundation
import Accelerate
import AVFoundation

/// Advanced pitch detector using YIN algorithm with voiced/unvoiced detection.
/// YIN is more robust than autocorrelation and less prone to octave errors.
class PitchDetector {
    private let sampleRate: Float
    
    // YIN algorithm parameters
    private let minFreq: Float = 50.0  // Minimum frequency (Hz) - human voice lower bound
    private let maxFreq: Float = 1000.0 // Maximum frequency (Hz) - human voice upper bound
    private let threshold: Float = 0.1  // YIN threshold for period detection
    
    // Voiced/Unvoiced detection parameters
    // Relaxed thresholds to be more permissive and detect more valid pitch
    private let minEnergy: Float = 0.0002  // Minimum RMS energy to consider voiced (very permissive)
    private let maxZeroCrossingRate: Float = 0.6  // Maximum ZCR for voiced sounds (very permissive)
    private let lowFreqEnergyRatio: Float = 0.1  // Minimum ratio of low-freq energy (very permissive)
    
    init(sampleRate: Float) {
        self.sampleRate = sampleRate
    }
    
    /// Estimates the pitch (frequency) from an audio buffer using YIN algorithm.
    /// Returns nil for unvoiced segments (consonants like 's', 't', 'f', etc.)
    func estimatePitch(from buffer: AVAudioPCMBuffer) -> Float? {
        guard let channelData = buffer.floatChannelData?[0] else { return nil }
        let frameLength = Int(buffer.frameLength)
        
        // Limit processing size for performance
        let processCount = min(frameLength, 4096)
        
        // Convert to array
        var audioData = Array(UnsafeBufferPointer(start: channelData, count: processCount))
        
        // Step 1: Voiced/Unvoiced Detection
        // Skip pitch calculation for unvoiced segments (consonants, silence, noise)
        if !isVoiced(audioData: audioData, count: processCount) {
            return nil // Unvoiced segment - no pitch
        }
        
        // Step 2: Apply pre-emphasis filter (high-pass) to reduce low-frequency noise
        applyPreEmphasis(to: &audioData, count: processCount)
        
        // Step 3: Calculate YIN difference function
        let minPeriod = Int(sampleRate / maxFreq)  // Minimum period in samples
        let maxPeriod = Int(sampleRate / minFreq)  // Maximum period in samples
        
        guard maxPeriod < processCount / 2 else { return nil }
        
        // Step 4: Compute YIN cumulative mean normalized difference function
        guard let period = computeYINPeriod(audioData: audioData, 
                                           count: processCount,
                                           minPeriod: minPeriod,
                                           maxPeriod: maxPeriod) else {
            return nil
        }
        
        // Step 5: Convert period to frequency
        let frequency = sampleRate / Float(period)
        
        // Validate frequency is in human voice range
        guard frequency >= minFreq && frequency <= maxFreq else {
            return nil
        }
        
        return frequency
    }
    
    // MARK: - Voiced/Unvoiced Detection
    
    /// Determines if the audio segment is voiced (has pitch) or unvoiced (no pitch).
    /// Unvoiced sounds include fricatives (s, f, sh), stops (t, p, k), and silence.
    private func isVoiced(audioData: [Float], count: Int) -> Bool {
        // 1. Energy check: unvoiced sounds typically have lower energy
        let rms = sqrt(audioData.prefix(count).map { $0 * $0 }.reduce(0, +) / Float(count))
        guard rms >= minEnergy else {
            return false // Too quiet - likely silence or unvoiced
        }
        
        // 2. Zero-crossing rate: unvoiced sounds have higher ZCR
        let zcr = calculateZeroCrossingRate(audioData: audioData, count: count)
        guard zcr <= maxZeroCrossingRate else {
            return false // High ZCR indicates unvoiced fricative
        }
        
        // 3. Spectral analysis: voiced sounds have more low-frequency energy
        let lowFreqRatio = calculateLowFrequencyEnergyRatio(audioData: audioData, count: count)
        guard lowFreqRatio >= lowFreqEnergyRatio else {
            return false // Too much high-frequency energy - likely unvoiced
        }
        
        return true // Passed all checks - likely voiced
    }
    
    /// Calculates zero-crossing rate (normalized by sample count).
    /// Unvoiced fricatives have high ZCR, voiced sounds have lower ZCR.
    private func calculateZeroCrossingRate(audioData: [Float], count: Int) -> Float {
        guard count > 1 else { return 0 }
        
        var crossings = 0
        for i in 1..<count {
            if (audioData[i-1] >= 0 && audioData[i] < 0) || 
               (audioData[i-1] < 0 && audioData[i] >= 0) {
                crossings += 1
            }
        }
        
        return Float(crossings) / Float(count)
    }
    
    /// Calculates the ratio of low-frequency energy to total energy.
    /// Voiced sounds have more energy in lower frequencies (fundamental + harmonics).
    private func calculateLowFrequencyEnergyRatio(audioData: [Float], count: Int) -> Float {
        guard count >= 256 else { return 0.5 } // Fallback for very short buffers
        
        // Simple frequency analysis using FFT
        let fftSize = 512
        var realIn = [Float](repeating: 0, count: fftSize)
        var imagIn = [Float](repeating: 0, count: fftSize)
        var realOut = [Float](repeating: 0, count: fftSize)
        var imagOut = [Float](repeating: 0, count: fftSize)
        
        // Copy data and apply window
        let copyCount = min(count, fftSize)
        for i in 0..<copyCount {
            // Apply Hann window to reduce spectral leakage
            let window = 0.5 * (1.0 - cos(2.0 * Float.pi * Float(i) / Float(copyCount - 1)))
            realIn[i] = audioData[i] * window
        }
        
        // Perform FFT using vDSP
        let log2n = vDSP_Length(log2(Double(fftSize)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return 0.5 // Fallback
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }
        
        var splitComplex = DSPSplitComplex(realp: &realIn, imagp: &imagIn)
        vDSP_fft_zip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
        
        // Calculate magnitudes from FFT output (now in realIn and imagIn)
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)
        var complex = DSPSplitComplex(realp: &realIn, imagp: &imagIn)
        vDSP_zvabs(&complex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
        
        // Calculate energy in low frequencies (first 1/4 of spectrum)
        let lowFreqEnd = fftSize / 8
        let lowFreqEnergy = magnitudes.prefix(lowFreqEnd).map { $0 * $0 }.reduce(0, +)
        let totalEnergy = magnitudes.map { $0 * $0 }.reduce(0, +)
        
        guard totalEnergy > 0 else { return 0 }
        return lowFreqEnergy / totalEnergy
    }
    
    // MARK: - Pre-emphasis Filter
    
    /// Applies a high-pass pre-emphasis filter to reduce low-frequency noise.
    /// This improves pitch detection accuracy.
    private func applyPreEmphasis(to audioData: inout [Float], count: Int) {
        guard count > 1 else { return }
        
        let alpha: Float = 0.97  // Pre-emphasis coefficient
        for i in (1..<count).reversed() {
            audioData[i] = audioData[i] - alpha * audioData[i - 1]
        }
    }
    
    // MARK: - YIN Algorithm
    
    /// Computes the fundamental period using YIN algorithm.
    /// YIN uses cumulative mean normalized difference function to avoid octave errors.
    private func computeYINPeriod(audioData: [Float], 
                                  count: Int,
                                  minPeriod: Int,
                                  maxPeriod: Int) -> Float? {
        guard maxPeriod < count / 2 else { return nil }
        
        // Step 1: Calculate difference function d_t(tau)
        var diff = [Float](repeating: 0, count: maxPeriod + 1)
        
        for tau in 0...maxPeriod {
            var sum: Float = 0
            for j in 0..<(count - maxPeriod) {
                let delta = audioData[j] - audioData[j + tau]
                sum += delta * delta
            }
            diff[tau] = sum
        }
        
        // Step 2: Calculate cumulative mean normalized difference function
        // d'_t(tau) = d_t(tau) / [(1/tau) * sum(d_t(j)) for j=1 to tau]
        var cmndf = [Float](repeating: 0, count: maxPeriod + 1)
        cmndf[0] = 1.0  // d'_t(0) = 1 by definition
        
        var cumulativeSum: Float = 0
        for tau in 1...maxPeriod {
            cumulativeSum += diff[tau]
            if cumulativeSum > 0 {
                cmndf[tau] = diff[tau] * Float(tau) / cumulativeSum
            } else {
                cmndf[tau] = 1.0
            }
        }
        
        // Step 3: Find the first minimum below threshold
        // Search from minPeriod to avoid detecting sub-harmonics
        var minValue: Float = Float.greatestFiniteMagnitude
        var minIndex: Int = -1
        
        for tau in minPeriod...maxPeriod {
            if cmndf[tau] < threshold {
                // Found a value below threshold - this is likely the period
                minIndex = tau
                minValue = cmndf[tau]
                break
            }
            
            // Track absolute minimum as fallback
            if cmndf[tau] < minValue {
                minValue = cmndf[tau]
                minIndex = tau
            }
        }
        
        // If no value below threshold, use the absolute minimum
        // but only if it's reasonably low (not too close to 1.0)
        // Relaxed threshold to be more permissive
        guard minIndex != -1 && minValue < 0.7 else {
            return nil
        }
        
        // Step 4: Parabolic interpolation for sub-sample precision
        if minIndex > 0 && minIndex < maxPeriod {
            let y1 = cmndf[minIndex - 1]
            let y2 = cmndf[minIndex]
            let y3 = cmndf[minIndex + 1]
            
            // Parabolic interpolation: find the vertex of the parabola
            let denominator = 2 * y2 - y1 - y3
            guard abs(denominator) > 1e-6 else {
                return Float(minIndex)
            }
            
            let d = (y3 - y1) / denominator
            let refinedPeriod = Float(minIndex) + d
            
            return refinedPeriod
        }
        
        return Float(minIndex)
    }
}
