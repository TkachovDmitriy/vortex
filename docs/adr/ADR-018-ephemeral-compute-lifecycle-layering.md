# ADR-018: Ephemeral compute, persistent infra — lifecycle layering & teardown

- **Status:** Accepted (current: `-target` teardown; documented evolution: split roots)
- **Date:** 2026-07-08
- **Deciders:** project owner

## Context

The cloud slice (ADR-010) is deliberately **ephemeral**: k3s on a single EC2, `apply`
for a demo, `destroy` after. After the first full deploy, tearing down surfaced a real
lifecycle question — the resources in the `dev` root do **not** share a lifecycle or a
cost profile:

| Resource | Cost | Changes between sessions? |
|---|---|---|
| **Compute** (EC2 + EIP + instance IAM) | **paid** (~$0.5/day running) | recreated every session |
| Network (VPC/subnet/SG/IGW) | free | no |
| **ECR + images** | ~$0.10/GB-mo (≈ 5¢ for our ~450 MB) | no — images are build artifacts |
| S3 state bucket (bootstrap) | cents | no |

A plain `tofu destroy` on `dev` both **over-reaches and fails**: it tries to delete the
**non-empty ECR repos** (`RepositoryNotEmptyException` — would need `force_delete` and
then a full **re-push every session**) and needlessly tears down the free network. What
we actually want on teardown: **stop the only thing that costs real money (compute)**
and **keep the free/cents persistent infra** so the next `apply` is fast and needs no
image re-push. k3s is what makes this cheap-ephemeral model viable at all — the whole
cluster lives on one destroyable instance, unlike EKS's always-on ~$73/mo control plane
(ADR-010).

## Decision

**Teardown destroys the compute layer only; network, ECR, and state persist. Do it via
`-target` now, and split state into a persistent layer + an ephemeral layer as the
documented evolution.**

1. **Per-session teardown = compute only.**
   ```bash
   tofu destroy -target=module.compute   # EC2 + EIP + instance IAM → $0
   ```
   Network (free) + ECR/images (cents) + state bucket stay. Next session: `tofu apply`
   recreates compute against the existing network/ECR; **images are already in ECR** →
   no re-push. (The k3s cluster itself is gone with the node — the k8s deploy steps
   re-run each session; that's inherent to an ephemeral cluster, not a cost issue.)

2. **k3s enables the model.** A single destroyable EC2 hosts the whole cluster, so
   "destroy compute" reclaims 100% of the compute spend. Managed EKS could not be torn
   down this cheaply (flat control-plane cost) — reinforces the k3s-for-the-demo call.

3. **`-target` is a stopgap, not the end state.** HashiCorp explicitly discourages
   routine `-target` use (it's for exceptional state recovery). Relying on it every
   teardown is a code smell — one forgotten flag and you nuke or orphan the wrong thing.

4. **Documented evolution — split state by lifecycle into two roots.** Move the
   **persistent** resources (network + ECR) into a long-lived root (alongside the
   existing `bootstrap`/state layer), leaving **compute** in the ephemeral `dev` root.
   Then a plain `tofu destroy` on the ephemeral root is **complete and safe** — no
   `-target` needed. Cross-layer references use **remote-state data sources**
   (`terraform_remote_state`) or passed values instead of direct module wiring.

   ```
   infra/environments/
   ├── bootstrap/    # state bucket           (create once)
   ├── platform/     # network + ECR          (persistent — rarely destroyed)   ← new
   └── dev/          # compute (k3s node)      (ephemeral — apply/destroy freely)
   ```

5. **Layering is a recognised IaC best practice** — separate infra by **change cadence
   and blast radius**: long-lived networking / registries / IAM / DNS in one state,
   frequently-recreated compute/app infra in another. Benefits: a mistake in the
   ephemeral root **can't reach** the persistent VPC/registry; smaller/faster state and
   plans; per-layer access control. Cost: cross-root references add wiring (remote
   state), and there are now multiple states to manage.

## Consequences

**Positive**

- Teardown stops 100% of real cost (compute) while keeping cents-level persistent infra.
- Fast re-apply: images stay in ECR → **no re-push**; network is already up.
- Once layered (§4), teardown is a clean `tofu destroy` with **no `-target`** and a
  small blast radius — the persistent layer is unreachable from the ephemeral one.

**Negative / risks**

- **`-target` today is a smell** — works, but easy to misfire and not idiomatic.
  *Mitigation:* the layering evolution (§4) removes the need for it.
- **Layering adds wiring** — cross-root `terraform_remote_state` data sources and two
  states to run/track. *Mitigation:* standard pattern; the blast-radius win is worth it.
- **`state mv` migration** — moving `network`/`ecr` to a new root requires
  `tofu state mv` (or destroy+recreate). *Mitigation:* one-time; ECR would need
  re-push if recreated, so use `state mv` to preserve images.

## Alternatives considered

- **`force_delete = true` on ECR + full `tofu destroy`** — simplest teardown (one
  command, no `-target`), but **deletes the images every session** (re-push each apply,
  slow) and tears down the free network for no benefit. Rejected as the routine path;
  acceptable only for a true full wipe.
- **Leave everything running** — no teardown friction, but pays ~$0.5/day for an idle
  node. Rejected — the slice is a demo, not a live service.
- **Single root + `-target` forever** — the current stopgap; works but non-idiomatic and
  fragile. Kept **only until** the layering split (§4) is done.
- **One root, mark compute with `create_before_destroy`/lifecycle tricks** — doesn't
  address the cross-lifecycle mismatch; the clean answer is separate state, not lifecycle
  meta-args. Rejected.
