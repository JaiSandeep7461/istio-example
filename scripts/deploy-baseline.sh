#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
kubectl apply -f base/namespace.yaml
kubectl apply -f base/catalog.yaml
kubectl apply -f base/reviews.yaml
kubectl apply -f base/frontend.yaml
kubectl -n shop rollout status deployment/catalog-v1 --timeout=120s
kubectl -n shop rollout status deployment/catalog-v2 --timeout=120s
kubectl -n shop rollout status deployment/reviews --timeout=120s
kubectl -n shop rollout status deployment/frontend --timeout=120s
