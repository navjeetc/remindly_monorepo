#!/bin/zsh

echo "🧪 Testing Remindly Backend API"
echo "================================"
echo ""

# Check if server is running
echo "Checking if server is running on localhost:3000..."
if ! curl -s http://localhost:3000/up > /dev/null 2>&1; then
    echo "❌ Server is not running!"
    echo "Please start the server first with:"
    echo "  cd backend && bin/rails s"
    exit 1
fi
echo "✓ Server is running"
echo ""

# Step 1: Get JWT token
echo "Step 1: Getting JWT token for senior@example.com..."
JWT=$(curl -s "http://localhost:3000/magic/dev_exchange?email=senior@example.com")

if [ -z "$JWT" ]; then
    echo "❌ Failed to get JWT token"
    exit 1
fi

echo "✓ JWT Token received: ${JWT:0:50}..."
echo ""

# Step 2: Get today's reminders
echo "Step 2: Fetching today's reminders..."
RESPONSE=$(curl -s -H "Authorization: Bearer $JWT" http://localhost:3000/reminders/today)
echo "Response: $RESPONSE"
echo ""

# Step 3: Create a reminder
echo "Step 3: Creating a new reminder..."
CREATE_RESPONSE=$(curl -s -X POST http://localhost:3000/reminders \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Take medication",
    "notes": "Blood pressure pills",
    "rrule": "FREQ=DAILY;BYHOUR=9",
    "tz": "America/New_York",
    "category": "medication"
  }')

echo "Response: $CREATE_RESPONSE"
echo ""

# Step 4: Get today's reminders again
echo "Step 4: Fetching today's reminders again..."
RESPONSE2=$(curl -s -H "Authorization: Bearer $JWT" http://localhost:3000/reminders/today)
echo "Response: $RESPONSE2"
echo ""

# Step 5: Create hydration reminder
echo "Step 5: Creating a hydration reminder..."
HYDRATION_RESPONSE=$(curl -s -X POST http://localhost:3000/reminders \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Drink water",
    "notes": "Stay hydrated!",
    "rrule": "FREQ=DAILY;BYHOUR=8,12,16,20",
    "tz": "America/New_York",
    "category": "hydration"
  }')

echo "Response: $HYDRATION_RESPONSE"
echo ""

echo "================================"
echo "✅ API Testing Complete!"
echo "================================"
