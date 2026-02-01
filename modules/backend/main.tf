resource "aws_dynamodb_table" "t" {
  name         = "visitors-${var.env}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"
  attribute {
    name = "id"
    type = "S"
  }
}

data "archive_file" "zip" {
  type        = "zip"
  source_file = var.lambda_source
  output_path = "${path.module}/func.zip"
}

resource "aws_iam_role" "iam" {
  name = "iam_for_lambda_${var.env}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "policy" {
  name = "policy_${var.env}"
  role = aws_iam_role.iam.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = ["dynamodb:UpdateItem", "dynamodb:GetItem", "dynamodb:PutItem"],
      Resource = aws_dynamodb_table.t.arn
    }]
  })
}

resource "aws_lambda_function" "func" {
  filename         = data.archive_file.zip.output_path
  function_name    = "counter-${var.env}"
  role             = aws_iam_role.iam.arn
  handler          = "func.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.zip.output_base64sha256
  environment {
    variables = { TABLE_NAME = aws_dynamodb_table.t.name }
  }
}

resource "aws_apigatewayv2_api" "api" {
  name          = "api-${var.env}"
  protocol_type = "HTTP"
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
  }
}

resource "aws_apigatewayv2_stage" "stage" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true
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

resource "aws_lambda_permission" "perm" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.func.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}