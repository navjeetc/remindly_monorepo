import Foundation
import SwiftUI
import Combine

/// App-wide settings with UserDefaults persistence
class AppSettings: ObservableObject {
    static let shared = AppSettings()
    
    // MARK: - Appearance Settings
    @AppStorage("fontSize") var fontSize: Double = 24.0
    @AppStorage("highContrastMode") var highContrastMode: Bool = false
    @AppStorage("colorScheme") var colorScheme: String = "auto"
    
    // MARK: - Voice & Sound Settings
    @AppStorage("voiceRate") var voiceRate: Double = 0.4
    @AppStorage("voiceVolume") var voiceVolume: Double = 1.0
    @AppStorage("notificationSoundEnabled") var notificationSoundEnabled: Bool = true
    
    // MARK: - Notification Settings
    @AppStorage("notificationsEnabled") var notificationsEnabled: Bool = true
    @AppStorage("reminderLeadTime") var reminderLeadTime: Int = 2
    @AppStorage("repeatInterval") var repeatInterval: Int = 5
    @AppStorage("quietHoursEnabled") var quietHoursEnabled: Bool = false
    @AppStorage("quietHoursStart") var quietHoursStart: Double = 22.0
    @AppStorage("quietHoursEnd") var quietHoursEnd: Double = 7.0
    
    // MARK: - Computed Properties
    var preferredColorScheme: ColorScheme? {
        switch colorScheme {
        case "light": return .light
        case "dark": return .dark
        default: return nil // auto
        }
    }
    
    var quietHoursStartTime: Date {
        let calendar = Calendar.current
        let hour = Int(quietHoursStart)
        let minute = Int((quietHoursStart - Double(hour)) * 60)
        return calendar.date(from: DateComponents(hour: hour, minute: minute)) ?? Date()
    }
    
    var quietHoursEndTime: Date {
        let calendar = Calendar.current
        let hour = Int(quietHoursEnd)
        let minute = Int((quietHoursEnd - Double(hour)) * 60)
        return calendar.date(from: DateComponents(hour: hour, minute: minute)) ?? Date()
    }
    
    // MARK: - Helper Methods
    func isInQuietHours() -> Bool {
        guard quietHoursEnabled else { return false }
        
        let calendar = Calendar.current
        let now = Date()
        let currentHour = Double(calendar.component(.hour, from: now))
        let currentMinute = Double(calendar.component(.minute, from: now))
        let currentTime = currentHour + (currentMinute / 60.0)
        
        if quietHoursStart < quietHoursEnd {
            // Same day range (e.g., 22:00 to 23:00)
            return currentTime >= quietHoursStart && currentTime < quietHoursEnd
        } else {
            // Overnight range (e.g., 22:00 to 07:00)
            return currentTime >= quietHoursStart || currentTime < quietHoursEnd
        }
    }
    
    func resetToDefaults() {
        fontSize = 24.0
        highContrastMode = false
        colorScheme = "auto"
        voiceRate = 0.4
        voiceVolume = 1.0
        notificationSoundEnabled = true
        notificationsEnabled = true
        reminderLeadTime = 2
        repeatInterval = 5
        quietHoursEnabled = false
        quietHoursStart = 22.0
        quietHoursEnd = 7.0
    }
}
