# ADR-020: App-of-Apps + Sealed Secrets key persistence

- **Status:** Accepted (design-first — to verify on next cluster bring-up)
- **Date:** 2026-08-13
- **Deciders:** project owner

## Context

ADR-019 landed GitOps but left two manual seams:

1. **SealedSecrets were applied by hand** (day-0 bootstrap), not by ArgoCD — so a fresh
   cluster or a lost app needs a human to re-apply them.
2. **The sealing key is regenerated per cluster.** The Bitnami controller generates a new
   RSA key pair on first start (a Secret in `kube-system` labelled
   `sealedsecrets.bitnami.com/sealed-secrets-key`). Because compute is **ephemeral**
   (ADR-018 — `destroy`/`apply` each session), every new cluster gets a **new key**, so the
   committed `SealedSecret`s — sealed against the *old* public cert — **can no longer be
   decrypted**. Automating their apply alone is a trap: ArgoCD would apply them, but they
   would never unseal, and you'd still re-seal every session.

## Decision

**Adopt the App-of-Apps pattern, let ArgoCD manage the SealedSecrets as a child app, and
persist the sealing key out-of-band so committed SealedSecrets survive cluster rebuilds.**

### 1. App-of-Apps

A single **root Application** (`platform/gitops/root.yaml`) points at a directory of child
Application manifests (`platform/gitops/apps/`). On a fresh cluster you apply **only the
root**; ArgoCD then creates and reconciles the children. Children:

- `apps/sealed-secrets.yaml` → `platform/gitops/sealed-secrets/` (directory source), **sync-wave 0**
- `apps/services.yaml` → `deploy/helm/vortex` (Helm), **sync-wave 1**

**Sync-waves** order child creation: secrets (wave 0) before services (wave 1). Note this
orders *creation*, not a hard barrier — cross-app readiness still relies on ArgoCD retry
(a service pod may briefly `CreateContainerConfigError` until its Secret unseals). Good
enough here; a hard gate would need in-app waves or health checks.

### 2. Sealing-key persistence (the load-bearing decision)

The controller's private key is the master key that decrypts **every** SealedSecret, so it
**cannot be committed to git**. It is backed up **out-of-band** and restored before the
controller starts on a new cluster:

```bash
# backup once (store OUT of git — password manager / gitignored file / AWS Secrets Manager)
kubectl get secret -n kube-system \
  -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > sealed-secrets-key.backup.yaml

# restore on a fresh cluster BEFORE (or just before restarting) the controller
kubectl apply -f sealed-secrets-key.backup.yaml
kubectl delete pod -n kube-system -l name=sealed-secrets-controller   # pick up the restored key
```

With the same key restored, the committed SealedSecrets decrypt on every rebuild → **truly
reproducible**, no re-sealing per session.

**Irony worth stating:** making secrets reproducible from git requires **one** secret that
is *not* in git — the sealing key. That key becomes the single out-of-band root of trust.
The cloud-native evolution is to hand that root to a KMS (e.g. seal the backup with AWS KMS,
or move to the SOPS+age / External Secrets + AWS Secrets Manager model) — deferred.

## Consequences

- **Good:** one `kubectl apply` (the root) bootstraps all GitOps apps; SealedSecrets are
  ArgoCD-managed and survive cluster rebuilds; clean path to more apps (add a child under
  `apps/`); demonstrates App-of-Apps + sync-waves.
- **Cost:** an out-of-band sealing-key backup must be safeguarded (its loss = re-seal
  everything; its leak = all secrets exposed). ArgoCD, the sealed-secrets controller, and
  the key restore remain true day-0 bootstrap (can't self-bootstrap — chicken-and-egg).
- **Follow-ups:** KMS-wrap the sealing key; move to External Secrets/SOPS; App-of-Apps could
  later also template the bootstrap (namespace/ecr-auth) once safe to do declaratively.
