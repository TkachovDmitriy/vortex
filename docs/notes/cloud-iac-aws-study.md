# Cloud + IaC — theory through practice (interview revision)

Study notes distilled from actually building the vortex cloud slice (OpenTofu → AWS →
k3s → ECR). Each topic: **concept → why → what we did (anchor) → interview Qs**.
Re-read before interviews. Related: ADR-010 (cloud/IaC), ADR-017 (ECR).

---

## 1. AWS networking

### CIDR (`/16`, `/24`, `/32`)
- **Concept:** IPv4 = 32 bits; `/N` freezes N bits as the network part, the rest are hosts. `/16` = 65 536 addrs, `/24` = 256, `/32` = 1. Smaller number after `/` = bigger network; each `+1` halves the range.
- **Why these:** two rules — (1) **RFC 1918** private ranges (`10.0.0.0/8`, `172.16/12`, `192.168/16`) for internal nets; (2) AWS VPC size limit `/16`–`/28`. `/16` VPC + `/24` subnet = convention (octet-aligned → readable; 3rd octet = subnet id).
- **Anchor:** VPC `10.0.0.0/16`, subnet `10.0.1.0/24`, SG scoped to my IP `/32`. AWS reserves **5 IPs per subnet** → `/24` = 251 usable.

### VPC / subnet / IGW / route table
- **Public subnet** = subnet whose **route table** has `0.0.0.0/0 → internet gateway`. The implicit **`local` route** (VPC CIDR) is auto-added, undeletable, and makes **all subnets in a VPC mutually routable** by default. Isolation between subnets is a **firewall** (SG/NACL) decision, not routing.
- **Anchor:** `network` module = VPC + public subnet (`map_public_ip_on_launch`) + IGW + route table (`0.0.0.0/0→igw`) + SG.

### Security Group (stateful firewall)
- **Concept:** SG attached to the resource (ENI). **Stateful** — allow a request in, the reply is auto-allowed out (no return rule needed). Contrast **NACL** = stateless, subnet-level, must open both directions.
- **Anchor:** ingress `22`/`6443`/`80`/`443` scoped to `allowed_cidr` (my `/32`), egress all (node pulls installer/images). SG-to-SG references (source = another SG) for tiered access instead of CIDRs.

**Interview Qs**
- What makes a subnet "public"? → route to an IGW (+ public IP), not the subnet itself.
- SG vs NACL? → SG stateful/per-ENI; NACL stateless/per-subnet.
- Can subnets in a VPC talk by default? → yes, via the `local` route; you *restrict* with SG/NACL.
- Why `/16`+`/24`? → RFC1918 + AWS limits; octet-aligned convention for readability/headroom.

---

## 2. IAM & IMDS

### Role vs policy vs instance profile
- A **role** has **two** policies: **trust** (`assume_role_policy` — *who* may assume it, e.g. `ec2.amazonaws.com`) and **permission** (attached — *what* it may do, e.g. ECR read). Both required.
- **Instance profile** = wrapper that lets an EC2 instance *wear* a role (EC2 can't attach a role directly).
- **Managed policy** (`arn:aws:iam::aws:policy/...`) = AWS-maintained; vs inline/custom.
- **Anchor:** node role: trust `ec2.amazonaws.com` + managed `AmazonEC2ContainerRegistryReadOnly` + instance profile → node pulls ECR with **no static creds**.

### IMDS (Instance Metadata Service)
- **Concept:** link-local `http://169.254.169.254` — instance reads metadata **and the role's temporary creds** from here.
- **IMDSv2** (`http_tokens=required`): two-step — **PUT** to get a session token, then **GET** with the token header. Blocks the SSRF-prone IMDSv1.
- **Hop limit:** `http_put_response_hop_limit` default **1** blocks **pods** (an extra network hop via CNI). Set **2** so in-cluster pods can reach IMDS.
- **Anchor:** `metadata_options { http_tokens=required, hop_limit=2 }` so the ECR-refresh CronJob pod can assume the node role.

### No-static-creds principle
- Identity over stored secrets: EC2 → **instance role** via IMDS; CI → **OIDC** assume-role (short-lived token, no `AWS_ACCESS_KEY` stored). `aws ecr get-login-password | docker login --password-stdin` mints a 12h token, not a saved password.

**Interview Qs**
- Trust vs permission policy? → who-can-assume vs what-it-can-do.
- Why an instance profile, not a role directly on EC2? → EC2 references a profile that wraps the role.
- IMDSv1 vs v2? → v2 = token (PUT→GET), mitigates SSRF.
- Pods can't reach IMDS — why? → hop limit 1; set 2.
- How does CI auth to AWS without stored keys? → OIDC federation → assume-role → temp creds.

---

## 3. OpenTofu / IaC

### tofu vs terraform
- OpenTofu = **MPL-2.0** Linux Foundation fork of Terraform (which relicensed to **BSL 1.1**, Aug 2023). Drop-in (same HCL/workflow). Chosen as the differentiator + license.

### Modules, variables, outputs, locals, for
- **Module** = reusable unit (`variables` in, `outputs` out). Modules **don't talk to each other** — the **root** wires one module's `output` into another's `variable` (`module.network.subnet_id`). tofu builds the dependency graph from these references (ordering is automatic).
- **locals** = computed reusable values in a root; **`for` expression** `[for x in list : expr]` transforms lists.
- **Anchor:** `dev` root wires `ecr`/`network`/`compute`; `[for svc in local.services : "vortex-${svc}"]` builds repo names.

### State & remote backend
- **State** = tofu's memory (real infra ↔ config map). Never commit (sensitive) → **S3 backend**. **Native S3 locking** (`use_lockfile=true`, since 2024) replaces the old DynamoDB lock table.
- **Bootstrap chicken-egg:** the bucket holding state can't be created by a run already using it → bootstrap with **local state**, then `tofu init -migrate-state`.
- **Partial backend:** keep sensitive/env values (bucket w/ account id) out of `backend.tf` → pass via `tofu init -backend-config=backend.hcl` (gitignored).

### Functions & gotchas (war stories)
- **`templatefile(path, vars)`** = `file()` + `${var}` interpolation; language-agnostic. Escape real shell `${VAR}` as `$${VAR}`.
- **`pathexpand()`** — tofu does **not** expand `~`; wrap paths.
- **`user_data_replace_on_change = true`** — user_data runs only at first boot; without this, changing it does **not** recreate the node, so the new script never runs.
- **`data "aws_ecr_authorization_token"`** — a *data source* reads (not creates) at apply time.

**Interview Qs**
- Why remote state + locking? → shared source of truth, prevent concurrent-apply corruption.
- Bootstrap the state bucket — chicken-egg? → local state first, then migrate.
- How do modules pass data? → via root; output→variable; graph auto-ordered.
- tofu vs terraform? → MPL vs BSL fork; drop-in.
- A user_data change didn't take effect — why? → `user_data_replace_on_change` default false.

---

## 4. Kubernetes — RBAC & the objects we used

- **ServiceAccount** = identity for **pods/processes** in-cluster (vs a human user with kubeconfig).
- **RBAC triangle:** ServiceAccount (who) + **Role** (what: verbs on resources) + **RoleBinding** (connect). Same shape as IAM. **Role/RoleBinding** = namespaced; **ClusterRole/Binding** = cluster-wide. Least privilege → namespaced.
- **imagePullSecret** = `docker-registry` Secret referenced by pods to pull from a private registry; patch the namespace `default` SA so all pods inherit it.
- **Native kinds vs CRD:** ServiceAccount/Role/ConfigMap/CronJob are built-in (`kubectl api-resources`); Gateway API (`Gateway`/`GatewayClass`) is a **CRD** — must install CRDs + controller first.
- **Anchor:** ECR-refresh CronJob runs as SA `ecr-cred-refresh` (Role: `secrets` get/create/update/patch) → writes `ecr-pull-secret`.

**Interview Qs**
- ServiceAccount vs user? → machine/pod identity vs human.
- RBAC pieces? → SA + Role + RoleBinding; namespaced vs cluster.
- How do pods pull from a private registry? → imagePullSecret (docker-registry).
- Native kind vs CRD? → built-in vs installed extension (Gateway API, operators).

---

## 5. ECR & registry auth on k3s

- **ECR** = AWS private registry; **one repo per service** (independent lifecycle/scan/IAM). **scan-on-push** = basic vuln scan; **lifecycle policy** expires untagged/old images (free-tier hygiene). Auth **token TTL = 12h**.
- **Chicken-egg:** the ECR-refresh CronJob's own image must be **public** (it can't live in the ECR it unlocks).
- **Pull on k3s (chosen 3b):** in-cluster **CronJob** refreshes `imagePullSecret` every 6h using the node role via IMDS — declarative, in-git, no host changes.
- **EKS (deferred 3a):** kubelet **ecr-credential-provider** does this natively (auto, per-pull) — the EKS-era improvement.
- **Anchor:** ADR-017; `ecr` tofu module + node role + IMDS hop 2 + `deploy/k8s/platform/ecr-auth/` CronJob.

**Interview Qs**
- How does a self-managed cluster pull from ECR? → refresh a pull-secret (CronJob) or kubelet credential provider (EKS).
- Why does EKS "just work" but k3s doesn't? → EKS bundles the kubelet ECR credential provider.
- ECR token lifetime? → 12h → refresh < 12h (we use 6h).

---

## 6. k3s vs EKS

- **EKS** = managed control plane (HA, upgrades, IRSA, native ECR/LB integration) but **~$73/mo per cluster** + nodes.
- **k3s** = lightweight single-binary k8s on one cheap EC2 → near-zero, ephemeral (`apply`/`destroy`). Teaches internals (you install the cluster + wire ECR yourself).
- **Judgment:** cost vs fidelity. k3s for the learning demo; EKS is Phase B ("on the job"). Free-tier is now **credit-based (~$200 / 6mo)** — EKS would drain it.

**Interview Qs**
- Why k3s not EKS for a demo? → cost (EKS control plane flat $73/mo) + more learning; EKS deferred.
- What does EKS give you that k3s doesn't? → managed HA control plane, IRSA, native ECR/LB, credential provider.

---

## 7. CI/CD landscape

- **Coupled-SaaS** (GitHub Actions, GitLab CI) = vendor-hosted **+** bound to the git platform. Convenient: zero infra, native repo integration, config-in-repo. Cost: platform lock-in. Won the "new projects" market.
- **Jenkins** = self-hosted, **platform-agnostic**, plugin-extensible (~1800). "Universal" = vendor-independent + integrate-anything, **not** "does more task types" (GitLab CI is general-purpose too). Strong for **on-prem/regulated/private-network/legacy** + centralized IaC control plane w/ approval gates.
- **TF-native IaC automation:** **Atlantis** (self-hosted OSS, PR-based `plan`/`apply` via comments, works with tofu), **TF Cloud/HCP** (managed SaaS, HashiCorp), **Spacelift/env0/Scalr** (managed, tofu-friendly, policy/drift).
- **Jenkins alternatives (universal/self-hosted):** TeamCity, GoCD, Buildkite, Drone/Woodpecker, Concourse; **k8s-native:** Tekton, Argo Workflows. Many are **Go** (single binary, cloud-native) — Jenkins persists on **ecosystem + inertia**, not language.

**Interview Qs**
- When Jenkins over GitHub Actions? → on-prem/air-gapped, private-network TF, centralized control + approvals, big legacy estate.
- Jenkins vs Atlantis? → general CI/CD (you build the TF pipeline) vs purpose-built TF-in-PR (plan-comment/apply/locking out of the box).
- Why GitHub Actions/GitLab CI won new projects? → coupled-SaaS: zero infra + native integration.
- Modern TF automation? → Atlantis / TF Cloud / Spacelift; `plan` on PR, gated `apply`, OIDC auth.

---

## 8. War stories (gold for interviews — real debugging)

Talk about these — they show you hit and solved real problems:
1. **k3s API cert x509** — `kubectl` failed TLS: cert valid for private IPs, not the public EIP. Fix: `--tls-san <EIP>`, **EIP-first** so the address is baked into `user_data` before the node boots (curl-metadata approach failed: IMDSv2 token + EIP attaches after boot).
2. **user_data didn't re-run** — changed the bootstrap script, cert still wrong. Cause: `user_data_replace_on_change` default **false** → node not recreated. Fix: set true + `tofu apply -replace`.
3. **SSH host key changed** — same EIP, new instance → `ssh-keygen -R <ip>` (local `known_hosts`; SSH blocks same-IP-different-key as a MITM signal).
4. **State bucket chicken-egg** — bootstrap w/ local state → `-migrate-state`.
5. **Pods can't reach IMDS** — hop limit 1 → set 2 (pod = extra hop).
6. **ECR refresher image chicken-egg** — must be public, can't live in the ECR it unlocks.
7. **EIP changes across destroy/apply** — ephemeral; read `tofu output -raw public_ip`, don't hardcode. EIP is stable *within* a session (survives instance replacement), not across destroy.

---

## How to extend this
One file per phase/topic in `docs/notes/`. Same shape: **concept → why → anchor → interview Qs**. Add a war-stories section — the debugging stories are what separate "did a tutorial" from "operated it".
