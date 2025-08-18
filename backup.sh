#!/bin/bash

# =============================================================================
# Homelab Backup Script
# =============================================================================
# Automated backup solution for Docker volumes and configurations

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() { echo -e "${BLUE}=== $1 ===${NC}"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

# Configuration
BACKUP_DIR="./backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_NAME="homelab-backup-${TIMESTAMP}"
RETENTION_DAYS=30

print_header "Homelab Backup Script"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Backup function
perform_backup() {
    print_header "Creating Backup: $BACKUP_NAME"
    
    # Create temporary backup directory
    TEMP_BACKUP_DIR="$BACKUP_DIR/${BACKUP_NAME}"
    mkdir -p "$TEMP_BACKUP_DIR"
    
    # Backup configurations
    print_info "Backing up configurations..."
    cp -r traefik "$TEMP_BACKUP_DIR/"
    cp docker-compose.yml "$TEMP_BACKUP_DIR/"
    cp .env "$TEMP_BACKUP_DIR/" 2>/dev/null || print_warning ".env file not found"
    cp aliases.sh "$TEMP_BACKUP_DIR/"
    print_success "Configuration files backed up"
    
    # Backup Docker volumes
    print_info "Backing up Docker volumes..."
    
    # Get list of volumes used by this project
    PROJECT_NAME=$(basename "$(pwd)")
    VOLUMES=$(docker volume ls --format "{{.Name}}" | grep "^${PROJECT_NAME}" || true)
    
    if [[ -n "$VOLUMES" ]]; then
        mkdir -p "$TEMP_BACKUP_DIR/volumes"
        
        for volume in $VOLUMES; do
            print_info "Backing up volume: $volume"
            docker run --rm \
                -v "$volume:/source:ro" \
                -v "$(pwd)/$TEMP_BACKUP_DIR/volumes:/backup" \
                alpine tar czf "/backup/${volume}.tar.gz" -C /source .
            print_success "Volume $volume backed up"
        done
    else
        print_warning "No project volumes found to backup"
    fi
    
    # Create compressed archive
    print_info "Creating compressed archive..."
    cd "$BACKUP_DIR"
    tar czf "${BACKUP_NAME}.tar.gz" "$BACKUP_NAME"
    rm -rf "$BACKUP_NAME"
    cd - >/dev/null
    
    print_success "Backup created: $BACKUP_DIR/${BACKUP_NAME}.tar.gz"
    
    # Show backup size
    BACKUP_SIZE=$(du -h "$BACKUP_DIR/${BACKUP_NAME}.tar.gz" | cut -f1)
    print_info "Backup size: $BACKUP_SIZE"
}

# Cleanup old backups
cleanup_old_backups() {
    print_header "Cleaning up old backups"
    
    find "$BACKUP_DIR" -name "homelab-backup-*.tar.gz" -type f -mtime +$RETENTION_DAYS -delete 2>/dev/null || true
    
    REMAINING_BACKUPS=$(find "$BACKUP_DIR" -name "homelab-backup-*.tar.gz" -type f | wc -l)
    print_success "Cleanup completed. $REMAINING_BACKUPS backups remaining."
}

# List existing backups
list_backups() {
    print_header "Existing Backups"
    
    if ls "$BACKUP_DIR"/homelab-backup-*.tar.gz 1> /dev/null 2>&1; then
        for backup in "$BACKUP_DIR"/homelab-backup-*.tar.gz; do
            BACKUP_SIZE=$(du -h "$backup" | cut -f1)
            BACKUP_DATE=$(date -r "$backup" "+%Y-%m-%d %H:%M:%S")
            echo -e "📦 $(basename "$backup") - ${BACKUP_SIZE} - ${BACKUP_DATE}"
        done
    else
        print_info "No backups found in $BACKUP_DIR"
    fi
}

# Restore function
restore_backup() {
    local backup_file="$1"
    
    if [[ ! -f "$backup_file" ]]; then
        print_error "Backup file not found: $backup_file"
        exit 1
    fi
    
    print_header "Restoring from: $(basename "$backup_file")"
    print_warning "This will stop all services and restore configurations!"
    
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^yes$ ]]; then
        print_info "Restore cancelled"
        exit 0
    fi
    
    # Stop services
    print_info "Stopping services..."
    docker compose down || true
    
    # Extract backup
    print_info "Extracting backup..."
    TEMP_RESTORE_DIR="/tmp/homelab-restore-$$"
    mkdir -p "$TEMP_RESTORE_DIR"
    tar xzf "$backup_file" -C "$TEMP_RESTORE_DIR"
    
    # Find the backup directory (should be the only directory in temp)
    BACKUP_CONTENT_DIR=$(find "$TEMP_RESTORE_DIR" -type d -name "homelab-backup-*" | head -1)
    
    if [[ -z "$BACKUP_CONTENT_DIR" ]]; then
        print_error "Invalid backup format"
        rm -rf "$TEMP_RESTORE_DIR"
        exit 1
    fi
    
    # Restore configurations
    print_info "Restoring configurations..."
    cp -r "$BACKUP_CONTENT_DIR"/* ./
    
    # Restore volumes if they exist
    if [[ -d "$BACKUP_CONTENT_DIR/volumes" ]]; then
        print_info "Restoring volumes..."
        for volume_backup in "$BACKUP_CONTENT_DIR"/volumes/*.tar.gz; do
            if [[ -f "$volume_backup" ]]; then
                VOLUME_NAME=$(basename "$volume_backup" .tar.gz)
                print_info "Restoring volume: $VOLUME_NAME"
                
                # Create volume if it doesn't exist
                docker volume create "$VOLUME_NAME" >/dev/null 2>&1 || true
                
                # Restore volume content
                docker run --rm \
                    -v "$VOLUME_NAME:/target" \
                    -v "$volume_backup:/backup.tar.gz:ro" \
                    alpine sh -c "cd /target && tar xzf /backup.tar.gz"
                print_success "Volume $VOLUME_NAME restored"
            fi
        done
    fi
    
    # Cleanup
    rm -rf "$TEMP_RESTORE_DIR"
    
    print_success "Restore completed!"
    print_info "You can now start services with: docker compose --profile base up -d"
}

# Main script logic
case "${1:-backup}" in
    "backup")
        perform_backup
        cleanup_old_backups
        ;;
    "list")
        list_backups
        ;;
    "restore")
        if [[ -z "${2:-}" ]]; then
            print_error "Please specify backup file to restore"
            print_info "Usage: $0 restore <backup-file>"
            list_backups
            exit 1
        fi
        restore_backup "$2"
        ;;
    "cleanup")
        cleanup_old_backups
        ;;
    *)
        echo "Usage: $0 {backup|list|restore <file>|cleanup}"
        echo ""
        echo "Commands:"
        echo "  backup          Create a new backup (default)"
        echo "  list            List existing backups"
        echo "  restore <file>  Restore from backup file"
        echo "  cleanup         Remove old backups"
        exit 1
        ;;
esac
