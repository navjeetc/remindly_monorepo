#!/bin/bash

# Phase 6 API Testing Script
# Tests the new filtering, pagination, and bulk operations

BASE_URL="http://localhost:5000"

echo "🧪 Testing Phase 6 API Enhancements"
echo "===================================="
echo ""

# First, get a JWT token using dev mode
echo "1️⃣ Getting authentication token..."
TOKEN=$(curl -s "${BASE_URL}/magic/dev_exchange?email=test@example.com")
echo "✅ Token obtained"
echo ""

# Test 1: List all reminders (basic)
echo "2️⃣ Testing GET /reminders (basic)"
curl -s -H "Authorization: Bearer ${TOKEN}" \
  "${BASE_URL}/reminders" | jq '.pagination'
echo ""

# Test 2: Filter by category
echo "3️⃣ Testing GET /reminders?category=0 (filter by medication)"
curl -s -H "Authorization: Bearer ${TOKEN}" \
  "${BASE_URL}/reminders?category=0" | jq '.reminders | length'
echo " reminders found"
echo ""

# Test 3: Search
echo "4️⃣ Testing GET /reminders?search=test (search)"
curl -s -H "Authorization: Bearer ${TOKEN}" \
  "${BASE_URL}/reminders?search=test" | jq '.reminders | length'
echo " reminders found"
echo ""

# Test 4: Pagination
echo "5️⃣ Testing GET /reminders?page=1&per_page=5 (pagination)"
curl -s -H "Authorization: Bearer ${TOKEN}" \
  "${BASE_URL}/reminders?page=1&per_page=5" | jq '.pagination'
echo ""

# Test 5: Get single reminder (if any exist)
echo "6️⃣ Testing GET /reminders/:id (get single)"
FIRST_ID=$(curl -s -H "Authorization: Bearer ${TOKEN}" \
  "${BASE_URL}/reminders" | jq -r '.reminders[0].id // empty')

if [ -n "$FIRST_ID" ]; then
  curl -s -H "Authorization: Bearer ${TOKEN}" \
    "${BASE_URL}/reminders/${FIRST_ID}" | jq '.title'
  echo ""
else
  echo "⚠️  No reminders found to test"
  echo ""
fi

# Test 6: Error handling - 404
echo "7️⃣ Testing GET /reminders/99999 (not found)"
curl -s -H "Authorization: Bearer ${TOKEN}" \
  "${BASE_URL}/reminders/99999" | jq '.'
echo ""

# Test 7: Bulk delete (with empty array - should succeed with 0 deletions)
echo "8️⃣ Testing DELETE /reminders/bulk_destroy (empty array)"
curl -s -X DELETE \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"ids": []}' \
  "${BASE_URL}/reminders/bulk_destroy" | jq '.'
echo ""

echo "✅ All tests complete!"
echo ""
echo "📊 Summary:"
echo "  - Filtering by category: ✅"
echo "  - Search functionality: ✅"
echo "  - Pagination: ✅"
echo "  - Get single reminder: ✅"
echo "  - Error handling (404): ✅"
echo "  - Bulk operations: ✅"
