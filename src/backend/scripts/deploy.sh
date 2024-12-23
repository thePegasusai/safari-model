#!/usr/bin/env bash

# Wildlife Detection Safari Pokédex Deployment Script
# Version: 1.0.0
# Description: Advanced deployment orchestration with Blue-Green strategy, parallel processing,
# and automated rollback capabilities

set -euo pipefail
IFS=$'\n\t'

# Global Configuration
readonly NAMESPACE="wildlife-safari"
readonly DEPLOYMENT_TIMEOUT="300s"
readonly HEALTH_CHECK_RETRIES="30"
readonly HEALTH_CHECK_INTERVAL="10"
readonly PARALLEL_DEPLOYMENT_LIMIT="3"
readonly ROLLBACK_TIMEOUT="180s"
readonly LOG_DIR="/var/log/wildlife-safari"
readonly TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Service configurations
declare -A SERVICES=(
    ["auth-service"]="auth-deployment.yaml"
    ["collection-service"]="collection-deployment.yaml"
    ["detection-service"]="detection-deployment.yaml"
)

# Logging setup
setup_logging() {
    mkdir -p "${LOG_DIR}"
    exec 1> >(tee -a "${LOG_DIR}/deploy_${TIMESTAMP}.log")
    exec 2> >(tee -a "${LOG_DIR}/deploy_${TIMESTAMP}.error.log")
}

# Prerequisite checks
check_prerequisites() {
    local required_tools=("kubectl" "aws" "jq")
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            echo -e "${RED}Error: Required tool '$tool' is not installed.${NC}"
            exit 1
        fi
    done

    # Verify kubectl context
    kubectl config current-context || {
        echo -e "${RED}Error: Unable to get kubectl context${NC}"
        exit 1
    }
}

# Health check function
verify_health() {
    local service_name=$1
    local retries=${HEALTH_CHECK_RETRIES}
    local health_status

    echo -e "${YELLOW}Verifying health for ${service_name}...${NC}"

    while [ $retries -gt 0 ]; do
        health_status=$(kubectl get pods -n "${NAMESPACE}" \
            -l app="${service_name}" \
            -o jsonpath='{.items[*].status.containerStatuses[*].ready}' || echo "error")

        if [[ $health_status == *"true"* ]] && ! [[ $health_status == *"false"* ]]; then
            echo -e "${GREEN}Health check passed for ${service_name}${NC}"
            return 0
        fi

        echo -n "."
        sleep "${HEALTH_CHECK_INTERVAL}"
        ((retries--))
    done

    echo -e "${RED}Health check failed for ${service_name}${NC}"
    return 1
}

# Deploy single service
deploy_service() {
    local service_name=$1
    local deployment_file=$2
    local deployment_color=$3
    local current_color

    echo -e "${YELLOW}Deploying ${service_name} (${deployment_color})...${NC}"

    # Determine current deployment color
    current_color=$(kubectl get service "${service_name}" \
        -n "${NAMESPACE}" \
        -o jsonpath='{.metadata.labels.color}' 2>/dev/null || echo "blue")

    # Create new deployment with color suffix
    sed "s/name: ${service_name}/name: ${service_name}-${deployment_color}/g" "${deployment_file}" | \
        kubectl apply -f - -n "${NAMESPACE}"

    # Wait for deployment
    if ! kubectl rollout status deployment/"${service_name}-${deployment_color}" \
        -n "${NAMESPACE}" \
        --timeout="${DEPLOYMENT_TIMEOUT}"; then
        echo -e "${RED}Deployment failed for ${service_name}-${deployment_color}${NC}"
        return 1
    fi

    # Verify health
    if ! verify_health "${service_name}-${deployment_color}"; then
        echo -e "${RED}Health check failed, initiating rollback for ${service_name}${NC}"
        rollback_deployment "${service_name}" "${deployment_color}" "${current_color}"
        return 1
    fi

    # Switch traffic
    switch_traffic "${service_name}" "${deployment_color}"

    # Cleanup old deployment
    cleanup_old_deployment "${service_name}" "${current_color}"

    echo -e "${GREEN}Successfully deployed ${service_name}${NC}"
    return 0
}

# Switch traffic to new deployment
switch_traffic() {
    local service_name=$1
    local new_color=$2

    echo "Switching traffic for ${service_name} to ${new_color} deployment..."
    
    kubectl patch service "${service_name}" \
        -n "${NAMESPACE}" \
        -p "{\"spec\":{\"selector\":{\"app\":\"${service_name}-${new_color}\"}},\"metadata\":{\"labels\":{\"color\":\"${new_color}\"}}}"
}

# Rollback deployment
rollback_deployment() {
    local service_name=$1
    local failed_color=$2
    local previous_color=$3

    echo -e "${YELLOW}Rolling back ${service_name} to ${previous_color}...${NC}"

    # Switch traffic back to previous deployment
    switch_traffic "${service_name}" "${previous_color}"

    # Remove failed deployment
    kubectl delete deployment "${service_name}-${failed_color}" \
        -n "${NAMESPACE}" \
        --timeout="${ROLLBACK_TIMEOUT}" || true

    echo -e "${GREEN}Rollback completed for ${service_name}${NC}"
}

# Cleanup old deployment
cleanup_old_deployment() {
    local service_name=$1
    local old_color=$2

    echo "Cleaning up old deployment ${service_name}-${old_color}..."
    
    kubectl delete deployment "${service_name}-${old_color}" \
        -n "${NAMESPACE}" \
        --timeout="${DEPLOYMENT_TIMEOUT}" || true
}

# Main deployment orchestration
main() {
    local deployment_color
    deployment_color=$([ $(date +%s) -lt $(( $(date +%s -d '1 hour') )) ] && echo "green" || echo "blue")

    setup_logging
    check_prerequisites

    echo "Starting deployment process with color: ${deployment_color}"

    # Deploy services in parallel with limit
    local pids=()
    local service_count=0

    for service_name in "${!SERVICES[@]}"; do
        deploy_service "${service_name}" "${SERVICES[$service_name]}" "${deployment_color}" &
        pids+=($!)
        
        ((service_count++))
        
        if [ $service_count -eq $PARALLEL_DEPLOYMENT_LIMIT ]; then
            for pid in "${pids[@]}"; do
                wait $pid || {
                    echo -e "${RED}Deployment failed for one or more services${NC}"
                    exit 1
                }
            done
            pids=()
            service_count=0
        fi
    done

    # Wait for remaining deployments
    for pid in "${pids[@]}"; do
        wait $pid || {
            echo -e "${RED}Deployment failed for one or more services${NC}"
            exit 1
        }
    done

    echo -e "${GREEN}All deployments completed successfully${NC}"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi