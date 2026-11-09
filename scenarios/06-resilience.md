# Scenario 06 — Resilience

## Goal

See what happens when a downstream service becomes slow, and compare application-only handling with Istio traffic policy.

## Normal Kubernetes

Without Istio:

```text
frontend
   |
   v
reviews
   |
   X
  slow
```

The frontend application must decide:

- how long to wait
- whether to retry
- how many retries
- how to back off
- how to simulate failures during testing

## Istio

Istio can express these behaviors in traffic policy:

```text
frontend
   |
   v
Envoy
   |
   +-- timeout
   +-- retry
   +-- fault injection
   |
   v
reviews
```

Apply the scenario:

```bash
kubectl apply -f istio/20-reviews-resilience.yaml
```

Generate traffic:

```for i in {1..30}; do curl -i http://localhost:8080/call/reviews; done
```

The configuration intentionally injects a delay into some requests so the timeout/retry behavior is observable.

Inspect the configuration:

```bash
istioctl analyze -n shop
```

Remove the fault after the experiment:

```bash
kubectl delete -f istio/20-reviews-resilience.yaml
```

## Lesson

Istio does not replace application resilience logic in every case. It gives the platform a place to enforce or experiment with common network-level traffic behavior without changing application code.
