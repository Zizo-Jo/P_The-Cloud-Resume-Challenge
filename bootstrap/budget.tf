# Cost guardrails as code. Lives in bootstrap/ because budgets are account-level.
#
# - A budget catches "we spent too much this month".
# - Anomaly detection catches "this service suddenly costs far more than usual",
#   even while the monthly total is still small.

variable "alert_email" {
  type        = string
  sensitive   = true
  description = "Where cost alerts are sent. Pass with TF_VAR_alert_email; never commit it (the repo is public)."
}

# --- Monthly budget: already existed, brought under Terraform ----------------

import {
  to = aws_budgets_budget.monthly
  id = "${data.aws_caller_identity.current.account_id}:My Zero-Spend Budget"
}

resource "aws_budgets_budget" "monthly" {
  name         = "My Zero-Spend Budget"
  budget_type  = "COST"
  limit_amount = "1.0"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Kept exactly as created, so importing changes nothing.
  time_period_start = "2025-07-01_00:00"
  time_period_end   = "2087-06-15_00:00"

  # Any real spend at all (the site should cost cents).
  notification {
    notification_type          = "ACTUAL"
    comparison_operator        = "GREATER_THAN"
    threshold                  = 0.01
    threshold_type             = "ABSOLUTE_VALUE"
    subscriber_email_addresses = [var.alert_email]
  }

  # 80% of the budget is spent.
  notification {
    notification_type          = "ACTUAL"
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    subscriber_email_addresses = [var.alert_email]
  }

  # AWS predicts we will pass the budget: a warning days before it happens.
  notification {
    notification_type          = "FORECASTED"
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    subscriber_email_addresses = [var.alert_email]
  }
}

# --- Cost Anomaly Detection ---------------------------------------------------

import {
  to = aws_ce_anomaly_monitor.services
  id = "arn:aws:ce::${data.aws_caller_identity.current.account_id}:anomalymonitor/6ef62060-38cd-414c-983d-9fc4b1b3e724"
}

# The monitor AWS created by default: watches every service separately.
resource "aws_ce_anomaly_monitor" "services" {
  name              = "Default-Services-Monitor"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

# The default subscription only alerts for anomalies of $100 AND 40%, which can
# never happen on a site that costs cents. This one alerts from $1.
resource "aws_ce_anomaly_subscription" "small_account" {
  name             = "zihao-cv-anomalies"
  frequency        = "DAILY"
  monitor_arn_list = [aws_ce_anomaly_monitor.services.arn]

  subscriber {
    type    = "EMAIL"
    address = var.alert_email
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = ["1"]
    }
  }
}
