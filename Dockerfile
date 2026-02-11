# syntax=docker/dockerfile:1

# -------------------------------------------------------------------
# SINGLE STAGE: Simple, reliable build
# -------------------------------------------------------------------
FROM python:3.13-trixie

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    TTYD_PORT=7681 \
    APP_PORT=7860 \
    XDG_RUNTIME_DIR=/tmp/runtime-user \
    PATH="/home/user/.local/bin:/usr/local/bin:${PATH}"

# 1. Install ALL system dependencies in ONE layer
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core utilities
    bash coreutils ca-certificates cron curl git less procps sudo vim tar wget zip unzip \
    # Build tools for ttyd
    build-essential cmake pkg-config \
    # ttyd dependencies
    libjson-c-dev libssl-dev libwebsockets-dev \
    # Node.js prerequisites
    gnupg \
    # Playwright system dependencies
    libasound2 libatk-bridge2.0-0 libatk1.0-0 libcairo2 libcups2 \
    libdbus-1-3 libdrm2 libgbm1 libglib2.0-0 libnspr4 libnss3 \
    libpango-1.0-0 libx11-6 libxcb1 libxcomposite1 libxdamage1 \
    libxext6 libxfixes3 libxrandr2 libxshmfence1 && \
    # Clean up
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Install Node.js via NodeSource
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - && \
    apt-get install -y nodejs && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    node --version && npm --version
# 3. Build ttyd
RUN cd /tmp && \
    git clone --depth 1 --branch 1.7.4 https://github.com/tsl0922/ttyd.git && \
    cd ttyd && mkdir build && cd build && \
    cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local .. && \
    make -j$(nproc) && make install && \
    cd / && rm -rf /tmp/ttyd && \
    ttyd --version

# 4. Install Python dependencies
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir \
    fastapi uvicorn httpx pydantic python-multipart \
    sqlalchemy alembic aiofiles jinja2 uv

# 6. Create non-root user (Hugging Face requirement)
RUN groupadd -g 1000 user && \
    useradd -m -u 1000 -g user -d /home/user user && \
    # Limited sudo for cron only
    echo "user ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/user && \
    chmod 0440 /etc/sudoers.d/user && \
    # Create directories
    mkdir -p ${XDG_RUNTIME_DIR} /data /app && \
    chown -R user:user ${XDG_RUNTIME_DIR} /data /app

# Install global npm packages
RUN npm install -g --omit=dev \
    pnpm@latest \
    @google/gemini-cli@latest \
    vite@latest \
    vitest@latest \
    clawhub@latest \
    openclaw@latest \
    @playwright/mcp@latest \
    agent-browser@latest \
    @anthropic-ai/claude-code@latest

# CRITICAL: Install Playwright browsers AS ROOT, BEFORE switching user
# Install browsers first (without trying to get system deps)
RUN npx playwright install chromium
# Then install the system dependencies Playwright needs
RUN npx playwright install-deps chromium

# 7. Switch to non-root user
USER user
WORKDIR /app

# 8. Copy application code
COPY --chown=user:user . /app

# 9. Install project dependencies
RUN if [ -f "package.json" ]; then \
        npm ci --omit=dev 2>/dev/null || npm install --omit=dev; \
    fi
RUN if [ -f "requirements.txt" ]; then \
        pip install --no-cache-dir --user -r requirements.txt; \
    fi

# 10. Install Playwright browsers
#RUN npx playwright install --with-deps chromium

# 11. Setup cron
RUN mkdir -p /home/user/cron && \
    touch /home/user/cron/cron.log && \
    crontab -l 2>/dev/null || echo "# User cron jobs" | crontab -

# 12. Expose ports
EXPOSE ${TTYD_PORT} ${APP_PORT}

# 13. Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:${TTYD_PORT} || exit 1
# 14. Entrypoint script
COPY --chown=user:user docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["start"]
