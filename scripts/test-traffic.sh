#!/usr/bin/env bash
set -euo pipefail
URL="${URL:-http://localhost:8080}"
curl -fsS "$URL/"; echo
for i in $(seq 1 20); do curl -fsS "$URL/call/catalog" || true; done
echo
curl -fsS -H 'x-release: beta' "$URL/call/catalog" || true
echo
curl -i "$URL/call/reviews" || true
