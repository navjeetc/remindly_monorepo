import Foundation
import AVFoundation
import Combine
import SwiftData

@MainActor
class ReminderVM: ObservableObject {
    @Published var occurrences: [OccurrenceResponse] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isAuthenticated = false
    @Published var isOffline = false
    
    private var isRefreshing = false
    private var isBootstrapping = false
    
    nonisolated(unsafe) private let synthesizer = AVSpeechSynthesizer()
    let apiClient = APIClient.shared // Made public for EditReminderView
    private let notificationManager = NotificationManager.shared
    private let dataManager = DataManager.shared
    private let syncManager = SyncManager.shared
    private let networkMonitor = NetworkMonitor.shared
    private let settings = AppSettings.shared
    private var notificationObserver: NSObjectProtocol?
    private var networkObserver: AnyCancellable?
    
    init() {
        setupNotificationObserver()
        setupNetworkObserver()
    }
    
    deinit {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    func bootstrap() {
        Task {
            isBootstrapping = true
            defer { isBootstrapping = false }
            
            print("🚀 ========== BOOTSTRAP STARTED ==========")
            
            // Request notification permissions
            let granted = await notificationManager.requestAuthorization()
            if !granted {
                errorMessage = "Notification permissions denied. Please enable in System Settings."
            }
            
            // Authentication is now handled by AuthenticationManager
            // Token is already set in APIClient by AuthenticationManager
            isAuthenticated = true
            
            // DEVELOPMENT ONLY: Clear all local data on startup to ensure fresh state
            #if DEBUG
            do {
                print("🧹 DEV MODE: Clearing all local data on startup...")
                try dataManager.clearAllLocalData()
                print("✅ DEV MODE: All local data cleared")
            } catch {
                print("⚠️ Failed to clear local data: \(error.localizedDescription)")
            }
            #endif
            
            // Check what's in cache BEFORE refresh
            do {
                let cachedOccurrences = try dataManager.fetchTodayOccurrences()
                print("📦 Cache BEFORE refresh: \(cachedOccurrences.count) occurrences")
                for (index, occ) in cachedOccurrences.enumerated() {
                    print("  [\(index)] CACHED id:\(occ.id), reminderId:\(occ.reminderId), title:'\(occ.reminderTitle)'")
                    if occ.reminderId < 0 {
                        print("    ⚠️ WARNING: Temporary reminder with negative ID found in cache!")
                    }
                }
                
                // Also check for ALL occurrences (not just today) to see if there are old temp ones
                let allDescriptor = FetchDescriptor<LocalOccurrence>()
                let allCached = try dataManager.modelContext.fetch(allDescriptor)
                let tempOccurrences = allCached.filter { $0.reminderId < 0 }
                if !tempOccurrences.isEmpty {
                    print("⚠️ Found \(tempOccurrences.count) temporary occurrences with negative IDs in cache:")
                    for occ in tempOccurrences {
                        print("  - id:\(occ.id), reminderId:\(occ.reminderId), scheduledAt:\(occ.scheduledAt)")
                    }
                }
            } catch {
                print("⚠️ Failed to check cache: \(error.localizedDescription)")
            }
            
            // Initial fetch and cache
            await refresh()
            
            // Also fetch and cache all reminders
            if networkMonitor.effectivelyConnected {
                do {
                    let reminders = try await apiClient.fetchReminders()
                    try dataManager.saveReminders(reminders)
                    print("✅ Cached \(reminders.count) reminders")
                } catch {
                    print("⚠️ Failed to cache reminders: \(error.localizedDescription)")
                }
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
    
    private func setupNetworkObserver() {
        networkObserver = Publishers.CombineLatest(
            networkMonitor.$isConnected,
            networkMonitor.$forceOffline
        )
        .map { isConnected, forceOffline in
            return isConnected && !forceOffline
        }
        .sink { [weak self] effectivelyConnected in
            guard let self = self else { return }
            self.isOffline = !effectivelyConnected
            
            // Don't trigger sync/refresh during initial bootstrap
            guard !self.isBootstrapping else {
                print("⚠️ Network change during bootstrap, ignoring")
                return
            }
            
            if effectivelyConnected {
                Task {
                    // Wait for sync to complete before refreshing
                    await self.syncManager.syncPendingActions()
                    await self.refresh()
                }
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
        // Prevent concurrent refresh calls
        guard !isRefreshing else {
            print("⚠️ Refresh already in progress, ignoring duplicate call")
            return
        }
        
        isRefreshing = true
        defer { isRefreshing = false }
        
        isLoading = true
        errorMessage = nil
        
        do {
            if networkMonitor.effectivelyConnected {
                // Online: fetch from API and cache
                print("🌐 ========== ONLINE REFRESH ==========")
                print("🔄 Fetching occurrences from API...")
                print("📊 Current occurrences count BEFORE fetch: \(occurrences.count)")
                
                let apiResponse = try await apiClient.fetchTodayReminders()
                print("📡 API RESPONSE: \(apiResponse.count) occurrences")
                for (index, occ) in apiResponse.enumerated() {
                    print("  [\(index)] API id:\(occ.id), reminderId:\(occ.reminderId), title:'\(occ.reminder.title)' at \(occ.scheduledAt) (\(occ.status))")
                }
                
                occurrences = apiResponse
                print("📊 Occurrences count AFTER fetch: \(occurrences.count)")
                try dataManager.saveOccurrences(occurrences)
                print("✅ Fetched \(occurrences.count) occurrences from API")
                for (index, occ) in occurrences.enumerated() {
                    print("  [\(index)] id:\(occ.id) - '\(occ.reminder.title)' at \(occ.scheduledAt) (\(occ.status))")
                }
                
                // Also refresh reminders cache for offline editing
                do {
                    let reminders = try await apiClient.fetchReminders()
                    try dataManager.saveReminders(reminders)
                    print("✅ Cached \(reminders.count) reminders")
                } catch {
                    print("⚠️ Failed to cache reminders: \(error.localizedDescription)")
                }
            } else {
                // Offline: load from cache
                print("📴 ========== OFFLINE MODE ==========")
                let localOccurrences = try dataManager.fetchTodayOccurrences()
                print("📦 Loading from cache: \(localOccurrences.count) occurrences")
                for (index, occ) in localOccurrences.enumerated() {
                    print("  [\(index)] CACHED id:\(occ.id), reminderId:\(occ.reminderId), title:'\(occ.reminderTitle)'")
                }
                occurrences = localOccurrences.map { $0.toOccurrenceResponse() }
                print("📱 Loaded \(occurrences.count) occurrences from cache (offline)")
                if !occurrences.isEmpty {
                    print("📱 First occurrence title: '\(occurrences[0].reminder.title)'")
                }
            }
            
            // Deduplicate by ID (defensive programming)
            var seen = Set<Int>()
            occurrences = occurrences.filter { occurrence in
                if seen.contains(occurrence.id) {
                    print("⚠️ Duplicate occurrence detected in refresh: id=\(occurrence.id), title='\(occurrence.reminder.title)'")
                    return false
                }
                seen.insert(occurrence.id)
                return true
            }
            print("📊 Final occurrences count after deduplication: \(occurrences.count)")
            
            // Schedule notifications for all pending reminders
            await notificationManager.scheduleNotifications(for: occurrences)
            print("🔔 Scheduled notifications for \(occurrences.count) occurrences")
        } catch {
            print("❌ Refresh error: \(error.localizedDescription)")
            errorMessage = "Failed to load reminders: \(error.localizedDescription)"
        }
        
        isLoading = false
        print("✅ Refresh complete, isLoading=false, occurrences.count=\(occurrences.count)")
    }
    
    func acknowledge(occurrence: OccurrenceResponse, kind: String) async {
        do {
            // Queue the action (will sync immediately if online)
            try await syncManager.queueAcknowledge(occurrenceId: occurrence.id, kind: kind)
            
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
            
            // Queue the snooze action
            try await syncManager.queueSnooze(occurrenceId: occurrence.id, minutes: minutes)
            
            // Refresh to get updated list
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
    
    func createReminder(title: String, notes: String?, category: String, rrule: String, time: Date) async throws {
        isLoading = true
        errorMessage = nil
        
        do {
            // For hourly reminders, pass the start time
            let startTime = rrule.contains("FREQ=HOURLY") ? time : nil
            
            // Queue the create action (this will sync and update cache if online)
            try await syncManager.queueCreateReminder(
                title: title,
                notes: notes,
                category: category,
                rrule: rrule,
                tz: TimeZone.current.identifier,
                startTime: startTime
            )
            
            // Load the updated occurrences from cache (already updated by sync)
            let localOccurrences = try dataManager.fetchTodayOccurrences()
            occurrences = localOccurrences.map { $0.toOccurrenceResponse() }
            
            // Deduplicate by ID (defensive programming)
            var seen = Set<Int>()
            occurrences = occurrences.filter { occurrence in
                if seen.contains(occurrence.id) {
                    print("⚠️ Duplicate occurrence detected: id=\(occurrence.id), title='\(occurrence.reminder.title)'")
                    return false
                }
                seen.insert(occurrence.id)
                return true
            }
            
            print("✅ Loaded \(occurrences.count) occurrences from cache after create")
            
            // Schedule notifications for all pending reminders
            await notificationManager.scheduleNotifications(for: occurrences)
            
            print("✅ Reminder created: \(title)")
            isLoading = false
        } catch {
            errorMessage = "Failed to create reminder: \(error.localizedDescription)"
            isLoading = false
            throw error
        }
    }
    
    func updateReminder(id: Int, title: String, notes: String?, category: String, rrule: String) async throws {
        print("🔄 Starting updateReminder for id:\(id), title:'\(title)'")
        isLoading = true
        errorMessage = nil
        
        do {
            // Queue the update action
            print("📝 Queueing update action...")
            try await syncManager.queueUpdateReminder(
                id: id,
                title: title,
                notes: notes,
                category: category,
                rrule: rrule,
                tz: TimeZone.current.identifier
            )
            
            print("🔄 Update queued, now refreshing occurrences...")
            // Refresh to show updated occurrences
            await refresh()
            
            print("✅ Reminder updated: \(title)")
        } catch {
            print("❌ Update failed: \(error.localizedDescription)")
            errorMessage = "Failed to update reminder: \(error.localizedDescription)"
            isLoading = false
            throw error
        }
    }
    
    func deleteReminder(id: Int) async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Queue the delete action
            try await syncManager.queueDeleteReminder(id: id)
            
            // Refresh to remove deleted reminder's occurrences
            await refresh()
            
            print("✅ Reminder deleted")
        } catch {
            errorMessage = "Failed to delete reminder: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    func speak(_ text: String) {
        let voiceRate = settings.voiceRate
        let voiceVolume = settings.voiceVolume
        
        Task.detached { [weak self] in
            guard let self = self else { return }
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = Float(voiceRate)
            utterance.volume = Float(voiceVolume)
            self.synthesizer.speak(utterance)
        }
    }
}
