#!/usr/bin/env bash
set -euo pipefail

if ! command -v istioctl >/dev/null 2>&1; then
  echo "istioctl not found. Install Istio 1.31.4 CLI from:"
  echo "https://istio.io/latest/docs/setup/getting-started/"
  exit 1
fi

CLI_VERSION="$(istioctl version --remote=false | head -n1)"
if ! grep -Eq '1\.31\.' <<<"$CLI_VERSION"; then
  echo "This lab targets Istio 1.31.x. Detected: $CLI_VERSION"
  exit 1
fi

istioctl install --set profile=demo -y
kubectl rollout status deployment/istiod -n istio-system --timeout=180s
kubectl rollout status deployment/istio-ingressgateway -n istio-system --timeout=180s
echo "Istio installation completed with $CLI_VERSION."
