"""Builds ops/summary.json for the public /ops page, a few times a day.

Uses only free APIs: CloudWatch GetMetricStatistics (inside the 1M free API
requests) and AWS Budgets. The Cost Explorer API is deliberately not used: it
costs $0.01 per call, and anything that queried it on demand could be abused
to run up the bill.
"""
import datetime
import json
import logging
import os

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

NAMESPACE = "ZihaoCV"
SLO_PERCENT = 99.5
DAY = 86400

cloudwatch = boto3.client("cloudwatch")
budgets = boto3.client("budgets")
s3 = boto3.client("s3")


def uptime_percent(days, now):
    """Share of external checks that passed in the last `days` days, or None without data."""
    points = cloudwatch.get_metric_statistics(
        Namespace=NAMESPACE,
        MetricName="Up",
        StartTime=now - datetime.timedelta(days=days),
        EndTime=now,
        Period=DAY,
        Statistics=["Sum", "SampleCount"],
    )["Datapoints"]
    checks = sum(p["SampleCount"] for p in points)
    if not checks:
        return None
    return round(100 * sum(p["Sum"] for p in points) / checks, 2)


def month_cost(account_id, budget_name):
    budget = budgets.describe_budget(AccountId=account_id, BudgetName=budget_name)["Budget"]
    spend = budget.get("CalculatedSpend", {})
    actual = float(spend.get("ActualSpend", {}).get("Amount", 0))
    forecast = float(spend.get("ForecastedSpend", {}).get("Amount", actual))
    return {
        # Rounded: the public page shows cents, nothing more precise.
        "cost_month_to_date": round(actual, 2),
        "cost_forecast": round(forecast, 2),
        "budget": round(float(budget["BudgetLimit"]["Amount"]), 2),
    }


def build_summary(now):
    return {
        "generated_at": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "uptime_7d_percent": uptime_percent(7, now),
        "uptime_30d_percent": uptime_percent(30, now),
        "slo_percent": SLO_PERCENT,
        **month_cost(os.environ["ACCOUNT_ID"], os.environ["BUDGET_NAME"]),
    }


def lambda_handler(event, context):
    summary = build_summary(datetime.datetime.now(datetime.timezone.utc))
    s3.put_object(
        Bucket=os.environ["BUCKET"],
        Key="ops/summary.json",
        Body=json.dumps(summary).encode(),
        ContentType="application/json",
        CacheControl="max-age=60",
    )
    logger.info("Published %s", summary)
    return summary
