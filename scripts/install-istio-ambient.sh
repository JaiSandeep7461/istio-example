#!/usr/bin/env bash
set -euo pipefail
if ! command -v istioctl >/dev/null 2>&1; then
  echo "istioctl not found. Install Istio 1.31.4 first."
  exit 1
fi
istioctl install --set profile=ambient -y
kubectl rollout status daemonset/ztunnel -n istio-system --timeout=180s
kubectl rollout status deployment/istiod -n istio-system --timeout=180s
