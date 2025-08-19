#!/bin/bash
# MySQL Role Post-Installation Script

print_info() {
    echo -e "\033[0;34mℹ $1\033[0m"
}

print_success() {
    echo -e "\033[0;32m✓ $1\033[0m"
}

print_info "Waiting for MySQL to be ready..."
sleep 10

# Test database connection
if docker exec ${COMPOSE_PROJECT_NAME:-homelab}-mysql mysqladmin ping -h localhost --silent; then
    print_success "MySQL is running and accessible"
else
    echo "Warning: MySQL may not be fully ready yet"
fi

print_info "MySQL role installation completed"
