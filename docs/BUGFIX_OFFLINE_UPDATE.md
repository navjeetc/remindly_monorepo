# Bug Fix: Offline Reminder Update Not Showing in UI

## Issue
When updating a reminder title while offline, the console showed "Reminder updated: [new title]" but the UI continued to display the old title in the reminder list.

## Root Cause
The `SyncManager.queueUpdateReminder()` method was only:
1. Creating a pending action for later sync
2. NOT updating the local SwiftData cache

This meant the UI, which loads from the local cache, never saw the updated title until the app went online and synced with the server.

## Solution

### 1. Added `updateReminder()` method to DataManager
**File:** `Services/DataManager.swift`

```swift
func updateReminder(id: Int, title: String, notes: String?, category: String, rrule: String) throws {
    // Update the LocalReminder
    let descriptor = FetchDescriptor<LocalReminder>(
        predicate: #Predicate { r in r.id == id }
    )
    
    if let reminder = try modelContext.fetch(descriptor).first {
        reminder.title = title
        reminder.notes = notes
        reminder.category = category
        reminder.rrule = rrule
        reminder.updatedAt = Date()
        
        // CRITICAL: Also update all associated occurrences' cached reminder info
        let occurrenceDescriptor = FetchDescriptor<LocalOccurrence>(
            predicate: #Predicate { o in o.reminderId == id }
        )
        
        let occurrences = try modelContext.fetch(occurrenceDescriptor)
        for occurrence in occurrences {
            occurrence.reminderTitle = title
            occurrence.reminderNotes = notes
            occurrence.reminderCategory = category
        }
        
        try modelContext.save()
    }
}
```

**Why update occurrences?**
The `LocalOccurrence` model caches reminder info (`reminderTitle`, `reminderNotes`, `reminderCategory`) for offline display. Without updating these, the UI would still show old data even though the reminder was updated.

### 2. Updated `queueUpdateReminder()` to update local cache
**File:** `Services/SyncManager.swift`

```swift
func queueUpdateReminder(id: Int, title: String, notes: String?, category: String, rrule: String, tz: String) async throws {
    // ... create payload and action ...
    
    try dataManager.addPendingAction(action)
    updatePendingCount()
    
    // NEW: Update local cache immediately for offline UI
    try dataManager.updateReminder(id: id, title: title, notes: notes, category: category, rrule: rrule)
    
    if networkMonitor.effectivelyConnected {
        await syncPendingActions()
    }
}
```

## Flow After Fix

### Offline Update Flow
1. User edits reminder title: "drink water" → "drink juice 123"
2. `ReminderVM.updateReminder()` calls `SyncManager.queueUpdateReminder()`
3. SyncManager:
   - Queues action for later sync ✅
   - **Updates local cache immediately** ✅
4. `ReminderVM.refresh()` reloads from cache
5. UI shows new title: "drink juice 123" ✅

### Online Sync Flow
1. Network reconnects
2. SyncManager processes pending actions
3. Sends update to server
4. Server regenerates occurrences
5. App fetches fresh data from server
6. Local cache updated with server data (conflict resolution: server wins)

## Testing

### Before Fix
```
1. Enable offline mode
2. Edit reminder title
3. Save
Result: ❌ UI shows old title
Console: ✅ "Reminder updated: [new title]"
```

### After Fix
```
1. Enable offline mode
2. Edit reminder title
3. Save
Result: ✅ UI shows new title immediately
Console: ✅ "Reminder updated: [new title]"
```

## Related Files Modified
- `Services/DataManager.swift` - Added `updateReminder()` method
- `Services/SyncManager.swift` - Updated `queueUpdateReminder()` to call `dataManager.updateReminder()`

## Impact
- ✅ Fixes offline update UI bug
- ✅ Provides immediate user feedback
- ✅ Maintains consistency between cache and UI
- ✅ No breaking changes to existing functionality
- ✅ Works for both offline and online modes

## Similar Pattern
This same pattern is already used for:
- **Delete**: `queueDeleteReminder()` deletes locally immediately
- **Acknowledge**: `queueAcknowledge()` updates occurrence status locally

Now **Update** follows the same optimistic UI pattern.
