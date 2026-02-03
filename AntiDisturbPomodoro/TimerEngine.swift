import Foundation
import Combine
import AppKit

/// Core timer state machine managing work/break phases
class TimerEngine: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var phase: TimerPhase = .work
    @Published private(set) var state: TimerState = .idle
    @Published private(set) var remainingSeconds: TimeInterval = 0
    @Published private(set) var completedWorkSessions: Int = 0
    
    // MARK: - Callbacks
    
    var onBreakStart: (() -> Void)?
    var onBreakEnd: (() -> Void)?
    var onWarning: (() -> Void)?
    var onPhaseEnd: (() -> Void)?
    
    // MARK: - Private State
    
    private var phaseEndDate: Date?
    private var pausedRemaining: TimeInterval?
    private var phaseStartDate: Date?
    private var warningFired = false
    
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Dependencies
    
    private let profileStore: ProfileStore
    private let notificationScheduler: NotificationScheduler
    private let alarmPlayer: AlarmPlayer
    private let statsStore: StatsStore
    
    init(
        profileStore: ProfileStore,
        notificationScheduler: NotificationScheduler,
        alarmPlayer: AlarmPlayer,
        statsStore: StatsStore
    ) {
        self.profileStore = profileStore
        self.notificationScheduler = notificationScheduler
        self.alarmPlayer = alarmPlayer
        self.statsStore = statsStore
        
        setupObservers()
    }
    
    private func setupObservers() {
        // Listen for wake from sleep
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                self?.handleWakeFromSleep()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Timer Control
    
    func start() {
        guard let profile = profileStore.currentProfile else { return }
        
        if state == .paused, let remaining = pausedRemaining {
            // Resume from pause
            phaseEndDate = Date().addingTimeInterval(remaining)
            pausedRemaining = nil
            state = .running
            warningFired = false
            scheduleNotifications()
            startTicking()
        } else if state == .idle {
            // Start fresh
            phase = .work
            remainingSeconds = TimeInterval(profile.ruleset.workSeconds)
            phaseEndDate = Date().addingTimeInterval(remainingSeconds)
            phaseStartDate = Date()
            pausedRemaining = nil
            state = .running
            warningFired = false
            scheduleNotifications()
            startTicking()
        }
    }
    
    func pause() {
        guard state == .running, let endDate = phaseEndDate else { return }
        
        pausedRemaining = endDate.timeIntervalSinceNow
        phaseEndDate = nil
        state = .paused
        
        stopTicking()
        cancelNotifications()
    }
    
    func resume() {
        start()
    }
    
    func toggleStartPause() {
        switch state {
        case .idle:
            start()
        case .running:
            pause()
        case .paused:
            resume()
        }
    }
    
    func reset() {
        stopTicking()
        cancelNotifications()
        alarmPlayer.stop()
        
        state = .idle
        phase = .work
        remainingSeconds = 0
        phaseEndDate = nil
        pausedRemaining = nil
        phaseStartDate = nil
        warningFired = false
        completedWorkSessions = 0
        
        // If we were on break, hide overlay
        onBreakEnd?()
    }
    
    func skip() {
        guard let profile = profileStore.currentProfile else { return }
        
        // Log stats for skipped phase
        if let startDate = phaseStartDate {
            let actualSeconds = Int(Date().timeIntervalSince(startDate))
            let plannedSeconds = plannedSecondsForPhase(phase, profile: profile)
            statsStore.log(
                profileId: profile.id,
                phase: phase,
                plannedSeconds: plannedSeconds,
                actualSeconds: actualSeconds,
                completed: false,
                skipped: true,
                strictMode: profile.overlay.strictDefault
            )
        }
        
        // Move to next phase
        alarmPlayer.stop()
        advancePhase()
    }
    
    // MARK: - Private Methods
    
    private func startTicking() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    
    private func stopTicking() {
        timer?.invalidate()
        timer = nil
    }
    
    private func tick() {
        guard state == .running, let endDate = phaseEndDate else { return }
        
        remainingSeconds = max(0, endDate.timeIntervalSinceNow)
        
        // Check for warning
        if let profile = profileStore.currentProfile {
            let warningSecondsInt = phase.isBreak ? profile.notifications.breakWarningSecondsBeforeEnd : profile.notifications.workWarningSecondsBeforeEnd
            let warningSeconds = TimeInterval(warningSecondsInt)
            if remainingSeconds <= warningSeconds && !warningFired && remainingSeconds > 0 {
                warningFired = true
                fireWarning()
            }
        }
        
        // Check for phase end
        if remainingSeconds <= 0 {
            phaseEnded()
        }
    }
    
    private func fireWarning() {
        guard let profile = profileStore.currentProfile else { return }
        
        onWarning?()
        
        // Play warning sound (work vs break)
        let soundId = phase.isBreak ? profile.sounds.breakWarningSoundId : profile.sounds.workWarningSoundId
        if !soundId.isEmpty {
            alarmPlayer.play(soundId: soundId, maxDuration: TimeInterval(profile.alarm.warningPlaySeconds))
        }
    }
    
    private func phaseEnded() {
        guard let profile = profileStore.currentProfile else { return }
        
        stopTicking()
        cancelNotifications()
        
        onPhaseEnd?()
        
        // Log stats
        if let startDate = phaseStartDate {
            let actualSeconds = Int(Date().timeIntervalSince(startDate))
            let plannedSeconds = plannedSecondsForPhase(phase, profile: profile)
            statsStore.log(
                profileId: profile.id,
                phase: phase,
                plannedSeconds: plannedSeconds,
                actualSeconds: actualSeconds,
                completed: true,
                skipped: false,
                strictMode: profile.overlay.strictDefault
            )
        }
        
        // Play end sound with appropriate duration
        // Work ending = break starting, Break ending = work starting
        let soundId: String
        let duration: TimeInterval
        
        if phase == .work {
            // Work ended, break is starting
            soundId = profile.sounds.workEndSoundId
            duration = TimeInterval(profile.alarm.breakStartPlaySeconds)
        } else {
            // Break ended
            soundId = profile.sounds.breakEndSoundId
            duration = TimeInterval(profile.alarm.breakEndPlaySeconds)
        }
        
        alarmPlayer.play(soundId: soundId, maxDuration: duration)
        
        // Track completed work sessions
        if phase == .work {
            completedWorkSessions += 1
        }
        
        // Advance phase
        advancePhase()
    }
    
    private func advancePhase() {
        guard let profile = profileStore.currentProfile else { return }
        
        let wasBreak = phase.isBreak
        
        // Determine next phase
        if phase == .work {
            if completedWorkSessions > 0 && completedWorkSessions % profile.ruleset.longBreakEvery == 0 {
                phase = .longBreak
            } else {
                phase = .shortBreak
            }
        } else {
            phase = .work
        }
        
        // Calculate duration
        let duration = TimeInterval(plannedSecondsForPhase(phase, profile: profile))
        remainingSeconds = duration
        warningFired = false
        
        // Handle break start/end callbacks
        if phase.isBreak && !wasBreak {
            onBreakStart?()
        } else if !phase.isBreak && wasBreak {
            onBreakEnd?()
        }
        
        // Auto-start based on settings
        if phase == .work && profile.features.autoStartWork {
            phaseEndDate = Date().addingTimeInterval(duration)
            phaseStartDate = Date()
            state = .running
            scheduleNotifications()
            startTicking()
        } else if phase.isBreak {
            // Always auto-start breaks
            phaseEndDate = Date().addingTimeInterval(duration)
            phaseStartDate = Date()
            state = .running
            scheduleNotifications()
            startTicking()
        } else {
            // Manual start required
            state = .idle
            phaseEndDate = nil
            phaseStartDate = nil
        }
    }
    
    private func plannedSecondsForPhase(_ phase: TimerPhase, profile: ProfileData) -> Int {
        switch phase {
        case .work: return profile.ruleset.workSeconds
        case .shortBreak: return profile.ruleset.shortBreakSeconds
        case .longBreak: return profile.ruleset.longBreakSeconds
        }
    }
    
    // MARK: - Notifications
    
    private func scheduleNotifications() {
        guard let profile = profileStore.currentProfile,
              let endDate = phaseEndDate,
              profile.notifications.bannerEnabled else { return }
        
        let warningSecondsInt = phase.isBreak ? profile.notifications.breakWarningSecondsBeforeEnd : profile.notifications.workWarningSecondsBeforeEnd
        let warningSeconds = TimeInterval(warningSecondsInt)
        let warningDate = endDate.addingTimeInterval(-warningSeconds)
        
        // Schedule warning notification
        if warningDate > Date() {
            notificationScheduler.scheduleWarning(at: warningDate, phase: phase)
        }
        
        // Schedule end notification
        notificationScheduler.schedulePhaseEnd(at: endDate, phase: phase)
    }
    
    private func cancelNotifications() {
        notificationScheduler.cancelAll()
    }
    
    // MARK: - Sleep/Wake Handling
    
    private func handleWakeFromSleep() {
        guard state == .running, let endDate = phaseEndDate else { return }
        
        let remaining = endDate.timeIntervalSinceNow
        
        if remaining <= 0 {
            // Phase ended while sleeping
            remainingSeconds = 0
            phaseEnded()
        } else {
            remainingSeconds = remaining
            // Reschedule notifications
            cancelNotifications()
            scheduleNotifications()
        }
    }
    
    // MARK: - State Persistence
    
    func saveState() {
        // Save current state for potential restoration
        // Implementation optional for v1
    }
    
    func restoreState() {
        // Restore state from previous session
        // Implementation optional for v1
    }
    
    // MARK: - Display Helpers
    
    var formattedRemaining: String {
        let minutes = Int(remainingSeconds) / 60
        let seconds = Int(remainingSeconds) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

