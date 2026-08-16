# Keyless CI → AWS auth via GitHub Actions OIDC (no static access keys).
# GitHub issues a short-lived JWT per workflow run; AWS trusts it and hands back
# temporary STS creds. See ADR-021.

# 1. Register GitHub's OIDC issuer as a trusted identity provider in this account.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"] # must equal the JWT `aud` claim
  # GitHub's documented thumbprints. AWS validates the JWT against its CA library
  # for this well-known issuer, but the field is still required by the provider.
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

# 2. Trust policy — who may assume the role. THIS is the security boundary:
#    only this repo, only the given branch, only aud=sts.amazonaws.com.
data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Without this StringLike, ANY GitHub repo could assume the role. Scope to
    # repo + branch. `sub` format for a branch push: repo:OWNER/REPO:ref:refs/heads/BRANCH
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:ref:refs/heads/${var.branch}"]
    }
  }
}

resource "aws_iam_role" "ci" {
  name               = "${var.name}-ci-ecr-push"
  assume_role_policy = data.aws_iam_policy_document.trust.json
  tags               = var.tags
}

# 3. Least-privilege ECR push. GetAuthorizationToken is account-level (can't be
#    scoped to a repo); the layer/put actions are scoped to the service repos only.
data "aws_iam_policy_document" "ecr_push" {
  statement {
    sid       = "EcrAuthToken"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
    ]
    resources = var.ecr_repository_arns
  }
}

resource "aws_iam_role_policy" "ecr_push" {
  name   = "ecr-push"
  role   = aws_iam_role.ci.id
  policy = data.aws_iam_policy_document.ecr_push.json
}
