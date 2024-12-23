#!/bin/bash

# Wildlife Detection Safari Pokédex - Disaster Recovery Setup Script
# Version: 1.0
# Last Updated: 2024

set -euo pipefail

# Load AWS CLI version 2.x
export AWS_CLI_VERSION="2.13.0"

# Source environment variables
if [[ -f ".env" ]]; then
    source .env
fi

# Configuration variables
declare -A RPO_THRESHOLDS=(
    ["user_data"]="15"        # 15 minutes RPO for user data
    ["media_files"]="60"      # 1 hour RPO for media files
    ["ml_models"]="1440"      # 24 hours RPO for ML models
)

declare -A RTO_THRESHOLDS=(
    ["user_data"]="60"        # 1 hour RTO for user data
    ["media_files"]="240"     # 4 hours RTO for media files
    ["ml_models"]="120"       # 2 hours RTO for ML models
)

# Logging configuration
LOG_FILE="/var/log/wildlife-safari/dr-setup.log"
CLOUDWATCH_LOG_GROUP="/wildlife-safari/dr-setup"

# Setup logging
setup_logging() {
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    mkdir -p "$(dirname $LOG_FILE)"
    
    # Create CloudWatch log group if it doesn't exist
    aws logs create-log-group --log-group-name "$CLOUDWATCH_LOG_GROUP" 2>/dev/null || true
    
    # Set retention policy
    aws logs put-retention-policy \
        --log-group-name "$CLOUDWATCH_LOG_GROUP" \
        --retention-in-days 90
}

log() {
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local message="$1"
    local level="${2:-INFO}"
    
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
    
    # Send to CloudWatch
    aws logs put-log-events \
        --log-group-name "$CLOUDWATCH_LOG_GROUP" \
        --log-stream-name "$(date +%Y/%m/%d)" \
        --log-events timestamp=$(date +%s%3N),message="[$level] $message"
}

# Error handling
error_handler() {
    local exit_code=$?
    local line_number=$1
    
    log "Error occurred in script at line $line_number" "ERROR"
    
    # Send alert through SNS
    aws sns publish \
        --topic-arn "$SNS_ALERT_TOPIC" \
        --message "DR setup failed at line $line_number with exit code $exit_code" \
        --subject "DR Setup Failure Alert"
        
    exit $exit_code
}

trap 'error_handler ${LINENO}' ERR

# RDS replication setup
setup_rds_replication() {
    local source_db="$1"
    local target_region="$2"
    
    log "Setting up RDS cross-region replication for $source_db to $target_region"
    
    # Create read replica
    aws rds create-db-instance-read-replica \
        --db-instance-identifier "${source_db}-replica" \
        --source-db-instance-identifier "$source_db" \
        --destination-region "$target_region" \
        --auto-minor-version-upgrade \
        --backup-retention-period 7 \
        --monitoring-interval 60 \
        --enable-performance-insights
        
    # Wait for replica to be available
    aws rds wait db-instance-available \
        --db-instance-identifier "${source_db}-replica" \
        --region "$target_region"
        
    # Setup CloudWatch alarms for replication lag
    aws cloudwatch put-metric-alarm \
        --alarm-name "${source_db}-replica-lag" \
        --metric-name ReplicaLag \
        --namespace AWS/RDS \
        --statistic Average \
        --period 300 \
        --evaluation-periods 2 \
        --threshold 300 \
        --comparison-operator GreaterThanThreshold \
        --alarm-actions "$SNS_ALERT_TOPIC" \
        --dimensions Name=DBInstanceIdentifier,Value="${source_db}-replica"
}

# S3 replication setup
setup_s3_replication() {
    local source_bucket="$1"
    local target_region="$2"
    
    log "Setting up S3 cross-region replication for $source_bucket to $target_region"
    
    # Create destination bucket
    aws s3api create-bucket \
        --bucket "${source_bucket}-dr" \
        --region "$target_region" \
        --create-bucket-configuration LocationConstraint="$target_region"
        
    # Enable versioning on both buckets
    aws s3api put-bucket-versioning \
        --bucket "$source_bucket" \
        --versioning-configuration Status=Enabled
        
    aws s3api put-bucket-versioning \
        --bucket "${source_bucket}-dr" \
        --versioning-configuration Status=Enabled
        
    # Setup replication
    aws s3api put-bucket-replication \
        --bucket "$source_bucket" \
        --replication-configuration file://configs/s3-replication.json
        
    # Setup lifecycle policies
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "$source_bucket" \
        --lifecycle-configuration file://configs/s3-lifecycle.json
}

# EKS DR setup
setup_eks_dr() {
    local primary_cluster="$1"
    local dr_region="$2"
    
    log "Setting up EKS disaster recovery for $primary_cluster in $dr_region"
    
    # Create DR cluster
    eksctl create cluster \
        --name "${primary_cluster}-dr" \
        --region "$dr_region" \
        --version 1.27 \
        --nodes-min 3 \
        --nodes-max 10 \
        --node-type c5.2xlarge
        
    # Setup cluster autoscaling
    kubectl apply -f configs/cluster-autoscaler.yaml
    
    # Setup cross-region secret replication
    kubectl apply -f configs/secret-replication.yaml
    
    # Configure Route53 DNS failover
    aws route53 create-health-check \
        --caller-reference "$(date +%s)" \
        --health-check-config file://configs/route53-health-check.json
}

# Validation functions
validate_replication_status() {
    local component="$1"
    local source_region="$2"
    local target_region="$3"
    
    log "Validating replication status for $component"
    
    case "$component" in
        "rds")
            # Check RDS replication lag
            local lag=$(aws rds describe-db-instances \
                --db-instance-identifier "${DB_INSTANCE}-replica" \
                --region "$target_region" \
                --query 'DBInstances[0].ReplicaLag' \
                --output text)
            
            if [[ $lag -gt ${RPO_THRESHOLDS["user_data"]} ]]; then
                log "RDS replication lag ($lag minutes) exceeds RPO threshold" "WARNING"
                return 1
            fi
            ;;
            
        "s3")
            # Check S3 replication metrics
            aws s3api get-bucket-metrics-configuration \
                --bucket "$MEDIA_BUCKET" \
                --id replication
            ;;
    esac
}

# Main execution
main() {
    log "Starting disaster recovery setup"
    
    # Setup logging
    setup_logging
    
    # Setup RDS replication
    setup_rds_replication "$DB_INSTANCE" "$DR_REGION"
    
    # Setup S3 replication for media files
    setup_s3_replication "$MEDIA_BUCKET" "$DR_REGION"
    
    # Setup EKS DR
    setup_eks_dr "$EKS_CLUSTER" "$DR_REGION"
    
    # Validate setup
    validate_replication_status "rds" "$PRIMARY_REGION" "$DR_REGION"
    validate_replication_status "s3" "$PRIMARY_REGION" "$DR_REGION"
    
    log "Disaster recovery setup completed successfully"
}

# Execute main function
main "$@"