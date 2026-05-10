FROM python:3.12-slim

RUN pip install --no-cache-dir prometheus_client==0.21.1

WORKDIR /app
COPY poller.py /app/poller.py

ENV CLAUDE_USAGE_BIN=/opt/claude-usage/claude-usage \
    POLL_INTERVAL_SECONDS=900 \
    HTTP_PORT=9092 \
    HOME=/home/poller

# Run as uid 1000 to match the host user that owns ~/.claude.
# Override at runtime with `user:` in compose if your uid differs.
RUN useradd -m -u 1000 poller
USER 1000

EXPOSE 9092
CMD ["python", "/app/poller.py"]
