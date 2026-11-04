"""Black-box uptime check, run every 5 minutes by EventBridge.

Internal metrics only exist when requests reach our code. A broken DNS record
or an expired certificate means silence, not errors, so this probes the site
the way a visitor would and publishes the result as a CloudWatch metric.

Two refinements after the site-down alarms of 2026-10-28 to 11-02 (only the
page check failed, always as a timeout, while the API check never did):
  - a check that fails with a network error is retried once, so a single
    dropped connection is not reported as an outage;
  - a diagnostic check fetches the page straight from CloudFront, skipping
    Cloudflare. It does not count towards "Up"; it only tells us which hop
    failed: page down + CloudFront ok = the Cloudflare path; both down = AWS.
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
TIMEOUT_SECONDS = 8
RETRY_DELAY_SECONDS = 2

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


def run(name, check, url):
    """True if the check passes. A network error gets one retry; a wrong
    answer (bad status, missing content) does not, because it is not a blip."""
    for attempt in (1, 2):
        try:
            return check(url)
        except Exception:
            if attempt == 2:
                logger.exception("Check %s raised (after a retry)", name)
                return False
            logger.warning("Check %s raised, retrying in %ss", name, RETRY_DELAY_SECONDS)
            time.sleep(RETRY_DELAY_SECONDS)


def lambda_handler(event, context):
    checks = {
        "site": (site_is_up, os.environ["SITE_URL"]),
        "api": (api_is_healthy, os.environ["HEALTH_URL"]),
    }
    started = time.monotonic()
    failed = [name for name, (check, url) in checks.items() if not run(name, check, url)]
    latency_ms = (time.monotonic() - started) * 1000

    # Diagnostic only: the same page straight from CloudFront, without Cloudflare.
    cdn_url = os.environ.get("CDN_URL")
    cdn_up = run("cloudfront-direct", site_is_up, cdn_url) if cdn_url else None

    up = 0 if failed else 1
    cdn_note = "" if cdn_up is None else f" (cloudfront direct: {'ok' if cdn_up else 'FAILED'})"
    if failed:
        logger.error("DOWN: failed checks: %s%s", ", ".join(failed), cdn_note)
    else:
        logger.info("UP in %.0f ms%s", latency_ms, cdn_note)

    metrics = [
        {"MetricName": "Up", "Value": up, "Unit": "Count"},
        {"MetricName": "LatencyMs", "Value": latency_ms, "Unit": "Milliseconds"},
    ]
    if cdn_up is not None:
        metrics.append({"MetricName": "CloudFrontDirectUp", "Value": int(cdn_up), "Unit": "Count"})
    cloudwatch.put_metric_data(Namespace=NAMESPACE, MetricData=metrics)
    return {"up": bool(up), "failed": failed, "cloudfront_direct_up": cdn_up}
