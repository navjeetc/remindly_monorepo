# Settings & Accessibility Feature

## Quick Reference

### New Files Added
- `Remindly/Models/AppSettings.swift` - Settings model with UserDefaults persistence
- `Remindly/SettingsView.swift` - Settings UI with 3 tabs

### Modified Files
- `Remindly/ReminderListView.swift` - Added settings button, dynamic font sizing, high contrast mode
- `Remindly/ReminderVM.swift` - Uses settings for voice synthesis
- `Remindly/NotificationManager.swift` - Respects all notification settings

## How to Use

### Accessing Settings
Click the gear icon (⚙️) in the top-right corner of the main view.

### Available Settings

#### Appearance Tab
- **Font Size**: Drag slider to adjust text size (18-48pt)
- **Color Scheme**: Choose Auto/Light/Dark mode
- **High Contrast**: Toggle for better visibility

#### Voice & Sound Tab
- **Voice Speed**: Adjust how fast reminders are spoken
- **Voice Volume**: Control voice loudness
- **Test Voice**: Click to hear a sample
- **Notification Sound**: Enable/disable notification sounds

#### Notifications Tab
- **Enable Notifications**: Master on/off switch
- **Lead Time**: How many minutes before the reminder to play voice prompt
- **Repeat Interval**: How often to repeat if not acknowledged
- **Quiet Hours**: Set time range to suppress notifications

### Settings Persistence
All settings are automatically saved and restored when you restart the app.

### Reset to Defaults
Click "Reset to Defaults" button at the bottom of settings to restore original values.

## For Developers

### Accessing Settings in Code
```swift
let settings = AppSettings.shared

// Read a setting
let fontSize = settings.fontSize

// Modify a setting (auto-saves)
settings.fontSize = 32.0

// Check quiet hours
if settings.isInQuietHours() {
    // Skip notification
}
```

### Using Settings in SwiftUI Views
```swift
@ObservedObject var settings = AppSettings.shared

var body: some View {
    Text("Hello")
        .font(.system(size: settings.fontSize))
        .preferredColorScheme(settings.preferredColorScheme)
}
```

## Testing Checklist
- [ ] Change font size - verify UI updates
- [ ] Toggle high contrast - verify borders appear
- [ ] Switch color scheme - verify theme changes
- [ ] Test voice - verify rate and volume work
- [ ] Enable quiet hours - verify notifications are suppressed
- [ ] Restart app - verify settings persist
- [ ] Reset to defaults - verify all settings reset

## Documentation
See `/SPRINT_4_SETTINGS_GUIDE.md` for complete implementation details.
