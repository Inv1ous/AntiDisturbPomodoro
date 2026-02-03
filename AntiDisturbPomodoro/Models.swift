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

        // End sounds (new keys or defaults)
        workEndSoundId = try container.decodeIfPresent(String.self, forKey: .workEndSoundId) ?? "builtin.chime"
        breakEndSoundId = try container.decodeIfPresent(String.self, forKey: .breakEndSoundId) ?? "builtin.chime"

        // Warning sounds: prefer new keys, migrate from old single key if needed
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
        case warningSoundId // legacy single warning sound id
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

        // Migrate from old single-value key if present
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
        case warningSecondsBeforeEnd // Old key for migration
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(workWarningSecondsBeforeEnd, forKey: .workWarningSecondsBeforeEnd)
        try container.encode(breakWarningSecondsBeforeEnd, forKey: .breakWarningSecondsBeforeEnd)
        try container.encode(bannerEnabled, forKey: .bannerEnabled)
    }
}

struct AlarmSettings: Codable, Equatable {
    var warningPlaySeconds: Int = 5
    var breakStartPlaySeconds: Int = 10
    var breakEndPlaySeconds: Int = 10
    
    // Migration support for old profiles with single maxPlaySeconds
    init() {}
    
    init(warningPlaySeconds: Int, breakStartPlaySeconds: Int, breakEndPlaySeconds: Int) {
        self.warningPlaySeconds = warningPlaySeconds
        self.breakStartPlaySeconds = breakStartPlaySeconds
        self.breakEndPlaySeconds = breakEndPlaySeconds
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Try new format first
        if let warning = try? container.decode(Int.self, forKey: .warningPlaySeconds) {
            warningPlaySeconds = warning
            breakStartPlaySeconds = try container.decodeIfPresent(Int.self, forKey: .breakStartPlaySeconds) ?? 10
            breakEndPlaySeconds = try container.decodeIfPresent(Int.self, forKey: .breakEndPlaySeconds) ?? 10
        }
        // Fall back to old format
        else if let maxPlay = try? container.decode(Int.self, forKey: .maxPlaySeconds) {
            warningPlaySeconds = min(maxPlay, 5)
            breakStartPlaySeconds = maxPlay
            breakEndPlaySeconds = maxPlay
        }
        // Use defaults
        else {
            warningPlaySeconds = 5
            breakStartPlaySeconds = 10
            breakEndPlaySeconds = 10
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case warningPlaySeconds
        case breakStartPlaySeconds
        case breakEndPlaySeconds
        case maxPlaySeconds  // Old key for migration
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(warningPlaySeconds, forKey: .warningPlaySeconds)
        try container.encode(breakStartPlaySeconds, forKey: .breakStartPlaySeconds)
        try container.encode(breakEndPlaySeconds, forKey: .breakEndPlaySeconds)
    }
}

struct OverlaySettings: Codable, Equatable {
    var strictDefault: Bool = true
    var delayedSkipEnabled: Bool = false
    var delayedSkipSeconds: Int = 30
}

struct FeatureSettings: Codable, Equatable {
    var autoStartWork: Bool = false
    var dailyStartEnabled: Bool = false
    var dailyStartTimeHHMM: String = "09:00"
    var menuBarCountdownTextEnabled: Bool = false
    var focusModeIntegrationEnabled: Bool = false
    var menuBarIcons: MenuBarIconSettings = MenuBarIconSettings()

    init() {}

    init(
        autoStartWork: Bool,
        dailyStartEnabled: Bool,
        dailyStartTimeHHMM: String,
        menuBarCountdownTextEnabled: Bool,
        focusModeIntegrationEnabled: Bool,
        menuBarIcons: MenuBarIconSettings
    ) {
        self.autoStartWork = autoStartWork
        self.dailyStartEnabled = dailyStartEnabled
        self.dailyStartTimeHHMM = dailyStartTimeHHMM
        self.menuBarCountdownTextEnabled = menuBarCountdownTextEnabled
        self.focusModeIntegrationEnabled = focusModeIntegrationEnabled
        self.menuBarIcons = menuBarIcons
    }

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
    // Values can be emoji like "🍅" or custom path like "custom:myicon.png"
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
    
    static func create(
        profileId: String,
        phase: TimerPhase,
        plannedSeconds: Int,
        actualSeconds: Int,
        completed: Bool,
        skipped: Bool,
        strictMode: Bool
    ) -> StatsEntry {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return StatsEntry(
            ts: formatter.string(from: Date()),
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

