# Scenario 05 — Traffic routing

## Goal

Understand why Kubernetes Service routing is not the same as Istio application-aware routing.

## Normal Kubernetes

The catalog Service selects Pods with:

```text
app: catalog
```

So:

```text
frontend
   |
   v
catalog Service
   |
   +----> catalog-v1
   |
   +----> catalog-v2
```

Kubernetes can select endpoints, but the Service itself does not express an HTTP rule such as:

> "Send beta users to v2."

## Istio DestinationRule

A DestinationRule creates named subsets based on labels:

```text
catalog
  |
  +-- subset v1
  |
  +-- subset v2
```

Apply:

```bash
kubectl apply -f istio/10-catalog-destination-rule.yaml
```

## Istio VirtualService

Now define routing:

```text
frontend
   |
   v
VirtualService
   |
   +---- 80% ---> v1
   |
   +---- 20% ---> v2
```

Apply:

```bash
kubectl apply -f istio/11-catalog-canary-virtual-service.yaml
```

Test:

```bash
for i in {1..50}; do curl -s http://localhost:8080/call/catalog; done
```

Do not expect exactly 40/10 in a 50-request sample. Weighted routing is statistical.

## Header routing

Now add:

```text
x-release: beta
        |
        v
      v2
```

Apply:

```bash
kubectl apply -f istio/12-catalog-header-route.yaml
curl -s -H 'x-release: beta' http://localhost:8080/call/catalog
```

The application does not need to implement the routing decision itself.

## Lesson

Kubernetes gives us service discovery and endpoint selection.

Istio gives us programmable traffic policy at the proxy layer.
