# Stage 1: Builder stage for plugins and security scanning
FROM kong:3.3-alpine AS builder

# Set build arguments and labels
ARG BUILD_DATE
ARG VCS_REF
LABEL org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.version="1.0.0" \
      org.label-schema.name="wildlife-detection-safari-pokedex-api-gateway" \
      org.label-schema.description="Kong API Gateway for Wildlife Detection Safari Pokédex"

# Install build dependencies with version pinning
RUN apk add --no-cache --virtual .build-deps \
    gcc=12.2.1_git20220924-r10 \
    musl-dev=1.2.4-r2 \
    git=2.40.1-r0 \
    curl=8.4.0-r0 \
    make=4.4.1-r1 \
    luarocks=3.9.2-r0

# Copy custom plugins
COPY ./plugins /tmp/plugins

# Install plugin dependencies with integrity verification
RUN cd /tmp/plugins && \
    luarocks install lua-resty-waf 0.12.1 && \
    luarocks install lua-resty-jwt 0.2.3 && \
    luarocks install lua-resty-redis-connector 1.1.1

# Security scan plugins and dependencies
RUN apk add --no-cache trivy=0.44.1-r0 && \
    trivy fs --severity HIGH,CRITICAL /tmp/plugins

# Stage 2: Final production image
FROM kong:3.3-alpine

# Copy validated configuration and plugins
COPY --from=builder /tmp/plugins /usr/local/kong/plugins
COPY ./config/kong.yml /usr/local/kong/declarative/kong.yml

# Set secure environment variables
ENV KONG_DATABASE=off \
    KONG_PROXY_ACCESS_LOG=/dev/stdout \
    KONG_ADMIN_ACCESS_LOG=/dev/stdout \
    KONG_PROXY_ERROR_LOG=/dev/stderr \
    KONG_ADMIN_ERROR_LOG=/dev/stderr \
    KONG_ADMIN_LISTEN=0.0.0.0:8001 \
    KONG_PLUGINS=bundled,jwt-auth,rate-limiting,cors,waf \
    KONG_SSL=on \
    KONG_SSL_CIPHER_SUITE=modern \
    KONG_NGINX_WORKER_PROCESSES=auto \
    KONG_NGINX_HTTP_CLIENT_BODY_BUFFER_SIZE=2m \
    KONG_NGINX_PROXY_BUFFERING=on \
    KONG_NGINX_PROXY_BUFFER_SIZE=128k \
    KONG_NGINX_PROXY_BUFFERS="4 256k" \
    KONG_REAL_IP_HEADER=X-Forwarded-For \
    KONG_TRUSTED_IPS=0.0.0.0/0,::/0

# Configure security headers
RUN echo "lua_shared_dict kong_rate_limiting_counters 12m;" >> /usr/local/share/lua/5.1/kong/templates/nginx_kong.lua && \
    echo "lua_shared_dict kong_waf_storage 64m;" >> /usr/local/share/lua/5.1/kong/templates/nginx_kong.lua

# Set up WAF rules
COPY ./config/waf-rules /usr/local/kong/waf-rules

# Create non-root user
RUN adduser -S -D -H -h /usr/local/kong kong && \
    chown -R kong:kong /usr/local/kong

# Switch to non-root user
USER kong

# Configure read-only filesystem
VOLUME ["/usr/local/kong/declarative", "/usr/local/kong/ssl"]

# Expose ports
EXPOSE 8000 8443 8001

# Health check configuration
HEALTHCHECK --interval=10s --timeout=10s --retries=3 \
    CMD kong health

# Start Kong Gateway
CMD ["kong", "docker-start"]