# GitHub Actions -> AWS without stored keys (OIDC).
#
# GitHub signs a short-lived token for every workflow run. AWS verifies the
# signature, then checks the token's claims against each role's trust policy.
# Lives in bootstrap/ (applied by hand) so CI can never edit its own permissions.

locals {
  # Immutable subject prefix: owner and repo are pinned by numeric ID, so a
  # deleted-and-recreated repo with the same name cannot assume these roles.
  # Source: GitHub repo Settings -> Actions -> OIDC.
  github_sub_prefix = "repo:Zizo-Jo@137719619/P_The-Cloud-Resume-Challenge@1123254278"
}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

# --- Plan role: used by pull requests, read-only ---------------------------

data "aws_iam_policy_document" "plan_trust" {
  statement {
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

    # Only workflow runs triggered by a pull request in this repo.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.github_sub_prefix}:pull_request"]
    }
  }
}

resource "aws_iam_role" "github_plan" {
  name                 = "github-actions-plan"
  description          = "Read-only: terraform plan on pull requests"
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  max_session_duration = 3600
}

# --- Apply role: used only after merge, through the "prod" environment -----

data "aws_iam_policy_document" "apply_trust" {
  statement {
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

    # Only jobs that run in the GitHub Environment "prod" (which is restricted
    # to the main branch in the repo settings).
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.github_sub_prefix}:environment:prod"]
    }
  }
}

resource "aws_iam_role" "github_apply" {
  name                 = "github-actions-apply"
  description          = "Write: terraform apply after merge to main"
  assume_role_policy   = data.aws_iam_policy_document.apply_trust.json
  max_session_duration = 3600
}

output "github_plan_role_arn" {
  value = aws_iam_role.github_plan.arn
}

output "github_apply_role_arn" {
  value = aws_iam_role.github_apply.arn
}
