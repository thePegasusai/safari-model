#!/bin/bash

# Wildlife Detection Safari Pokédex - Terraform Apply Script
# Version: 1.0.0
# Required: aws-cli 2.x, terraform 1.0+
# Purpose: Securely apply Terraform infrastructure changes with validation and health checks

set -euo pipefail

# Source initialization functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/init-terraform.sh"

# Global variables
readonly VALID_ENVIRONMENTS=("dev" "staging" "prod")
readonly AWS_REGION=${AWS_REGION:-"us-west-2"}
readonly PLAN_FILE=${PLAN_FILE:-"terraform.plan"}
readonly LOG_FILE=${LOG_FILE:-"terraform-apply.log"}
readonly BACKUP_DIR=${BACKUP_DIR:-"./terraform-backups"}
readonly HEALTH_CHECK_TIMEOUT=${HEALTH_CHECK_TIMEOUT:-300}
readonly MAX_RETRIES=${MAX_RETRIES:-3}
readonly TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Setup logging
setup_logging() {
    local environment=$1
    mkdir -p "$(dirname "${LOG_FILE}")"
    exec 1> >(tee -a "${LOG_FILE}")
    exec 2> >(tee -a "${LOG_FILE}")
    log "INFO" "Starting Terraform apply for environment: ${environment}"
}

log() {
    local level=$1
    local message=$2
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [${level}] ${message}"
}

# Validate environment and permissions
validate_environment() {
    local environment=$1
    
    # Check if environment is valid
    if [[ ! " ${VALID_ENVIRONMENTS[@]} " =~ " ${environment} " ]]; then
        log "ERROR" "Invalid environment: ${environment}. Must be one of: ${VALID_ENVIRONMENTS[*]}"
        return 1
    }

    # Validate environment configuration
    local config_file="${SCRIPT_DIR}/../terraform/environments/${environment}/main.tf"
    if [[ ! -f "${config_file}" ]]; then
        log "ERROR" "Environment configuration not found: ${config_file}"
        return 1
    }

    # Additional production safeguards
    if [[ "${environment}" == "prod" ]]; then
        # Verify multi-party authorization
        if [[ -z "${APPROVED_BY:-}" ]]; then
            log "ERROR" "Production deployments require approval (set APPROVED_BY)"
            return 1
        }
        
        # Verify maintenance window
        if ! check_maintenance_window; then
            log "ERROR" "Outside approved production maintenance window"
            return 1
        }
    }

    return 0
}

# Create state backup
backup_terraform_state() {
    local environment=$1
    local backup_path="${BACKUP_DIR}/${environment}/${TIMESTAMP}"
    
    log "INFO" "Creating state backup at: ${backup_path}"
    
    mkdir -p "${backup_path}"
    
    # Copy state files
    terraform state pull > "${backup_path}/terraform.tfstate"
    
    # Verify backup
    if [[ ! -s "${backup_path}/terraform.tfstate" ]]; then
        log "ERROR" "State backup failed or empty"
        return 1
    }
    
    # Upload to S3 backup bucket
    aws s3 cp "${backup_path}/terraform.tfstate" \
        "s3://wildlife-safari-terraform-backup-${environment}/${TIMESTAMP}/terraform.tfstate" \
        --sse AES256

    log "INFO" "State backup completed successfully"
    return 0
}

# Generate and validate Terraform plan
generate_plan() {
    local environment=$1
    
    log "INFO" "Generating Terraform plan for environment: ${environment}"
    
    # Initialize Terraform if needed
    if ! initialize_terraform_backend "${environment}" "${AWS_REGION}"; then
        log "ERROR" "Terraform initialization failed"
        return 1
    }

    # Run security scan on configuration
    if ! security_scan "${environment}"; then
        log "ERROR" "Security policy validation failed"
        return 1
    }

    # Generate plan
    if ! terraform plan \
        -detailed-exitcode \
        -input=false \
        -out="${PLAN_FILE}" \
        -var-file="../terraform/environments/${environment}/terraform.tfvars"; then
        log "ERROR" "Terraform plan generation failed"
        return 1
    }

    # Validate plan for sensitive changes
    if ! validate_plan_safety "${PLAN_FILE}"; then
        log "ERROR" "Plan contains unsafe changes"
        return 1
    }

    log "INFO" "Plan generated successfully: ${PLAN_FILE}"
    return 0
}

# Apply Terraform changes
apply_changes() {
    local environment=$1
    local retries=0
    
    log "INFO" "Applying Terraform changes for environment: ${environment}"
    
    # Verify plan file exists
    if [[ ! -f "${PLAN_FILE}" ]]; then
        log "ERROR" "Plan file not found: ${PLAN_FILE}"
        return 1
    }

    # Create state backup
    if ! backup_terraform_state "${environment}"; then
        log "ERROR" "State backup failed"
        return 1
    }

    # Apply changes with retry logic
    while [[ ${retries} -lt ${MAX_RETRIES} ]]; do
        if terraform apply \
            -input=false \
            -auto-approve \
            "${PLAN_FILE}"; then
            
            # Perform health checks
            if perform_health_check "${environment}"; then
                log "INFO" "Changes applied successfully"
                return 0
            else
                log "ERROR" "Health check failed after apply"
                if [[ ${retries} -lt $((MAX_RETRIES-1)) ]]; then
                    log "INFO" "Attempting rollback and retry"
                    rollback_changes "${environment}"
                fi
            fi
        fi
        
        retries=$((retries+1))
        log "WARN" "Apply failed, attempt ${retries}/${MAX_RETRIES}"
    done

    log "ERROR" "Failed to apply changes after ${MAX_RETRIES} attempts"
    return 1
}

# Perform health checks
perform_health_check() {
    local environment=$1
    local timeout=${HEALTH_CHECK_TIMEOUT}
    local start_time=$(date +%s)
    
    log "INFO" "Performing health checks for environment: ${environment}"
    
    while true; do
        local current_time=$(date +%s)
        if [[ $((current_time - start_time)) -gt ${timeout} ]]; then
            log "ERROR" "Health check timed out after ${timeout} seconds"
            return 1
        fi

        # Core infrastructure checks
        if ! check_core_services "${environment}"; then
            continue
        fi

        # Network connectivity checks
        if ! check_network_connectivity "${environment}"; then
            continue
        fi

        # Security group validation
        if ! validate_security_groups "${environment}"; then
            continue
        fi

        # Load balancer health
        if ! check_load_balancers "${environment}"; then
            continue
        fi

        # Database connectivity
        if ! check_database_connectivity "${environment}"; then
            continue
        fi

        log "INFO" "All health checks passed successfully"
        return 0
    done
}

# Main execution
main() {
    if [[ $# -ne 1 ]]; then
        log "ERROR" "Usage: $0 <environment>"
        exit 1
    }

    local environment=$1
    
    # Setup logging
    setup_logging "${environment}"
    
    # Validate environment and permissions
    if ! validate_environment "${environment}"; then
        exit 1
    }

    # Generate and validate plan
    if ! generate_plan "${environment}"; then
        exit 2
    }

    # Apply changes
    if ! apply_changes "${environment}"; then
        log "ERROR" "Failed to apply changes, check logs for details"
        exit 3
    }

    log "INFO" "Infrastructure changes completed successfully"
    exit 0
}

# Execute main function
main "$@"
```

This script provides a comprehensive implementation for applying Terraform changes with:

1. Robust environment validation and security controls
2. State backup before applying changes
3. Plan generation with security validation
4. Retry logic for resilient deployments
5. Comprehensive health checks
6. Production safeguards including approval requirements
7. Detailed logging and error handling
8. Rollback capabilities on failure

The script follows infrastructure deployment best practices:
- Uses secure backend initialization from init-terraform.sh
- Implements comprehensive validation and health checks
- Provides proper error handling and logging
- Includes production-specific safeguards
- Supports multiple environments with appropriate controls
- Maintains audit trail of all operations

Usage:
```bash
# Make script executable
chmod +x apply-terraform.sh

# Run for specific environment
./apply-terraform.sh dev
./apply-terraform.sh staging
APPROVED_BY="username" ./apply-terraform.sh prod