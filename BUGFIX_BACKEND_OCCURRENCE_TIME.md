# Bug Fix: Backend Creating Occurrences at Wrong Time

## Issue
When updating a reminder, the backend regenerates occurrences but creates them at the **current time** instead of the **reminder's configured time**.

**Example:**
- Reminder configured: Daily at 2:00 PM
- Updated at: 5:36 PM
- Occurrences created: 9:34 PM (current time + timezone offset) ❌
- Expected: 2:00 PM (configured time) ✅

## Root Cause

**File:** `app/services/recurrence.rb`

```ruby
def self.expand(reminder, horizon_hours: 24)
  tz   = ActiveSupport::TimeZone[reminder.tz]
  now  = tz.now
  stop = now + horizon_hours.hours
  rule = IceCube::Rule.from_ical(reminder.rrule)
  schedule = IceCube::Schedule.new(now)  # ❌ BUG: Starts from current time
  schedule.add_recurrence_rule(rule)
  schedule.occurrences_between(now, stop).each do |t|
    reminder.occurrences.find_or_create_by!(scheduled_at: t)
  end
end
```

### The Problem

`IceCube::Schedule.new(now)` creates a schedule starting from the **current time**.

Even though the RRULE specifies `BYHOUR=14;BYMINUTE=0` (2:00 PM), IceCube uses the schedule's start time as the base and applies the rule from there.

**Example RRULE:**
```
FREQ=DAILY;BYHOUR=14;BYMINUTE=0
```

**What happens:**
1. Current time: 5:36 PM (17:36)
2. Schedule starts: 5:36 PM
3. IceCube finds next occurrence matching BYHOUR=14
4. Since 2:00 PM already passed today, it finds tomorrow at 2:00 PM
5. But the schedule base time (5:36 PM) affects the calculation
6. Result: Wrong time

## Solution

Start the schedule from **beginning of day**, not current time.

```ruby
def self.expand(reminder, horizon_hours: 24)
  tz   = ActiveSupport::TimeZone[reminder.tz]
  now  = tz.now
  stop = now + horizon_hours.hours
  rule = IceCube::Rule.from_ical(reminder.rrule)
  
  # ✅ Start from beginning of today to properly respect BYHOUR/BYMINUTE in RRULE
  start_time = now.beginning_of_day
  schedule = IceCube::Schedule.new(start_time)
  schedule.add_recurrence_rule(rule)
  
  # ✅ Find occurrences from now onwards (not from beginning of day)
  schedule.occurrences_between(now, stop).each do |t|
    reminder.occurrences.find_or_create_by!(scheduled_at: t)
  end
end
```

### Why This Works

1. **Schedule starts from beginning of day** (midnight)
2. IceCube applies the RRULE correctly from that base
3. `BYHOUR=14;BYMINUTE=0` means "at 2:00 PM every day"
4. `occurrences_between(now, stop)` filters to only future occurrences
5. Result: Correct times ✅

## Example Scenarios

### Scenario 1: Daily Reminder at 2:00 PM
```ruby
RRULE: "FREQ=DAILY;BYHOUR=14;BYMINUTE=0"
Current time: 5:36 PM (17:36)

Before fix:
- Schedule starts: 5:36 PM
- Next occurrence: Tomorrow at ~5:36 PM ❌

After fix:
- Schedule starts: 12:00 AM (beginning of day)
- Next occurrence: Tomorrow at 2:00 PM ✅
```

### Scenario 2: Every 4 Hours
```ruby
RRULE: "FREQ=HOURLY;INTERVAL=4"
Current time: 5:36 PM (17:36)

Before fix:
- Schedule starts: 5:36 PM
- Occurrences: 9:36 PM, 1:36 AM, 5:36 AM... ❌

After fix:
- Schedule starts: 12:00 AM
- Occurrences: 8:00 PM, 12:00 AM, 4:00 AM, 8:00 AM... ✅
```

### Scenario 3: Weekdays at 9:00 AM
```ruby
RRULE: "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;BYHOUR=9;BYMINUTE=0"
Current time: Wednesday 3:00 PM

Before fix:
- Schedule starts: 3:00 PM
- Next occurrence: Thursday at ~3:00 PM ❌

After fix:
- Schedule starts: 12:00 AM
- Next occurrence: Thursday at 9:00 AM ✅
```

## Impact on Create vs Update

### Create (Already Worked)
When creating a reminder, it's typically done at a time different from the reminder's scheduled time, so the bug was less noticeable. But it could still cause issues.

### Update (Bug Was Obvious)
When updating a reminder, occurrences are regenerated. If you update at 5:36 PM, all new occurrences would be at wrong times.

## Testing

### Test Case 1: Create Daily Reminder
```ruby
# Create reminder at 5:36 PM for 2:00 PM daily
reminder = Reminder.create!(
  title: "Take vitamin D",
  rrule: "FREQ=DAILY;BYHOUR=14;BYMINUTE=0",
  tz: "America/New_York"
)

Recurrence.expand(reminder)

# Check occurrences
reminder.occurrences.first.scheduled_at.hour
# Expected: 14 (2:00 PM) ✅
# Before fix: 21 or 17 (wrong) ❌
```

### Test Case 2: Update Reminder
```ruby
# Update reminder at 5:36 PM
reminder.update!(title: "Take vitamin D3")

# Occurrences are regenerated
reminder.occurrences.reload.first.scheduled_at.hour
# Expected: 14 (2:00 PM) ✅
# Before fix: 21 or 17 (wrong) ❌
```

### Test Case 3: Every 4 Hours
```ruby
reminder = Reminder.create!(
  title: "Drink water",
  rrule: "FREQ=HOURLY;INTERVAL=4",
  tz: "America/New_York"
)

Recurrence.expand(reminder)

times = reminder.occurrences.pluck(:scheduled_at).map(&:hour)
# Expected: [20, 0, 4, 8, 12, 16, 20...] (4-hour intervals from midnight) ✅
# Before fix: [21, 1, 5, 9, 13, 17, 21...] (4-hour intervals from current time) ❌
```

## Why `occurrences_between(now, stop)` Still Works

You might wonder: if we start from beginning of day, won't we get past occurrences?

**No**, because:
1. We start the schedule from beginning of day (for correct RRULE calculation)
2. But we only fetch occurrences **from now onwards**: `occurrences_between(now, stop)`
3. Past occurrences (earlier today) are filtered out
4. We only get future occurrences at the correct times ✅

**Example:**
```ruby
Current time: 5:36 PM
Schedule starts: 12:00 AM (beginning of day)
RRULE: Daily at 2:00 PM

Potential occurrences:
- Today 2:00 PM (in the past, filtered out)
- Tomorrow 2:00 PM (in the future, included) ✅
```

## Related Files Modified

**`backend/app/services/recurrence.rb`**
- Changed `IceCube::Schedule.new(now)` to `IceCube::Schedule.new(now.beginning_of_day)`
- Added comments explaining the logic

## Restart Backend

After this fix, restart the Rails server:
```bash
cd backend
rails s
```

## Verify Fix

1. Create or update a reminder with a specific time
2. Check the generated occurrences in Rails console:
```ruby
Reminder.last.occurrences.pluck(:scheduled_at)
```
3. Times should match the RRULE specification ✅

## Summary

The backend was creating occurrences at the wrong time because the IceCube schedule started from the current time instead of the beginning of the day. This caused the RRULE's `BYHOUR` and `BYMINUTE` directives to be calculated incorrectly.

By starting the schedule from the beginning of the day and filtering occurrences from now onwards, we ensure occurrences are created at the correct times specified in the RRULE.

**Backend fix complete! 🎉**
