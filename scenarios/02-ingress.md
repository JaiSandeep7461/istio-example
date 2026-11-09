# Scenario 02 — Ingress: Kubernetes first, Istio second

## Goal

Understand ingress as a **traffic direction** before learning the Istio Ingress Gateway.

## Normal Kubernetes

Traffic entering an application can be represented as:

```text
Client
   |
   v
Kubernetes entry mechanism
   |
   v
Service
   |
   v
frontend Pod
```

In a local KIND lab, we can simplify the demonstration by using a Service port-forward:

```bash
./scripts/deploy-baseline.sh
kubectl -n shop port-forward svc/frontend 8080:8080
curl http://localhost:8080/
```

Port-forward is only a lab access mechanism; it is not a production ingress architecture.

## What is ingress?

Ingress simply means:

> Traffic is entering the cluster/mesh toward an application.

It does **not** automatically mean "Istio".

## Istio ingress

Now install Istio and use its ingress gateway:

```text
Client
   |
   v
Istio Ingress Gateway
   |
   v
Gateway resource
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
./scripts/install-istio.sh
./scripts/enable-mesh.sh
kubectl apply -f istio/00-demo-gateway.yaml
kubectl -n istio-system port-forward svc/istio-ingressgateway 8081:80
curl -i -H 'Host: shop.local' http://localhost:8081/
```

## Why add the gateway?

The gateway gives us a dedicated mesh edge where we can configure listeners and connect those listeners to Istio routing rules.

Important distinction:

- Gateway = edge/listener configuration
- VirtualService = route configuration
- Ingress = direction of traffic
- Ingress Gateway = proxy/entry point

The gateway is not magically the application route by itself.
