# infra/ — Cloud + IaC (OpenTofu)

Provisions vortex's cloud cluster. **OpenTofu only** (`tofu`, not `terraform`) and
**cloud infra only** — the app is deployed via Helm/ArgoCD, never via `kubernetes_*`
or `helm_*` resources. See **ADR-010** for the full rationale.

> Status: **skeleton / design-first.** Module `.tf` files are authored by hand
> (the owner already knows HCL — this is not a CV-gap skill). This README is the blueprint.

## What this builds

A single, **ephemeral, right-sized k3s node on AWS**, with the cheap/stable network +
state primitives separated from the paid compute so `destroy` of compute leaves the
free layer intact.

```
infra/
├── modules/
│   ├── network/         # VPC, subnet, IGW, route table, security group  (≈ free, may persist)
│   ├── compute/         # EC2 + cloud-init k3s install, EIP, key pair     (PAID, ephemeral)
│   └── state-backend/   # S3 bucket for remote tofu state                 (free, one-time bootstrap)
└── environments/
    ├── bootstrap/      # root: creates the S3 state bucket (LOCAL state, run once)
    └── dev/            # root: wires network + compute, owns backend.tf → the bucket
```

## Cost seam (the point of the split — ADR-010 §2/§3)

| Layer | Resources | Cost | Lifecycle |
|---|---|---|---|
| `network` | VPC, subnet, IGW, RT, SG | free | persist |
| `state-backend` | S3 (versioned, SSE, locked) | ~free (state is KB) | bootstrap once |
| `compute` | EC2 `t3.small`/`t3.medium`, EIP | **paid** (~$0.04/hr) | `apply` for demo → `destroy` after |

`t3.medium` (4 GB) for full-stack incl. metrics; `t3.small` (2 GB) for app + data only.

## Module contracts

### `modules/network`
- **Purpose:** the VPC vortex's node lives in; firewall scoped to the owner's IP.
- **Key resources:** `aws_vpc`, `aws_subnet` (public), `aws_internet_gateway`,
  `aws_route_table` (+ assoc), `aws_security_group` (ingress: `6443` kube-API,
  `80`/`443` ingress, `22` SSH — all from `allowed_cidr`; egress all).
- **Inputs:** `vpc_cidr`, `subnet_cidr`, `allowed_cidr`, `tags`.
- **Outputs:** `vpc_id`, `subnet_id`, `security_group_id`.

### `modules/compute`
- **Purpose:** the k3s node itself; k3s installed via `user_data`/cloud-init.
- **Key resources:** `aws_instance` (Ubuntu LTS AMI via data source),
  `aws_eip`, `aws_key_pair`; `user_data` runs the k3s installer and writes kubeconfig.
- **Inputs:** `instance_type` (`t3.small`|`t3.medium`), `subnet_id`,
  `security_group_id`, `key_name`/`public_key`, `tags`.
- **Outputs:** `public_ip`, `instance_id`, `kubeconfig_hint` (how to fetch it).

### `modules/state-backend`
- **Purpose:** the S3 bucket holding remote tofu state. **Bootstrap once** with local
  state, then `tofu init -migrate-state` (ADR-010 §5). Not part of the per-demo cycle.
- **Key resources:** `aws_s3_bucket` + `versioning` + `server_side_encryption` +
  `public_access_block`.
- **Inputs:** `bucket_name`, `tags`.
- **Outputs:** `bucket_name`, `bucket_arn`.

## environments/dev (root module)

Thin wiring layer. Expected files (authored by hand):
- `backend.tf` — `s3` backend, `use_lockfile = true` (native locking, no DynamoDB), SSE.
- `providers.tf` — `aws` provider pinned; region `eu-central-1`; auth via local profile/env.
- `main.tf` — `module "network"` → `module "compute"`; passes the network outputs in.
- `variables.tf` / `terraform.tfvars.example` — `allowed_cidr`, `instance_type`, etc.
  (commit the `.example`, never a real `.tfvars` with your IP/keys).
- `outputs.tf` — surfaces `public_ip` and the kubeconfig fetch hint.

## Workflow (once the .tf exists)

```bash
# one-time: create the state bucket (local state), then point dev at it
cd infra/environments/bootstrap
tofu init && tofu apply                    # creates S3 state bucket
# copy the output bucket_name into environments/dev/backend.tf

# per demo
cd ../dev
tofu init                                  # picks up the S3 backend
tofu apply                                 # bring up network + ephemeral k3s node
# ... fetch kubeconfig (see outputs), then deploy the app SEPARATELY via Helm (ADR-014) ...
helm install vortex deploy/helm/vortex -n vortex --create-namespace

# teardown: destroy the PAID compute only; keep free network + cents-level ECR/state
# (ADR-018 — images stay in ECR → no re-push next apply)
tofu destroy -target=module.compute
```

## Lifecycle: ephemeral compute vs persistent infra (ADR-018)

Not everything shares a lifecycle/cost: **compute** (EC2+EIP) is the only real cost and
is recreated each session; **network** (free), **ECR+images** (~cents), and the **state
bucket** persist. So teardown destroys `module.compute` only (`-target`) — a full
`tofu destroy` would fail on non-empty ECR repos and needlessly drop the free network.
The documented evolution (ADR-018 §4) splits these into a **persistent** root
(network+ECR) and an **ephemeral** root (compute) so teardown is a clean `tofu destroy`
with no `-target`.

## Guardrails (ADR-010 §8)

- **Secrets/state never committed:** `*.tfstate*`, `*.tfvars` (real), `.terraform/`,
  `*.pem`, kubeconfig are gitignored.
- **Auth** via local AWS profile / env vars — no hardcoded access keys in HCL.
- Set an **AWS billing alarm**; the free-tier credit plan is ~$200 / ~6 months.
