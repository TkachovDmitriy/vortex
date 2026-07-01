# ADR-010: Cloud + IaC — OpenTofu provisioning an ephemeral k3s on AWS

- **Status:** Accepted (design-first — no infra built yet; `infra/` skeleton only)
- **Date:** 2026-06-26
- **Deciders:** project owner

## Context

The **cloud + IaC slice is the last 🔴 core, offer-blocking item** on the roadmap.
DevOps job postings weight Terraform/AWS heavily, so "I deployed vortex to a real
cloud, provisioned by code, with remote state" is a gate for the first offer — not a
nice-to-have. Everything else core (Docker, Kubernetes on kind, the metrics/logs
observability slices) is already done; this closes the zero→production story.

The owner's IaC starting point is **strong, not zero**: real Terraform on AWS —
reusable modules, **remote state in S3**, IAM roles, Lambda + CloudFront. So the
*tool mechanics* (HCL, modules, backends, state locking) are **not the CV gap**. Per
the Learning Protocol that means no syntax tutoring; the value here is the **decisions**
— tool choice, cloud topology, and cost engineering under a constrained budget.

Two external facts shape the decision:

1. **Terraform relicensed to BSL 1.1 (Aug 2023); OpenTofu is the MPL-2.0 Linux
   Foundation fork.** The owner already knows Terraform, so OpenTofu is a drop-in
   (same HCL, same workflow) that doubles as the **CV differentiator** — "I migrated
   to OpenTofu and here's the licensing/governance reasoning" beats "I used Terraform
   like everyone else." (This is why CLAUDE.md mandates `tofu`, not `terraform`.)

2. **AWS changed the free tier on 2025-07-15.** New accounts no longer get the classic
   12-month / 750-EC2-hours plan; they get a **credit-based plan (~$200 credits, valid
   ~6 months or until exhausted)**. And **EKS has never been free** — its control plane
   is a flat ~$73/month per cluster, which would drain the entire credit balance in
   about a month for zero learning payoff. The free-tier compute instance
   (**t3.micro, 1 GB RAM**) also **cannot hold k3s + 5 services + Postgres** — k3s alone
   wants ~512 MB–1 GB; the stack would OOM.

The app already runs unchanged on kind via Helm (ADR-014). Golden rule #5 ("same app
runs at every stage") and the CLAUDE.md convention ("Terraform/OpenTofu provisions
cloud infra only — apps deploy via Helm/ArgoCD, never via `kubernetes_*` resources")
both constrain *how* the app gets onto the cloud cluster.

## Decision

**Provision a single, right-sized, ephemeral k3s node on AWS with OpenTofu; keep
always-free primitives (VPC/IAM/S3) separate from paid compute; store state remotely
in S3 with native locking; deploy the unchanged app via Helm. Managed EKS is deferred
to Phase B.**

1. **OpenTofu (`tofu`), not Terraform.** Drop-in fork; the owner's Terraform knowledge
   transfers 1:1. Chosen for the MPL-2.0 license (vs. Terraform's BSL 1.1) and as the
   deliberate CV differentiator. Pin the `tofu` version and the AWS provider version.

2. **k3s on one ephemeral EC2 — not EKS, not an always-on t3.micro.** The cluster is a
   **single right-sized instance** (`t3.small` 2 GB minimum, `t3.medium` 4 GB if the
   metrics stack rides along), brought up with `tofu apply` for a demo and torn down
   with `tofu destroy` after. At ~$0.04/hr a t3.medium is ≈ **$1 per full day of
   demoing** — the ~$200 credits then cover *months* of real use. This is the
   **cost-engineering decision the slice exists to demonstrate**: size compute to the
   workload and make it ephemeral, rather than leaving a too-small free instance
   running. Managed K8s (EKS, IRSA, managed node groups) is explicitly **Phase B,
   on-the-job** per the roadmap.

3. **Separate always-free primitives from paid compute.** **VPC, subnet, IGW, route
   table, security group, IAM, and the S3 state bucket are free (or effectively free)
   and may persist.** Only the **EC2 node + EIP** cost money and are the ephemeral
   part. The module split (Decision §6) mirrors this seam so `destroy` of the compute
   layer leaves the cheap, stable network/state layer intact.

4. **Remote state in S3 with native S3 locking — no DynamoDB.** S3 added conditional
   writes in 2024, so the `s3` backend now does state locking natively
   (`use_lockfile = true`); the legacy DynamoDB lock table is no longer required. State
   is **encrypted** (SSE), the bucket **versioned** and **public-access-blocked**.
   (Updates the owner's existing S3-state pattern to the current best practice.)

5. **Bootstrap the state bucket once, then migrate.** Chicken-and-egg: the bucket that
   holds remote state cannot itself be created by a tofu run that already uses that
   bucket as a backend. Resolve with the standard two-step — the `state-backend` root
   applies with **local state**, then `tofu init -migrate-state` moves to S3. The
   bucket is a one-time bootstrap, not part of the per-demo lifecycle.

6. **Reusable `modules/` + `environments/` layout** (sketched below). Composable
   modules (`network`, `compute`, `state-backend`) consumed by thin per-environment
   roots. One environment (`dev`) now; the structure is ready for `staging`/`prod`
   without restructuring. Modules expose explicit `variables`/`outputs`; roots wire
   them and own the backend config.

7. **OpenTofu provisions cloud infra only; the app arrives via Helm.** k3s is installed
   through EC2 **`user_data` / cloud-init** (download + run the k3s installer, write the
   kubeconfig). The vortex Helm release (ADR-014) is applied **separately** against the
   resulting cluster — **never** through `kubernetes_*`/`helm_*` TF resources (CLAUDE.md
   convention; keeps the same-app-everywhere proof honest and avoids provider-in-provider
   coupling). At the GitOps phase (Phase 4) ArgoCD takes over the app sync.

8. **Single region, least-privilege, nothing secret committed.** Pin one region
   (`eu-central-1` / Frankfurt — closest, and where the owner's S3 already lives).
   Security group opens only what's needed (`6443` kube-API and `80/443` ingress from
   the owner's IP; `22` SSH likewise IP-scoped). No credentials, kubeconfig, or
   `*.tfstate` in git (`.gitignore`); auth via the local AWS profile / env, not
   hardcoded keys.

## Consequences

**Positive**

- Closes the last offer-blocking slice: a real, code-provisioned cloud deploy with
  remote state — the headline DevOps résumé line.
- **Near-zero cost** within the credit-based free tier: free primitives persist, paid
  compute is ephemeral and right-sized (~$1/demo-day).
- **OpenTofu + the BSL→MPL reasoning** is a concrete differentiator over the
  Terraform-default crowd, while reusing the owner's existing HCL skill.
- The unchanged app proves golden rule #5 (compose → kind → cloud, same Helm release).
- Module/env seam matches the cost seam (cheap-stable vs. paid-ephemeral) and is ready
  for ArgoCD (Phase 4) and more environments.

**Negative / risks**

- **Single-node k3s is not HA** and is *not* what employers run in prod (that's EKS).
  *Mitigation:* explicitly scoped as the cheap core slice; EKS/HA is Phase B and named
  as such — the judgment (cost vs. fidelity) is the point.
- **Ephemeral cluster = re-provision per demo**; nothing is "always up" to click on.
  *Mitigation:* `apply`/`destroy` is fast and scripted; the cost trade is deliberate.
  An always-on option remains a one-line change if a live URL is ever needed.
- **t3.small (2 GB) is tight** for app + Postgres + the metrics stack together.
  *Mitigation:* t3.medium (4 GB) for full-stack demos; or skip the LGTM stack on cloud
  (it's already proven on kind) and deploy app + data only.
- **`user_data` k3s install is imperative-ish** (a bootstrap script, not declarative
  infra). *Mitigation:* acceptable and idiomatic for single-node k3s; the declarative
  story lives in the K8s manifests/Helm, not the node bootstrap.
- **Credit-based free tier expires (~6 months / on exhaustion).** *Mitigation:*
  ephemeral compute stretches credits for months; set a billing alarm; the cheap
  always-free primitives survive regardless.

## Alternatives considered

- **Managed AWS EKS** — most production-realistic (managed control plane, IRSA, node
  groups), but ~$73/mo control plane drains the ~$200 credits in ~a month for no
  learning the cheap path doesn't also teach. Roadmap explicitly defers managed K8s to
  Phase B. Rejected for the core slice.
- **Always-on free-tier t3.micro (1 GB)** — genuinely free, but cannot run k3s + 5
  services + Postgres (OOM). Rejected; "I left a free micro running" is also a weaker
  story than deliberate cost engineering.
- **k3s on Hetzner / DigitalOcean droplet** — cheaper always-on (~€4–5/mo) and simpler
  billing, but a new provider for the owner and **less résumé-relevant than AWS**
  (AWS dominates job postings). Rejected in favour of leveraging + showcasing AWS.
- **Managed DigitalOcean DOKS** — free control plane, ~$12/mo node, dead simple, but a
  new provider and it **hides the k3s bootstrap** (the cluster just appears) — less to
  demonstrate. Rejected.
- **Terraform (not OpenTofu)** — what the owner already knows, but BSL-licensed and the
  default everyone lists; OpenTofu is the same workflow with a better license story and
  a CV edge. Rejected per CLAUDE.md.
- **DynamoDB state-lock table** — the pre-2024 standard, but S3 native locking
  (`use_lockfile`) makes it redundant overhead. Rejected.
- **Deploy the app via `kubernetes_*` / `helm_*` TF resources** — fewer moving parts,
  but violates the CLAUDE.md convention, couples app lifecycle to infra runs, and
  breaks the "same Helm release everywhere" proof. Rejected; Helm/ArgoCD owns the app.
