#!/usr/bin/env python3
"""Poll claude-usage and expose Anthropic subscription utilization +
profile info as Prometheus metrics on HTTP_PORT/metrics.

Cross-machine accurate: data comes from Anthropic's own /api/oauth/usage
and /api/oauth/profile endpoints via the bind-mounted claude-usage CLI.
Reset timestamps are exposed as unix epoch seconds; compute "seconds
until reset" in PromQL via `metric - time()`.
"""

import json
import os
import subprocess
import sys
import time
from datetime import datetime
from prometheus_client import start_http_server, Gauge

CLAUDE_USAGE_BIN = os.environ.get("CLAUDE_USAGE_BIN", "/opt/claude-usage/claude-usage")
POLL_INTERVAL = int(os.environ.get("POLL_INTERVAL_SECONDS", "900"))
HTTP_PORT = int(os.environ.get("HTTP_PORT", "9092"))

util_5h = Gauge(
    "claude_subscription_5h_utilization_pct",
    "5-hour session window utilization (percent, 0-100+)",
)
reset_5h_ts = Gauge(
    "claude_subscription_5h_reset_timestamp_seconds",
    "5h window reset time (unix epoch seconds)",
)
util_7d = Gauge(
    "claude_subscription_7d_utilization_pct",
    "7-day rolling window utilization (percent, 0-100+)",
)
reset_7d_ts = Gauge(
    "claude_subscription_7d_reset_timestamp_seconds",
    "7d window reset time (unix epoch seconds)",
)
util_7d_sonnet = Gauge(
    "claude_subscription_7d_sonnet_utilization_pct",
    "7-day Sonnet-specific utilization (percent)",
)
util_7d_opus = Gauge(
    "claude_subscription_7d_opus_utilization_pct",
    "7-day Opus-specific utilization (percent)",
)
util_extra = Gauge(
    "claude_subscription_extra_usage_utilization_pct",
    "Extra-usage (paid overflow) utilization (percent)",
)
poll_success = Gauge(
    "claude_subscription_poll_success",
    "1 if last poll succeeded, 0 if it failed",
)
poll_ts = Gauge(
    "claude_subscription_poll_timestamp_seconds",
    "Unix timestamp of the last successful poll",
)
plan_info = Gauge(
    "claude_subscription_plan_info",
    "Subscription plan info (always 1; carries plan/tier/status/org_type labels)",
    ["plan", "tier", "status", "org_type"],
)


_PLAN_TOKEN_MAP = {"claude": "Claude", "max": "Max", "pro": "Pro"}


def _format_plan_name(rate_limit_tier):
    """Turn 'default_claude_max_20x' into 'Claude Max 20x'."""
    if not rate_limit_tier:
        return "unknown"
    if rate_limit_tier.startswith("default_"):
        rate_limit_tier = rate_limit_tier[len("default_"):]
    tokens = rate_limit_tier.split("_")
    return " ".join(_PLAN_TOKEN_MAP.get(t, t) for t in tokens)


def _parse_iso(ts):
    if ts is None:
        return None
    return datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()


def _set_or_nan(gauge, value):
    gauge.set(float(value) if value is not None else float("nan"))


def _update_window(block, util_g, reset_g):
    if not isinstance(block, dict):
        util_g.set(float("nan"))
        reset_g.set(float("nan"))
        return
    _set_or_nan(util_g, block.get("utilization"))
    _set_or_nan(reset_g, _parse_iso(block.get("resets_at")))


_last_plan_labels = None


def _update_plan(profile):
    """Set the plan_info gauge and clear stale labelsets if the plan changed."""
    global _last_plan_labels
    org = (profile or {}).get("organization") or {}
    tier = org.get("rate_limit_tier") or "unknown"
    status = org.get("subscription_status") or "unknown"
    org_type = org.get("organization_type") or "unknown"
    plan = _format_plan_name(tier)

    new_labels = (plan, tier, status, org_type)
    if _last_plan_labels is not None and _last_plan_labels != new_labels:
        plan_info.remove(*_last_plan_labels)
    plan_info.labels(*new_labels).set(1)
    _last_plan_labels = new_labels


def poll_once():
    proc = subprocess.run(
        [CLAUDE_USAGE_BIN],
        capture_output=True,
        text=True,
        timeout=60,
    )
    if proc.returncode != 0:
        raise RuntimeError(
            f"claude-usage exit {proc.returncode}: {proc.stderr.strip()[:200]}"
        )
    data = json.loads(proc.stdout)
    usage = data.get("usage") or {}
    profile = data.get("profile")

    _update_window(usage.get("five_hour"), util_5h, reset_5h_ts)
    _update_window(usage.get("seven_day"), util_7d, reset_7d_ts)

    sonnet = usage.get("seven_day_sonnet") or {}
    _set_or_nan(util_7d_sonnet, sonnet.get("utilization") if isinstance(sonnet, dict) else None)

    opus = usage.get("seven_day_opus") or {}
    _set_or_nan(util_7d_opus, opus.get("utilization") if isinstance(opus, dict) else None)

    extra = usage.get("extra_usage") or {}
    if isinstance(extra, dict) and extra.get("is_enabled") and extra.get("utilization") is not None:
        util_extra.set(float(extra["utilization"]))
    else:
        util_extra.set(float("nan"))

    _update_plan(profile)


def main():
    print(
        f"usage-poller starting: port={HTTP_PORT} interval={POLL_INTERVAL}s "
        f"bin={CLAUDE_USAGE_BIN}",
        flush=True,
    )
    start_http_server(HTTP_PORT)
    while True:
        try:
            poll_once()
            poll_success.set(1)
            poll_ts.set(time.time())
            print("poll OK", flush=True)
        except Exception as e:
            poll_success.set(0)
            print(f"poll FAILED: {e}", file=sys.stderr, flush=True)
        time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    main()
