#!/usr/bin/env bash
set -euo pipefail

# End-to-end smoke test for the TrackIT platform.
# Usage: KONG_URL=http://<manager-ip>:8000 bash scripts/smoke-test.sh
# Defaults to http://localhost:8000 if KONG_URL is not set.

KONG_URL="${KONG_URL:-http://localhost:8000}"
STEP=0
FAILED=false

pass() { echo "  ✓ Step $STEP: $*"; }
fail() { echo "  ✗ Step $STEP FAILED: $*"; FAILED=true; exit 1; }

require_cmd() {
    command -v "$1" > /dev/null 2>&1 || { echo "ERROR: '$1' is required but not installed."; exit 1; }
}

require_cmd curl
require_cmd jq

echo "==> TrackIT smoke test against $KONG_URL"
echo ""

# Generate a unique user for this test run
TIMESTAMP=$(date +%s)
USERNAME="smoketest_${TIMESTAMP}"
EMAIL="smoke_${TIMESTAMP}@trackit.test"
PASSWORD="SmokeTest1!"

# ─── Step 1: Register ────────────────────────────────────────────────────────
STEP=1
echo "--- Step $STEP: POST /api/v1/auth/register"
REGISTER_RESP=$(curl -sf -w "\n%{http_code}" \
    -X POST "$KONG_URL/api/v1/auth/register" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$USERNAME\",\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" \
    || fail "curl failed")
HTTP_CODE=$(echo "$REGISTER_RESP" | tail -1)
[[ "$HTTP_CODE" == "201" ]] || fail "Expected 201, got $HTTP_CODE. Body: $(echo "$REGISTER_RESP" | head -1)"
pass "Registered user $USERNAME (201)"

# ─── Step 2: Login ───────────────────────────────────────────────────────────
STEP=2
echo "--- Step $STEP: POST /api/v1/auth/login"
LOGIN_RESP=$(curl -sf -w "\n%{http_code}" \
    -X POST "$KONG_URL/api/v1/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}" \
    || fail "curl failed")
HTTP_CODE=$(echo "$LOGIN_RESP" | tail -1)
[[ "$HTTP_CODE" == "200" ]] || fail "Expected 200, got $HTTP_CODE"
TOKEN=$(echo "$LOGIN_RESP" | head -1 | jq -r '.tokens.accessToken // empty')
[[ -n "$TOKEN" ]] || fail "Could not extract token from login response: $(echo "$LOGIN_RESP" | head -1)"
REFRESH_TOKEN=$(echo "$LOGIN_RESP" | head -1 | jq -r '.tokens.refreshToken // empty')
pass "Login OK, token extracted"

AUTH_HEADER="Authorization: Bearer $TOKEN"

# ─── Step 3: Validate token ──────────────────────────────────────────────────
STEP=3
echo "--- Step $STEP: POST /api/v1/auth/validate"
VALIDATE_RESP=$(curl -sf -w "\n%{http_code}" \
    -X POST "$KONG_URL/api/v1/auth/validate" \
    -H "Content-Type: application/json" \
    -d "{\"token\":\"$TOKEN\"}" \
    || fail "curl failed")
HTTP_CODE=$(echo "$VALIDATE_RESP" | tail -1)
[[ "$HTTP_CODE" == "200" ]] || fail "Expected 200, got $HTTP_CODE"
VALID=$(echo "$VALIDATE_RESP" | head -1 | jq -r '.valid')
[[ "$VALID" == "true" ]] || fail "Token reported as invalid: $(echo "$VALIDATE_RESP" | head -1)"
pass "Token valid"

# ─── Step 4: List exercises ──────────────────────────────────────────────────
STEP=4
echo "--- Step $STEP: GET /api/v1/exercises"
EXERCISES_RESP=$(curl -sf -w "\n%{http_code}" \
    "$KONG_URL/api/v1/exercises" \
    -H "$AUTH_HEADER" \
    || fail "curl failed")
HTTP_CODE=$(echo "$EXERCISES_RESP" | tail -1)
[[ "$HTTP_CODE" == "200" ]] || fail "Expected 200, got $HTTP_CODE"
COUNT=$(echo "$EXERCISES_RESP" | head -1 | jq '. | if type == "array" then length elif .content then .content | length else 0 end')
[[ "$COUNT" -ge 1 ]] || fail "Expected at least 1 exercise, got $COUNT"
pass "Got $COUNT exercises"

# ─── Step 5: Create a workout ────────────────────────────────────────────────
STEP=5
echo "--- Step $STEP: POST /api/v1/workouts"
EXERCISE_ID=$(echo "$EXERCISES_RESP" | head -1 | jq -r 'if type == "array" then .[0].id elif .content then .content[0].id else empty end')
[[ -n "$EXERCISE_ID" ]] || { echo "  (no exercise id found, skipping workout creation)"; EXERCISE_ID="1"; }

WORKOUT_BODY="{\"name\":\"Smoke Test Workout\",\"exercises\":[{\"exerciseId\":$EXERCISE_ID,\"position\":0,\"targetSets\":3,\"targetReps\":10}]}"
WORKOUT_RESP=$(curl -sf -w "\n%{http_code}" \
    -X POST "$KONG_URL/api/v1/workouts" \
    -H "$AUTH_HEADER" \
    -H "Content-Type: application/json" \
    -d "$WORKOUT_BODY" \
    || fail "curl failed")
HTTP_CODE=$(echo "$WORKOUT_RESP" | tail -1)
[[ "$HTTP_CODE" == "201" ]] || fail "Expected 201, got $HTTP_CODE. Body: $(echo "$WORKOUT_RESP" | head -1)"
pass "Created workout (201)"

# ─── Step 6: List workouts ───────────────────────────────────────────────────
STEP=6
echo "--- Step $STEP: GET /api/v1/workouts"
WORKOUTS_RESP=$(curl -sf -w "\n%{http_code}" \
    "$KONG_URL/api/v1/workouts" \
    -H "$AUTH_HEADER" \
    || fail "curl failed")
HTTP_CODE=$(echo "$WORKOUTS_RESP" | tail -1)
[[ "$HTTP_CODE" == "200" ]] || fail "Expected 200, got $HTTP_CODE"
WC=$(echo "$WORKOUTS_RESP" | head -1 | jq '. | if type == "array" then length elif .content then .content | length else 0 end')
[[ "$WC" -ge 1 ]] || fail "Expected at least 1 workout, got $WC"
pass "Got $WC workout(s)"

# ─── Step 7: Create a meal ───────────────────────────────────────────────────
STEP=7
echo "--- Step $STEP: POST /api/v1/meals"
TODAY=$(date -u +%Y-%m-%dT%H:%M:%SZ)
MEAL_BODY="{\"mealType\":\"LUNCH\",\"consumedAt\":\"$TODAY\",\"items\":[]}"
MEAL_RESP=$(curl -sf -w "\n%{http_code}" \
    -X POST "$KONG_URL/api/v1/meals" \
    -H "$AUTH_HEADER" \
    -H "Content-Type: application/json" \
    -d "$MEAL_BODY" \
    || fail "curl failed")
HTTP_CODE=$(echo "$MEAL_RESP" | tail -1)
[[ "$HTTP_CODE" == "201" ]] || fail "Expected 201, got $HTTP_CODE. Body: $(echo "$MEAL_RESP" | head -1)"
pass "Created meal (201)"

# ─── Step 8: Daily nutrition stats ───────────────────────────────────────────
TODAY_DATE=$(date -u +%Y-%m-%d)
STEP=8
echo "--- Step $STEP: GET /api/v1/stats/nutrition/daily?date=$TODAY_DATE"
STATS_RESP=$(curl -sf -w "\n%{http_code}" \
    "$KONG_URL/api/v1/stats/nutrition/daily?date=$TODAY_DATE" \
    -H "$AUTH_HEADER" \
    || fail "curl failed")
HTTP_CODE=$(echo "$STATS_RESP" | tail -1)
[[ "$HTTP_CODE" == "200" ]] || fail "Expected 200, got $HTTP_CODE"
pass "Nutrition stats returned (200)"

# ─── Step 9: Dashboard ───────────────────────────────────────────────────────
STEP=9
echo "--- Step $STEP: GET /api/v1/dashboard"
DASH_RESP=$(curl -sf -w "\n%{http_code}" \
    "$KONG_URL/api/v1/dashboard" \
    -H "$AUTH_HEADER" \
    || fail "curl failed")
HTTP_CODE=$(echo "$DASH_RESP" | tail -1)
[[ "$HTTP_CODE" == "200" ]] || fail "Expected 200, got $HTTP_CODE"
pass "Dashboard returned (200)"

# ─── Result ──────────────────────────────────────────────────────────────────
echo ""
if $FAILED; then
    echo "❌ Smoke test FAILED"
    exit 1
else
    echo "✅ Smoke test passed (all $STEP steps)"
fi
