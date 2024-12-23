# -----------------------------
# Stage 1: Builder
# -----------------------------
FROM node:18-alpine AS builder

# Install build dependencies and dumb-init
RUN apk add --no-cache dumb-init=1.2.5-r2 curl=8.4.0-r0 \
    && apk add --no-cache --virtual .build-deps python3 make g++

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./
COPY tsconfig.json ./

# Install dependencies including dev dependencies
RUN npm ci

# Copy source code
COPY src/ ./src/

# Build TypeScript code
RUN npm run build \
    && npm run security-audit \
    && npm prune --production

# -----------------------------
# Stage 2: Production
# -----------------------------
FROM node:18-alpine

# Install dumb-init and security updates
RUN apk add --no-cache dumb-init=1.2.5-r2 curl=8.4.0-r0 \
    && apk upgrade --no-cache

# Set working directory
WORKDIR /app

# Create non-root user/group
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Copy package files and install production dependencies
COPY package*.json ./
RUN npm ci --only=production \
    && npm cache clean --force

# Copy compiled JavaScript from builder
COPY --from=builder /app/dist ./dist

# Set proper permissions
RUN chown -R appuser:appgroup /app \
    && chmod -R 550 /app \
    && chmod -R 770 /app/dist

# Environment configuration
ENV NODE_ENV=production \
    PORT=3000 \
    NODE_OPTIONS="--max-old-space-size=4096" \
    TZ=UTC

# Health check configuration
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

# Container metadata
LABEL maintainer="Wildlife Safari Team" \
    service="collection-service" \
    version="1.0.0" \
    description="Collection management service for Wildlife Detection Safari Pokédex" \
    security.scan-date=${BUILD_DATE}

# Security hardening
RUN rm -rf /usr/local/lib/node_modules/npm \
    && rm -rf /usr/local/bin/npm \
    && rm -rf /usr/local/bin/npx

# Resource limits
RUN echo "appuser soft nofile 65536" >> /etc/security/limits.conf \
    && echo "appuser hard nofile 65536" >> /etc/security/limits.conf

# Expose service port
EXPOSE 3000

# Set user
USER appuser

# Mount points for volumes
VOLUME ["/app/node_modules", "/tmp"]

# Set entry point with dumb-init for proper process management
ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["node", "dist/app.js"]

# Security capabilities
RUN setcap 'cap_net_bind_service=+ep' /usr/local/bin/node

# Read-only root filesystem
RUN chmod a-w /

# Additional security configurations
SECURITY_OPT ["seccomp=unconfined"]
SECURITY_OPT ["no-new-privileges=true"]