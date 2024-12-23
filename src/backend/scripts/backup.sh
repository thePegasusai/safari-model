#!/bin/bash

# Wildlife Detection Safari Pokédex Backup Script
# Version: 1.0.0
# Dependencies:
# - aws-cli v2.0.0
# - postgresql-client v15
# - gnupg v2.0
# - parallel v20230522

set -euo pipefail

# Global Constants
BACKUP_ROOT="/opt/wildlife-safari/backups"
S3_BUCKET="wildlife-safari-backups"
LOG_DIR="/var/log/wildlife-safari/backups"
RETENTION_DAYS=30
MAX_PARALLEL_UPLOADS=5
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SCRIPT_NAME=$(basename "$0")

# Load environment variables
if [ -f "../.env" ]; then
    # shellcheck source=/dev/null
    source "../.env"
else
    echo "ERROR: Environment file not found!"
    exit 1
fi

# Required environment variables check
required_vars=(
    "DB_HOST" "DB_PORT" "DB_NAME" "DB_USERNAME" "DB_PASSWORD"
    "AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "KMS_KEY_ID"
)

for var in "${required_vars[@]}"; do
    if [ -z "${!var:-}" ]; then
        echo "ERROR: Required environment variable $var is not set!"
        exit 1
    fi
done

# Initialize logging
setup_logging() {
    mkdir -p "$LOG_DIR"
    exec 1> >(tee -a "${LOG_DIR}/${SCRIPT_NAME}_${TIMESTAMP}.log")
    exec 2>&1
    echo "=== Backup Started at $(date) ==="
}

# Cleanup function
cleanup() {
    local exit_code=$?
    echo "Performing cleanup..."
    
    # Remove temporary files
    if [ -d "$TEMP_DIR" ]; then
        find "$TEMP_DIR" -type f -exec shred -u {} \;
        rm -rf "$TEMP_DIR"
    fi
    
    echo "=== Backup Finished at $(date) with exit code $exit_code ==="
    exit "$exit_code"
}

# Initialize backup environment
initialize_backup() {
    echo "Initializing backup environment..."
    
    # Verify running as correct user
    if [ "$(id -u)" != "0" ]; then
        echo "ERROR: This script must be run as root!"
        exit 1
    }
    
    # Create secure temporary directory
    TEMP_DIR=$(mktemp -d)
    chmod 700 "$TEMP_DIR"
    
    # Verify AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        echo "ERROR: AWS credentials verification failed!"
        exit 1
    }
    
    # Set up signal handlers
    trap cleanup EXIT INT TERM
    
    # Create backup directory structure
    BACKUP_DIR="${BACKUP_ROOT}/${TIMESTAMP}"
    mkdir -p "${BACKUP_DIR}"/{db,ml,media}
    
    return 0
}

# Database backup function
backup_database() {
    local backup_dir="$1"
    echo "Starting database backup..."
    
    # Create database backup
    PGPASSWORD="$DB_PASSWORD" pg_dump \
        -h "$DB_HOST" \
        -p "$DB_PORT" \
        -U "$DB_USERNAME" \
        -d "$DB_NAME" \
        -F c \
        -Z 9 \
        -f "${TEMP_DIR}/db_backup.gz"
    
    # Calculate checksum before encryption
    sha256sum "${TEMP_DIR}/db_backup.gz" > "${TEMP_DIR}/db_backup.sha256"
    
    # Encrypt backup
    gpg --batch --yes --symmetric \
        --cipher-algo AES256 \
        --passphrase-file <(echo "$KMS_KEY_ID") \
        --output "${backup_dir}/db/db_backup.gz.gpg" \
        "${TEMP_DIR}/db_backup.gz"
    
    # Upload to S3 with server-side encryption
    aws s3 cp \
        "${backup_dir}/db/db_backup.gz.gpg" \
        "s3://${S3_BUCKET}/db/${TIMESTAMP}/" \
        --sse aws:kms \
        --sse-kms-key-id "$KMS_KEY_ID"
    
    echo "Database backup completed successfully"
    return 0
}

# ML models backup function
backup_ml_models() {
    local backup_dir="$1"
    echo "Starting ML models backup..."
    
    # Create ML models archive
    tar czf "${TEMP_DIR}/ml_models.tar.gz" -C /opt/wildlife-safari/models .
    
    # Encrypt ML models archive
    aws kms encrypt \
        --key-id "$KMS_KEY_ID" \
        --plaintext fileb://"${TEMP_DIR}/ml_models.tar.gz" \
        --output text \
        --query CiphertextBlob \
        --output binary \
        > "${backup_dir}/ml/ml_models.tar.gz.enc"
    
    # Upload to S3
    aws s3 cp \
        "${backup_dir}/ml/ml_models.tar.gz.enc" \
        "s3://${S3_BUCKET}/ml/${TIMESTAMP}/" \
        --sse aws:kms \
        --sse-kms-key-id "$KMS_KEY_ID"
    
    echo "ML models backup completed successfully"
    return 0
}

# Media files backup function
backup_media() {
    local backup_dir="$1"
    echo "Starting media files backup..."
    
    # Create list of files to backup
    find /opt/wildlife-safari/media -type f -print0 > "${TEMP_DIR}/media_files.txt"
    
    # Process files in parallel
    cat "${TEMP_DIR}/media_files.txt" | parallel -0 -j "$MAX_PARALLEL_UPLOADS" \
        "aws s3 cp {} s3://${S3_BUCKET}/media/${TIMESTAMP}/{/.} \
        --sse aws:kms \
        --sse-kms-key-id $KMS_KEY_ID"
    
    echo "Media files backup completed successfully"
    return 0
}

# Backup monitoring function
monitor_backup_health() {
    local backup_type="$1"
    local start_time="$2"
    local end_time
    end_time=$(date +%s)
    
    # Calculate duration
    local duration=$((end_time - start_time))
    
    # Send metrics to CloudWatch
    aws cloudwatch put-metric-data \
        --namespace "WildlifeSafari/Backups" \
        --metric-name "BackupDuration" \
        --value "$duration" \
        --dimensions BackupType="$backup_type"
    
    # Check backup size
    local backup_size
    backup_size=$(aws s3 ls --recursive "s3://${S3_BUCKET}/${backup_type}/${TIMESTAMP}/" \
        | awk '{sum += $3} END {print sum}')
    
    # Send backup report
    local subject="Wildlife Safari Backup Report - ${backup_type} - ${TIMESTAMP}"
    local message="Backup completed:\nType: ${backup_type}\nDuration: ${duration}s\nSize: ${backup_size} bytes"
    echo -e "$message" | mail -s "$subject" "$ALERT_EMAIL"
    
    return 0
}

# Cleanup old backups
cleanup_old_backups() {
    echo "Cleaning up old backups..."
    
    aws s3 ls "s3://${S3_BUCKET}/" | while read -r line; do
        backup_date=$(echo "$line" | awk '{print $2}' | cut -d'/' -f1)
        if [ $(( ($(date +%s) - $(date -d "$backup_date" +%s)) / 86400 )) -gt "$RETENTION_DAYS" ]; then
            aws s3 rm "s3://${S3_BUCKET}/${backup_date}/" --recursive
        fi
    done
}

# Main execution
main() {
    local start_time
    start_time=$(date +%s)
    
    setup_logging
    initialize_backup || exit 1
    
    # Perform backups
    backup_database "$BACKUP_DIR" || exit 1
    monitor_backup_health "database" "$start_time"
    
    backup_ml_models "$BACKUP_DIR" || exit 1
    monitor_backup_health "ml_models" "$start_time"
    
    backup_media "$BACKUP_DIR" || exit 1
    monitor_backup_health "media" "$start_time"
    
    cleanup_old_backups
    
    echo "All backups completed successfully"
    return 0
}

# Execute main function
main "$@"