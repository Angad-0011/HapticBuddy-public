import Foundation
import AVFoundation
import UIKit
import Darwin

/// Manages device-specific latency calibration for audio-haptic synchronization
class LatencyCalibrationManager {
    static let shared = LatencyCalibrationManager()
    
    private let userDefaults = UserDefaults.standard
    private let calibrationKey = "haptic_audio_latency_calibration"
    
    private init() {}
    
    /// Device model identifier (e.g., "iPhone14,2" for iPhone 13 Pro)
    var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "Unknown"
            }
        }
    }
    
    /// Get calibrated latency for current device (in seconds)
    /// Returns a small offset to account for audio playback latency
    func getCalibratedLatency() -> TimeInterval {
        // Check if we have a stored calibration for this device
        if let stored = userDefaults.dictionary(forKey: calibrationKey),
           let deviceLatency = stored[deviceModel] as? Double {
            return deviceLatency
        }
        
        // Default latency estimates per device family (in seconds)
        // These are conservative estimates based on typical iOS device behavior
        let model = deviceModel.lowercased()
        
        if model.contains("iphone") {
            // iPhone models typically have 20-50ms audio latency
            if model.contains("iphone15") || model.contains("iphone14") || model.contains("iphone13") {
                return 0.030 // 30ms for recent iPhones
            } else if model.contains("iphone12") || model.contains("iphone11") {
                return 0.035 // 35ms for older recent iPhones
            } else {
                return 0.040 // 40ms for older models
            }
        } else if model.contains("ipad") {
            // iPads typically have slightly higher latency
            return 0.045 // 45ms for iPads
        }
        
        // Default fallback
        return 0.035 // 35ms default
    }
    
    /// Store a calibrated latency for the current device
    /// This can be called after a calibration test
    func storeCalibration(latency: TimeInterval) {
        var calibrations = userDefaults.dictionary(forKey: calibrationKey) ?? [:]
        calibrations[deviceModel] = latency
        userDefaults.set(calibrations, forKey: calibrationKey)
        print("📊 Stored latency calibration for \(deviceModel): \(latency * 1000)ms")
    }
    
    /// Check if calibration has been performed for this device
    func hasCalibration() -> Bool {
        if let stored = userDefaults.dictionary(forKey: calibrationKey),
           stored[deviceModel] != nil {
            return true
        }
        return false
    }
    
    /// Get the stored calibration value (if available)
    func getStoredCalibration() -> TimeInterval? {
        if let stored = userDefaults.dictionary(forKey: calibrationKey),
           let deviceLatency = stored[deviceModel] as? Double {
            return deviceLatency
        }
        return nil
    }
    
    /// Clear calibration for current device (useful for re-calibration)
    func clearCalibration() {
        var calibrations = userDefaults.dictionary(forKey: calibrationKey) ?? [:]
        calibrations.removeValue(forKey: deviceModel)
        userDefaults.set(calibrations, forKey: calibrationKey)
        print("📊 Cleared calibration for \(deviceModel)")
    }
}

