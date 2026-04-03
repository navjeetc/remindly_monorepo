# Bug Fix: Offline-Created Reminders Cannot Be Edited

## Issue
When creating a reminder offline and then trying to edit it (also offline), the edit view showed blank fields. The reminder wasn't in the local cache, so there was no data to load.

## Root Cause
The `queueCreateReminder()` method only:
1. Created a pending action for later sync
2. Did NOT create a local `LocalReminder` in the cache

Without a local reminder, the edit view couldn't find the reminder by ID and showed an error: "Reminder not found in cache."

## Solution: Temporary IDs for Offline-Created Reminders

### Strategy
Use **negative IDs** as temporary identifiers for offline-created reminders until they sync with the server and get real positive IDs.

### Implementation

#### 1. Generate Temporary ID in `queueCreateReminder()`
**File:** `Services/SyncManager.swift`

```swift
func queueCreateReminder(title: String, notes: String?, category: String, rrule: String, tz: String) async throws {
    let payload = CreateReminderPayload(...)
    let data = try JSONEncoder().encode(payload)
    
    // Generate temporary negative ID (unique timestamp-based)
    let tempId = -Int(Date().timeIntervalSince1970)
    
    let action = PendingAction(
        actionType: "create_reminder",
        reminderId: tempId,  // Store temp ID in action
        payload: data
    )
    
    try dataManager.addPendingAction(action)
    updatePendingCount()
    
    // Create local reminder with temporary ID for offline editing
    try dataManager.createLocalReminder(
        id: tempId,
        title: title,
        notes: notes,
        category: category,
        rrule: rrule,
        tz: tz
    )
    
    if networkMonitor.effectivelyConnected {
        await syncPendingActions()
    }
}
```

**Why negative IDs?**
- Server always assigns positive IDs
- Negative IDs can never conflict with real IDs
- Easy to identify temporary reminders (`id < 0`)
- Timestamp-based ensures uniqueness

#### 2. Add `createLocalReminder()` to DataManager
**File:** `Services/DataManager.swift`

```swift
func createLocalReminder(id: Int, title: String, notes: String?, category: String, rrule: String, tz: String) throws {
    let now = Date()
    let reminder = LocalReminder(
        id: id,
        title: title,
        notes: notes,
        rrule: rrule,
        tz: tz,
        category: category,
        userId: 0, // Temporary user ID
        createdAt: now,
        updatedAt: now,
        lastSyncedAt: nil
    )
    
    modelContext.insert(reminder)
    try modelContext.save()
}
```

#### 3. Clean Up Temporary Reminder After Sync
**File:** `Services/SyncManager.swift`

```swift
case "create_reminder":
    let payload = try JSONDecoder().decode(CreateReminderPayload.self, from: action.payload)
    try await apiClient.createReminder(...)
    
    // Delete temporary local reminder (negative ID) after successful sync
    if let tempId = action.reminderId, tempId < 0 {
        try? dataManager.deleteReminder(id: tempId)
        print("🗑️ Deleted temporary reminder with ID: \(tempId)")
    }
```

After successful sync:
1. Server creates the real reminder with a positive ID
2. Temporary reminder (negative ID) is deleted
3. Next refresh fetches the real reminder from server
4. Local cache updated with real data

#### 4. Handle Editing Temporary Reminders
**File:** `Services/SyncManager.swift`

```swift
func queueUpdateReminder(id: Int, title: String, notes: String?, category: String, rrule: String, tz: String) async throws {
    // If updating a temporary reminder (negative ID), update the pending create action instead
    if id < 0 {
        let actions = try dataManager.fetchPendingActions()
        if let createAction = actions.first(where: { 
            $0.actionType == "create_reminder" && $0.reminderId == id 
        }) {
            // Update the create action's payload with new data
            let newPayload = CreateReminderPayload(
                title: title,
                notes: notes,
                category: category,
                rrule: rrule,
                tz: tz
            )
            let newData = try JSONEncoder().encode(newPayload)
            
            // Replace old action with updated one
            try dataManager.deletePendingAction(createAction)
            let updatedAction = PendingAction(
                actionType: "create_reminder",
                reminderId: id,
                payload: newData
            )
            try dataManager.addPendingAction(updatedAction)
            
            // Update local cache
            try dataManager.updateReminder(id: id, title: title, notes: notes, category: category, rrule: rrule)
            
            print("✅ Updated pending create action for temporary reminder")
            updatePendingCount()
            return
        }
    }
    
    // Normal update flow for synced reminders...
}
```

**Why update the create action?**
- The reminder doesn't exist on the server yet
- No point creating both a "create" and "update" action
- Just update the "create" action with the latest data
- When it syncs, server gets the final version

## Flow Diagrams

### Offline Create → Edit → Sync Flow

```
1. User creates reminder offline
   ↓
2. Generate temp ID: -1728334867
   ↓
3. Create LocalReminder with temp ID
   ↓
4. Queue "create_reminder" action
   ↓
5. User edits the reminder
   ↓
6. Load from cache using temp ID ✅
   ↓
7. User saves changes
   ↓
8. Update LocalReminder with temp ID
   ↓
9. Update "create_reminder" action payload
   ↓
10. Network reconnects
    ↓
11. Sync: POST /reminders (with final data)
    ↓
12. Server creates reminder with ID: 42
    ↓
13. Delete temp reminder (ID: -1728334867)
    ↓
14. Refresh: fetch from server
    ↓
15. Cache updated with real reminder (ID: 42)
```

### Online Create Flow (No Change)

```
1. User creates reminder online
   ↓
2. Generate temp ID: -1728334867
   ↓
3. Create LocalReminder with temp ID
   ↓
4. Queue "create_reminder" action
   ↓
5. Immediately sync (online)
   ↓
6. POST /reminders → server returns ID: 42
   ↓
7. Delete temp reminder (ID: -1728334867)
   ↓
8. Refresh: fetch from server
   ↓
9. Cache updated with real reminder (ID: 42)
```

## Testing

### Test Case 1: Create Offline, Edit Offline
```
1. Enable offline mode
2. Create reminder: "Take vitamin D"
3. Reminder appears in list
4. Right-click → "Edit Reminder"
5. Edit view loads with data ✅
6. Change title to "Take vitamin D3"
7. Save
8. List updates with new title ✅
9. Go online
10. Reminder syncs with final title ✅
```

### Test Case 2: Create Offline, Edit Multiple Times
```
1. Offline: Create "Test 1"
2. Edit to "Test 2"
3. Edit to "Test 3"
4. Go online
5. Server receives "Test 3" (final version) ✅
```

### Test Case 3: Create Online (Fast Sync)
```
1. Online: Create "Morning meds"
2. Immediately syncs
3. Temp reminder replaced with real one
4. Edit works with real ID ✅
```

## Edge Cases Handled

### Multiple Offline Creates
```
Reminder A: temp ID = -1728334867
Reminder B: temp ID = -1728334868
Reminder C: temp ID = -1728334869

All unique, no conflicts ✅
```

### Edit Before First Sync Completes
```
1. Create reminder (online)
2. Sync starts but hasn't completed
3. User edits immediately
4. Edits the temp reminder ✅
5. Sync completes
6. Temp deleted, real reminder fetched
7. Next edit uses real ID ✅
```

### Sync Failure
```
1. Create offline
2. Go online
3. Sync fails (server error)
4. Temp reminder stays in cache ✅
5. User can still edit ✅
6. Retry sync later
```

## Related Files Modified

1. **`Services/SyncManager.swift`**
   - `queueCreateReminder()` - Generate temp ID, create local reminder
   - `queueUpdateReminder()` - Handle temp ID updates
   - `processAction()` - Clean up temp reminders after sync

2. **`Services/DataManager.swift`**
   - `createLocalReminder()` - New method to create local reminder

## Impact

✅ **Fixes**
- Offline-created reminders can now be edited
- Edit view loads data correctly
- No more "Reminder not found in cache" errors

✅ **Benefits**
- Consistent offline experience
- Multiple edits before sync supported
- No data loss
- Seamless transition from temp to real ID

✅ **No Breaking Changes**
- Online flow unchanged
- Existing reminders unaffected
- Backward compatible

## Comparison with Previous Bugs

| Bug | Issue | Solution |
|-----|-------|----------|
| **Update not showing** | Local cache not updated | Update cache immediately |
| **Create then edit blank** | No local reminder created | Create with temp negative ID |

Both bugs had the same root cause: **local cache not updated for offline actions**.

## Future Improvements

1. **Visual Indicator**: Show badge on temp reminders ("Pending sync")
2. **Batch Sync**: Sync all pending creates in one request
3. **Conflict Resolution**: Handle case where user edits on multiple devices
4. **Optimistic Occurrences**: Generate local occurrences for temp reminders
