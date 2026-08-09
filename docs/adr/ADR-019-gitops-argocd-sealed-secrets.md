# ADR-019: GitOps delivery — ArgoCD + Sealed Secrets

- **Status:** Accepted (implemented on cloud k3s)
- **Date:** 2026-08-09
- **Deciders:** project owner

## Context

Through ADR-010/017 the stack deploys to cloud k3s, but delivery is **imperative and
push-based**: a human runs `helm install` from a laptop holding cluster-admin kubeconfig.
That has three gaps this project should demonstrably close:

1. **No audit trail / no drift correction** — `kubectl edit` leaves no record, and nothing
   reconciles the cluster back to a known state.
2. **Not reproducible from git** — every `Secret`/`ConfigMap` is gitignored, so a fresh
   cluster cannot be rebuilt from the repo alone.
3. **Credentials on the pusher** — CI or a laptop needs admin access to the cluster.

Phase 4 of the roadmap is GitOps. The headline CV skills here are *why pull-based* and
*how secrets live safely in git*.

## Decision

**Adopt pull-based GitOps with ArgoCD (in-cluster, watches git, reconciles) and make
secrets git-safe with Bitnami Sealed Secrets. One ArgoCD `Application` manages the
services umbrella chart; the data/platform layers remain day-0 bootstrap.**

1. **ArgoCD, pull-based.** The controller runs in-cluster and pulls desired state from
   git — no external system holds cluster credentials, `git revert` is rollback, and
   `git log` is the audit trail.

2. **Single `Application` → `deploy/helm/vortex`** (`platform/gitops/application.yaml`),
   `syncPolicy.automated` with **`selfHeal`** and **`prune`** on. This is a learning
   cluster where seeing drift get reverted is the point; production would gate sync
   behind manual promotion. App-of-Apps is deferred until there is more than one app.

3. **Sealed Secrets for git-safe secrets.** The controller holds a private key; `kubeseal`
   encrypts with the public cert into `SealedSecret` CRDs (`platform/gitops/sealed-secrets/`)
   that are **safe to commit**. Only the owning cluster's controller can decrypt them, so
   they are **not portable across clusters** (re-seal per cluster). This closes gap #2.

4. **Bootstrap vs GitOps split (consistent with ADR-014 "services-only").** The umbrella
   chart is services only. The **data layer** (Postgres/NATS), **ecr-auth**, namespace,
   and the **SealedSecrets** are applied once as **day-0 bootstrap** (imperative); the
   **apps** are **day-2 GitOps**. Having ArgoCD also apply the SealedSecrets is a clean
   next iteration, not required to close the reproducibility gap.

5. **`global.imageRegistry` committed in the Application.** ArgoCD renders the chart
   itself, so the ECR host (which embeds the AWS account id) moves into git via
   `helm.parameters`. **An account id is an identifier, not a credential** — access is
   IAM-gated (ADR-017) — so it is safe to commit, and GitOps requires config to live in git.

## Amendment to ADR-014 — commit vendored `charts/*.tgz`

ADR-014 gitignored the vendored `.tgz` (like `node_modules`), keeping only `Chart.lock`.
That predates GitOps. ArgoCD's repo-server runs `helm dependency build` **only at the top
level, not recursively**, so the multi-level local dependency chain
`vortex → orders → common` fails to render (`no template "common.service"`) unless the
built charts are present in git. **We therefore commit the vendored `.tgz`** so ArgoCD
gets self-contained, renderable sources.

Trade-off: binaries in git. The cleaner long-term fix is to publish the `common` library
chart as an **OCI chart to ECR** and depend on it by URL, letting `helm dependency build`
fetch it — which would remove the binaries again. Deferred (tracked as a future ADR).

## Consequences

- **Good:** declarative, auditable, self-healing delivery; secrets reproducible from git;
  no external credential holds cluster admin; a demonstrable "change git → cluster
  converges" loop.
- **Cost:** vendored chart binaries in git (until the OCI follow-up); a day-0 bootstrap
  step still exists outside GitOps (data/platform); image bumps require a git write (the
  "who edits values.yaml" question — manual for now, CI/Image-Updater later).
- **Follow-ups:** OCI `common` chart to drop binaries; optionally let ArgoCD manage the
  SealedSecrets + a second Application; App-of-Apps once a platform app is added.
