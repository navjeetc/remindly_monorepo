import Foundation
import UserNotifications
import AVFoundation
import Combine

@MainActor
class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()
    
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private let center = UNUserNotificationCenter.current()
    
    // Voice synthesizer for pre-notification prompts
    nonisolated(unsafe) private let synthesizer = AVSpeechSynthesizer()
    
    private override init() {
        super.init()
        center.delegate = self
        Task {
            await checkAuthorizationStatus()
        }
    }
    
    // MARK: - Permission Management
    
    func requestAuthorization() async -> Bool {
        do {
            print("🔔 Requesting notification authorization...")
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            print("🔔 Authorization granted: \(granted)")
            await checkAuthorizationStatus()
            return granted
        } catch {
            print("❌ Error requesting notification authorization: \(error)")
            return false
        }
    }
    
    func checkAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        print("🔔 Current authorization status: \(authorizationStatus.rawValue)")
        switch authorizationStatus {
        case .notDetermined:
            print("   - Not determined (need to request)")
        case .denied:
            print("   - Denied (user needs to enable in Settings)")
        case .authorized:
            print("   - Authorized ✅")
        case .provisional:
            print("   - Provisional")
        case .ephemeral:
            print("   - Ephemeral")
        @unknown default:
            print("   - Unknown status")
        }
    }
    
    // MARK: - Notification Scheduling
    
    func scheduleNotifications(for occurrences: [OccurrenceResponse]) async {
        let settings = AppSettings.shared
        
        // Skip if notifications are disabled
        guard settings.notificationsEnabled else {
            print("🔕 Notifications disabled in settings")
            center.removeAllPendingNotificationRequests()
            return
        }
        
        // Remove all pending notifications first
        center.removeAllPendingNotificationRequests()
        
        let now = Date()
        // Allow a 5-minute grace period for recently passed occurrences
        let gracePeriod: TimeInterval = 5 * 60 // 5 minutes
        let earliestScheduleTime = now.addingTimeInterval(-gracePeriod)
        
        for occurrence in occurrences {
            // Only schedule for pending occurrences that are either in the future or within grace period
            guard occurrence.status == "pending",
                  occurrence.scheduledAt > earliestScheduleTime else {
                continue
            }
            
            // Skip if in quiet hours
            if settings.isInQuietHours() {
                print("🌙 Skipping notification during quiet hours: \(occurrence.reminder.title)")
                continue
            }
            
            // Schedule main notification (with voice)
            await scheduleMainNotification(for: occurrence)
            
            // Schedule repeat notification based on settings
            await scheduleRepeatNotification(for: occurrence)
        }
        
        // Log scheduled notifications
        let pending = await center.pendingNotificationRequests()
        print("📅 Scheduled \(pending.count) notifications")
    }
    
    private func scheduleMainNotification(for occurrence: OccurrenceResponse) async {
        let settings = AppSettings.shared
        
        let content = UNMutableNotificationContent()
        content.title = occurrence.reminder.title
        
        if let notes = occurrence.reminder.notes, !notes.isEmpty {
            content.body = notes
        } else {
            content.body = "Time for your \(occurrence.reminder.category ?? "reminder")"
        }
        
        // Use sound based on settings
        if settings.notificationSoundEnabled {
            content.sound = .defaultCritical // Use critical sound for important reminders
        } else {
            content.sound = nil
        }
        
        content.categoryIdentifier = "REMINDER"
        content.badge = 1
        
        // Add category badge
        if let category = occurrence.reminder.category {
            content.subtitle = category.capitalized
        }
        
        content.userInfo = [
            "occurrenceId": occurrence.id,
            "type": "main",
            "reminderId": occurrence.reminderId
        ]
        
        // If scheduled time is in the past, trigger immediately (after 1 second)
        let now = Date()
        let triggerDate = occurrence.scheduledAt > now ? occurrence.scheduledAt : now.addingTimeInterval(1)
        
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: triggerDate),
            repeats: false
        )
        
        let request = UNNotificationRequest(
            identifier: "reminder-\(occurrence.id)",
            content: content,
            trigger: trigger
        )
        
        try? await center.add(request)
    }
    
    private func scheduleRepeatNotification(for occurrence: OccurrenceResponse) async {
        let settings = AppSettings.shared
        let repeatInterval = TimeInterval(settings.repeatInterval * 60) // Convert minutes to seconds
        let repeatTime = occurrence.scheduledAt.addingTimeInterval(repeatInterval)
        
        let content = UNMutableNotificationContent()
        content.title = "⏰ Reminder: \(occurrence.reminder.title)"
        content.body = "You haven't acknowledged this reminder yet"
        
        // Use sound based on settings
        if settings.notificationSoundEnabled {
            content.sound = .defaultCritical
        } else {
            content.sound = nil
        }
        
        content.categoryIdentifier = "REMINDER_REPEAT"
        content.badge = 1
        
        content.userInfo = [
            "occurrenceId": occurrence.id,
            "type": "repeat",
            "reminderId": occurrence.reminderId
        ]
        
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: repeatTime),
            repeats: false
        )
        
        let request = UNNotificationRequest(
            identifier: "repeat-\(occurrence.id)",
            content: content,
            trigger: trigger
        )
        
        try? await center.add(request)
    }
    
    // MARK: - Notification Actions
    
    func setupNotificationCategories() {
        // Actions for main reminder notification
        let takenAction = UNNotificationAction(
            identifier: "TAKEN",
            title: "✓ Taken",
            options: [.foreground]
        )
        
        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE",
            title: "⏰ Snooze 10 min",
            options: []
        )
        
        let skipAction = UNNotificationAction(
            identifier: "SKIP",
            title: "✗ Skip",
            options: [.destructive]
        )
        
        let reminderCategory = UNNotificationCategory(
            identifier: "REMINDER",
            actions: [takenAction, snoozeAction, skipAction],
            intentIdentifiers: [],
            options: []
        )
        
        let repeatCategory = UNNotificationCategory(
            identifier: "REMINDER_REPEAT",
            actions: [takenAction, skipAction],
            intentIdentifiers: [],
            options: []
        )
        
        let voicePromptCategory = UNNotificationCategory(
            identifier: "VOICE_PROMPT",
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        
        center.setNotificationCategories([reminderCategory, repeatCategory, voicePromptCategory])
    }
    
    // MARK: - Voice Prompts
    
    func playVoicePrompt(_ text: String) {
        Task { @MainActor in
            let settings = AppSettings.shared
            let voiceRate = settings.voiceRate
            let voiceVolume = settings.voiceVolume
            
            Task.detached { [weak self] in
                guard let self = self else { return }
                let utterance = AVSpeechUtterance(string: text)
                utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
                utterance.rate = Float(voiceRate)
                utterance.volume = Float(voiceVolume)
                utterance.preUtteranceDelay = 0.5
                self.synthesizer.speak(utterance)
            }
        }
    }
    
    // MARK: - Utility
    
    func cancelNotification(for occurrenceId: Int) {
        center.removePendingNotificationRequests(withIdentifiers: [
            "reminder-\(occurrenceId)",
            "repeat-\(occurrenceId)"
        ])
    }
    
    func cancelAllNotifications() {
        center.removeAllPendingNotificationRequests()
    }
    
    func getPendingNotifications() async -> [UNNotificationRequest] {
        return await center.pendingNotificationRequests()
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    
    // Handle notification when app is in foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        
        // Play voice for main reminder notifications
        if let type = userInfo["type"] as? String, 
           (type == "main" || type == "repeat") {
            let title = notification.request.content.title
            // Remove emojis from voice (they sound weird)
            let cleanText = title
                .replacingOccurrences(of: "⏰ Reminder: ", with: "")
                .replacingOccurrences(of: "⏰", with: "")
            
            Task { @MainActor [weak self, cleanText] in
                self?.playVoicePrompt(cleanText)
            }
        }
        
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification tap or action
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        
        // Play voice when user taps the notification (brings app to foreground)
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            let title = response.notification.request.content.title
            // Remove emojis from voice
            let cleanText = title
                .replacingOccurrences(of: "⏰ Reminder: ", with: "")
                .replacingOccurrences(of: "⏰", with: "")
            
            Task { @MainActor [weak self, cleanText] in
                self?.playVoicePrompt(cleanText)
            }
        }
        
        guard let occurrenceId = userInfo["occurrenceId"] as? Int else {
            completionHandler()
            return
        }
        
        Task { @MainActor in
            // Post notification to handle in the app
            NotificationCenter.default.post(
                name: NSNotification.Name("HandleNotificationAction"),
                object: nil,
                userInfo: [
                    "occurrenceId": occurrenceId,
                    "action": response.actionIdentifier
                ]
            )
        }
        
        completionHandler()
    }
}
