# Future Features & Enhancements

This document tracks potential features and enhancements for future development of Remindly.

## Priority Features

### 1. Recurring Tasks ✅ **COMPLETED**
**Description:** Ability to set tasks to repeat automatically on a schedule.

**Status:** ✅ Implemented

**Implementation:**
- ✅ User-friendly UI with dropdown selector (Daily/Weekly/Monthly)
- ✅ Pattern-specific options (interval, day selection, day of month)
- ✅ Time picker with live preview
- ✅ Auto-generates RRULE using iCalendar format
- ✅ Reuses existing Recurrence service from Reminders
- ✅ Automatically expands into task instances for next 30 days
- ✅ Parent-child relationship (template → instances)

**Completed Features:**
- Daily recurrence with configurable interval
- Weekly recurrence with day selection (Sun-Sat)
- Monthly recurrence with day of month
- Live preview showing human-readable pattern
- Auto-expansion on task create/update

**Files Modified:**
- `backend/app/models/task.rb` - Added recurrence associations and methods
- `backend/app/services/recurrence.rb` - Extended to handle tasks
- `backend/app/controllers/tasks_controller.rb` - Auto-expansion logic
- `backend/app/views/tasks/_form.html.erb` - User-friendly recurrence UI
- `backend/db/migrate/*` - Added rrule, tz, start_time, parent_task_id fields

---

### 2. Open-ended Tasks ✅ **COMPLETED**
**Description:** Create tasks without specifying a date/time, allowing caregivers to self-assign based on availability.

**Status:** ✅ Implemented

**Implementation:**
- ✅ Made scheduled_at optional in tasks table
- ✅ Easy checkbox toggle in task form
- ✅ Auto-hides date field when marked as open-ended
- ✅ Smart default (tomorrow at 9 AM) when converting to scheduled
- ✅ Purple badge display throughout UI
- ✅ Separate section on tasks index showing open-ended tasks
- ✅ All nil checks in place for scheduled_at across views

**Completed Features:**
- Checkbox toggle: "Make this an open-ended task (no specific date)"
- Open-ended tasks displayed in purple-highlighted section
- Filter option to view all open-ended tasks
- Assignment notifications handle open-ended tasks
- Senior dashboard displays open-ended tasks correctly

**Files Modified:**
- `backend/app/models/task.rb` - Added open_ended? method and scopes
- `backend/app/controllers/tasks_controller.rb` - Handle nil scheduled_at
- `backend/app/views/tasks/_form.html.erb` - Checkbox toggle with JavaScript
- `backend/app/views/tasks/index.html.erb` - Open-ended tasks section
- `backend/app/views/tasks/show.html.erb` - Handle nil scheduled_at
- `backend/app/views/dashboard/index.html.erb` - Handle nil scheduled_at
- `backend/db/migrate/*` - Made scheduled_at nullable

---

### 3. Blocking Unavailable Times ⏳ **PENDING**
**Description:** Enable blocking out time periods when the care receiver is unavailable.

**Use Cases:**
- Late-night hours (e.g., 10 PM - 7 AM)
- Meal times
- Scheduled appointments or activities
- Rest periods

**Technical Considerations:**
- Time block creation and management
- Validation to prevent task scheduling during blocked times
- Recurring blocked times (e.g., every night)
- Override capability for emergencies

---

### 4. Hierarchy of Caregivers ⏳ **PENDING**
**Description:** Implement role-based permissions with a main caregiver having elevated privileges.

**Roles:**
- **Main Caregiver:** Full permissions including:
  - Setting blocked times
  - Managing other helpers
  - Modifying all tasks
  - Access to all settings
- **Helper/Secondary Caregiver:** Limited permissions:
  - View tasks
  - Complete assigned tasks
  - Add tasks (with approval?)

**Technical Considerations:**
- Role-based access control (RBAC) system
- Permission matrix
- Role assignment and transfer
- Audit logging for sensitive actions

---

### 5. Task List Visibility for Care Receivers ✅ **COMPLETED**
**Description:** Care receivers should be able to view their upcoming tasks, not just receive reminders.

**Status:** ✅ Implemented and Enhanced

**Implementation:**
- ✅ Dashboard view of upcoming tasks (30-day window)
- ✅ Task details (title, description, time, priority, assigned caregiver)
- ✅ Visibility controls via `visible_to_senior` flag (defaults to true)
- ✅ Informational note for caregivers explaining visibility criteria
- ✅ Available on both web dashboard and voice reminder clients

**Completed Features:**
- Dashboard view showing tasks for next 30 days
- Task filtering by status, type, priority
- Task details with scheduling information
- Visibility toggle per task

**Future Enhancements (Optional):**
- Calendar view option
- Completed task history view
- Enhanced filtering options
- Mobile-optimized view

**Files Modified:**
- `backend/app/controllers/dashboard_controller.rb` - Extended visibility window to 30 days
- `backend/app/views/dashboard/index.html.erb` - Updated heading
- `backend/app/views/tasks/index.html.erb` - Added visibility criteria info for caregivers

---

## Secondary Features

### 6. Bulk Task Addition
**Description:** Quickly add multiple tasks at once.

**Potential Approaches:**
- CSV import
- Template-based task creation
- Multi-task form
- Copy/duplicate existing tasks

**Priority:** Low (nice to have, not urgent)

---

### 7. In-App Communication
**Description:** Chat function for caregivers to coordinate within the app.

**Features:**
- Direct messaging between caregivers
- Group chat for all caregivers
- Task-specific comments/notes
- Read receipts

**Technical Considerations:**
- Real-time messaging infrastructure (WebSockets?)
- Message persistence
- Notification system
- Privacy and data retention

---

## Future Integrations

### 8. Smart Speaker Integration
**Description:** Integration with voice assistants like Amazon Alexa or Google Home.

**Use Cases:**
- Voice-activated task reminders
- Hands-free task completion confirmation
- Voice queries for upcoming tasks
- Accessibility for users with limited mobility

**Technical Considerations:**
- Alexa Skills / Google Actions development
- Voice authentication
- Privacy and security concerns
- API design for voice interfaces

---

### 9. Specialized Reminder Devices
**Description:** Integration with portable, dedicated reminder devices for care receivers with limited tech skills.

**Potential Devices:**
- Simple button-based devices
- Audio-only reminder systems
- Large-display tablets with simplified UI
- Wearable devices

**Technical Considerations:**
- Device communication protocols
- Battery life and charging
- Durability and ease of use
- Cost and accessibility

---

## Implementation Notes

When prioritizing these features, consider:
1. **User Impact:** Which features solve the most pressing user needs?
2. **Technical Complexity:** What's the development effort required?
3. **Dependencies:** Which features build on each other?
4. **Market Differentiation:** Which features set Remindly apart?

## Suggested Roadmap Phases

**Phase 6:** Core Task Management Enhancements
- Recurring Tasks
- Blocking Unavailable Times
- Task List Visibility for Care Receivers

**Phase 7:** Caregiver Collaboration
- Hierarchy of Caregivers
- Open-ended Tasks
- In-App Communication

**Phase 8:** Advanced Features & Integrations
- Bulk Task Addition
- Smart Speaker Integration
- Specialized Device Integration

---

*Last Updated: January 9, 2025*
