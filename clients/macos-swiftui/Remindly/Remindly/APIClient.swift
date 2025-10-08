import Foundation

class APIClient {
    static let shared = APIClient()
    
    let baseURL = Config.baseURL
    
    private var token: String?
    
    func setToken(_ token: String) {
        self.token = token
    }
    
    func authenticate(email: String) async throws -> String {
        let url = URL(string: "\(baseURL)/magic/dev_exchange?email=\(email)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let token = String(data: data, encoding: .utf8) ?? ""
        self.token = token
        return token
    }
    
    func createReminder(title: String, notes: String?, category: String, rrule: String, tz: String, startTime: Date? = nil) async throws {
        guard let token = token else {
            throw APIError.notAuthenticated
        }
        
        var request = URLRequest(url: URL(string: "\(baseURL)/reminders")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = [
            "title": title,
            "category": category,
            "rrule": rrule,
            "tz": tz
        ]
        
        if let notes = notes {
            body["notes"] = notes
        }
        
        if let startTime = startTime {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            body["start_time"] = formatter.string(from: startTime)
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, _) = try await URLSession.shared.data(for: request)
    }
    
    func fetchTodayReminders() async throws -> [OccurrenceResponse] {
        guard let token = token else {
            throw APIError.notAuthenticated
        }
        
        var request = URLRequest(url: URL(string: "\(baseURL)/reminders/today")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string \(dateString)")
        }
        return try decoder.decode([OccurrenceResponse].self, from: data)
    }
    
    func acknowledge(occurrenceId: Int, kind: String) async throws {
        guard let token = token else {
            throw APIError.notAuthenticated
        }
        
        var request = URLRequest(url: URL(string: "\(baseURL)/acknowledgements")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["occurrence_id": occurrenceId, "kind": kind]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, _) = try await URLSession.shared.data(for: request)
    }
    
    func snooze(occurrenceId: Int, minutes: Int = 10) async throws -> SnoozeResponse {
        guard let token = token else {
            throw APIError.notAuthenticated
        }
        
        var request = URLRequest(url: URL(string: "\(baseURL)/acknowledgements/snooze")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["occurrence_id": occurrenceId, "minutes": minutes]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string \(dateString)")
        }
        return try decoder.decode(SnoozeResponse.self, from: data)
    }
    
    func fetchReminders() async throws -> [ReminderResponse] {
        guard let token = token else {
            throw APIError.notAuthenticated
        }
        
        var request = URLRequest(url: URL(string: "\(baseURL)/reminders")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string \(dateString)")
        }
        return try decoder.decode([ReminderResponse].self, from: data)
    }
    
    func updateReminder(id: Int, title: String, notes: String?, category: String, rrule: String, tz: String, startTime: Date? = nil) async throws {
        guard let token = token else {
            throw APIError.notAuthenticated
        }
        
        var request = URLRequest(url: URL(string: "\(baseURL)/reminders/\(id)")!)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = [
            "title": title,
            "category": category,
            "rrule": rrule,
            "tz": tz
        ]
        
        if let notes = notes {
            body["notes"] = notes
        }
        
        if let startTime = startTime {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            body["start_time"] = formatter.string(from: startTime)
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, _) = try await URLSession.shared.data(for: request)
    }
    
    func deleteReminder(id: Int) async throws {
        guard let token = token else {
            throw APIError.notAuthenticated
        }
        
        var request = URLRequest(url: URL(string: "\(baseURL)/reminders/\(id)")!)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (_, _) = try await URLSession.shared.data(for: request)
    }
}

enum APIError: Error {
    case notAuthenticated
}

struct OccurrenceResponse: Codable, Identifiable {
    let id: Int
    let reminderId: Int
    let scheduledAt: Date
    let status: String
    let createdAt: Date
    let updatedAt: Date
    let reminder: ReminderInfo
    
    enum CodingKeys: String, CodingKey {
        case id
        case reminderId = "reminder_id"
        case scheduledAt = "scheduled_at"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case reminder
    }
}

struct ReminderInfo: Codable {
    let title: String
    let notes: String?
    let category: String?
}

struct SnoozeResponse: Codable {
    let snoozedOccurrenceId: Int
    let scheduledAt: Date
    let minutes: Int
    
    enum CodingKeys: String, CodingKey {
        case snoozedOccurrenceId = "snoozed_occurrence_id"
        case scheduledAt = "scheduled_at"
        case minutes
    }
}

struct ReminderResponse: Codable, Identifiable {
    let id: Int
    let title: String
    let notes: String?
    let rrule: String
    let tz: String
    let category: String
    let userId: Int
    let createdAt: Date
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id, title, notes, rrule, tz, category
        case userId = "user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
