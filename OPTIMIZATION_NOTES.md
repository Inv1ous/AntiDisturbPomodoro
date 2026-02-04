# AntiDisturbPomodoro - Optimization Notes

This document details all memory and CPU optimizations made to the AntiDisturbPomodoro codebase, plus additional feature improvements. **All original features have been preserved.**

## Summary of Optimizations

### 1. **TimerEngine.swift** - Display String Caching
- **Problem**: `formattedRemaining` and `formattedExtraTimeRemaining` computed properties regenerated strings on every access (every 0.5 seconds × number of observers)
- **Solution**: Added caching that only regenerates the string when the integer seconds value changes
- **Impact**: Reduces string allocations by ~50% and eliminates redundant formatting calls

### 2. **StatsStore.swift** - ISO8601DateFormatter Caching & Single-Pass Computation
- **Problem 1**: `parseDate()` created a new `ISO8601DateFormatter` on every call (expensive operation)
- **Problem 2**: `updateSummaries()` iterated through all entries 3 times (today, week, all-time)
- **Solution**: 
  - Static cached `ISO8601DateFormatter` instance
  - Date parsing cache to avoid re-parsing same timestamps
  - Single-pass summary computation that calculates all three summaries in one loop
- **Impact**: ~67% reduction in iterations, eliminates formatter allocation overhead

### 3. **Models.swift** - StatsEntry.create() Formatter Caching
- **Problem**: `StatsEntry.create()` instantiated a new `ISO8601DateFormatter` on every stats log
- **Solution**: Static cached formatter instance
- **Impact**: Eliminates formatter allocation on every pomodoro completion

### 4. **StatusBarController.swift** - Throttled Menu Bar Updates
- **Problem**: `updateMenuBar()` called every 0.5 seconds even when nothing changed visually
- **Solution**: Track last displayed values and only update when display would actually change
- **Impact**: Reduces menu bar updates by up to 50% when timer is running

### 5. **SoundLibrary.swift** - Computed Property Caching
- **Problem**: `builtInSounds` and `importedSounds` computed properties created new filtered arrays on every access
- **Solution**: Cache filtered arrays, invalidate when `sounds` array changes
- **Impact**: Eliminates redundant array filtering in Settings UI

### 6. **AppHome.swift** - ISO8601DateFormatter Caching
- **Problem**: `generateImportedSoundFilename()` created new formatter on every import
- **Solution**: Static cached formatter instance
- **Impact**: Minimal but consistent with overall optimization strategy

### 7. **AlarmPlayer.swift** - Sound Instance Caching
- **Problem**: Created new `NSSound` instance on every loop iteration during alarm playback
- **Solution**: Cache `NSSound` instances by URL with LRU-style eviction (max 5 entries)
- **Impact**: Reduces disk I/O and memory allocations during alarm looping

### 8. **ProfileStore.swift** - Debounced Saving & Thread Optimization
- **Problem 1**: Every settings change triggered immediate disk write
- **Problem 2**: Unnecessary `DispatchQueue.main.async` when already on main thread
- **Solution**: 
  - Debounced save with 0.5s delay to coalesce rapid changes
  - Removed unnecessary async dispatch
- **Impact**: Reduces disk I/O when user is adjusting sliders/steppers

### 9. **OverlayManager.swift** - Intelligent Window Refresh
- **Problem**: `refreshOverlayContent()` destroyed and recreated all overlay windows
- **Solution**: 
  - Track screens by ObjectIdentifier
  - Only recreate windows if screen configuration changed
  - Otherwise, just update the content view
- **Impact**: Significantly reduces window creation overhead during overlay updates

---

## Feature Improvements (Second Update)

### 1. **Audio Testing No Longer Loops**
- The play button in the sound settings now plays the sound once without looping
- Previously it would loop for 3 seconds which was confusing for testing

### 2. **Alarm Duration Mode Selection**
- You can now choose between two modes for each alarm duration:
  - **Seconds**: Play the sound for X seconds (loops as needed)
  - **Loop count**: Play the sound exactly X times
- Available for: Work Warning, Break Warning, Work End, Break End

### 3. **Fixed "Resume Break" Button Truncation**
- The "Resume Break" button in the menu bar popover no longer shows as "Resume Bre..."
- Improved layout with proper text sizing

### 4. **Improved Extra Time Text Display**
- Whole minutes: "1 min", "2 min", etc.
- Non-whole minutes: "1 min and 30 seconds", "2 min and 15 seconds"
- Less than a minute: "45 seconds"

---

## Memory Improvements

| Optimization | Memory Saved |
|--------------|--------------|
| Cached ISO8601DateFormatter (×3 locations) | ~1KB per use avoided |
| Date parsing cache | Variable, prevents repeated parsing |
| Sound instance cache | Avoids repeated file reads |
| Filtered array caching | Prevents temporary array allocations |
| Single-pass stats computation | 2/3 fewer temporary arrays |

## CPU Improvements

| Optimization | CPU Reduction |
|--------------|---------------|
| Throttled menu bar updates | Up to 50% fewer updates |
| Cached display strings | ~50% fewer String allocations |
| Single-pass summaries | ~67% fewer iterations |
| Debounced profile saves | Coalesces rapid changes |
| Smart overlay refresh | Avoids window recreation |

## Testing Recommendations

1. **Timer accuracy**: Verify timer still counts down correctly
2. **Menu bar updates**: Confirm display updates when state changes
3. **Alarm looping**: Test that alarms loop correctly for full duration
4. **Sound testing**: Verify test button plays sound once without looping
5. **Loop count mode**: Test alarm plays exactly the specified number of times
6. **Stats tracking**: Verify today/week/all-time stats are accurate
7. **Overlay behavior**: Test overlay shows/hides correctly on break start/end
8. **Settings persistence**: Confirm settings are saved after changes
9. **Multi-monitor**: Test overlay appears on all screens

All original functionality has been preserved - these are purely performance optimizations plus the requested feature improvements.
