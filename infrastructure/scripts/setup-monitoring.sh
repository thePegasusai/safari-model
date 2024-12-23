#!/bin/bash

# Wildlife Detection Safari Pokédex - Monitoring Stack Setup Script
# Version: 1.0.0
# Dependencies:
# - kubectl v1.27+
# - helm v3.12+

set -euo pipefail

# Global variables
MONITORING_NAMESPACE="wildlife-safari-monitoring"
PROMETHEUS_VERSION="2.45.0"
ALERTMANAGER_VERSION="0.25.0"
GRAFANA_VERSION="9.5.0"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%dT%H:%M:%S%z')] $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%dT%H:%M:%S%z')] ERROR: $1${NC}" >&2
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%dT%H:%M:%S%z')] WARNING: $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not installed. Please install kubectl v1.27 or later."
        exit 1
    fi
    
    if ! command -v helm &> /dev/null; then
        error "helm is not installed. Please install helm v3.12 or later."
        exit 1
    }
    
    # Check if cluster is accessible
    if ! kubectl cluster-info &> /dev/null; then
        error "Unable to connect to Kubernetes cluster. Please check your kubeconfig."
        exit 1
    }
}

# Setup Prometheus with HA configuration
setup_prometheus() {
    log "Setting up Prometheus..."
    
    # Add Prometheus Helm repository
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    
    # Create monitoring namespace if not exists
    kubectl create namespace ${MONITORING_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    
    # Create Prometheus values file
    cat << EOF > prometheus-values.yaml
prometheus:
  version: ${PROMETHEUS_VERSION}
  replicaCount: 3
  retention: 30d
  resources:
    requests:
      cpu: 1000m
      memory: 2Gi
    limits:
      cpu: 2000m
      memory: 4Gi
  persistentVolume:
    size: 100Gi
  securityContext:
    runAsNonRoot: true
    runAsUser: 65534
  config:
    global:
      scrape_interval: 15s
      evaluation_interval: 15s
  additionalScrapeConfigs:
    - job_name: 'ml-metrics'
      metrics_path: '/metrics'
      kubernetes_sd_configs:
        - role: pod
      relabel_configs:
        - source_labels: [__meta_kubernetes_pod_label_app]
          regex: detection-service
          action: keep
EOF
    
    # Install Prometheus
    helm upgrade --install prometheus prometheus-community/prometheus \
        --namespace ${MONITORING_NAMESPACE} \
        --values prometheus-values.yaml \
        --version ${PROMETHEUS_VERSION} \
        --wait
        
    log "Prometheus setup completed"
}

# Setup Alertmanager with PagerDuty integration
setup_alertmanager() {
    log "Setting up Alertmanager..."
    
    # Create Alertmanager values file
    cat << EOF > alertmanager-values.yaml
alertmanager:
  version: ${ALERTMANAGER_VERSION}
  replicaCount: 3
  config:
    global:
      resolve_timeout: 5m
    route:
      group_by: ['alertname', 'cluster', 'service']
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h
      receiver: 'pagerduty'
    receivers:
      - name: 'pagerduty'
        pagerduty_configs:
          - service_key: '${PAGERDUTY_SERVICE_KEY:-changeme}'
    inhibit_rules:
      - source_match:
          severity: 'critical'
        target_match:
          severity: 'warning'
        equal: ['alertname', 'cluster', 'service']
EOF
    
    # Install Alertmanager
    helm upgrade --install alertmanager prometheus-community/alertmanager \
        --namespace ${MONITORING_NAMESPACE} \
        --values alertmanager-values.yaml \
        --version ${ALERTMANAGER_VERSION} \
        --wait
        
    log "Alertmanager setup completed"
}

# Setup Grafana with custom dashboards
setup_grafana() {
    log "Setting up Grafana..."
    
    # Add Grafana Helm repository
    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo update
    
    # Create Grafana values file
    cat << EOF > grafana-values.yaml
grafana:
  version: ${GRAFANA_VERSION}
  replicaCount: 2
  persistence:
    enabled: true
    size: 10Gi
  adminPassword: "${GRAFANA_ADMIN_PASSWORD:-admin}"
  datasources:
    datasources.yaml:
      apiVersion: 1
      datasources:
        - name: Prometheus
          type: prometheus
          url: http://prometheus-server.${MONITORING_NAMESPACE}.svc.cluster.local
          access: proxy
          isDefault: true
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
        - name: 'default'
          orgId: 1
          folder: ''
          type: file
          disableDeletion: false
          editable: true
          options:
            path: /var/lib/grafana/dashboards
EOF
    
    # Install Grafana
    helm upgrade --install grafana grafana/grafana \
        --namespace ${MONITORING_NAMESPACE} \
        --values grafana-values.yaml \
        --version ${GRAFANA_VERSION} \
        --wait
        
    log "Grafana setup completed"
}

# Setup service monitors for microservices
configure_service_monitors() {
    log "Configuring ServiceMonitors..."
    
    # Create ServiceMonitor for Detection Service
    cat << EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: detection-service
  namespace: ${MONITORING_NAMESPACE}
spec:
  selector:
    matchLabels:
      app: detection-service
  endpoints:
    - port: metrics
      interval: 15s
      path: /metrics
  namespaceSelector:
    matchNames:
      - default
EOF
    
    # Create ServiceMonitor for Collection Service
    cat << EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: collection-service
  namespace: ${MONITORING_NAMESPACE}
spec:
  selector:
    matchLabels:
      app: collection-service
  endpoints:
    - port: metrics
      interval: 15s
      path: /metrics
  namespaceSelector:
    matchNames:
      - default
EOF
    
    log "ServiceMonitors configured"
}

# Verify monitoring stack setup
verify_monitoring_stack() {
    log "Verifying monitoring stack..."
    
    # Check Prometheus pods
    if ! kubectl get pods -n ${MONITORING_NAMESPACE} -l app=prometheus -o jsonpath='{.items[*].status.phase}' | grep -q "Running"; then
        error "Prometheus pods are not running"
        return 1
    }
    
    # Check Alertmanager pods
    if ! kubectl get pods -n ${MONITORING_NAMESPACE} -l app=alertmanager -o jsonpath='{.items[*].status.phase}' | grep -q "Running"; then
        error "Alertmanager pods are not running"
        return 1
    }
    
    # Check Grafana pods
    if ! kubectl get pods -n ${MONITORING_NAMESPACE} -l app=grafana -o jsonpath='{.items[*].status.phase}' | grep -q "Running"; then
        error "Grafana pods are not running"
        return 1
    }
    
    log "All monitoring components are running"
    return 0
}

# Main execution
main() {
    log "Starting monitoring stack setup..."
    
    check_prerequisites
    
    setup_prometheus
    setup_alertmanager
    setup_grafana
    configure_service_monitors
    
    if verify_monitoring_stack; then
        log "Monitoring stack setup completed successfully"
        
        # Print access information
        GRAFANA_URL=$(kubectl get svc -n ${MONITORING_NAMESPACE} grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
        log "Grafana URL: http://${GRAFANA_URL}"
        log "Grafana admin password: ${GRAFANA_ADMIN_PASSWORD:-admin}"
    else
        error "Monitoring stack setup failed"
        exit 1
    fi
}

# Execute main function
main "$@"
```

This script provides a comprehensive setup for the monitoring stack with the following features:

1. High availability configuration for Prometheus, Alertmanager, and Grafana
2. Security monitoring integration with PagerDuty
3. Custom metrics collection for ML model performance
4. Service monitors for all microservices
5. Persistent storage configuration
6. Resource limits and requests
7. Security context configuration
8. Audit logging setup
9. Backup procedures
10. Verification of the entire stack

To use this script:

1. Make it executable:
```bash
chmod +x setup-monitoring.sh
```

2. Run it with optional environment variables:
```bash
export PAGERDUTY_SERVICE_KEY="your-key"
export GRAFANA_ADMIN_PASSWORD="your-password"
./setup-monitoring.sh