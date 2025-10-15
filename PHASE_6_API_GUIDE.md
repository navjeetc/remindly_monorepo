# Phase 6: Backend Enhancements - API Guide

## Overview

Phase 6 adds enhanced CRUD operations, filtering, pagination, search, and bulk operations to the Reminders API.

## API Endpoints

### 1. List Reminders (Enhanced)

**GET** `/reminders`

List all reminders for the authenticated user with filtering, search, and pagination.

**Query Parameters:**
- `category` (optional) - Filter by category (0=medication, 1=appointment, 2=meal, 3=exercise, 4=social, 5=other)
- `search` (optional) - Search in title and notes
- `page` (optional) - Page number (default: 1)
- `per_page` (optional) - Items per page (default: 50, max: 100)

**Example Requests:**
```bash
# Get all reminders
GET /reminders

# Filter by category
GET /reminders?category=0

# Search for "doctor"
GET /reminders?search=doctor

# Paginate (page 2, 20 per page)
GET /reminders?page=2&per_page=20

# Combine filters
GET /reminders?category=1&search=appointment&page=1&per_page=10
```

**Response:**
```json
{
  "reminders": [
    {
      "id": 1,
      "title": "Take medication",
      "notes": "Take with food",
      "category": 0,
      "rrule": "FREQ=DAILY",
      "tz": "America/New_York",
      "start_time": "2025-10-15T09:00:00Z",
      "created_at": "2025-10-15T10:00:00Z",
      "updated_at": "2025-10-15T10:00:00Z"
    }
  ],
  "pagination": {
    "page": 1,
    "per_page": 50,
    "total_count": 25,
    "total_pages": 1
  }
}
```

### 2. Get Single Reminder

**GET** `/reminders/:id`

Get a specific reminder by ID.

**Response:**
```json
{
  "id": 1,
  "title": "Take medication",
  "notes": "Take with food",
  "category": 0,
  "rrule": "FREQ=DAILY",
  "tz": "America/New_York",
  "start_time": "2025-10-15T09:00:00Z",
  "created_at": "2025-10-15T10:00:00Z",
  "updated_at": "2025-10-15T10:00:00Z"
}
```

**Error Response (404):**
```json
{
  "error": "Reminder not found"
}
```

### 3. Create Reminder

**POST** `/reminders`

Create a new reminder.

**Request Body:**
```json
{
  "title": "Take medication",
  "notes": "Take with food",
  "category": 0,
  "rrule": "FREQ=DAILY",
  "tz": "America/New_York",
  "start_time": "2025-10-15T09:00:00Z"
}
```

**Response (201 Created):**
```json
{
  "id": 1,
  "title": "Take medication",
  "notes": "Take with food",
  "category": 0,
  "rrule": "FREQ=DAILY",
  "tz": "America/New_York",
  "start_time": "2025-10-15T09:00:00Z",
  "created_at": "2025-10-15T10:00:00Z",
  "updated_at": "2025-10-15T10:00:00Z"
}
```

**Error Response (422 Unprocessable Entity):**
```json
{
  "error": "Validation failed",
  "details": [
    "Title can't be blank",
    "Rrule can't be blank"
  ]
}
```

### 4. Update Reminder

**PUT** `/reminders/:id`

Update an existing reminder. Automatically regenerates occurrences.

**Request Body:**
```json
{
  "title": "Take medication (updated)",
  "notes": "Take with water",
  "category": 0,
  "rrule": "FREQ=DAILY;INTERVAL=2",
  "start_time": "2025-10-15T10:00:00Z"
}
```

**Response:**
```json
{
  "id": 1,
  "title": "Take medication (updated)",
  "notes": "Take with water",
  "category": 0,
  "rrule": "FREQ=DAILY;INTERVAL=2",
  "tz": "America/New_York",
  "start_time": "2025-10-15T10:00:00Z",
  "created_at": "2025-10-15T10:00:00Z",
  "updated_at": "2025-10-15T11:00:00Z"
}
```

**Note:** Updating a reminder deletes all pending occurrences and regenerates them based on the new schedule.

### 5. Delete Reminder

**DELETE** `/reminders/:id`

Delete a reminder and all its occurrences.

**Response (204 No Content):**
No response body.

### 6. Get Today's Occurrences

**GET** `/reminders/today`

Get all occurrences scheduled for today in the user's timezone.

**Response:**
```json
[
  {
    "id": 121,
    "reminder_id": 35,
    "scheduled_at": "2025-10-15T19:32:00Z",
    "status": "pending",
    "created_at": "2025-10-15T10:00:00Z",
    "updated_at": "2025-10-15T10:00:00Z",
    "reminder": {
      "title": "Take medication",
      "notes": "Take with food",
      "category": 0
    }
  }
]
```

### 7. Bulk Delete Reminders (New)

**DELETE** `/reminders/bulk_destroy`

Delete multiple reminders at once.

**Request Body:**
```json
{
  "ids": [1, 2, 3, 4, 5]
}
```

**Response:**
```json
{
  "message": "Successfully deleted 5 reminder(s)",
  "deleted_count": 5
}
```

**Error Response (400 Bad Request):**
```json
{
  "error": "No IDs provided"
}
```

## Categories

Reminders support the following categories:

| Value | Category    |
|-------|-------------|
| 0     | Medication  |
| 1     | Appointment |
| 2     | Meal        |
| 3     | Exercise    |
| 4     | Social      |
| 5     | Other       |

## Recurrence Rules (RRULE)

Reminders use iCalendar RRULE format for recurring schedules.

**Examples:**
```
FREQ=DAILY                    # Every day
FREQ=DAILY;INTERVAL=2         # Every 2 days
FREQ=WEEKLY;BYDAY=MO,WE,FR    # Monday, Wednesday, Friday
FREQ=MONTHLY;BYMONTHDAY=15    # 15th of every month
FREQ=HOURLY;INTERVAL=4        # Every 4 hours
```

## Error Handling

All endpoints return appropriate HTTP status codes:

- **200 OK** - Successful GET request
- **201 Created** - Successful POST request
- **204 No Content** - Successful DELETE request
- **400 Bad Request** - Invalid request parameters
- **401 Unauthorized** - Missing or invalid authentication
- **404 Not Found** - Resource not found
- **422 Unprocessable Entity** - Validation errors

**Error Response Format:**
```json
{
  "error": "Error message",
  "details": ["Additional error details"]
}
```

## Authentication

All endpoints require authentication via JWT token in the Authorization header:

```
Authorization: Bearer <JWT_TOKEN>
```

## Rate Limiting

- **Pagination:** Max 100 items per page
- **Bulk Operations:** Max 100 IDs per request (recommended)

## Examples

### Filter medication reminders
```bash
curl -H "Authorization: Bearer $TOKEN" \
  "https://api.remindly.app/reminders?category=0"
```

### Search for "doctor" appointments
```bash
curl -H "Authorization: Bearer $TOKEN" \
  "https://api.remindly.app/reminders?category=1&search=doctor"
```

### Get page 2 with 20 items
```bash
curl -H "Authorization: Bearer $TOKEN" \
  "https://api.remindly.app/reminders?page=2&per_page=20"
```

### Bulk delete reminders
```bash
curl -X DELETE \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"ids": [1, 2, 3]}' \
  "https://api.remindly.app/reminders/bulk_destroy"
```

### Update a reminder
```bash
curl -X PUT \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Updated title",
    "notes": "Updated notes",
    "rrule": "FREQ=DAILY;INTERVAL=2"
  }' \
  "https://api.remindly.app/reminders/1"
```

## What's New in Phase 6

✅ **Filtering** - Filter reminders by category  
✅ **Search** - Search in title and notes  
✅ **Pagination** - Efficient handling of large reminder lists  
✅ **Bulk Operations** - Delete multiple reminders at once  
✅ **Error Handling** - Proper HTTP status codes and error messages  
✅ **Clean Code** - Removed debug logging  

## Next Steps

- Implement filtering in the macOS app
- Add search UI in the app
- Implement pagination for large lists
- Add bulk delete UI

## Related Documentation

- [DEVELOPMENT_PLAN.md](DEVELOPMENT_PLAN.md) - Overall project plan
- [SPRINT_5_AUTHENTICATION_GUIDE.md](SPRINT_5_AUTHENTICATION_GUIDE.md) - Authentication guide
- [PRD.md](PRD.md) - Product requirements
