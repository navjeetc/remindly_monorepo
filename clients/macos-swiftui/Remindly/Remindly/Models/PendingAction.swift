import Foundation
import SwiftData

@Model
final class PendingAction {
    @Attribute(.unique) var id: UUID
    var actionType: String // "acknowledge", "snooze", "create_reminder", "update_reminder", "delete_reminder"
    var occurrenceId: Int?
    var reminderId: Int?
    var payload: Data // JSON encoded data
    var createdAt: Date
    var retryCount: Int
    var lastRetryAt: Date?
    var error: String?
    
    init(id: UUID = UUID(), actionType: String, occurrenceId: Int? = nil, reminderId: Int? = nil, payload: Data, createdAt: Date = Date(), retryCount: Int = 0, lastRetryAt: Date? = nil, error: String? = nil) {
        self.id = id
        self.actionType = actionType
        self.occurrenceId = occurrenceId
        self.reminderId = reminderId
        self.payload = payload
        self.createdAt = createdAt
        self.retryCount = retryCount
        self.lastRetryAt = lastRetryAt
        self.error = error
    }
}

// Helper structs for payload encoding
struct AcknowledgePayload: Codable {
    let occurrenceId: Int
    let kind: String
}

struct SnoozePayload: Codable {
    let occurrenceId: Int
    let minutes: Int
}

struct CreateReminderPayload: Codable {
    let title: String
    let notes: String?
    let category: String
    let rrule: String
    let tz: String
    let startTime: Date?
    
    enum CodingKeys: String, CodingKey {
        case title, notes, category, rrule, tz
        case startTime = "start_time"
    }
}

struct UpdateReminderPayload: Codable {
    let id: Int
    let title: String
    let notes: String?
    let category: String
    let rrule: String
    let tz: String
    let startTime: Date?
    
    enum CodingKeys: String, CodingKey {
        case id, title, notes, category, rrule, tz
        case startTime = "start_time"
    }
}

struct DeleteReminderPayload: Codable {
    let id: Int
}
