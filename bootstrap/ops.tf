# Phase 4: the public /ops status page.
#
# The CI roles' inline policies are close to IAM's 10,240-character limit per
# role, so these additions are customer-managed policies attached to the roles
# (free, 6,144 characters each, up to 10 per role).

locals {
  cf_function  = "zihao-cv-dir-index"
  ops_function = "ops-publisher-dev"
  ops_role     = "ops_publisher_dev"
  ops_rule     = "ops-publisher-dev-schedule"
  budget_name  = "My Zero-Spend Budget"
}

# --- Read access to the Phase 4 resources (plan, drift and apply roles) ------

data "aws_iam_policy_document" "ops_read" {
  statement {
    sid       = "ReadDirIndexFunction"
    actions   = ["cloudfront:DescribeFunction", "cloudfront:GetFunction"]
    resources = ["arn:aws:cloudfront::${local.account_id}:function/${local.cf_function}"]
  }

  statement {
    sid       = "ReadOpsPublisher"
    actions   = ["lambda:Get*", "lambda:List*"]
    resources = ["arn:aws:lambda:us-east-1:${local.account_id}:function:${local.ops_function}"]
  }

  statement {
    sid       = "ReadOpsPublisherRole"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["arn:aws:iam::${local.account_id}:role/${local.ops_role}"]
  }

  statement {
    sid       = "ReadOpsPublisherLogGroup"
    actions   = ["logs:ListTagsForResource", "logs:ListTagsLogGroup"]
    resources = ["arn:aws:logs:us-east-1:${local.account_id}:log-group:/aws/lambda/${local.ops_function}"]
  }

  statement {
    sid       = "ReadOpsSchedule"
    actions   = ["events:DescribeRule", "events:ListTagsForResource", "events:ListTargetsByRule"]
    resources = ["arn:aws:events:us-east-1:${local.account_id}:rule/${local.ops_rule}"]
  }
}

resource "aws_iam_policy" "ops_read" {
  name   = "github-ops-read"
  policy = data.aws_iam_policy_document.ops_read.json
}

resource "aws_iam_role_policy_attachment" "plan_ops_read" {
  role       = aws_iam_role.github_plan.name
  policy_arn = aws_iam_policy.ops_read.arn
}

# --- Write access for the deploy (apply) role ---------------------------------

data "aws_iam_policy_document" "ops_write" {
  source_policy_documents = [data.aws_iam_policy_document.ops_read.json]

  # CloudFront Function that serves /ops/ as /ops/index.html.
  statement {
    sid = "WriteDirIndexFunction"
    actions = [
      "cloudfront:CreateFunction",
      "cloudfront:UpdateFunction",
      "cloudfront:PublishFunction",
      "cloudfront:DeleteFunction",
    ]
    resources = ["arn:aws:cloudfront::${local.account_id}:function/${local.cf_function}"]
  }

  statement {
    sid = "WriteOpsPublisher"
    actions = [
      "lambda:CreateFunction",
      "lambda:DeleteFunction",
      "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration",
      "lambda:AddPermission",
      "lambda:RemovePermission",
      "lambda:TagResource",
      "lambda:UntagResource",
    ]
    resources = ["arn:aws:lambda:us-east-1:${local.account_id}:function:${local.ops_function}"]
  }

  statement {
    sid = "WriteOpsPublisherLogGroup"
    actions = [
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy",
      "logs:DeleteRetentionPolicy",
      "logs:TagResource",
      "logs:UntagResource",
    ]
    resources = ["arn:aws:logs:us-east-1:${local.account_id}:log-group:/aws/lambda/${local.ops_function}"]
  }

  statement {
    sid = "WriteOpsSchedule"
    actions = [
      "events:PutRule",
      "events:DeleteRule",
      "events:PutTargets",
      "events:RemoveTargets",
      "events:TagResource",
      "events:UntagResource",
    ]
    resources = ["arn:aws:events:us-east-1:${local.account_id}:rule/${local.ops_rule}"]
  }

  statement {
    sid       = "PassOpsPublisherRole"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.account_id}:role/${local.ops_role}"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "ops_write" {
  name   = "github-ops-write"
  policy = data.aws_iam_policy_document.ops_write.json
}

resource "aws_iam_role_policy_attachment" "apply_ops_write" {
  role       = aws_iam_role.github_apply.name
  policy_arn = aws_iam_policy.ops_write.arn
}

# --- Drift role: read-only plus one status file -------------------------------
# The nightly drift check writes ops/drift.json for the status page. Giving
# that write to the plan role would let every pull request write it too, so
# drift gets its own role: everything the plan role can read, plus exactly
# that one object.

data "aws_iam_policy_document" "drift_trust" {
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

    # Only jobs in the "drift" GitHub Environment (restricted to main).
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.github_sub_prefix}:environment:drift"]
    }
  }
}

resource "aws_iam_role" "github_drift" {
  name                 = "github-actions-drift"
  description          = "Read-only nightly drift check; may write ops/drift.json"
  assume_role_policy   = data.aws_iam_policy_document.drift_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "drift_permissions" {
  source_policy_documents = [data.aws_iam_policy_document.plan_permissions.json]

  statement {
    sid       = "WriteDriftStatus"
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${local.website_bucket}/ops/drift.json"]
  }
}

resource "aws_iam_role_policy" "github_drift" {
  name   = "drift-read-plus-status"
  role   = aws_iam_role.github_drift.id
  policy = data.aws_iam_policy_document.drift_permissions.json
}

resource "aws_iam_role_policy_attachment" "drift_ops_read" {
  role       = aws_iam_role.github_drift.name
  policy_arn = aws_iam_policy.ops_read.arn
}

# --- Role of the daily ops-publisher Lambda -----------------------------------
# Reads the uptime metric and the budget's month-to-date spend (both free APIs;
# the Cost Explorer API is deliberately not used: $0.01 per call) and writes
# one file, ops/summary.json.

resource "aws_iam_role" "ops_publisher" {
  name = local.ops_role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "ops_publisher" {
  name = "ops-publisher"
  role = aws_iam_role.ops_publisher.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:us-east-1:${local.account_id}:log-group:/aws/lambda/${local.ops_function}:*"
      },
      {
        # Neither action supports resource-level permissions.
        Effect   = "Allow"
        Action   = ["cloudwatch:GetMetricStatistics", "xray:PutTraceSegments", "xray:PutTelemetryRecords"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["budgets:ViewBudget"]
        Resource = "arn:aws:budgets::${local.account_id}:budget/${local.budget_name}"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "arn:aws:s3:::${local.website_bucket}/ops/summary.json"
      },
    ]
  })
}

output "github_drift_role_arn" {
  value = aws_iam_role.github_drift.arn
}
