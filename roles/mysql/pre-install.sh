#!/bin/bash
# MySQL Role Pre-Installation Script

print_info() {
    echo -e "\033[0;34mℹ $1\033[0m"
}

print_warning() {
    echo -e "\033[1;33m⚠ $1\033[0m"
}

print_info "Setting up MySQL configuration..."

# Create MySQL configuration file
cat > ./config/mysql.cnf << 'EOF'
[mysqld]
# Basic Configuration
default-authentication-plugin=mysql_native_password
sql_mode=STRICT_TRANS_TABLES,NO_ZERO_DATE,NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO

# Performance Configuration
innodb_buffer_pool_size=256M
innodb_log_file_size=64M
max_connections=200

# Security Configuration
bind-address=0.0.0.0
skip-networking=false

# Character Set Configuration
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci

# Logging Configuration
general_log=0
log_error=/var/log/mysql/error.log
slow_query_log=1
slow_query_log_file=/var/log/mysql/slow.log
long_query_time=2

[mysql]
default-character-set=utf8mb4

[client]
default-character-set=utf8mb4
EOF

print_info "MySQL configuration created"

# Check if passwords are set
if [[ -z "${MYSQL_ROOT_PASSWORD:-}" ]]; then
    print_warning "MYSQL_ROOT_PASSWORD not set - generating random password"
    export MYSQL_ROOT_PASSWORD=$(openssl rand -base64 32)
    echo "MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD" >> .env
fi

if [[ -z "${MYSQL_PASSWORD:-}" ]]; then
    print_warning "MYSQL_PASSWORD not set - generating random password"
    export MYSQL_PASSWORD=$(openssl rand -base64 32)
    echo "MYSQL_PASSWORD=$MYSQL_PASSWORD" >> .env
fi
