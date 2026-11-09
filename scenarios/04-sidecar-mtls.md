# Scenario 04 — Sidecar mode and mTLS

## Goal

First see normal application traffic, then see what changes when Envoy sidecars and mTLS are introduced.

## Normal Kubernetes

Without Istio:

```text
frontend application
       |
       | HTTP
       v
catalog Service
       |
       v
catalog application
```

The applications are responsible for any application-level TLS they need.

## Install Istio sidecar mode

```bash
./scripts/install-istio.sh
./scripts/enable-mesh.sh
kubectl -n shop get pods
```

Inspect containers:

```bash
POD=$(kubectl -n shop get pod -l app=frontend -o jsonpath='{.items[0].metadata.name}')
kubectl -n shop get pod "$POD" -o jsonpath='{.spec.containers[*].name}{"\n"}'
istioctl proxy-status
```

The participating Pod contains the application plus the Istio proxy.

## Sidecar traffic path

```text
frontend application
       |
       v
frontend Envoy
       |
       | mesh traffic
       v
catalog Envoy
       |
       v
catalog application
```

The application does not have to know that the proxy is handling mesh traffic.

## Enable strict mTLS

```bash
kubectl apply -f istio/30-peer-authentication-strict.yaml
```

Now the important path is:

```text
frontend application
       |
       | local application traffic
       v
frontend Envoy
       |
       | ===== mTLS encrypted =====
       v
catalog Envoy
       |
       | local application traffic
       v
catalog application
```

The application containers are not themselves performing the mesh mTLS handshake.

## Verify certificates

```bash
istioctl proxy-config secret "$POD" -n shop
istioctl proxy-config clusters "$POD" -n shop
```

## Prove encryption

Run traffic:

```bash
kubectl -n shop port-forward svc/frontend 8080:8080
curl -s http://localhost:8080/call/catalog
```

For a deeper lab, capture traffic on the KIND node while generating requests:

```bash
docker exec -it istio-lab-control-plane sh
tcpdump -i any -nn -A tcp
```

Do not make the mistake of saying "I saw HTTP somewhere, therefore mTLS is broken." There are multiple network hops. The relevant proxy-to-proxy hop is encrypted; traffic before interception and after decryption is a different hop.

## Core lesson

mTLS gives:

- workload authentication
- encrypted proxy-to-proxy transport
- workload identity

It does not mean the application code suddenly becomes a TLS application.
