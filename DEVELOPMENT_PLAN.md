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

### **Phase 5: Authentication & Security**
*Goal: Proper magic link authentication*

#### 5.1 Login Screen
- [ ] Email input form
- [ ] Request magic link button
- [ ] Loading state
- [ ] Error handling

#### 5.2 Magic Link Flow
- [ ] POST to `/magic/request`
- [ ] Show "Check your email" message
- [ ] Handle deep link from email
- [ ] Verify token via `/magic/verify`
- [ ] Store JWT securely in Keychain

#### 5.3 Session Management
- [ ] Auto-refresh JWT before expiry
- [ ] Logout functionality
- [ ] Handle expired tokens
- [ ] Remember user email

**Acceptance Criteria:**
- User can login with email
- Magic link opens app and authenticates
- JWT stored securely
- Session persists across launches

---

### **Phase 6: Backend Enhancements**
*Goal: Support new client features*

#### 6.1 Reminder CRUD Endpoints
- [ ] GET `/reminders` - list all user reminders
- [ ] PUT `/reminders/:id` - update reminder
- [ ] DELETE `/reminders/:id` - delete reminder
- [ ] Regenerate occurrences on update

#### 6.2 Status Management
- [ ] Background job to mark missed occurrences
- [ ] Update occurrence status on acknowledgement
- [ ] Return status in `/reminders/today` response

#### 6.3 Timezone Support
- [ ] Store user timezone in User model
- [ ] Return occurrences in user's timezone
- [ ] Handle DST transitions

#### 6.4 Email Service
- [ ] Configure ActionMailer
- [ ] Magic link email template
- [ ] Test email delivery

**Acceptance Criteria:**
- Full CRUD for reminders
- Occurrences marked as missed automatically
- Timezone handling works correctly
- Magic link emails sent

---

### **Phase 7: Caregiver Dashboard** (Phase 1.5)
*Goal: Web interface for caregivers*

#### 7.1 Caregiver Model & Linking
- [ ] Create CaregiverLink model (already exists)
- [ ] Generate pairing tokens
- [ ] Link caregiver to senior
- [ ] Permissions system

#### 7.2 Dashboard UI (Hotwire)
- [ ] Login page for caregivers
- [ ] Dashboard showing linked seniors
- [ ] Today's reminders for each senior
- [ ] Acknowledgement status
- [ ] 7-day history view

#### 7.3 Real-Time Updates
- [ ] Turbo Streams for live updates
- [ ] Show when senior acknowledges
- [ ] Missed reminder alerts
- [ ] Last sync timestamp

**Acceptance Criteria:**
- Caregiver can link to senior
- Dashboard shows real-time status
- 7-day history visible
- Mobile responsive

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

**Current Status:** Sprint 4 (Settings & Accessibility) complete ✅
**Next Action:** Begin Sprint 5 - Authentication & Security

**Recent Completions:**
- ✅ Sprint 1: Notification Infrastructure (complete)
- ✅ Sprint 2: Reminder Management (complete)
- ✅ Sprint 3: Offline Support (complete)
- ✅ Sprint 4: Settings & Accessibility (complete)
