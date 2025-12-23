#!/bin/bash

# Comprehensive backup script for MERN App DevOps
# Usage: ./scripts/backup.sh [environment] [backup-type] [options]

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENVIRONMENT="${1:-prod}"
BACKUP_TYPE="${2:-full}" # full, database, files, configs
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="${PROJECT_ROOT}/backups/${ENVIRONMENT}/${TIMESTAMP}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Backup tracking
BACKUP_SIZE=0
FILES_BACKED_UP=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Usage information
usage() {
    cat << EOF
Usage: $0 [ENVIRONMENT] [BACKUP-TYPE] [OPTIONS]

Environments:
  dev         Backup development environment
  staging     Backup staging environment
  prod        Backup production environment (default)

Backup Types:
  full        Full backup (database + files + configs)
  database    MongoDB database only
  files       Application files and logs only
  configs     Configuration files only

Options:
  --s3         Upload backup to S3
  --encrypt    Encrypt backup files
  --compress   Compress backup files
  --retention  Set retention days (default: 30)
  --help       Show this help message

Examples:
  $0 prod full --s3 --encrypt
  $0 staging database --compress
  $0 dev configs

EOF
}

# Create backup directory structure
create_backup_structure() {
    log_info "Creating backup directory structure..."
    
    mkdir -p "${BACKUP_DIR}"/{database,files,configs,logs,metadata}
    
    # Create metadata file
    cat > "${BACKUP_DIR}/metadata/backup-info.json" << EOF
{
    "environment": "${ENVIRONMENT}",
    "backup_type": "${BACKUP_TYPE}",
    "timestamp": "${TIMESTAMP}",
    "hostname": "$(hostname)",
    "user": "$(whoami)",
    "script_version": "1.0"
}
EOF
    
    log_success "Backup directory structure created: ${BACKUP_DIR}"
}

# Backup Kubernetes configurations
backup_k8s_configs() {
    log_info "Backing up Kubernetes configurations..."
    
    local namespace="mern-app-${ENVIRONMENT}"
    local k8s_backup_dir="${BACKUP_DIR}/configs/kubernetes"
    mkdir -p "$k8s_backup_dir"
    
    # Backup all resources in namespace
    kubectl get all -n "$namespace" -o yaml > "${k8s_backup_dir}/all-resources.yaml" || {
        log_warning "Failed to backup Kubernetes resources"
        return 1
    }
    
    # Backup specific resource types
    local resource_types=("deployments" "services" "configmaps" "secrets" "pvc" "ingress" "networkpolicies" "serviceaccounts" "roles" "rolebindings")
    
    for resource_type in "${resource_types[@]}"; do
        if kubectl get "$resource_type" -n "$namespace" &> /dev/null; then
            kubectl get "$resource_type" -n "$namespace" -o yaml > "${k8s_backup_dir}/${resource_type}.yaml" || {
                log_warning "Failed to backup $resource_type"
            }
        fi
    done
    
    log_success "Kubernetes configurations backed up"
}

# Backup Terraform configurations
backup_terraform_configs() {
    log_info "Backing up Terraform configurations..."
    
    local tf_backup_dir="${BACKUP_DIR}/configs/terraform"
    mkdir -p "$tf_backup_dir"
    
    # Copy terraform directory
    cp -r "${PROJECT_ROOT}/terraform/"* "$tf_backup_dir/" || {
        log_warning "Failed to backup Terraform configurations"
        return 1
    }
    
    # Save current Terraform state (if accessible)
    if command -v terraform &> /dev/null; then
        cd "${PROJECT_ROOT}/terraform/envs/${ENVIRONMENT}"
        terraform state pull > "${tf_backup_dir}/terraform-state.json" 2>/dev/null || {
            log_warning "Failed to backup Terraform state"
        }
    fi
    
    log_success "Terraform configurations backed up"
}

# Backup Ansible configurations
backup_ansible_configs() {
    log_info "Backing up Ansible configurations..."
    
    local ansible_backup_dir="${BACKUP_DIR}/configs/ansible"
    mkdir -p "$ansible_backup_dir"
    
    # Copy ansible directory
    cp -r "${PROJECT_ROOT}/ansible/"* "$ansible_backup_dir/" || {
        log_warning "Failed to backup Ansible configurations"
        return 1
    }
    
    log_success "Ansible configurations backed up"
}

# Backup application code and configs
backup_application_files() {
    log_info "Backing up application files..."
    
    local app_backup_dir="${BACKUP_DIR}/files/application"
    mkdir -p "$app_backup_dir"
    
    # Copy application source code
    local app_dirs=(
        "${PROJECT_ROOT}/ansible/roles/webserver/files/app"
        "${PROJECT_ROOT}/ansible/roles/webserver/files/app/client"
    )
    
    for app_dir in "${app_dirs[@]}"; do
        if [ -d "$app_dir" ]; then
            cp -r "$app_dir" "${app_backup_dir}/" || {
                log_warning "Failed to backup $app_dir"
            }
        fi
    done
    
    # Copy Dockerfiles and docker configs
    if [ -f "${PROJECT_ROOT}/ansible/roles/webserver/files/Dockerfile" ]; then
        cp "${PROJECT_ROOT}/ansible/roles/webserver/files/Dockerfile" "${app_backup_dir}/"
    fi
    
    # Copy monitoring configs
    if [ -d "${PROJECT_ROOT}/monitoring" ]; then
        cp -r "${PROJECT_ROOT}/monitoring" "${app_backup_dir}/"
    fi
    
    # Copy scripts
    if [ -d "${PROJECT_ROOT}/scripts" ]; then
        cp -r "${PROJECT_ROOT}/scripts" "${app_backup_dir}/"
    fi
    
    log_success "Application files backed up"
}

# Backup MongoDB database
backup_mongodb() {
    log_info "Backing up MongoDB database..."
    
    local namespace="mern-app-${ENVIRONMENT}"
    local db_backup_dir="${BACKUP_DIR}/database"
    mkdir -p "$db_backup_dir"
    
    # Get MongoDB pod
    local mongo_pod=$(kubectl get pods -n "$namespace" -l app=mongo -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -z "$mongo_pod" ]; then
        log_error "No MongoDB pod found"
        return 1
    fi
    
    # Create database dump
    log_info "Creating MongoDB dump..."
    if kubectl exec -n "$namespace" "$mongo_pod" -- mongodump --out /tmp/backup &> /dev/null; then
        # Copy dump from pod
        kubectl cp "${namespace}/${mongo_pod}:/tmp/backup" "${db_backup_dir}/mongodb-dump"
        
        # Create compressed archive
        cd "${db_backup_dir}"
        tar -czf "mongodb-backup-${TIMESTAMP}.tar.gz" mongodb-dump
        rm -rf mongodb-dump
        
        log_success "MongoDB backup completed"
    else
        log_error "Failed to create MongoDB backup"
        return 1
    fi
}

# Backup Kubernetes secrets (encrypted)
backup_secrets() {
    log_info "Backing up Kubernetes secrets..."
    
    local namespace="mern-app-${ENVIRONMENT}"
    local secrets_backup_dir="${BACKUP_DIR}/configs/kubernetes/secrets"
    mkdir -p "$secrets_backup_dir"
    
    # Get all secrets
    local secrets=$(kubectl get secrets -n "$namespace" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    
    if [ -n "$secrets" ]; then
        for secret in $secrets; do
            # Export secret data
            kubectl get secret "$secret" -n "$namespace" -o yaml > "${secrets_backup_dir}/${secret}.yaml" || {
                log_warning "Failed to backup secret: $secret"
            }
        done
        
        log_success "Kubernetes secrets backed up"
    else
        log_info "No secrets found to backup"
    fi
}

# Backup application logs
backup_logs() {
    log_info "Backing up application logs..."
    
    local namespace="mern-app-${ENVIRONMENT}"
    local logs_backup_dir="${BACKUP_DIR}/logs"
    mkdir -p "$logs_backup_dir"
    
    # Get recent pod logs
    local pods=$(kubectl get pods -n "$namespace" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    
    if [ -n "$pods" ]; then
        for pod in $pods; do
            log_info "Backing up logs for pod: $pod"
            kubectl logs "$pod" -n "$namespace" --tail=1000 > "${logs_backup_dir}/${pod}-logs.txt" 2>/dev/null || {
                log_warning "Failed to backup logs for pod: $pod"
            }
        done
        
        log_success "Application logs backed up"
    else
        log_info "No pods found for log backup"
    fi
}

# Compress backup
compress_backup() {
    log_info "Compressing backup..."
    
    cd "${BACKUP_DIR}/.."
    tar -czf "mern-app-backup-${ENVIRONMENT}-${TIMESTAMP}.tar.gz" "${TIMESTAMP}/"
    
    # Calculate backup size
    local compressed_size=$(du -h "mern-app-backup-${ENVIRONMENT}-${TIMESTAMP}.tar.gz" | cut -f1)
    log_success "Backup compressed: ${compressed_size}"
    
    # Clean up uncompressed directory
    rm -rf "${TIMESTAMP}/"
}

# Encrypt backup
encrypt_backup() {
    log_info "Encrypting backup..."
    
    local backup_file="${BACKUP_DIR}/../mern-app-backup-${ENVIRONMENT}-${TIMESTAMP}.tar.gz"
    local encrypted_file="${backup_file}.enc"
    
    # Use GPG for encryption
    if command -v gpg &> /dev/null; then
        gpg --cipher-algo AES256 --compress-algo 1 --symmetric --output "$encrypted_file" "$backup_file" || {
            log_error "Failed to encrypt backup"
            return 1
        }
        
        # Remove unencrypted file
        rm "$backup_file"
        
        log_success "Backup encrypted successfully"
    else
        log_warning "GPG not available, skipping encryption"
    fi
}

# Upload to S3
upload_to_s3() {
    log_info "Uploading backup to S3..."
    
    local bucket_name="${S3_BACKUP_BUCKET:-mern-app-backups}"
    local backup_file="${BACKUP_DIR}/../mern-app-backup-${ENVIRONMENT}-${TIMESTAMP}.tar.gz"
    
    if command -v aws &> /dev/null; then
        # Determine file to upload
        local file_to_upload="$backup_file"
        if [ -f "${backup_file}.enc" ]; then
            file_to_upload="${backup_file}.enc"
        fi
        
        # Upload to S3
        aws s3 cp "$file_to_upload" "s3://${bucket_name}/backups/${ENVIRONMENT}/" || {
            log_error "Failed to upload backup to S3"
            return 1
        }
        
        log_success "Backup uploaded to S3: s3://${bucket_name}/backups/${ENVIRONMENT}/"
    else
        log_error "AWS CLI not available for S3 upload"
        return 1
    fi
}

# Cleanup old backups
cleanup_old_backups() {
    log_info "Cleaning up old backups..."
    
    local retention_days="${1:-30}"
    local backup_parent_dir="${PROJECT_ROOT}/backups/${ENVIRONMENT}"
    
    if [ -d "$backup_parent_dir" ]; then
        find "$backup_parent_dir" -type f -mtime +${retention_days} -delete || {
            log_warning "Failed to clean up old backups"
        }
        
        log_success "Old backups cleaned up (retention: ${retention_days} days)"
    fi
}

# Generate backup report
generate_report() {
    local report_file="${BACKUP_DIR}/../backup-report-${ENVIRONMENT}-${TIMESTAMP}.txt"
    
    # Calculate final backup size
    local final_backup="${BACKUP_DIR}/../mern-app-backup-${ENVIRONMENT}-${TIMESTAMP}.tar.gz"
    if [ -f "${final_backup}.enc" ]; then
        final_backup="${final_backup}.enc"
    fi
    
    if [ -f "$final_backup" ]; then
        BACKUP_SIZE=$(du -h "$final_backup" | cut -f1)
        FILES_BACKED_UP=$(find "$BACKUP_DIR" -type f | wc -l)
    fi
    
    cat > "$report_file" << EOF
MERN App Backup Report
======================
Environment: $ENVIRONMENT
Backup Type: $BACKUP_TYPE
Timestamp: $TIMESTAMP
Hostname: $(hostname)
User: $(whoami)

Backup Summary:
- Backup Size: $BACKUP_SIZE
- Files Backed Up: $FILES_BACKED_UP
- Backup Location: ${BACKUP_DIR}
- Compressed: $([ -f "${BACKUP_DIR}/../mern-app-backup-${ENVIRONMENT}-${TIMESTAMP}.tar.gz" ] && echo "Yes" || echo "No")
- Encrypted: $([ -f "${final_backup}.enc" ] && echo "Yes" || echo "No")
- S3 Uploaded: $([ "${UPLOAD_S3:-false}" = "true" ] && echo "Yes" || echo "No")

Backup Contents:
$(find "$BACKUP_DIR" -type f | head -20)

$(if [ $(find "$BACKUP_DIR" -type f | wc -l) -gt 20 ]; then
    echo "... and $(($(find "$BACKUP_DIR" -type f | wc -l) - 20)) more files"
fi)

Status: SUCCESS
EOF

    log_info "Backup report generated: $report_file"
}

# Main backup function
main() {
    local upload_s3=false
    local encrypt=false
    local compress=false
    local retention_days=30
    
    # Parse options
    shift 2 # Remove environment and backup type arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --s3)
                upload_s3=true
                shift
                ;;
            --encrypt)
                encrypt=true
                shift
                ;;
            --compress)
                compress=true
                shift
                ;;
            --retention)
                retention_days="$2"
                shift 2
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Set environment variables
    export UPLOAD_S3="$upload_s3"
    
    echo "========================================="
    echo "  MERN App Backup"
    echo "  Environment: $ENVIRONMENT"
    echo "  Backup Type: $BACKUP_TYPE"
    echo "  Timestamp: $TIMESTAMP"
    echo "========================================="
    echo
    
    # Create backup structure
    create_backup_structure
    
    # Execute backup based on type
    case "$BACKUP_TYPE" in
        "full")
            backup_k8s_configs
            backup_terraform_configs
            backup_ansible_configs
            backup_application_files
            backup_mongodb
            backup_secrets
            backup_logs
            ;;
        "database")
            backup_mongodb
            ;;
        "files")
            backup_application_files
            backup_logs
            ;;
        "configs")
            backup_k8s_configs
            backup_terraform_configs
            backup_ansible_configs
            backup_secrets
            ;;
        *)
            log_error "Invalid backup type: $BACKUP_TYPE"
            exit 1
            ;;
    esac
    
    # Post-processing
    if [ "$compress" = true ] || [ "$encrypt" = true ] || [ "$upload_s3" = true ]; then
        compress_backup
    fi
    
    if [ "$encrypt" = true ]; then
        encrypt_backup
    fi
    
    if [ "$upload_s3" = true ]; then
        upload_to_s3
    fi
    
    # Cleanup old backups
    cleanup_old_backups "$retention_days"
    
    # Generate report
    generate_report
    
    echo
    echo "========================================="
    echo "  Backup Completed Successfully"
    echo "========================================="
    log_success "Backup completed for $ENVIRONMENT environment"
    log_info "Backup location: ${BACKUP_DIR}"
    
    if [ -f "${BACKUP_DIR}/../mern-app-backup-${ENVIRONMENT}-${TIMESTAMP}.tar.gz" ]; then
        local backup_size=$(du -h "${BACKUP_DIR}/../mern-app-backup-${ENVIRONMENT}-${TIMESTAMP}.tar.gz" | cut -f1)
        log_info "Backup size: $backup_size"
    fi
}

# Run main function
main "$@"
