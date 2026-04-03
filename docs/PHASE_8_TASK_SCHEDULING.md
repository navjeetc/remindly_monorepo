# Phase 8: Shared Task & Appointment Scheduling

## Overview
Enable caregivers to create, assign, and track shared tasks and appointments for seniors (doctor visits, grocery errands, etc.), allowing multiple caregivers to coordinate care responsibilities.

---

## Goals
1. **Task Management** - Create tasks beyond medication reminders (appointments, errands, activities)
2. **Caregiver Coordination** - Assign tasks to specific caregivers or leave unassigned
3. **Availability Tracking** - See who's available and divide the workload
4. **Status Updates** - Mark tasks as done, in-progress, or cancelled
5. **Notifications** - Alert assigned caregivers about upcoming tasks

---

## Database Schema

### New Models

#### Task
```ruby
class Task < ApplicationRecord
  belongs_to :senior, class_name: "User"
  belongs_to :assigned_to, class_name: "User", optional: true
  belongs_to :created_by, class_name: "User"
  
  enum :task_type, { 
    appointment: 0,      # Doctor, dentist, specialist
    errand: 1,          # Grocery, pharmacy, shopping
    activity: 2,        # Social event, exercise class
    household: 3,       # Cleaning, maintenance
    transportation: 4,  # Ride to location
    other: 5
  }
  
  enum :status, {
    pending: 0,
    assigned: 1,
    in_progress: 2,
    completed: 3,
    cancelled: 4
  }
  
  enum :priority, {
    low: 0,
    medium: 1,
    high: 2,
    urgent: 3
  }
  
  validates :title, :task_type, :scheduled_at, presence: true
end
```

**Fields:**
- `title` (string, required) - "Doctor appointment", "Grocery shopping"
- `description` (text) - Additional details
- `task_type` (enum) - Type of task
- `status` (enum) - Current status
- `priority` (enum) - Urgency level
- `scheduled_at` (datetime) - When task should happen
- `duration_minutes` (integer) - Estimated duration
- `location` (string) - Where (address, clinic name, etc.)
- `notes` (text) - Additional notes or instructions
- `completed_at` (datetime) - When marked complete
- `senior_id` (foreign key) - Who the task is for
- `assigned_to_id` (foreign key, optional) - Which caregiver is assigned
- `created_by_id` (foreign key) - Who created the task

#### TaskComment
```ruby
class TaskComment < ApplicationRecord
  belongs_to :task
  belongs_to :user
  
  validates :content, presence: true
end
```

**Fields:**
- `task_id` (foreign key)
- `user_id` (foreign key) - Who posted the comment
- `content` (text) - Comment text
- `created_at` (datetime)

#### CaregiverAvailability
```ruby
class CaregiverAvailability < ApplicationRecord
  belongs_to :caregiver, class_name: "User"
  
  validates :date, :start_time, :end_time, presence: true
end
```

**Fields:**
- `caregiver_id` (foreign key)
- `date` (date) - Which day
- `start_time` (time) - Available from
- `end_time` (time) - Available until
- `notes` (text) - Optional notes about availability

---

## Features

### 8.1 Task Creation & Management

#### Task Creation Form
- **Title** (required) - Brief description
- **Type** - Dropdown (Appointment, Errand, Activity, etc.)
- **Priority** - Low/Medium/High/Urgent
- **Date & Time** - When task should happen
- **Duration** - Estimated time needed
- **Location** - Where (optional)
- **Description** - Detailed notes
- **Assign to** - Dropdown of linked caregivers or "Unassigned"

#### Task List Views
1. **Calendar View** - Monthly/weekly calendar showing all tasks
2. **List View** - Filterable list with sorting
3. **My Tasks** - Tasks assigned to current caregiver
4. **Unassigned** - Tasks needing assignment
5. **Upcoming** - Next 7 days
6. **Completed** - Historical tasks

#### Filters & Search
- Filter by task type
- Filter by status
- Filter by assigned caregiver
- Filter by priority
- Search by title/description
- Date range filter

### 8.2 Task Assignment & Coordination

#### Assignment Options
- **Assign to specific caregiver** - Select from linked caregivers
- **Leave unassigned** - Any caregiver can claim
- **Self-assign** - Caregiver takes ownership
- **Reassign** - Transfer to another caregiver

#### Availability Calendar
- Caregivers set their availability
- Visual calendar showing who's available when
- Conflict detection (overlapping tasks)
- Suggested assignments based on availability

#### Load Balancing
- Dashboard showing task distribution per caregiver
- "Tasks this week" count for each caregiver
- Visual indicators for overloaded caregivers
- Suggestions to redistribute tasks

### 8.3 Task Status & Updates

#### Status Workflow
```
Pending → Assigned → In Progress → Completed
                  ↓
              Cancelled
```

#### Status Actions
- **Pending** - Initial state, waiting for assignment
- **Assigned** - Caregiver assigned, not started
- **In Progress** - Caregiver started the task
- **Completed** - Task finished (with completion notes)
- **Cancelled** - Task no longer needed

#### Completion Details
- Mark complete with timestamp
- Add completion notes (optional)
- Upload receipt/photo (future enhancement)
- Rate difficulty (optional feedback)

### 8.4 Notifications & Reminders

#### Email Notifications
- **Task assigned** - "You've been assigned: Doctor appointment"
- **Task due soon** - "Reminder: Grocery shopping in 2 hours"
- **Task overdue** - "Overdue: Pharmacy pickup"
- **Task completed** - "John marked 'Doctor appointment' as complete"
- **Task reassigned** - "Task transferred to you from Sarah"
- **New comment** - "New comment on 'Grocery shopping'"

#### In-App Notifications
- Badge count for pending tasks
- Notification bell with recent updates
- Toast notifications for real-time updates

#### Reminder Schedule
- 24 hours before task
- 2 hours before task
- At task time (if not started)
- 1 hour after task time (if not completed)

### 8.5 Collaboration Features

#### Task Comments
- Add comments to tasks
- @mention other caregivers
- Attach files (future)
- Comment history with timestamps

#### Activity Log
- Who created the task
- Assignment changes
- Status updates
- Comments added
- Completion details

#### Shared Notes
- Task-specific notes visible to all caregivers
- Senior preferences (e.g., "Prefers morning appointments")
- Important information (e.g., "Bring insurance card")

---

## UI/UX Design

### Dashboard Enhancements

#### Caregiver Dashboard
```
┌─────────────────────────────────────────────────┐
│ Dashboard for senior@example.com                │
├─────────────────────────────────────────────────┤
│ [Reminders] [Tasks] [Calendar] [Settings]       │
├─────────────────────────────────────────────────┤
│                                                  │
│ My Tasks (3)                    [+ New Task]    │
│ ┌─────────────────────────────────────────────┐ │
│ │ 🏥 Doctor Appointment          HIGH          │ │
│ │ Today at 2:00 PM • 60 min                   │ │
│ │ Location: Main St Clinic                    │ │
│ │ [Start] [Complete] [Reassign]               │ │
│ └─────────────────────────────────────────────┘ │
│                                                  │
│ Unassigned Tasks (2)                            │
│ ┌─────────────────────────────────────────────┐ │
│ │ 🛒 Grocery Shopping            MEDIUM        │ │
│ │ Tomorrow at 10:00 AM • 90 min               │ │
│ │ [Assign to Me] [Assign to...]               │ │
│ └─────────────────────────────────────────────┘ │
│                                                  │
│ Team Availability                               │
│ ┌─────────────────────────────────────────────┐ │
│ │ John: Available 9am-5pm                     │ │
│ │ Sarah: Available 2pm-8pm                    │ │
│ │ You: Set availability →                     │ │
│ └─────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────┘
```

#### Calendar View
- Monthly/weekly view
- Color-coded by task type
- Click to view/edit task
- Drag-and-drop to reschedule
- Filter by caregiver

#### Task Detail Modal
```
┌─────────────────────────────────────────────────┐
│ Doctor Appointment                    [Edit] [×]│
├─────────────────────────────────────────────────┤
│ Type: Appointment          Priority: HIGH       │
│ Status: Assigned           Assigned to: John    │
│                                                  │
│ When: Today, Oct 16 at 2:00 PM                 │
│ Duration: 60 minutes                            │
│ Location: Main St Clinic, 123 Main St          │
│                                                  │
│ Description:                                    │
│ Annual checkup with Dr. Smith                   │
│ Bring insurance card and medication list        │
│                                                  │
│ Comments (2):                                   │
│ Sarah: Don't forget to ask about blood pressure│
│ John: I'll pick up prescriptions after         │
│                                                  │
│ [Add Comment]                                   │
│                                                  │
│ [Mark In Progress] [Complete] [Cancel]         │
└─────────────────────────────────────────────────┘
```

### Mobile Responsive
- Stack cards vertically on mobile
- Swipe actions for quick status updates
- Bottom sheet for task details
- Push notifications for mobile

---

## API Endpoints

### Tasks
```ruby
# List tasks
GET /api/tasks
  ?senior_id=1
  &status=pending
  &assigned_to=2
  &task_type=appointment
  &start_date=2025-10-16
  &end_date=2025-10-23

# Create task
POST /api/tasks
{
  "task": {
    "senior_id": 1,
    "title": "Doctor Appointment",
    "task_type": "appointment",
    "priority": "high",
    "scheduled_at": "2025-10-16T14:00:00Z",
    "duration_minutes": 60,
    "location": "Main St Clinic",
    "description": "Annual checkup",
    "assigned_to_id": 2
  }
}

# Update task
PATCH /api/tasks/:id
{
  "task": {
    "status": "completed",
    "completed_at": "2025-10-16T15:30:00Z",
    "notes": "Went well, got new prescription"
  }
}

# Assign task
POST /api/tasks/:id/assign
{
  "assigned_to_id": 2
}

# Self-assign task
POST /api/tasks/:id/claim

# Delete task
DELETE /api/tasks/:id
```

### Comments
```ruby
# Add comment
POST /api/tasks/:task_id/comments
{
  "comment": {
    "content": "Don't forget to bring insurance card"
  }
}

# List comments
GET /api/tasks/:task_id/comments
```

### Availability
```ruby
# Set availability
POST /api/availability
{
  "availability": {
    "date": "2025-10-16",
    "start_time": "09:00",
    "end_time": "17:00",
    "notes": "Available all day"
  }
}

# Get team availability
GET /api/availability
  ?senior_id=1
  &start_date=2025-10-16
  &end_date=2025-10-23
```

---

## Implementation Plan

### Sprint 1: Core Task Management (5 days)

#### Day 1-2: Database & Models
- [ ] Create migration for tasks table
- [ ] Create Task model with validations
- [ ] Create TaskComment model
- [ ] Add associations to User and CaregiverLink
- [ ] Seed sample tasks

#### Day 3-4: API Endpoints
- [ ] TasksController with CRUD actions
- [ ] Filtering and search logic
- [ ] Assignment endpoints
- [ ] Comments endpoints
- [ ] Error handling and validations

#### Day 5: Testing
- [ ] Model tests
- [ ] Controller tests
- [ ] API integration tests

### Sprint 2: UI & Dashboard (5 days)

#### Day 1-2: Task List & Forms
- [ ] Tasks index page with filters
- [ ] Task creation form
- [ ] Task edit form
- [ ] Task detail modal
- [ ] Status update buttons

#### Day 3-4: Calendar View
- [ ] Calendar component (FullCalendar.js or similar)
- [ ] Task display on calendar
- [ ] Click to view task
- [ ] Filter by caregiver/type
- [ ] Responsive design

#### Day 5: Polish & UX
- [ ] Loading states
- [ ] Empty states
- [ ] Error messages
- [ ] Success notifications
- [ ] Mobile responsive

### Sprint 3: Coordination Features (4 days)

#### Day 1-2: Availability System
- [ ] CaregiverAvailability model
- [ ] Availability form
- [ ] Team availability view
- [ ] Conflict detection
- [ ] Suggested assignments

#### Day 3: Comments & Activity
- [ ] Comment system
- [ ] Activity log
- [ ] Real-time updates (optional)

#### Day 4: Load Balancing
- [ ] Task distribution dashboard
- [ ] Visual indicators
- [ ] Redistribution suggestions

### Sprint 4: Notifications (3 days)

#### Day 1-2: Email Notifications
- [ ] TaskMailer with templates
- [ ] Assignment notifications
- [ ] Reminder notifications
- [ ] Completion notifications
- [ ] Background jobs for scheduling

#### Day 3: In-App Notifications
- [ ] Notification model
- [ ] Badge counts
- [ ] Notification center
- [ ] Mark as read

---

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Task completion rate | ≥ 90% | Completed / Total tasks |
| Average assignment time | ≤ 2 hours | Time from creation to assignment |
| Caregiver engagement | ≥ 80% | Caregivers using tasks weekly |
| Load distribution | ≤ 30% variance | Standard deviation of tasks per caregiver |
| On-time completion | ≥ 85% | Completed within scheduled time |

---

## Future Enhancements

### Phase 8.5: Advanced Features
- **Recurring tasks** - Weekly grocery shopping, monthly checkups
- **Templates** - Pre-defined task templates
- **File attachments** - Upload receipts, photos, documents
- **Task dependencies** - "Complete A before starting B"
- **Reminders via SMS** - Text message notifications
- **Integration with calendar apps** - Google Calendar, Apple Calendar
- **Expense tracking** - Track costs for errands
- **Mileage tracking** - For transportation tasks
- **Task analytics** - Reports on completion rates, time spent
- **Mobile app** - Native iOS/Android apps

### Integration Opportunities
- **Google Maps** - Directions to task locations
- **Pharmacy APIs** - Prescription refill reminders
- **Healthcare portals** - Sync with doctor appointments
- **Grocery delivery** - Integration with Instacart, etc.

---

## Technical Considerations

### Performance
- Index on `senior_id`, `assigned_to_id`, `scheduled_at`, `status`
- Pagination for task lists (50 per page)
- Eager loading for associations
- Cache team availability

### Security
- Verify caregiver has access to senior before showing tasks
- Audit log for task changes
- Permission checks for assignment/completion
- Rate limiting on task creation

### Data Integrity
- Validate scheduled_at is in the future (for new tasks)
- Prevent assignment to non-linked caregivers
- Cascade delete tasks when senior is deleted
- Soft delete for audit trail (optional)

---

## Migration Path

### For Existing Users
1. Introduce tasks gradually (beta feature flag)
2. Provide tutorial/walkthrough
3. Offer task templates for common scenarios
4. Import existing appointments from reminders (optional)

### Backwards Compatibility
- Reminders continue to work as-is
- Tasks are separate feature
- No breaking changes to existing APIs

---

## Documentation Needed

- [ ] User guide for caregivers
- [ ] API documentation
- [ ] Setup instructions
- [ ] Best practices guide
- [ ] FAQ

---

## Estimated Timeline

**Total: 17 days (3.5 weeks)**

- Sprint 1: Core Task Management (5 days)
- Sprint 2: UI & Dashboard (5 days)
- Sprint 3: Coordination Features (4 days)
- Sprint 4: Notifications (3 days)

---

## Dependencies

- Phase 7 (Caregiver Dashboard) must be complete ✅
- Email service (MagicMailer) already exists ✅
- Background jobs (Sidekiq or similar) needed for notifications
- Calendar library (FullCalendar.js or similar)

---

**Status:** Planning Phase  
**Priority:** High  
**Complexity:** Medium-High  
**Value:** High - Addresses major caregiver coordination pain point

---

**Next Steps:**
1. Review and approve Phase 8 plan
2. Create feature branch: `phase-8-task-scheduling`
3. Begin Sprint 1: Core Task Management
