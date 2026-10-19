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

# --- Plan role permissions: read-only ---------------------------------------
# Terraform plan "refreshes" every resource (reads its current settings), so the
# role needs read access to exactly the things infra/envs/prod manages.
# Names are hardcoded because bootstrap has its own state and cannot reference
# resources from the prod state.

locals {
  account_id     = data.aws_caller_identity.current.account_id
  website_bucket = "zihao-resume-dev-2026-v99"
  table_name     = "visitors-dev"
  function_name  = "counter-dev"
  lambda_role    = "iam_for_lambda_dev"
}

data "aws_iam_policy_document" "plan_permissions" {
  # Read the prod state file. The PR workflow runs plan with -lock=false, so
  # no write access to the state bucket is needed.
  statement {
    sid       = "ReadProdState"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.state.arn}/prod/terraform.tfstate"]
  }

  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    sid     = "ReadWebsiteBucket"
    actions = ["s3:Get*", "s3:List*"]
    resources = [
      "arn:aws:s3:::${local.website_bucket}",
      "arn:aws:s3:::${local.website_bucket}/*",
    ]
  }

  statement {
    sid       = "ReadCloudFront"
    actions   = ["cloudfront:Get*", "cloudfront:List*"]
    resources = ["*"] # distribution/OAC IDs are generated, so cannot be named here
  }

  statement {
    sid       = "ReadCertificate"
    actions   = ["acm:Describe*", "acm:Get*", "acm:List*"]
    resources = ["arn:aws:acm:us-east-1:${local.account_id}:certificate/*"]
  }

  statement {
    sid       = "ReadLambda"
    actions   = ["lambda:Get*", "lambda:List*"]
    resources = ["arn:aws:lambda:us-east-1:${local.account_id}:function:${local.function_name}"]
  }

  statement {
    sid       = "ReadApiGateway"
    actions   = ["apigateway:GET"]
    resources = ["arn:aws:apigateway:us-east-1::/*"]
  }

  statement {
    sid       = "ReadDynamoDB"
    actions   = ["dynamodb:Describe*", "dynamodb:List*"]
    resources = ["arn:aws:dynamodb:us-east-1:${local.account_id}:table/${local.table_name}"]
  }

  statement {
    sid       = "ReadLambdaRole"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["arn:aws:iam::${local.account_id}:role/${local.lambda_role}"]
  }
}

resource "aws_iam_role_policy" "github_plan" {
  name   = "plan-read-only"
  role   = aws_iam_role.github_plan.id
  policy = data.aws_iam_policy_document.plan_permissions.json
}

# --- Apply role permissions: read + write, scoped to this project ------------
# Starts from everything the plan role can read (a refresh happens before every
# apply), then adds write access to the same resources and nothing else.
# Deliberately absent: iam:AttachRolePolicy, iam:CreateRole and any IAM action
# on other roles, so a deploy cannot hand itself extra permissions.

locals {
  # Generated by AWS, so they cannot be derived from names. If a resource is
  # ever recreated, update the ID here too.
  cloudfront_distribution_id = "E32881U4Y5ZDYR"
  cloudfront_oac_id          = "E11PPTETTVPQY1"
  api_id                     = "ubnjbwuf9e"
}

data "aws_iam_policy_document" "apply_permissions" {
  source_policy_documents = [data.aws_iam_policy_document.plan_permissions.json]

  statement {
    sid     = "WriteProdState"
    actions = ["s3:PutObject", "s3:DeleteObject"]
    resources = [
      "${aws_s3_bucket.state.arn}/prod/terraform.tfstate",
      "${aws_s3_bucket.state.arn}/prod/terraform.tfstate.tflock", # use_lockfile
    ]
  }

  statement {
    sid       = "ReadLockFile"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.state.arn}/prod/terraform.tfstate.tflock"]
  }

  statement {
    sid     = "WriteWebsiteBucket"
    actions = ["s3:*"]
    resources = [
      "arn:aws:s3:::${local.website_bucket}",
      "arn:aws:s3:::${local.website_bucket}/*",
    ]
  }

  statement {
    sid = "WriteCloudFront"
    actions = [
      "cloudfront:UpdateDistribution",
      "cloudfront:CreateInvalidation",
      "cloudfront:UpdateOriginAccessControl",
      "cloudfront:TagResource",
      "cloudfront:UntagResource",
    ]
    resources = [
      "arn:aws:cloudfront::${local.account_id}:distribution/${local.cloudfront_distribution_id}",
      "arn:aws:cloudfront::${local.account_id}:origin-access-control/${local.cloudfront_oac_id}",
    ]
  }

  statement {
    sid = "WriteCertificate"
    actions = [
      "acm:UpdateCertificateOptions",
      "acm:AddTagsToCertificate",
      "acm:RemoveTagsFromCertificate",
    ]
    resources = ["arn:aws:acm:us-east-1:${local.account_id}:certificate/*"]
  }

  statement {
    sid = "WriteLambda"
    actions = [
      "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration",
      "lambda:AddPermission",
      "lambda:RemovePermission",
      "lambda:TagResource",
      "lambda:UntagResource",
    ]
    resources = ["arn:aws:lambda:us-east-1:${local.account_id}:function:${local.function_name}"]
  }

  statement {
    sid     = "WriteApiGateway"
    actions = ["apigateway:PUT", "apigateway:POST", "apigateway:PATCH", "apigateway:DELETE"]
    resources = [
      "arn:aws:apigateway:us-east-1::/apis/${local.api_id}",
      "arn:aws:apigateway:us-east-1::/apis/${local.api_id}/*",
      "arn:aws:apigateway:us-east-1::/tags/*",
    ]
  }

  statement {
    sid = "WriteDynamoDB"
    actions = [
      "dynamodb:UpdateTable",
      "dynamodb:UpdateContinuousBackups",
      "dynamodb:UpdateTimeToLive",
      "dynamodb:TagResource",
      "dynamodb:UntagResource",
    ]
    resources = ["arn:aws:dynamodb:us-east-1:${local.account_id}:table/${local.table_name}"]
  }

  statement {
    sid = "WriteLambdaRole"
    actions = [
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
    ]
    resources = ["arn:aws:iam::${local.account_id}:role/${local.lambda_role}"]
  }

  statement {
    sid       = "PassLambdaRoleToLambda"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.account_id}:role/${local.lambda_role}"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "github_apply" {
  name   = "apply-scoped-write"
  role   = aws_iam_role.github_apply.id
  policy = data.aws_iam_policy_document.apply_permissions.json
}

output "github_plan_role_arn" {
  value = aws_iam_role.github_plan.arn
}

output "github_apply_role_arn" {
  value = aws_iam_role.github_apply.arn
}
