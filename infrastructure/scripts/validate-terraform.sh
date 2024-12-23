#!/bin/bash

# validate-terraform.sh
# Validates Terraform configurations across all environments with security compliance checks
# Version: 1.0.0
# Dependencies:
# - terraform ~> 1.0
# - tflint latest
# - gnu-parallel latest
# - jq latest

# Set strict error handling
set -e
set -u
set -o pipefail

# Global variables
TERRAFORM_DIRS=(
    "../terraform/aws"
    "../terraform/environments/dev"
    "../terraform/environments/staging"
    "../terraform/environments/prod"
)
EXIT_CODE=0
PARALLEL_JOBS=4
TEMP_DIR=$(mktemp -d)
LOG_FILE="${TEMP_DIR}/validation.log"

# Error handling and cleanup
error_handler() {
    local line_no=$1
    echo "Error occurred in script at line: ${line_no}" | tee -a "${LOG_FILE}"
    exit 1
}

cleanup() {
    local exit_code=$?
    echo "Cleaning up temporary resources..." | tee -a "${LOG_FILE}"
    rm -rf "${TEMP_DIR}"
    exit ${exit_code}
}

trap 'error_handler ${LINENO}' ERR
trap cleanup EXIT

# Logging function with security context
log() {
    local level=$1
    local message=$2
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    jq -n \
        --arg timestamp "${timestamp}" \
        --arg level "${level}" \
        --arg message "${message}" \
        '{timestamp: $timestamp, level: $level, message: $message}' \
        | tee -a "${LOG_FILE}"
}

# Version checking function
check_terraform_version() {
    log "INFO" "Checking required tool versions..."
    
    # Check Terraform version
    if ! terraform version >/dev/null 2>&1; then
        log "ERROR" "Terraform is not installed"
        return 1
    fi
    
    local tf_version
    tf_version=$(terraform version -json | jq -r '.terraform_version')
    if [[ ! "${tf_version}" =~ ^1\. ]]; then
        log "ERROR" "Terraform version must be 1.x, found: ${tf_version}"
        return 1
    fi
    
    # Check tflint
    if ! tflint --version >/dev/null 2>&1; then
        log "ERROR" "tflint is not installed"
        return 1
    }
    
    # Check parallel
    if ! parallel --version >/dev/null 2>&1; then
        log "ERROR" "GNU parallel is not installed"
        return 1
    }
    
    # Check jq
    if ! jq --version >/dev/null 2>&1; then
        log "ERROR" "jq is not installed"
        return 1
    }
    
    # Verify security policy file
    if [[ ! -f "../config/security/policies.json" ]]; then
        log "ERROR" "Security policies file not found"
        return 1
    }
    
    return 0
}

# Validate single Terraform directory
validate_terraform_dir() {
    local dir_path=$1
    local environment=$2
    local validation_output="${TEMP_DIR}/${environment}_validation.json"
    local exit_status=0
    
    log "INFO" "Validating directory: ${dir_path} (${environment})"
    
    # Create temporary directory for this validation
    local temp_work_dir
    temp_work_dir=$(mktemp -d)
    cd "${dir_path}" || exit 1
    
    # Initialize Terraform with plugin caching
    if ! terraform init -backend=false -input=false > "${temp_work_dir}/init.log" 2>&1; then
        log "ERROR" "Terraform init failed in ${dir_path}"
        exit_status=1
    fi
    
    # Check formatting
    if ! terraform fmt -check -recursive > "${temp_work_dir}/fmt.log" 2>&1; then
        log "WARNING" "Terraform formatting issues found in ${dir_path}"
        exit_status=1
    fi
    
    # Validate configuration
    if ! terraform validate -json > "${temp_work_dir}/validate.json" 2>&1; then
        log "ERROR" "Terraform validation failed in ${dir_path}"
        exit_status=1
    fi
    
    # Run tflint with security rules
    if ! tflint --format json \
        --config="../config/security/policies.json" \
        > "${temp_work_dir}/tflint.json" 2>&1; then
        log "ERROR" "tflint security validation failed in ${dir_path}"
        exit_status=1
    fi
    
    # Aggregate results
    jq -s '{ 
        environment: $env,
        path: $path,
        validation_results: {
            terraform: .[0],
            tflint: .[1]
        },
        timestamp: $timestamp
    }' \
        --arg env "${environment}" \
        --arg path "${dir_path}" \
        --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        "${temp_work_dir}/validate.json" \
        "${temp_work_dir}/tflint.json" \
        > "${validation_output}"
    
    # Cleanup temporary directory
    rm -rf "${temp_work_dir}"
    
    return ${exit_status}
}

# Generate security validation report
generate_security_report() {
    local report_file="${TEMP_DIR}/security_report.json"
    local validation_files=("${TEMP_DIR}"/*_validation.json)
    
    log "INFO" "Generating security validation report..."
    
    # Aggregate all validation results
    jq -s '{
        summary: {
            total_environments: length,
            passed: map(select(.validation_results.terraform.valid and .validation_results.tflint.errors == 0)) | length,
            failed: map(select(.validation_results.terraform.valid == false or .validation_results.tflint.errors > 0)) | length
        },
        environments: .
    }' "${validation_files[@]}" > "${report_file}"
    
    # Generate human-readable summary
    {
        echo "Security Validation Report"
        echo "========================="
        echo ""
        jq -r '.summary | "Total Environments: \(.total_environments)\nPassed: \(.passed)\nFailed: \(.failed)"' "${report_file}"
        echo ""
        echo "Detailed Results:"
        jq -r '.environments[] | "Environment: \(.environment)\nPath: \(.path)\nStatus: \(if .validation_results.terraform.valid and .validation_results.tflint.errors == 0 then "PASSED" else "FAILED" end)\n"' "${report_file}"
    } > "${TEMP_DIR}/security_report.txt"
    
    return 0
}

# Main execution
main() {
    log "INFO" "Starting Terraform validation with security checks..."
    
    # Check required tools
    if ! check_terraform_version; then
        log "ERROR" "Tool version check failed"
        exit 1
    fi
    
    # Create working directory structure
    mkdir -p "${TEMP_DIR}"
    
    # Parallel process validation across directories
    export -f validate_terraform_dir
    export -f log
    
    parallel --jobs "${PARALLEL_JOBS}" \
        validate_terraform_dir {1} {2} ::: \
        "${TERRAFORM_DIRS[@]}" ::: \
        "dev" "staging" "prod" \
        || EXIT_CODE=1
    
    # Generate final report
    if ! generate_security_report; then
        log "ERROR" "Failed to generate security report"
        EXIT_CODE=1
    fi
    
    # Output results
    if [[ ${EXIT_CODE} -eq 0 ]]; then
        log "INFO" "Terraform validation completed successfully"
    else
        log "ERROR" "Terraform validation failed"
    fi
    
    return ${EXIT_CODE}
}

# Execute main function
main "$@"