# Future Features & Enhancements

This document tracks potential features and enhancements for future development of Remindly.

## Priority Features

### 1. Recurring Tasks
**Description:** Ability to set tasks to repeat automatically on a schedule.

**Use Cases:**
- Weekly tasks (e.g., laundry every Thursday)
- Daily routines (e.g., medication reminders)
- Monthly appointments (e.g., doctor visits)

**Technical Considerations:**
- Recurrence patterns (daily, weekly, monthly, custom)
- End date or occurrence count options
- Handling of skipped/missed occurrences
- Database schema for recurrence rules

---

### 2. Open-ended Tasks
**Description:** Create tasks without specifying a date/time, allowing caregivers to self-assign based on availability.

**Use Cases:**
- Flexible tasks that don't have strict deadlines
- Tasks that any available caregiver can complete
- Non-time-sensitive activities

**Technical Considerations:**
- Task pool/queue system
- Self-assignment mechanism
- Visibility of unassigned tasks
- Notification strategy for available tasks

---

### 3. Blocking Unavailable Times
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

### 4. Hierarchy of Caregivers
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
