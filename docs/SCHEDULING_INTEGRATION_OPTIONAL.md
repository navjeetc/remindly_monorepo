# Scheduling Integration - Optional Feature

## Overview

The scheduling integration feature is **completely optional** and designed as an opt-in enhancement. Caregivers can continue using Remindly's task management without any external integrations.

---

## How It's Optional

### 1. **No Required Setup**
- Zero configuration needed to use tasks
- No API keys or external accounts required
- Works out of the box for manual task management

### 2. **Independent Task System**
```ruby
# Tasks work perfectly without any integration
Task.create!(
  senior: senior,
  created_by: caregiver,
  title: "Doctor Appointment",
  task_type: :appointment,
  scheduled_at: tomorrow_at_2pm,
  status: :pending
)
# ✅ Works perfectly - no integration needed
```

### 3. **Optional Association**
```ruby
# In Task model
belongs_to :scheduling_integration, optional: true
#                                    ^^^^^^^^^ Key word!
```

The `scheduling_integration_id` field can be `NULL` - it's only populated when a task is synced from an external platform.

### 4. **Separate Tables**
- `tasks` table exists independently
- `scheduling_integrations` table is separate
- No foreign key constraints forcing integration

---

## Usage Scenarios

### Scenario A: Manual Coordination (No Integration)
**Who:** Caregivers who prefer to coordinate among themselves

**What they do:**
- Create tasks manually in Remindly
- Assign tasks to each other
- Mark tasks complete
- Add comments and notes

**What they DON'T need:**
- Acuity Scheduling account
- Calendly account
- Any external scheduling platform
- API keys or credentials

**Database state:**
```ruby
task.scheduling_integration_id  # => nil
task.external_source            # => nil
task.external_id                # => nil
task.external_url               # => nil
```

### Scenario B: With External Integration (Optional)
**Who:** Caregivers who use Acuity/Calendly for client scheduling

**What they do:**
- Connect their Acuity/Calendly account (one-time setup)
- Appointments automatically sync as tasks
- Can still create manual tasks too
- Both types appear in unified task list

**Database state:**
```ruby
# Manual task
manual_task.scheduling_integration_id  # => nil
manual_task.external_source            # => nil

# Synced task
synced_task.scheduling_integration_id  # => 123
synced_task.external_source            # => "acuity"
synced_task.external_id                # => "456"
```

---

## UI/UX Considerations

### Settings Page
```
┌─────────────────────────────────────────────────┐
│ Scheduling Integrations (Optional)              │
├─────────────────────────────────────────────────┤
│                                                  │
│ ℹ️  Connect external scheduling platforms to    │
│    automatically sync appointments as tasks.    │
│    This is completely optional - you can        │
│    continue managing tasks manually.            │
│                                                  │
│ ┌─────────────────────────────────────────────┐ │
│ │ No integrations connected                   │ │
│ │                                             │ │
│ │ [+ Connect Acuity Scheduling]               │ │
│ │ [+ Connect Calendly]                        │ │
│ └─────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────┘
```

### Task List
```
┌─────────────────────────────────────────────────┐
│ Tasks                                            │
├─────────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────────┐ │
│ │ 🏥 Doctor Appointment                       │ │
│ │ Tomorrow at 2:00 PM                         │ │
│ │ Created manually                            │ │
│ └─────────────────────────────────────────────┘ │
│                                                  │
│ ┌─────────────────────────────────────────────┐ │
│ │ 🏥 Dentist Checkup         🔗 Acuity        │ │
│ │ Friday at 10:00 AM                          │ │
│ │ Synced from Acuity Scheduling               │ │
│ │ [View in Acuity]                            │ │
│ └─────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────┘
```

---

## Feature Flags (Future)

For even more control, you could add a feature flag:

```ruby
# config/settings.yml
features:
  scheduling_integrations:
    enabled: true  # Set to false to hide integration UI entirely
```

Then in controllers/views:
```ruby
# Only show integration settings if enabled
if Settings.features.scheduling_integrations.enabled
  render 'scheduling_integrations/index'
end
```

---

## Migration Path

### For Existing Users
1. **Nothing changes** - Existing tasks continue working
2. **New fields are nullable** - No data migration needed
3. **Opt-in when ready** - Connect integration at their convenience

### For New Users
1. **Start with manual tasks** - Full functionality from day one
2. **Discover integration later** - Optional enhancement
3. **No pressure** - Never required

---

## Database Schema Design

### Tasks Table
```sql
CREATE TABLE tasks (
  -- Core fields (required)
  id BIGINT PRIMARY KEY,
  senior_id BIGINT NOT NULL,
  created_by_id BIGINT NOT NULL,
  title VARCHAR NOT NULL,
  task_type INTEGER NOT NULL,
  status INTEGER NOT NULL,
  scheduled_at DATETIME NOT NULL,
  
  -- Optional fields for external sync
  scheduling_integration_id BIGINT,  -- NULL = manual task
  external_source VARCHAR,            -- NULL = manual task
  external_id VARCHAR,                -- NULL = manual task
  external_url VARCHAR,               -- NULL = manual task
  sync_metadata JSON,                 -- NULL = manual task
  
  FOREIGN KEY (scheduling_integration_id) 
    REFERENCES scheduling_integrations(id)
    ON DELETE SET NULL  -- If integration deleted, task remains
);
```

**Key points:**
- All external sync fields are nullable
- Foreign key uses `ON DELETE SET NULL` - tasks survive integration deletion
- No `NOT NULL` constraints on integration fields

---

## Code Examples

### Creating Manual Tasks (No Integration)
```ruby
# Works perfectly without any integration
Task.create!(
  senior: senior,
  created_by: caregiver,
  title: "Grocery Shopping",
  task_type: :errand,
  scheduled_at: Time.current + 2.hours,
  status: :pending,
  priority: :medium
  # No scheduling_integration_id needed!
)
```

### Querying Manual vs Synced Tasks
```ruby
# Get only manual tasks
Task.manually_created
# => SELECT * FROM tasks WHERE external_source IS NULL

# Get only synced tasks
Task.synced_from_external
# => SELECT * FROM tasks WHERE external_source IS NOT NULL

# Get all tasks (manual + synced)
Task.all
# => SELECT * FROM tasks
```

### Checking Task Source
```ruby
task = Task.find(123)

if task.external_appointment?
  puts "Synced from #{task.external_provider_name}"
  puts "View at: #{task.external_link}"
else
  puts "Created manually in Remindly"
end
```

---

## Benefits of Optional Design

### ✅ **Flexibility**
- Teams can adopt at their own pace
- No forced workflow changes
- Mix manual and synced tasks

### ✅ **No Vendor Lock-in**
- Not dependent on external services
- Can disconnect integration anytime
- Tasks remain accessible

### ✅ **Gradual Adoption**
- Start with manual tasks
- Add integration when needed
- Remove integration if not useful

### ✅ **Reduced Complexity**
- Simple onboarding (no integration setup required)
- Lower barrier to entry
- Less to learn initially

---

## Testing Optional Behavior

```ruby
# Test manual task creation
RSpec.describe Task, type: :model do
  it 'can be created without scheduling integration' do
    task = Task.create!(
      senior: senior,
      created_by: caregiver,
      title: "Test Task",
      task_type: :appointment,
      scheduled_at: 1.day.from_now,
      status: :pending
    )
    
    expect(task).to be_valid
    expect(task.scheduling_integration).to be_nil
    expect(task.external_appointment?).to be false
  end
  
  it 'can be created with scheduling integration' do
    integration = create(:scheduling_integration)
    
    task = Task.create!(
      senior: senior,
      created_by: caregiver,
      title: "Synced Task",
      task_type: :appointment,
      scheduled_at: 1.day.from_now,
      status: :pending,
      scheduling_integration: integration,
      external_source: 'acuity',
      external_id: '12345'
    )
    
    expect(task).to be_valid
    expect(task.scheduling_integration).to eq(integration)
    expect(task.external_appointment?).to be true
  end
end
```

---

## Documentation for Users

### Help Text
```
Q: Do I need to connect Acuity or Calendly?
A: No! The scheduling integration is completely optional. You can 
   create and manage tasks manually without any external accounts.

Q: What happens if I disconnect my integration?
A: Your synced tasks remain in Remindly. They just won't update 
   automatically anymore. You can still edit them manually.

Q: Can I use both manual and synced tasks?
A: Yes! You can create manual tasks and have synced tasks in the 
   same list. They work together seamlessly.

Q: Will this cost extra?
A: The Remindly integration is free. However, Acuity Scheduling 
   and Calendly have their own pricing plans if you choose to use them.
```

---

## Summary

The scheduling integration is designed as an **optional enhancement**, not a requirement:

- ✅ Tasks work perfectly without any integration
- ✅ No setup required for basic task management
- ✅ `scheduling_integration` is optional in database
- ✅ All external sync fields are nullable
- ✅ Can mix manual and synced tasks
- ✅ Can disconnect integration anytime
- ✅ Tasks survive integration deletion

**Bottom line:** Caregivers who are happy coordinating among themselves can completely ignore the scheduling integration feature and use Remindly's task management as-is.
