resource "aws_dynamodb_table" "t" {
  name         = "visitors-${var.env}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  # Restore the table to any second in the last 35 days.
  point_in_time_recovery {
    enabled = true
  }

  lifecycle {
    prevent_destroy = true
  }
  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_iam_role" "iam" {
  name = "iam_for_lambda_${var.env}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Created by Terraform (instead of by Lambda on first run) so we control the
# retention. Without a retention setting, logs are kept, and billed, forever.
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/counter-${var.env}"
  retention_in_days = 30
}

# One log line per API request (route, status, latency). Visitor IPs are left
# out on purpose: they are personal data and nothing here needs them.
# The /aws/vendedlogs/ prefix is pre-authorised for log delivery, so no
# account-wide logs resource policy has to be written.
resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/vendedlogs/apigateway/api-${var.env}"
  retention_in_days = 30
}

resource "aws_iam_role_policy" "policy" {
  name = "policy_${var.env}"
  role = aws_iam_role.iam.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      # The function only touches the item with id "count": update_item for a
      # visit, get_item for /health.
      Effect   = "Allow",
      Action   = ["dynamodb:UpdateItem", "dynamodb:GetItem"],
      Resource = aws_dynamodb_table.t.arn,
      Condition = {
        "ForAllValues:StringEquals" = { "dynamodb:LeadingKeys" = ["count"] }
      }
      },
      {
        # The log group already exists, so the function only writes into it.
        Effect   = "Allow",
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"],
        Resource = "${aws_cloudwatch_log_group.lambda.arn}:*"
      },
      {
        # X-Ray does not support resource-level permissions.
        Effect   = "Allow",
        Action   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"],
        Resource = "*"
    }]
  })
}

resource "aws_lambda_function" "func" {
  # Built and attested in CI before Terraform runs (scripts/build_lambdas.py).
  filename         = var.lambda_zip
  function_name    = "counter-${var.env}"
  role             = aws_iam_role.iam.arn
  handler          = "func.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = filebase64sha256(var.lambda_zip)
  environment {
    variables = { TABLE_NAME = aws_dynamodb_table.t.name }
  }
  tracing_config {
    mode = "Active"
  }
  depends_on = [aws_cloudwatch_log_group.lambda]
}

resource "aws_apigatewayv2_api" "api" {
  name          = "api-${var.env}"
  protocol_type = "HTTP"
  cors_configuration {
    # Only the site itself may call the API from a browser.
    allow_origins = ["https://zihao-cv.site", "https://www.zihao-cv.site"]
    allow_methods = ["GET", "OPTIONS"]
  }
}

resource "aws_apigatewayv2_stage" "stage" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api.arn
    format = jsonencode({
      requestId          = "$context.requestId"
      requestTime        = "$context.requestTime"
      routeKey           = "$context.routeKey"
      status             = "$context.status"
      responseLatency    = "$context.responseLatency"
      integrationStatus  = "$context.integrationStatus"
      integrationLatency = "$context.integrationLatency"
    })
  }

  # Caps abuse and cost. A Lambda reserved-concurrency cap is not possible
  # here: the account limit is 10 and AWS requires 10 to stay unreserved.
  default_route_settings {
    throttling_rate_limit  = 10
    throttling_burst_limit = 20
  }
}

resource "aws_apigatewayv2_integration" "int" {
  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.func.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "route" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "GET /count"
  target    = "integrations/${aws_apigatewayv2_integration.int.id}"
}

# Read-only health check: used by the smoke test so deploys do not add visits.
resource "aws_apigatewayv2_route" "health" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "GET /health"
  target    = "integrations/${aws_apigatewayv2_integration.int.id}"
}

resource "aws_lambda_permission" "perm" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.func.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}