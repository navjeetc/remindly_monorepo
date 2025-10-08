import Foundation
import SwiftData

@Model
final class LocalOccurrence {
    @Attribute(.unique) var id: Int
    var reminderId: Int
    var scheduledAt: Date
    var status: String
    var createdAt: Date
    var updatedAt: Date
    var lastSyncedAt: Date?
    
    // Cached reminder info for display
    var reminderTitle: String
    var reminderNotes: String?
    var reminderCategory: String?
    
    var reminder: LocalReminder?
    
    init(id: Int, reminderId: Int, scheduledAt: Date, status: String, createdAt: Date, updatedAt: Date, reminderTitle: String, reminderNotes: String? = nil, reminderCategory: String? = nil, lastSyncedAt: Date? = nil) {
        self.id = id
        self.reminderId = reminderId
        self.scheduledAt = scheduledAt
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.reminderTitle = reminderTitle
        self.reminderNotes = reminderNotes
        self.reminderCategory = reminderCategory
        self.lastSyncedAt = lastSyncedAt
    }
    
    // Convert from API response
    static func from(_ response: OccurrenceResponse) -> LocalOccurrence {
        return LocalOccurrence(
            id: response.id,
            reminderId: response.reminderId,
            scheduledAt: response.scheduledAt,
            status: response.status,
            createdAt: response.createdAt,
            updatedAt: response.updatedAt,
            reminderTitle: response.reminder.title,
            reminderNotes: response.reminder.notes,
            reminderCategory: response.reminder.category,
            lastSyncedAt: Date()
        )
    }
    
    // Convert to API response format for UI
    func toOccurrenceResponse() -> OccurrenceResponse {
        return OccurrenceResponse(
            id: id,
            reminderId: reminderId,
            scheduledAt: scheduledAt,
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt,
            reminder: ReminderInfo(
                title: reminderTitle,
                notes: reminderNotes,
                category: reminderCategory
            )
        )
    }
}
