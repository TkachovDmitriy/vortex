# ADR-017: Container image registry — Amazon ECR + node IAM role

- **Status:** Accepted (design-first — `ecr` module + IAM role to be built)
- **Date:** 2026-07-05
- **Deciders:** project owner

## Context

Deploying vortex to the cloud k3s node (ADR-010) surfaced the first hard blocker:
the Helm charts reference **local images** (`vortex-<svc>:latest`,
`pullPolicy: IfNotPresent`) that worked on kind via `kind load`. The cloud node has
no such images and nowhere to pull them from → `ImagePullBackOff`. The stack needs a
real container registry.

The project is already all-in on **AWS + OpenTofu**, so the registry choice is really
"AWS-native or not". **Amazon ECR** keeps everything in one cloud, is provisioned by
the same IaC, and authenticates via **IAM** rather than static tokens — a cohesive,
résumé-strong story ("my IaC provisions the registry and the cluster pulls from it
with an instance role"). The alternative (GitHub Container Registry) is simpler for
public images but sits outside the AWS/IAM story.

Two wrinkles shape the decision:

1. **ECR auth tokens are short-lived (~12h).** On **EKS**, the kubelet has a built-in
   ECR credential provider and this is invisible. On **vanilla k3s** it is not handled
   automatically — the node must obtain and refresh an ECR token itself.

2. **This reverses ADR-010's "no instance profile" call.** ADR-010 deliberately skipped
   an EC2 instance role because nothing on the node needed the AWS API. Pulling from
   ECR *is* an AWS API call, so the node now needs an IAM role with ECR read — a clean
   example of "requirements changed → the earlier decision changes".

## Decision

**Use private Amazon ECR, one repository per service, provisioned by OpenTofu. The k3s
node authenticates to ECR via an EC2 instance IAM role (no static creds); a token is
refreshed into k3s's `registries.yaml` on a timer. Helm points `global.imageRegistry`
at the ECR host.**

1. **Amazon ECR, private, one repo per service** (`vortex-gateway`, `vortex-orders`,
   `vortex-inventory`, `vortex-notifications`, `vortex-analytics`). Per-service repos
   are the ECR norm (independent lifecycle policies, scan results, and IAM scoping) and
   line up with per-service deploys (ADR-008). Provisioned by a new `infra/modules/ecr`.

2. **Node pulls via an EC2 instance IAM role** carrying the AWS-managed
   `AmazonEC2ContainerRegistryReadOnly` policy — **no static registry credentials
   anywhere**. This adds the instance profile ADR-010 skipped; documented as a
   deliberate reversal now that ECR is a requirement.

3. **Auth via a Kubernetes CronJob that refreshes an `imagePullSecret`.** A CronJob in
   the `vortex` namespace runs every ~11h: `aws ecr get-login-password` (the pod gets
   AWS creds from the **node's instance role via IMDS** — no static keys) piped into a
   `kubectl apply` that (re)writes a `docker-registry` Secret; pods reference it via
   `imagePullSecrets`. Chosen over host-level mechanisms (systemd timer /
   `amazon-ecr-credential-helper`) because it is **declarative, in-git, portable across
   any k8s, doesn't touch the node OS, and fits the GitOps phase** — the k3s node has no
   native ECR integration, so keeping auth in-cluster is cleaner than bespoke host
   wiring. **On EKS this whole mechanism is unnecessary** (see §7).

4. **Image naming + Helm wiring.** Images are tagged
   `<account>.dkr.ecr.eu-central-1.amazonaws.com/vortex-<svc>:<tag>`. The umbrella's
   `global.imageRegistry` is set to the ECR host, so every subchart's
   `vortex-<svc>` repository resolves to its ECR path with no per-chart edits.

5. **Scan-on-push + lifecycle policy.** Repos enable basic **scan-on-push** (a cheap
   vulnerability signal, nods to the supply-chain theme) and an **expire-untagged /
   keep-last-N lifecycle policy** so storage stays within free-tier limits.

6. **k3s now; the kubelet credential provider is the EKS-era improvement.** The chosen
   CronJob (§3) is the pragmatic path on self-managed k3s. **EKS bundles the
   `ecr-credential-provider` kubelet plugin**, which authenticates every pull from the
   node's IAM role automatically — no CronJob, no Secret, no refresh. That is the
   documented evolution when this moves to EKS (Phase B); replicating it by hand on k3s
   (sourcing the binary + kubelet args) is more host wiring than the CronJob is worth
   here. (Mirrors the "later evolution" pattern of ADR-005/014.)

## Consequences

**Positive**

- Single-cloud, IaC-provisioned registry; the cluster pulls with an **IAM role, zero
  static credentials** — the strongest part of the story.
- Unblocks the cloud Helm deploy; `global.imageRegistry` is a one-line switch.
- Teaches the real ECR mechanics (12h token, node-side refresh) that EKS hides.
- Scan-on-push adds a supply-chain signal for almost no cost.

**Negative / risks**

- **Token-refresh machinery on k3s** (timer + `registries.yaml`) is bespoke; EKS would
  make it free. *Mitigation:* small, explicit, documented — and itself a learning point.
- **ECR is not free forever** — 500 MB private storage free for 12 months, then paid
  (small for these images). *Mitigation:* lifecycle policy expires old/untagged layers.
- **Five repos to manage.** *Mitigation:* created/destroyed as one `for_each` module.
- **Bootstrap ordering:** repos must exist before `docker push`, and the node role must
  exist before it can pull. *Mitigation:* both provisioned by `tofu apply` before deploy.

## Alternatives considered

- **GitHub Container Registry (ghcr.io)** — simplest for public images, no AWS auth
  dance. But it sits outside the AWS/IAM narrative and needs a PAT or public repos;
  weaker fit for an AWS-centric portfolio. Rejected in favour of the cohesive AWS story.
- **Docker Hub** — familiar, but anonymous/free pull rate limits bite CI and clusters,
  and it adds a third-party account. Rejected.
- **Single mono-repository with per-service tags** (`vortex:gateway-latest`) — fewer
  objects, but loses per-service lifecycle/scan/IAM granularity. Rejected for per-repo.
- **Kubelet `ecr-credential-provider` plugin** — the *correct* node-native mechanism
  (what EKS bundles): kubelet auto-authenticates every pull from the instance role, no
  Secret/refresh. But on k3s the binary must be sourced and kubelet args wired by hand —
  more host coupling than the in-cluster CronJob. **Deferred as the EKS-era improvement
  (Decision §6)**, not chosen for k3s now.
- **Host-level refresh (systemd timer / `amazon-ecr-credential-helper` writing
  `registries.yaml`)** — works, but modifies the node OS, is k3s-specific, and sits
  outside git/GitOps. Rejected in favour of the declarative in-cluster CronJob.
- **Static long-lived creds in `registries.yaml`** — impossible anyway (ECR tokens
  expire in 12h) and insecure. Rejected.
- **Reuse the "no instance profile" stance from ADR-010** — no longer valid once the
  node must call the ECR API. Explicitly reversed here.
