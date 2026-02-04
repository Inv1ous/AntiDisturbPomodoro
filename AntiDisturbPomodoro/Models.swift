import Foundation

// MARK: - Sound Models

struct SoundLibraryData: Codable {
    var version: Int = 1
    var sounds: [SoundEntry]
}

struct SoundEntry: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var format: String
    var source: SoundSource
    var path: String
    
    enum SoundSource: String, Codable {
        case builtIn = "built_in"
        case imported = "imported"
    }
}

// MARK: - Profile Models

struct ProfileData: Codable, Identifiable {
    var version: Int = 1
    var id: String
    var name: String
    var ruleset: Ruleset
    var sounds: SoundSettings
    var notifications: NotificationSettings
    var alarm: AlarmSettings
    var overlay: OverlaySettings
    var features: FeatureSettings
    var hotkeys: HotkeySettings
    
    static func createDefault(id: String = "default", name: String = "Default") -> ProfileData {
        ProfileData(
            version: 1,
            id: id,
            name: name,
            ruleset: Ruleset(),
            sounds: SoundSettings(),
            notifications: NotificationSettings(),
            alarm: AlarmSettings(),
            overlay: OverlaySettings(),
            features: FeatureSettings(),
            hotkeys: HotkeySettings()
        )
    }
}

struct Ruleset: Codable, Equatable {
    var workSeconds: Int = 1500        // 25 minutes
    var shortBreakSeconds: Int = 300   // 5 minutes
    var longBreakSeconds: Int = 900    // 15 minutes
    var longBreakEvery: Int = 4        // Every 4 work sessions
}

struct SoundSettings: Codable, Equatable {
    var workEndSoundId: String = "builtin.chime"
    var breakEndSoundId: String = "builtin.chime"
    var workWarningSoundId: String = "builtin.chime"
    var breakWarningSoundId: String = "builtin.chime"

    init() {}

    init(workEndSoundId: String, breakEndSoundId: String, workWarningSoundId: String, breakWarningSoundId: String) {
        self.workEndSoundId = workEndSoundId
        self.breakEndSoundId = breakEndSoundId
        self.workWarningSoundId = workWarningSoundId
        self.breakWarningSoundId = breakWarningSoundId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        workEndSoundId = try container.decodeIfPresent(String.self, forKey: .workEndSoundId) ?? "builtin.chime"
        breakEndSoundId = try container.decodeIfPresent(String.self, forKey: .breakEndSoundId) ?? "builtin.chime"

        if let ww = try container.decodeIfPresent(String.self, forKey: .workWarningSoundId),
           let bw = try container.decodeIfPresent(String.self, forKey: .breakWarningSoundId) {
            workWarningSoundId = ww
            breakWarningSoundId = bw
        } else if let legacy = try container.decodeIfPresent(String.self, forKey: .warningSoundId) {
            workWarningSoundId = legacy
            breakWarningSoundId = legacy
        } else {
            workWarningSoundId = "builtin.chime"
            breakWarningSoundId = "builtin.chime"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case workEndSoundId
        case breakEndSoundId
        case workWarningSoundId
        case breakWarningSoundId
        case warningSoundId
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(workEndSoundId, forKey: .workEndSoundId)
        try container.encode(breakEndSoundId, forKey: .breakEndSoundId)
        try container.encode(workWarningSoundId, forKey: .workWarningSoundId)
        try container.encode(breakWarningSoundId, forKey: .breakWarningSoundId)
    }
}

struct NotificationSettings: Codable, Equatable {
    var workWarningSecondsBeforeEnd: Int = 60
    var breakWarningSecondsBeforeEnd: Int = 60
    var bannerEnabled: Bool = true

    init() {}

    init(workWarningSecondsBeforeEnd: Int, breakWarningSecondsBeforeEnd: Int, bannerEnabled: Bool) {
        self.workWarningSecondsBeforeEnd = workWarningSecondsBeforeEnd
        self.breakWarningSecondsBeforeEnd = breakWarningSecondsBeforeEnd
        self.bannerEnabled = bannerEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let oldWarning = try? container.decode(Int.self, forKey: .warningSecondsBeforeEnd) {
            workWarningSecondsBeforeEnd = oldWarning
            breakWarningSecondsBeforeEnd = oldWarning
            bannerEnabled = try container.decodeIfPresent(Bool.self, forKey: .bannerEnabled) ?? true
        } else {
            workWarningSecondsBeforeEnd = try container.decodeIfPresent(Int.self, forKey: .workWarningSecondsBeforeEnd) ?? 60
            breakWarningSecondsBeforeEnd = try container.decodeIfPresent(Int.self, forKey: .breakWarningSecondsBeforeEnd) ?? 60
            bannerEnabled = try container.decodeIfPresent(Bool.self, forKey: .bannerEnabled) ?? true
        }
    }

    private enum CodingKeys: String, CodingKey {
        case workWarningSecondsBeforeEnd
        case breakWarningSecondsBeforeEnd
        case bannerEnabled
        case warningSecondsBeforeEnd
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(workWarningSecondsBeforeEnd, forKey: .workWarningSecondsBeforeEnd)
        try container.encode(breakWarningSecondsBeforeEnd, forKey: .breakWarningSecondsBeforeEnd)
        try container.encode(bannerEnabled, forKey: .bannerEnabled)
    }
}

// MARK: - Alarm Duration Mode

/// Specifies whether alarm duration is measured in seconds or loop count
enum AlarmDurationMode: String, Codable, Equatable, CaseIterable {
    case seconds = "seconds"
    case loopCount = "loopCount"
    
    var displayName: String {
        switch self {
        case .seconds: return "seconds"
        case .loopCount: return "times"
        }
    }
}

struct AlarmSettings: Codable, Equatable {
    // Duration values (interpreted based on mode)
    var workWarningPlayValue: Int = 5
    var breakWarningPlayValue: Int = 5
    var breakStartPlayValue: Int = 10
    var breakEndPlayValue: Int = 10
    
    // Duration modes
    var workWarningPlayMode: AlarmDurationMode = .seconds
    var breakWarningPlayMode: AlarmDurationMode = .seconds
    var breakStartPlayMode: AlarmDurationMode = .seconds
    var breakEndPlayMode: AlarmDurationMode = .seconds
    
    /// Per-event volume scalars (UI range: 0.0 ... 2.0)
    var workEndVolume: Double = 1.0
    var breakEndVolume: Double = 1.0
    var workWarningVolume: Double = 1.0
    var breakWarningVolume: Double = 1.0
    
    init() {}
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Try new format first (with modes)
        if let workWarningVal = try? container.decode(Int.self, forKey: .workWarningPlayValue) {
            workWarningPlayValue = workWarningVal
            breakWarningPlayValue = try container.decodeIfPresent(Int.self, forKey: .breakWarningPlayValue) ?? 5
            breakStartPlayValue = try container.decodeIfPresent(Int.self, forKey: .breakStartPlayValue) ?? 10
            breakEndPlayValue = try container.decodeIfPresent(Int.self, forKey: .breakEndPlayValue) ?? 10
            
            workWarningPlayMode = try container.decodeIfPresent(AlarmDurationMode.self, forKey: .workWarningPlayMode) ?? .seconds
            breakWarningPlayMode = try container.decodeIfPresent(AlarmDurationMode.self, forKey: .breakWarningPlayMode) ?? .seconds
            breakStartPlayMode = try container.decodeIfPresent(AlarmDurationMode.self, forKey: .breakStartPlayMode) ?? .seconds
            breakEndPlayMode = try container.decodeIfPresent(AlarmDurationMode.self, forKey: .breakEndPlayMode) ?? .seconds
        }
        // Try previous format (workWarningPlaySeconds)
        else if let workWarning = try? container.decode(Int.self, forKey: .workWarningPlaySeconds) {
            workWarningPlayValue = workWarning
            breakWarningPlayValue = try container.decodeIfPresent(Int.self, forKey: .breakWarningPlaySeconds) ?? 5
            breakStartPlayValue = try container.decodeIfPresent(Int.self, forKey: .breakStartPlaySeconds) ?? 10
            breakEndPlayValue = try container.decodeIfPresent(Int.self, forKey: .breakEndPlaySeconds) ?? 10
            
            workWarningPlayMode = .seconds
            breakWarningPlayMode = .seconds
            breakStartPlayMode = .seconds
            breakEndPlayMode = .seconds
        }
        // Try old single warning format
        else if let oldWarning = try? container.decode(Int.self, forKey: .warningPlaySeconds) {
            workWarningPlayValue = oldWarning
            breakWarningPlayValue = oldWarning
            breakStartPlayValue = try container.decodeIfPresent(Int.self, forKey: .breakStartPlaySeconds) ?? 10
            breakEndPlayValue = try container.decodeIfPresent(Int.self, forKey: .breakEndPlaySeconds) ?? 10
            
            workWarningPlayMode = .seconds
            breakWarningPlayMode = .seconds
            breakStartPlayMode = .seconds
            breakEndPlayMode = .seconds
        }
        // Try oldest single max-play format
        else if let maxPlay = try? container.decode(Int.self, forKey: .maxPlaySeconds) {
            workWarningPlayValue = maxPlay
            breakWarningPlayValue = maxPlay
            breakStartPlayValue = maxPlay
            breakEndPlayValue = maxPlay
            
            workWarningPlayMode = .seconds
            breakWarningPlayMode = .seconds
            breakStartPlayMode = .seconds
            breakEndPlayMode = .seconds
        }
        // Fallback defaults
        else {
            workWarningPlayValue = 5
            breakWarningPlayValue = 5
            breakStartPlayValue = 10
            breakEndPlayValue = 10
            
            workWarningPlayMode = .seconds
            breakWarningPlayMode = .seconds
            breakStartPlayMode = .seconds
            breakEndPlayMode = .seconds
        }
        
        // Volume
        let legacyVolume = try container.decodeIfPresent(Double.self, forKey: .volume) ?? 1.0
        workEndVolume = Self.clampVolume(try container.decodeIfPresent(Double.self, forKey: .workEndVolume) ?? legacyVolume)
        breakEndVolume = Self.clampVolume(try container.decodeIfPresent(Double.self, forKey: .breakEndVolume) ?? legacyVolume)
        workWarningVolume = Self.clampVolume(try container.decodeIfPresent(Double.self, forKey: .workWarningVolume) ?? legacyVolume)
        breakWarningVolume = Self.clampVolume(try container.decodeIfPresent(Double.self, forKey: .breakWarningVolume) ?? legacyVolume)
    }
    
    private enum CodingKeys: String, CodingKey {
        case workWarningPlayValue
        case breakWarningPlayValue
        case breakStartPlayValue
        case breakEndPlayValue
        case workWarningPlayMode
        case breakWarningPlayMode
        case breakStartPlayMode
        case breakEndPlayMode
        case workEndVolume
        case breakEndVolume
        case workWarningVolume
        case breakWarningVolume
        case volume
        // Legacy keys for migration
        case workWarningPlaySeconds
        case breakWarningPlaySeconds
        case breakStartPlaySeconds
        case breakEndPlaySeconds
        case warningPlaySeconds
        case maxPlaySeconds
    }

    private static func clampVolume(_ value: Double) -> Double {
        max(0.0, min(2.0, value))
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(workWarningPlayValue, forKey: .workWarningPlayValue)
        try container.encode(breakWarningPlayValue, forKey: .breakWarningPlayValue)
        try container.encode(breakStartPlayValue, forKey: .breakStartPlayValue)
        try container.encode(breakEndPlayValue, forKey: .breakEndPlayValue)
        
        try container.encode(workWarningPlayMode, forKey: .workWarningPlayMode)
        try container.encode(breakWarningPlayMode, forKey: .breakWarningPlayMode)
        try container.encode(breakStartPlayMode, forKey: .breakStartPlayMode)
        try container.encode(breakEndPlayMode, forKey: .breakEndPlayMode)

        try container.encode(Self.clampVolume(workEndVolume), forKey: .workEndVolume)
        try container.encode(Self.clampVolume(breakEndVolume), forKey: .breakEndVolume)
        try container.encode(Self.clampVolume(workWarningVolume), forKey: .workWarningVolume)
        try container.encode(Self.clampVolume(breakWarningVolume), forKey: .breakWarningVolume)
    }
}

struct OverlaySettings: Codable, Equatable {
    var strictDefault: Bool = false
    var delayedSkipEnabled: Bool = false
    var delayedSkipSeconds: Int = 30
    
    var extraTimeEnabled: Bool = true
    var extraTimeSeconds: Int = 60
    
    var holdAfterBreak: Bool = false
    
    init() {}
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        strictDefault = try container.decodeIfPresent(Bool.self, forKey: .strictDefault) ?? true
        delayedSkipEnabled = try container.decodeIfPresent(Bool.self, forKey: .delayedSkipEnabled) ?? false
        delayedSkipSeconds = try container.decodeIfPresent(Int.self, forKey: .delayedSkipSeconds) ?? 30
        extraTimeEnabled = try container.decodeIfPresent(Bool.self, forKey: .extraTimeEnabled) ?? true
        extraTimeSeconds = try container.decodeIfPresent(Int.self, forKey: .extraTimeSeconds) ?? 60
        holdAfterBreak = try container.decodeIfPresent(Bool.self, forKey: .holdAfterBreak) ?? false
    }
    
    private enum CodingKeys: String, CodingKey {
        case strictDefault
        case delayedSkipEnabled
        case delayedSkipSeconds
        case extraTimeEnabled
        case extraTimeSeconds
        case holdAfterBreak
    }
}

struct FeatureSettings: Codable, Equatable {
    var autoStartWork: Bool = false
    var dailyStartEnabled: Bool = false
    var dailyStartTimeHHMM: String = "09:00"
    var menuBarCountdownTextEnabled: Bool = false
    var focusModeIntegrationEnabled: Bool = false
    var menuBarIcons: MenuBarIconSettings = MenuBarIconSettings()

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoStartWork = try container.decodeIfPresent(Bool.self, forKey: .autoStartWork) ?? false
        dailyStartEnabled = try container.decodeIfPresent(Bool.self, forKey: .dailyStartEnabled) ?? false
        dailyStartTimeHHMM = try container.decodeIfPresent(String.self, forKey: .dailyStartTimeHHMM) ?? "09:00"
        menuBarCountdownTextEnabled = try container.decodeIfPresent(Bool.self, forKey: .menuBarCountdownTextEnabled) ?? false
        focusModeIntegrationEnabled = try container.decodeIfPresent(Bool.self, forKey: .focusModeIntegrationEnabled) ?? false
        menuBarIcons = try container.decodeIfPresent(MenuBarIconSettings.self, forKey: .menuBarIcons) ?? MenuBarIconSettings()
    }

    private enum CodingKeys: String, CodingKey {
        case autoStartWork
        case dailyStartEnabled
        case dailyStartTimeHHMM
        case menuBarCountdownTextEnabled
        case focusModeIntegrationEnabled
        case menuBarIcons
    }
}

struct MenuBarIconSettings: Codable, Equatable {
    var useCustomIcons: Bool = false
    var idleIcon: String = "🍅"
    var workIcon: String = "🍅"
    var breakIcon: String = "☕️"
    var pausedIcon: String = "⏸️"
}

struct HotkeySettings: Codable, Equatable {
    var startPause: String = "cmd+shift+p"
    var stopAlarm: String = "cmd+shift+s"
    var skipPhase: String = "cmd+shift+k"
}

// MARK: - Stats Models

struct StatsEntry: Codable {
    var ts: String
    var profileId: String
    var phase: TimerPhase
    var plannedSeconds: Int
    var actualSeconds: Int
    var completed: Bool
    var skipped: Bool
    var strictMode: Bool
    
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    static func create(
        profileId: String,
        phase: TimerPhase,
        plannedSeconds: Int,
        actualSeconds: Int,
        completed: Bool,
        skipped: Bool,
        strictMode: Bool
    ) -> StatsEntry {
        return StatsEntry(
            ts: iso8601Formatter.string(from: Date()),
            profileId: profileId,
            phase: phase,
            plannedSeconds: plannedSeconds,
            actualSeconds: actualSeconds,
            completed: completed,
            skipped: skipped,
            strictMode: strictMode
        )
    }
}

// MARK: - Timer Models

enum TimerPhase: String, Codable, Equatable {
    case work
    case shortBreak
    case longBreak
    
    var displayName: String {
        switch self {
        case .work: return "Work"
        case .shortBreak: return "Short Break"
        case .longBreak: return "Long Break"
        }
    }
    
    var isBreak: Bool {
        self == .shortBreak || self == .longBreak
    }
}

enum TimerState: Equatable {
    case idle
    case running
    case paused
}

struct RuntimeState: Codable {
    var profileId: String
    var phase: TimerPhase
    var phaseEndDate: Date?
    var pausedRemaining: TimeInterval?
    var completedWorkSessions: Int
    var isRunning: Bool
}

// MARK: - Stats Summary

struct StatsSummary {
    var totalSessions: Int = 0
    var completedSessions: Int = 0
    var totalFocusMinutes: Int = 0
    var skippedSessions: Int = 0
    
    static let empty = StatsSummary()
}
