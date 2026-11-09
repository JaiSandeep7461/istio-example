# Scenario 03 — Egress: Kubernetes first, Istio second

## Goal

Understand why outbound traffic needs an explicit control strategy.

## 1. Normal Kubernetes

Start with no Istio.

A Pod can make an external request when the cluster's network path permits it:

```text
Pod
 |
 v
Pod network / CNI
 |
 v
Node routing
 |
 v
NAT / firewall
 |
 v
Internet
 |
 v
google.com
```

Run a temporary curl Pod:

```bash
kubectl run curl --rm -it --restart=Never \
  --image=curlimages/curl:8.10.1 -- \
  curl -I --max-time 10 https://www.google.com
```

If the surrounding environment permits Internet access, you should receive an HTTP response.

There is no Istio egress gateway here.

## 2. What problem does egress control solve?

Imagine the security requirement:

> "Applications in this mesh must not make arbitrary outbound connections."

Without an explicit policy, an application could attempt:

```text
Pod ---> google.com
Pod ---> github.com
Pod ---> random-api.example
Pod ---> attacker.example
```

The exact enforcement mechanism may involve Kubernetes NetworkPolicy, cloud firewalling, a proxy, or a combination.

## 3. Istio REGISTRY_ONLY

Istio can change unknown outbound behavior from the default permissive mode to registry-only:

```text
outboundTrafficPolicy:
  mode: REGISTRY_ONLY
```

Then the proxy only accepts destinations known to Istio's service registry, such as a ServiceEntry.

Conceptually:

```text
                    +--> registered host ---> allowed
Pod --> sidecar ----+
                    +--> unknown host ------> blocked
```

Important: `REGISTRY_ONLY` is **not a complete outbound firewall**. Istio documents it primarily as a proxy-level way to reject unknown destinations and expose missing ServiceEntry configuration.

## 4. Register an external service

The repository already contains:

```text
istio/40-egress-service-entry.yaml
```

It registers `httpbin.org`.

Apply it:

```bash
kubectl apply -f istio/40-egress-service-entry.yaml
kubectl -n shop get serviceentry
```

Now Istio knows that external service exists.

## 5. Introduce the egress gateway

The controlled path becomes:

```text
frontend application
       |
       v
frontend Envoy
       |
       v
Istio Egress Gateway
       |
       v
httpbin.org
```

Apply:

```bash
kubectl apply -f istio/41-egress-gateway.yaml
kubectl apply -f istio/42-egress-routing.yaml
```

Test:

```bash
curl http://localhost:8080/call/external
```

Inspect:

```bash
kubectl -n shop get serviceentry,gateway,virtualservice
kubectl -n istio-system get pods -l istio=egressgateway
```

## 6. Why is the egress gateway useful?

It creates a dedicated, observable exit point:

```text
Applications
    |
    v
Sidecars
    |
    v
Egress Gateway
    |
    +--> external API A
    +--> external API B
    +--> external API C
```

You can apply routing, authorization, telemetry, and TLS-related controls at that boundary.

## 7. Important security limitation

Do not claim:

> "Installing an Istio egress gateway automatically makes it impossible to bypass."

That is false.

Istio's own documentation explains that strong enforcement can require NetworkPolicy, firewall, or cloud-network controls so application traffic cannot bypass the gateway.

For production-grade egress enforcement, think:

```text
Istio Egress Gateway
        +
Kubernetes NetworkPolicy
        +
Cloud/network firewall
```

That is defense in depth.

## 8. The lesson

Normal Kubernetes answers:

> "Can this Pod reach the Internet?"

Istio egress adds:

> "Which external destinations are registered, how should traffic be routed, and where should controlled outbound traffic leave the mesh?"

And network controls provide the stronger enforcement boundary.
