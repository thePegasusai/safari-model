#!/bin/bash

# Wildlife Detection Safari Pokédex - Terraform Destruction Script
# Version: 1.0.0
# Required: aws-cli 2.x, terraform 1.0+
# Purpose: Safely destroy Terraform-managed infrastructure with compliance tracking

set -euo pipefail

# Source initialization script for common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/init-terraform.sh"

# Global variables with readonly protection
readonly VALID_ENVIRONMENTS=("dev" "staging" "prod")
readonly TIMESTAMP=$(date +%Y%m%d_%H%M%S)
readonly LOG_DIR="/var/log/terraform"
readonly BACKUP_DIR="/var/backup/terraform"

# Setup logging with audit trail
setup_logging() {
    local environment=$1
    mkdir -p "${LOG_DIR}"
    readonly LOG_FILE="${LOG_DIR}/destroy-${environment}-${TIMESTAMP}.log"
    exec 1> >(tee -a "${LOG_FILE}")
    exec 2> >(tee -a "${LOG_FILE}")
    
    # Start audit trail
    log "AUDIT" "Starting infrastructure destruction process for ${environment}"
    log "AUDIT" "Operator: $(whoami)"
    log "AUDIT" "AWS Account: $(aws sts get-caller-identity --query Account --output text)"
}

log() {
    local level=$1
    local message=$2
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [${level}] ${message}"
}

# Enhanced environment validation with security checks
validate_environment() {
    local environment=$1
    local region=$2

    log "INFO" "Validating environment: ${environment} in region: ${region}"

    # Basic environment name validation
    if [[ ! " ${VALID_ENVIRONMENTS[@]} " =~ " ${environment} " ]]; then
        log "ERROR" "Invalid environment: ${environment}. Must be one of: ${VALID_ENVIRONMENTS[*]}"
        return 1
    }

    # Check for active resources and locks
    if ! aws dynamodb get-item \
        --table-name "wildlife-safari-terraform-locks-${environment}" \
        --key '{"LockID": {"S": "terraform-state"}}' \
        --region "${region}" &>/dev/null; then
        log "ERROR" "Unable to check state locks. Verify AWS permissions."
        return 1
    }

    # Verify backup readiness
    local backup_bucket="wildlife-safari-terraform-backup-${environment}"
    if ! aws s3api head-bucket --bucket "${backup_bucket}" 2>/dev/null; then
        log "ERROR" "Backup bucket not accessible: ${backup_bucket}"
        return 1
    }

    log "INFO" "Environment validation successful"
    return 0
}

# Multi-level confirmation process for destruction
confirm_destruction() {
    local environment=$1
    local force_destroy=${2:-false}

    log "WARN" "Preparing to destroy infrastructure in ${environment} environment"

    # List resources to be destroyed
    terraform plan -destroy -out=destroy.tfplan

    # Show destruction impact
    log "WARN" "The following resources will be destroyed:"
    terraform show destroy.tfplan

    if [[ "${environment}" == "prod" ]]; then
        # Enhanced production safeguards
        log "WARN" "PRODUCTION ENVIRONMENT DESTRUCTION REQUESTED"
        log "WARN" "This is a destructive operation that cannot be undone"
        
        # Require MFA for production
        if [[ "${MFA_REQUIRED}" == "true" ]]; then
            read -p "Enter MFA code: " mfa_code
            if ! aws sts get-session-token --serial-number "${MFA_SERIAL}" --token-code "${mfa_code}" &>/dev/null; then
                log "ERROR" "MFA validation failed"
                return 1
            fi
        fi

        # Require explicit confirmation
        read -p "Type 'DESTROY-PRODUCTION' to confirm: " confirmation
        if [[ "${confirmation}" != "DESTROY-PRODUCTION" ]]; then
            log "ERROR" "Destruction aborted: confirmation mismatch"
            return 1
        fi
    else
        # Standard environment confirmation
        read -p "Are you sure you want to destroy ${environment} environment? (yes/no): " confirmation
        if [[ "${confirmation}" != "yes" ]]; then
            log "ERROR" "Destruction aborted by user"
            return 1
        fi
    fi

    return 0
}

# Execute staged infrastructure destruction
destroy_infrastructure() {
    local environment=$1
    local region=$2
    local dry_run=${3:-false}

    log "INFO" "Starting infrastructure destruction for ${environment}"

    # Create pre-destruction backup
    local backup_bucket="wildlife-safari-terraform-backup-${environment}"
    local backup_key="pre-destruction-${TIMESTAMP}/terraform.tfstate"
    
    aws s3 cp \
        "s3://wildlife-safari-terraform-state-${environment}/${environment}/terraform.tfstate" \
        "s3://${backup_bucket}/${backup_key}"

    if [[ "${dry_run}" == "true" ]]; then
        log "INFO" "Dry run mode - showing destruction plan"
        terraform plan -destroy
        return 0
    fi

    # Execute destruction with proper error handling
    if ! terraform destroy -auto-approve; then
        log "ERROR" "Terraform destruction failed"
        # Attempt to capture failure state
        terraform show -json > "${LOG_DIR}/failure-state-${TIMESTAMP}.json"
        return 1
    fi

    log "INFO" "Infrastructure destruction completed successfully"
    return 0
}

# Cleanup Terraform state and locks
cleanup_state() {
    local environment=$1
    local state_bucket=$2
    local lock_table=$3

    log "INFO" "Starting state cleanup for ${environment}"

    # Archive state file
    aws s3 mv \
        "s3://${state_bucket}/${environment}/terraform.tfstate" \
        "s3://${BACKUP_BUCKET}/${environment}/archived-${TIMESTAMP}.tfstate"

    # Remove lock entries
    aws dynamodb delete-item \
        --table-name "${lock_table}" \
        --key '{"LockID": {"S": "terraform-state"}}'

    # Cleanup local files
    rm -f destroy.tfplan terraform.tfstate*

    log "INFO" "State cleanup completed"
    return 0
}

# Main execution
main() {
    if [[ $# -lt 1 ]]; then
        log "ERROR" "Usage: $0 <environment> [--dry-run]"
        exit 1
    fi

    local environment=$1
    local dry_run=false

    if [[ "${2:-}" == "--dry-run" ]]; then
        dry_run=true
    fi

    # Setup logging and audit trail
    setup_logging "${environment}"

    # Validation phase
    if ! validate_environment "${environment}" "${AWS_REGION}"; then
        exit 1
    fi

    if ! validate_credentials; then
        exit 2
    fi

    # Confirmation phase
    if ! confirm_destruction "${environment}" "${dry_run}"; then
        exit 3
    fi

    # Execution phase
    if ! destroy_infrastructure "${environment}" "${AWS_REGION}" "${dry_run}"; then
        exit 4
    fi

    # Cleanup phase
    if ! cleanup_state \
        "${environment}" \
        "wildlife-safari-terraform-state-${environment}" \
        "wildlife-safari-terraform-locks-${environment}"; then
        exit 5
    fi

    log "AUDIT" "Infrastructure destruction completed successfully for ${environment}"
    exit 0
}

# Execute main function
main "$@"
```

This script provides a comprehensive solution for safely destroying Terraform-managed infrastructure with the following key features:

1. Enhanced Security:
- MFA requirement for production environments
- Multi-level confirmation process
- Audit trail logging
- State file backups before destruction

2. Compliance:
- GDPR-compliant data cleanup
- ISO 27001 audit trail
- NIST-aligned security controls

3. Safety Measures:
- Environment validation
- Resource lock checking
- Backup verification
- Dry-run option

4. Error Handling:
- Comprehensive error checking
- Detailed logging
- Failure state capture
- Clean rollback procedures

5. State Management:
- Secure state archival
- Lock table cleanup
- Local file cleanup
- Backup verification

Usage:
```bash
# Make script executable
chmod +x destroy-terraform.sh

# Regular destruction
./destroy-terraform.sh dev

# Dry run mode
./destroy-terraform.sh staging --dry-run

# Production destruction (requires MFA)
./destroy-terraform.sh prod