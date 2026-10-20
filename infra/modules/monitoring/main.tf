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

# --- Black-box uptime check ----------------------------------------------------
# A small Lambda probes the site and the API from the outside every 5 minutes and
# publishes ZihaoCV/Up (1 or 0). CloudWatch Synthetics would do the same for
# ~$10/month, thirty times the cost of the whole site.

data "archive_file" "uptime" {
  type        = "zip"
  source_file = var.uptime_source
  output_path = "${path.module}/uptime.zip"
}

# The role is created in bootstrap/ (the pipeline cannot create IAM roles).
data "aws_iam_role" "uptime" {
  name = "uptime_lambda_${var.env}"
}

resource "aws_cloudwatch_log_group" "uptime" {
  name              = "/aws/lambda/uptime-${var.env}"
  retention_in_days = 30
}

resource "aws_lambda_function" "uptime" {
  filename         = data.archive_file.uptime.output_path
  function_name    = "uptime-${var.env}"
  role             = data.aws_iam_role.uptime.arn
  handler          = "check.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30
  source_code_hash = data.archive_file.uptime.output_base64sha256

  environment {
    variables = {
      SITE_URL   = var.site_url
      HEALTH_URL = var.health_url
    }
  }
  tracing_config {
    mode = "Active"
  }
  depends_on = [aws_cloudwatch_log_group.uptime]
}

resource "aws_cloudwatch_event_rule" "uptime" {
  name                = "uptime-${var.env}-schedule"
  description         = "Run the uptime check every 5 minutes"
  schedule_expression = "rate(5 minutes)"
}

resource "aws_cloudwatch_event_target" "uptime" {
  rule = aws_cloudwatch_event_rule.uptime.name
  arn  = aws_lambda_function.uptime.arn
}

resource "aws_lambda_permission" "uptime" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.uptime.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.uptime.arn
}

# Two failed checks in a row (10 minutes) before waking anyone: one lost packet
# is not an outage. Missing data counts as DOWN here: if the checker itself dies,
# that is exactly what we want to hear about.
resource "aws_cloudwatch_metric_alarm" "site_down" {
  alarm_name          = "zihao-cv-site-down"
  alarm_description   = "The site or the API failed the external check twice in a row. See docs/runbook.md#site-down"
  namespace           = "ZihaoCV"
  metric_name         = "Up"
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = local.notify
  ok_actions          = local.notify
}
