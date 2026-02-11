#!/usr/bin/env bash
set -e

# Function to start cron service as user
start_cron() {
    echo "Starting cron service..."
    # Load user's crontab if exists
    if [ -f "/app/crontab" ]; then
        crontab /app/crontab
    fi
    # Start cron in foreground
    sudo /usr/sbin/cron -f &
    CRON_PID=$!
    echo "Cron started with PID: ${CRON_PID}"
}

# Function to start ttyd web terminal
start_ttyd() {
    echo "Starting ttyd web terminal on port ${TTYD_PORT:-7681}..."
    # Start ttyd with bash, allowing login shell with full environment
    /usr/local/bin/ttyd \
        -p "${TTYD_PORT:-7681}" \
        --writable \
        -t fontSize=14 \
        -t fontFamily="'JetBrains Mono', 'Cascadia Code', monospace" \
        -t theme='{"background": "#0a0a0a"}' \
        bash --login &
    TTYD_PID=$!
    echo "ttyd started with PID: ${TTYD_PID}"
}

# Function to start main application - SIMPLIFIED
start_app() {
    echo "Starting HTTP server on port ${APP_PORT:-7860}..."
    # Always start HTTP server (for Hugging Face health check)
    python -m http.server ${APP_PORT:-7860} --bind 0.0.0.0 > /dev/null 2>&1 &
    APP_PID=$!
    echo "HTTP server started with PID: ${APP_PID}"
}

# Function to handle graceful shutdown
cleanup() {
    echo "Shutting down services..."
    [ -n "${TTYD_PID}" ] && kill ${TTYD_PID} 2>/dev/null || true
    [ -n "${CRON_PID}" ] && sudo kill ${CRON_PID} 2>/dev/null || true
    [ -n "${APP_PID}" ] && kill ${APP_PID} 2>/dev/null || true
    exit 0
}

# Trap signals for graceful shutdown
trap cleanup SIGINT SIGTERM

# Main entrypoint logic
case "${1}" in
    "start")
        start_cron
        start_app
        start_ttyd
        ;;
    "cron-only")
        start_cron
        tail -f /dev/null
        ;;
    "ttyd-only")
        start_ttyd
        tail -f /dev/null
        ;;
    "app-only")
        start_app
        tail -f /dev/null
        ;;
    *)
        exec "$@"
        ;;
esac

# Wait for any process to exit
wait -n
