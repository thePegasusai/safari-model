#!/bin/bash

# Wildlife Detection Safari Pokédex - Kong API Gateway Setup Script
# Version: 1.0.0
# Dependencies:
# - curl v7.0+
# - jq v1.6+
# - docker v24.0+
# - redis-tools v6.0+

set -euo pipefail

# Configuration variables
KONG_ADMIN_URL="http://localhost:8001"
KONG_PROXY_URL="http://localhost:8000"
CONFIG_PATH="../api-gateway/config/kong.yml"
REDIS_URL="redis://redis-cluster:6379"
SSL_CERT_PATH="/etc/kong/ssl"
LOG_PATH="/var/log/kong"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logging function
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}"
}

# Health check function
check_kong_health() {
    log "INFO" "Performing Kong health check..."
    
    # Check Kong Admin API
    if ! curl -s -o /dev/null -w "%{http_code}" "${KONG_ADMIN_URL}/status" | grep -q "200"; then
        log "ERROR" "Kong Admin API is not accessible"
        return 1
    fi
    
    # Check Redis connectivity
    if ! redis-cli -u "${REDIS_URL}" ping | grep -q "PONG"; then
        log "ERROR" "Redis cluster is not accessible"
        return 1
    }
    
    # Verify SSL certificates
    if [ ! -f "${SSL_CERT_PATH}/kong-default.crt" ]; then
        log "ERROR" "SSL certificates not found"
        return 1
    }
    
    # Check plugin status
    local required_plugins=("jwt-auth" "rate-limiting" "cors" "prometheus")
    for plugin in "${required_plugins[@]}"; do
        if ! curl -s "${KONG_ADMIN_URL}/plugins" | jq -r '.data[].name' | grep -q "^${plugin}$"; then
            log "ERROR" "Required plugin ${plugin} is not enabled"
            return 1
        fi
    done
    
    log "INFO" "Health check completed successfully"
    return 0
}

# Plugin setup function
setup_plugins() {
    log "INFO" "Configuring Kong plugins..."
    
    # Configure JWT authentication
    curl -s -X POST "${KONG_ADMIN_URL}/plugins" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "jwt-auth",
            "config": {
                "key_claim_name": "kid",
                "claims_to_verify": ["exp", "nbf", "iss"],
                "maximum_expiration": 3600,
                "algorithm": "RS256"
            }
        }'
    
    # Configure rate limiting
    curl -s -X POST "${KONG_ADMIN_URL}/plugins" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "rate-limiting",
            "config": {
                "minute": 300,
                "policy": "redis",
                "redis_host": "redis",
                "redis_port": 6379,
                "fault_tolerant": true
            }
        }'
    
    # Configure CORS
    curl -s -X POST "${KONG_ADMIN_URL}/plugins" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "cors",
            "config": {
                "origins": ["*"],
                "methods": ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
                "headers": ["Authorization", "Content-Type", "X-Request-ID"],
                "exposed_headers": ["X-Auth-Token", "X-Request-ID"],
                "max_age": 3600,
                "credentials": true
            }
        }'
    
    # Configure Prometheus metrics
    curl -s -X POST "${KONG_ADMIN_URL}/plugins" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "prometheus",
            "config": {}
        }'
    
    log "INFO" "Plugin configuration completed"
}

# Service configuration function
configure_services() {
    log "INFO" "Configuring Kong services..."
    
    # Load configuration from YAML
    if [ ! -f "${CONFIG_PATH}" ]; then
        log "ERROR" "Configuration file not found: ${CONFIG_PATH}"
        return 1
    }
    
    # Apply configuration using deck
    docker run --rm \
        -v "${CONFIG_PATH}:/kong.yml" \
        kong/deck sync \
        --kong-addr "${KONG_ADMIN_URL}" \
        --state /kong.yml
    
    # Verify service configuration
    local services=("auth-service" "detection-service" "collection-service" "sync-service")
    for service in "${services[@]}"; do
        if ! curl -s "${KONG_ADMIN_URL}/services/${service}" | jq -r '.name' | grep -q "^${service}$"; then
            log "ERROR" "Service ${service} configuration failed"
            return 1
        fi
    done
    
    log "INFO" "Service configuration completed"
}

# Security configuration function
apply_security() {
    log "INFO" "Applying security configurations..."
    
    # Configure TLS
    curl -s -X PATCH "${KONG_ADMIN_URL}" \
        -H "Content-Type: application/json" \
        -d '{
            "ssl_cipher_suite": "modern",
            "ssl_protocols": ["TLSv1.2", "TLSv1.3"],
            "ssl_prefer_server_ciphers": true
        }'
    
    # Configure security headers
    curl -s -X POST "${KONG_ADMIN_URL}/plugins" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "response-transformer",
            "config": {
                "add": {
                    "headers": [
                        "Strict-Transport-Security:max-age=31536000; includeSubDomains",
                        "X-Content-Type-Options:nosniff",
                        "X-Frame-Options:DENY",
                        "X-XSS-Protection:1; mode=block"
                    ]
                }
            }
        }'
    
    log "INFO" "Security configuration completed"
}

# Main execution
main() {
    log "INFO" "Starting Kong API Gateway setup..."
    
    # Create required directories
    mkdir -p "${SSL_CERT_PATH}" "${LOG_PATH}"
    
    # Check Kong health
    if ! check_kong_health; then
        log "ERROR" "Health check failed"
        exit 1
    fi
    
    # Setup components
    setup_plugins
    configure_services
    apply_security
    
    # Final health check
    if check_kong_health; then
        log "INFO" "Kong API Gateway setup completed successfully"
        exit 0
    else
        log "ERROR" "Final health check failed"
        exit 1
    fi
}

# Script execution
main "$@"