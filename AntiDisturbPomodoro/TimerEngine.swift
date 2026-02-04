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
    
    // Extra time (ignore break) state
    @Published private(set) var isInExtraTime: Bool = false
    @Published private(set) var extraTimeRemaining: TimeInterval = 0
    @Published private(set) var savedBreakRemaining: TimeInterval = 0
    
    // Post-break hold state
    @Published private(set) var isHoldingAfterBreak: Bool = false
    
    // MARK: - Callbacks
    
    var onBreakStart: (() -> Void)?
    var onBreakEnd: (() -> Void)?
    var onWarning: (() -> Void)?
    var onPhaseEnd: (() -> Void)?
    var onExtraTimeEnd: (() -> Void)?
    var onHoldAfterBreak: (() -> Void)?
    
    // MARK: - Private State
    
    private var phaseEndDate: Date?
    private var pausedRemaining: TimeInterval?
    private var phaseStartDate: Date?
    private var warningFired = false
    private var extraTimeEndDate: Date?
    
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Cached Values for Display (CPU optimization)
    
    private var _cachedFormattedRemaining: String = "00:00"
    private var _lastFormattedSeconds: Int = -1
    
    private var _cachedFormattedExtraTime: String = "00:00"
    private var _lastFormattedExtraSeconds: Int = -1
    
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
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                self?.handleWakeFromSleep()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Timer Control
    
    func start() {
        guard let profile = profileStore.currentProfile else { return }
        
        if isHoldingAfterBreak {
            isHoldingAfterBreak = false
            startWorkSession()
            return
        }
        
        if state == .paused, let remaining = pausedRemaining {
            phaseEndDate = Date().addingTimeInterval(remaining)
            pausedRemaining = nil
            state = .running
            warningFired = false
            scheduleNotifications()
            startTicking()
        } else if state == .idle {
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
    
    private func startWorkSession() {
        guard let profile = profileStore.currentProfile else { return }
        
        phase = .work
        let duration = TimeInterval(profile.ruleset.workSeconds)
        remainingSeconds = duration
        phaseEndDate = Date().addingTimeInterval(duration)
        phaseStartDate = Date()
        pausedRemaining = nil
        state = .running
        warningFired = false
        
        onBreakEnd?()
        scheduleNotifications()
        startTicking()
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
        isInExtraTime = false
        extraTimeRemaining = 0
        savedBreakRemaining = 0
        extraTimeEndDate = nil
        isHoldingAfterBreak = false
        
        _lastFormattedSeconds = -1
        _lastFormattedExtraSeconds = -1
        
        onBreakEnd?()
    }
    
    func skip() {
        guard let profile = profileStore.currentProfile else { return }
        
        if isHoldingAfterBreak {
            isHoldingAfterBreak = false
            state = .idle
            onBreakEnd?()
            return
        }
        
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
        
        alarmPlayer.stop()
        advancePhase()
    }
    
    // MARK: - Extra Time (Ignore Break)
    
    func requestExtraTime() {
        guard let profile = profileStore.currentProfile,
              phase.isBreak,
              state == .running,
              !isInExtraTime else { return }
        
        savedBreakRemaining = remainingSeconds
        
        stopTicking()
        cancelNotifications()
        
        isInExtraTime = true
        let extraSeconds = TimeInterval(profile.overlay.extraTimeSeconds)
        extraTimeRemaining = extraSeconds
        extraTimeEndDate = Date().addingTimeInterval(extraSeconds)
        
        onBreakEnd?()
        
        startTicking()
    }
    
    func endExtraTimeEarly() {
        guard isInExtraTime else { return }
        finishExtraTime()
    }
    
    private func finishExtraTime() {
        isInExtraTime = false
        extraTimeEndDate = nil
        extraTimeRemaining = 0
        
        if savedBreakRemaining > 0 {
            remainingSeconds = savedBreakRemaining
            phaseEndDate = Date().addingTimeInterval(savedBreakRemaining)
            savedBreakRemaining = 0
            warningFired = false
            
            onBreakStart?()
            
            scheduleNotifications()
        } else {
            advancePhase()
        }
        
        onExtraTimeEnd?()
    }
    
    // MARK: - Post-Break Hold
    
    func confirmStartWork() {
        guard isHoldingAfterBreak else { return }
        isHoldingAfterBreak = false
        startWorkSession()
    }
    
    func cancelAfterBreak() {
        guard isHoldingAfterBreak else { return }
        isHoldingAfterBreak = false
        state = .idle
        phase = .work
        remainingSeconds = 0
        onBreakEnd?()
    }
    
    // MARK: - Private Methods
    
    private func startTicking() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tick()
        }
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    
    private func stopTicking() {
        timer?.invalidate()
        timer = nil
    }
    
    private func tick() {
        if isInExtraTime {
            guard let endDate = extraTimeEndDate else { return }
            extraTimeRemaining = max(0, endDate.timeIntervalSinceNow)
            
            if extraTimeRemaining <= 0 {
                finishExtraTime()
            }
            return
        }
        
        guard state == .running, let endDate = phaseEndDate else { return }
        
        remainingSeconds = max(0, endDate.timeIntervalSinceNow)
        
        if let profile = profileStore.currentProfile {
            let warningSecondsInt = phase.isBreak ? profile.notifications.breakWarningSecondsBeforeEnd : profile.notifications.workWarningSecondsBeforeEnd
            let warningSeconds = TimeInterval(warningSecondsInt)
            if remainingSeconds <= warningSeconds && !warningFired && remainingSeconds > 0 {
                warningFired = true
                fireWarning()
            }
        }
        
        if remainingSeconds <= 0 {
            phaseEnded()
        }
    }
    
    private func fireWarning() {
        guard let profile = profileStore.currentProfile else { return }
        
        onWarning?()
        
        let soundId = phase.isBreak ? profile.sounds.breakWarningSoundId : profile.sounds.workWarningSoundId
        let value = phase.isBreak ? profile.alarm.breakWarningPlayValue : profile.alarm.workWarningPlayValue
        let mode = phase.isBreak ? profile.alarm.breakWarningPlayMode : profile.alarm.workWarningPlayMode
        let volume = phase.isBreak ? profile.alarm.breakWarningVolume : profile.alarm.workWarningVolume
        
        if !soundId.isEmpty && soundId != "none" {
            alarmPlayer.play(soundId: soundId, value: value, mode: mode, volume: volume)
        }
    }
    
    private func phaseEnded() {
        guard let profile = profileStore.currentProfile else { return }
        
        stopTicking()
        cancelNotifications()
        
        onPhaseEnd?()
        
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
        
        // Play end sound with appropriate duration mode and volume
        let soundId: String
        let value: Int
        let mode: AlarmDurationMode
        
        if phase == .work {
            // Work ended, break is starting
            soundId = profile.sounds.workEndSoundId
            value = profile.alarm.breakStartPlayValue
            mode = profile.alarm.breakStartPlayMode
        } else {
            // Break ended
            soundId = profile.sounds.breakEndSoundId
            value = profile.alarm.breakEndPlayValue
            mode = profile.alarm.breakEndPlayMode
        }
        
        if !soundId.isEmpty && soundId != "none" {
            let volume = (phase == .work) ? profile.alarm.workEndVolume : profile.alarm.breakEndVolume
            alarmPlayer.play(soundId: soundId, value: value, mode: mode, volume: volume)
        }
        
        if phase == .work {
            completedWorkSessions += 1
        }
        
        if phase.isBreak && profile.overlay.holdAfterBreak {
            isHoldingAfterBreak = true
            state = .idle
            remainingSeconds = 0
            onHoldAfterBreak?()
            return
        }
        
        advancePhase()
    }
    
    private func advancePhase() {
        guard let profile = profileStore.currentProfile else { return }
        
        let wasBreak = phase.isBreak
        
        if phase == .work {
            if completedWorkSessions > 0 && completedWorkSessions % profile.ruleset.longBreakEvery == 0 {
                phase = .longBreak
            } else {
                phase = .shortBreak
            }
        } else {
            phase = .work
        }
        
        let duration = TimeInterval(plannedSecondsForPhase(phase, profile: profile))
        remainingSeconds = duration
        warningFired = false
        
        if phase.isBreak && !wasBreak {
            onBreakStart?()
        } else if !phase.isBreak && wasBreak {
            onBreakEnd?()
        }
        
        if phase == .work && profile.features.autoStartWork {
            phaseEndDate = Date().addingTimeInterval(duration)
            phaseStartDate = Date()
            state = .running
            scheduleNotifications()
            startTicking()
        } else if phase.isBreak {
            phaseEndDate = Date().addingTimeInterval(duration)
            phaseStartDate = Date()
            state = .running
            scheduleNotifications()
            startTicking()
        } else {
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
        
        if warningDate > Date() {
            notificationScheduler.scheduleWarning(at: warningDate, phase: phase)
        }
        
        notificationScheduler.schedulePhaseEnd(at: endDate, phase: phase)
    }
    
    private func cancelNotifications() {
        notificationScheduler.cancelAll()
    }
    
    // MARK: - Sleep/Wake Handling
    
    private func handleWakeFromSleep() {
        if isInExtraTime, let endDate = extraTimeEndDate {
            let remaining = endDate.timeIntervalSinceNow
            if remaining <= 0 {
                finishExtraTime()
            } else {
                extraTimeRemaining = remaining
            }
            return
        }
        
        guard state == .running, let endDate = phaseEndDate else { return }
        
        let remaining = endDate.timeIntervalSinceNow
        
        if remaining <= 0 {
            remainingSeconds = 0
            phaseEnded()
        } else {
            remainingSeconds = remaining
            cancelNotifications()
            scheduleNotifications()
        }
    }
    
    // MARK: - State Persistence
    
    func saveState() {
        // Implementation optional for v1
    }
    
    func restoreState() {
        // Implementation optional for v1
    }
    
    // MARK: - Display Helpers (Optimized with caching)
    
    var formattedRemaining: String {
        let seconds = isInExtraTime ? extraTimeRemaining : remainingSeconds
        let intSeconds = Int(seconds)
        
        if intSeconds != _lastFormattedSeconds {
            let minutes = intSeconds / 60
            let secs = intSeconds % 60
            _cachedFormattedRemaining = String(format: "%02d:%02d", minutes, secs)
            _lastFormattedSeconds = intSeconds
        }
        return _cachedFormattedRemaining
    }
    
    var formattedExtraTimeRemaining: String {
        let intSeconds = Int(extraTimeRemaining)
        
        if intSeconds != _lastFormattedExtraSeconds {
            let minutes = intSeconds / 60
            let seconds = intSeconds % 60
            _cachedFormattedExtraTime = String(format: "%02d:%02d", minutes, seconds)
            _lastFormattedExtraSeconds = intSeconds
        }
        return _cachedFormattedExtraTime
    }
}
