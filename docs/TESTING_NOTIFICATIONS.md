# Testing Notification System

## Pre-Test Checklist

1. **Backend Running**: Ensure Rails server is running on `localhost:3000`
2. **Test Data**: Ensure there are reminders in the database with upcoming times
3. **System Settings**: Check macOS notification settings allow notifications

## Test Scenarios

### Test 1: Permission Request
**Steps:**
1. Launch the app for the first time
2. Should see permission dialog for notifications

**Expected:**
- Permission dialog appears
- After granting, app continues to load reminders

**Status:** [ ]

---

### Test 2: Notification Scheduling
**Steps:**
1. Launch app
2. Click the info (ℹ️) button to show debug panel
3. Check "Pending notifications" count

**Expected:**
- Should show 3 notifications per pending reminder:
  - `voice-{id}` (2 min before)
  - `reminder-{id}` (at scheduled time)
  - `repeat-{id}` (5 min after)
- Debug panel shows scheduled times

**Status:** [ ]

---

### Test 3: Voice Prompt (Manual)
**Steps:**
1. Wait for a voice prompt notification (2 min before scheduled time)
2. Or manually trigger by calling `NotificationManager.shared.playVoicePrompt("Test")`

**Expected:**
- Voice speaks the reminder title
- Rate is slow (0.4) for seniors
- Clear and audible

**Status:** [ ]

---

### Test 4: Main Notification
**Steps:**
1. Wait for scheduled time OR create a reminder 1 minute in the future
2. Observe notification banner

**Expected:**
- Notification appears with:
  - Title: Reminder title
  - Body: Notes or category
  - Three action buttons: ✓ Taken, ⏰ Snooze, ✗ Skip
- Critical sound plays

**Status:** [ ]

---

### Test 5: Notification Actions
**Steps:**
1. When notification appears, click "✓ Taken"

**Expected:**
- App opens (if not already open)
- Reminder marked as acknowledged
- Notification disappears
- Repeat notification cancelled
- Backend receives acknowledgement

**Status:** [ ]

---

### Test 6: Snooze Functionality
**Steps:**
1. When notification appears, click "⏰ Snooze"

**Expected:**
- Original notifications cancelled
- New notification scheduled for 10 minutes later
- Message shows "Reminder snoozed for 10 minutes"

**Status:** [ ]

---

### Test 7: Skip Action
**Steps:**
1. When notification appears, click "✗ Skip"

**Expected:**
- Reminder marked as skipped
- All notifications for that occurrence cancelled
- Backend receives skip acknowledgement

**Status:** [ ]

---

### Test 8: Repeat Notification
**Steps:**
1. Let a notification appear without taking action
2. Wait 5 minutes

**Expected:**
- Repeat notification appears with "⏰ Reminder: {title}"
- Body says "You haven't acknowledged this reminder yet"
- Only shows Taken and Skip actions (no snooze)

**Status:** [ ]

---

### Test 9: Notification Tap (No Action)
**Steps:**
1. Click on notification banner (not action buttons)

**Expected:**
- App opens and focuses
- Shows reminder list
- Reminder still pending

**Status:** [ ]

---

### Test 10: Multiple Reminders
**Steps:**
1. Have 3+ reminders scheduled
2. Check debug panel

**Expected:**
- All reminders have notifications scheduled
- No duplicate notifications
- Times are correct

**Status:** [ ]

---

### Test 11: Refresh Rescheduling
**Steps:**
1. Note pending notification count
2. Click refresh button
3. Check debug panel again

**Expected:**
- Old notifications cleared
- New notifications scheduled
- Count matches number of pending reminders × 3

**Status:** [ ]

---

### Test 12: Background Behavior
**Steps:**
1. Schedule a notification for 2 minutes from now
2. Minimize or hide the app
3. Wait for notification

**Expected:**
- Notification still appears
- Voice prompt plays (if enabled)
- Actions work from background

**Status:** [ ]

---

## Quick Test Setup

To test quickly without waiting, you can:

1. **Create test reminders with near-future times:**
   ```bash
   # In Rails console
   rails c
   
   user = User.first
   reminder = user.reminders.create!(
     title: "Test Reminder",
     notes: "This is a test",
     category: "medication",
     rrule: "FREQ=DAILY",
     tz: "America/New_York"
   )
   
   # Create occurrence for 2 minutes from now
   Occurrence.create!(
     reminder: reminder,
     scheduled_at: 2.minutes.from_now,
     status: "pending"
   )
   ```

2. **Or modify existing occurrences:**
   ```ruby
   Occurrence.where(status: "pending").first.update(scheduled_at: 1.minute.from_now)
   ```

---

## Known Issues to Watch For

- [ ] Notifications not appearing → Check System Settings > Notifications > Remindly
- [ ] Voice not playing → Check volume, audio output device
- [ ] Actions not working → Check console for errors
- [ ] Duplicate notifications → Check if refresh clears old ones
- [ ] Wrong times → Check timezone handling

---

## Debug Commands

### Check pending notifications in console:
```swift
Task {
    let pending = await NotificationManager.shared.getPendingNotifications()
    print("Pending: \(pending.count)")
    for req in pending {
        print("- \(req.identifier): \(req.content.title)")
    }
}
```

### Manually trigger voice:
```swift
NotificationManager.shared.playVoicePrompt("Take your medication")
```

### Cancel all notifications:
```swift
NotificationManager.shared.cancelAllNotifications()
```

---

## Success Criteria

✅ All 12 test scenarios pass
✅ No crashes or errors in console
✅ Notifications appear at correct times
✅ Actions work reliably
✅ Voice prompts are clear and audible
✅ Backend receives acknowledgements correctly
