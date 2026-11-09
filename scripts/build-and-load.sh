#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
docker build -t istio-lab/frontend:1.0 apps/frontend
kind load docker-image istio-lab/frontend:1.0 --name istio-lab
