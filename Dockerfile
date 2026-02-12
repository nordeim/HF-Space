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
    bash coreutils ca-certificates cron curl git less procps sudo vim tar wget zip unzip tmux openssh-client \
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

RUN cd /usr/bin && wget https://github.com/nordeim/HF-Space/raw/refs/heads/main/bun
RUN cd /usr/bin && wget https://github.com/nordeim/HF-Space/raw/refs/heads/main/uv
RUN cd /usr/bin && wget https://github.com/nordeim/HF-Space/raw/refs/heads/main/uvx
RUN chmod a+x /usr/bin/bun /usr/bin/uv*
RUN wget https://github.com/anomalyco/opencode/releases/download/v1.1.59/opencode-linux-x64.tar.gz -O /home/opencode-linux-x64.tar.gz
RUN tar -xf /home/opencode-linux-x64.tar.gz -C /usr/bin

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

RUN mkdir -p /home/project/opencode && chown -R user:user /home/project
RUN groupadd -g 1001 opencode && useradd -m -u 1001 -g opencode -d /home/opencode opencode
RUN chmod 775 /home/opencode && usermod -aG opencode user
RUN chmod 777 /home/project/opencode
RUN wget https://github.com/nordeim/HF-Space/raw/refs/heads/main/project-openclaw.tgz -O /home/project-openclaw.tgz
RUN tar -xf /home/project-openclaw.tgz -C /home/project
    
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
RUN pip install --no-cache-dir --user markitdown[all]
RUN pip install --no-cache-dir --user beautifulsoup4 charset-normalizer defusedxml flatbuffers httptools magika markdownify markitdown mpmath numpy onnxruntime packaging protobuf python-dotenv PyYAML requests six soupsieve sympy urllib3 uvloop watchfiles websockets

# 10. Install Playwright browsers
#RUN npx playwright install --with-deps chromium

# 11. Setup cron
RUN mkdir -p /home/user/cron && \
    touch /home/user/cron/cron.log && \
    crontab -l 2>/dev/null || echo "# User cron jobs" | crontab -
RUN wget https://raw.githubusercontent.com/nordeim/HF-Space/refs/heads/main/my-cron-job.txt -O /app/my-cron-job.txt && cat /app/my-cron-job.txt | crontab -
RUN mkdir /home/user/.openclaw && wget https://github.com/nordeim/HF-Space/raw/refs/heads/main/openclaw-user.tgz -O /app/openclaw-user.tgz && tar -xf /app/openclaw-user.tgz -C /home/user/.openclaw
RUN mkdir -p /home/user/.bun/install/global && cd /home/user/.bun/install/global && bun install mcporter
RUN wget https://raw.githubusercontent.com/nordeim/HF-Space/refs/heads/main/brew-install.sh -O /app/brew-install.sh && chmod +x /app/brew-install.sh && /app/brew-install.sh
RUN wget https://raw.githubusercontent.com/nordeim/HF-Space/refs/heads/main/profile.txt -O /home/user/.profile
RUN sudo ln -sf /home/user /home/pete
RUN mkdir /home/user/.claude && wget https://github.com/nordeim/HF-Space/raw/refs/heads/main/claude.tar.xz -O /home/user/claude.tar.xz && tar -xf /home/user/claude.tar.xz -C /home/user/.claude
RUN touch /home/project/openclaw/morning_7am_cron.sh && chmod +x /home/project/openclaw/morning_7am_cron.sh

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
