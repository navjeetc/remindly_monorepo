# Remindly Web Client

A web-based reminder application with **voice announcements** using the Web Speech API. This client provides the same announcement functionality as the SwiftUI macOS app, but runs in any modern web browser.

## Features

### 🔊 Voice Announcements
- **Web Speech API** integration for text-to-speech
- Automatic voice announcements when reminders are due
- Configurable voice rate and volume
- Works in Chrome, Edge, Safari, and other modern browsers

### 🔔 Browser Notifications
- Native browser notifications for due reminders
- Persistent notifications that require user interaction
- Click notifications to focus and scroll to reminder

### ⏰ Smart Reminder Detection
- Automatic checking for due reminders (configurable interval)
- 5-minute grace period for recently passed reminders
- Visual highlighting when reminders are announced
- Real-time status updates

### 🎨 User Interface
- Clean, modern design with responsive layout
- Color-coded reminder cards (upcoming, overdue, completed)
- Quick actions: Taken, Snooze, Skip
- Real-time statistics dashboard
- Mobile-friendly responsive design

### ⚙️ Customizable Settings
- **Voice Settings**: Enable/disable, rate, volume
- **Notification Settings**: Browser notifications, sound, check interval
- **Quiet Hours**: Disable announcements during specific times
- **API Configuration**: Custom backend URL

### 🔐 Authentication
- Magic link email authentication
- Development mode quick login
- Secure JWT token storage

## Browser Compatibility

| Feature | Chrome | Edge | Safari | Firefox |
|---------|--------|------|--------|---------|
| Voice Announcements | ✅ | ✅ | ✅ | ✅ |
| Browser Notifications | ✅ | ✅ | ✅ | ✅ |
| Local Storage | ✅ | ✅ | ✅ | ✅ |

**Note**: Voice quality and available voices may vary by browser and operating system.

## Setup Instructions

### 1. Prerequisites

- Modern web browser (Chrome, Edge, Safari, Firefox)
- Remindly backend server running (default: `http://localhost:3000`)

### 2. Start the Backend

```bash
cd backend
rails server
```

### 3. Serve the Web Client

You can use any static file server. Here are a few options:

#### Option A: Python HTTP Server
```bash
cd clients/web
python3 -m http.server 8080
```

#### Option B: Node.js HTTP Server
```bash
cd clients/web
npx http-server -p 8080
```

#### Option C: PHP Built-in Server
```bash
cd clients/web
php -S localhost:8080
```

### 4. Open in Browser

Navigate to: `http://localhost:8080`

## Usage Guide

### First Time Setup

1. **Login**
   - Enter your email to receive a magic link
   - Or use "Quick Dev Login" for development

2. **Grant Permissions**
   - Allow browser notifications when prompted
   - Voice announcements work automatically (no permission needed)

3. **Configure Settings** (Optional)
   - Click the ⚙️ settings icon
   - Adjust voice rate, volume, and notification preferences
   - Set quiet hours if desired

### Daily Use

1. **View Reminders**
   - Today's reminders are displayed automatically
   - Color-coded by status:
     - 🔵 Blue = Upcoming
     - 🟡 Yellow = Overdue
     - 🟢 Green = Completed

2. **Automatic Announcements**
   - Voice announcement plays when reminder is due
   - Browser notification appears simultaneously
   - Reminder card highlights briefly

3. **Take Action**
   - **✓ Taken**: Mark as completed
   - **⏰ Snooze**: Postpone for 10 minutes
   - **✗ Skip**: Mark as skipped

4. **Refresh**
   - Click 🔄 to manually refresh reminders
   - Auto-refresh happens every 10 seconds (configurable)

## Configuration

### Settings Panel

Access via the ⚙️ icon in the header.

#### Voice Settings
- **Enable Voice Announcements**: Toggle voice on/off
- **Voice Speed**: 0.1 (slow) to 2.0 (fast), default: 0.4
- **Voice Volume**: 0.0 (silent) to 1.0 (full), default: 1.0
- **Test Voice**: Preview current voice settings

#### Notification Settings
- **Enable Browser Notifications**: Toggle notifications on/off
- **Play Notification Sound**: Enable/disable notification sound
- **Check Interval**: How often to check for due reminders (5-60 seconds)
- **Request Permission**: Manually request notification permission

#### Quiet Hours
- **Enable Quiet Hours**: Disable announcements during specific times
- **Start Time**: When quiet hours begin (e.g., 22:00)
- **End Time**: When quiet hours end (e.g., 07:00)

#### API Settings
- **API Base URL**: Backend server URL (default: `http://localhost:3000`)

### Local Storage

Settings are persisted in browser local storage:
- `remindlySettings`: User preferences
- `authToken`: Authentication JWT token
- `apiBaseUrl`: Backend server URL

## How Voice Announcements Work

### Web Speech API

The web client uses the browser's built-in **Web Speech API** (`speechSynthesis`):

```javascript
const utterance = new SpeechSynthesisUtterance(reminderText);
utterance.lang = 'en-US';
utterance.rate = 0.4;  // Speed
utterance.volume = 1.0; // Volume
speechSynthesis.speak(utterance);
```

### Announcement Triggers

Voice announcements are triggered when:

1. **Reminder becomes due**: Within 5-minute grace period
2. **Periodic check detects due reminder**: Every 10 seconds (default)
3. **Not in quiet hours**: Respects quiet hours setting
4. **Voice enabled**: User has voice announcements enabled

### Deduplication

Each reminder is announced only once per session using an in-memory set:

```javascript
this.announcedReminders = new Set();
```

This prevents repeated announcements on each check cycle.

## API Integration

### Endpoints Used

- `GET /magic/request?email={email}` - Request magic link
- `GET /magic/dev_exchange` - Development login
- `GET /reminders/today` - Fetch today's reminders
- `POST /acknowledgements` - Mark reminder as taken/skipped
- `POST /acknowledgements/snooze` - Snooze reminder

### Authentication

All API requests include the JWT token in the Authorization header:

```javascript
headers: {
    'Authorization': `Bearer ${authToken}`,
    'Content-Type': 'application/json'
}
```

## Troubleshooting

### Voice Not Working

1. **Check browser support**: Open browser console and type `'speechSynthesis' in window`
2. **Check settings**: Ensure "Enable Voice Announcements" is checked
3. **Check quiet hours**: Verify you're not in quiet hours
4. **Test voice**: Use "Test Voice" button in settings
5. **Check browser permissions**: Some browsers require user interaction first

### Notifications Not Appearing

1. **Grant permission**: Click "Request Notification Permission" in settings
2. **Check browser settings**: Ensure notifications are allowed for the site
3. **Check quiet hours**: Verify you're not in quiet hours
4. **Check settings**: Ensure "Enable Browser Notifications" is checked

### Reminders Not Loading

1. **Check backend**: Ensure Rails server is running on correct port
2. **Check API URL**: Verify API Base URL in settings matches backend
3. **Check console**: Open browser DevTools console for error messages
4. **Check authentication**: Try logging out and back in

### CORS Issues

If you see CORS errors in the console, ensure your Rails backend has CORS configured:

```ruby
# config/initializers/cors.rb
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins '*'  # Or specify your web client URL
    resource '*',
      headers: :any,
      methods: [:get, :post, :put, :patch, :delete, :options, :head]
  end
end
```

## Development

### File Structure

```
clients/web/
├── index.html      # Main HTML structure
├── app.js          # Application logic & Web Speech API
├── styles.css      # Styling
└── README.md       # This file
```

### Key Classes

- **RemindlyApp**: Main application class
  - Authentication management
  - Settings persistence
  - Reminder fetching and rendering
  - Voice announcements via Web Speech API
  - Browser notifications
  - Periodic checking

### Extending Functionality

To add new features:

1. **Add UI elements** in `index.html`
2. **Add styles** in `styles.css`
3. **Add logic** in `app.js` RemindlyApp class
4. **Update settings** if needed

## Comparison with SwiftUI App

| Feature | SwiftUI (macOS) | Web Client |
|---------|----------------|------------|
| Voice Announcements | AVSpeechSynthesizer | Web Speech API |
| Notifications | UNUserNotificationCenter | Notification API |
| Storage | SwiftData | LocalStorage |
| Background Processing | Yes | Limited (tab must be open) |
| Offline Support | Full | Partial |
| Platform | macOS only | Cross-platform |

## Known Limitations

1. **Tab must be open**: Announcements only work when browser tab is active/open
2. **No background processing**: Unlike native apps, web apps can't run in background
3. **Voice quality**: Varies by browser and OS
4. **Notification persistence**: Some browsers auto-dismiss notifications after timeout

## Future Enhancements

- [ ] Service Worker for background notifications
- [ ] Progressive Web App (PWA) support
- [ ] Offline mode with IndexedDB
- [ ] Push notifications via web push
- [ ] Custom notification sounds
- [ ] Multiple voice options
- [ ] Reminder creation/editing UI
- [ ] Calendar view

## License

Part of the Remindly project.

## Support

For issues or questions, please refer to the main Remindly repository documentation.
