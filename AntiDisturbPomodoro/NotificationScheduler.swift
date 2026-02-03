import Foundation
import UserNotifications

/// Schedules and manages system banner notifications
class NotificationScheduler: NSObject, ObservableObject {
    
    @Published private(set) var hasPermission = false
    
    private let notificationCenter = UNUserNotificationCenter.current()
    
    override init() {
        super.init()
        notificationCenter.delegate = self
        checkPermission()
    }
    
    // MARK: - Permission
    
    func requestPermission() {
        notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.hasPermission = granted
            }
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }
    
    func checkPermission() {
        notificationCenter.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.hasPermission = settings.authorizationStatus == .authorized
            }
        }
    }
    
    // MARK: - Scheduling
    
    func scheduleWarning(at date: Date, phase: TimerPhase) {
        let content = UNMutableNotificationContent()
        content.title = "Time Warning"
        content.body = "\(phase.displayName) ends in 1 minute"
        content.categoryIdentifier = "TIMER_WARNING"
        
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, date.timeIntervalSinceNow),
            repeats: false
        )
        
        let request = UNNotificationRequest(
            identifier: "warning_\(phase.rawValue)",
            content: content,
            trigger: trigger
        )
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("Failed to schedule warning notification: \(error)")
            }
        }
    }
    
    func schedulePhaseEnd(at date: Date, phase: TimerPhase) {
        let content = UNMutableNotificationContent()
        content.title = "\(phase.displayName) Complete"
        content.body = phase.isBreak ? "Break is over. Time to focus!" : "Great work! Time for a break."
        content.categoryIdentifier = "TIMER_END"
        
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, date.timeIntervalSinceNow),
            repeats: false
        )
        
        let request = UNNotificationRequest(
            identifier: "end_\(phase.rawValue)",
            content: content,
            trigger: trigger
        )
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("Failed to schedule end notification: \(error)")
            }
        }
    }
    
    // MARK: - Cancellation
    
    func cancelAll() {
        notificationCenter.removeAllPendingNotificationRequests()
    }
    
    func cancelWarning() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [
            "warning_work",
            "warning_shortBreak",
            "warning_longBreak"
        ])
    }
    
    func cancelEnd() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [
            "end_work",
            "end_shortBreak",
            "end_longBreak"
        ])
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationScheduler: UNUserNotificationCenterDelegate {
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .list])
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Handle notification tap if needed
        completionHandler()
    }
}
