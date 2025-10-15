import SwiftUI
import AVFoundation
import Combine

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @Environment(\.dismiss) var dismiss
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.system(size: 32, weight: .bold))
                
                Spacer()
                
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Tab selection
            HStack(spacing: 0) {
                SettingsTab(title: "Appearance", icon: "textformat.size", isSelected: selectedTab == 0) {
                    selectedTab = 0
                }
                SettingsTab(title: "Voice & Sound", icon: "speaker.wave.2", isSelected: selectedTab == 1) {
                    selectedTab = 1
                }
                SettingsTab(title: "Notifications", icon: "bell.badge", isSelected: selectedTab == 2) {
                    selectedTab = 2
                }
                SettingsTab(title: "Account", icon: "person.circle", isSelected: selectedTab == 3) {
                    selectedTab = 3
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            Divider()
                .padding(.top, 8)
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch selectedTab {
                    case 0:
                        AppearanceSettings()
                    case 1:
                        VoiceSoundSettings()
                    case 2:
                        NotificationSettings()
                    case 3:
                        AccountSettings()
                    default:
                        EmptyView()
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer
            HStack {
                Button("Reset to Defaults") {
                    settings.resetToDefaults()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 700, height: 600)
    }
}

struct SettingsTab: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(title)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
            }
            .foregroundColor(isSelected ? .blue : .primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Appearance Settings
struct AppearanceSettings: View {
    @ObservedObject var settings = AppSettings.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(title: "Text Size", icon: "textformat.size") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("A")
                            .font(.system(size: 14))
                        Slider(value: $settings.fontSize, in: 18...48, step: 2)
                        Text("A")
                            .font(.system(size: 24, weight: .bold))
                        Text("\(Int(settings.fontSize))pt")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .frame(width: 50, alignment: .trailing)
                    }
                    
                    Text("Sample Text")
                        .font(.system(size: settings.fontSize))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            
            SettingsSection(title: "Display Mode", icon: "circle.lefthalf.filled") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Color Scheme", selection: $settings.colorScheme) {
                        Text("Auto").tag("auto")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                    
                    Text("Automatically adjusts based on system appearance")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            
            SettingsSection(title: "Accessibility", icon: "eye") {
                Toggle("High Contrast Mode", isOn: $settings.highContrastMode)
                    .font(.system(size: 16))
                
                if settings.highContrastMode {
                    Text("Increases contrast for better visibility")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
        }
    }
}

// MARK: - Voice & Sound Settings
struct VoiceSoundSettings: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var isTesting = false
    @StateObject private var voicePlayer = VoicePlayer()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(title: "Voice Speed", icon: "speedometer") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "tortoise")
                            .foregroundColor(.secondary)
                        Slider(value: $settings.voiceRate, in: 0.3...0.7, step: 0.05)
                        Image(systemName: "hare")
                            .foregroundColor(.secondary)
                        Text(String(format: "%.2f", settings.voiceRate))
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .frame(width: 50, alignment: .trailing)
                    }
                    
                    Text("Slower speeds are easier to understand")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            
            SettingsSection(title: "Voice Volume", icon: "speaker.wave.3") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "speaker.wave.1")
                            .foregroundColor(.secondary)
                        Slider(value: $settings.voiceVolume, in: 0.5...1.0, step: 0.1)
                        Image(systemName: "speaker.wave.3")
                            .foregroundColor(.secondary)
                        Text("\(Int(settings.voiceVolume * 100))%")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .frame(width: 50, alignment: .trailing)
                    }
                }
            }
            
            SettingsSection(title: "Test Voice", icon: "play.circle") {
                Button(action: testVoice) {
                    HStack {
                        Image(systemName: isTesting ? "stop.circle.fill" : "play.circle.fill")
                        Text(isTesting ? "Playing..." : "Test Voice Settings")
                    }
                    .font(.system(size: 16))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .disabled(isTesting)
            }
            
            SettingsSection(title: "Notification Sound", icon: "bell") {
                Toggle("Play sound with notifications", isOn: $settings.notificationSoundEnabled)
                    .font(.system(size: 16))
            }
        }
    }
    
    private func testVoice() {
        isTesting = true
        voicePlayer.playTestVoice(rate: settings.voiceRate, volume: settings.voiceVolume)
        
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            isTesting = false
        }
    }
}

// MARK: - Notification Settings
struct NotificationSettings: View {
    @ObservedObject var settings = AppSettings.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(title: "Notifications", icon: "bell.badge") {
                Toggle("Enable notifications", isOn: $settings.notificationsEnabled)
                    .font(.system(size: 16))
                
                if !settings.notificationsEnabled {
                    Text("You won't receive reminder notifications")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                        .padding(.top, 4)
                }
            }
            
            if settings.notificationsEnabled {
                SettingsSection(title: "Voice Prompt Lead Time", icon: "clock") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("\(settings.reminderLeadTime) minutes before")
                                .font(.system(size: 16))
                            Spacer()
                            Stepper("", value: $settings.reminderLeadTime, in: 1...10)
                        }
                        
                        Text("Voice prompt will play \(settings.reminderLeadTime) minute\(settings.reminderLeadTime == 1 ? "" : "s") before the scheduled time")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                
                SettingsSection(title: "Repeat Interval", icon: "repeat") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Every \(settings.repeatInterval) minutes")
                                .font(.system(size: 16))
                            Spacer()
                            Stepper("", value: $settings.repeatInterval, in: 3...15)
                        }
                        
                        Text("Notification will repeat every \(settings.repeatInterval) minutes if not acknowledged")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                
                SettingsSection(title: "Quiet Hours", icon: "moon") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Enable quiet hours", isOn: $settings.quietHoursEnabled)
                            .font(.system(size: 16))
                        
                        if settings.quietHoursEnabled {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Start:")
                                        .frame(width: 60, alignment: .leading)
                                    TimePickerSlider(value: $settings.quietHoursStart)
                                }
                                
                                HStack {
                                    Text("End:")
                                        .frame(width: 60, alignment: .leading)
                                    TimePickerSlider(value: $settings.quietHoursEnd)
                                }
                                
                                Text("No notifications will be sent during quiet hours")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .padding(.top, 4)
                            }
                            .padding(.top, 8)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Helper Views
struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(.blue)
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
            }
            
            content
                .padding(.leading, 26)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
}

struct TimePickerSlider: View {
    @Binding var value: Double
    
    var body: some View {
        HStack {
            Slider(value: $value, in: 0...24, step: 0.25)
            Text(timeString)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 80, alignment: .trailing)
                .monospacedDigit()
        }
    }
    
    var timeString: String {
        let hours = Int(value)
        let minutes = Int((value - Double(hours)) * 60)
        return String(format: "%02d:%02d", hours, minutes)
    }
}

// MARK: - Account Settings
struct AccountSettings: View {
    @ObservedObject private var authManager = AuthenticationManager.shared
    @State private var showLogoutConfirmation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Account")
                .font(.system(size: 24, weight: .bold))
            
            // User Info
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Signed in as")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            
                            Text(authManager.userEmail ?? "Unknown")
                                .font(.system(size: 16, weight: .medium))
                        }
                        
                        Spacer()
                    }
                }
                .padding(8)
            }
            
            // Session Info
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(.green)
                        Text("Session Active")
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                    
                    Text("Your session is secure and encrypted.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(8)
            }
            
            Spacer()
            
            // Logout Button
            Button(action: {
                showLogoutConfirmation = true
            }) {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Logout")
                        .font(.system(size: 16, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .alert("Logout", isPresented: $showLogoutConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Logout", role: .destructive) {
                    authManager.logout()
                }
            } message: {
                Text("Are you sure you want to logout? You'll need to sign in again to access your reminders.")
            }
        }
    }
}

// MARK: - Voice Player Helper
class VoicePlayer: ObservableObject {
    nonisolated(unsafe) private let synthesizer = AVSpeechSynthesizer()
    
    func playTestVoice(rate: Double, volume: Double) {
        Task.detached { [synthesizer] in
            let utterance = AVSpeechUtterance(string: "This is how your reminders will sound. Take your medication now.")
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = Float(rate)
            utterance.volume = Float(volume)
            synthesizer.speak(utterance)
        }
    }
}

#Preview {
    SettingsView()
}
