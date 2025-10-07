# 🧭 Remindly — MVP Product Requirements Document (PRD)

## 1. Overview

**Remindly** is a desktop-first reminder and wellness companion designed for **seniors and caregivers**.  
It helps seniors stay on schedule with medications, hydration, and routines — and enables caregivers to monitor acknowledgements in real time.

- **Platforms:** macOS (SwiftUI MVP), Windows (Tauri, Phase 2)
- **Backend:** Rails 8 API (JWT auth + recurrence)
- **UI Goal:** Large text, minimal actions, voice prompts, “one-glance clarity”

---

## 2. Core Use Cases

| User | Need | Solution |
|------|------|-----------|
| Senior | Be reminded to take meds / hydrate / walk | Desktop notifications, voice prompt, large-button acknowledge |
| Caregiver | See if senior took their meds | Web dashboard (Hotwire) showing acknowledgements in real time |
| Both | Stay connected even offline | Local persistence with periodic API sync |

---

## 3. Functional Scope (MVP)

### A. Reminder Management
**Actors:** Senior  
**Description:** Seniors can create recurring reminders using natural time intervals.

#### Features
- Create, edit, delete reminders
- Fields: `title`, `notes`, `rrule`, `category`, `tz`
- Categories: `Medication`, `Hydration`, `Routine`
- Default RRULE presets (daily 9AM, every 2 hours, etc.)
- Recurrence engine: **IceCube** (backend)
- Sync from SwiftUI → Rails `/reminders` endpoint

---

### B. Today’s Reminders View
**Actors:** Senior  
**Description:** Main dashboard showing all today’s occurrences.

#### Features
- Display list grouped by time
- Each card shows title, category, time, notes, and status (`Pending`, `Acknowledged`, `Missed`)
- Actions:  
  - Play voice prompt  
  - Mark as Taken / Snooze / Skip  
- When acknowledged: POST `/acknowledgements` and refresh list

---

### C. Notifications & Voice
**Actors:** Senior  
**Description:** Auditory and visual alerts.

#### Features
- macOS local notification (`UNUserNotificationCenter`)
- Voice prompt before scheduled time
- Repeat if not acknowledged within 5 minutes
- Volume / rate controls in preferences

---

### D. Caregiver Dashboard (Phase 1.5)
**Actors:** Caregiver  
**Description:** View linked senior’s activity and history.

#### Features
- Web-based (Hotwire + Turbo Streams)
- Link token for pairing caregiver/senior
- Dashboard shows daily acknowledgements, 7-day history, missed alerts

---

### E. Authentication (Magic Link)
**Actors:** Both  
**Description:** Passwordless login.

#### Features
- `/magic/request?email=…` → send link
- `/magic/verify?token=…` → return JWT
- SwiftUI stores JWT in `UserDefaults`
- Rails uses `Authorization: Bearer <token>`

---

### F. Settings & Accessibility
**Actors:** Senior  
**Description:** Adjust interface for visibility and hearing.

#### Features
- Font scaling
- High-contrast mode
- Voice prompt test
- Time zone picker

---

### G. Sync & Offline
**Actors:** Senior  
**Description:** Works offline and syncs later.

#### Features
- Local persistence in SwiftUI
- Sync acknowledgements and reminders on reconnect

---

## 4. API Summary

| Endpoint | Method | Purpose |
|-----------|---------|---------|
| `/magic/request` | GET | Request magic link email |
| `/magic/verify` | GET | Verify token and return JWT |
| `/magic/dev_exchange` | GET | Dev exchange shortcut |
| `/reminders` | POST | Create reminder |
| `/reminders/today` | GET | Get today’s occurrences |
| `/acknowledgements` | POST | Mark occurrence as acknowledged |

---

## 5. Data Models

### Reminder
| Field | Type | Notes |
|--------|------|-------|
| id | int | PK |
| title | string | required |
| notes | text | optional |
| rrule | string | RFC 5545 format |
| tz | string | time zone name |
| category | enum | medication, hydration, routine |

### Occurrence
| Field | Type | Notes |
|--------|------|-------|
| id | int | PK |
| reminder_id | int | FK |
| scheduled_at | datetime | UTC |
| status | enum | pending, acknowledged, missed |

### Acknowledgement
| Field | Type | Notes |
|--------|------|-------|
| occurrence_id | int | FK |
| kind | enum | taken, snooze, skip |
| at | datetime | timestamp |

---

## 6. Non-Functional Requirements
- Performance: reminders list loads in < 300 ms
- Offline-first
- Accessibility: full keyboard + voiceover support
- Privacy: no external analytics in MVP
- Security: JWT expiry 24h, refresh via `/magic/verify`

---

## 7. Future Enhancements
| Phase | Feature | Description |
|--------|----------|-------------|
| 2 | Windows (Tauri) client | Reuse API and shared locales |
| 2 | Multi-language support | `en`, `es`, `de`, `fr`, `hi` |
| 2 | Family plan | Multiple seniors per caregiver |
| 3 | Smart voice agent | Conversational reminders |
| 3 | Health data integration | Apple HealthKit / Fitbit hydration |

---

## 8. MVP Success Metrics
| Metric | Target |
|---------|---------|
| Setup completion | ≥ 80 % |
| 7-day retention | ≥ 60 % |
| Acknowledgement rate | ≥ 85 % |
| Caregiver engagement | ≥ 70 % |

---

**Version:** 1.0 (Rails 8 + SwiftUI MVP)  
**Author:** Jeet  
**Date:** October 2025
