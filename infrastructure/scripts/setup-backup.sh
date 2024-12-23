#!/bin/bash

# Wildlife Detection Safari Pokédex - Backup Configuration Script
# Version: 1.0.0
# Description: Configures and initializes automated backup procedures across different data stores
# with enhanced support for geo-redundancy and version control

# Exit on any error
set -e

# Import required environment variables
source /etc/wildlife-safari/env.conf

# Global Constants
readonly BACKUP_RETENTION_DAYS=30
readonly BACKUP_S3_PREFIX="backups"
readonly LOG_FILE="/var/log/wildlife-safari/backup.log"
readonly MEDIA_BACKUP_INTERVAL="1h"
readonly MODEL_BACKUP_INTERVAL="24h"
readonly SECONDARY_REGIONS=('eu-west-1' 'ap-southeast-1')

# Logging function
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" | tee -a "$LOG_FILE"
}

# Error handling function
error_handler() {
    local exit_code=$?
    log "ERROR: Command failed with exit code $exit_code"
    log "ERROR: Line number: ${BASH_LINENO[0]}"
    exit $exit_code
}

trap error_handler ERR

# Verify AWS CLI installation and credentials
check_aws_prerequisites() {
    log "Checking AWS prerequisites..."
    
    if ! command -v aws &> /dev/null; then
        log "ERROR: AWS CLI is not installed"
        exit 1
    }

    if ! aws sts get-caller-identity &> /dev/null; then
        log "ERROR: AWS credentials are not properly configured"
        exit 1
    }
}

# Configure RDS automated backups
setup_rds_backup() {
    local db_identifier=$1
    local backup_window=$2
    
    log "Configuring RDS backup for $db_identifier"
    
    # Configure automated snapshots
    aws rds modify-db-instance \
        --db-instance-identifier "$db_identifier" \
        --backup-retention-period $BACKUP_RETENTION_DAYS \
        --preferred-backup-window "$backup_window" \
        --copy-tags-to-snapshot \
        --apply-immediately

    # Enable cross-region snapshot copying for each secondary region
    for region in "${SECONDARY_REGIONS[@]}"; do
        log "Setting up cross-region snapshot copying to $region"
        aws rds modify-db-instance \
            --db-instance-identifier "$db_identifier" \
            --source-region "$(aws configure get region)" \
            --destination-region "$region" \
            --copy-tags-to-snapshot
    done
}

# Configure S3 backup replication
setup_s3_backup() {
    local source_bucket=$1
    local backup_type=$2
    
    log "Configuring S3 backup for $source_bucket ($backup_type)"
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "$source_bucket" \
        --versioning-configuration Status=Enabled

    # Configure lifecycle rules based on backup type
    local retention_period
    if [ "$backup_type" == "media" ]; then
        retention_period=1
    else
        retention_period=24
    fi

    # Create lifecycle rules
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "$source_bucket" \
        --lifecycle-configuration file://<(cat <<EOF
{
    "Rules": [
        {
            "ID": "${backup_type}-backup-lifecycle",
            "Status": "Enabled",
            "Filter": {
                "Prefix": "${BACKUP_S3_PREFIX}/"
            },
            "Transitions": [
                {
                    "Days": 30,
                    "StorageClass": "STANDARD_IA"
                },
                {
                    "Days": 90,
                    "StorageClass": "GLACIER"
                }
            ],
            "NoncurrentVersionExpiration": {
                "NoncurrentDays": $BACKUP_RETENTION_DAYS
            }
        }
    ]
}
EOF
)

    # Configure replication to secondary regions
    for region in "${SECONDARY_REGIONS[@]}"; do
        local destination_bucket="${source_bucket}-replica-${region}"
        
        # Create destination bucket in secondary region
        aws s3api create-bucket \
            --bucket "$destination_bucket" \
            --region "$region" \
            --create-bucket-configuration LocationConstraint="$region"

        # Configure replication
        aws s3api put-bucket-replication \
            --bucket "$source_bucket" \
            --replication-configuration file://<(cat <<EOF
{
    "Role": "${REPLICATION_ROLE_ARN}",
    "Rules": [
        {
            "ID": "${backup_type}-replication-${region}",
            "Status": "Enabled",
            "Priority": 1,
            "DeleteMarkerReplication": { "Status": "Enabled" },
            "Destination": {
                "Bucket": "arn:aws:s3:::${destination_bucket}",
                "StorageClass": "STANDARD_IA"
            }
        }
    ]
}
EOF
)
    done
}

# Configure backup validation and monitoring
setup_backup_monitoring() {
    log "Configuring backup monitoring and validation"

    # Create CloudWatch alarms for backup monitoring
    aws cloudwatch put-metric-alarm \
        --alarm-name "backup-failure-alarm" \
        --alarm-description "Alarm when backup fails" \
        --metric-name "BackupJobsFailedCount" \
        --namespace "AWS/Backup" \
        --statistic Sum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 1 \
        --alarm-actions "${SNS_TOPIC_ARN}"
}

# Main execution
main() {
    log "Starting backup configuration..."

    # Check prerequisites
    check_aws_prerequisites

    # Setup RDS backups
    setup_rds_backup "wildlife-safari-db" "03:00-04:00"

    # Setup S3 backups for media and models
    setup_s3_backup "${MEDIA_BUCKET_ID}" "media"
    setup_s3_backup "${MODELS_BUCKET_ID}" "models"

    # Setup backup monitoring
    setup_backup_monitoring

    log "Backup configuration completed successfully"
}

# Execute main function
main "$@"

# Function to check backup status
check_backup_status() {
    local backup_type=$1
    
    case $backup_type in
        "rds")
            aws rds describe-db-snapshots \
                --db-instance-identifier "wildlife-safari-db" \
                --query 'DBSnapshots[?Status==`available`].[DBSnapshotIdentifier,SnapshotCreateTime]' \
                --output table
            ;;
        "s3")
            aws s3api list-object-versions \
                --bucket "$MEDIA_BUCKET_ID" \
                --prefix "${BACKUP_S3_PREFIX}/" \
                --query 'Versions[?IsLatest==`true`].[Key,LastModified]' \
                --output table
            ;;
    esac
}

# Export functions for external use
export -f check_backup_status