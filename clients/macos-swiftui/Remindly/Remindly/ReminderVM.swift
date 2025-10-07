import Foundation
import AVFoundation
import Combine

@MainActor
class ReminderVM: ObservableObject {
    @Published var occurrences: [OccurrenceResponse] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isAuthenticated = false
    
    nonisolated(unsafe) private let synthesizer = AVSpeechSynthesizer()
    private let apiClient = APIClient.shared
    private let notificationManager = NotificationManager.shared
    private var notificationObserver: NSObjectProtocol?
    
    init() {
        setupNotificationObserver()
    }
    
    deinit {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    func bootstrap() {
        Task {
            do {
                // Request notification permissions
                let granted = await notificationManager.requestAuthorization()
                if !granted {
                    errorMessage = "Notification permissions denied. Please enable in System Settings."
                }
                
                // Auto-authenticate in dev mode
                _ = try await apiClient.authenticate(email: "senior@example.com")
                isAuthenticated = true
                await refresh()
            } catch {
                errorMessage = "Failed to authenticate: \(error.localizedDescription)"
            }
        }
    }
    
    private func setupNotificationObserver() {
        notificationObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("HandleNotificationAction"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let userInfo = notification.userInfo,
                  let occurrenceId = userInfo["occurrenceId"] as? Int,
                  let action = userInfo["action"] as? String else {
                return
            }
            
            Task {
                await self.handleNotificationAction(occurrenceId: occurrenceId, action: action)
            }
        }
    }
    
    private func handleNotificationAction(occurrenceId: Int, action: String) async {
        guard let occurrence = occurrences.first(where: { $0.id == occurrenceId }) else {
            return
        }
        
        switch action {
        case "TAKEN":
            await acknowledge(occurrence: occurrence, kind: "taken")
        case "SNOOZE":
            // Snooze for 10 minutes - reschedule notification
            await snooze(occurrence: occurrence, minutes: 10)
        case "SKIP":
            await acknowledge(occurrence: occurrence, kind: "skip")
        default:
            // Default action (tap on notification) - just refresh to show the reminder
            await refresh()
        }
    }
    
    func refresh() async {
        isLoading = true
        errorMessage = nil
        
        do {
            occurrences = try await apiClient.fetchTodayReminders()
            
            // Schedule notifications for all pending reminders
            await notificationManager.scheduleNotifications(for: occurrences)
        } catch {
            errorMessage = "Failed to load reminders: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    func acknowledge(occurrence: OccurrenceResponse, kind: String) async {
        do {
            try await apiClient.acknowledge(occurrenceId: occurrence.id, kind: kind)
            
            // Cancel notifications for this occurrence
            notificationManager.cancelNotification(for: occurrence.id)
            
            await refresh()
        } catch {
            errorMessage = "Failed to acknowledge: \(error.localizedDescription)"
        }
    }
    
    func snooze(occurrence: OccurrenceResponse, minutes: Int) async {
        do {
            // Cancel existing notifications
            notificationManager.cancelNotification(for: occurrence.id)
            
            // Call backend snooze endpoint
            let response = try await apiClient.snooze(occurrenceId: occurrence.id, minutes: minutes)
            
            print("✅ Snoozed! New occurrence ID: \(response.snoozedOccurrenceId) at \(response.scheduledAt)")
            
            // Refresh to get updated list including new snoozed occurrence
            await refresh()
            
            errorMessage = "⏰ Reminder snoozed for \(minutes) minutes"
            
            // Clear message after 3 seconds
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                errorMessage = nil
            }
        } catch {
            errorMessage = "Failed to snooze: \(error.localizedDescription)"
        }
    }
    
    nonisolated func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.4 // Slower for seniors
        utterance.volume = 1.0
        synthesizer.speak(utterance)
    }
}
