#!/bin/bash
# Test script to verify magic link generation for different client types

echo "🧪 Testing Magic Link Generation"
echo "================================"
echo ""

BASE_URL="http://localhost:5000"
TEST_EMAIL="test@example.com"

echo "📧 Test Email: $TEST_EMAIL"
echo ""

# Test 1: Voice Web Client (should get /client/ link)
echo "Test 1: Voice Web Client Login"
echo "-------------------------------"
echo "Making request with client=web parameter..."
RESPONSE1=$(curl -s -X GET "$BASE_URL/magic/request?email=$TEST_EMAIL&client=web")
echo "Response: $RESPONSE1"
echo ""
echo "✅ Check your email (letter_opener should open in browser)"
echo "   Expected: Magic link should point to /client/?token=..."
echo ""
read -p "Press Enter to continue to next test..."
echo ""

# Test 2: Dashboard/API Login (should get /magic/verify link)
echo "Test 2: Dashboard/API Login"
echo "----------------------------"
echo "Making request WITHOUT client parameter..."
RESPONSE2=$(curl -s -X GET "$BASE_URL/magic/request?email=$TEST_EMAIL")
echo "Response: $RESPONSE2"
echo ""
echo "✅ Check your email (letter_opener should open in browser)"
echo "   Expected: Magic link should point to /magic/verify?token=..."
echo ""
read -p "Press Enter to continue to next test..."
echo ""

# Test 3: Explicit API request
echo "Test 3: API Request (macOS app simulation)"
echo "-------------------------------------------"
echo "Making request with no client parameter (API default)..."
RESPONSE3=$(curl -s -X GET "$BASE_URL/magic/request?email=$TEST_EMAIL")
echo "Response: $RESPONSE3"
echo ""
echo "✅ Check your email"
echo "   Expected: Magic link should point to /magic/verify?token=..."
echo ""

echo ""
echo "📊 Summary"
echo "=========="
echo "Test 1 (client=web):     Should use /client/ path"
echo "Test 2 (no param):       Should use /magic/verify path"
echo "Test 3 (API):            Should use /magic/verify path"
echo ""
echo "🔍 Check Rails logs for details:"
echo "   tail -f log/development.log | grep -A 5 'Magic link'"
echo ""
echo "✅ All tests completed!"
