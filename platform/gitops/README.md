# platform/gitops — ArgoCD + Sealed Secrets (ADR-019)

Pull-based delivery: ArgoCD watches git and reconciles the vortex services into the
cluster. Secrets live in git as `SealedSecret` CRDs (safe to commit).

```
application.yaml       ArgoCD Application → deploy/helm/vortex (services umbrella)
sealed-secrets/        committed SealedSecrets (postgres, orders, inventory)
```

## Layers

- **day-0 bootstrap (imperative, once per cluster):** namespace, SealedSecrets, ecr-auth,
  data (Postgres/NATS). Not managed by ArgoCD — see ADR-014 (services-only) / ADR-019.
- **day-2 GitOps (ArgoCD):** the 5 services via the umbrella chart.

## Bootstrap order (fresh cluster)

Prereqs: cluster up (`infra/environments/dev`, ADR-010), `KUBECONFIG` exported,
ArgoCD + Sealed Secrets controller installed.

```bash
kubectl create namespace vortex

# secrets (controller decrypts these into real Secrets)
kubectl apply -f platform/gitops/sealed-secrets/

# ECR pull auth (ADR-017) — configmap.yaml is gitignored (account id)
kubectl apply -n vortex -f deploy/k8s/platform/ecr-auth/{serviceaccount,rbac,configmap,cronjob}.yaml
kubectl create job --from=cronjob/ecr-cred-refresh ecr-cred-refresh-init -n vortex
kubectl patch serviceaccount default -n vortex -p '{"imagePullSecrets":[{"name":"ecr-pull-secret"}]}'

# data layer (Postgres + NATS)
kubectl apply -n vortex \
  -f deploy/k8s/data/postgres/{init-configmap,service,statefulset}.yaml \
  -f deploy/k8s/data/nats/{service,statefulset}.yaml

# hand delivery to ArgoCD (last manual apply)
kubectl apply -f platform/gitops/application.yaml
```

## Re-sealing a secret

`SealedSecret`s are bound to this cluster's controller key — a new cluster needs re-sealing.

```bash
kubeseal --format yaml < deploy/k8s/data/postgres/secret.yaml \
  > platform/gitops/sealed-secrets/postgres-sealedsecret.yaml
# commit + push; ArgoCD (or a manual apply) reconciles it
```

## Notes

- Vendored `charts/*.tgz` are committed (ADR-019 amends ADR-014) so ArgoCD's repo-server
  can render the multi-level local chart deps. Re-vendor bottom-up after chart changes:
  `helm dependency update deploy/helm/<svc>` (each) then `deploy/helm/vortex`.
- ArgoCD reads the **remote** branch in `application.yaml` (`targetRevision`) — local/unpushed
  commits are invisible to it.
