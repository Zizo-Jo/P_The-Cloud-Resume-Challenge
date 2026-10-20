output "api_endpoint" {
  # invoke_url already ends with "/" for the $default stage.
  value = "${trimsuffix(aws_apigatewayv2_stage.stage.invoke_url, "/")}/count"
}

output "health_endpoint" {
  value = "${trimsuffix(aws_apigatewayv2_stage.stage.invoke_url, "/")}/health"
}
