# Istio on KIND — Scenario-First Service Mesh Lab

This repository teaches Istio **from the Kubernetes networking problem first**, instead of starting with Istio terminology.

The learning pattern for every topic is:

1. **Run normal Kubernetes without Istio**
2. **Observe the traffic flow**
3. **Identify the limitation/problem**
4. **Introduce Istio**
5. **Run the same request again**
6. **Compare the traffic path**
7. **Prove what changed with kubectl / istioctl / logs / packet capture**

## Core mental model

Do not start with:

> "Istio is a service mesh."

Start with:

> **Kubernetes already provides connectivity. Istio is added when we need more control over that connectivity.**

Examples:

- Kubernetes Service → basic service discovery and endpoint load balancing
- Istio VirtualService → application-aware routing
- Istio DestinationRule → destination subsets and connection policies
- Istio ingress gateway → controlled mesh entry point
- Istio egress gateway → controlled mesh exit point
- Istio mTLS → workload-to-workload authentication and encrypted proxy-to-proxy transport
- Istio AuthorizationPolicy → identity-aware access control
- Istio sidecar → Envoy proxy in each participating Pod
- Istio ambient → ztunnel per node, with optional waypoint for L7 processing

## Scenario map

| Scenario | First without Istio | Then with Istio | Main question |
|---|---|---|---|
| 01 | Pod → Service → Pod | Sidecar → Sidecar | What does Istio add to normal service traffic? |
| 02 | Internet → Service → Pod | Ingress Gateway → Service | Why do we need an ingress gateway? |
| 03 | Pod → Node → Internet | Egress Gateway | How do we control outbound traffic? |
| 04 | Plain application traffic | Envoy + mTLS | Where is traffic actually encrypted? |
| 05 | Service selects Pods | VirtualService + DestinationRule | How do we do 80/20 and header routing? |
| 06 | Application handles failures | Istio retries/timeouts/fault injection | Can traffic behavior be controlled outside code? |
| 07 | Network connectivity only | AuthorizationPolicy | Can identity decide who may call whom? |
| 08 | Envoy in every Pod | ztunnel + optional waypoint | How does ambient change the data plane? |

---

# 1. Prerequisites

Install:

- Docker
- KIND
- kubectl
- curl
- Bash
- istioctl 1.31.x

The lab uses KIND node image `kindest/node:v1.35.0`.

Check:

```bash
docker version
kind version
kubectl version --client
istioctl version --remote=false
curl --version
```

---

# 2. Create the KIND cluster

```bash
kind create cluster --name istio-lab --config kind/cluster.yaml
kubectl cluster-info --context kind-istio-lab
kubectl get nodes -o wide
```

Build/load the frontend image:

```bash
chmod +x scripts/*.sh
./scripts/build-and-load.sh
```

---

# 3. Scenario 01 — Normal Kubernetes traffic

Read first:

- [Scenario 01 — Normal Kubernetes traffic](scenarios/01-normal-kubernetes.md)

Run:

```bash
./scripts/deploy-baseline.sh
kubectl -n shop get pods,svc,endpoints -o wide
kubectl -n shop port-forward svc/frontend 8080:8080
```

In another terminal:

```bash
curl -s http://localhost:8080/
curl -s http://localhost:8080/call/catalog
curl -s http://localhost:8080/call/reviews
```

The important flow is:

```text
frontend Pod
     |
     | DNS: catalog.shop.svc.cluster.local
     v
Kubernetes Service
     |
     v
catalog Pod
```

No Istio is involved.

---

# 4. Scenario 02 — Ingress

Read:

- [Scenario 02 — Ingress: normal Kubernetes first](scenarios/02-ingress.md)

First understand direct Kubernetes access:

```text
Client
  |
  v
Kubernetes Service
  |
  v
frontend Pod
```

Then introduce:

```text
Client
  |
  v
Istio Ingress Gateway
  |
  v
VirtualService
  |
  v
frontend Service
  |
  v
frontend Pod
```

Run:

```bash
kubectl apply -f istio/00-demo-gateway.yaml
kubectl -n istio-system port-forward svc/istio-ingressgateway 8081:80
curl -i -H 'Host: shop.local' http://localhost:8081/
```

The key lesson:

> **Ingress is a traffic direction. The ingress gateway is the controlled component used to receive traffic into the mesh.**

---

# 5. Scenario 03 — Egress

Read this one carefully:

- [Scenario 03 — Egress: normal Kubernetes first](scenarios/03-egress.md)

## Normal Kubernetes

A Pod can normally make an outbound request if the cluster/network allows it:

```text
Pod
 |
 v
Node / CNI / routing
 |
 v
NAT / network firewall
 |
 v
Internet
 |
 v
google.com
```

For example, from a curl-capable Pod:

```bash
kubectl run curl --rm -it --restart=Never --image=curlimages/curl:8.10.1 -- \
  curl -I --max-time 10 https://www.google.com
```

There is no Istio egress gateway here.

## Istio: blocking unknown external destinations

Istio can be configured with:

```text
outboundTrafficPolicy:
  mode: REGISTRY_ONLY
```

In this mode, unknown external destinations are blocked unless they are explicitly registered, for example with a ServiceEntry.

That gives us:

```text
Pod
 |
 v
Istio sidecar
 |
 +----> undeclared external host
 |              X
 |           BLOCKED
 |
 +----> declared ServiceEntry
                |
                v
             allowed
```

Important:

**REGISTRY_ONLY is not a complete outbound firewall.** Istio documents it as primarily a way to block unknown destinations at the proxy and detect missing ServiceEntries. For strong egress enforcement, combine an egress gateway with Kubernetes NetworkPolicy/firewall/network controls.

## Istio Egress Gateway

The controlled path becomes:

```text
Application
    |
    v
Source Envoy
    |
    v
Istio Egress Gateway
    |
    v
External service
```

The egress gateway gives you a dedicated, observable exit point where Istio policies and TLS origination can be applied.

Run the existing lab:

```bash
kubectl apply -f istio/40-egress-service-entry.yaml
kubectl apply -f istio/41-egress-gateway.yaml
kubectl apply -f istio/42-egress-routing.yaml

kubectl -n shop get serviceentry,gateway,virtualservice
curl http://localhost:8080/call/external
```

The exact security model is explained in the scenario document.

---

# 6. Scenario 04 — Sidecar mode and mTLS

Read:

- [Scenario 04 — Sidecar and mTLS](scenarios/04-sidecar-mtls.md)

Enable injection:

```bash
./scripts/install-istio.sh
./scripts/enable-mesh.sh
```

Inspect:

```bash
kubectl -n shop get pods
istioctl proxy-status
```

A participating Pod becomes conceptually:

```text
+--------------------------- Pod ---------------------------+
|                                                           |
|  Application  <---->  Envoy istio-proxy                  |
|                                                           |
+-----------------------------------------------------------+
```

With strict mTLS:

```text
frontend application
       |
       v
frontend Envoy
       |
       | ===== mTLS encrypted =====
       v
catalog Envoy
       |
       v
catalog application
```

The application does not need to implement this mesh mTLS itself.

Verify:

```bash
kubectl apply -f istio/30-peer-authentication-strict.yaml

POD=$(kubectl -n shop get pod -l app=frontend -o jsonpath='{.items[0].metadata.name}')
istioctl proxy-config secret "$POD" -n shop
istioctl proxy-config clusters "$POD" -n shop
```

The scenario also contains a packet-capture exercise.

---

# 7. Scenario 05 — Traffic routing

Read:

- [Scenario 05 — Routing](scenarios/05-routing.md)

First Kubernetes:

```text
frontend
   |
   v
catalog Service
   |
   +----> v1
   |
   +----> v2
```

Then Istio:

```text
frontend
   |
   v
VirtualService
   |
   +---- 80% ----> catalog v1
   |
   +---- 20% ----> catalog v2
```

And:

```text
x-release: beta
        |
        v
catalog v2
```

Run:

```bash
kubectl apply -f istio/10-catalog-destination-rule.yaml
kubectl apply -f istio/11-catalog-canary-virtual-service.yaml
kubectl apply -f istio/12-catalog-header-route.yaml

for i in {1..50}; do curl -s http://localhost:8080/call/catalog; done
curl -s -H 'x-release: beta' http://localhost:8080/call/catalog
```

---

# 8. Scenario 06 — Resilience

Read:

- [Scenario 06 — Resilience](scenarios/06-resilience.md)

Normal Kubernetes does not automatically give your application:

- HTTP retries
- request timeout policy
- fault injection
- application-aware traffic behavior

With Istio:

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

Run:

```bash
kubectl apply -f istio/20-reviews-resilience.yaml
for i in {1..30}; do curl -i http://localhost:8080/call/reviews; done
```

The lab deliberately injects latency so you can observe the behavior.

---

# 9. Scenario 07 — Authorization

Read:

- [Scenario 07 — Authorization](scenarios/07-authorization.md)

Normal Kubernetes networking answers:

> Can these two workloads communicate?

Istio AuthorizationPolicy can answer:

> **Which authenticated workload identity is allowed to perform this operation?**

Conceptually:

```text
frontend identity
       |
       v
AuthorizationPolicy
       |
       +---- GET catalog ----> ALLOW
       |
       +---- other operation -> DENY
```

Run:

```bash
kubectl apply -f istio/31-authorization-policy.yaml
kubectl -n shop get authorizationpolicy
curl -s http://localhost:8080/call/catalog
```

mTLS provides workload identity/authentication; AuthorizationPolicy uses that identity for authorization.

---

# 10. Scenario 08 — Ambient mode

Read:

- [Scenario 08 — Ambient mode](scenarios/08-ambient.md)

Sidecar:

```text
Pod
+----------------------+
| app + Envoy          |
+----------------------+
```

Ambient:

```text
Node
+--------------------------------+
| Pod            Pod             |
| app            app             |
|  |              |              |
|  +------ ztunnel ------------- |
+--------------------------------+
```

ztunnel provides the L4 secure overlay. It uses HBONE and mTLS for mesh traffic.

Run on a fresh cluster:

```bash
./scripts/cleanup.sh

kind create cluster --name istio-ambient-lab --config kind/cluster.yaml
istioctl install --set profile=ambient -y

kubectl apply -f ambient/namespace.yaml
kubectl apply -f ambient/apps.yaml
kubectl label namespace ambient-shop istio.io/dataplane-mode=ambient
```

Inspect:

```bash
kubectl -n ambient-shop get pods
kubectl -n ambient-shop get pod -l app=frontend -o jsonpath='{.items[0].spec.containers[*].name}{"\n"}'
istioctl ztunnel-config workloads
```

You should not see an `istio-proxy` sidecar inside the application Pod.

---

# 11. Ambient waypoint

Ambient ztunnel is primarily L4.

For L7 processing, use a waypoint:

```text
Application
    |
    v
ztunnel
    |
    v
Waypoint Envoy
    |
    v
destination ztunnel
    |
    v
Application
```

Run:

```bash
kubectl apply -f ambient/waypoint.yaml
kubectl label namespace ambient-shop istio.io/use-waypoint=ambient-waypoint --overwrite
kubectl get gateway -n ambient-shop
kubectl get pods -n ambient-shop
```

This is why saying **"ambient means there is no Envoy"** is wrong.

The accurate statement is:

> Ambient removes the per-Pod Envoy sidecar. Envoy can still be used as a waypoint for L7 functionality.

---

# 12. The complete mental model

After completing all scenarios, think about Istio like this:

```text
                         INGRESS
                            |
                            v
                    Istio Ingress Gateway
                            |
                            v
                       Application
                            |
                            v
                  +-------------------+
                  |   Istio data      |
                  |      plane        |
                  +-------------------+
                     |       |      |
                     v       v      v
                  Routing  mTLS   AuthZ
                     |       |      |
                     v       v      v
                  Services / Workloads
                            |
                            v
                         EGRESS
                            |
                            v
                    Egress Gateway
                            |
                            v
                      Internet/API
```

And the data-plane choices are:

```text
Sidecar mode
Application + Envoy per Pod

Ambient mode
Application Pod
      +
node-level ztunnel
      +
optional waypoint Envoy for L7
```

---

# 13. Important distinction

Do not mix these concepts:

**Ingress** = direction of traffic entering the mesh.

**Ingress Gateway** = proxy/entry point used to handle that traffic.

**Egress** = direction of traffic leaving the mesh.

**Egress Gateway** = dedicated proxy/exit point used to control that traffic.

**Gateway resource** = configuration describing listeners/edge behavior.

**VirtualService** = routing rules.

**ServiceEntry** = tells Istio about an external service.

**REGISTRY_ONLY** = blocks unknown destinations at the Istio proxy; it is not a complete firewall.

**NetworkPolicy/firewall** = network-level enforcement and useful defense in depth.

---

# 14. Recommended learning order

Do not jump directly to advanced YAML.

Follow this order:

1. Normal Kubernetes Pod-to-Pod traffic
2. Kubernetes Service
3. Normal ingress
4. Istio ingress
5. Normal egress
6. Istio egress
7. Sidecar
8. mTLS and packet capture
9. VirtualService
10. DestinationRule
11. Resilience
12. AuthorizationPolicy
13. Ambient
14. Waypoint
15. Sidecar vs ambient comparison

For each scenario, explain the **normal Kubernetes traffic first**. Only then introduce the Istio object that changes the behavior.

## Official references

- Istio architecture: https://istio.io/latest/docs/ops/deployment/architecture/
- Traffic management: https://istio.io/latest/docs/concepts/traffic-management/
- Egress control: https://istio.io/latest/docs/tasks/traffic-management/egress/egress-control/
- Egress gateway: https://istio.io/latest/docs/tasks/traffic-management/egress/egress-gateway/
- Sidecar reference: https://istio.io/latest/docs/reference/config/networking/sidecar/
- Ambient overview: https://istio.io/latest/docs/ambient/overview/
- Ambient waypoints: https://istio.io/latest/docs/ambient/usage/waypoint/
- KIND: https://kind.sigs.k8s.io/docs/user/quick-start/
