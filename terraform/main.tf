terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }
  required_version = ">= 1.2.0"
}

provider "aws" {
  region  = "us-east-1"
}

resource "aws_dynamodb_table" "terraform_test_table" {
  name           = "visitors-terraform"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

# --- 1. Pack lambda ---
# Convert to .zip, lambda needs this format
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/func.py"
  output_path = "${path.module}/lambda/func.zip"
}

# --- 2. Create a IAM Role ---
# Lambda needs the role to execute in AWS 
resource "aws_iam_role" "iam_for_lambda" {
  name = "iam_for_lambda_terraform"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

# --- 3. DynamoDB Full Access ---
resource "aws_iam_policy_attachment" "lambda_dynamodb_attach" {
  name       = "lambda_dynamodb_attach"
  roles      = [aws_iam_role.iam_for_lambda.name]
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

# --- 4. Create Lambda ---
resource "aws_lambda_function" "test_lambda" {
  filename      = data.archive_file.lambda_zip.output_path
  function_name = "updateVisitorCount_Terraform"
  role          = aws_iam_role.iam_for_lambda.arn
  handler       = "func.lambda_handler"
  runtime       = "python3.9"

  # Hash, terraform updates when lambda python code changes
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
}

# --- 5. HTTP API Gateway ---
resource "aws_apigatewayv2_api" "http_api" {
  name          = "resume_api_terraform"
  protocol_type = "HTTP"

  # Solve CORS 
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["Content-Type"]
  }
}

# --- 6. API  (Stage) ---
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}

# --- 7. Integration Lambda ---
resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.http_api.id
  integration_type = "AWS_PROXY"
  
  # To the lambda we created
  integration_uri    = aws_lambda_function.test_lambda.invoke_arn
  payload_format_version = "2.0"
}

# --- 8. Route ---
resource "aws_apigatewayv2_route" "get_count" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /count" 
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# --- 9. Give API permission to use the Lambda  ---
resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.test_lambda.function_name
  principal     = "apigateway.amazonaws.com"

  # Only this API can invoke the Lambda
  source_arn = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

# --- 10. Print API URL to debug or check ---
output "api_url" {
  description = "My API Gateway URL"
  value       = aws_apigatewayv2_stage.default.invoke_url
}