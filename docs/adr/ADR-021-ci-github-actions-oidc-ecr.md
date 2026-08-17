# ADR-021: CI on GitHub Actions — keyless ECR push via OIDC

- **Status:** Accepted (implemented — to verify on next `tofu apply` + a push to develop)
- **Date:** 2026-08-13
- **Deciders:** project owner

## Context

CD is done (ArgoCD, ADR-019/020); CI was still just a `.gitkeep`. CI must typecheck,
build each service image, scan it, and push to ECR (ADR-017) so the GitOps loop has fresh
images to deploy. Pushing to ECR needs AWS credentials in CI — and the default path
(static `AWS_ACCESS_KEY_ID/SECRET` in GitHub Secrets) means **long-lived credentials**
that can leak (logs, forks) and must be rotated. The project's whole trajectory is
"no long-lived credentials" (instance roles in ADR-017, the ESO direction in ADR-020).

## Decision

**GitHub Actions CI with keyless AWS auth via OIDC. A checks stage (typecheck + build +
Trivy) runs on every PR; images push to ECR only on `develop`, after the scan passes,
using a short-lived token from an IAM role scoped to this repo + branch.**

1. **OIDC, not static keys.** An `aws_iam_openid_connect_provider` trusts GitHub's issuer;
   an IAM role (`vortex-dev-ci-ecr-push`, module `infra/modules/ci-oidc`) is assumable only
   via `AssumeRoleWithWebIdentity`. Each run gets a ~1h STS token — nothing stored.

2. **Trust scoped by `sub` claim.** The trust policy requires
   `sub = repo:TkachovDmitriy/vortex:ref:refs/heads/develop` and `aud = sts.amazonaws.com`.
   Without the `sub` condition, *any* GitHub repo could assume the role. The workflow needs
   `permissions: id-token: write` to obtain the JWT (the #1 gotcha if omitted).

3. **Least-privilege push.** The role's policy allows `ecr:GetAuthorizationToken` (account
   -level, unscopable) plus the layer/`PutImage` actions scoped to the service repo ARNs.

4. **Scan gates push; immutable tags.** Trivy fails the job on fixable HIGH/CRITICAL CVEs
   before any push. Images are tagged with the **git SHA** (never `latest`) so a tag maps to
   exactly one commit — required for a clean GitOps image-bump later.

5. **tofu owns only the IAM/OIDC infra**, per CLAUDE.md (tofu = cloud infra only). The role
   lives beside ECR in the persistent layer; the workflow references its ARN
   (`tofu output ci_role_arn`).

## Consequences

- **Good:** zero long-lived CI credentials; leak blast-radius is one ~1h token scoped to one
  repo+branch+action; supply-chain gate (Trivy) before images ship; immutable tags ready for
  GitOps image-bump.
- **Cost:** an account-level OIDC provider now exists (one-time); the CI role ARN is
  hardcoded in the workflow (an identifier, not a secret — consistent with ADR-019).
- **Follow-ups:** image-bump step (write the SHA tag into Helm values → ArgoCD deploys it) to
  close CI→CD fully; add `bun test` + a lint step once they exist; `buf` proto checks once
  `proto/` lands; extend trust to PRs/environments if promotion flows are added.
