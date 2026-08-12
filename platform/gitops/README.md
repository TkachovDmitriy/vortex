# platform/gitops — ArgoCD + Sealed Secrets (ADR-019, ADR-020)

Pull-based delivery via ArgoCD, structured as **App-of-Apps**. Secrets live in git as
`SealedSecret` CRDs (safe to commit); the sealing key is persisted out-of-band.

```
root.yaml              App-of-Apps root → apps/  (the ONE manual apply)
apps/
  sealed-secrets.yaml  child → sealed-secrets/     (sync-wave 0)
  services.yaml        child → deploy/helm/vortex   (sync-wave 1)
sealed-secrets/        committed SealedSecrets (postgres, orders, inventory)
```

## Layers

- **day-0 bootstrap (imperative, once per cluster):** ArgoCD, sealed-secrets controller,
  **sealing-key restore**, ecr-auth, data (Postgres/NATS). Can't self-bootstrap.
- **day-2 GitOps (ArgoCD):** everything under `apps/` — SealedSecrets + the 5 services.

## Bootstrap order (fresh cluster)

Prereqs: cluster up (`infra/environments/dev`, ADR-010), `KUBECONFIG` exported.

```bash
# 1. ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 2. Sealed Secrets controller + RESTORE the persisted key (ADR-020) — BEFORE sealing/unsealing
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/latest/download/controller.yaml
kubectl apply -f sealed-secrets-key.backup.yaml            # out-of-band key (NOT in git)
kubectl delete pod -n kube-system -l name=sealed-secrets-controller   # pick up restored key

# 3. ecr-auth (ADR-017) — configmap.yaml is gitignored (account id)
kubectl create namespace vortex
kubectl apply -n vortex -f deploy/k8s/platform/ecr-auth/{serviceaccount,rbac,configmap,cronjob}.yaml
kubectl create job --from=cronjob/ecr-cred-refresh ecr-cred-refresh-init -n vortex
kubectl patch serviceaccount default -n vortex -p '{"imagePullSecrets":[{"name":"ecr-pull-secret"}]}'

# 4. data layer (Postgres + NATS)
kubectl apply -n vortex \
  -f deploy/k8s/data/postgres/{init-configmap,service,statefulset}.yaml \
  -f deploy/k8s/data/nats/{service,statefulset}.yaml

# 5. hand everything else to ArgoCD (the ONLY app manifest you apply by hand)
kubectl apply -f platform/gitops/root.yaml
```

The root creates the child apps; sealed-secrets (wave 0) unseal with the restored key, then
services (wave 1) come up.

## Sealing-key backup (do this once, keep it safe)

```bash
kubectl get secret -n kube-system \
  -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > sealed-secrets-key.backup.yaml
# store OUT of git — password manager / AWS Secrets Manager. Loss = re-seal all; leak = all exposed.
```

## Re-sealing a secret

```bash
kubeseal --format yaml < deploy/k8s/data/postgres/secret.yaml \
  > platform/gitops/sealed-secrets/postgres-sealedsecret.yaml
# commit + push; ArgoCD reconciles it
```

## Notes

- Vendored `charts/*.tgz` are committed (ADR-019 amends ADR-014) so ArgoCD's repo-server can
  render multi-level local chart deps. Re-vendor bottom-up after chart edits.
- ArgoCD reads the **remote** branch (`targetRevision`) — local/unpushed commits are invisible.
