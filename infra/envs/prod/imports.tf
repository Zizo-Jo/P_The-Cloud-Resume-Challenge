# One-time adoption of the resources that were already running in AWS
# after the original local state was lost. Safe to delete once applied.

# --- Backend ---
import {
  to = module.backend.aws_dynamodb_table.t
  id = "visitors-dev"
}

import {
  to = module.backend.aws_iam_role.iam
  id = "iam_for_lambda_dev"
}

import {
  to = module.backend.aws_iam_role_policy.policy
  id = "iam_for_lambda_dev:policy_dev"
}

import {
  to = module.backend.aws_lambda_function.func
  id = "counter-dev"
}

import {
  to = module.backend.aws_lambda_permission.perm
  id = "counter-dev/terraform-20260201195445344500000002"
}

import {
  to = module.backend.aws_apigatewayv2_api.api
  id = "ubnjbwuf9e"
}

import {
  to = module.backend.aws_apigatewayv2_stage.stage
  id = "ubnjbwuf9e/$default"
}

import {
  to = module.backend.aws_apigatewayv2_integration.int
  id = "ubnjbwuf9e/8701v87"
}

import {
  to = module.backend.aws_apigatewayv2_route.route
  id = "ubnjbwuf9e/p1pz2sh"
}

# --- Frontend ---
import {
  to = module.frontend.aws_s3_bucket.b
  id = "zihao-resume-dev-2026-v99"
}

import {
  to = module.frontend.aws_s3_bucket_public_access_block.pub
  id = "zihao-resume-dev-2026-v99"
}

import {
  to = module.frontend.aws_s3_bucket_policy.pol
  id = "zihao-resume-dev-2026-v99"
}

import {
  to = module.frontend.aws_s3_object.html
  id = "zihao-resume-dev-2026-v99/index.html"
}

import {
  to = module.frontend.aws_cloudfront_origin_access_control.oac
  id = "E11PPTETTVPQY1"
}

import {
  to = module.frontend.aws_acm_certificate.cert
  id = "arn:aws:acm:us-east-1:030342421998:certificate/dc7b465d-005e-4a27-a763-f1d7d48f7da2"
}

import {
  to = module.frontend.aws_cloudfront_distribution.cdn
  id = "E32881U4Y5ZDYR"
}
