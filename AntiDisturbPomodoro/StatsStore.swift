import Foundation
import Combine

/// Manages stats logging and summaries
class StatsStore: ObservableObject {
    
    @Published private(set) var todaySummary = StatsSummary.empty
    @Published private(set) var weekSummary = StatsSummary.empty
    @Published private(set) var allTimeSummary = StatsSummary.empty
    
    private let appHome: AppHome
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private var allEntries: [StatsEntry] = []
    
    // MARK: - Cached Date Formatter (Memory/CPU optimization)
    /// Reuse a single ISO8601DateFormatter instance instead of creating one per call
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    // MARK: - Cached Parsed Dates (Memory optimization)
    /// Cache parsed dates to avoid repeated parsing of the same timestamp
    private var parsedDateCache: [String: Date] = [:]
    
    init(appHome: AppHome) {
        self.appHome = appHome
    }
    
    // MARK: - Load
    
    func load() {
        loadAllEntries()
        updateSummaries()
    }
    
    private func loadAllEntries() {
        allEntries = []
        parsedDateCache = [:] // Clear cache when reloading
        
        let url = appHome.statsFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        
        let lines = content.components(separatedBy: .newlines)
        
        // Pre-allocate array capacity for better memory performance
        allEntries.reserveCapacity(lines.count)
        
        for line in lines where !line.isEmpty {
            if let data = line.data(using: .utf8),
               let entry = try? decoder.decode(StatsEntry.self, from: data) {
                allEntries.append(entry)
                // Pre-parse and cache the date
                if let date = Self.iso8601Formatter.date(from: entry.ts) {
                    parsedDateCache[entry.ts] = date
                }
            }
        }
    }
    
    // MARK: - Log
    
    func log(
        profileId: String,
        phase: TimerPhase,
        plannedSeconds: Int,
        actualSeconds: Int,
        completed: Bool,
        skipped: Bool,
        strictMode: Bool
    ) {
        let entry = StatsEntry.create(
            profileId: profileId,
            phase: phase,
            plannedSeconds: plannedSeconds,
            actualSeconds: actualSeconds,
            completed: completed,
            skipped: skipped,
            strictMode: strictMode
        )
        
        // Append to file
        appendToFile(entry)
        
        // Update in-memory data
        allEntries.append(entry)
        
        // Cache the parsed date
        if let date = Self.iso8601Formatter.date(from: entry.ts) {
            parsedDateCache[entry.ts] = date
        }
        
        updateSummaries()
    }
    
    private func appendToFile(_ entry: StatsEntry) {
        guard let data = try? encoder.encode(entry),
              let jsonString = String(data: data, encoding: .utf8) else { return }
        
        // Remove newlines from JSON for JSONL format
        let line = jsonString.replacingOccurrences(of: "\n", with: "") + "\n"
        
        let url = appHome.statsFileURL
        
        if let fileHandle = FileHandle(forWritingAtPath: url.path) {
            defer { fileHandle.closeFile() }
            fileHandle.seekToEndOfFile()
            if let lineData = line.data(using: .utf8) {
                fileHandle.write(lineData)
            }
        } else {
            // File doesn't exist, create it
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
    
    // MARK: - Summaries (Optimized: Single-pass computation)
    
    private func updateSummaries() {
        let now = Date()
        let calendar = Calendar.current
        
        // Calculate time boundaries once
        let todayStart = calendar.startOfDay(for: now)
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
        
        // Single-pass computation of all summaries (CPU optimization)
        var todayStats = StatsSummary()
        var weekStats = StatsSummary()
        var allTimeStats = StatsSummary()
        
        for entry in allEntries where entry.phase == .work {
            // Get cached date or parse it
            let date: Date?
            if let cached = parsedDateCache[entry.ts] {
                date = cached
            } else {
                date = Self.iso8601Formatter.date(from: entry.ts)
                if let d = date {
                    parsedDateCache[entry.ts] = d
                }
            }
            
            // Update all-time stats (always)
            allTimeStats.totalSessions += 1
            if entry.completed {
                allTimeStats.completedSessions += 1
                allTimeStats.totalFocusMinutes += entry.actualSeconds / 60
            }
            if entry.skipped {
                allTimeStats.skippedSessions += 1
            }
            
            // Check if within week
            if let entryDate = date, entryDate >= weekStart {
                weekStats.totalSessions += 1
                if entry.completed {
                    weekStats.completedSessions += 1
                    weekStats.totalFocusMinutes += entry.actualSeconds / 60
                }
                if entry.skipped {
                    weekStats.skippedSessions += 1
                }
                
                // Check if within today
                if entryDate >= todayStart {
                    todayStats.totalSessions += 1
                    if entry.completed {
                        todayStats.completedSessions += 1
                        todayStats.totalFocusMinutes += entry.actualSeconds / 60
                    }
                    if entry.skipped {
                        todayStats.skippedSessions += 1
                    }
                }
            }
        }
        
        todaySummary = todayStats
        weekSummary = weekStats
        allTimeSummary = allTimeStats
    }
    
    // MARK: - Date Parsing (Optimized with caching)
    
    private func parseDate(_ ts: String) -> Date? {
        // Check cache first
        if let cached = parsedDateCache[ts] {
            return cached
        }
        // Parse and cache
        if let date = Self.iso8601Formatter.date(from: ts) {
            parsedDateCache[ts] = date
            return date
        }
        return nil
    }
    
    // MARK: - Query Helpers
    
    func entries(for profileId: String) -> [StatsEntry] {
        allEntries.filter { $0.profileId == profileId }
    }
    
    func recentEntries(limit: Int = 10) -> [StatsEntry] {
        Array(allEntries.suffix(limit).reversed())
    }
    
    // MARK: - Memory Management
    
    /// Clears the date cache if memory pressure is detected
    func clearDateCache() {
        parsedDateCache.removeAll(keepingCapacity: true)
    }
}
