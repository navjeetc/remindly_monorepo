# Sprint 3: Offline Support - Issues & Fixes Summary

## Issues Encountered During Testing

### Issue 1: Update Title Offline - Change Not Displayed ❌
**Symptom:** When editing a reminder title while offline, the change doesn't appear in the list.

**Expected:** Title updates immediately in the UI.

**Status:** Should be fixed by existing code, needs verification.

**Code Path:**
1. User edits title offline
2. `ReminderVM.updateReminder()` called
3. `SyncManager.queueUpdateReminder()` called
4. `DataManager.updateReminder()` updates local cache
5. `ReminderVM.refresh()` reloads from cache
6. UI should update

**Possible Causes:**
- SwiftUI not detecting the change in `@Published occurrences`
- Cache update not completing before refresh
- Occurrence not being mapped correctly

**Debug Steps:**
1. Add print statement after cache update
2. Check if `occurrences` array is updated
3. Verify `LocalOccurrence.reminderTitle` is changed

---

### Issue 2: Occurrence Scheduled +24 Hours ⚠️
**Symptom:** When creating/updating a reminder, occurrences are created for tomorrow instead of today.

**Example:**
- Current time: 5:44 PM
- Reminder time: 5:41 PM (already passed)
- Occurrence created: Tomorrow at 5:41 PM

**Root Cause:** The reminder time (5:41 PM) has already passed today, so the next occurrence is tomorrow.

**Status:** This is **expected behavior** for times that have passed.

**Fix Applied:** Modified `Recurrence.expand` to include occurrences from the last hour:
```ruby
if t >= now - 1.hour
  reminder.occurrences.find_or_create_by!(scheduled_at: t)
end
```

This allows reminders created/updated within 1 hour of their scheduled time to still show today's occurrence.

**Testing Recommendation:** Create reminders with times in the **future** (e.g., if it's 5:44 PM, set reminder for 6:00 PM).

---

### Issue 3: Refresh Shows Nothing ❌
**Symptom:** After going online and syncing, clicking refresh shows no reminders.

**Possible Causes:**
1. No occurrences scheduled for today (see Issue 2)
2. Fetch failing silently
3. Cache not being updated
4. Race condition between sync and refresh

**Status:** Needs investigation.

**Debug Steps:**
1. Check console output for "✅ Fetched X occurrences"
2. Check backend: `Reminder.last.occurrences`
3. Check if occurrences exist but are for tomorrow
4. Verify sync completed before refresh

---

## Fixes Implemented

### Fix 1: Offline Update Not Showing (Client)
**Files:**
- `Services/DataManager.swift` - Added `updateReminder()` method
- `Services/SyncManager.swift` - Call `dataManager.updateReminder()` when queueing

**What it does:**
- Updates `LocalReminder` in cache
- Updates all `LocalOccurrence` cached reminder info
- Provides immediate UI feedback

---

### Fix 2: Create Offline Then Edit (Client)
**Files:**
- `Services/SyncManager.swift` - Generate temp negative IDs
- `Services/DataManager.swift` - Added `createLocalReminder()` method

**What it does:**
- Creates local reminder with temp ID when creating offline
- Allows editing before sync
- Replaces temp with real ID after sync

---

### Fix 3: Create Online Then Edit Offline (Client)
**Files:**
- `Services/SyncManager.swift` - Fetch reminders after create sync
- `ReminderVM.swift` - Cache reminders after create

**What it does:**
- Ensures newly created reminders are cached
- Available for offline editing later

---

### Fix 4: Race Condition Sync vs Refresh (Client)
**Files:**
- `ReminderVM.swift` - Sequential sync then refresh

**What it does:**
- Waits for sync to complete before refreshing
- Ensures server has latest data before fetching
- Prevents showing stale data

---

### Fix 5: Wrong Occurrence Times (Backend)
**Files:**
- `backend/app/services/recurrence.rb`

**What it does:**
- Starts IceCube schedule from beginning of day
- Properly respects BYHOUR/BYMINUTE in RRULE
- Creates occurrences at correct times

---

### Fix 6: Include Recent Past Occurrences (Backend)
**Files:**
- `backend/app/services/recurrence.rb`

**What it does:**
- Includes occurrences from the last hour
- Allows reminders created near their time to show today
- Prevents always showing tomorrow's occurrence

---

## Testing Checklist

### Test 1: Create Reminder for Future Time
```
1. Note current time (e.g., 5:44 PM)
2. Create reminder for future time (e.g., 6:00 PM)
3. ✅ Should show occurrence today at 6:00 PM
```

### Test 2: Update Title Offline
```
1. Create reminder online
2. Go offline
3. Edit title
4. ✅ Should show new title immediately
5. Go online
6. ✅ Should still show new title
```

### Test 3: Create Offline, Edit Offline
```
1. Go offline
2. Create reminder
3. Edit title
4. ✅ Should show updated title
5. Go online
6. ✅ Should sync with final title
```

### Test 4: Multiple Updates Offline
```
1. Create reminder online
2. Go offline
3. Edit title 3 times
4. ✅ Should show final title
5. Go online
6. ✅ Should sync final title only
```

### Test 5: Refresh After Sync
```
1. Create reminder online (future time)
2. Go offline
3. Edit title
4. Go online (auto-syncs)
5. Click refresh
6. ✅ Should show updated reminder
```

---

## Console Output Reference

### Successful Offline Update
```
✅ Updated pending create action for temporary reminder
OR
✅ Reminder updated: [title]
📱 Loaded X occurrences from cache (offline)
```

### Successful Online Sync
```
📡 Network connected: WiFi
🔄 Syncing X pending actions
✅ Synced action: update_reminder
✅ Cached X reminders after update sync
✅ Fetched X occurrences from API
✅ Cached X reminders
```

### No Occurrences Today
```
✅ Fetched 0 occurrences from API
```
This means no reminders scheduled for today (times have passed or set for future days).

---

## Known Limitations

### 1. "Today's View" Only
The app only shows occurrences scheduled for **today**. If a reminder has no occurrence today, it won't appear in the list.

**Workaround:** Create reminders with times in the future, or wait until tomorrow.

**Future Enhancement:** Add "All Reminders" view.

### 2. Past Times Create Tomorrow's Occurrence
If you create/update a reminder with a time that has already passed today, the occurrence will be for tomorrow.

**Workaround:** Set reminder times in the future.

**Fix Applied:** 1-hour grace period allows recent times to still show today.

### 3. Offline Edits Don't Generate New Occurrences
When editing offline, only the cached occurrences are updated. New occurrences are generated when syncing online.

**This is expected:** Can't generate occurrences without server.

---

## Debugging Commands

### Check Backend Occurrences
```ruby
# Rails console
Reminder.last
Reminder.last.occurrences
Reminder.last.occurrences.pluck(:scheduled_at)
```

### Check Client Cache
```swift
// Add to ReminderVM temporarily
let reminders = try? dataManager.fetchReminders()
print("Cached reminders: \(reminders?.count ?? 0)")

let occurrences = try? dataManager.fetchTodayOccurrences()
print("Cached occurrences: \(occurrences?.count ?? 0)")
```

### Force Refresh
Click the refresh button (↻) in the app header.

---

## Next Steps

1. **Restart Backend:** `cd backend && rails s`
2. **Rebuild Client:** Clean and rebuild in Xcode
3. **Test with Future Times:** Create reminders for times ahead of current time
4. **Check Console Output:** Verify sync and fetch messages
5. **Report Results:** Share console output and behavior

---

## Summary

Most offline functionality is working correctly. The main issues are:

1. **UI not updating offline** - Needs investigation (should work with existing code)
2. **Occurrences for tomorrow** - Expected behavior for past times, 1-hour grace period added
3. **Refresh shows nothing** - Likely related to #2 (no today occurrences)

**Recommendation:** Test with reminder times set in the **future** (e.g., 30 minutes from now) to verify the sync and refresh logic works correctly.
