#!/bin/bash
# Test script to verify POST magic link verification works

echo "🧪 Testing Magic Link POST Security"
echo "===================================="
echo ""

BASE_URL="http://localhost:5000"
TEST_EMAIL="test@example.com"

echo "Step 1: Generate a test token using Rails console"
echo "--------------------------------------------------"
echo "Generating signed token for $TEST_EMAIL..."
TOKEN=$(rails runner "
user = User.find_or_create_by!(email: '$TEST_EMAIL')
token = user.signed_id(purpose: :magic_login, expires_in: 30.minutes)
puts token
")
echo "Token generated: ${TOKEN:0:50}..."
echo ""

echo "Step 2: Test GET request (old method - token in URL)"
echo "-----------------------------------------------------"
echo "Testing: GET /magic/verify?token=..."
GET_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X GET "$BASE_URL/magic/verify?token=$TOKEN")
GET_HTTP_CODE=$(echo "$GET_RESPONSE" | grep "HTTP_CODE" | cut -d: -f2)
GET_BODY=$(echo "$GET_RESPONSE" | grep -v "HTTP_CODE")
echo "HTTP Status: $GET_HTTP_CODE"
echo "Response: $GET_BODY"
echo ""

echo "Step 3: Generate another token for POST test"
echo "---------------------------------------------"
echo "Generating new signed token..."
TOKEN2=$(rails runner "
user = User.find_or_create_by!(email: '$TEST_EMAIL')
token = user.signed_id(purpose: :magic_login, expires_in: 30.minutes)
puts token
")
echo "Token generated: ${TOKEN2:0:50}..."
echo ""

echo "Step 4: Test POST request (new method - token in body)"
echo "-------------------------------------------------------"
echo "Testing: POST /magic/verify with JSON body"
POST_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "$BASE_URL/magic/verify" \
  -H "Content-Type: application/json" \
  -d "{\"token\":\"$TOKEN2\"}")
POST_HTTP_CODE=$(echo "$POST_RESPONSE" | grep "HTTP_CODE" | cut -d: -f2)
POST_BODY=$(echo "$POST_RESPONSE" | grep -v "HTTP_CODE")
echo "HTTP Status: $POST_HTTP_CODE"
echo "Response: $POST_BODY"
echo ""

echo "📊 Summary"
echo "=========="
echo "GET request:  HTTP $GET_HTTP_CODE"
echo "POST request: HTTP $POST_HTTP_CODE"
echo ""

if [ "$GET_HTTP_CODE" = "200" ] && [ "$POST_HTTP_CODE" = "200" ]; then
    echo "✅ Both methods work!"
    echo "   - GET: Backward compatible (email links)"
    echo "   - POST: More secure (token not in URL)"
elif [ "$POST_HTTP_CODE" = "200" ]; then
    echo "✅ POST method works!"
    echo "⚠️  GET method failed (might be token already used)"
else
    echo "❌ Tests failed"
    echo "   Check Rails logs for errors"
fi

echo ""
echo "🔍 Security improvement:"
echo "   - POST keeps token out of server logs"
echo "   - POST keeps token out of browser history"
echo "   - POST keeps token out of referer headers"
