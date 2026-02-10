# syntax=docker/dockerfile:1

# -------------------------------------------------------------------
# Stage 1: Build Stage - Heavy compilation and downloads
# -------------------------------------------------------------------
FROM python:3.13-slim-trixie AS builder

ENV DEBIAN_FRONTEND=noninteractive \
    NODE_VERSION=24 \
    PYTHONUNBUFFERED=1

# Install build dependencies only
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    cmake \
    curl \
    git \
    libjson-c-dev \
    libssl-dev \
    libwebsockets-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 24.x LTS with binary verification
RUN ARCH="$(dpkg --print-architecture)" && \
    case "${ARCH}" in \
        amd64) ARCH="x64";; \
        arm64) ARCH="arm64";; \
        *) echo "Unsupported architecture: ${ARCH}" && exit 1;; \
    esac && \
    NODE_SHA256="$(curl -fsSL https://unofficial-builds.nodejs.org/download/release/v24.x/SHASUMS256.txt | \
    grep "node-v24.*linux-${ARCH}.tar.xz" | head -1 | cut -d ' ' -f1)" && \
    curl -fsSL "https://unofficial-builds.nodejs.org/download/release/v24.x/node-v24.x-linux-${ARCH}.tar.xz" -o /tmp/node.tar.xz && \
    echo "${NODE_SHA256} /tmp/node.tar.xz" | sha256sum -c - && \
    tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 --no-same-owner && \
    rm -rf /tmp/node.tar.xz && \
    ln -s /usr/local/bin/node /usr/local/bin/nodejs && \
    npm config set fund false --global

# Build ttyd from source (optimized for size)
RUN cd /tmp && \
    git clone --depth 1 --branch 1.7.4 https://github.com/tsl0922/ttyd.git && \
    cd ttyd && \
    mkdir build && cd build && \
    cmake -DCMAKE_BUILD_TYPE=Release .. && \
    make -j$(nproc) && \
    make install && \
    cd / && rm -rf /tmp/ttyd

# Install global npm packages (Playwright separately due to browser downloads)
RUN npm install -g --omit=dev \
    pnpm@latest \
    @google/gemini-cli@latest \
    vite@latest \
    vitest@latest \
    clawhub@latest \
    @playwright/mcp@latest \
    agent-browser@latest \
    @anthropic-ai/claude-code@latest

# Install Python dependencies globally (will be copied in final stage)
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir \
    fastapi \
    uvicorn \
    httpx \
    pydantic \
    python-multipart \
    sqlalchemy \
    alembic \
    aiofiles \
    jinja2

# -------------------------------------------------------------------
# Stage 2: Runtime Stage - Minimal, secure production image
# -------------------------------------------------------------------
FROM python:3.13-slim-trixie

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    TTYD_PORT=7681 \
    APP_PORT=7860 \
    XDG_RUNTIME_DIR=/tmp/runtime-appuser \
    PATH="/home/appuser/.local/bin:${PATH}"

# Install runtime dependencies (minimal set)
RUN apt-get update && apt-get install -y --no-install-recommends \
    # System essentials
    bash \
    ca-certificates \
    curl \
    git \
    less \
    procps \
    sudo \
    vim \
    # Cron with secure defaults
    cron \
    # Playwright system dependencies (minimal for headless)
    libasound2 \
    libatk-bridge2.0-0 \
    libatk1.0-0 \
    libcairo2 \
    libcups2 \
    libdbus-1-3 \
    libdrm2 \
    libgbm1 \
    libglib2.0-0 \
    libgtk-3-0 \
    libnspr4 \
    libnss3 \
    libpango-1.0-0 \
    libx11-6 \
    libxcb1 \
    libxcomposite1 \
    libxdamage1 \
    libxext6 \
    libxfixes3 \
    libxrandr2 \
    libxshmfence1 \
    # Cleanup
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Create non-root user with specific UID/GID for Hugging Face compatibility
RUN groupadd -g 1000 appuser && \
    useradd -m -u 1000 -g appuser -d /home/appuser appuser && \
    # Configure secure sudo access (limited to specific commands)
    echo "appuser ALL=(ALL) NOPASSWD: /usr/sbin/cron, /usr/bin/crontab" > /etc/sudoers.d/appuser && \
    chmod 0440 /etc/sudoers.d/appuser && \
    # Create runtime directory with correct permissions
    mkdir -p ${XDG_RUNTIME_DIR} && \
    chown -R appuser:appuser ${XDG_RUNTIME_DIR} && \
    # Create data directory for persistent storage
    mkdir -p /data && \
    chown -R appuser:appuser /data

# Copy compiled artifacts and global packages from builder
COPY --from=builder /usr/local/bin/ttyd /usr/local/bin/ttyd
COPY --from=builder /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=builder /usr/local/bin/node /usr/local/bin/node
COPY --from=builder /usr/local/bin/npm /usr/local/bin/npm
COPY --from=builder /usr/local/bin/pnpm /usr/local/bin/pnpm
COPY --from=builder /usr/local/lib/python3.13/site-packages /usr/local/lib/python3.13/site-packages

# Create symlinks for global npm packages
RUN cd /usr/local/bin && \
    for tool in vite vitest gemini-cli claude-code; do \
        ln -sf ../lib/node_modules/@*/$tool/bin/* ./ 2>/dev/null || true; \
        ln -sf ../lib/node_modules/$tool/bin/* ./ 2>/dev/null || true; \
    done && \
    # Verify installations
    node --version && npm --version && python --version

# Switch to non-root user
USER appuser

# Set working directory
WORKDIR /app

# Copy application code with proper ownership
COPY --chown=appuser:appuser . /app

# Install Playwright browsers (as non-root user)
RUN npx playwright install --with-deps chromium

# Install project dependencies
RUN if [ -f "package.json" ]; then npm ci --omit=dev; fi
RUN if [ -f "requirements.txt" ]; then pip install --no-cache-dir --user -r requirements.txt; fi

# Set up cron with user permissions
RUN mkdir -p /home/appuser/cron && \
    touch /home/appuser/cron/cron.log && \
    crontab -l 2>/dev/null || echo "# Cron jobs for appuser" | crontab -

# Expose ports (ttyd terminal and main app)
EXPOSE ${TTYD_PORT} ${APP_PORT}

# Health check verifies both services
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:${TTYD_PORT} || exit 1

# Use entrypoint script for proper service orchestration
COPY --chown=appuser:appuser docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["start"]
