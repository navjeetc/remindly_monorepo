# Test Plan v0.4.0 - Priority Features Release

**Release Date:** January 9, 2026  
**Branch:** feature/priority-enhancements  
**Features:** Recurring Tasks, Open-Ended Tasks, Blocking Unavailable Times

---

## Pre-Deployment Checklist

- [ ] Run migrations on production database
- [ ] Verify all assets compiled successfully
- [ ] Check production logs for errors after deployment
- [ ] Verify version number displays correctly in UI

---

## Test Environment Setup

### Test Users Required
- **Senior User:** senior@example.com (or create new)
- **Caregiver User:** caregiver@example.com (or create new)
- **Link:** Ensure caregiver is linked to senior

### Test Data Needed
- At least 2-3 existing tasks for the senior
- Access to both senior and caregiver dashboards

---

## Feature 1: Recurring Tasks

### Test Case 1.1: Create Daily Recurring Task
**Objective:** Verify daily recurring tasks are created and expanded correctly

**Steps:**
1. Log in as caregiver
2. Navigate to senior's tasks page
3. Click "New Task"
4. Fill in:
   - Title: "Daily Medication"
   - Task Type: "Medication"
   - Priority: "High"
   - Scheduled Date/Time: Tomorrow at 9:00 AM
   - Duration: 15 minutes
5. Scroll to "Recurrence" section
6. Select "Repeat: Daily"
7. Set time to 09:00
8. Click "Create Task"

**Expected Results:**
- ✅ Task is created successfully
- ✅ Preview shows "Every day at 09:00"
- ✅ Multiple task instances are created for next 30 days
- ✅ All instances show in tasks list
- ✅ Each instance has same title, type, priority

**Pass/Fail:** ______

---

### Test Case 1.2: Create Weekly Recurring Task
**Objective:** Verify weekly recurring tasks with specific days

**Steps:**
1. Click "New Task"
2. Fill in:
   - Title: "Physical Therapy"
   - Task Type: "Appointment"
   - Priority: "Medium"
3. Uncheck "open-ended" if checked
4. In Recurrence section:
   - Select "Repeat: Weekly"
   - Check: Monday, Wednesday, Friday
   - Set time to 14:00
5. Click "Create Task"

**Expected Results:**
- ✅ Task created successfully
- ✅ Preview shows "Weekly on Mon, Wed, Fri at 14:00"
- ✅ Task instances only appear on Mon/Wed/Fri
- ✅ No instances on Tue/Thu/Sat/Sun

**Pass/Fail:** ______

---

### Test Case 1.3: Create Monthly Recurring Task
**Objective:** Verify monthly recurring tasks

**Steps:**
1. Click "New Task"
2. Fill in:
   - Title: "Doctor Appointment"
   - Task Type: "Appointment"
3. In Recurrence section:
   - Select "Repeat: Monthly"
   - Set day to: 15
   - Set time to 10:00
4. Click "Create Task"

**Expected Results:**
- ✅ Task created successfully
- ✅ Preview shows "Monthly on day 15 at 10:00"
- ✅ Task instances appear on 15th of each month

**Pass/Fail:** ______

---

### Test Case 1.4: Edit Recurring Task Template
**Objective:** Verify editing a recurring task regenerates instances

**Steps:**
1. Find a recurring task (has 🔄 badge)
2. Click "Edit"
3. Change the time from 09:00 to 10:00
4. Click "Update Task"
5. View task list

**Expected Results:**
- ✅ Task updated successfully
- ✅ All future instances show new time (10:00)
- ✅ Past/completed instances unchanged

**Pass/Fail:** ______

---

### Test Case 1.5: Complete Recurring Task Instance
**Objective:** Verify completing one instance doesn't affect others

**Steps:**
1. Find a recurring task instance
2. Click on it to view details
3. Click "Mark as Complete"
4. Return to task list

**Expected Results:**
- ✅ Only that specific instance marked complete
- ✅ Other instances remain pending
- ✅ Template task still shows as recurring

**Pass/Fail:** ______

---

## Feature 2: Open-Ended Tasks

### Test Case 2.1: Create Open-Ended Task
**Objective:** Verify open-ended tasks can be created without dates

**Steps:**
1. Click "New Task"
2. Fill in:
   - Title: "Grocery Shopping"
   - Task Type: "Errand"
   - Priority: "Low"
3. Check "📅 Make this an open-ended task (no specific date)"
4. Verify date field is hidden
5. Click "Create Task"

**Expected Results:**
- ✅ Task created successfully
- ✅ Task appears in "Open-Ended Tasks" section (purple highlight)
- ✅ No scheduled date shown
- ✅ Badge shows "Open-ended (no specific date)"

**Pass/Fail:** ______

---

### Test Case 2.2: Convert Open-Ended to Scheduled
**Objective:** Verify converting open-ended task to scheduled

**Steps:**
1. Find an open-ended task
2. Click "Edit"
3. Uncheck "Make this an open-ended task"
4. Verify date field appears with tomorrow at 9 AM pre-filled
5. Change time if desired
6. Click "Update Task"

**Expected Results:**
- ✅ Task updated successfully
- ✅ Task moves from "Open-Ended" section to scheduled list
- ✅ Shows scheduled date/time
- ✅ Purple badge removed

**Pass/Fail:** ______

---

### Test Case 2.3: Convert Scheduled to Open-Ended
**Objective:** Verify converting scheduled task to open-ended

**Steps:**
1. Find a scheduled task
2. Click "Edit"
3. Check "Make this an open-ended task"
4. Verify date field is hidden
5. Click "Update Task"

**Expected Results:**
- ✅ Task updated successfully
- ✅ Task moves to "Open-Ended Tasks" section
- ✅ No scheduled date shown
- ✅ Purple badge appears

**Pass/Fail:** ______

---

### Test Case 2.4: Assign Open-Ended Task
**Objective:** Verify open-ended tasks can be assigned

**Steps:**
1. Find an open-ended task
2. Click on it to view details
3. Click "Assign to Me" (or assign to another caregiver)
4. Check notifications

**Expected Results:**
- ✅ Task assigned successfully
- ✅ Notification sent (no date mentioned in message)
- ✅ Task shows as assigned
- ✅ Still appears in open-ended section

**Pass/Fail:** ______

---

### Test Case 2.5: View Open-Ended Tasks on Senior Dashboard
**Objective:** Verify seniors can see open-ended tasks if visible_to_senior is checked

**Steps:**
1. Create/edit an open-ended task
2. Ensure "Show this task to senior on their dashboard" is checked
3. Log in as senior
4. View dashboard

**Expected Results:**
- ✅ Open-ended task appears on senior dashboard
- ✅ Shows "Open-ended" badge
- ✅ No date/time displayed

**Pass/Fail:** ______

---

### Test Case 2.6: Filter Open-Ended Tasks
**Objective:** Verify filter works for open-ended tasks

**Steps:**
1. Go to tasks list
2. In "View" dropdown, select "Open-Ended"
3. View filtered results

**Expected Results:**
- ✅ Only open-ended tasks shown
- ✅ Scheduled tasks hidden
- ✅ Filter can be cleared

**Pass/Fail:** ______

---

## Feature 3: Blocking Unavailable Times

### Test Case 3.1: Create One-Time Time Block
**Objective:** Verify creating a single blocked time period

**Steps:**
1. Go to tasks page
2. Click "🚫 Blocked Times" button
3. Click "+ New Time Block"
4. Fill in:
   - Reason: "Doctor Appointment"
   - Start Time: Tomorrow at 2:00 PM
   - End Time: Tomorrow at 3:30 PM
   - Leave "Recurring" unchecked
5. Click "Create Time Block"

**Expected Results:**
- ✅ Time block created successfully
- ✅ Appears in blocked times list
- ✅ Shows date, time range, and reason

**Pass/Fail:** ______

---

### Test Case 3.2: Create Recurring Time Block (Sleep Hours)
**Objective:** Verify recurring time blocks work correctly

**Steps:**
1. Click "+ New Time Block"
2. Fill in:
   - Reason: "Sleep Time"
   - Start Time: Today at 10:00 PM
   - End Time: Tomorrow at 7:00 AM
   - Check "🔄 Make this a recurring block"
   - Pattern: "Every Night"
   - Ensure "Active" is checked
3. Click "Create Time Block"

**Expected Results:**
- ✅ Time block created successfully
- ✅ Shows purple "🔄 Recurring" badge
- ✅ Shows pattern "Every Night"

**Pass/Fail:** ______

---

### Test Case 3.3: Task Validation - Conflict Detection
**Objective:** Verify tasks cannot be scheduled during blocked times

**Steps:**
1. Go to tasks page
2. Click "New Task"
3. Fill in task details
4. Uncheck "open-ended"
5. Set scheduled time to 11:00 PM (during sleep block from 3.2)
6. Click "Create Task"

**Expected Results:**
- ✅ Task creation fails
- ✅ Error message displayed: "Scheduled at conflicts with blocked time: Sleep Time (10:00 PM - 07:00 AM)"
- ✅ Form remains filled (not cleared)
- ✅ User can adjust time and retry

**Pass/Fail:** ______

---

### Test Case 3.4: Task Validation - Successful Outside Block
**Objective:** Verify tasks can be scheduled outside blocked times

**Steps:**
1. Using same form from 3.3
2. Change scheduled time to 8:00 AM (after sleep block ends)
3. Click "Create Task"

**Expected Results:**
- ✅ Task created successfully
- ✅ No error messages
- ✅ Task appears in list at 8:00 AM

**Pass/Fail:** ______

---

### Test Case 3.5: Edit Time Block
**Objective:** Verify time blocks can be edited

**Steps:**
1. Go to "🚫 Blocked Times"
2. Find a time block
3. Click "Edit"
4. Change the reason or times
5. Click "Update Time Block"

**Expected Results:**
- ✅ Time block updated successfully
- ✅ Changes reflected in list
- ✅ Task validation uses new times

**Pass/Fail:** ______

---

### Test Case 3.6: Deactivate Time Block
**Objective:** Verify time blocks can be temporarily disabled

**Steps:**
1. Edit a time block
2. Uncheck "✅ Active"
3. Click "Update Time Block"
4. Try to create a task during that time

**Expected Results:**
- ✅ Time block updated
- ✅ Task can now be scheduled during that time (no conflict)
- ✅ Block still appears in list (not deleted)

**Pass/Fail:** ______

---

### Test Case 3.7: Delete Time Block
**Objective:** Verify time blocks can be deleted

**Steps:**
1. Go to "🚫 Blocked Times"
2. Find a time block
3. Click "Delete"
4. Confirm deletion

**Expected Results:**
- ✅ Time block deleted successfully
- ✅ Removed from list
- ✅ Tasks can now be scheduled during that time

**Pass/Fail:** ______

---

### Test Case 3.8: Recurring Block Patterns
**Objective:** Verify different recurring patterns work

**Steps:**
1. Create time blocks with each pattern:
   - Daily
   - Weekdays (Mon-Fri)
   - Weekends (Sat-Sun)
   - Weekly
2. Try scheduling tasks on different days

**Expected Results:**
- ✅ Daily: Blocks every day
- ✅ Weekdays: Only blocks Mon-Fri
- ✅ Weekends: Only blocks Sat-Sun
- ✅ Weekly: Blocks same day each week

**Pass/Fail:** ______

---

### Test Case 3.9: Overlap Prevention
**Objective:** Verify overlapping time blocks are prevented

**Steps:**
1. Create a time block: 2:00 PM - 4:00 PM
2. Try to create another block: 3:00 PM - 5:00 PM (overlaps)
3. Attempt to save

**Expected Results:**
- ✅ Error message: "This time block overlaps with an existing block"
- ✅ Second block not created
- ✅ First block remains

**Pass/Fail:** ______

---

## Integration Tests

### Test Case 4.1: Recurring Task + Time Block Interaction
**Objective:** Verify recurring tasks respect time blocks

**Steps:**
1. Create a recurring daily task at 10:00 PM
2. Create a time block for sleep (10:00 PM - 7:00 AM)
3. Observe behavior

**Expected Results:**
- ✅ Error shown when creating task during blocked time
- ✅ Must adjust task time to avoid block

**Pass/Fail:** ______

---

### Test Case 4.2: Open-Ended Task + Time Block
**Objective:** Verify open-ended tasks bypass time block validation

**Steps:**
1. Create an open-ended task (no scheduled time)
2. Verify it can be created even with time blocks present

**Expected Results:**
- ✅ Open-ended task created successfully
- ✅ No time block validation (since no scheduled_at)

**Pass/Fail:** ______

---

### Test Case 4.3: Convert Open-Ended to Scheduled During Block
**Objective:** Verify validation when converting open-ended to scheduled

**Steps:**
1. Have a time block: 10:00 PM - 7:00 AM
2. Edit an open-ended task
3. Uncheck "open-ended"
4. Set time to 11:00 PM (during block)
5. Try to save

**Expected Results:**
- ✅ Error message about blocked time
- ✅ Cannot save until time adjusted

**Pass/Fail:** ______

---

## UI/UX Tests

### Test Case 5.1: Mobile Responsiveness
**Objective:** Verify all new features work on mobile

**Steps:**
1. Access site on mobile device or resize browser
2. Test all new forms and lists

**Expected Results:**
- ✅ Forms are usable on mobile
- ✅ Buttons are tappable
- ✅ No horizontal scrolling
- ✅ Text is readable

**Pass/Fail:** ______

---

### Test Case 5.2: Error Message Clarity
**Objective:** Verify error messages are clear and helpful

**Steps:**
1. Trigger various errors (blocked time, overlapping blocks, etc.)
2. Read error messages

**Expected Results:**
- ✅ Messages are clear and specific
- ✅ Include relevant details (times, reasons)
- ✅ Suggest how to fix the issue

**Pass/Fail:** ______

---

### Test Case 5.3: Navigation Flow
**Objective:** Verify navigation between features is intuitive

**Steps:**
1. Navigate: Dashboard → Tasks → Blocked Times → Back to Tasks
2. Create task → View task → Edit task → Back to list

**Expected Results:**
- ✅ All navigation links work
- ✅ Back buttons return to correct page
- ✅ No broken links

**Pass/Fail:** ______

---

## Performance Tests

### Test Case 6.1: Large Number of Recurring Tasks
**Objective:** Verify performance with many recurring task instances

**Steps:**
1. Create 3-4 daily recurring tasks
2. Wait for expansion (30 days = ~90-120 instances)
3. Load tasks page
4. Measure page load time

**Expected Results:**
- ✅ Page loads in < 3 seconds
- ✅ All tasks display correctly
- ✅ No timeouts or errors

**Pass/Fail:** ______

---

### Test Case 6.2: Multiple Time Blocks
**Objective:** Verify performance with many time blocks

**Steps:**
1. Create 10+ time blocks
2. Try to create a task
3. Measure validation time

**Expected Results:**
- ✅ Validation completes quickly (< 1 second)
- ✅ No noticeable lag
- ✅ Correct conflict detection

**Pass/Fail:** ______

---

## Edge Cases

### Test Case 7.1: Task Spanning Midnight
**Objective:** Verify tasks that cross midnight work with time blocks

**Steps:**
1. Create time block: 11:00 PM - 1:00 AM (next day)
2. Create task at 11:30 PM with 2-hour duration

**Expected Results:**
- ✅ Conflict detected correctly
- ✅ Error message accurate

**Pass/Fail:** ______

---

### Test Case 7.2: Zero-Duration Task
**Objective:** Verify tasks without duration use default (1 hour)

**Steps:**
1. Create task without specifying duration
2. Schedule during a time block

**Expected Results:**
- ✅ Uses 1-hour default for validation
- ✅ Conflict detected if overlaps

**Pass/Fail:** ______

---

### Test Case 7.3: Past Date Time Block
**Objective:** Verify time blocks in the past don't affect new tasks

**Steps:**
1. Create time block for yesterday
2. Create task for today at same time

**Expected Results:**
- ✅ No conflict (past block doesn't affect future)
- ✅ Task created successfully

**Pass/Fail:** ______

---

## Regression Tests

### Test Case 8.1: Existing Tasks Unaffected
**Objective:** Verify existing tasks still work correctly

**Steps:**
1. View existing tasks created before this release
2. Edit an existing task
3. Complete an existing task

**Expected Results:**
- ✅ All existing tasks display correctly
- ✅ Can edit without issues
- ✅ Can complete normally

**Pass/Fail:** ______

---

### Test Case 8.2: Existing Reminders Unaffected
**Objective:** Verify reminder functionality unchanged

**Steps:**
1. View reminders
2. Acknowledge a reminder
3. Create a new reminder

**Expected Results:**
- ✅ Reminders work as before
- ✅ No errors or issues
- ✅ Recurrence service still works for reminders

**Pass/Fail:** ______

---

## Browser Compatibility

Test all features in:
- [ ] Chrome (latest)
- [ ] Firefox (latest)
- [ ] Safari (latest)
- [ ] Edge (latest)
- [ ] Mobile Safari (iOS)
- [ ] Mobile Chrome (Android)

---

## Post-Deployment Verification

### Immediate Checks (within 1 hour)
- [ ] Check production logs for errors
- [ ] Verify database migrations ran successfully
- [ ] Test login flow works
- [ ] Create one test task to verify basic functionality

### 24-Hour Checks
- [ ] Monitor error rates in logs
- [ ] Check for any user-reported issues
- [ ] Verify recurring tasks are expanding correctly
- [ ] Check time block validations are working

### 1-Week Checks
- [ ] Review usage analytics
- [ ] Gather user feedback
- [ ] Identify any edge cases not covered in testing
- [ ] Plan any necessary hotfixes

---

## Rollback Plan

If critical issues are found:

1. **Immediate:** Revert to previous version
   ```bash
   cd backend
   kamal rollback
   ```

2. **Database:** Rollback migrations if needed
   ```bash
   rails db:rollback STEP=2
   ```

3. **Communication:** Notify users of temporary downtime

4. **Investigation:** Identify root cause before re-deploying

---

## Sign-Off

**Tester Name:** ___________________________  
**Date:** ___________________________  
**Overall Result:** PASS / FAIL  

**Notes:**
_____________________________________________
_____________________________________________
_____________________________________________

**Approved for Production:** YES / NO  
**Approver:** ___________________________  
**Date:** ___________________________
