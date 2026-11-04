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
CDN = "https://d123.cloudfront.test"


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
    monkeypatch.setenv("CDN_URL", CDN)
    with mock_aws():
        yield


def fake_fetch(monkeypatch, check, responses):
    """responses: url -> (status, body), an Exception to raise, or a list of
    those returned one per call (to test the retry). CDN defaults to healthy."""
    responses = {CDN: (200, "Zihao Zhou"), **responses}
    calls = {}

    def fetch(url):
        result = responses[url]
        if isinstance(result, list):
            result = result[min(calls.get(url, 0), len(result) - 1)]
        calls[url] = calls.get(url, 0) + 1
        if isinstance(result, Exception):
            raise result
        return result

    monkeypatch.setattr(check, "fetch", fetch)
    monkeypatch.setattr(check.time, "sleep", lambda seconds: None)
    return calls


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

    assert result == {"up": True, "failed": [], "cloudfront_direct_up": True}
    up_metric()


def test_page_without_expected_content_is_down(env, monkeypatch):
    check = load_check()
    fake_fetch(monkeypatch, check, {
        SITE: (200, "<h1>blank page</h1>"),
        HEALTH: (200, json.dumps({"status": "ok"})),
    })

    assert check.lambda_handler({}, None)["failed"] == ["site"]


def test_unhealthy_api_is_down(env, monkeypatch):
    check = load_check()
    fake_fetch(monkeypatch, check, {
        SITE: (200, "Zihao Zhou"),
        HEALTH: (200, json.dumps({"status": "unavailable"})),
    })

    assert check.lambda_handler({}, None)["failed"] == ["api"]


def test_network_error_counts_as_down_and_still_publishes(env, monkeypatch):
    check = load_check()
    fake_fetch(monkeypatch, check, {
        SITE: OSError("connection refused"),
        HEALTH: OSError("timed out"),
    })

    result = check.lambda_handler({}, None)

    assert result["up"] is False
    assert result["failed"] == ["site", "api"]
    up_metric()  # a failed check must still report, otherwise silence looks like "no data"


def test_one_timeout_is_retried_and_not_reported_as_down(env, monkeypatch):
    check = load_check()
    calls = fake_fetch(monkeypatch, check, {
        SITE: [TimeoutError("The read operation timed out"), (200, "Zihao Zhou")],
        HEALTH: (200, json.dumps({"status": "ok"})),
    })

    assert check.lambda_handler({}, None)["up"] is True
    assert calls[SITE] == 2


def test_wrong_content_is_not_retried(env, monkeypatch):
    check = load_check()
    calls = fake_fetch(monkeypatch, check, {
        SITE: (200, "blank"),
        HEALTH: (200, json.dumps({"status": "ok"})),
    })

    assert check.lambda_handler({}, None)["failed"] == ["site"]
    assert calls[SITE] == 1


def test_cloudfront_direct_only_diagnoses_and_does_not_change_up(env, monkeypatch):
    check = load_check()
    fake_fetch(monkeypatch, check, {
        SITE: TimeoutError("The read operation timed out"),
        HEALTH: (200, json.dumps({"status": "ok"})),
        CDN: (200, "Zihao Zhou"),
    })

    result = check.lambda_handler({}, None)

    # The page failed through Cloudflare but CloudFront itself served it:
    # the problem is the Cloudflare hop.
    assert result == {"up": False, "failed": ["site"], "cloudfront_direct_up": True}
    names = {m["MetricName"] for m in boto3.client("cloudwatch").list_metrics(Namespace="ZihaoCV")["Metrics"]}
    assert "CloudFrontDirectUp" in names
