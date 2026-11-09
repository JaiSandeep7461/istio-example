#!/usr/bin/env bash
set -euo pipefail
kubectl label namespace shop istio-injection=enabled --overwrite
kubectl -n shop rollout restart deployment
kubectl -n shop rollout status deployment/frontend --timeout=120s
kubectl -n shop rollout status deployment/catalog-v1 --timeout=120s
kubectl -n shop rollout status deployment/catalog-v2 --timeout=120s
kubectl -n shop rollout status deployment/reviews --timeout=120s
