# Scenario 07 — Authorization

## Goal

Understand the difference between network connectivity and identity-aware authorization.

## Normal Kubernetes

Normal networking primarily asks:

> Can traffic reach the destination?

Conceptually:

```text
frontend --------> catalog
other workload --> catalog
```

If network connectivity is available, the application itself may need to implement authentication and authorization.

## Istio identity

With Istio mTLS, workloads receive identities through the mesh security system.

Then AuthorizationPolicy can use that identity:

```text
frontend workload identity
          |
          v
AuthorizationPolicy
          |
          +---- GET catalog ----> ALLOW
          |
          +---- unauthorized ---> DENY
```

Apply:

```bash
kubectl apply -f istio/31-authorization-policy.yaml
kubectl -n shop get authorizationpolicy
```

Test the normal frontend path:

```bash
curl -s http://localhost:8080/call/catalog
```

The repository policy permits the default service account to perform HTTP GET against catalog.

## Important distinction

mTLS:

> "Who is this workload and can we establish an authenticated encrypted connection?"

AuthorizationPolicy:

> "Now that we know who it is, is this identity allowed to perform this operation?"

That distinction is important in interviews and production troubleshooting.
