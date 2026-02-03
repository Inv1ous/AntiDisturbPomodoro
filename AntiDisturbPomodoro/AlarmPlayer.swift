import Foundation
import AppKit

/// Handles audio playback for alarms using NSSound (native macOS, no CoreAudio warnings)
class AlarmPlayer: NSObject, ObservableObject {
    
    @Published private(set) var isPlaying = false
    
    private var sound: NSSound?
    private var stopTimer: Timer?
    private var loopTimer: Timer?
    private let soundLibrary: SoundLibrary
    
    // Store current sound info for looping
    private var currentSoundURL: URL?
    private var currentMaxDuration: TimeInterval = 10
    private var playStartTime: Date?
    
    init(soundLibrary: SoundLibrary) {
        self.soundLibrary = soundLibrary
    }
    
    // MARK: - Playback Control
    
    func play(soundId: String, maxDuration: TimeInterval = 10) {
        // Stop any current playback
        stop()
        
        currentMaxDuration = maxDuration
        playStartTime = Date()
        
        // Handle system default sound
        if soundId == "system.default" {
            playSystemSound(maxDuration: maxDuration)
            return
        }
        
        // Resolve sound file URL
        guard let fileURL = soundLibrary.resolveFileURL(forId: soundId) else {
            print("Could not resolve sound URL for id: \(soundId)")
            playSystemSound(maxDuration: maxDuration)
            return
        }
        
        // Check if file exists
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            print("Sound file does not exist: \(fileURL.path)")
            playSystemSound(maxDuration: maxDuration)
            return
        }
        
        currentSoundURL = fileURL
        
        // Create and play sound
        guard let nsSound = NSSound(contentsOf: fileURL, byReference: true) else {
            print("Failed to create NSSound from: \(fileURL.path)")
            playSystemSound(maxDuration: maxDuration)
            return
        }
        
        sound = nsSound
        sound?.delegate = self
        sound?.play()
        isPlaying = true
        
        // Schedule stop after max duration
        stopTimer = Timer.scheduledTimer(withTimeInterval: maxDuration, repeats: false) { [weak self] _ in
            self?.stop()
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
        
        isPlaying = false
    }
    
    // MARK: - System Sound Fallback
    
    private func playSystemSound(maxDuration: TimeInterval) {
        isPlaying = true
        
        // Play system alert sound immediately
        NSSound.beep()
        
        // Repeat beep every 1.5 seconds
        loopTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            NSSound.beep()
        }
        
        // Schedule stop after max duration
        stopTimer = Timer.scheduledTimer(withTimeInterval: maxDuration, repeats: false) { [weak self] _ in
            self?.stop()
        }
    }
    
    // MARK: - Test Playback
    
    func testSound(soundId: String, maxDuration: TimeInterval = 3) {
        play(soundId: soundId, maxDuration: maxDuration)
    }
}

// MARK: - NSSoundDelegate

extension AlarmPlayer: NSSoundDelegate {
    
    func sound(_ sound: NSSound, didFinishPlaying flag: Bool) {
        // Only restart if we should still be playing (within max duration)
        guard flag,
              isPlaying,
              let startTime = playStartTime,
              let soundURL = currentSoundURL else {
            return
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        let remaining = currentMaxDuration - elapsed
        
        // If there's still time remaining, restart the sound for looping
        if remaining > 0.5 {
            // Small delay before restarting to prevent audio glitches
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self = self, self.isPlaying else { return }
                
                if let newSound = NSSound(contentsOf: soundURL, byReference: true) {
                    self.sound = newSound
                    newSound.delegate = self
                    newSound.play()
                }
            }
        } else {
            // Duration exceeded, stop
            stop()
        }
    }
}

