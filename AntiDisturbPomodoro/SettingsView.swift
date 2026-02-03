import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct SettingsView: View {
    
    var body: some View {
        TabView {
            ProfilesSettingsTab()
                .tabItem {
                    Label("Profiles", systemImage: "person.2")
                }
            
            RulesetSettingsTab()
                .tabItem {
                    Label("Timing", systemImage: "clock")
                }
            
            SoundsSettingsTab()
                .tabItem {
                    Label("Sounds", systemImage: "speaker.wave.2")
                }
            
            NotificationsSettingsTab()
                .tabItem {
                    Label("Alerts", systemImage: "bell")
                }
            
            OverlaySettingsTab()
                .tabItem {
                    Label("Break Overlay", systemImage: "rectangle.inset.filled")
                }
            
            FeaturesSettingsTab()
                .tabItem {
                    Label("Features", systemImage: "gearshape")
                }
            
            HotkeysSettingsTab()
                .tabItem {
                    Label("Hotkeys", systemImage: "command")
                }
            
            StatsSettingsTab()
                .tabItem {
                    Label("Stats", systemImage: "chart.bar")
                }
        }
        .frame(width: 550, height: 450)
        .overlay(SettingsWindowConfigurator().frame(width: 0, height: 0))
    }
}

// MARK: - Profiles Tab

struct ProfilesSettingsTab: View {
    @EnvironmentObject var profileStore: ProfileStore
    
    @State private var newProfileName = ""
    @State private var showingNewProfile = false
    @State private var profileToDelete: ProfileData?
    @State private var showingDeleteConfirm = false
    
    var body: some View {
        HStack(spacing: 0) {
            // Profile List
            VStack(alignment: .leading) {
                Text("Profiles")
                    .font(.headline)
                    .padding(.bottom, 8)
                
                List(profileStore.profiles, selection: $profileStore.currentProfileId) { profile in
                    HStack {
                        Text(profile.name)
                        if profile.id == profileStore.currentProfileId {
                            Spacer()
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                    .tag(profile.id)
                    .contextMenu {
                        Button("Duplicate") {
                            _ = profileStore.duplicateProfile(profile.id, newName: "\(profile.name) Copy")
                        }
                        Button("Delete", role: .destructive) {
                            profileToDelete = profile
                            showingDeleteConfirm = true
                        }
                        .disabled(profileStore.profiles.count <= 1)
                    }
                }
                .listStyle(.bordered)
                
                HStack {
                    Button(action: { showingNewProfile = true }) {
                        Image(systemName: "plus")
                    }
                    
                    Button(action: {
                        if let profile = profileStore.currentProfile {
                            profileToDelete = profile
                            showingDeleteConfirm = true
                        }
                    }) {
                        Image(systemName: "minus")
                    }
                    .disabled(profileStore.profiles.count <= 1)
                }
                .padding(.top, 4)
            }
            .frame(width: 180)
            .padding()
            
            Divider()
            
            // Profile Details
            VStack(alignment: .leading, spacing: 16) {
                if let profile = profileStore.currentProfile {
                    Text("Profile: \(profile.name)")
                        .font(.headline)
                    
                    HStack {
                        TextField("Name", text: Binding(
                            get: { profile.name },
                            set: { newValue in profileStore.renameProfile(profile.id, newName: newValue) }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                    }
                    
                    Spacer()
                    
                    Button("Reset to Defaults") {
                        profileStore.resetProfileToDefaults(profile.id)
                    }
                    .foregroundColor(.orange)
                    
                    Text("This will reset all settings for this profile to the base defaults.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Select a profile")
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .alert("New Profile", isPresented: $showingNewProfile) {
            TextField("Profile name", text: $newProfileName)
            Button("Create") {
                if !newProfileName.isEmpty {
                    let newProfile = profileStore.createProfile(name: newProfileName)
                    profileStore.currentProfileId = newProfile.id
                    newProfileName = ""
                }
            }
            Button("Cancel", role: .cancel) {
                newProfileName = ""
            }
        }
        .alert("Delete Profile?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let profile = profileToDelete {
                    profileStore.deleteProfile(profile.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(profileToDelete?.name ?? "")\"? This cannot be undone.")
        }
    }
}

// MARK: - Ruleset Tab

struct RulesetSettingsTab: View {
    @EnvironmentObject var profileStore: ProfileStore
    
    var body: some View {
        Form {
            if let profile = profileStore.currentProfile {
                Section("Work Session") {
                    Stepper(
                        "Duration: \(profile.ruleset.workSeconds / 60) minutes",
                        value: Binding(
                            get: { profile.ruleset.workSeconds / 60 },
                            set: { newValue in profileStore.updateCurrentProfile { $0.ruleset.workSeconds = newValue * 60 } }
                        ),
                        in: 1...120
                    )
                }
                
                Section("Short Break") {
                    Stepper(
                        "Duration: \(profile.ruleset.shortBreakSeconds / 60) minutes",
                        value: Binding(
                            get: { profile.ruleset.shortBreakSeconds / 60 },
                            set: { newValue in profileStore.updateCurrentProfile { $0.ruleset.shortBreakSeconds = newValue * 60 } }
                        ),
                        in: 1...60
                    )
                }
                
                Section("Long Break") {
                    Stepper(
                        "Duration: \(profile.ruleset.longBreakSeconds / 60) minutes",
                        value: Binding(
                            get: { profile.ruleset.longBreakSeconds / 60 },
                            set: { newValue in profileStore.updateCurrentProfile { $0.ruleset.longBreakSeconds = newValue * 60 } }
                        ),
                        in: 1...120
                    )
                    
                    Stepper(
                        "After every \(profile.ruleset.longBreakEvery) work sessions",
                        value: Binding(
                            get: { profile.ruleset.longBreakEvery },
                            set: { newValue in profileStore.updateCurrentProfile { $0.ruleset.longBreakEvery = newValue } }
                        ),
                        in: 2...10
                    )
                }
            } else {
                Text("Select a profile to edit timing settings.")
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Sounds Tab

struct SoundsSettingsTab: View {
    @EnvironmentObject var profileStore: ProfileStore
    @EnvironmentObject var soundLibrary: SoundLibrary
    @EnvironmentObject var alarmPlayer: AlarmPlayer
    
    @State private var showingImporter = false
    
    var body: some View {
        Form {
            if let profile = profileStore.currentProfile {
                Section("Sound Selection") {
                    SoundPicker(
                        title: "Work End",
                        selectedId: Binding(
                            get: { profile.sounds.workEndSoundId },
                            set: { newValue in profileStore.updateCurrentProfile { $0.sounds.workEndSoundId = newValue } }
                        )
                    )

                    SoundPicker(
                        title: "Break End",
                        selectedId: Binding(
                            get: { profile.sounds.breakEndSoundId },
                            set: { newValue in profileStore.updateCurrentProfile { $0.sounds.breakEndSoundId = newValue } }
                        )
                    )

                    SoundPicker(
                        title: "Work Warning",
                        selectedId: Binding(
                            get: { profile.sounds.workWarningSoundId },
                            set: { newValue in profileStore.updateCurrentProfile { $0.sounds.workWarningSoundId = newValue } }
                        )
                    )

                    SoundPicker(
                        title: "Break Warning",
                        selectedId: Binding(
                            get: { profile.sounds.breakWarningSoundId },
                            set: { newValue in profileStore.updateCurrentProfile { $0.sounds.breakWarningSoundId = newValue } }
                        )
                    )
                }
                
                Section("Sound Library") {
                    VStack(alignment: .leading) {
                        Text("Built-in Sounds: \(soundLibrary.builtInSounds.count)")
                            .font(.caption)
                        Text("Imported Sounds: \(soundLibrary.importedSounds.count)")
                            .font(.caption)
                    }
                    
                    Button("Import Sound File...") {
                        showingImporter = true
                    }
                    
                    if !soundLibrary.importedSounds.isEmpty {
                        ForEach(soundLibrary.importedSounds) { sound in
                            HStack {
                                Text(sound.name)
                                Text("(\(sound.format))")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button("Remove") {
                                    soundLibrary.removeSound(id: sound.id)
                                }
                                .buttonStyle(.link)
                                .foregroundColor(.red)
                            }
                        }
                    }
                }
            } else {
                Text("Select a profile to edit sound settings.")
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.mp3, .audio, UTType(filenameExtension: "m4a") ?? .audio, .wav],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                _ = soundLibrary.importSounds(from: urls)
            case .failure(let error):
                print("Import failed: \(error)")
            }
        }
    }
}

struct SoundPicker: View {
    let title: String
    @Binding var selectedId: String
    
    @EnvironmentObject var soundLibrary: SoundLibrary
    @EnvironmentObject var alarmPlayer: AlarmPlayer
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Picker("", selection: $selectedId) {
                ForEach(soundLibrary.sounds) { sound in
                    Text(sound.name).tag(sound.id)
                }
            }
            .frame(width: 150)
            
            Button(action: { alarmPlayer.testSound(soundId: selectedId) }) {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
        }
    }
}

// MARK: - Notifications Tab

struct NotificationsSettingsTab: View {
    @EnvironmentObject var profileStore: ProfileStore
    
    var body: some View {
        Form {
            if let profile = profileStore.currentProfile {
                Section("Work Warning Reminder") {
                    Stepper(
                        "Show warning \(profile.notifications.workWarningSecondsBeforeEnd) seconds before work ends",
                        value: Binding(
                            get: { profile.notifications.workWarningSecondsBeforeEnd },
                            set: { newValue in profileStore.updateCurrentProfile { $0.notifications.workWarningSecondsBeforeEnd = newValue } }
                        ),
                        in: 10...300,
                        step: 10
                    )
                }
                
                Section("Break Warning Reminder") {
                    Stepper(
                        "Show warning \(profile.notifications.breakWarningSecondsBeforeEnd) seconds before break ends",
                        value: Binding(
                            get: { profile.notifications.breakWarningSecondsBeforeEnd },
                            set: { newValue in profileStore.updateCurrentProfile { $0.notifications.breakWarningSecondsBeforeEnd = newValue } }
                        ),
                        in: 10...300,
                        step: 10
                    )
                }
                
                Section("Banner Notifications") {
                    Toggle(
                        "Show banner notifications",
                        isOn: Binding(
                            get: { profile.notifications.bannerEnabled },
                            set: { newValue in profileStore.updateCurrentProfile { $0.notifications.bannerEnabled = newValue } }
                        )
                    )
                    
                    Text("Banners appear at warning time and when phases end.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Alarm Durations") {
                    Stepper(
                        "Warning alarm: \(profile.alarm.warningPlaySeconds) seconds",
                        value: Binding(
                            get: { profile.alarm.warningPlaySeconds },
                            set: { newValue in profileStore.updateCurrentProfile { $0.alarm.warningPlaySeconds = newValue } }
                        ),
                        in: 1...30
                    )
                    
                    Stepper(
                        "Break start alarm: \(profile.alarm.breakStartPlaySeconds) seconds",
                        value: Binding(
                            get: { profile.alarm.breakStartPlaySeconds },
                            set: { newValue in profileStore.updateCurrentProfile { $0.alarm.breakStartPlaySeconds = newValue } }
                        ),
                        in: 1...60
                    )
                    
                    Stepper(
                        "Break end alarm: \(profile.alarm.breakEndPlaySeconds) seconds",
                        value: Binding(
                            get: { profile.alarm.breakEndPlaySeconds },
                            set: { newValue in profileStore.updateCurrentProfile { $0.alarm.breakEndPlaySeconds = newValue } }
                        ),
                        in: 1...60
                    )
                    
                    Text("Alarms loop until duration expires or you click Stop Alarm.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Select a profile to edit notification settings.")
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Overlay Tab

struct OverlaySettingsTab: View {
    @EnvironmentObject var profileStore: ProfileStore
    
    var body: some View {
        Form {
            if let profile = profileStore.currentProfile {
                Section("Break Overlay Behavior") {
                    Toggle(
                        "Strict Mode (no skip button)",
                        isOn: Binding(
                            get: { profile.overlay.strictDefault },
                            set: { newValue in profileStore.updateCurrentProfile { $0.overlay.strictDefault = newValue } }
                        )
                    )
                    
                    Text("When enabled, you cannot skip breaks. This helps enforce rest periods.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Delayed Skip") {
                    Toggle(
                        "Enable delayed skip",
                        isOn: Binding(
                            get: { profile.overlay.delayedSkipEnabled },
                            set: { newValue in profileStore.updateCurrentProfile { $0.overlay.delayedSkipEnabled = newValue } }
                        )
                    )
                    .disabled(profile.overlay.strictDefault)
                    
                    if profile.overlay.delayedSkipEnabled && !profile.overlay.strictDefault {
                        Stepper(
                            "Skip available after \(profile.overlay.delayedSkipSeconds) seconds",
                            value: Binding(
                                get: { profile.overlay.delayedSkipSeconds },
                                set: { newValue in profileStore.updateCurrentProfile { $0.overlay.delayedSkipSeconds = newValue } }
                            ),
                            in: 5...120,
                            step: 5
                        )
                    }
                    
                    Text("Delayed skip shows a disabled button that becomes enabled after the specified time.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Overlay Info") {
                    Text("The break overlay covers all connected monitors to help you take a proper break. You can always stop the alarm sound.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Select a profile to edit overlay settings.")
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Features Tab

struct FeaturesSettingsTab: View {
    @EnvironmentObject var profileStore: ProfileStore
    @EnvironmentObject var appHome: AppHome
    
    @State private var showingIconImporter = false
    @State private var importingForState: IconState = .idle
    
    enum IconState: String, CaseIterable {
        case idle = "Idle"
        case work = "Work"
        case breakTime = "Break"
        case paused = "Paused"
    }
    
    var body: some View {
        Form {
            if let profile = profileStore.currentProfile {
                Section("Auto-Start") {
                    Toggle(
                        "Auto-start work after break",
                        isOn: Binding(
                            get: { profile.features.autoStartWork },
                            set: { newValue in profileStore.updateCurrentProfile { $0.features.autoStartWork = newValue } }
                        )
                    )
                    
                    Text("When enabled, work sessions start automatically after breaks end.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Menu Bar Display") {
                    Toggle(
                        "Show countdown in menu bar",
                        isOn: Binding(
                            get: { profile.features.menuBarCountdownTextEnabled },
                            set: { newValue in profileStore.updateCurrentProfile { $0.features.menuBarCountdownTextEnabled = newValue } }
                        )
                    )
                    
                    Toggle(
                        "Use custom PNG icons",
                        isOn: Binding(
                            get: { profile.features.menuBarIcons.useCustomIcons },
                            set: { newValue in profileStore.updateCurrentProfile { $0.features.menuBarIcons.useCustomIcons = newValue } }
                        )
                    )
                }
                
                if profile.features.menuBarIcons.useCustomIcons {
                    Section("Custom Icons (18x18 PNG recommended)") {
                        IconRow(
                            label: "Idle",
                            value: profile.features.menuBarIcons.idleIcon,
                            appHome: appHome,
                            onImport: { importingForState = .idle; showingIconImporter = true },
                            onClear: { profileStore.updateCurrentProfile { $0.features.menuBarIcons.idleIcon = "🍅" } }
                        )
                        
                        IconRow(
                            label: "Work",
                            value: profile.features.menuBarIcons.workIcon,
                            appHome: appHome,
                            onImport: { importingForState = .work; showingIconImporter = true },
                            onClear: { profileStore.updateCurrentProfile { $0.features.menuBarIcons.workIcon = "🍅" } }
                        )
                        
                        IconRow(
                            label: "Break",
                            value: profile.features.menuBarIcons.breakIcon,
                            appHome: appHome,
                            onImport: { importingForState = .breakTime; showingIconImporter = true },
                            onClear: { profileStore.updateCurrentProfile { $0.features.menuBarIcons.breakIcon = "☕️" } }
                        )
                        
                        IconRow(
                            label: "Paused",
                            value: profile.features.menuBarIcons.pausedIcon,
                            appHome: appHome,
                            onImport: { importingForState = .paused; showingIconImporter = true },
                            onClear: { profileStore.updateCurrentProfile { $0.features.menuBarIcons.pausedIcon = "⏸️" } }
                        )
                        
                        Text("Icons are set as template images for proper light/dark mode support. Use single-color PNGs with transparency.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Section("Emoji Icons") {
                        EmojiIconRow(
                            label: "Idle",
                            value: Binding(
                                get: { profile.features.menuBarIcons.idleIcon },
                                set: { newValue in profileStore.updateCurrentProfile { $0.features.menuBarIcons.idleIcon = newValue } }
                            )
                        )
                        
                        EmojiIconRow(
                            label: "Work",
                            value: Binding(
                                get: { profile.features.menuBarIcons.workIcon },
                                set: { newValue in profileStore.updateCurrentProfile { $0.features.menuBarIcons.workIcon = newValue } }
                            )
                        )
                        
                        EmojiIconRow(
                            label: "Break",
                            value: Binding(
                                get: { profile.features.menuBarIcons.breakIcon },
                                set: { newValue in profileStore.updateCurrentProfile { $0.features.menuBarIcons.breakIcon = newValue } }
                            )
                        )
                        
                        EmojiIconRow(
                            label: "Paused",
                            value: Binding(
                                get: { profile.features.menuBarIcons.pausedIcon },
                                set: { newValue in profileStore.updateCurrentProfile { $0.features.menuBarIcons.pausedIcon = newValue } }
                            )
                        )
                        
                        HStack {
                            Text("Presets:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("🍅") {
                                profileStore.updateCurrentProfile {
                                    $0.features.menuBarIcons.idleIcon = "🍅"
                                    $0.features.menuBarIcons.workIcon = "🍅"
                                    $0.features.menuBarIcons.breakIcon = "☕️"
                                    $0.features.menuBarIcons.pausedIcon = "⏸️"
                                }
                            }
                            .buttonStyle(.bordered)
                            Button("⏱️") {
                                profileStore.updateCurrentProfile {
                                    $0.features.menuBarIcons.idleIcon = "⏱️"
                                    $0.features.menuBarIcons.workIcon = "🔥"
                                    $0.features.menuBarIcons.breakIcon = "💤"
                                    $0.features.menuBarIcons.pausedIcon = "⏸️"
                                }
                            }
                            .buttonStyle(.bordered)
                            Button("🔴") {
                                profileStore.updateCurrentProfile {
                                    $0.features.menuBarIcons.idleIcon = "⚪️"
                                    $0.features.menuBarIcons.workIcon = "🔴"
                                    $0.features.menuBarIcons.breakIcon = "🟢"
                                    $0.features.menuBarIcons.pausedIcon = "🟡"
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                
                Section("Focus Mode") {
                    Toggle(
                        "Focus mode integration",
                        isOn: Binding(
                            get: { profile.features.focusModeIntegrationEnabled },
                            set: { newValue in profileStore.updateCurrentProfile { $0.features.focusModeIntegrationEnabled = newValue } }
                        )
                    )
                    .disabled(true)
                    
                    Text("Focus mode must be configured manually in System Settings > Focus.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button("Open Focus Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Focus")!)
                    }
                }
            } else {
                Text("Select a profile to edit feature settings.")
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .fileImporter(
            isPresented: $showingIconImporter,
            allowedContentTypes: [.png],
            allowsMultipleSelection: false
        ) { result in
            handleIconImport(result: result)
        }
    }
    
    private func handleIconImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            let filename = appHome.importIcon(from: url, named: importingForState.rawValue.lowercased())
            guard let filename = filename else { return }
            
            let customValue = "custom:\(filename)"
            
            profileStore.updateCurrentProfile { profile in
                switch importingForState {
                case .idle:
                    profile.features.menuBarIcons.idleIcon = customValue
                case .work:
                    profile.features.menuBarIcons.workIcon = customValue
                case .breakTime:
                    profile.features.menuBarIcons.breakIcon = customValue
                case .paused:
                    profile.features.menuBarIcons.pausedIcon = customValue
                }
            }
            
        case .failure(let error):
            print("Icon import failed: \(error)")
        }
    }
}

struct IconRow: View {
    let label: String
    let value: String
    let appHome: AppHome
    let onImport: () -> Void
    let onClear: () -> Void
    
    var body: some View {
        HStack {
            Text(label)
            
            Spacer()
            
            if value.hasPrefix("custom:") {
                if let image = appHome.loadMenuBarIcon(value, size: NSSize(width: 18, height: 18)) {
                    Image(nsImage: image)
                        .frame(width: 24, height: 24)
                }
                Text(String(value.dropFirst("custom:".count)))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text(value)
                    .font(.title3)
            }
            
            Button("Import") {
                onImport()
            }
            .buttonStyle(.bordered)
            
            Button("Clear") {
                onClear()
            }
            .buttonStyle(.borderless)
            .foregroundColor(.red)
        }
    }
}

struct EmojiIconRow: View {
    let label: String
    @Binding var value: String
    
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("", text: $value)
                .frame(width: 50)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Hotkeys Tab

struct HotkeysSettingsTab: View {
    @EnvironmentObject var profileStore: ProfileStore
    
    var body: some View {
        Form {
            if let profile = profileStore.currentProfile {
                Section("Global Hotkeys") {
                    HStack {
                        Text("Start/Pause Timer")
                        Spacer()
                        Text(profile.hotkeys.startPause)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                    }
                    
                    HStack {
                        Text("Stop Alarm")
                        Spacer()
                        Text(profile.hotkeys.stopAlarm)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                    }
                    
                    HStack {
                        Text("Skip Phase")
                        Spacer()
                        Text(profile.hotkeys.skipPhase)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                
                Section {
                    Text("Hotkey customization will be available in a future update. The app requires Accessibility permissions for global hotkeys to work.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button("Open Accessibility Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                }
            } else {
                Text("Select a profile to view hotkey settings.")
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Stats Tab

struct StatsSettingsTab: View {
    @EnvironmentObject var statsStore: StatsStore
    @EnvironmentObject var appHome: AppHome
    
    var body: some View {
        Form {
            Section("Today") {
                StatRow(label: "Completed Sessions", value: "\(statsStore.todaySummary.completedSessions)")
                StatRow(label: "Total Focus Time", value: "\(statsStore.todaySummary.totalFocusMinutes) minutes")
                StatRow(label: "Skipped", value: "\(statsStore.todaySummary.skippedSessions)")
            }
            
            Section("This Week") {
                StatRow(label: "Completed Sessions", value: "\(statsStore.weekSummary.completedSessions)")
                StatRow(label: "Total Focus Time", value: "\(statsStore.weekSummary.totalFocusMinutes) minutes")
                StatRow(label: "Skipped", value: "\(statsStore.weekSummary.skippedSessions)")
            }
            
            Section("All Time") {
                StatRow(label: "Completed Sessions", value: "\(statsStore.allTimeSummary.completedSessions)")
                StatRow(label: "Total Focus Time", value: formatHours(statsStore.allTimeSummary.totalFocusMinutes))
                StatRow(label: "Skipped", value: "\(statsStore.allTimeSummary.skippedSessions)")
            }
            
            Section {
                Button("Open Stats File") {
                    NSWorkspace.shared.activateFileViewerSelecting([appHome.statsFileURL])
                }
                
                Text("Stats are stored in stats.jsonl in the app folder.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
    
    private func formatHours(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours > 0 {
            return "\(hours)h \(remainingMinutes)m"
        }
        return "\(minutes) minutes"
    }
}

struct StatRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    SettingsView()
}
