import Foundation
import Accelerate
import AVFoundation

/// Extracts Mel-Frequency Cepstral Coefficients (MFCCs) from audio for acoustic feature comparison.
/// MFCCs are standard features used in speech recognition and can be compared using DTW for pronunciation scoring.
class MFCCExtractor {
    static let shared = MFCCExtractor()
    
    private init() {}
    
    // MFCC parameters
    private let sampleRate: Double = 44100.0
    private let frameLength: Int = 512 // FFT window size
    private let frameShift: Int = 256 // Frame overlap
    private let numMelFilters: Int = 26 // Number of Mel filter banks
    private let numCepstralCoeffs: Int = 13 // Number of MFCC coefficients (including C0)
    
    /// Extract MFCC features from an audio file
    /// - Parameter audioURL: URL to the audio file
    /// - Returns: Array of MFCC feature vectors (one per frame), or nil if extraction fails
    func extractMFCCs(from audioURL: URL) -> [[Float]]? {
        guard let audioFile = try? AVAudioFile(forReading: audioURL) else {
            print("⚠️ MFCCExtractor: Failed to open audio file")
            return nil
        }
        
        // Use processingFormat which is always PCM (converted from source format)
        let pcmFormat = audioFile.processingFormat
        let fileSampleRate = pcmFormat.sampleRate
        
        // Verify it's PCM format by checking commonFormat
        // processingFormat should always be PCM, but we check to be safe
        guard pcmFormat.commonFormat == .pcmFormatFloat32 || 
              pcmFormat.commonFormat == .pcmFormatInt16 ||
              pcmFormat.commonFormat == .pcmFormatInt32 ||
              pcmFormat.commonFormat == .pcmFormatFloat64 else {
            print("⚠️ MFCCExtractor: Processing format is not PCM (format: \(pcmFormat.commonFormat.rawValue))")
            return nil
        }
        
        // Create buffer with PCM format
        guard let buffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: AVAudioFrameCount(audioFile.length)) else {
            print("⚠️ MFCCExtractor: Failed to create audio buffer")
            return nil
        }
        
        do {
            // Read audio file - AVAudioFile automatically converts to processingFormat (PCM)
            try audioFile.read(into: buffer)
        } catch {
            print("⚠️ MFCCExtractor: Failed to read audio file: \(error)")
            return nil
        }
        
        guard let channelData = buffer.floatChannelData?[0] else {
            print("⚠️ MFCCExtractor: No channel data")
            return nil
        }
        
        let frameCount = Int(buffer.frameLength)
        let audioData = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
        
        // Extract MFCCs
        return extractMFCCsFromSamples(audioData, sampleRate: Double(fileSampleRate))
    }
    
    /// Extract MFCC features from raw audio samples
    /// - Parameters:
    ///   - samples: Raw audio samples (Float array)
    ///   - sampleRate: Sample rate of the audio
    /// - Returns: Array of MFCC feature vectors
    private func extractMFCCsFromSamples(_ samples: [Float], sampleRate: Double) -> [[Float]] {
        var mfccFrames: [[Float]] = []
        
        // Process audio in frames
        var frameStart = 0
        while frameStart + frameLength <= samples.count {
            // Extract frame
            let frame = Array(samples[frameStart..<frameStart + frameLength])
            
            // Apply window (Hann window to reduce spectral leakage)
            let windowedFrame = applyHannWindow(frame)
            
            // Compute FFT
            guard let fftMagnitudes = computeFFT(windowedFrame, sampleRate: sampleRate) else {
                frameStart += frameShift
                continue
            }
            
            // Apply Mel filter bank
            let melSpectrum = applyMelFilterBank(fftMagnitudes, sampleRate: sampleRate)
            
            // Take logarithm
            let logMelSpectrum = melSpectrum.map { max(1e-10, $0) }.map { log10($0) }
            
            // Apply DCT (Discrete Cosine Transform) to get MFCCs
            let mfccs = applyDCT(logMelSpectrum)
            
            mfccFrames.append(mfccs)
            
            frameStart += frameShift
        }
        
        return mfccFrames
    }
    
    /// Apply Hann window to reduce spectral leakage
    private func applyHannWindow(_ frame: [Float]) -> [Float] {
        let n = frame.count
        return frame.enumerated().map { index, value in
            let window = 0.5 * (1.0 - cos(2.0 * Float.pi * Float(index) / Float(n - 1)))
            return value * window
        }
    }
    
    /// Compute FFT and return magnitude spectrum
    private func computeFFT(_ frame: [Float], sampleRate: Double) -> [Float]? {
        let fftSize = frameLength
        let log2n = vDSP_Length(log2(Double(fftSize)))
        
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return nil
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }
        
        // Prepare input (real and imaginary parts)
        var realIn = frame + [Float](repeating: 0, count: fftSize - frame.count)
        var imagIn = [Float](repeating: 0, count: fftSize)
        var realOut = [Float](repeating: 0, count: fftSize)
        var imagOut = [Float](repeating: 0, count: fftSize)
        
        // Perform FFT (vDSP_fft_zip modifies the input arrays in-place)
        var splitComplex = DSPSplitComplex(realp: &realIn, imagp: &imagIn)
        vDSP_fft_zip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
        
        // After FFT, realIn and imagIn contain the FFT results
        // Calculate magnitudes (only need first half due to symmetry)
        let halfSize = fftSize / 2
        var magnitudes = [Float](repeating: 0, count: halfSize)
        var complex = DSPSplitComplex(realp: &realIn, imagp: &imagIn)
        vDSP_zvabs(&complex, 1, &magnitudes, 1, vDSP_Length(halfSize))
        
        return magnitudes
    }
    
    /// Apply Mel filter bank to magnitude spectrum
    private func applyMelFilterBank(_ magnitudes: [Float], sampleRate: Double) -> [Float] {
        let nyquist = sampleRate / 2.0
        let melMax = hzToMel(nyquist)
        let melMin = 0.0
        
        // Create Mel filter bank
        var melFilters = [[Float]](repeating: [Float](repeating: 0, count: magnitudes.count), count: numMelFilters)
        
        for i in 0..<numMelFilters {
            let melCenter = melMin + (melMax - melMin) * Double(i + 1) / Double(numMelFilters + 1)
            let hzCenter = melToHz(melCenter)
            let binCenter = Int(hzCenter / nyquist * Double(magnitudes.count))
            
            // Create triangular filter
            let filterWidth = binCenter / 2
            for j in 0..<magnitudes.count {
                let distance = abs(j - binCenter)
                if distance < filterWidth {
                    let weight = 1.0 - Float(distance) / Float(filterWidth)
                    melFilters[i][j] = weight
                }
            }
        }
        
        // Apply filters to magnitude spectrum
        var melSpectrum = [Float](repeating: 0, count: numMelFilters)
        for i in 0..<numMelFilters {
            var sum: Float = 0
            for j in 0..<magnitudes.count {
                sum += magnitudes[j] * melFilters[i][j]
            }
            melSpectrum[i] = sum
        }
        
        return melSpectrum
    }
    
    /// Apply DCT (Discrete Cosine Transform) to get MFCC coefficients
    private func applyDCT(_ melSpectrum: [Float]) -> [Float] {
        var mfccs = [Float](repeating: 0, count: numCepstralCoeffs)
        
        for i in 0..<numCepstralCoeffs {
            var sum: Float = 0
            for j in 0..<melSpectrum.count {
                let cosValue = cos(Float.pi * Float(i) * (Float(j) + 0.5) / Float(melSpectrum.count))
                sum += melSpectrum[j] * cosValue
            }
            // Normalize
            if i == 0 {
                mfccs[i] = sum / sqrt(Float(melSpectrum.count))
            } else {
                mfccs[i] = sum * sqrt(2.0 / Float(melSpectrum.count))
            }
        }
        
        return mfccs
    }
    
    /// Convert Hz to Mel scale
    private func hzToMel(_ hz: Double) -> Double {
        return 2595.0 * log10(1.0 + hz / 700.0)
    }
    
    /// Convert Mel to Hz
    private func melToHz(_ mel: Double) -> Double {
        return 700.0 * (pow(10, mel / 2595.0) - 1.0)
    }
    
    /// Calculate DTW distance between two MFCC feature sequences
    /// - Parameters:
    ///   - mfcc1: First MFCC sequence
    ///   - mfcc2: Second MFCC sequence
    /// - Returns: DTW distance (lower = more similar)
    func calculateMFCCDTW(_ mfcc1: [[Float]], _ mfcc2: [[Float]]) -> Double {
        guard !mfcc1.isEmpty && !mfcc2.isEmpty else { return Double.infinity }
        
        let n = mfcc1.count
        let m = mfcc2.count
        
        // Initialize DP table
        var dtw = [[Double]](repeating: [Double](repeating: Double.infinity, count: m + 1), count: n + 1)
        dtw[0][0] = 0.0
        
        // Fill DP table
        for i in 1...n {
            for j in 1...m {
                // Calculate Euclidean distance between MFCC vectors
                let cost = euclideanDistance(mfcc1[i-1], mfcc2[j-1])
                dtw[i][j] = cost + min(dtw[i-1][j], dtw[i][j-1], dtw[i-1][j-1])
            }
        }
        
        return dtw[n][m]
    }
    
    /// Calculate Euclidean distance between two MFCC feature vectors
    private func euclideanDistance(_ v1: [Float], _ v2: [Float]) -> Double {
        guard v1.count == v2.count else { return Double.infinity }
        
        var sum: Double = 0.0
        for i in 0..<v1.count {
            let diff = Double(v1[i] - v2[i])
            sum += diff * diff
        }
        
        return sqrt(sum)
    }
}

