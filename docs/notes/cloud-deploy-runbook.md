# Cloud deploy runbook + war-stories (vortex on AWS k3s)

The practical companion to `cloud-iac-aws-study.md` (theory) and `ADR-010`/`ADR-017`.
How the first cloud deploy actually went: the sequence, the issues we hit, and how to test.

---

## Deploy sequence (manual — later moves to CI/ArgoCD)

```bash
# 1. infra: network + node + ECR + IAM
cd infra/environments/dev
tofu init -reconfigure -backend-config=backend.hcl   # if state backend was reset
# terraform.tfvars: allowed_cidr = "<your-ip>/32"
tofu apply

# 2. push images to ECR (they can't be pulled if they aren't there)
REGISTRY=$(tofu output -raw ecr_registry_url)
aws ecr get-login-password --region eu-central-1 | docker login --username AWS --password-stdin $REGISTRY
for svc in gateway orders inventory notifications analytics; do
  docker tag vortex-$svc:latest $REGISTRY/vortex-$svc:latest
  docker push $REGISTRY/vortex-$svc:latest
done

# 3. kubeconfig (SSH once; IP changes each apply → read from output)
IP=$(tofu output -raw public_ip)
ssh-keygen -R $IP
ssh -i ~/.ssh/vortex-dev ubuntu@$IP 'sudo sed "s/127.0.0.1/'"$IP"'/" /etc/rancher/k3s/k3s.yaml' > vortex-dev.kubeconfig
export KUBECONFIG=$PWD/vortex-dev.kubeconfig

# 4. ECR pull auth (in-cluster, ADR-017 §3)
kubectl create namespace vortex
cd ../../../deploy/k8s/platform/ecr-auth
cp configmap.example.yaml configmap.yaml    # set ECR_REGISTRY
kubectl apply -f serviceaccount.yaml -f rbac.yaml -f configmap.yaml -f cronjob.yaml
kubectl create job --from=cronjob/ecr-cred-refresh ecr-cred-refresh-init -n vortex   # → creates ecr-pull-secret
kubectl patch serviceaccount default -n vortex -p '{"imagePullSecrets":[{"name":"ecr-pull-secret"}]}'

# 5. data layer + per-service secrets (gitignored, applied out-of-band — ADR-012/014)
cd ../../data && kubectl apply -n vortex -R -f .
kubectl apply -n vortex -f ../services/orders/secret.yaml -f ../services/inventory/secret.yaml

# 6. app via Helm, images → ECR
cd ../../.. && helm install vortex deploy/helm/vortex -n vortex --set global.imageRegistry=$REGISTRY
kubectl get pods -n vortex -w    # all should reach Running
```

---

## War-stories (real issues we hit — interview gold)

1. **`ImagePullBackOff`, image resolved to `docker.io/library/vortex-analytics:latest`.**
   Root cause: the Helm `common` chart's `_deployment.tpl` **never applied `global.imageRegistry`** — it rendered `{{ .Values.image.repository }}:{{ tag }}` with no registry prefix, so `--set global.imageRegistry=…` was silently ignored → kubelet defaulted to Docker Hub. **Fix:** prepend the registry in the template for **both** the main container **and** the `initContainers` images:
   ```
   image: "{{ if .Values.global.imageRegistry }}{{ .Values.global.imageRegistry }}/{{ end }}{{ .Values.image.repository }}:{{ tag }}"
   # initContainers: range + prepend registry to each .image (omit "image" | toYaml keeps other fields)
   ```
   Lesson: a values key documented but not wired in the template fails **silently**.

2. **Chart edit had no effect — `helm template` still showed old images.**
   Root cause: the umbrella uses **vendored `charts/*.tgz`**, not the live `common/` source. **Fix:** re-vendor bottom-up: `helm dependency update` each service chart (pulls new `common`), then the umbrella. Verify with `helm template … | grep image:` **before** upgrading.

3. **`Init:CreateContainerConfigError` on orders/inventory.**
   Root cause: the migrate initContainer `envFrom: secretRef: orders-secret` / `inventory-secret` — the per-service Secrets **didn't exist** (gitignored, provisioned out-of-band; we'd applied Postgres's secret but not these). **Fix:** `kubectl apply` the gitignored `deploy/k8s/services/{orders,inventory}/secret.yaml`. Lesson: `CreateContainerConfigError` ≈ a referenced Secret/ConfigMap is missing.

4. **`Init:ContainerStatusUnknown` (transient, NOT memory).**
   Appeared while the migrate initContainer ran; resolved itself once migrations finished — the pod went `Running`. Was **not** an OOM/eviction (node conditions clean). Lesson: a transient `ContainerStatusUnknown` during init can just be churn; confirm via node `Conditions` + Events before assuming resource pressure.

5. **Old ReplicaSet pods linger next to new ones.**
   After `helm upgrade`, old pods (pre-fix, `ImagePullBackOff`, older AGE) coexist with new ones (post-fix). Distinguish by **AGE** and pod-hash; the old ReplicaSet is garbage-collected automatically. Don't debug the old ones.

---

## How to test the deployed app (real path, not just localhost)

### A. Local smoke test (tunnel — quick, but not a real network test)
`port-forward` opens a **localhost tunnel** straight to the pod — it bypasses the node, SG, and EIP, so it proves the pod works but **not** the real path.
```bash
kubectl port-forward -n vortex svc/gateway 3000:3000 &
curl -s localhost:3000/health
```

### B. Real external test (through SG → EIP → node → Traefik → pod) ⭐
**k3s already ships Traefik** as a `LoadBalancer` on `:80/:443` with a default `IngressClass traefik`
(`kubectl get svc -n kube-system traefik` shows `80:…/443:…`; EXTERNAL-IP is the node's *private* IP —
the public path is via the EIP). So **don't** add another LoadBalancer on :80 (it collides with Traefik) —
**route through the Traefik that's already there** with an `Ingress`, then curl the node's public IP:
```bash
kubectl apply -f - <<'YAML'   # or write a file (heredoc indentation is fragile)
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: { name: gateway-test, namespace: vortex }
spec:
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend: { service: { name: gateway, port: { number: 3000 } } }
YAML

IP=$(tofu -chdir=infra/environments/dev output -raw public_ip)
curl -s http://$IP/health
# order body = { item, quantity }; seeded stock: widget=100, gizmo=5, gadget=0
curl -s -X POST http://$IP/orders -H 'content-type: application/json' -d '{"item":"widget","quantity":1}'   # → status: created
curl -s -X POST http://$IP/orders -H 'content-type: application/json' -d '{"item":"gadget","quantity":1}'   # → status: rejected (sync orders→inventory)

# async fan-out reached both consumers?
kubectl logs -n vortex deploy/notifications --tail=5
kubectl logs -n vortex deploy/analytics --tail=5
```
Exercises the whole system over the real network:
**your IP → Security Group (:80) → EIP → node → Traefik → gateway → orders → inventory → Postgres**,
plus `order.created → NATS → notifications/analytics`.

> This uses the **Ingress API** via k3s's bundled Traefik — fine for a *test*. The intended *permanent*
> front door is **Gateway API** (ADR-013: Envoy Gateway, or Traefik-as-Gateway), a deferred item — it
> needs the Gateway API CRDs + controller installed on the cloud cluster (not done in this slice).

### C. From inside the node (isolate networking)
If B fails but A works, the pod is fine and the problem is the path (SG/port/LB):
```bash
ssh -i ~/.ssh/vortex-dev ubuntu@$IP 'curl -s localhost/health'   # after the :80 LB patch
```

---

## Teardown
```bash
cd infra/environments/dev && tofu destroy   # dev only; bootstrap (state bucket) stays
```
EIP is released → next apply gets a new IP (read `tofu output -raw public_ip`, never hardcode).
