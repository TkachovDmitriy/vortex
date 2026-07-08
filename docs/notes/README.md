# Study notes — theory through practice

Interview-revision notes distilled from actually building vortex. **Not** generic theory —
each concept is anchored to *what we built and what broke*. Re-read before interviews.

Format per topic: **concept → why → anchor (what we did) → issues/war-stories → interview Qs**.

## Notes by phase
| Note | Phase | Covers |
|---|---|---|
| [kubernetes-study.md](kubernetes-study.md) | 2 (headline) | workloads, StatefulSet, Services, Gateway API, Helm, NATS |
| [observability-study.md](observability-study.md) | 3 | Prometheus/metrics, Loki/logs, Grafana, Alloy, pull vs push |
| [cloud-iac-aws-study.md](cloud-iac-aws-study.md) | Cloud/IaC | AWS networking, IAM/IMDS, OpenTofu, ECR, k3s vs EKS, CI/CD |
| [cloud-deploy-runbook.md](cloud-deploy-runbook.md) | Cloud/IaC | deploy sequence, deploy war-stories, how to test the real path |

To add later: Phase 1 (Docker multi-stage), Phase 4 (GitOps/ArgoCD + Sealed Secrets), tracing (OTel/Tempo).

## Why the war-stories matter most
The **issues we resolved** (not the happy path) are what separate "did a tutorial" from
"operated it". In interviews, lead with: *"I hit X, root cause was Y, I fixed it with Z."*
Every note has a war-stories section — those are your strongest material.

## Source of truth
These notes summarise; the authoritative records are the **ADRs** (`docs/adr/`) — each
decision, why, and alternatives considered. Notes point back to the relevant ADR.
