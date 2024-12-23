# Stage 1: Build stage
FROM golang:1.21-alpine AS builder

# Set build-time variables for optimization
ENV CGO_ENABLED=0 \
    GOOS=linux \
    GOARCH=amd64 \
    GO111MODULE=on

# Install build dependencies and security tools
RUN apk add --no-cache \
    ca-certificates \
    tzdata \
    git \
    make \
    && update-ca-certificates

# Set working directory
WORKDIR /build

# Copy go mod files first for better layer caching
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download && \
    go mod verify

# Copy source code
COPY . .

# Run security scan on dependencies
RUN go install golang.org/x/vuln/cmd/govulncheck@latest && \
    govulncheck ./...

# Build optimized binary with security flags
RUN go build -ldflags="-w -s \
    -X main.version=1.0.0 \
    -X main.buildTime=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    -trimpath \
    -o sync-service ./cmd/sync

# Stage 2: Runtime stage
FROM alpine:3.18

# Set runtime environment variables
ENV PORT=8080 \
    GIN_MODE=release \
    TZ=UTC

# Create non-root user for security
RUN addgroup -S syncapp && \
    adduser -S -G syncapp syncapp && \
    mkdir -p /app/logs && \
    chown -R syncapp:syncapp /app

# Install runtime dependencies
RUN apk add --no-cache \
    ca-certificates \
    tzdata \
    && rm -rf /var/cache/apk/*

# Set working directory
WORKDIR /app

# Copy binary and required files from builder
COPY --from=builder /build/sync-service .
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo

# Set permissions
RUN chmod +x /app/sync-service && \
    chown -R syncapp:syncapp /app

# Switch to non-root user
USER syncapp

# Expose port
EXPOSE 8080

# Set up health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:${PORT}/health || exit 1

# Set resource limits
ENV GOMAXPROCS=2

# Set security options
LABEL org.opencontainers.image.vendor="Wildlife Safari Team" \
      org.opencontainers.image.title="Sync Service" \
      org.opencontainers.image.description="Wildlife Safari Sync Service" \
      org.opencontainers.image.version="1.0.0" \
      org.opencontainers.image.created=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
      org.opencontainers.image.source="https://github.com/wildlifesafari/sync-service" \
      org.opencontainers.image.licenses="Proprietary"

# Start application with monitoring endpoints
CMD ["/app/sync-service"]