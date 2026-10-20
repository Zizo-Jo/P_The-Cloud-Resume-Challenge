"""Black-box uptime check, run every 5 minutes by EventBridge.

Internal metrics only exist when requests reach our code. A broken DNS record
or an expired certificate means silence, not errors, so this probes the site
the way a visitor would and publishes the result as a CloudWatch metric.
"""
import json
import logging
import os
import time
import urllib.request

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

NAMESPACE = "ZihaoCV"
TIMEOUT_SECONDS = 10

cloudwatch = boto3.client("cloudwatch")


def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": "zihao-cv-uptime/1.0"})
    with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
        return response.status, response.read().decode("utf-8", "replace")


def site_is_up(url):
    status, body = fetch(url)
    return status == 200 and "Zihao Zhou" in body


def api_is_healthy(url):
    status, body = fetch(url)
    return status == 200 and json.loads(body).get("status") == "ok"


def lambda_handler(event, context):
    checks = {
        "site": (site_is_up, os.environ["SITE_URL"]),
        "api": (api_is_healthy, os.environ["HEALTH_URL"]),
    }
    started = time.monotonic()
    failed = []
    for name, (check, url) in checks.items():
        try:
            if not check(url):
                failed.append(name)
        except Exception:
            logger.exception("Check %s raised", name)
            failed.append(name)
    latency_ms = (time.monotonic() - started) * 1000

    up = 0 if failed else 1
    if failed:
        logger.error("DOWN: failed checks: %s", ", ".join(failed))
    else:
        logger.info("UP in %.0f ms", latency_ms)

    cloudwatch.put_metric_data(
        Namespace=NAMESPACE,
        MetricData=[
            {"MetricName": "Up", "Value": up, "Unit": "Count"},
            {"MetricName": "LatencyMs", "Value": latency_ms, "Unit": "Milliseconds"},
        ],
    )
    return {"up": bool(up), "failed": failed}
