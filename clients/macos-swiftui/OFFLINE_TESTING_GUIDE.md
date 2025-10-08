# Offline Testing Quick Guide

## 🚀 Quick Start

### Enable Offline Mode
Click the **network slash icon** (🌐❌) in the top-right corner of the app.
- Red icon = Offline mode enabled
- Gray icon = Online mode

### Visual Indicators
- **Orange "Offline" badge** appears in header when disconnected
- All actions still work, but are queued for later sync

---

## 🧪 5-Minute Test

### 1. Test Offline Acknowledgement (1 min)
```
1. Click network slash icon → goes red
2. Click "✓ Taken" on any reminder
3. Reminder disappears (marked as acknowledged)
4. Click network icon → goes gray (online)
5. Watch console: "✅ Synced action: acknowledge"
```

### 2. Test Offline Create (2 min)
```
1. Enable offline mode (red network icon)
2. Click "+" button
3. Create reminder:
   - Title: "Test Offline Reminder"
   - Category: Medication
   - Time: 2:00 PM
   - Recurrence: Daily
4. Click "Create Reminder"
5. Go back online
6. Wait for sync
7. Refresh → new reminder appears with occurrences
```

### 3. Test Offline Delete (1 min)
```
1. Enable offline mode
2. Right-click any reminder
3. Select "Delete Reminder"
4. Confirm deletion
5. Reminder disappears immediately
6. Go back online
7. Deletion syncs to server
```

### 4. Test Persistence (1 min)
```
1. Ensure you have some reminders
2. Enable offline mode
3. Quit app (Cmd+Q)
4. Relaunch app
5. Verify: All reminders still visible
6. Orange "Offline" badge shows
```

---

## 📊 What to Look For

### Console Output (Good Signs ✅)
```
✅ Cached X reminders
✅ Fetched X occurrences from API
📱 Loaded X occurrences from cache (offline)
📡 Network connected: WiFi
🔄 Syncing X pending actions
✅ Synced action: acknowledge
✅ Reminder created: [title]
```

### Console Output (Expected Warnings ⚠️)
```
⚠️ Cannot sync: offline
⚠️ Failed to cache reminders: [error]
```

### Console Output (Bad Signs ❌)
```
❌ Failed to sync action: [error]
❌ Sync error: [error]
⚠️ Action failed 3 times, skipping
```

---

## 🔍 Debug Panel

Click the **info icon** (ℹ️) in the header to see:
- Number of pending notifications
- List of scheduled notifications with times
- Refresh button to update

---

## 🐛 Common Issues

### Issue: "Offline" badge doesn't appear
**Fix:** Click the network slash icon to toggle offline mode

### Issue: Actions don't sync when going online
**Fix:** 
1. Check console for errors
2. Ensure backend is running (http://localhost:3000)
3. Try manual refresh (↻ icon)

### Issue: Reminders don't load offline
**Fix:**
1. Go online first
2. Wait for initial sync
3. Then test offline mode

### Issue: Duplicate reminders after sync
**Fix:** This shouldn't happen, but if it does:
1. Delete duplicates
2. Report bug with console logs

---

## 🎯 Advanced Testing

### Test Sync Queue
```
1. Enable offline mode
2. Perform 5 different actions:
   - Acknowledge 2 reminders
   - Create 1 reminder
   - Edit 1 reminder
   - Delete 1 reminder
3. Check pending count (should be 5)
4. Go online
5. Watch all 5 actions sync in order
6. Pending count returns to 0
```

### Test Retry Logic
```
1. Stop the backend server (Ctrl+C in terminal)
2. Enable offline mode
3. Acknowledge a reminder
4. Go online (but server still down)
5. Console shows: "❌ Failed to sync action"
6. Retry count increments
7. Start backend server
8. Action syncs successfully
```

### Test Network Interruption
```
1. Start with online mode
2. Acknowledge a reminder (syncs immediately)
3. Enable offline mode
4. Acknowledge another reminder (queued)
5. Go online
6. Second action syncs
7. Both reminders marked as acknowledged
```

---

## 📱 Real Network Testing

To test with actual network disconnection (not just the toggle):

### macOS WiFi Control
```bash
# Disable WiFi
networksetup -setairportpower en0 off

# Enable WiFi
networksetup -setairportpower en0 on
```

### Verify Network Status
```bash
# Check current status
networksetup -getairportpower en0

# Monitor network changes
log stream --predicate 'subsystem == "com.apple.network"' --level debug
```

---

## ✅ Success Criteria

After testing, you should be able to:
- [x] Use app fully offline
- [x] Create/edit/delete reminders offline
- [x] Acknowledge reminders offline
- [x] See queued actions sync when online
- [x] Quit and relaunch app offline
- [x] No data loss at any point
- [x] Clear visual feedback (offline badge)

---

## 🚨 When to Report Issues

Report if you see:
1. Data loss (reminders disappear)
2. Duplicate reminders after sync
3. Actions fail to sync after 3 retries
4. App crashes when offline
5. Sync never completes (hangs)
6. Incorrect offline indicator state

Include in bug report:
- Steps to reproduce
- Console logs (copy/paste)
- Screenshot of UI state
- Network mode (online/offline)
- Number of pending actions
