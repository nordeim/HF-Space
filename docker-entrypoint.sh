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
        -c ":${TTYD_PASSWORD}" \
        -t fontSize=14 \
        -t fontFamily="'JetBrains Mono', 'Cascadia Code', monospace" \
        -t theme='{"background": "#0a0a0a"}' \
        bash --login &
    TTYD_PID=$!
    echo "ttyd started with PID: ${TTYD_PID}"
}

# Function to start main application
start_app() {
    echo "Starting main application on port ${APP_PORT:-7860}..."
    
    # Check for common application types
    if [ -f "package.json" ] && grep -q '"start"' package.json; then
        npm start
    elif [ -f "main.py" ] || [ -f "app.py" ]; then
        python -m uvicorn main:app --host 0.0.0.0 --port ${APP_PORT:-7860}
    elif [ -f "manage.py" ]; then
        python manage.py runserver 0.0.0.0:${APP_PORT:-7860}
    elif [ -f "server.js" ] || [ -f "index.js" ]; then
        node server.js
    else
        echo "No application detected. Starting default Python HTTP server..."
        python -m http.server ${APP_PORT:-7860}
    fi
}

# Function to handle graceful shutdown
cleanup() {
    echo "Shutting down services..."
    [ -n "${TTYD_PID}" ] && kill ${TTYD_PID} 2>/dev/null || true
    [ -n "${CRON_PID}" ] && sudo kill ${CRON_PID} 2>/dev/null || true
    exit 0
}

# Trap signals for graceful shutdown
trap cleanup SIGINT SIGTERM

# Main entrypoint logic
case "${1}" in
    "start")
        start_cron
        start_ttyd
        start_app
        ;;
    "cron-only")
        start_cron
        # Keep container running
        tail -f /dev/null
        ;;
    "ttyd-only")
        start_ttyd
        # Keep container running
        tail -f /dev/null
        ;;
    "app-only")
        start_app
        ;;
    *)
        exec "$@"
        ;;
esac

# Wait for any process to exit
wait -n
