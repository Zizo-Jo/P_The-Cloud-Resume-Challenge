"""Unit tests for the uptime-check Lambda. The network and CloudWatch are faked."""

import importlib.util
import json
from pathlib import Path

import boto3
import pytest
from moto import mock_aws

CHECK_PATH = Path(__file__).resolve().parents[1] / "src" / "uptime" / "check.py"
SITE = "https://site.test"
HEALTH = "https://api.test/health"


def load_check():
    spec = importlib.util.spec_from_file_location("check", CHECK_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture
def env(monkeypatch):
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "test")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "test")
    monkeypatch.setenv("AWS_DEFAULT_REGION", "us-east-1")
    monkeypatch.setenv("SITE_URL", SITE)
    monkeypatch.setenv("HEALTH_URL", HEALTH)
    with mock_aws():
        yield


def fake_fetch(monkeypatch, check, responses):
    """responses: url -> (status, body) or an Exception to raise."""

    def fetch(url):
        result = responses[url]
        if isinstance(result, Exception):
            raise result
        return result

    monkeypatch.setattr(check, "fetch", fetch)


def up_metric():
    metrics = boto3.client("cloudwatch").list_metrics(Namespace="ZihaoCV", MetricName="Up")["Metrics"]
    assert metrics, "Up metric was not published"
    return metrics


def test_everything_healthy_reports_up(env, monkeypatch):
    check = load_check()
    fake_fetch(monkeypatch, check, {
        SITE: (200, "<h1>Zihao Zhou</h1>"),
        HEALTH: (200, json.dumps({"status": "ok", "count": 5})),
    })

    result = check.lambda_handler({}, None)

    assert result == {"up": True, "failed": []}
    up_metric()


def test_page_without_expected_content_is_down(env, monkeypatch):
    check = load_check()
    fake_fetch(monkeypatch, check, {
        SITE: (200, "<h1>blank page</h1>"),
        HEALTH: (200, json.dumps({"status": "ok"})),
    })

    assert check.lambda_handler({}, None) == {"up": False, "failed": ["site"]}


def test_unhealthy_api_is_down(env, monkeypatch):
    check = load_check()
    fake_fetch(monkeypatch, check, {
        SITE: (200, "Zihao Zhou"),
        HEALTH: (200, json.dumps({"status": "unavailable"})),
    })

    assert check.lambda_handler({}, None) == {"up": False, "failed": ["api"]}


def test_network_error_counts_as_down_and_still_publishes(env, monkeypatch):
    check = load_check()
    fake_fetch(monkeypatch, check, {
        SITE: OSError("connection refused"),
        HEALTH: OSError("timed out"),
    })

    result = check.lambda_handler({}, None)

    assert result == {"up": False, "failed": ["site", "api"]}
    up_metric()  # a failed check must still report, otherwise silence looks like "no data"
