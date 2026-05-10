#!/usr/bin/env python3
"""Poll claude-usage and expose Anthropic subscription utilization as
Prometheus metrics on HTTP_PORT/metrics.

Cross-machine accurate: data comes from Anthropic's own /api/oauth/usage
endpoint via the bind-mounted claude-usage CLI, which reads the user's
OAuth credentials. Reset timestamps are exposed as unix epoch seconds;
compute "seconds until reset" in PromQL via `metric - time()`.
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


def _parse_iso(ts):
    if ts is None:
        return None
    # Python <3.11 doesn't accept trailing 'Z' in fromisoformat.
    return datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()


def _set_or_nan(gauge, value):
    gauge.set(float(value) if value is not None else float("nan"))


def _update_window(block, util_g, reset_g):
    if not isinstance(block, dict):
        util_g.set(float("nan"))
        reset_g.set(float("nan"))
        return
    _set_or_nan(util_g, block.get("utilization"))
    reset = _parse_iso(block.get("resets_at"))
    _set_or_nan(reset_g, reset)


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

    _update_window(data.get("five_hour"), util_5h, reset_5h_ts)
    _update_window(data.get("seven_day"), util_7d, reset_7d_ts)

    sonnet = data.get("seven_day_sonnet") or {}
    _set_or_nan(util_7d_sonnet, sonnet.get("utilization") if isinstance(sonnet, dict) else None)

    opus = data.get("seven_day_opus") or {}
    _set_or_nan(util_7d_opus, opus.get("utilization") if isinstance(opus, dict) else None)

    extra = data.get("extra_usage") or {}
    if isinstance(extra, dict) and extra.get("is_enabled") and extra.get("utilization") is not None:
        util_extra.set(float(extra["utilization"]))
    else:
        util_extra.set(float("nan"))


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
