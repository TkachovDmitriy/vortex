# Runbook — dev cluster bring-up (and teardown)

End-to-end procedure to bring the **ephemeral** dev k3s cluster up on AWS, restore the
full GitOps stack, verify the app works, and tear it back down to stop billing.

**Two audiences, one doc:**
- **Operational** — the exact, copy-pasteable sequence to bring the cluster up next time (steps 1–8).
- **Explanatory** — the mental model and talking points to *narrate* this in an interview
  ("walk me through your GitOps setup"). See [Interview walkthrough](#interview-walkthrough--how-to-explain-this).

The compute layer is **ephemeral by design** (ADR-018): the node is created per working
session and destroyed after, so you pay for EC2 only while you use it. Everything below
is idempotent and reproducible — a fresh node is always a clean slate.

- Infra decisions: ADR-010 (OpenTofu/k3s/AWS), ADR-017 (ECR), ADR-018 (ephemeral layering)
- GitOps decisions: ADR-019 (ArgoCD + Sealed Secrets), ADR-020 (App-of-Apps + key persistence)
- GitOps detail: [`platform/gitops/README.md`](../../platform/gitops/README.md)

> **Verified live end-to-end on 2026-08-23.** The commands below are the exact sequence
> that worked, not a sketch.

## Prereqs

- Inside the dev shell: `nix develop` (provides `tofu`, `kubectl`, `kubeseal`, `argocd`, `gh`).
- AWS creds valid and pointing at the right account:
  ```bash
  aws sts get-caller-identity          # expect account 709569057692, user vortex-user
  ```
- Persistent infra (network/ECR/CI) already in state — it survives compute teardown:
  ```bash
  tofu -chdir=infra/environments/dev state list   # module.network / module.ecr / module.ci_oidc present, module.compute absent
  ```

---

## 1. Bring the node up (compute layer only)

```bash
tofu -chdir=infra/environments/dev apply -target=module.compute
```

- `-target=module.compute` touches **only** the EC2 node + EIP. Network/ECR/CI are untouched.
- Review the plan (should be `+ aws_instance.node`, `+ aws_eip.node` and bindings — nothing
  destroyed), then `yes`.
- ⚠️ **Billing starts here.** Note the `public_ip` output — it is a **new EIP each time**.

## 2. Fetch the kubeconfig and point kubectl at it

k3s writes its kubeconfig with `127.0.0.1`; we pull it over SSH and rewrite the host to the EIP.
Use the `kubeconfig_hint` output verbatim, or:

```bash
EIP=$(tofu -chdir=infra/environments/dev output -raw public_ip)
ssh -o StrictHostKeyChecking=accept-new ubuntu@"$EIP" \
  "sudo sed \"s/127.0.0.1/$EIP/\" /etc/rancher/k3s/k3s.yaml" > vortex-dev.kubeconfig
export KUBECONFIG=$PWD/vortex-dev.kubeconfig   # the dev shell auto-exports this if the file exists
```

Wait ~1–2 min for cloud-init, then confirm the node and system pods are healthy:

```bash
kubectl get nodes            # one node, STATUS Ready
kubectl get pods -A          # coredns / traefik / metrics-server Running
```

## 3. Bootstrap the GitOps engines (day-0, imperative)

ArgoCD and the sealed-secrets controller can't deploy themselves — install them by hand once:

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/latest/download/controller.yaml
```

Wait for them (fresh ArgoCD pods may flash `CreateContainerConfigError` for a few seconds
while their ConfigMaps propagate — this self-heals):

```bash
kubectl get pods -n argocd
kubectl get pods -n kube-system -l name=sealed-secrets-controller
```

## 4. Secrets — pick ONE branch

The controller holds the private key that decrypts committed `SealedSecret`s. Which path you
take depends on whether you have that key backed up.

### 4a. Key IS backed up → restore (the normal path)

```bash
kubectl apply -f vortex-dev-sealed-secrets-key.backup.yaml     # out-of-band file, NOT in git
kubectl delete pod -n kube-system -l name=sealed-secrets-controller   # restart to pick up the key
```

Committed SealedSecrets stay decryptable — nothing else to do.

### 4b. Key is LOST / first ever bring-up → re-seal

A fresh controller generated a **new** key, so the committed SealedSecrets (sealed with the old
key) are undecryptable. Re-seal the plaintext secrets under the new key, **immediately back the
new key up**, then commit via PR (ArgoCD reads `develop`):

```bash
# re-seal all three under the new key (kubeseal fetches the pubkey via KUBECONFIG)
kubeseal --format yaml < deploy/k8s/data/postgres/secret.yaml   > platform/gitops/sealed-secrets/postgres-sealedsecret.yaml
kubeseal --format yaml < deploy/k8s/services/orders/secret.yaml > platform/gitops/sealed-secrets/orders-sealedsecret.yaml
kubeseal --format yaml < deploy/k8s/services/inventory/secret.yaml > platform/gitops/sealed-secrets/inventory-sealedsecret.yaml

# back up the NEW key out-of-band and lock it down (gitignored, never commit)
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > vortex-dev-sealed-secrets-key.backup.yaml
chmod 600 vortex-dev-sealed-secrets-key.backup.yaml

# ship the re-sealed secrets to develop via PR
git checkout -b fix/reseal-secrets
git add platform/gitops/sealed-secrets/ && git commit -m "[Fix] gitops: re-seal secrets under new cluster sealing key"
git push -u origin fix/reseal-secrets && gh pr create --base develop --fill
gh pr merge --squash --delete-branch
git checkout develop && git pull
```

> Store the key backup in a password manager / AWS Secrets Manager. From then on, future
> bring-ups use path 4a (restore) — no re-seal needed. (ADR-020; the ESO migration will
> remove this manual step entirely.)

## 5. ecr-auth + data layer (day-0, imperative)

ecr-auth keeps a short-lived ECR pull token refreshed so the node can pull private images:

```bash
kubectl create namespace vortex
kubectl apply -n vortex \
  -f deploy/k8s/platform/ecr-auth/serviceaccount.yaml \
  -f deploy/k8s/platform/ecr-auth/rbac.yaml \
  -f deploy/k8s/platform/ecr-auth/configmap.yaml \
  -f deploy/k8s/platform/ecr-auth/cronjob.yaml
kubectl create job --from=cronjob/ecr-cred-refresh ecr-cred-refresh-init -n vortex
kubectl patch serviceaccount default -n vortex -p '{"imagePullSecrets":[{"name":"ecr-pull-secret"}]}'
# wait ~20–30s, then:
kubectl get job ecr-cred-refresh-init -n vortex        # Complete 1/1
kubectl get secret ecr-pull-secret -n vortex           # type dockerconfigjson
```

Data layer (Postgres + NATS) — **do NOT apply the plaintext `secret.yaml`** (the Secret comes
from the SealedSecret via ArgoCD in step 6, so `postgres-0` stays pending until then):

```bash
kubectl apply -n vortex \
  -f deploy/k8s/data/postgres/init-configmap.yaml \
  -f deploy/k8s/data/postgres/service.yaml \
  -f deploy/k8s/data/postgres/statefulset.yaml \
  -f deploy/k8s/data/nats/service.yaml \
  -f deploy/k8s/data/nats/statefulset.yaml
```

## 6. Hand everything to ArgoCD (App-of-Apps)

The **only** Application you apply by hand. It creates the child apps; from here ArgoCD owns
the cluster state and reads the `develop` branch.

```bash
kubectl apply -f platform/gitops/root.yaml
```

- sync-wave 0 → `vortex-sealed-secrets` applies the SealedSecrets → controller decrypts them →
  `postgres-secret`/`orders-secret`/`inventory-secret` appear → `postgres-0` unblocks.
- sync-wave 1 → `vortex` (Helm umbrella) deploys the 5 services, pulling images from ECR.

> Do **not** create child apps by hand in the ArgoCD UI — that's an anti-pattern (the app
> wouldn't be in git). `root.yaml` is the single source.

## 7. Verify

```bash
kubectl get applications -n argocd     # vortex-root / vortex-sealed-secrets / vortex → Synced / Healthy
kubectl get pods -n vortex             # postgres-0, nats-0, + 5 services all Running
```

Functional smoke test (gateway → orders → inventory sync + `order.created` → NATS fan-out):

```bash
kubectl port-forward -n vortex svc/gateway 3000:3000 >/dev/null 2>&1 &
sleep 2
curl -s localhost:3000/health; echo
curl -s -XPOST localhost:3000/orders -H 'content-type: application/json' -d '{"item":"widget","quantity":1}'; echo
kubectl logs -n vortex deploy/notifications --tail=5   # 📧 order <id> → created
kubectl logs -n vortex deploy/analytics    --tail=5    # 📊 recorded order <id> → created
```

Same `orderId` echoed by both consumers = the full sync + async path works.

## 8. Teardown (stop billing) ⚠️

```bash
kill %1 2>/dev/null                                          # stop the port-forward
tofu -chdir=infra/environments/dev destroy -target=module.compute
```

Plan should destroy **only** `aws_instance.node` + `aws_eip.node` (never ECR/network/IAM).
ECR images persist, so the next bring-up is fast. `vortex-dev.kubeconfig` becomes stale after
destroy (a new bring-up gets a fresh EIP + kubeconfig).

---

## Notes / not covered by this runbook

- **L7 Gateway API (ADR-013) is NOT part of the bootstrap.** Its manifests live in
  `deploy/k8s/platform/gateway/` + `deploy/k8s/services/gateway/httproute.yaml`, outside the
  Helm umbrella, so ArgoCD does not deploy them. Until applied by hand, reach the gateway via
  `kubectl port-forward` (step 7).
- **Image tags:** `global.imageTag` is written by CI's image-bump job on a develop push
  (ADR-021). Until the first bump, services run their per-chart fallback `image.tag`.
- **Secrets evolution:** the manual key restore/re-seal dance goes away with the planned
  External Secrets Operator + AWS Secrets Manager migration (ADR-020 flags it).

---

## Interview walkthrough — how to explain this

If asked *"walk me through how your environment comes up"*, the story is **five decisions**,
not a pile of commands. Lead with the decision, then the mechanism.

**1. Layered infra with an ephemeral compute tier (cost discipline).**
Cheap, durable infra (VPC, ECR, IAM/OIDC) lives permanently in OpenTofu state. The one expensive
thing — the EC2 node — is a **separately targeted layer** I `apply`/`destroy` per session
(`-target=module.compute`). *So I pay for compute only while working, without re-provisioning the
network or re-pushing images.* Shows: Terraform/OpenTofu module design, targeting, cost-awareness.

**2. Day-0 vs day-2 split (the bootstrap paradox).**
ArgoCD and the sealed-secrets controller **can't deploy themselves** — that's a chicken-and-egg,
so they're an imperative **day-0 bootstrap** (`kubectl apply`). Everything after that — the apps,
the secret manifests — is **day-2**, owned declaratively by ArgoCD. *I draw the line at "what can
git-driven reconciliation manage" vs "what has to exist before reconciliation can run."*

**3. Pull-based GitOps + App-of-Apps.**
I apply exactly **one** root `Application` by hand; it generates the child apps
(`sealed-secrets`, `services`). Git — the `develop` branch — is the single source of truth;
ArgoCD continuously reconciles and **self-heals drift** (a manual `kubectl scale` gets reverted).
**Sync-waves** order it: secrets (wave 0) land before the pods that consume them (wave 1). *No one
runs `kubectl apply` against prod; the cluster converges to what's in git.*

**4. Secrets that are safe to commit (Sealed Secrets + the key tradeoff).**
Asymmetric crypto: the controller holds a private key and publishes a public cert; `kubeseal`
encrypts values with the cert, so the resulting `SealedSecret` is safe in git — **only the
in-cluster controller can decrypt it.** The honest tradeoff I can discuss: the key is
**per-cluster**, so losing it orphans every SealedSecret. I mitigate by **persisting the key
out-of-band** (restore on a new cluster) — and I flag the cleaner evolution: **External Secrets
Operator + AWS Secrets Manager**, where git holds only references and the node's IAM role pulls
the values, so a new cluster needs **zero** manual secret steps. *Shows I understand the mechanism
AND its operational limits, not just that I wired it up.*

**5. The app proves both communication patterns on purpose.**
A single order request exercises the **synchronous** path (gateway → orders → inventory over REST,
"I need an answer now" — ADR-003) *and* the **asynchronous** path (orders emits `order.created` to
**NATS JetStream**, which fans out to two independent consumers, "this happened, react whenever" —
ADR-006). *The business logic is trivial on purpose — the point is the architecture is deliberate.*

**And the delivery loop that ties it together:** CI builds, Trivy-scans, and pushes each image by
**git-SHA** to ECR (keyless OIDC, ADR-021); an **image-bump** step writes that SHA into git;
ArgoCD deploys it. *There is no `kubectl` in the deploy path — a git commit is the deploy.*

### Likely follow-up questions (and the honest answers)

- *"Why not Terraform for the k8s resources?"* — Deliberate boundary: OpenTofu provisions **cloud
  infra only**; apps are delivered by Helm/ArgoCD. Mixing `kubernetes_*` TF resources couples app
  lifecycle to infra state and fights GitOps. (Also: anything TF reads lands in state in plaintext —
  a reason secrets never flow through TF.)
- *"How do you roll back?"* — `git revert` the image-bump (or any) commit; ArgoCD reconciles back.
- *"What's not production-grade yet?"* — single node (no HA), sealed-secrets key is manual (ESO is
  the fix), L7 Gateway API isn't in the bootstrap, no PDB/HPA/SLOs yet. I know the gaps and the
  sequence to close them.
