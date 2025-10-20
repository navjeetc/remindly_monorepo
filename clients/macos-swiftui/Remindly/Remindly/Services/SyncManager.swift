import Foundation
import Combine

@MainActor
class SyncManager: ObservableObject {
    static let shared = SyncManager()
    
    @Published var isSyncing = false
    @Published var pendingActionsCount = 0
    
    private let dataManager = DataManager.shared
    private let apiClient = APIClient.shared
    private let networkMonitor = NetworkMonitor.shared
    
    private var syncObserver: NSObjectProtocol?
    private var isCreatingReminder = false
    
    private init() {
        setupNetworkObserver()
        updatePendingCount()
    }
    
    private func setupNetworkObserver() {
        syncObserver = NotificationCenter.default.addObserver(
            forName: .networkConnected,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.syncPendingActions()
            }
        }
    }
    
    deinit {
        if let observer = syncObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Queue Actions
    
    func queueAcknowledge(occurrenceId: Int, kind: String) async throws {
        let payload = AcknowledgePayload(occurrenceId: occurrenceId, kind: kind)
        let data = try JSONEncoder().encode(payload)
        
        let action = PendingAction(
            actionType: "acknowledge",
            occurrenceId: occurrenceId,
            payload: data
        )
        
        try dataManager.addPendingAction(action)
        updatePendingCount()
        
        // Update local status immediately
        try dataManager.updateOccurrenceStatus(id: occurrenceId, status: "acknowledged")
        
        // Try to sync if online
        if networkMonitor.effectivelyConnected {
            await syncPendingActions()
        }
    }
    
    func queueSnooze(occurrenceId: Int, minutes: Int) async throws {
        let payload = SnoozePayload(occurrenceId: occurrenceId, minutes: minutes)
        let data = try JSONEncoder().encode(payload)
        
        let action = PendingAction(
            actionType: "snooze",
            occurrenceId: occurrenceId,
            payload: data
        )
        
        try dataManager.addPendingAction(action)
        updatePendingCount()
        
        // Update local status
        try dataManager.updateOccurrenceStatus(id: occurrenceId, status: "acknowledged")
        
        if networkMonitor.effectivelyConnected {
            await syncPendingActions()
        }
    }
    
    func queueCreateReminder(title: String, notes: String?, category: String, rrule: String, tz: String, startTime: Date? = nil) async throws {
        // Prevent concurrent reminder creation
        guard !isCreatingReminder else {
            print("⚠️ Reminder creation already in progress, ignoring duplicate call")
            return
        }
        
        isCreatingReminder = true
        defer { isCreatingReminder = false }
        
        let payload = CreateReminderPayload(
            title: title,
            notes: notes,
            category: category,
            rrule: rrule,
            tz: tz,
            startTime: startTime
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        
        // Generate temporary negative ID for offline-created reminders
        let tempId = -Int(Date().timeIntervalSince1970)
        
        let action = PendingAction(
            actionType: "create_reminder",
            reminderId: tempId,
            payload: data
        )
        
        try dataManager.addPendingAction(action)
        updatePendingCount()
        
        // Create local reminder with temporary ID for offline editing
        try dataManager.createLocalReminder(
            id: tempId,
            title: title,
            notes: notes,
            category: category,
            rrule: rrule,
            tz: tz
        )
        
        // Create a local occurrence for today so the reminder appears in the list
        try createLocalOccurrenceForToday(
            reminderId: tempId,
            title: title,
            notes: notes,
            category: category,
            rrule: rrule,
            startTime: startTime
        )
        
        if networkMonitor.effectivelyConnected {
            await syncPendingActions()
        }
    }
    
    func queueUpdateReminder(id: Int, title: String, notes: String?, category: String, rrule: String, tz: String, startTime: Date? = nil) async throws {
        // If updating a temporary reminder (negative ID), update the pending create action instead
        if id < 0 {
            let actions = try dataManager.fetchPendingActions()
            if let createAction = actions.first(where: { $0.actionType == "create_reminder" && $0.reminderId == id }) {
                // Update the create action's payload
                let newPayload = CreateReminderPayload(
                    title: title,
                    notes: notes,
                    category: category,
                    rrule: rrule,
                    tz: tz,
                    startTime: startTime
                )
                let newData = try JSONEncoder().encode(newPayload)
                
                // Delete old action and create new one with updated payload
                try dataManager.deletePendingAction(createAction)
                let updatedAction = PendingAction(
                    actionType: "create_reminder",
                    reminderId: id,
                    payload: newData
                )
                try dataManager.addPendingAction(updatedAction)
                
                // Update local cache
                try dataManager.updateReminder(id: id, title: title, notes: notes, category: category, rrule: rrule)
                
                print("✅ Updated pending create action for temporary reminder")
                updatePendingCount()
                return
            }
        }
        
        // Normal update flow for synced reminders
        let payload = UpdateReminderPayload(
            id: id,
            title: title,
            notes: notes,
            category: category,
            rrule: rrule,
            tz: tz,
            startTime: startTime
        )
        let data = try JSONEncoder().encode(payload)
        
        let action = PendingAction(
            actionType: "update_reminder",
            reminderId: id,
            payload: data
        )
        
        try dataManager.addPendingAction(action)
        updatePendingCount()
        
        // Update local cache immediately for offline UI
        print("🔄 Updating local cache for reminder \(id): \(title)")
        try dataManager.updateReminder(id: id, title: title, notes: notes, category: category, rrule: rrule)
        print("✅ Local cache updated for reminder \(id)")
        
        if networkMonitor.effectivelyConnected {
            await syncPendingActions()
        }
    }
    
    func queueDeleteReminder(id: Int) async throws {
        let payload = DeleteReminderPayload(id: id)
        let data = try JSONEncoder().encode(payload)
        
        let action = PendingAction(
            actionType: "delete_reminder",
            reminderId: id,
            payload: data
        )
        
        try dataManager.addPendingAction(action)
        updatePendingCount()
        
        // Delete locally immediately
        try dataManager.deleteReminder(id: id)
        
        if networkMonitor.effectivelyConnected {
            await syncPendingActions()
        }
    }
    
    // MARK: - Sync
    
    func syncPendingActions() async {
        guard networkMonitor.effectivelyConnected else {
            print("⚠️ Cannot sync: offline")
            return
        }
        
        guard !isSyncing else {
            print("⚠️ Sync already in progress")
            return
        }
        
        isSyncing = true
        defer { isSyncing = false }
        
        do {
            let actions = try dataManager.fetchPendingActions()
            print("🔄 Syncing \(actions.count) pending actions")
            
            for action in actions {
                do {
                    try await processAction(action)
                    try dataManager.deletePendingAction(action)
                    print("✅ Synced action: \(action.actionType)")
                } catch {
                    let retryCount = action.retryCount + 1
                    try dataManager.updatePendingAction(action, retryCount: retryCount, error: error.localizedDescription)
                    print("❌ Failed to sync action: \(error.localizedDescription)")
                    
                    // Stop syncing if we hit too many errors
                    if retryCount >= 3 {
                        print("⚠️ Action failed 3 times, skipping: \(action.actionType)")
                    }
                }
            }
            
            updatePendingCount()
        } catch {
            print("❌ Sync error: \(error.localizedDescription)")
        }
    }
    
    private func processAction(_ action: PendingAction) async throws {
        switch action.actionType {
        case "acknowledge":
            let payload = try JSONDecoder().decode(AcknowledgePayload.self, from: action.payload)
            try await apiClient.acknowledge(occurrenceId: payload.occurrenceId, kind: payload.kind)
            
        case "snooze":
            let payload = try JSONDecoder().decode(SnoozePayload.self, from: action.payload)
            _ = try await apiClient.snooze(occurrenceId: payload.occurrenceId, minutes: payload.minutes)
            
        case "create_reminder":
            print("📝 Decoding CreateReminderPayload...")
            if let jsonString = String(data: action.payload, encoding: .utf8) {
                print("📝 Payload JSON: \(jsonString)")
            }
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let payload = try decoder.decode(CreateReminderPayload.self, from: action.payload)
            print("✅ Decoded payload: title='\(payload.title)', category=\(payload.category)")
            
            try await apiClient.createReminder(
                title: payload.title,
                notes: payload.notes,
                category: payload.category,
                rrule: payload.rrule,
                tz: payload.tz,
                startTime: payload.startTime
            )
            
            // Delete temporary local reminder and its occurrences (negative ID) after successful sync
            if let tempId = action.reminderId, tempId < 0 {
                try? dataManager.deleteReminder(id: tempId)
                try? dataManager.deleteOccurrencesByReminderId(tempId)
                print("🗑️ Deleted temporary reminder and occurrences with ID: \(tempId)")
            }
            
            // Fetch and cache the real reminder from server
            let reminders = try await apiClient.fetchReminders()
            try dataManager.saveReminders(reminders)
            print("✅ Cached \(reminders.count) reminders after create sync")
            
            // Also fetch and cache today's occurrences to ensure UI is up-to-date
            let occurrences = try await apiClient.fetchTodayReminders()
            try dataManager.saveOccurrences(occurrences)
            print("✅ Cached \(occurrences.count) occurrences after create sync")
            
        case "update_reminder":
            let payload = try JSONDecoder().decode(UpdateReminderPayload.self, from: action.payload)
            try await apiClient.updateReminder(
                id: payload.id,
                title: payload.title,
                notes: payload.notes,
                category: payload.category,
                rrule: payload.rrule,
                tz: payload.tz,
                startTime: payload.startTime
            )
            
            // Fetch and cache updated reminders from server
            let reminders = try await apiClient.fetchReminders()
            try dataManager.saveReminders(reminders)
            print("✅ Cached \(reminders.count) reminders after update sync")
            
        case "delete_reminder":
            let payload = try JSONDecoder().decode(DeleteReminderPayload.self, from: action.payload)
            try await apiClient.deleteReminder(id: payload.id)
            
        default:
            throw NSError(domain: "SyncManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown action type: \(action.actionType)"])
        }
    }
    
    private func updatePendingCount() {
        do {
            let actions = try dataManager.fetchPendingActions()
            pendingActionsCount = actions.count
        } catch {
            print("❌ Failed to update pending count: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Local Occurrence Generation
    
    private func createLocalOccurrenceForToday(reminderId: Int, title: String, notes: String?, category: String, rrule: String, startTime: Date?) throws {
        // Calculate the next occurrence time based on rrule
        let scheduledTime: Date
        
        if rrule.contains("FREQ=HOURLY") {
            // For hourly reminders, use the start time or current time
            scheduledTime = startTime ?? Date()
        } else {
            // For daily/weekly reminders, extract the time from rrule
            let calendar = Calendar.current
            var hour = 9 // Default to 9 AM
            var minute = 0
            
            // Parse BYHOUR and BYMINUTE from rrule
            if let hourMatch = rrule.range(of: "BYHOUR=(\\d+)", options: .regularExpression) {
                let hourStr = String(rrule[hourMatch]).replacingOccurrences(of: "BYHOUR=", with: "")
                hour = Int(hourStr) ?? 9
            }
            if let minuteMatch = rrule.range(of: "BYMINUTE=(\\d+)", options: .regularExpression) {
                let minuteStr = String(rrule[minuteMatch]).replacingOccurrences(of: "BYMINUTE=", with: "")
                minute = Int(minuteStr) ?? 0
            }
            
            // Create today's date with the specified time
            var components = calendar.dateComponents([.year, .month, .day], from: Date())
            components.hour = hour
            components.minute = minute
            scheduledTime = calendar.date(from: components) ?? Date()
        }
        
        // Generate a temporary negative occurrence ID
        let tempOccurrenceId = -Int(Date().timeIntervalSince1970) - 1000
        
        let now = Date()
        let occurrence = LocalOccurrence(
            id: tempOccurrenceId,
            reminderId: reminderId,
            scheduledAt: scheduledTime,
            status: "pending",
            createdAt: now,
            updatedAt: now,
            reminderTitle: title,
            reminderNotes: notes,
            reminderCategory: category,
            lastSyncedAt: nil
        )
        
        try dataManager.insertOccurrence(occurrence)
        print("✅ Created local occurrence for reminder '\(title)' at \(scheduledTime)")
    }
}
