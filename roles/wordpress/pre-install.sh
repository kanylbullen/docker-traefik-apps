#!/bin/bash

# =============================================================================
# WordPress Pre-Installation Script
# =============================================================================
# This script runs before WordPress installation to set up the database
# and any other prerequisites

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Check if MySQL container is running
check_mysql_container() {
    local mysql_host="$1"
    local container_name=""
    
    # Extract container name from host
    if [[ "$mysql_host" == homelab-mysql-*-mysql ]]; then
        container_name="$mysql_host"
    else
        print_error "Invalid MySQL host format: $mysql_host"
        return 1
    fi
    
    if ! docker ps --format "{{.Names}}" | grep -q "^${container_name}$"; then
        print_error "MySQL container $container_name is not running"
        print_info "Please ensure the corresponding MySQL instance is installed and running"
        return 1
    fi
    
    print_success "MySQL container $container_name is running"
    return 0
}

# Wait for MySQL to be ready
wait_for_mysql() {
    local mysql_host="$1"
    local mysql_root_password="$2"
    local max_attempts=30
    local attempt=1
    
    print_info "Waiting for MySQL to be ready..."
    
    while [ $attempt -le $max_attempts ]; do
        if docker exec "$mysql_host" mysqladmin ping -h localhost --silent >/dev/null 2>&1; then
            print_success "MySQL is ready"
            return 0
        fi
        
        print_info "Attempt $attempt/$max_attempts - MySQL not ready yet, waiting..."
        sleep 2
        ((attempt++))
    done
    
    print_error "MySQL did not become ready after $max_attempts attempts"
    return 1
}

# Create WordPress database and user
create_wordpress_database() {
    local mysql_host="$1"
    local mysql_root_password="$2"
    local db_name="$3"
    local db_user="$4"
    local db_password="$5"
    
    print_info "Creating WordPress database '$db_name' and user '$db_user'"
    
    # Create the database and user
    docker exec -i "$mysql_host" mysql -uroot -p"$mysql_root_password" << EOF
CREATE DATABASE IF NOT EXISTS \`$db_name\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$db_user'@'%' IDENTIFIED BY '$db_password';
GRANT ALL PRIVILEGES ON \`$db_name\`.* TO '$db_user'@'%';
FLUSH PRIVILEGES;
EOF

    if [ $? -eq 0 ]; then
        print_success "Database '$db_name' and user '$db_user' created successfully"
    else
        print_error "Failed to create database '$db_name' and user '$db_user'"
        return 1
    fi
}

# Get MySQL root password based on the MySQL instance
get_mysql_root_password() {
    local mysql_host="$1"
    
    # Extract instance name from MySQL host
    if [[ "$mysql_host" =~ homelab-mysql-([^-]+)-mysql ]]; then
        local mysql_instance="${BASH_REMATCH[1]}"
        local mysql_env_file="/opt/homelab/instances/mysql-${mysql_instance}/.env"
        
        if [[ -f "$mysql_env_file" ]]; then
            # First try instance-specific password, then fall back to global
            local instance_password=$(grep "^${mysql_instance}_MYSQL_ROOT_PASSWORD=" "$mysql_env_file" | cut -d'=' -f2- | sed 's/^"//; s/"$//')
            local global_password=$(grep "^MYSQL_ROOT_PASSWORD=" "$mysql_env_file" | cut -d'=' -f2- | sed 's/^"//; s/"$//')
            
            if [[ -n "$instance_password" ]]; then
                echo "$instance_password"
            elif [[ -n "$global_password" ]]; then
                echo "$global_password"
            else
                print_error "No MySQL root password found in $mysql_env_file"
                return 1
            fi
        else
            print_error "MySQL instance environment file not found: $mysql_env_file"
            return 1
        fi
    else
        print_error "Could not extract instance name from MySQL host: $mysql_host"
        return 1
    fi
}

# Main setup function
main() {
    print_info "WordPress pre-installation setup starting..."
    
    # Check if we have the required environment variables
    if [[ -z "${WORDPRESS_DB_HOST:-}" ]]; then
        print_error "WORDPRESS_DB_HOST environment variable is not set"
        exit 1
    fi
    
    if [[ -z "${WORDPRESS_DB_NAME:-}" ]]; then
        print_error "WORDPRESS_DB_NAME environment variable is not set"
        exit 1
    fi
    
    if [[ -z "${WORDPRESS_DB_USER:-}" ]]; then
        print_error "WORDPRESS_DB_USER environment variable is not set"
        exit 1
    fi
    
    if [[ -z "${WORDPRESS_DB_PASSWORD:-}" ]]; then
        print_error "WORDPRESS_DB_PASSWORD environment variable is not set"
        exit 1
    fi
    
    # Get MySQL root password
    local mysql_root_password
    mysql_root_password=$(get_mysql_root_password "$WORDPRESS_DB_HOST")
    if [ $? -ne 0 ]; then
        exit 1
    fi
    
    # Check if MySQL container is running
    if ! check_mysql_container "$WORDPRESS_DB_HOST"; then
        exit 1
    fi
    
    # Wait for MySQL to be ready
    if ! wait_for_mysql "$WORDPRESS_DB_HOST" "$mysql_root_password"; then
        exit 1
    fi
    
    # Create WordPress database and user
    if ! create_wordpress_database "$WORDPRESS_DB_HOST" "$mysql_root_password" "$WORDPRESS_DB_NAME" "$WORDPRESS_DB_USER" "$WORDPRESS_DB_PASSWORD"; then
        exit 1
    fi
    
    print_success "WordPress pre-installation setup completed successfully"
}

# Run main function
main "$@"
