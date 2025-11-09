# Scheduling Integration Plan

## Overview

Enable integration with third-party scheduling platforms (Acuity Scheduling, Calendly, etc.) to streamline appointment booking for seniors and caregivers. The system will support multiple providers through a provider-agnostic abstraction layer.

## Architecture Decision: Enhanced Task Model

**Key Decision:** Instead of creating separate models for external appointments, we enhance the existing `Task` model to support external scheduling integrations. This approach:

- ✅ **Avoids data duplication** - Task already has all scheduling fields (scheduled_at, duration_minutes, location, etc.)
- ✅ **Maintains single source of truth** - All scheduled events in one place
- ✅ **Simplifies queries** - No complex joins needed
- ✅ **Improves UX** - Unified calendar view for all tasks/appointments
- ✅ **Follows SRP** - Task = "scheduled event" regardless of source (manual, Acuity, Calendly)
- ✅ **Reduces complexity** - Fewer models, less code to maintain

**What we add:**
- `SchedulingIntegration` model (stores credentials and settings)
- 5 new fields to `Task` model (external_source, external_id, external_url, sync_metadata, scheduling_integration_id)

**What we avoid:**
- ❌ Separate `ScheduledAppointment` model
- ❌ Complex task ↔ appointment synchronization logic
- ❌ Duplicate data storage
- ❌ Split UI views

---

## Goals

1. **Multi-Provider Support** - Abstract interface supporting multiple scheduling platforms
2. **HIPAA Compliance** - Prioritize healthcare-compliant providers (Acuity)
3. **Two-Way Sync** - Appointments ↔ Tasks synchronization
4. **Webhook Integration** - Real-time updates from scheduling platforms
5. **Simple Setup** - Easy connection flow for caregivers
6. **Secure Credentials** - Encrypted API key storage

---

## Architecture

### Provider Abstraction Layer

```ruby
# app/services/scheduling/base_provider.rb
module Scheduling
  class BaseProvider
    def fetch_appointments(start_date, end_date)
      raise NotImplementedError
    end
    
    def create_appointment(params)
      raise NotImplementedError
    end
    
    def cancel_appointment(external_id)
      raise NotImplementedError
    end
    
    def get_appointment_types
      raise NotImplementedError
    end
    
    def verify_credentials
      raise NotImplementedError
    end
  end
end
```

### Provider Implementations

```ruby
# app/services/scheduling/acuity_provider.rb
module Scheduling
  class AcuityProvider < BaseProvider
    BASE_URL = "https://acuityscheduling.com/api/v1"
    
    def initialize(user_id, api_key)
      @user_id = user_id
      @api_key = api_key
    end
    
    def fetch_appointments(start_date, end_date)
      response = connection.get("/appointments", {
        minDate: start_date.iso8601,
        maxDate: end_date.iso8601
      })
      parse_appointments(response.body)
    end
    
    # ... other methods
  end
end

# app/services/scheduling/calendly_provider.rb
module Scheduling
  class CalendlyProvider < BaseProvider
    # Future implementation
  end
end
```

---

## Database Schema

### SchedulingIntegration Model

**Purpose:** Store credentials and settings for external scheduling platform connections.

```ruby
class SchedulingIntegration < ApplicationRecord
  belongs_to :user  # Caregiver who set up the integration
  belongs_to :senior, class_name: "User", optional: true
  has_many :tasks, dependent: :nullify  # Tasks synced from this integration
  
  enum :provider, {
    acuity: 0,
    calendly: 1,
    # Future providers...
  }
  
  enum :status, {
    active: 0,
    inactive: 1,
    error: 2
  }
  
  # Encrypted credentials
  encrypts :api_key
  encrypts :api_secret
  encrypts :access_token
  
  validates :provider, :status, presence: true
  validates :provider_user_id, presence: true
end
```

**Fields:**
- `user_id` (FK) - Caregiver who owns the integration
- `senior_id` (FK, optional) - Associated senior
- `provider` (enum) - Which scheduling platform (acuity, calendly)
- `status` (enum) - Integration health status
- `provider_user_id` (string) - User ID on the scheduling platform
- `api_key` (encrypted string) - API credentials
- `api_secret` (encrypted string) - OAuth secret if needed
- `access_token` (encrypted string) - OAuth token if needed
- `webhook_secret` (string) - For webhook verification
- `last_synced_at` (datetime) - Last successful sync
- `sync_enabled` (boolean) - Auto-sync on/off
- `settings` (jsonb) - Provider-specific settings

### Enhanced Task Model

**Purpose:** Existing Task model enhanced to support external scheduling integrations.

```ruby
class Task < ApplicationRecord
  # Existing associations
  belongs_to :senior, class_name: "User"
  belongs_to :assigned_to, class_name: "User", optional: true
  belongs_to :created_by, class_name: "User"
  has_many :task_comments, dependent: :destroy
  
  # NEW: Optional link to scheduling integration
  belongs_to :scheduling_integration, optional: true
  
  # Existing enums...
  enum :task_type, { appointment: 0, errand: 1, activity: 2, household: 3, transportation: 4, other: 5 }
  enum :status, { pending: 0, assigned: 1, in_progress: 2, completed: 3, cancelled: 4 }
  enum :priority, { low: 0, medium: 1, high: 2, urgent: 3 }
  
  # NEW: Scopes for external appointments
  scope :synced_from_external, -> { where.not(external_source: nil) }
  scope :manually_created, -> { where(external_source: nil) }
  scope :from_acuity, -> { where(external_source: 'acuity') }
  scope :from_calendly, -> { where(external_source: 'calendly') }
  
  # NEW: Helper methods
  def external_appointment?
    external_source.present?
  end
  
  def external_link
    return nil unless external_appointment?
    
    case external_source
    when 'acuity'
      "https://secure.acuityscheduling.com/appointments/#{external_id}"
    when 'calendly'
      external_url
    end
  end
  
  def sync_to_external!
    return unless scheduling_integration
    # Sync logic here
  end
end
```

**New Fields to Add:**
- `scheduling_integration_id` (FK, optional) - Link to integration that created this task
- `external_source` (string, optional) - Provider name ('acuity', 'calendly', null for manual)
- `external_id` (string, optional) - Appointment ID in external system
- `external_url` (string, optional) - Direct link to appointment in external system
- `sync_metadata` (jsonb, optional) - Full external appointment data for reference

**Migration:**
```ruby
class AddSchedulingIntegrationToTasks < ActiveRecord::Migration[8.0]
  def change
    add_reference :tasks, :scheduling_integration, foreign_key: true
    add_column :tasks, :external_source, :string
    add_column :tasks, :external_id, :string
    add_column :tasks, :external_url, :string
    add_column :tasks, :sync_metadata, :jsonb
    
    add_index :tasks, [:external_source, :external_id], unique: true, where: "external_source IS NOT NULL"
  end
end
```

**Why This Approach?**
- ✅ **No data duplication** - Task already has all scheduling fields
- ✅ **Single source of truth** - All scheduled events in one place
- ✅ **Simpler queries** - No joins needed
- ✅ **Better UX** - Unified calendar view
- ✅ **Follows SRP** - Task = "scheduled event" regardless of source
- ✅ **Easier maintenance** - Less code, fewer models

---

## Features

### 1. Integration Setup

#### Connection Flow
1. Caregiver navigates to Settings → Integrations
2. Selects provider (Acuity, Calendly, etc.)
3. Enters credentials (API key for Acuity, OAuth for Calendly)
4. System verifies credentials
5. Optionally associates with specific senior
6. Enables auto-sync

#### UI Mockup
```
┌─────────────────────────────────────────────────┐
│ Scheduling Integrations                         │
├─────────────────────────────────────────────────┤
│                                                  │
│ Connect your scheduling platform to             │
│ automatically sync appointments as tasks.       │
│                                                  │
│ ┌─────────────────────────────────────────────┐ │
│ │ 🏥 Acuity Scheduling (Recommended)          │ │
│ │ HIPAA-compliant • Healthcare-focused        │ │
│ │ [Connect Acuity]                            │ │
│ └─────────────────────────────────────────────┘ │
│                                                  │
│ ┌─────────────────────────────────────────────┐ │
│ │ 📅 Calendly                                 │ │
│ │ Popular • Easy to use                       │ │
│ │ [Connect Calendly]                          │ │
│ └─────────────────────────────────────────────┘ │
│                                                  │
│ Active Integrations (1)                         │
│ ┌─────────────────────────────────────────────┐ │
│ │ ✅ Acuity Scheduling                        │ │
│ │ Connected for: senior@example.com           │ │
│ │ Last synced: 5 minutes ago                  │ │
│ │ Auto-sync: ON                               │ │
│ │ [Settings] [Sync Now] [Disconnect]          │ │
│ └─────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────┘
```

### 2. Appointment Sync

#### One-Way Sync (Phase 1)
- **Scheduling Platform → Remindly**
- Fetch appointments via API
- Create/update tasks automatically
- Manual sync button + auto-sync (hourly)

#### Two-Way Sync (Phase 2)
- **Remindly → Scheduling Platform**
- Create appointment when task is created
- Update appointment when task is modified
- Cancel appointment when task is cancelled

#### Sync Logic
```ruby
# app/services/scheduling/sync_service.rb
class Scheduling::SyncService
  def sync_integration(integration)
    provider = get_provider(integration)
    
    # Fetch appointments from last 7 days to next 90 days
    start_date = 7.days.ago
    end_date = 90.days.from_now
    
    appointments = provider.fetch_appointments(start_date, end_date)
    
    appointments.each do |appointment|
      sync_appointment(integration, appointment)
    end
    
    integration.update!(last_synced_at: Time.current)
  end
  
  private
  
  def sync_appointment(integration, appointment)
    # Find or create Task directly - no intermediate model needed!
    task = Task.find_or_initialize_by(
      external_source: integration.provider,
      external_id: appointment[:id]
    )
    
    task.assign_attributes(
      senior_id: integration.senior_id,
      title: appointment[:title] || "#{appointment[:type]} Appointment",
      description: appointment[:notes],
      task_type: :appointment,
      status: map_external_status(appointment[:status]),
      priority: :medium,
      scheduled_at: appointment[:datetime],
      duration_minutes: appointment[:duration],
      location: appointment[:location],
      notes: "Synced from #{integration.provider}",
      created_by: integration.user,
      scheduling_integration: integration,
      external_url: appointment[:calendar_url],
      sync_metadata: appointment.to_json
    )
    
    task.save!
  end
  
  def map_external_status(external_status)
    # Map external appointment status to task status
    case external_status
    when 'scheduled' then :assigned
    when 'confirmed' then :assigned
    when 'completed' then :completed
    when 'canceled' then :cancelled
    else :pending
    end
  end
  
  def get_provider(integration)
    Scheduling::ProviderFactory.create(integration)
  end
end
```

### 3. Webhook Integration

#### Webhook Endpoints
```ruby
# config/routes.rb
namespace :webhooks do
  post 'acuity', to: 'acuity#create'
  post 'calendly', to: 'calendly#create'
end
```

#### Webhook Handler
```ruby
# app/controllers/webhooks/acuity_controller.rb
class Webhooks::AcuityController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :verify_webhook_signature
  
  def create
    action = params[:action]
    appointment_id = params[:id]
    
    case action
    when 'scheduled'
      handle_scheduled(params)
    when 'rescheduled'
      handle_rescheduled(params)
    when 'canceled'
      handle_canceled(params)
    end
    
    head :ok
  end
  
  private
  
  def handle_scheduled(params)
    integration = find_integration_by_appointment(params)
    return unless integration
    
    # Sync this specific appointment as a task
    provider = Scheduling::ProviderFactory.create(integration)
    appointment = provider.get_appointment(params[:id])
    
    Scheduling::SyncService.new.sync_appointment(integration, appointment)
  end
  
  def handle_rescheduled(params)
    # Update existing task with new time
    task = Task.find_by(external_source: 'acuity', external_id: params[:id])
    return unless task
    
    provider = Scheduling::ProviderFactory.create(task.scheduling_integration)
    appointment = provider.get_appointment(params[:id])
    
    task.update!(
      scheduled_at: appointment[:datetime],
      duration_minutes: appointment[:duration],
      location: appointment[:location],
      sync_metadata: appointment.to_json
    )
  end
  
  def handle_canceled(params)
    # Mark task as cancelled
    task = Task.find_by(external_source: 'acuity', external_id: params[:id])
    return unless task
    
    task.update!(status: :cancelled)
  end
  
  def verify_webhook_signature
    # Verify webhook authenticity
  end
end
```

### 4. Task → Appointment Creation

```ruby
# app/models/task.rb
class Task < ApplicationRecord
  after_create :create_scheduling_appointment, if: :should_create_appointment?
  
  private
  
  def should_create_appointment?
    task_type == 'appointment' && 
    senior.scheduling_integrations.active.any? &&
    metadata['create_external_appointment'] == true
  end
  
  def create_scheduling_appointment
    integration = senior.scheduling_integrations.active.first
    provider = Scheduling::ProviderFactory.create(integration)
    
    appointment = provider.create_appointment(
      appointment_type_id: metadata['appointment_type_id'],
      datetime: scheduled_at,
      duration: duration_minutes,
      client: {
        firstName: senior.first_name,
        lastName: senior.last_name,
        email: senior.email,
        phone: senior.phone
      },
      notes: notes
    )
    
    ScheduledAppointment.create!(
      scheduling_integration: integration,
      task: self,
      external_id: appointment[:id],
      # ... other fields
    )
  end
end
```

---

## API Endpoints

### Integrations
```ruby
# List integrations
GET /api/scheduling_integrations

# Create integration
POST /api/scheduling_integrations
{
  "scheduling_integration": {
    "provider": "acuity",
    "provider_user_id": "12345",
    "api_key": "xxx",
    "senior_id": 1,
    "sync_enabled": true
  }
}

# Test credentials
POST /api/scheduling_integrations/verify
{
  "provider": "acuity",
  "provider_user_id": "12345",
  "api_key": "xxx"
}

# Sync now
POST /api/scheduling_integrations/:id/sync

# Update settings
PATCH /api/scheduling_integrations/:id
{
  "scheduling_integration": {
    "sync_enabled": false
  }
}

# Delete integration
DELETE /api/scheduling_integrations/:id
```

### Tasks (Enhanced for External Appointments)
```ruby
# List tasks (including synced appointments)
GET /api/tasks
  ?senior_id=1
  &external_source=acuity  # Filter by external source
  &start_date=2025-11-01
  &end_date=2025-11-30

# Get task details (works for both manual and synced tasks)
GET /api/tasks/:id
# Response includes external_source, external_id, external_url if synced

# Sync specific external appointment
POST /api/tasks/:id/sync_from_external
# Re-fetches data from external system and updates task
```

---

## Implementation Plan

### Phase 1: Core Infrastructure (3 days)

#### Day 1: Database & Models
- [ ] Create migration for `scheduling_integrations` table
- [ ] Create migration to add external sync fields to `tasks` table
- [ ] Update Task model with new associations and scopes
- [ ] Create SchedulingIntegration model with validations
- [ ] Add encrypted attributes for credentials
- [ ] Seed sample data

#### Day 2: Provider Abstraction
- [ ] Create `Scheduling::BaseProvider` interface
- [ ] Implement `Scheduling::AcuityProvider`
- [ ] Create `Scheduling::ProviderFactory`
- [ ] Add credential verification

#### Day 3: Sync Service
- [ ] Implement `Scheduling::SyncService`
- [ ] One-way sync (Platform → Remindly as Tasks)
- [ ] Background job for auto-sync
- [ ] Error handling and logging

### Phase 2: UI & Dashboard (2 days)

#### Day 1: Integration Setup
- [ ] Integrations index page
- [ ] Connection form for Acuity
- [ ] Credential verification UI
- [ ] Active integrations list

#### Day 2: Sync Management
- [ ] Manual sync button
- [ ] Sync status indicators
- [ ] Task list view showing external appointments (with badges/icons)
- [ ] Settings page

### Phase 3: Webhook Integration (2 days)

#### Day 1: Webhook Handlers
- [ ] Acuity webhook endpoint
- [ ] Signature verification
- [ ] Event processing (scheduled, rescheduled, canceled)
- [ ] Update Task records directly from webhooks

#### Day 2: Testing & Monitoring
- [ ] Webhook testing tools
- [ ] Error notifications
- [ ] Webhook logs

### Phase 4: Two-Way Sync (3 days)

#### Day 1-2: Task → Appointment
- [ ] Create appointment when task is created (if linked to integration)
- [ ] Update appointment when task is modified
- [ ] Cancel appointment when task is cancelled

#### Day 3: Conflict Resolution
- [ ] Handle sync conflicts
- [ ] User notifications for conflicts
- [ ] Manual conflict resolution UI

---

## Security Considerations

### Credential Storage
- Use Rails encrypted attributes for API keys
- Store credentials per-user, not globally
- Rotate webhook secrets regularly

### Webhook Security
- Verify webhook signatures
- Rate limit webhook endpoints
- Log all webhook events for audit

### HIPAA Compliance (Acuity)
- Sign BAA with Acuity
- Encrypt all PHI in transit and at rest
- Audit log all appointment access
- Implement data retention policies

### API Rate Limiting
- Respect provider rate limits
- Implement exponential backoff
- Cache appointment data appropriately

---

## Provider-Specific Details

### Acuity Scheduling

**Authentication:**
```ruby
# Basic Auth with User ID + API Key
connection.basic_auth(@user_id, @api_key)
```

**Key Endpoints:**
- `GET /appointments` - List appointments
- `POST /appointments` - Create appointment
- `PUT /appointments/{id}` - Update appointment
- `DELETE /appointments/{id}/cancel` - Cancel appointment
- `GET /appointment-types` - List available types
- `GET /calendars` - List calendars

**Webhooks:**
- Configure at: https://secure.acuityscheduling.com/app.php?key=api&action=webhooks
- Events: `appointment.scheduled`, `appointment.rescheduled`, `appointment.canceled`

**HIPAA:**
- Contact Acuity to sign BAA
- Enable HIPAA mode in account settings
- Use secure forms for intake

### Calendly (Future)

**Authentication:**
- OAuth 2.0 flow
- Personal Access Token for testing

**Key Endpoints:**
- `GET /scheduled_events` - List events
- `GET /event_types` - List event types
- Webhooks via webhook subscriptions

**Limitations:**
- No HIPAA compliance
- No BAA available
- Better for general scheduling

---

## Testing Strategy

### Unit Tests
```ruby
# spec/services/scheduling/acuity_provider_spec.rb
RSpec.describe Scheduling::AcuityProvider do
  describe '#fetch_appointments' do
    it 'fetches appointments from Acuity API'
    it 'handles API errors gracefully'
    it 'parses appointment data correctly'
  end
end

# spec/services/scheduling/sync_service_spec.rb
RSpec.describe Scheduling::SyncService do
  describe '#sync_integration' do
    it 'creates tasks from appointments'
    it 'updates existing tasks'
    it 'handles deleted appointments'
  end
end
```

### Integration Tests
```ruby
# spec/requests/scheduling_integrations_spec.rb
RSpec.describe 'Scheduling Integrations API' do
  describe 'POST /api/scheduling_integrations' do
    it 'creates integration with valid credentials'
    it 'rejects invalid credentials'
  end
end
```

### Webhook Tests
```ruby
# spec/requests/webhooks/acuity_spec.rb
RSpec.describe 'Acuity Webhooks' do
  describe 'POST /webhooks/acuity' do
    it 'processes scheduled event'
    it 'verifies webhook signature'
    it 'rejects invalid signatures'
  end
end
```

---

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Sync success rate | ≥ 99% | Successful syncs / Total syncs |
| Sync latency | ≤ 5 minutes | Time from appointment creation to task creation |
| Webhook processing | ≤ 30 seconds | Time to process webhook event |
| Integration uptime | ≥ 99.5% | Active integrations / Total integrations |
| User adoption | ≥ 30% | Users with active integrations |

---

## Future Enhancements

### Additional Providers
- **Google Calendar** - Personal calendar sync
- **Microsoft Bookings** - Enterprise scheduling
- **Square Appointments** - Payment integration
- **SimplyBook.me** - International support

### Advanced Features
- **Smart scheduling** - AI-suggested appointment times
- **Conflict detection** - Warn about overlapping appointments
- **Availability sync** - Sync caregiver availability to scheduling platform
- **Multi-calendar support** - Aggregate multiple calendars
- **Appointment reminders** - Custom reminder rules per integration
- **Analytics** - Appointment trends and insights

### Mobile Support
- Push notifications for new appointments
- Quick sync from mobile app
- Mobile-optimized integration setup

---

## Dependencies

- **Faraday** - HTTP client for API calls
- **ActiveJob** - Background sync jobs
- **Sidekiq** (optional) - Job processing
- **Rails encrypted attributes** - Credential storage

---

## Documentation Needed

- [ ] User guide for setting up integrations
- [ ] API documentation for scheduling endpoints
- [ ] Provider-specific setup guides (Acuity, Calendly)
- [ ] Webhook configuration instructions
- [ ] HIPAA compliance guide
- [ ] Troubleshooting guide

---

## Estimated Timeline

**Total: 10 days (2 weeks)**

- Phase 1: Core Infrastructure (3 days)
- Phase 2: UI & Dashboard (2 days)
- Phase 3: Webhook Integration (2 days)
- Phase 4: Two-Way Sync (3 days)

---

**Status:** Planning Phase  
**Priority:** High  
**Complexity:** Medium-High  
**Value:** High - Streamlines appointment management for caregivers

---

## Next Steps

1. Review and approve this plan
2. Set up Acuity Scheduling test account
3. Begin Phase 1 implementation
4. Create feature flag for gradual rollout
