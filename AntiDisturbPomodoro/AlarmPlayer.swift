import Foundation
import AppKit

/// Handles audio playback for alarms using NSSound (native macOS, no CoreAudio warnings)
class AlarmPlayer: NSObject, ObservableObject {
    
    @Published private(set) var isPlaying = false
    /// UI volume scalar. The settings UI allows 0...2 (0%...200%).
    /// NSSound's internal volume is 0...1, so we clamp when applying.
    @Published var volume: Double = 1.0 {
        didSet {
            sound?.volume = Self.nsSoundVolume(from: volume)
        }
    }
    
    private var sound: NSSound?
    private var stopTimer: Timer?
    private var loopTimer: Timer?
    private let soundLibrary: SoundLibrary
    
    // Store current sound info for looping
    private var currentSoundURL: URL?
    private var currentMaxDuration: TimeInterval = 10
    private var playStartTime: Date?
    
    // Loop count mode support
    private var loopMode: AlarmDurationMode = .seconds
    private var targetLoopCount: Int = 1
    private var currentLoopCount: Int = 0
    private var shouldLoop: Bool = true
    
    // MARK: - Sound Cache (Memory/CPU optimization)
    private var soundCache: [URL: NSSound] = [:]
    private let maxCacheSize = 5
    
    init(soundLibrary: SoundLibrary) {
        self.soundLibrary = soundLibrary
        super.init()
    }
    
    // MARK: - Playback Control
    
    /// Play a sound with duration specified in seconds
    func play(soundId: String, maxDuration: TimeInterval = 10, volume: Double = 1.0) {
        playSound(soundId: soundId, value: Int(maxDuration), mode: .seconds, volume: volume, allowLoop: true)
    }
    
    /// Play a sound with duration mode (seconds or loop count)
    func play(soundId: String, value: Int, mode: AlarmDurationMode, volume: Double = 1.0) {
        playSound(soundId: soundId, value: value, mode: mode, volume: volume, allowLoop: true)
    }
    
    private func playSound(soundId: String, value: Int, mode: AlarmDurationMode, volume: Double, allowLoop: Bool) {
        // Stop any current playback
        stop()
        
        // Handle "none" sound option
        if soundId == "none" || soundId.isEmpty {
            return
        }
        
        self.volume = volume
        self.loopMode = mode
        self.shouldLoop = allowLoop
        self.currentLoopCount = 0
        playStartTime = Date()
        
        if mode == .seconds {
            currentMaxDuration = TimeInterval(value)
            targetLoopCount = Int.max
        } else {
            // Loop count mode
            targetLoopCount = value
            currentMaxDuration = TimeInterval.greatestFiniteMagnitude // No time limit
        }
        
        // Handle system default sound
        if soundId == "system.default" {
            playSystemSound(maxDuration: mode == .seconds ? TimeInterval(value) : TimeInterval(value * 2))
            return
        }
        
        // Resolve sound file URL
        guard let fileURL = soundLibrary.resolveFileURL(forId: soundId) else {
            print("Could not resolve sound URL for id: \(soundId)")
            playSystemSound(maxDuration: mode == .seconds ? TimeInterval(value) : TimeInterval(value * 2))
            return
        }
        
        // Check if file exists
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            print("Sound file does not exist: \(fileURL.path)")
            playSystemSound(maxDuration: mode == .seconds ? TimeInterval(value) : TimeInterval(value * 2))
            return
        }
        
        currentSoundURL = fileURL
        
        // Try to get from cache or create new sound
        let nsSound: NSSound
        if let cached = soundCache[fileURL], let copy = cached.copy() as? NSSound {
            nsSound = copy
        } else {
            guard let newSound = NSSound(contentsOf: fileURL, byReference: true) else {
                print("Failed to create NSSound from: \(fileURL.path)")
                playSystemSound(maxDuration: mode == .seconds ? TimeInterval(value) : TimeInterval(value * 2))
                return
            }
            nsSound = newSound
            
            // Cache it
            if soundCache.count >= maxCacheSize {
                if let firstKey = soundCache.keys.first {
                    soundCache.removeValue(forKey: firstKey)
                }
            }
            soundCache[fileURL] = NSSound(contentsOf: fileURL, byReference: true)
        }
        
        sound = nsSound
        sound?.volume = Self.nsSoundVolume(from: volume)
        sound?.delegate = self
        sound?.play()
        isPlaying = true
        currentLoopCount = 1
        
        // Schedule stop after max duration (only for seconds mode)
        if mode == .seconds {
            stopTimer = Timer.scheduledTimer(withTimeInterval: currentMaxDuration, repeats: false) { [weak self] _ in
                self?.stop()
            }
        }
    }
    
    func stop() {
        stopTimer?.invalidate()
        stopTimer = nil
        
        loopTimer?.invalidate()
        loopTimer = nil
        
        sound?.stop()
        sound?.delegate = nil
        sound = nil
        
        currentSoundURL = nil
        playStartTime = nil
        currentLoopCount = 0
        
        isPlaying = false
    }
    
    // MARK: - System Sound Fallback
    
    private func playSystemSound(maxDuration: TimeInterval) {
        isPlaying = true
        
        NSSound.beep()
        
        loopTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            NSSound.beep()
        }
        
        stopTimer = Timer.scheduledTimer(withTimeInterval: maxDuration, repeats: false) { [weak self] _ in
            self?.stop()
        }
    }
    
    // MARK: - Test Playback (No Looping)
    
    /// Test a sound - plays once without looping
    func testSound(soundId: String, volume: Double = 1.0) {
        // Stop any current playback
        stop()
        
        // Handle "none" sound option
        if soundId == "none" || soundId.isEmpty {
            return
        }
        
        self.volume = volume
        self.shouldLoop = false  // Disable looping for test
        
        // Handle system default sound
        if soundId == "system.default" {
            isPlaying = true
            NSSound.beep()
            // Auto-stop after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.isPlaying = false
            }
            return
        }
        
        // Resolve sound file URL
        guard let fileURL = soundLibrary.resolveFileURL(forId: soundId) else {
            print("Could not resolve sound URL for id: \(soundId)")
            NSSound.beep()
            return
        }
        
        // Check if file exists
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            print("Sound file does not exist: \(fileURL.path)")
            NSSound.beep()
            return
        }
        
        // Create and play sound once
        guard let nsSound = NSSound(contentsOf: fileURL, byReference: true) else {
            print("Failed to create NSSound from: \(fileURL.path)")
            NSSound.beep()
            return
        }
        
        sound = nsSound
        sound?.volume = Self.nsSoundVolume(from: volume)
        sound?.delegate = self
        sound?.play()
        isPlaying = true
    }
    
    // MARK: - Memory Management
    
    func clearCache() {
        soundCache.removeAll()
    }
}

// MARK: - NSSoundDelegate

extension AlarmPlayer: NSSoundDelegate {
    
    func sound(_ sound: NSSound, didFinishPlaying flag: Bool) {
        guard flag, isPlaying else {
            // Sound was stopped or didn't finish normally
            isPlaying = false
            return
        }
        
        // If looping is disabled (test mode), just stop
        guard shouldLoop else {
            isPlaying = false
            self.sound = nil
            return
        }
        
        guard let soundURL = currentSoundURL else {
            isPlaying = false
            return
        }
        
        // Check if we should continue based on mode
        var shouldContinue = false
        
        if loopMode == .seconds {
            // Check time remaining
            if let startTime = playStartTime {
                let elapsed = Date().timeIntervalSince(startTime)
                let remaining = currentMaxDuration - elapsed
                shouldContinue = remaining > 0.5
            }
        } else {
            // Loop count mode - check if we've reached target
            shouldContinue = currentLoopCount < targetLoopCount
        }
        
        if shouldContinue {
            // Small delay before restarting to prevent audio glitches
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self = self, self.isPlaying, self.shouldLoop else { return }
                
                let newSound: NSSound?
                if let cached = self.soundCache[soundURL], let copy = cached.copy() as? NSSound {
                    newSound = copy
                } else {
                    newSound = NSSound(contentsOf: soundURL, byReference: true)
                }
                
                if let newSound = newSound {
                    self.sound = newSound
                    newSound.volume = Self.nsSoundVolume(from: self.volume)
                    newSound.delegate = self
                    newSound.play()
                    self.currentLoopCount += 1
                }
            }
        } else {
            // Done playing
            stop()
        }
    }

    private static func nsSoundVolume(from uiVolume: Double) -> Float {
        let clamped = max(0.0, min(1.0, uiVolume))
        return Float(clamped)
    }
}
