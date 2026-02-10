#!/bin/bash
# Create XDG_RUNTIME_DIR for the current user
export XDG_RUNTIME_DIR=/run/user/$(id -u)
sudo mkdir -p $XDG_RUNTIME_DIR 2>/dev/null || true
sudo chmod 0700 $XDG_RUNTIME_DIR 2>/dev/null || true

# Start a minimal HTTP server on port 7860 (for HF Spaces health check)
python3 -m http.server 7860 --bind 0.0.0.0 > /dev/null 2>&1 &

echo "================================================================================"
echo "🚀 Development Container Web Terminal"
echo "================================================================================"
echo ""
echo "📡 Web Terminal: Access via browser on port 7681"
echo "✅ Health Check: HTTP server on port 7860"
echo "🔧 Sudo available: appuser has passwordless sudo"
echo "👤 User ID: $(id -u)"
echo ""
echo "================================================================================"

# Start web terminal (foreground - keeps container alive)
exec ttyd \
  --port ${TTYD_PORT:-7681} \
  --writable \
  --client-option titleFixed="Dev Container Terminal" \
  --client-option theme='"'"'{"background":"#1e1e1e"}'"'"' \
  bash