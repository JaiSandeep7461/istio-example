# Scenario 08 — Ambient mode

## Goal

Understand ambient mode by first identifying the problem with the sidecar model.

## Sidecar model

In sidecar mode every participating Pod gets an Envoy proxy:

```text
+---------------------- Pod ----------------------+
|                                                  |
|  Application              Envoy                  |
|                            |                     |
+----------------------------|---------------------+
                             |
                             v
                         mesh traffic
```

For many workloads, this means another container per Pod and the associated CPU/memory/configuration overhead.

## Ambient model

Ambient removes the per-Pod Envoy sidecar.

```text
Node
+------------------------------------------------+
|                                                |
|  frontend Pod          catalog Pod             |
|       |                     |                  |
|       +----------+----------+                  |
|                  |                             |
|               ztunnel                          |
+------------------------------------------------+
```

ztunnel is a node-level L4 proxy.

## Create a fresh cluster

```bash
./scripts/cleanup.sh
kind create cluster --name istio-ambient-lab --config kind/cluster.yaml
istioctl install --set profile=ambient -y
```

Deploy the example:

```bash
kubectl apply -f ambient/namespace.yaml
kubectl apply -f ambient/apps.yaml
kubectl label namespace ambient-shop istio.io/dataplane-mode=ambient
```

Inspect:

```bash
kubectl -n ambient-shop get pods
kubectl -n ambient-shop get pod -l app=frontend -o jsonpath='{.items[0].spec.containers[*].name}{"\n"}'
```

There should be no `istio-proxy` container in the application Pod.

## Generate traffic

```bash
kubectl -n ambient-shop exec deploy/frontend -- wget -qO- http://catalog:5678/
```

Inspect ztunnel:

```bash
istioctl ztunnel-config workloads
```

The path is approximately:

```text
frontend Pod
    |
    v
source-node ztunnel
    |
    | ===== HBONE + mTLS =====
    v
destination-node ztunnel
    |
    v
catalog Pod
```

## Add a waypoint

ztunnel is primarily L4. For L7 behavior, deploy a waypoint.

```bash
kubectl apply -f ambient/waypoint.yaml
kubectl label namespace ambient-shop istio.io/use-waypoint=ambient-waypoint --overwrite
kubectl get gateway -n ambient-shop
kubectl get pods -n ambient-shop
```

The path becomes:

```text
frontend Pod
    |
    v
ztunnel
    |
    v
waypoint Envoy
    |
    v
destination ztunnel
    |
    v
catalog Pod
```

This is why the statement "ambient means no Envoy" is inaccurate.

The accurate statement is:

> Ambient removes the per-Pod Envoy sidecar. Envoy can still exist as a waypoint when L7 processing is required.

## Sidecar vs ambient

| Area | Sidecar | Ambient |
|---|---|---|
| Proxy placement | Envoy in each Pod | ztunnel on each node |
| L4 security | Envoy | ztunnel |
| L7 features | Sidecar Envoy | waypoint Envoy |
| App Pod extra proxy | Yes | No |
| mTLS | Yes | Yes |
| Main trade-off | per-Pod proxy overhead | additional node/waypoint architecture |

## Lesson

Ambient is not a different purpose from Istio. It is a different data-plane architecture for providing mesh capabilities.
