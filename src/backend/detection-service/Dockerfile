# Stage 1: Builder stage
FROM python:3.11-slim AS builder

# Version tracking
LABEL maintainer="Wildlife Detection Service Team"
LABEL version="1.0.0"
LABEL description="Wildlife Detection Service with LNN-based species and fossil detection"

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    python3-dev \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /build

# Copy requirements file
COPY requirements.txt .

# Configure pip
ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_DEFAULT_TIMEOUT=100 \
    PYTHONUNBUFFERED=1

# Install dependencies with optimized compilation
RUN python -m venv /opt/venv && \
    . /opt/venv/bin/activate && \
    pip install --no-cache-dir -U pip setuptools wheel && \
    pip install --no-cache-dir -r requirements.txt && \
    # Strip debug symbols
    find /opt/venv -type f -name "*.so" -exec strip --strip-unneeded {} + && \
    # Remove unnecessary files
    find /opt/venv -type d -name "__pycache__" -exec rm -rf {} + && \
    find /opt/venv -type f -name "*.pyc" -delete

# Stage 2: Runtime stage
FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04 AS runtime

# Install Python 3.11 runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.11 \
    python3.11-venv \
    libpython3.11 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -r -s /bin/false detection-service

# Set working directory
WORKDIR /app

# Copy virtual environment from builder
COPY --from=builder /opt/venv /opt/venv

# Copy application code
COPY src/ /app/src/

# Set environment variables
ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONPATH="/app" \
    PORT=8000 \
    MODEL_PATH="/app/models" \
    LOG_LEVEL="INFO" \
    WORKERS=4 \
    CUDA_VISIBLE_DEVICES="0" \
    PYTORCH_CUDA_ALLOC_CONF="max_split_size_mb:512"

# Create necessary directories with correct permissions
RUN mkdir -p /app/models /app/cache && \
    chown -R detection-service:detection-service /app

# Switch to non-root user
USER detection-service

# Expose ports for API and metrics
EXPOSE 8000 9100

# Set up healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:8000/health && nvidia-smi > /dev/null || exit 1

# Set resource limits
ENV NVIDIA_VISIBLE_DEVICES="0" \
    NVIDIA_DRIVER_CAPABILITIES="compute,utility" \
    NVIDIA_REQUIRE_CUDA="cuda>=11.8"

# Command to run the application
CMD ["python", "-m", "uvicorn", "src.app:app", \
     "--host", "0.0.0.0", \
     "--port", "8000", \
     "--workers", "4", \
     "--log-level", "info", \
     "--limit-concurrency", "1000", \
     "--limit-max-requests", "10000", \
     "--timeout-keep-alive", "30"]

# Security labels
LABEL org.opencontainers.image.source="https://github.com/wildlife-detection-service" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="Wildlife Detection Service" \
      org.opencontainers.image.title="Wildlife Detection Service" \
      org.opencontainers.image.description="LNN-powered wildlife and fossil detection service" \
      org.opencontainers.image.version="1.0.0" \
      org.opencontainers.image.created="2023-10-20" \
      security.capabilities="compute,utility"