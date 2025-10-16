# 🚀 Remindly Development Plan

## Current Status Analysis

### ✅ What's Already Implemented
- **Backend (Rails 8)**
  - JWT authentication with magic link endpoints
  - User, Reminder, Occurrence, Acknowledgement models
  - `/reminders/today` endpoint returning occurrences
  - `/acknowledgements` POST endpoint
  - Recurrence engine with IceCube
  - Basic CRUD for reminders

- **macOS Client (SwiftUI)**
  - Basic UI showing today's reminders
  - Authentication flow (dev mode)
  - Acknowledge actions (Taken/Snooze/Skip)
  - Voice synthesis for reading reminders
  - Network entitlements configured
  - Large text, senior-friendly UI

### ❌ What's Missing (Per PRD)

#### High Priority (MVP Core)
1. **Notifications System** - Desktop notifications not implemented
2. **Reminder Creation UI** - No way to create/edit reminders from macOS app
3. **Offline Persistence** - No local storage, fully dependent on network
4. **Notification Scheduling** - No background timer or notification triggers
5. **Status Updates** - Occurrences don't update to "missed" automatically

#### Medium Priority (MVP Polish)
6. **Settings/Preferences** - No accessibility settings (font size, voice controls)
7. **Time Zone Handling** - Using server time, not user's local timezone
8. **Error Handling** - Basic error messages, needs retry logic
9. **Proper Authentication** - Still using dev mode, needs magic link flow

#### Lower Priority (Phase 1.5+)
10. **Caregiver Dashboard** - Web interface not started
11. **Caregiver Linking** - No pairing mechanism
12. **7-Day History View** - Only shows today
13. **Multi-language Support** - English only

---

## 📋 Phased Development Plan

### **Phase 1: Core Notification System** (Current Branch)
*Goal: Make the app actually remind users at scheduled times*

#### 1.1 macOS Notification Permissions & Setup
- [ ] Request `UNUserNotificationCenter` permissions on launch
- [ ] Create notification manager service
- [ ] Test basic notification delivery

#### 1.2 Background Notification Scheduling
- [ ] Fetch today's reminders on app launch
- [ ] Schedule notifications for each pending occurrence
- [ ] Handle notification tap to open app and show reminder
- [ ] Re-schedule notifications when app refreshes

#### 1.3 Notification Enhancements
- [ ] Add voice prompt 2 minutes before scheduled time
- [ ] Repeat notification if not acknowledged within 5 minutes
- [ ] Show action buttons in notification (Taken/Snooze/Skip)
- [ ] Custom notification sound for seniors

**Acceptance Criteria:**
- User receives desktop notification at scheduled time
- Tapping notification opens app to that reminder
- Voice prompt plays before notification
- Notifications repeat if ignored

---

### **Phase 2: Reminder Management UI**
*Goal: Users can create and manage reminders without backend access*

#### 2.1 Create Reminder Flow
- [ ] Add "+" button to main view
- [ ] Create reminder form with fields:
  - Title (required)
  - Notes (optional)
  - Category picker (Medication/Hydration/Routine)
  - Time picker
  - Recurrence presets (Daily, Every 2 hours, Custom)
- [ ] POST to `/reminders` endpoint
- [ ] Refresh list after creation

#### 2.2 Edit & Delete Reminders
- [ ] Swipe actions on reminder cards
- [ ] Edit reminder sheet
- [ ] Delete confirmation dialog
- [ ] Update backend via API

#### 2.3 RRULE Presets
- [ ] Daily at specific time
- [ ] Every N hours (2, 4, 6, 8)
- [ ] Specific days of week
- [ ] Custom RRULE builder (advanced)

**Acceptance Criteria:**
- User can create reminder with simple UI
- Reminders sync to backend
- Edit/delete works correctly
- Recurrence patterns generate correct occurrences

---

### **Phase 3: Offline Support & Persistence**
*Goal: App works without internet, syncs when reconnected*

#### 3.1 Local Storage Layer
- [ ] Add SwiftData or Core Data models
- [ ] Store reminders locally
- [ ] Store occurrences locally
- [ ] Store acknowledgements with sync flag

#### 3.2 Sync Logic
- [ ] Detect network connectivity
- [ ] Queue acknowledgements when offline
- [ ] Sync on reconnect
- [ ] Conflict resolution (server wins)
- [ ] Show sync status indicator

#### 3.3 Offline-First UX
- [ ] Load from local storage first
- [ ] Background sync every 5 minutes
- [ ] Show "offline" indicator
- [ ] Graceful degradation

**Acceptance Criteria:**
- App launches and shows reminders without network
- Acknowledgements work offline
- Syncs automatically when online
- No data loss

---

### **Phase 4: Settings & Accessibility**
*Goal: Customizable experience for seniors*

#### 4.1 Settings Screen
- [ ] Add settings button/menu
- [ ] Create settings view with sections:
  - Appearance
  - Voice & Sound
  - Notifications
  - Account

#### 4.2 Appearance Settings
- [ ] Font size slider (18-48pt)
- [ ] High contrast mode toggle
- [ ] Color scheme (light/dark/auto)
- [ ] Preview changes live

#### 4.3 Voice & Sound Settings
- [ ] Voice rate slider (0.3-0.6)
- [ ] Voice volume slider
- [ ] Test voice button
- [ ] Notification sound picker

#### 4.4 Notification Settings
- [ ] Enable/disable notifications
- [ ] Reminder lead time (2-10 minutes)
- [ ] Repeat interval (5-15 minutes)
- [ ] Quiet hours (optional)

**Acceptance Criteria:**
- Settings persist across launches
- Changes apply immediately
- Voice test works
- Accessibility guidelines met

---

### **Phase 5: Authentication & Security** ✅ COMPLETE
*Goal: Proper magic link authentication*

#### 5.1 Login Screen
- [x] Email input form
- [x] Request magic link button
- [x] Loading state
- [x] Error handling

#### 5.2 Magic Link Flow
- [x] POST to `/magic/request`
- [x] Show "Check your email" message
- [x] Handle deep link from email
- [x] Verify token via `/magic/verify`
- [x] Store JWT securely in Keychain

#### 5.3 Session Management
- [x] Auto-refresh JWT before expiry
- [x] Logout functionality
- [x] Handle expired tokens
- [x] Remember user email

**Acceptance Criteria:**
- [x] User can login with email
- [x] Magic link opens app and authenticates
- [x] JWT stored securely
- [x] Session persists across launches

**Deliverables:**
- AuthenticationManager with Keychain storage
- LoginView with magic link flow
- Deep link handling for magic links
- Session monitoring and auto-logout
- Account settings with logout
- Backend email service (MagicMailer)
- Comprehensive documentation

**Documentation:**
- `/SPRINT_5_AUTHENTICATION_GUIDE.md` - Complete implementation guide
- `/PHASE_5_SETUP_INSTRUCTIONS.md` - Quick setup guide

---

### **Phase 6: Backend Enhancements** ✅ COMPLETE
*Goal: Support new client features*

#### 6.1 Reminder CRUD Endpoints
- [x] GET `/reminders` - list all user reminders with filtering & pagination
- [x] GET `/reminders/:id` - get single reminder
- [x] PUT `/reminders/:id` - update reminder
- [x] DELETE `/reminders/:id` - delete reminder
- [x] Regenerate occurrences on update
- [x] DELETE `/reminders/bulk_destroy` - bulk delete

#### 6.2 Filtering & Search
- [x] Filter by category
- [x] Search in title and notes
- [x] Pagination support (max 100 per page)
- [x] Sort by created_at

#### 6.3 Error Handling
- [x] Proper HTTP status codes
- [x] Validation error messages
- [x] Not found handling
- [x] Authorization checks

#### 6.4 Code Quality
- [x] Remove debug logging
- [x] Clean up controller code
- [x] Add error rescue handlers

**Acceptance Criteria:**
- [x] Full CRUD for reminders
- [x] Filtering and search work correctly
- [x] Pagination handles large lists
- [x] Error handling is consistent
- [x] Bulk operations available

**Deliverables:**
- Enhanced RemindersController with filtering, search, pagination
- Bulk delete endpoint
- Proper error handling
- API documentation

**Documentation:**
- `/PHASE_6_API_GUIDE.md` - Complete API reference

---

### **Phase 7: Caregiver Dashboard** ✅ COMPLETE
*Goal: Web interface for caregivers*

#### 7.1 Caregiver Model & Linking
- [x] Create CaregiverLink model with enhancements
- [x] Generate pairing tokens (7-day expiry)
- [x] Link caregiver to senior via token
- [x] Permissions system (view/manage)

#### 7.2 Dashboard UI
- [x] Login page for caregivers (magic link)
- [x] Dashboard showing linked seniors
- [x] Today's reminders for each senior
- [x] Acknowledgement status display
- [x] 7-day history view (grouped by date)
- [x] Admin panel for user management
- [x] Reminder CRUD for caregivers

#### 7.3 Real-Time Updates
- [ ] Turbo Streams for live updates (deferred to future)
- [x] Show acknowledgement status
- [x] Missed reminder count
- [x] Status indicators (pending/acknowledged/missed)

**Acceptance Criteria:**
- [x] Caregiver can link to senior
- [x] Dashboard shows current status
- [x] 7-day history visible
- [x] Mobile responsive
- [x] Security hardened (9 issues fixed)

**Deliverables:**
- Admin panel with role management
- Magic link authentication for web
- Pairing system with secure tokens
- Senior activity monitoring
- Full reminder CRUD for caregivers
- Comprehensive documentation

**Documentation:**
- `/PHASE_7_CAREGIVER_DASHBOARD.md` - Complete implementation guide
- `/FUTURE_ENHANCEMENTS.md` - Roadmap for optional features

---

### **Phase 8: Shared Task & Appointment Scheduling**
*Goal: Enable caregivers to coordinate care tasks and appointments*

#### 8.1 Task Management
- [ ] Task model (appointments, errands, activities)
- [ ] Task creation and editing
- [ ] Task assignment to caregivers
- [ ] Status workflow (pending → assigned → in progress → completed)
- [ ] Priority levels (low/medium/high/urgent)

#### 8.2 Caregiver Coordination
- [ ] Availability calendar
- [ ] Task assignment and reassignment
- [ ] Load balancing dashboard
- [ ] Unassigned task pool
- [ ] Self-assignment capability

#### 8.3 Collaboration Features
- [ ] Task comments and @mentions
- [ ] Activity log
- [ ] Shared notes
- [ ] File attachments (future)

#### 8.4 Notifications
- [ ] Email notifications (assigned, due soon, completed)
- [ ] In-app notifications
- [ ] Reminder schedule (24h, 2h, at time, overdue)

#### 8.5 Views & Filters
- [ ] Calendar view (monthly/weekly)
- [ ] List view with filters
- [ ] My Tasks view
- [ ] Unassigned tasks view
- [ ] Completed tasks history

**Acceptance Criteria:**
- Caregivers can create tasks for seniors
- Tasks can be assigned to specific caregivers
- Availability tracking shows who's free
- Load is balanced across caregivers
- Notifications alert about upcoming tasks
- Mobile responsive

**Documentation:**
- `/PHASE_8_TASK_SCHEDULING.md` - Complete implementation plan

---

## 🎯 Recommended Next Steps (This Sprint)

### Sprint 1: Notifications Foundation (3-5 days)
**Branch:** `feature/notifications-and-reminders` (current)

1. **Day 1-2: Notification Infrastructure**
   - Implement `NotificationManager` class
   - Request permissions on launch
   - Schedule notifications for today's reminders
   - Test notification delivery

2. **Day 3: Notification Actions**
   - Handle notification tap
   - Add action buttons to notifications
   - Connect to acknowledgement flow

3. **Day 4: Voice Integration**
   - Schedule voice prompts before notifications
   - Add repeat logic for unacknowledged reminders
   - Test timing and reliability

4. **Day 5: Polish & Testing**
   - Edge case handling
   - Background app behavior
   - User testing with sample data

### Sprint 2: Reminder Management (3-4 days)
**Branch:** `feature/reminder-crud`

1. Create reminder form UI
2. Implement RRULE presets
3. Add edit/delete functionality
4. Backend CRUD endpoints

### Sprint 3: Offline Support (4-5 days) ✅ COMPLETE
**Branch:** `feature/offline-persistence`
**Status:** Fully implemented and ready for testing

1. ✅ Add SwiftData models (LocalReminder, LocalOccurrence, PendingAction)
2. ✅ Implement sync logic (SyncManager with retry)
3. ✅ Queue management (offline action queue)
4. ✅ Network monitoring (NetworkMonitor with NWPathMonitor)
5. ✅ UI integration (offline indicator, debug tools)
6. ⏳ Testing offline scenarios (see SPRINT_3_TEST_PLAN.md)

**Deliverables:**
- SwiftData persistence layer
- Automatic sync on reconnection
- Offline-first architecture
- Debug tools for testing
- Comprehensive test plan

**Documentation:**
- `/SPRINT_3_TEST_PLAN.md` - Complete test scenarios
- `/clients/macos-swiftui/OFFLINE_TESTING_GUIDE.md` - Quick testing guide

### Sprint 4: Settings & Accessibility (3-4 days) ✅ COMPLETE
**Branch:** `sprint-4-settings-accessibility`
**Status:** Fully implemented and ready for testing

1. ✅ Create settings screen UI
2. ✅ Implement appearance settings (font size, contrast, theme)
3. ✅ Add voice & sound settings (rate, volume, test)
4. ✅ Add notification preferences (lead time, repeat interval, quiet hours)
5. ✅ Persist settings with UserDefaults
6. ✅ Apply settings across app

**Deliverables:**
- AppSettings model with UserDefaults persistence
- Comprehensive SettingsView with 3 tabs
- Integration with ReminderVM and NotificationManager
- Dynamic font sizing across all UI
- High contrast mode support
- Quiet hours functionality
- Comprehensive documentation

**Documentation:**
- `/SPRINT_4_SETTINGS_GUIDE.md` - Complete implementation guide

---

## 🧪 Testing Strategy

### Unit Tests
- [ ] Notification scheduling logic
- [ ] RRULE generation
- [ ] Sync queue management
- [ ] JWT token handling

### Integration Tests
- [ ] API client tests
- [ ] Notification delivery
- [ ] Offline → Online sync
- [ ] Authentication flow

### User Acceptance Testing
- [ ] Senior usability testing
- [ ] Caregiver dashboard testing
- [ ] Accessibility testing
- [ ] Cross-timezone testing

---

## 📊 Success Metrics (Per PRD)

| Metric | Target | How to Measure |
|--------|--------|----------------|
| Setup completion | ≥ 80% | Track users who complete first reminder |
| 7-day retention | ≥ 60% | Active users after 7 days |
| Acknowledgement rate | ≥ 85% | Acknowledged / Total occurrences |
| Caregiver engagement | ≥ 70% | Caregivers checking dashboard weekly |

---

## 🔧 Technical Debt to Address

1. **Error Handling**: Improve error messages and retry logic
2. **Loading States**: Better UX for async operations
3. **Code Organization**: Separate concerns (networking, persistence, UI)
4. **Testing**: Add comprehensive test coverage
5. **Documentation**: API docs, setup guides, architecture docs
6. **Performance**: Optimize list rendering for many reminders
7. **Security**: Move JWT secret to environment variables
8. **Logging**: Add structured logging for debugging

---

**Current Status:** Phase 7 (Caregiver Dashboard) complete ✅
**Next Action:** Begin Phase 8 - Shared Task & Appointment Scheduling

**Recent Completions:**
- ✅ Phase 1: Notification Infrastructure (complete)
- ✅ Phase 2: Reminder Management (complete)
- ✅ Phase 3: Offline Support (complete)
- ✅ Phase 4: Settings & Accessibility (complete)
- ✅ Phase 5: Authentication & Security (complete)
- ✅ Phase 6: Backend Enhancements (complete)
- ✅ Phase 7: Caregiver Dashboard (complete)

**Phase 8 Timeline:** 17 days (3.5 weeks)
- Sprint 1: Core Task Management (5 days)
- Sprint 2: UI & Dashboard (5 days)
- Sprint 3: Coordination Features (4 days)
- Sprint 4: Notifications (3 days)
