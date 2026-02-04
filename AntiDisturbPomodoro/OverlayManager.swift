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
    @Published var isShowingPostBreakHold: Bool = false
    
    private var skipTimer: Timer?
    
    // MARK: - Screen Tracking (Optimization)
    private var windowScreens: Set<ObjectIdentifier> = []
    
    init(timerEngine: TimerEngine, alarmPlayer: AlarmPlayer, profileStore: ProfileStore) {
        self.timerEngine = timerEngine
        self.alarmPlayer = alarmPlayer
        self.profileStore = profileStore
        super.init()
        
        timerEngine.$isHoldingAfterBreak
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isHolding in
                guard let self = self else { return }
                let wasHolding = self.isShowingPostBreakHold
                self.isShowingPostBreakHold = isHolding
                
                if isHolding != wasHolding && !self.overlayWindows.isEmpty {
                    self.refreshOverlayContent()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Show/Hide Overlay
    
    func showOverlay() {
        hideOverlay()
        
        guard let profile = profileStore?.currentProfile else { return }
        
        skipEnabled = false
        skipCountdown = 0
        isShowingPostBreakHold = false
        windowScreens.removeAll()
        
        for screen in NSScreen.screens {
            let window = createOverlayWindow(for: screen)
            overlayWindows.append(window)
            windowScreens.insert(ObjectIdentifier(screen))
            window.orderFrontRegardless()
        }
        
        if profile.overlay.delayedSkipEnabled && !profile.overlay.strictDefault {
            let delaySeconds = profile.overlay.delayedSkipSeconds
            skipCountdown = delaySeconds
            startSkipCountdown()
        } else if !profile.overlay.strictDefault {
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
        windowScreens.removeAll()
        isShowingPostBreakHold = false
    }
    
    // MARK: - Optimized Content Refresh
    
    private func refreshOverlayContent() {
        guard !overlayWindows.isEmpty else { return }
        
        guard let timerEngine = timerEngine,
              let alarmPlayer = alarmPlayer,
              let profileStore = profileStore else { return }
        
        let currentScreens = Set(NSScreen.screens.map { ObjectIdentifier($0) })
        
        if currentScreens != windowScreens {
            let wasShowing = !overlayWindows.isEmpty
            hideOverlay()
            
            if wasShowing {
                for screen in NSScreen.screens {
                    let window = createOverlayWindow(for: screen)
                    overlayWindows.append(window)
                    windowScreens.insert(ObjectIdentifier(screen))
                    window.orderFrontRegardless()
                }
            }
        } else {
            for window in overlayWindows {
                let contentView = OverlayContentView(
                    timerEngine: timerEngine,
                    alarmPlayer: alarmPlayer,
                    overlayManager: self,
                    profileStore: profileStore
                )
                window.contentView = NSHostingView(rootView: contentView)
            }
        }
    }
    
    // MARK: - Window Creation
    
    private func createOverlayWindow(for screen: NSScreen) -> NSWindow {
        guard let timerEngine = timerEngine,
              let alarmPlayer = alarmPlayer,
              let profileStore = profileStore else {
            fatalError("Required dependencies not available")
        }
        
        let contentView = OverlayContentView(
            timerEngine: timerEngine,
            alarmPlayer: alarmPlayer,
            overlayManager: self,
            profileStore: profileStore
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
    
    func requestExtraTime() {
        timerEngine?.requestExtraTime()
    }
    
    func confirmStartWork() {
        timerEngine?.confirmStartWork()
    }
    
    func cancelAfterBreak() {
        timerEngine?.cancelAfterBreak()
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
            Color.black.opacity(0.85)
                .ignoresSafeArea()
            
            if timerEngine.isHoldingAfterBreak {
                postBreakHoldView
            } else {
                normalBreakView
            }
        }
    }
    
    // MARK: - Normal Break View
    
    private var normalBreakView: some View {
        VStack(spacing: 40) {
            Text(timerEngine.phase.displayName)
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(.white)
            
            Text(timerEngine.formattedRemaining)
                .font(.system(size: 120, weight: .light, design: .monospaced))
                .foregroundColor(.white)
            
            Text(breakMessage)
                .font(.title2)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 60)
            
            VStack(spacing: 16) {
                HStack(spacing: 20) {
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
                
                if showExtraTimeButton {
                    Button(action: { overlayManager.requestExtraTime() }) {
                        HStack {
                            Image(systemName: "clock.badge.plus")
                            Text("I need \(extraTimeText)")
                        }
                        .font(.title3)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.orange.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 20)
            
            if !overlayManager.skipEnabled && profileStore.currentProfile?.overlay.delayedSkipEnabled == true {
                Text("Skip available in \(overlayManager.skipCountdown)s")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }
    
    // MARK: - Post-Break Hold View
    
    private var postBreakHoldView: some View {
        VStack(spacing: 40) {
            Text("Break Complete!")
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(.white)
            
            Text("00:00")
                .font(.system(size: 120, weight: .light, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
            
            Text("Ready to start your next work session?")
                .font(.title2)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            
            HStack(spacing: 20) {
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
                
                Button(action: { overlayManager.confirmStartWork() }) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Start Work")
                    }
                    .font(.title3)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.green.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                
                Button(action: { overlayManager.cancelAfterBreak() }) {
                    HStack {
                        Image(systemName: "xmark")
                        Text("Cancel")
                    }
                    .font(.title3)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.gray.opacity(0.6))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 20)
        }
    }
    
    // MARK: - Computed Properties
    
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
        return !profile.overlay.strictDefault || profile.overlay.delayedSkipEnabled
    }
    
    private var showExtraTimeButton: Bool {
        guard let profile = profileStore.currentProfile else { return false }
        return profile.overlay.extraTimeEnabled && !timerEngine.isInExtraTime
    }
    
    /// Formats extra time text:
    /// - Whole minutes: "1 min", "2 min", etc.
    /// - Non-whole minutes: "1 min and 30 seconds", "2 min and 15 seconds", etc.
    private var extraTimeText: String {
        guard let profile = profileStore.currentProfile else { return "1 min" }
        let totalSeconds = profile.overlay.extraTimeSeconds
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        
        if seconds == 0 {
            // Whole minutes
            return "\(minutes) min"
        } else if minutes == 0 {
            // Only seconds (less than a minute)
            return "\(seconds) seconds"
        } else {
            // Minutes and seconds
            return "\(minutes) min and \(seconds) seconds"
        }
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
