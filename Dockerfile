# syntax=docker/dockerfile:1

# Use the specified Python 3.13 image based on Debian Trixie
FROM python:3.13-trixie

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install system-level dependencies and essential utilities
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Build tools for compiling Python and Node.js native extensions
    build-essential \
    bash \
    # Version control
    git \
    # Efficient file synchronization
    rsync \
    # Archive utilities
    zip unzip \
    # Network utilities
    curl wget \
    # SSL certificates
    ca-certificates \
    # Additional dependencies for ttyd (web-based terminal)
    libwebsockets-dev \
    libjson-c-dev \
    libssl-dev \
    # Build dependencies for ttyd compilation
    cmake \
    pkg-config \
    # >>> NEW: Add sudo and system utilities <<<
    sudo \
    # dbus \
    # systemd \
    # systemd-sysv \
    # Cleanup to reduce layer size
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 24.x LTS using the official NodeSource setup script
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/* \
    # Verify installation
    && node --version \
    && npm --version


# Upgrade pip to the latest version
RUN pip install --no-cache-dir --upgrade pip

# Install OpenClaw globally as requested
RUN npm install -g openclaw@latest

# Install FastAPI/Next.js development dependencies
RUN pip install --no-cache-dir \
    fastapi \
    uvicorn \
    httpx \
    pydantic \
    python-multipart \
    sqlalchemy \
    alembic \
    aiofiles \
    jinja2

# Install Next.js/React development dependencies
RUN npm install -g \
    create-next-app \
    react \
    react-dom \
    typescript \
    @types/node \
    @types/react \
    tailwindcss \
    postcss \
    autoprefixer \
    eslint \
    prettier
    
# >>> NEW: Install ttyd (web-based terminal) from source <<<
# Download and install ttyd - a much more stable alternative to WeTTY
# Note: We're building from source for better compatibility with Python 3.13
RUN cd /tmp \
    && git clone https://github.com/tsl0922/ttyd.git \
    && cd ttyd \
    && mkdir build \
    && cd build \
    && cmake .. \
    && make \
    && make install \
    # Clean up build files
    && cd / \
    && rm -rf /tmp/ttyd \
    # Verify installation
    && ttyd --version

# >>> NEW: Create appuser with UID 1000 (Hugging Face recommendation) <<<
RUN groupadd -g 1000 appuser && useradd -m -u 1000 -g appuser -d /home/appuser appuser

# >>> NEW: Configure passwordless sudo for appuser <<<
RUN echo "appuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/appuser && \
    chmod 0440 /etc/sudoers.d/appuser

# Create the default application directory and set ownership
RUN mkdir -p /app 
COPY . /app
RUN pip install -r /app/requirements.txt
RUN chown -R appuser:appuser /app
RUN chmod +x /app/*sh

# Switch to the non-root user
USER appuser

# Set the working directory inside the container
WORKDIR /app

# >>> NEW: Set up XDG_RUNTIME_DIR (fixed without shell expansion) <<<
ENV XDG_RUNTIME_DIR=/run/user/1000

# Set environment variable for Python to run in unbuffered mode
ENV PYTHONUNBUFFERED=1

# Default port for ttyd (Hugging Face Spaces expects this)
ENV TTYD_PORT=7681

# Expose both ports
EXPOSE 7681
EXPOSE 7860

# Dummy health check that always passes
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD true

# Set the default command to start the web terminal
CMD ["/app/start-all.sh"]