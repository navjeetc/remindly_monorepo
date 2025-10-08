import Foundation
import SwiftData

@Model
final class LocalReminder {
    @Attribute(.unique) var id: Int
    var title: String
    var notes: String?
    var rrule: String
    var tz: String
    var category: String
    var userId: Int
    var createdAt: Date
    var updatedAt: Date
    var lastSyncedAt: Date?
    
    @Relationship(deleteRule: .cascade, inverse: \LocalOccurrence.reminder)
    var occurrences: [LocalOccurrence]?
    
    init(id: Int, title: String, notes: String? = nil, rrule: String, tz: String, category: String, userId: Int, createdAt: Date, updatedAt: Date, lastSyncedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.notes = notes
        self.rrule = rrule
        self.tz = tz
        self.category = category
        self.userId = userId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastSyncedAt = lastSyncedAt
    }
    
    // Convert from API response
    static func from(_ response: ReminderResponse) -> LocalReminder {
        return LocalReminder(
            id: response.id,
            title: response.title,
            notes: response.notes,
            rrule: response.rrule,
            tz: response.tz,
            category: response.category,
            userId: response.userId,
            createdAt: response.createdAt,
            updatedAt: response.updatedAt,
            lastSyncedAt: Date()
        )
    }
}
