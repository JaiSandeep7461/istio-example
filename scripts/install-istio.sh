#!/usr/bin/env bash
set -euo pipefail
if ! command -v istioctl >/dev/null 2>&1; then
  echo "istioctl not found. Install CLI from https://istio.io/latest/docs/setup/getting-started/"
  exit 1
fi
istioctl install --set profile=demo -y
kubectl rollout status deployment/istiod -n istio-system --timeout=180s
kubectl rollout status deployment/istio-ingressgateway -n istio-system --timeout=180s
