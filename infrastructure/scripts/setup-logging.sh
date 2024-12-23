#!/bin/bash

# Wildlife Detection Safari Pokédex - Logging Infrastructure Setup Script
# Version: 1.0.0
# Purpose: Configure and set up centralized logging infrastructure with ELK Stack and CloudWatch
# Dependencies:
# - aws-cli v2.0
# - elastic v8.0
# - filebeat v8.0

set -euo pipefail

# Global Configuration Variables
LOG_RETENTION_DAYS=${LOG_RETENTION_DAYS:-30}
ELASTICSEARCH_URL=${ELASTICSEARCH_URL:-"https://elasticsearch:9200"}
KIBANA_URL=${KIBANA_URL:-"https://kibana:5601"}
LOG_LEVEL=${LOG_LEVEL:-"INFO"}
ENCRYPTION_KEY=${ENCRYPTION_KEY:-"/etc/wildlife-safari/keys/logging.key"}
SSL_CERT_PATH=${SSL_CERT_PATH:-"/etc/wildlife-safari/certs/logging.crt"}

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check required commands
    local required_commands=("aws" "curl" "openssl" "docker")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command not found: $cmd"
            exit 1
        fi
    done

    # Check required files
    if [[ ! -f "$SSL_CERT_PATH" ]]; then
        log_error "SSL certificate not found at $SSL_CERT_PATH"
        exit 1
    fi

    if [[ ! -f "$ENCRYPTION_KEY" ]]; then
        log_error "Encryption key not found at $ENCRYPTION_KEY"
        exit 1
    }
}

# Setup Elasticsearch with security and compliance features
setup_elasticsearch() {
    local cluster_name="wildlife-safari-logs"
    local node_count=3

    log_info "Setting up Elasticsearch cluster: $cluster_name"

    # Create Elasticsearch configuration
    cat > elasticsearch.yml <<EOF
cluster.name: $cluster_name
node.name: \${HOSTNAME}
network.host: 0.0.0.0
discovery.seed_hosts: ["es-node-1", "es-node-2", "es-node-3"]
cluster.initial_master_nodes: ["es-node-1"]
xpack.security.enabled: true
xpack.security.transport.ssl.enabled: true
xpack.security.transport.ssl.verification_mode: certificate
xpack.security.transport.ssl.keystore.path: elastic-certificates.p12
xpack.security.transport.ssl.truststore.path: elastic-certificates.p12
xpack.security.audit.enabled: true
xpack.security.audit.logfile.events.include: ["authentication_success", "authentication_failure", "access_denied", "connection_denied"]
EOF

    # Setup index lifecycle policies
    curl -X PUT "$ELASTICSEARCH_URL/_ilm/policy/logs-policy" -H 'Content-Type: application/json' -d '{
        "policy": {
            "phases": {
                "hot": {
                    "min_age": "0ms",
                    "actions": {
                        "rollover": {
                            "max_age": "1d",
                            "max_size": "50gb"
                        }
                    }
                },
                "warm": {
                    "min_age": "2d",
                    "actions": {
                        "shrink": {
                            "number_of_shards": 1
                        },
                        "forcemerge": {
                            "max_num_segments": 1
                        }
                    }
                },
                "cold": {
                    "min_age": "7d",
                    "actions": {
                        "searchable_snapshot": {
                            "snapshot_repository": "logs_backup"
                        }
                    }
                },
                "delete": {
                    "min_age": "'$LOG_RETENTION_DAYS'd",
                    "actions": {
                        "delete": {}
                    }
                }
            }
        }
    }'
}

# Setup Filebeat for secure log shipping
setup_filebeat() {
    log_info "Configuring Filebeat..."

    # Create Filebeat configuration
    cat > filebeat.yml <<EOF
filebeat.inputs:
- type: container
  paths:
    - /var/log/containers/*.log
  processors:
    - add_kubernetes_metadata:
        host: \${NODE_NAME}
        matchers:
        - logs_path:
            logs_path: "/var/log/containers/"

- type: log
  enabled: true
  paths:
    - /var/log/wildlife-safari/*.log
  fields:
    app: wildlife-safari
  fields_under_root: true
  json.keys_under_root: true
  json.add_error_key: true

output.elasticsearch:
  hosts: ["${ELASTICSEARCH_URL}"]
  protocol: "https"
  ssl.certificate_authorities: ["${SSL_CERT_PATH}"]
  ssl.certificate: "${SSL_CERT_PATH}"
  ssl.key: "${ENCRYPTION_KEY}"
  indices:
    - index: "wildlife-safari-logs-%{+yyyy.MM.dd}"
      when.contains:
        app: "wildlife-safari"

processors:
  - add_host_metadata: ~
  - add_cloud_metadata: ~
  - add_docker_metadata: ~
  - add_kubernetes_metadata: ~
  - drop_fields:
      fields: ["agent.ephemeral_id", "agent.hostname", "agent.id", "agent.version"]

logging.level: ${LOG_LEVEL}
logging.to_files: true
logging.files:
  path: /var/log/filebeat
  name: filebeat
  keepfiles: 7
  permissions: 0644
EOF
}

# Setup AWS CloudWatch logging
setup_cloudwatch() {
    log_info "Configuring CloudWatch logging..."

    # Create log groups with encryption
    local log_groups=(
        "/aws/wildlife-safari/api-gateway"
        "/aws/wildlife-safari/detection-service"
        "/aws/wildlife-safari/collection-service"
        "/aws/wildlife-safari/sync-service"
    )

    for log_group in "${log_groups[@]}"; do
        aws logs create-log-group --log-group-name "$log_group"
        aws logs put-retention-policy \
            --log-group-name "$log_group" \
            --retention-in-days "$LOG_RETENTION_DAYS"
        
        # Enable encryption
        aws logs associate-kms-key \
            --log-group-name "$log_group" \
            --kms-key-id "$(cat $ENCRYPTION_KEY)"
    done

    # Setup cross-region replication
    local regions=("us-west-2" "eu-west-1" "ap-southeast-1")
    for region in "${regions[@]}"; do
        aws logs put-subscription-filter \
            --log-group-name "/aws/wildlife-safari/api-gateway" \
            --filter-name "CrossRegionReplication" \
            --filter-pattern "" \
            --destination-arn "arn:aws:logs:$region:$(aws sts get-caller-identity --query Account --output text):destination:WildlifeSafariLogs" \
            --region "$region"
    done
}

# Setup monitoring integration
setup_monitoring() {
    log_info "Configuring monitoring integration..."

    # Import Prometheus metrics configuration
    local prometheus_config="/etc/prometheus/prometheus.yml"
    cp "$(dirname "$0")/../../src/backend/monitoring/prometheus.yml" "$prometheus_config"

    # Import Grafana dashboards
    local grafana_dashboard="/etc/grafana/provisioning/dashboards/wildlife-safari.json"
    cp "$(dirname "$0")/../../src/backend/monitoring/grafana-dashboards.json" "$grafana_dashboard"
}

# Main execution
main() {
    log_info "Starting logging infrastructure setup..."

    # Check prerequisites
    check_prerequisites

    # Setup components
    setup_elasticsearch
    setup_filebeat
    setup_cloudwatch
    setup_monitoring

    # Verify setup
    if verify_setup; then
        log_info "Logging infrastructure setup completed successfully"
    else
        log_error "Logging infrastructure setup failed"
        exit 1
    fi
}

# Verify setup
verify_setup() {
    local status=0

    # Check Elasticsearch health
    if ! curl -s "$ELASTICSEARCH_URL/_cluster/health" | grep -q '"status":"green"'; then
        log_error "Elasticsearch cluster is not healthy"
        status=1
    fi

    # Check Filebeat status
    if ! systemctl is-active --quiet filebeat; then
        log_error "Filebeat service is not running"
        status=1
    fi

    # Check CloudWatch log groups
    if ! aws logs describe-log-groups --log-group-name-prefix "/aws/wildlife-safari" &>/dev/null; then
        log_error "CloudWatch log groups not properly configured"
        status=1
    fi

    return $status
}

# Execute main function
main "$@"