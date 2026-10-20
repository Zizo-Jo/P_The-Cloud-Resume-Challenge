output "api_endpoint" {
  # invoke_url already ends with "/" for the $default stage.
  value = "${trimsuffix(aws_apigatewayv2_stage.stage.invoke_url, "/")}/count"
}

output "health_endpoint" {
  value = "${trimsuffix(aws_apigatewayv2_stage.stage.invoke_url, "/")}/health"
}

output "function_name" {
  value = aws_lambda_function.func.function_name
}

output "api_id" {
  value = aws_apigatewayv2_api.api.id
}
