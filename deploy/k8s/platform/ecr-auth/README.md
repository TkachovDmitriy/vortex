# ecr-auth — pull images from ECR on k3s (ADR-017 §3)

A CronJob refreshes a `docker-registry` Secret (`ecr-pull-secret`) every 6h using a
short-lived ECR token minted from the **node's instance role** (via IMDS — no static
credentials). App pods reference the Secret via `imagePullSecrets`.

> On EKS this is unnecessary — the kubelet ECR credential provider handles it (ADR-017 §6).

## Prerequisites
- Node provisioned with the instance role (`AmazonEC2ContainerRegistryReadOnly`) and
  IMDS hop limit 2 — both in `infra/modules/compute` (ADR-017 §2, metadata_options).
- ECR repos exist (`tofu apply` of the `ecr` module).
- The `vortex` namespace exists.

## Deploy order
```bash
kubectl create namespace vortex   # if not already

# fill in your account id (gitignored — holds the registry host)
cp configmap.example.yaml configmap.yaml
#   ECR_REGISTRY = $(tofu -chdir=../../../../infra/environments/dev output -raw ecr_registry_url)

kubectl apply -f serviceaccount.yaml -f rbac.yaml -f configmap.yaml -f cronjob.yaml

# CronJobs don't run on apply — trigger once so the Secret exists BEFORE deploying apps
kubectl create job --from=cronjob/ecr-cred-refresh ecr-cred-refresh-init -n vortex
kubectl logs -n vortex job/ecr-cred-refresh-init          # verify success
kubectl get secret ecr-pull-secret -n vortex               # should exist
```

## Wire the Secret into app pods
Pods must reference `ecr-pull-secret` as an `imagePullSecrets`. Simplest — patch the
namespace's `default` ServiceAccount so every pod inherits it automatically:
```bash
kubectl patch serviceaccount default -n vortex \
  -p '{"imagePullSecrets":[{"name":"ecr-pull-secret"}]}'
```
(Alternatively set `imagePullSecrets` in the Helm values per service.)

## Notes
- `image` for the CronJob must be **public** — it can't live in the ECR it unlocks.
- Schedule is 6h (token TTL is 12h) — safe margin, avoids the `*/11` cron gap.
