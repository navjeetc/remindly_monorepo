# Remindly Web Client - Quick Start Guide

Get up and running with voice-enabled reminders in 3 minutes!

## 🚀 Quick Start

### 1. Start the Backend (Terminal 1)

```bash
cd backend
rails server
```

The backend should start on `http://localhost:3000`

### 2. Start the Web Client (Terminal 2)

Choose one of these options:

**Option A: Python (easiest)**
```bash
cd clients/web
python3 -m http.server 8080
```

**Option B: Node.js**
```bash
cd clients/web
npx http-server -p 8080
```

**Option C: npm (with live reload)**
```bash
cd clients/web
npm install
npm run dev
```

### 3. Open in Browser

Navigate to: **http://localhost:8080**

### 4. Login

Click **"Quick Dev Login"** button for instant access (development mode)

### 5. Grant Permissions

When prompted:
- ✅ **Allow** browser notifications
- Voice announcements work automatically (no permission needed)

### 6. Test It Out!

1. You should see today's reminders listed
2. When a reminder is due, you'll hear a voice announcement
3. A browser notification will also appear
4. Try the action buttons: ✓ Taken, ⏰ Snooze, ✗ Skip

## 🎤 Testing Voice Announcements

1. Click the **⚙️ Settings** icon
2. Click **"Test Voice"** button
3. You should hear: "This is a test of the voice announcement system"

If you don't hear anything:
- Check your system volume
- Ensure voice announcements are enabled in settings
- Try a different browser (Chrome/Edge work best)

## ⚙️ Adjusting Settings

Click the **⚙️** icon to customize:

- **Voice Speed**: Slower (0.1) to Faster (2.0)
- **Voice Volume**: Quiet (0.0) to Loud (1.0)
- **Check Interval**: How often to check for due reminders
- **Quiet Hours**: Disable announcements at night

## 🔔 How Announcements Work

1. **Automatic Checking**: Every 10 seconds (default), the app checks for due reminders
2. **Due Detection**: If a reminder's time is within 5 minutes, it's announced
3. **Voice + Notification**: Both play simultaneously
4. **One-Time Only**: Each reminder is announced once per session

## 📱 Mobile Usage

The web client works on mobile browsers too!

1. Open `http://YOUR_COMPUTER_IP:8080` on your phone
2. Add to home screen for app-like experience
3. Voice announcements work on iOS Safari and Android Chrome

## 🐛 Troubleshooting

### No Voice?
- Open browser console (F12) and check for errors
- Verify `'speechSynthesis' in window` returns `true`
- Try clicking "Test Voice" in settings

### No Notifications?
- Check browser notification permissions
- Click "Request Notification Permission" in settings
- Some browsers block notifications on `localhost` - try `127.0.0.1` instead

### Can't Connect to Backend?
- Ensure Rails server is running on port 3000
- Check the API Base URL in settings matches your backend
- Look for CORS errors in browser console

### Reminders Not Showing?
- Try the "Quick Dev Login" button
- Check that you have reminders created in the system
- Click the 🔄 refresh button

## 🎯 Next Steps

- **Create Reminders**: Use the SwiftUI app or Rails console to create test reminders
- **Customize Settings**: Adjust voice and notification preferences
- **Set Quiet Hours**: Configure do-not-disturb times
- **Test on Mobile**: Try it on your phone or tablet

## 💡 Pro Tips

1. **Keep Tab Open**: Announcements only work when the browser tab is open
2. **Pin the Tab**: Pin the tab in your browser to keep it always available
3. **Full Screen**: Use F11 for a distraction-free reminder display
4. **Multiple Devices**: Open on multiple devices for redundancy

## 📚 Full Documentation

See [README.md](./README.md) for complete documentation including:
- Detailed feature list
- API integration details
- Advanced configuration
- Development guide

## 🆘 Need Help?

1. Check the [README.md](./README.md) troubleshooting section
2. Open browser DevTools console (F12) to see error messages
3. Verify backend is running: `curl http://localhost:3000/up`

---

**Enjoy your voice-enabled reminders! 🔊✨**
