# Symptom-based alarms: what users would feel (errors, throttling, slowness),
# not internal causes. Every alarm notifies on ALARM and on recovery.

resource "aws_sns_topic" "alerts" {
  name = "zihao-cv-alerts"
}

# The subscription stays "pending" until the link in the confirmation email is
# clicked; Terraform cannot do that step.
resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

locals {
  notify = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "zihao-cv-lambda-errors"
  alarm_description   = "The counter Lambda threw an error. See docs/runbook.md#lambda-errors"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = var.lambda_function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  # No traffic means no data, which is not an outage; the uptime check covers that.
  treat_missing_data = "notBreaching"
  alarm_actions      = local.notify
  ok_actions         = local.notify
}

resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  alarm_name          = "zihao-cv-lambda-throttles"
  alarm_description   = "Lambda rejected a call: the account limit is only 10 concurrent runs. See docs/runbook.md#lambda-throttles"
  namespace           = "AWS/Lambda"
  metric_name         = "Throttles"
  dimensions          = { FunctionName = var.lambda_function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.notify
  ok_actions          = local.notify
}

resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name          = "zihao-cv-api-5xx"
  alarm_description   = "Visitors got a server error from the API. See docs/runbook.md#api-5xx"
  namespace           = "AWS/ApiGateway"
  metric_name         = "5xx"
  dimensions          = { ApiId = var.api_id, Stage = "$default" }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.notify
  ok_actions          = local.notify
}

# p99, not the average: an average of 100 ms can hide 1% of visitors waiting seconds.
resource "aws_cloudwatch_metric_alarm" "api_latency" {
  alarm_name          = "zihao-cv-api-latency-p99"
  alarm_description   = "1 in 100 requests takes over 1 second, three periods in a row. See docs/runbook.md#api-latency"
  namespace           = "AWS/ApiGateway"
  metric_name         = "Latency"
  dimensions          = { ApiId = var.api_id, Stage = "$default" }
  extended_statistic  = "p99"
  period              = 300
  evaluation_periods  = 3
  threshold           = 1000
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.notify
  ok_actions          = local.notify
}
