import Foundation
import SwiftData

@MainActor
class DataManager {
    static let shared = DataManager()
    
    let modelContainer: ModelContainer
    let modelContext: ModelContext
    
    private init() {
        do {
            let schema = Schema([
                LocalReminder.self,
                LocalOccurrence.self,
                PendingAction.self
            ])
            
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            modelContext = ModelContext(modelContainer)
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }
    
    // MARK: - Occurrences
    
    func saveOccurrences(_ occurrences: [OccurrenceResponse]) throws {
        // Clear existing occurrences for today
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        
        print("💾 saveOccurrences called with \(occurrences.count) occurrences")
        
        let descriptor = FetchDescriptor<LocalOccurrence>(
            predicate: #Predicate { occurrence in
                occurrence.scheduledAt >= today && occurrence.scheduledAt < tomorrow
            }
        )
        
        let existing = try modelContext.fetch(descriptor)
        print("🗑️ Deleting \(existing.count) existing occurrences from cache")
        for occurrence in existing {
            print("  - Deleting id:\(occurrence.id), reminderId:\(occurrence.reminderId)")
            modelContext.delete(occurrence)
        }
        
        // Save new occurrences
        print("➕ Inserting \(occurrences.count) new occurrences")
        for occurrence in occurrences {
            print("  + Inserting id:\(occurrence.id), reminderId:\(occurrence.reminderId), title:'\(occurrence.reminder.title)'")
            let local = LocalOccurrence.from(occurrence)
            modelContext.insert(local)
        }
        
        try modelContext.save()
        print("✅ saveOccurrences complete")
    }
    
    func fetchTodayOccurrences() throws -> [LocalOccurrence] {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        
        let descriptor = FetchDescriptor<LocalOccurrence>(
            predicate: #Predicate { occurrence in
                occurrence.scheduledAt >= today && occurrence.scheduledAt < tomorrow
            },
            sortBy: [SortDescriptor(\.scheduledAt)]
        )
        
        return try modelContext.fetch(descriptor)
    }
    
    func updateOccurrenceStatus(id: Int, status: String) throws {
        let descriptor = FetchDescriptor<LocalOccurrence>(
            predicate: #Predicate { occurrence in
                occurrence.id == id
            }
        )
        
        if let occurrence = try modelContext.fetch(descriptor).first {
            occurrence.status = status
            occurrence.updatedAt = Date()
            try modelContext.save()
        }
    }
    
    func insertOccurrence(_ occurrence: LocalOccurrence) throws {
        modelContext.insert(occurrence)
        try modelContext.save()
    }
    
    func deleteOccurrencesByReminderId(_ reminderId: Int) throws {
        let descriptor = FetchDescriptor<LocalOccurrence>(
            predicate: #Predicate { occurrence in
                occurrence.reminderId == reminderId
            }
        )
        
        let occurrences = try modelContext.fetch(descriptor)
        for occurrence in occurrences {
            modelContext.delete(occurrence)
        }
        try modelContext.save()
    }
    
    // MARK: - Reminders
    
    func saveReminders(_ reminders: [ReminderResponse]) throws {
        for reminder in reminders {
            let descriptor = FetchDescriptor<LocalReminder>(
                predicate: #Predicate { r in
                    r.id == reminder.id
                }
            )
            
            if let existing = try modelContext.fetch(descriptor).first {
                // Update existing
                existing.title = reminder.title
                existing.notes = reminder.notes
                existing.rrule = reminder.rrule
                existing.category = reminder.category
                existing.updatedAt = reminder.updatedAt
                existing.lastSyncedAt = Date()
            } else {
                // Insert new
                let local = LocalReminder.from(reminder)
                modelContext.insert(local)
            }
        }
        
        try modelContext.save()
    }
    
    func fetchReminders() throws -> [LocalReminder] {
        let descriptor = FetchDescriptor<LocalReminder>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        
        return try modelContext.fetch(descriptor)
    }
    
    func createLocalReminder(id: Int, title: String, notes: String?, category: String, rrule: String, tz: String) throws {
        let now = Date()
        let reminder = LocalReminder(
            id: id,
            title: title,
            notes: notes,
            rrule: rrule,
            tz: tz,
            category: category,
            userId: 0, // Temporary user ID
            createdAt: now,
            updatedAt: now,
            lastSyncedAt: nil
        )
        
        modelContext.insert(reminder)
        try modelContext.save()
    }
    
    func updateReminder(id: Int, title: String, notes: String?, category: String, rrule: String) throws {
        let descriptor = FetchDescriptor<LocalReminder>(
            predicate: #Predicate { r in
                r.id == id
            }
        )
        
        if let reminder = try modelContext.fetch(descriptor).first {
            print("📝 Found reminder \(id) in cache, updating title: '\(reminder.title)' → '\(title)'")
            reminder.title = title
            reminder.notes = notes
            reminder.category = category
            reminder.rrule = rrule
            reminder.updatedAt = Date()
            
            // Also update all associated occurrences' cached reminder info
            let occurrenceDescriptor = FetchDescriptor<LocalOccurrence>(
                predicate: #Predicate { o in
                    o.reminderId == id
                }
            )
            
            let occurrences = try modelContext.fetch(occurrenceDescriptor)
            print("📝 Updating \(occurrences.count) occurrences with new title")
            for occurrence in occurrences {
                occurrence.reminderTitle = title
                occurrence.reminderNotes = notes
                occurrence.reminderCategory = category
            }
            
            try modelContext.save()
            print("💾 Saved changes to SwiftData")
        } else {
            print("⚠️ Reminder \(id) not found in cache!")
        }
    }
    
    func deleteReminder(id: Int) throws {
        let descriptor = FetchDescriptor<LocalReminder>(
            predicate: #Predicate { r in
                r.id == id
            }
        )
        
        if let reminder = try modelContext.fetch(descriptor).first {
            modelContext.delete(reminder)
            try modelContext.save()
        }
    }
    
    // MARK: - Pending Actions
    
    func addPendingAction(_ action: PendingAction) throws {
        modelContext.insert(action)
        try modelContext.save()
    }
    
    func fetchPendingActions() throws -> [PendingAction] {
        let descriptor = FetchDescriptor<PendingAction>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        
        return try modelContext.fetch(descriptor)
    }
    
    func deletePendingAction(_ action: PendingAction) throws {
        modelContext.delete(action)
        try modelContext.save()
    }
    
    func updatePendingAction(_ action: PendingAction, retryCount: Int, error: String?) throws {
        action.retryCount = retryCount
        action.lastRetryAt = Date()
        action.error = error
        try modelContext.save()
    }
}
