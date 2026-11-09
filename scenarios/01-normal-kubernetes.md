# Scenario 01 — Normal Kubernetes traffic

## Goal

Understand what Kubernetes does **before Istio exists**.

## Traffic

```text
frontend Pod
    |
    | HTTP request
    v
catalog Service
    |
    | endpoint selection
    v
catalog Pod
```

The application calls:

```text
http://catalog:5678/
```

Kubernetes DNS resolves `catalog` to the Service. The Service provides a stable virtual endpoint while the actual catalog Pods can change.

## Run

```bash
./scripts/deploy-baseline.sh
kubectl -n shop get pods,svc,endpoints -o wide
kubectl -n shop port-forward svc/frontend 8080:8080
```

Then:

```bash
curl -s http://localhost:8080/call/catalog
curl -s http://localhost:8080/call/reviews
```

## What is happening?

There is no Envoy and no Istio control plane in the request path.

```text
frontend application
        |
        | HTTP
        v
Kubernetes Service
        |
        v
catalog Pod
        |
        v
catalog application
```

Kubernetes gives us connectivity and service discovery. It does not automatically provide application-aware HTTP routing such as "beta users go to v2".

## Observe the Service

```bash
kubectl -n shop get svc catalog
kubectl -n shop get endpoints catalog
kubectl -n shop get pods -l app=catalog -L version
```

## The problem we will solve later

Suppose we want:

- 80% traffic to v1
- 20% traffic to v2
- `x-release: beta` always to v2
- retries and timeouts
- workload-to-workload mTLS
- identity-aware authorization

Kubernetes Service alone is not designed to express those application-level policies.

That is the point at which we introduce Istio.
