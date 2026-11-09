# Istio on KIND: Online Shop Service Mesh Lab

This lab teaches what Istio is, why Kubernetes users add it, and how to demonstrate its features locally.

**Scenario:** an online shop contains a frontend, catalog v1/v2, and reviews. First deploy using Kubernetes Services only. Then install Istio and demonstrate sidecar injection, 80/20 canary traffic, beta-header routing, fault injection, strict mTLS, authorization, and ingress.

## What is Istio?

Istio is a **service mesh**: a layer that manages application traffic between services and provides traffic management, workload security, and telemetry. Kubernetes still schedules Pods, restarts containers, provides Service discovery, and runs cluster networking. Istio does not replace Kubernetes or your CNI.

This repository uses Istio's **sidecar mode**. A participating Pod gets an Envoy `istio-proxy` container beside its application container.

- `istiod` is the control plane. It watches workloads and mesh configuration, then programs proxies.
- Envoy sidecars form the data plane. They intercept and handle application traffic.
- `DestinationRule` defines destination subsets and policies.
- `VirtualService` controls request routing and weights.
- `PeerAuthentication` controls inbound mTLS mode.
- `AuthorizationPolicy` controls which workload identity may do what.
- `Gateway` configures an edge proxy listener; `VirtualService` binds routes to it.

Kubernetes Service DNS continues to work; Istio provides policy-aware traffic control on top.

## Architecture

```mermaid
flowchart LR
 U[User] --> FE[frontend]
 FE --> CS[Kubernetes Service: catalog]
 CS --> V1[catalog v1 Pods]
 CS --> V2[catalog v2 Pods]
 FE --> RS[Kubernetes Service: reviews]
 RS --> R[reviews Pod]
 subgraph Mesh[Istio mesh]
  FE -. Envoy .- V1
  FE -. Envoy .- V2
  FE -. Envoy .- R
 end
 CP[istiod] -. configures .-> FE
 CP -. configures .-> V1
 CP -. configures .-> V2
 CP -. configures .-> R
```

## Prerequisites and version

Install Docker, KIND, kubectl, curl, Bash, and `istioctl` 1.31.x. On Windows use WSL Ubuntu or Git Bash with Docker Desktop configured. KIND pins Kubernetes node image `kindest/node:v1.35.0`; check the [Istio supported-release matrix](https://istio.io/latest/docs/releases/supported-releases/) before changing versions and use a Kubernetes release supported by your chosen Istio minor.

```bash
docker version
kind version
kubectl version --client
istioctl version --remote=false
curl --version
```

## Repository layout

```text
kind/cluster.yaml
apps/frontend/{Dockerfile,app.py}
base/{namespace,catalog,reviews,frontend}.yaml
istio/{00-demo-gateway,10-catalog-destination-rule,11-catalog-canary-virtual-service,12-catalog-header-route,20-reviews-resilience,30-peer-authentication-strict,31-authorization-policy}.yaml
scripts/{build-and-load,deploy-baseline,install-istio,enable-mesh,test-traffic,cleanup}.sh
```

## 1. Create KIND cluster

```bash
kind create cluster --name istio-lab --config kind/cluster.yaml
kubectl cluster-info --context kind-istio-lab
kubectl get nodes -o wide
```

## 2. Build and load frontend image

```bash
chmod +x scripts/*.sh
./scripts/build-and-load.sh
```

KIND nodes cannot automatically use images from your host Docker cache; the script loads the image into KIND.

## 3. Deploy without Istio (baseline)

```bash
./scripts/deploy-baseline.sh
kubectl -n shop get deploy,pods,svc -o wide
kubectl -n shop port-forward svc/frontend 8080:8080
```

Leave port-forward running. In another terminal:

```bash
curl -s http://localhost:8080/
curl -s http://localhost:8080/call/catalog
curl -s http://localhost:8080/call/reviews
```

The frontend calls `catalog:5678` and `reviews:5678` through Kubernetes Service DNS.

### Show the Kubernetes-only limitation

```bash
kubectl -n shop scale deploy/catalog-v1 --replicas=2
kubectl -n shop scale deploy/catalog-v2 --replicas=2
kubectl -n shop get pods -l app=catalog -L version
for i in {1..12}; do curl -s http://localhost:8080/call/catalog; done
```

The catalog Service selects all Pods labeled `app: catalog`. Kubernetes Services do basic endpoint selection/load balancing; they do not natively express an application-level 80/20 version split or header-based route. That is the policy problem Istio will solve. Stop port-forward with Ctrl+C.

## 4. Install Istio

Install the Istio 1.31.4 CLI from the [official Getting Started guide](https://istio.io/latest/docs/setup/getting-started/), then:

```bash
./scripts/install-istio.sh
kubectl get pods -n istio-system
istioctl version
```

The script uses the `demo` profile for this disposable lab. This profile is for evaluation, not production sizing.

## 5. Enable sidecar injection

```bash
./scripts/enable-mesh.sh
kubectl -n shop get pods
POD=$(kubectl -n shop get pod -l app=frontend -o jsonpath='{.items[0].metadata.name}')
kubectl -n shop get pod "$POD" -o jsonpath='{.spec.containers[*].name}{"\\n"}'
istioctl proxy-status
istioctl proxy-config listeners "$POD" -n shop
```

Expected containers include `frontend` and `istio-proxy`. `istiod` configures proxies; it is not in the request path.

## 6. Canary: 80% v1 and 20% v2

```bash
kubectl apply -f istio/10-catalog-destination-rule.yaml
kubectl apply -f istio/11-catalog-canary-virtual-service.yaml
kubectl -n shop get destinationrule,virtualservice
kubectl -n shop port-forward svc/frontend 8080:8080
```

In another terminal:

```bash
for i in {1..50}; do curl -s http://localhost:8080/call/catalog; done
```

Expect both versions, approximately 80/20 over a sufficiently large sample. Small samples are statistical, not exact counts. `DestinationRule` defines subsets using Pod labels; `VirtualService` chooses subsets and weights. Kubernetes Service discovery remains in place.

Inspect:

```bash
istioctl analyze -n shop
POD=$(kubectl -n shop get pod -l app=frontend -o jsonpath='{.items[0].metadata.name}')
istioctl proxy-config routes "$POD" -n shop
```

## 7. Header-based routing: beta gets v2

```bash
kubectl apply -f istio/12-catalog-header-route.yaml
curl -s http://localhost:8080/call/catalog
curl -s -H 'x-release: beta' http://localhost:8080/call/catalog
```

The `x-release: beta` request goes to v2. Other traffic follows 80/20.

## 8. Timeout, retries, and fault injection

```bash
kubectl apply -f istio/20-reviews-resilience.yaml
for i in {1..30}; do curl -i http://localhost:8080/call/reviews; done
```

Istio injects a 3-second delay into 30% of reviews requests. The frontend's client timeout is 2 seconds, making the delay observable. The VirtualService also declares an Istio timeout and retry policy. Fault injection is a test feature; remove it after the demo:

```bash
kubectl delete -f istio/20-reviews-resilience.yaml
```

## 9. Strict mTLS

Confirm all `shop` workloads have sidecars, then:

```bash
kubectl apply -f istio/30-peer-authentication-strict.yaml
kubectl -n shop get peerauthentication
curl -s http://localhost:8080/call/catalog
curl -s http://localhost:8080/call/reviews
```

Strict mTLS requires encrypted and mutually authenticated connections between participating workloads in this namespace. Envoy proxies use workload identities and certificates provisioned by Istio; application containers do not handle these certificates directly.

Inspect proxy config:

```bash
POD=$(kubectl -n shop get pod -l app=frontend -o jsonpath='{.items[0].metadata.name}')
istioctl proxy-config clusters "$POD" -n shop
```

Do not use an uninjected Pod as the positive test under strict mTLS; plaintext connections should be rejected.

## 10. Authorization policy

```bash
kubectl apply -f istio/31-authorization-policy.yaml
kubectl -n shop get authorizationpolicy
curl -s http://localhost:8080/call/catalog
```

The policy allows the `frontend` service account to issue HTTP GET to catalog. A different workload identity should be denied. mTLS authenticates and encrypts; `AuthorizationPolicy` decides which authenticated identity may perform an operation.

## 11. Optional ingress Gateway

```bash
kubectl apply -f istio/00-demo-gateway.yaml
kubectl -n istio-system port-forward svc/istio-ingressgateway 8081:80
curl -i -H 'Host: shop.local' http://localhost:8081/
```

Gateway configures the edge proxy listener. VirtualService binds `shop.local` and routes ingress traffic to the frontend Service. Gateway alone does not define the application route.

## Troubleshooting

```bash
kubectl get pods -A
kubectl -n shop get pods -o wide
kubectl -n shop describe pod <pod-name>
kubectl -n shop logs <pod-name> -c istio-proxy
istioctl analyze -n shop
istioctl proxy-status
istioctl proxy-config routes <pod-name> -n shop
istioctl proxy-config clusters <pod-name> -n shop
```

| Symptom | Check |
|---|---|
| frontend ImagePullBackOff | Run build-and-load script after KIND creation. |
| Missing istio-proxy | Label namespace and restart Deployments. |
| Wrong route | Check subset labels, hosts, DestinationRule, VirtualService, and `istioctl analyze`. |
| Strict mTLS breaks calls | Ensure caller and target Pods both have sidecars. |
| Gateway 404 | Check Host header, Gateway selector, VirtualService binding, and Service port. |

## Cleanup

Stop port-forward commands, then run:

```bash
./scripts/cleanup.sh
```

This deletes the KIND cluster and all resources inside it.

## Suggested 10-minute teaching flow

1. Minutes 0–2: baseline Kubernetes Service calls.
2. Minutes 2–4: install Istio, inject and inspect `istio-proxy`.
3. Minutes 4–6: 80/20 canary and beta header route.
4. Minutes 6–8: latency/fault injection and retries.
5. Minutes 8–10: strict mTLS and authorization.

**One-line explanation:** Kubernetes runs and connects services; Istio adds a programmable, observable, and secure traffic layer between services.

## Official references

- [Istio architecture](https://istio.io/latest/docs/ops/deployment/architecture/)
- [Istio Getting Started](https://istio.io/latest/docs/setup/getting-started/)
- [Traffic Management](https://istio.io/latest/docs/concepts/traffic-management/)
- [Security concepts](https://istio.io/latest/docs/concepts/security/)
- [Supported releases](https://istio.io/latest/docs/releases/supported-releases/)
- [KIND Quick Start](https://kind.sigs.k8s.io/docs/user/quick-start/)

# Advanced traffic and data-plane labs

## Ingress, egress, sidecar and ambient — the practical mental model

**Ingress** is traffic entering the mesh:

    User
      |
      v
    Istio Ingress Gateway
      |
      v
    frontend Service
      |
      v
    application Pod

**Egress** is traffic leaving the mesh:

    application Pod
      |
      v
    sidecar / ztunnel
      |
      v
    Istio Egress Gateway
      |
      v
    External API / Internet

An Istio Gateway configures an edge proxy. A Gateway resource defines listener/edge properties, while a VirtualService or Gateway API route defines application routing. Ingress and egress gateways are dedicated Envoy proxy deployments at the mesh edge. citeturn884347search9turn884347search6

### Sidecar mode

Sidecar mode injects an Envoy proxy into every participating application Pod.

    +------------------- Pod -------------------+
    |                                            |
    |  Application ---> Envoy istio-proxy       |
    |                         |                  |
    +-------------------------|------------------+
                              |
                         mesh traffic

The sidecar can process L4 and L7 traffic. This makes routing, retries, timeouts, fault injection, authorization and telemetry possible without putting that logic into the application. The trade-off is that every workload carries another proxy and its CPU/memory/configuration overhead. citeturn884347search8

### Ambient mode

Ambient removes the Envoy sidecar from the application Pod.

    Node
    +--------------------------------------+
    | frontend Pod      catalog Pod        |
    |       |                 |            |
    |       +--------+--------+            |
    |                |                     |
    |             ztunnel                  |
    +--------------------------------------+

ztunnel is a per-node L4 proxy. It provides the secure overlay and HBONE transport. When L7 features are required, a waypoint proxy is added; the waypoint is an Envoy proxy outside the application Pod. citeturn884347search3turn884347search12

The key difference is therefore not "Istio versus no Istio":

    Sidecar:
    application + Envoy in every Pod

    Ambient:
    application Pod + node ztunnel
                      +
                  optional waypoint for L7

## Lab: sidecar mode and encrypted traffic

Run the existing sidecar lab first:

    ./scripts/build-and-load.sh
    ./scripts/deploy-baseline.sh
    ./scripts/install-istio.sh
    ./scripts/enable-mesh.sh

Verify the sidecar:

    POD=$(kubectl -n shop get pod -l app=frontend -o jsonpath='{.items[0].metadata.name}')
    kubectl -n shop get pod "$POD" -o jsonpath='{.spec.containers[*].name}{"\n"}'
    istioctl proxy-status

You should see the application container and istio-proxy.

Enable strict mTLS:

    kubectl apply -f istio/30-peer-authentication-strict.yaml

Verify the workload certificates loaded by Envoy:

    istioctl proxy-config secret "$POD" -n shop

Inspect the proxy cluster configuration:

    istioctl proxy-config clusters "$POD" -n shop

Then generate traffic:

    kubectl -n shop port-forward svc/frontend 8080:8080
    curl http://localhost:8080/call/catalog

The important traffic path is:

    frontend application
          |
          | plaintext HTTP inside source Pod
          v
    frontend Envoy
          |
          | ===== mTLS encrypted =====
          v
    catalog Envoy
          |
          | plaintext HTTP inside destination Pod
          v
    catalog application

mTLS protects the proxy-to-proxy network connection. The application itself does not need to implement TLS. Istio provisions workload identities/certificates and uses them for mutual authentication and encrypted transport. citeturn884347search6

### Packet-level encryption exercise

For a stronger demonstration, capture packets on the KIND node while the request is running. This is useful because application logs alone do not prove encryption.

Find the node:

    docker ps --format 'table {{.Names}}	{{.Image}}'

Enter the KIND control-plane container:

    docker exec -it istio-lab-control-plane sh

If tcpdump is available, inspect traffic:

    tcpdump -i any -nn -A tcp

Generate requests from another terminal:

    for i in {1..20}; do curl -s http://localhost:8080/call/catalog; done

You should not expect to see the original application HTTP payload on the proxy-to-proxy network path; that hop is protected by Istio mTLS.

Important: traffic inside the source Pod before interception and traffic after decryption at the destination proxy are not the same network hop. Therefore, "I can see HTTP in a packet capture" is not automatically proof that mTLS is broken.

## Lab: Ingress Gateway

Apply:

    kubectl apply -f istio/00-demo-gateway.yaml

Expose the gateway locally:

    kubectl -n istio-system port-forward svc/istio-ingressgateway 8081:80

Call it with the required host:

    curl -i -H 'Host: shop.local' http://localhost:8081/

The path is:

    client
      |
      v
    Istio Ingress Gateway
      |
      v
    frontend Service
      |
      v
    frontend Pod

This is different from directly port-forwarding the frontend Service. The Gateway gives you a dedicated mesh entry point where TLS/listener configuration and edge traffic policies can be applied. citeturn884347search13turn884347search9

## Lab: Egress Gateway

This lab uses an external HTTP service definition and routes traffic through the dedicated Istio egress gateway.

Apply:

    kubectl apply -f istio/40-egress-service-entry.yaml
    kubectl apply -f istio/41-egress-gateway.yaml
    kubectl apply -f istio/42-egress-routing.yaml

Inspect:

    kubectl -n shop get serviceentry
    kubectl -n shop get gateway
    kubectl -n shop get virtualservice

The intended path is:

    frontend
       |
       v
    frontend sidecar
       |
       v
    Istio Egress Gateway
       |
       v
    httpbin.org

An egress gateway gives you a dedicated, observable exit point where routing, authorization and TLS origination can be applied. It is especially useful when an organization requires external traffic to leave through controlled nodes. citeturn884347search0turn884347search2

Important security point: an Istio egress gateway configuration alone does not magically prevent every possible packet from bypassing the gateway. Strict enforcement may also require Kubernetes NetworkPolicy, firewall rules or cloud network controls. citeturn884347search2

## Lab: Ambient mode

Use a fresh cluster for this comparison so the sidecar experiment and ambient experiment are clearly separated.

    ./scripts/cleanup.sh
    kind create cluster --name istio-ambient-lab --config kind/cluster.yaml

Install the ambient profile:

    istioctl install --set profile=ambient -y

Verify ztunnel:

    kubectl get pods -n istio-system
    kubectl get daemonset -n istio-system

Deploy the ambient workloads:

    kubectl apply -f ambient/namespace.yaml
    kubectl apply -f ambient/apps.yaml

Enroll the namespace:

    kubectl label namespace ambient-shop istio.io/dataplane-mode=ambient

Now inspect the application Pod:

    kubectl -n ambient-shop get pods
    kubectl -n ambient-shop get pod -l app=frontend -o jsonpath='{.items[0].spec.containers[*].name}{"\n"}'

You should see only the application container. There is no istio-proxy sidecar.

This is the central ambient demonstration: the workload participates in the mesh without an Envoy container inside its Pod. Ambient enrollment also does not require restarting the application Pod. citeturn884347search8

Generate traffic:

    kubectl -n ambient-shop exec deploy/frontend -- wget -qO- http://catalog:5678/

Inspect ambient workload state:

    istioctl ztunnel-config workloads

The traffic path is:

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

Ambient ztunnel provides the secure L4 overlay and HBONE transport. citeturn884347search12turn884347search3

## Lab: Ambient waypoint for L7

Ambient's ztunnel is intentionally L4. If you need L7 features such as HTTP routing, L7 authorization, retries, timeouts or fault injection, add a waypoint.

Apply:

    kubectl apply -f ambient/waypoint.yaml
    kubectl label namespace ambient-shop istio.io/use-waypoint=ambient-waypoint --overwrite

Check:

    kubectl get gateway -n ambient-shop
    kubectl get pods -n ambient-shop

The architecture becomes:

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

This is why ambient should not be described as "Istio without Envoy". Ambient removes per-Pod Envoys, but Envoy can still be used as a waypoint when L7 processing is needed. citeturn884347search7turn884347search12

## Sidecar vs ambient: what to say in an interview

"Sidecar mode injects an Envoy proxy into each participating Pod. The proxy intercepts the application's traffic and can provide L4/L7 traffic management, mTLS, authorization and telemetry.

Ambient mode moves the basic data-plane function out of the application Pods. A ztunnel runs on every node and provides a secure L4 overlay using HBONE and mTLS. When L7 features are needed, an Envoy waypoint is deployed outside the application Pods.

Ingress controls traffic entering the mesh. Egress controls traffic leaving the mesh. An ingress gateway is the controlled entry point, while an egress gateway is the controlled exit point for external services."

## Official references

- Istio data-plane modes: https://istio.io/latest/docs/overview/dataplane-modes/
- Ambient architecture: https://istio.io/latest/docs/ambient/overview/
- Ambient waypoints: https://istio.io/latest/docs/ambient/usage/waypoint/
- Ambient egress gateway: https://istio.io/latest/docs/ambient/usage/egress-gateway/
- Ingress gateway: https://istio.io/latest/docs/tasks/traffic-management/ingress/
- Egress gateway: https://istio.io/latest/docs/tasks/traffic-management/egress/egress-gateway/
- TLS configuration: https://istio.io/latest/docs/ops/configuration/traffic-management/tls-configuration/
