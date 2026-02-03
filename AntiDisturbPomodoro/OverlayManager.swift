import Foundation
import AppKit
import SwiftUI
import Combine

/// Manages full-screen overlay windows across all monitors during breaks
class OverlayManager: NSObject, ObservableObject {
    
    private var overlayWindows: [NSWindow] = []
    private var cancellables = Set<AnyCancellable>()
    
    private weak var timerEngine: TimerEngine?
    private weak var alarmPlayer: AlarmPlayer?
    private weak var profileStore: ProfileStore?
    
    @Published var skipEnabled = false
    @Published var skipCountdown: Int = 0
    
    private var skipTimer: Timer?
    
    init(timerEngine: TimerEngine, alarmPlayer: AlarmPlayer, profileStore: ProfileStore) {
        self.timerEngine = timerEngine
        self.alarmPlayer = alarmPlayer
        self.profileStore = profileStore
        super.init()
    }
    
    // MARK: - Show/Hide Overlay
    
    func showOverlay() {
        // Close any existing overlays
        hideOverlay()
        
        guard let profile = profileStore?.currentProfile else { return }
        
        // Reset skip state
        skipEnabled = false
        skipCountdown = 0
        
        // Create overlay for each screen
        for screen in NSScreen.screens {
            let window = createOverlayWindow(for: screen)
            overlayWindows.append(window)
            window.orderFrontRegardless()
        }
        
        // Handle delayed skip if enabled
        if profile.overlay.delayedSkipEnabled && !profile.overlay.strictDefault {
            let delaySeconds = profile.overlay.delayedSkipSeconds
            skipCountdown = delaySeconds
            startSkipCountdown()
        } else if !profile.overlay.strictDefault {
            // Not strict mode and no delay - enable skip immediately
            skipEnabled = true
        }
    }
    
    func hideOverlay() {
        skipTimer?.invalidate()
        skipTimer = nil
        
        for window in overlayWindows {
            window.orderOut(nil)
            window.close()
        }
        overlayWindows.removeAll()
    }
    
    // MARK: - Window Creation
    
    private func createOverlayWindow(for screen: NSScreen) -> NSWindow {
        let contentView = OverlayContentView(
            timerEngine: timerEngine!,
            alarmPlayer: alarmPlayer!,
            overlayManager: self,
            profileStore: profileStore!
        )
        
        let hostingView = NSHostingView(rootView: contentView)
        
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        
        window.contentView = hostingView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.isReleasedWhenClosed = false
        
        // Make the window full screen
        window.setFrame(screen.frame, display: true)
        
        return window
    }
    
    // MARK: - Skip Countdown
    
    private func startSkipCountdown() {
        skipTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            self.skipCountdown -= 1
            
            if self.skipCountdown <= 0 {
                self.skipTimer?.invalidate()
                self.skipTimer = nil
                self.skipEnabled = true
            }
        }
    }
    
    // MARK: - Actions
    
    func endBreak() {
        timerEngine?.skip()
    }
    
    func stopAlarm() {
        alarmPlayer?.stop()
    }
}

// MARK: - SwiftUI Overlay Content

struct OverlayContentView: View {
    @ObservedObject var timerEngine: TimerEngine
    @ObservedObject var alarmPlayer: AlarmPlayer
    @ObservedObject var overlayManager: OverlayManager
    @ObservedObject var profileStore: ProfileStore
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.85)
                .ignoresSafeArea()
            
            VStack(spacing: 40) {
                // Phase indicator
                Text(timerEngine.phase.displayName)
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(.white)
                
                // Timer display
                Text(timerEngine.formattedRemaining)
                    .font(.system(size: 120, weight: .light, design: .monospaced))
                    .foregroundColor(.white)
                
                // Progress message
                Text(breakMessage)
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 60)
                
                // Buttons
                HStack(spacing: 20) {
                    // Stop Alarm button (always visible when playing)
                    if alarmPlayer.isPlaying {
                        Button(action: { overlayManager.stopAlarm() }) {
                            HStack {
                                Image(systemName: "speaker.slash.fill")
                                Text("Stop Alarm")
                            }
                            .font(.title3)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.red.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // End Break button (conditional)
                    if showEndBreakButton {
                        Button(action: { overlayManager.endBreak() }) {
                            HStack {
                                Image(systemName: "forward.fill")
                                Text(endBreakButtonText)
                            }
                            .font(.title3)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(buttonBackground)
                            .foregroundColor(buttonForeground)
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                        .disabled(!overlayManager.skipEnabled)
                    }
                }
                .padding(.top, 20)
                
                // Skip countdown message
                if !overlayManager.skipEnabled && profileStore.currentProfile?.overlay.delayedSkipEnabled == true {
                    Text("Skip available in \(overlayManager.skipCountdown)s")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
    }
    
    private var breakMessage: String {
        switch timerEngine.phase {
        case .shortBreak:
            return "Take a short break. Stretch, rest your eyes, grab some water."
        case .longBreak:
            return "Great work! Enjoy your well-deserved long break."
        case .work:
            return "Time to focus!"
        }
    }
    
    private var showEndBreakButton: Bool {
        guard let profile = profileStore.currentProfile else { return false }
        
        // Show if not strict, or if delayed skip is enabled
        return !profile.overlay.strictDefault || profile.overlay.delayedSkipEnabled
    }
    
    private var endBreakButtonText: String {
        if overlayManager.skipEnabled {
            return "End Break"
        } else {
            return "End Break (\(overlayManager.skipCountdown)s)"
        }
    }
    
    private var buttonBackground: Color {
        overlayManager.skipEnabled ? Color.blue.opacity(0.8) : Color.gray.opacity(0.5)
    }
    
    private var buttonForeground: Color {
        overlayManager.skipEnabled ? .white : .white.opacity(0.5)
    }
}
