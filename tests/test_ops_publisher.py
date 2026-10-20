"""Unit tests for the ops-publisher Lambda, against fake CloudWatch, Budgets and S3 (moto)."""

import datetime
import importlib.util
import json
from pathlib import Path

import boto3
import pytest
from moto import mock_aws

PUBLISHER_PATH = Path(__file__).resolve().parents[1] / "src" / "ops" / "publisher.py"
ACCOUNT = "123456789012"
BUDGET = "test-budget"
BUCKET = "test-site"
NOW = datetime.datetime(2026, 10, 20, 12, 0, tzinfo=datetime.timezone.utc)


def load_publisher():
    spec = importlib.util.spec_from_file_location("publisher", PUBLISHER_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture
def aws(monkeypatch):
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "test")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "test")
    monkeypatch.setenv("AWS_DEFAULT_REGION", "us-east-1")
    monkeypatch.setenv("ACCOUNT_ID", ACCOUNT)
    monkeypatch.setenv("BUDGET_NAME", BUDGET)
    monkeypatch.setenv("BUCKET", BUCKET)
    with mock_aws():
        boto3.client("s3").create_bucket(Bucket=BUCKET)
        boto3.client("budgets").create_budget(
            AccountId=ACCOUNT,
            Budget={
                "BudgetName": BUDGET,
                "BudgetLimit": {"Amount": "1.0", "Unit": "USD"},
                "TimeUnit": "MONTHLY",
                "BudgetType": "COST",
            },
        )
        yield


def put_checks(values, hours_ago):
    boto3.client("cloudwatch").put_metric_data(
        Namespace="ZihaoCV",
        MetricData=[
            {"MetricName": "Up", "Value": v, "Timestamp": NOW - datetime.timedelta(hours=hours_ago)}
            for v in values
        ],
    )


def test_uptime_is_share_of_passed_checks(aws):
    put_checks([1, 1, 1, 0], hours_ago=2)

    assert load_publisher().uptime_percent(7, NOW) == 75.0


def test_old_checks_count_for_30_days_but_not_7(aws):
    put_checks([1, 1], hours_ago=2)
    put_checks([0, 0], hours_ago=24 * 10)

    publisher = load_publisher()

    assert publisher.uptime_percent(7, NOW) == 100.0
    assert publisher.uptime_percent(30, NOW) == 50.0


def test_no_checks_means_no_uptime_yet(aws):
    assert load_publisher().uptime_percent(30, NOW) is None


def test_summary_has_budget_and_is_written_to_s3(aws):
    put_checks([1], hours_ago=1)
    publisher = load_publisher()
    publisher.datetime = _FrozenDatetime  # pin "now" for the handler

    summary = publisher.lambda_handler({}, None)

    assert summary["budget"] == 1.0
    assert summary["slo_percent"] == 99.5
    assert summary["uptime_7d_percent"] == 100.0
    obj = boto3.client("s3").get_object(Bucket=BUCKET, Key="ops/summary.json")
    assert json.loads(obj["Body"].read()) == summary
    assert obj["CacheControl"] == "max-age=60"
    assert obj["ContentType"] == "application/json"


class _FrozenDatetime:
    """Stand-in for the datetime module with a fixed now()."""

    timedelta = datetime.timedelta
    timezone = datetime.timezone

    class datetime(datetime.datetime):
        @classmethod
        def now(cls, tz=None):
            return NOW
