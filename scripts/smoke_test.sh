#!/usr/bin/env bash
# Post-deploy check: is the live site up and is the API answering?
# Usage: scripts/smoke_test.sh <site_url> <health_url>
# The health endpoint only reads the counter, so a deploy never adds a visit.
set -euo pipefail

SITE_URL="${1:?usage: smoke_test.sh <site_url> <health_url>}"
HEALTH_URL="${2:?usage: smoke_test.sh <site_url> <health_url>}"

# CloudFront can take a moment after an apply, so retry a few times.
CURL=(curl --silent --show-error --fail --location --max-time 20 --retry 5 --retry-delay 5 --retry-all-errors)

echo "Checking site: $SITE_URL"
page=$("${CURL[@]}" "$SITE_URL")
if ! grep -q "Zihao Zhou" <<<"$page"; then
  echo "FAIL: page loaded but does not contain the expected content" >&2
  exit 1
fi
echo "OK: site returns 200 with the expected content"

echo "Checking API health: $HEALTH_URL"
count=$("${CURL[@]}" "$HEALTH_URL" | jq -er 'select(.status == "ok") | .count | select(type == "number" and . >= 1)')
echo "OK: API is healthy, count=$count"
