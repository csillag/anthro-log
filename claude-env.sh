# Source this in any shell where Claude Code runs.
#   source ~/deai/anthro-log/claude-env.sh
#
# Endpoint default = localhost. Override ANTHRO_LOG_HOST if collector lives
# on a different machine (e.g. ANTHRO_LOG_HOST=192.168.1.42 source ...).

: "${ANTHRO_LOG_HOST:=localhost}"

export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_EXPORTER=otlp
export OTEL_LOGS_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_PROTOCOL=grpc
export OTEL_EXPORTER_OTLP_ENDPOINT="http://${ANTHRO_LOG_HOST}:4317"

# Faster export = quicker dashboard updates. Default is 60s/5s.
export OTEL_METRIC_EXPORT_INTERVAL=10000   # 10s
export OTEL_LOGS_EXPORT_INTERVAL=5000      # 5s

# Optional: tag your sessions so multi-user scrapes are attributable.
# export OTEL_RESOURCE_ATTRIBUTES="user.id=$(id -un),host.name=$(hostname)"

echo "Claude Code OTel → ${OTEL_EXPORTER_OTLP_ENDPOINT}"
