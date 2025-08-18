#!/bin/bash

# =============================================================================
# Homelab Quick Setup Script - Enhanced Version
# =============================================================================
# This script helps you get your homelab up and running quickly with improved
# error handling, validation, and recovery mechanisms

set -euo pipefail  # Enhanced error handling

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
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

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Cleanup function for error recovery
cleanup_on_error() {
    print_error "Setup failed, performing cleanup..."
    docker compose down --remove-orphans 2>/dev/null || true
    print_info "Cleanup completed. You can safely retry the setup."
}

# Set trap for error handling
trap cleanup_on_error ERR

# Minimum system requirements check
check_system_requirements() {
    print_header "System Requirements Check"
    
    # Check available disk space (minimum 2GB)
    available_space=$(df . | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 2097152 ]]; then  # 2GB in KB
        print_error "Insufficient disk space. At least 2GB required."
        exit 1
    fi
    print_success "Sufficient disk space available"
    
    # Check if ports are available
    if ss -tulpn 2>/dev/null | grep -q ":80\|:443"; then
        print_warning "Ports 80 or 443 appear to be in use. This may cause conflicts."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    print_success "Required ports appear to be available"
    
    # Check Docker version
    docker_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
    print_success "Docker version: $docker_version"
    
    # Check Docker Compose version
    compose_version=$(docker compose version --short 2>/dev/null || echo "unknown")
    print_success "Docker Compose version: $compose_version"
}

print_header "Homelab Setup Script - Enhanced"

# Run system requirements check
check_system_requirements

# Check if .env exists
if [[ ! -f ".env" ]]; then
    print_warning ".env file not found. Copying from .env.example..."
    cp .env.example .env
    print_success "Created .env file"
    print_warning "Please edit .env file with your configuration before continuing!"
    read -p "Press enter when you've configured .env..."
fi

# Source environment variables
if [[ -f ".env" ]]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# Validate required environment variables
print_header "Validating Configuration"

required_vars=("DOMAIN" "ACME_EMAIL" "CF_DNS_API_TOKEN" "TS_AUTHKEY")
missing_vars=()

for var in "${required_vars[@]}"; do
    if [[ -z "${!var}" ]] || [[ "${!var}" == "example.com" ]] || [[ "${!var}" == *"change-me"* ]] || [[ "${!var}" == *"put-your"* ]]; then
        missing_vars+=("$var")
    fi
done

if [[ ${#missing_vars[@]} -gt 0 ]]; then
    print_error "Missing or placeholder values for: ${missing_vars[*]}"
    print_error "Please edit .env file with real values"
    exit 1
fi

# Validate domain formats
domains=("$DOMAIN")
if [[ -n "${DOMAIN2:-}" && "$DOMAIN2" != "disabled.local" ]]; then
    domains+=("$DOMAIN2")
fi
if [[ -n "${DOMAIN3:-}" && "$DOMAIN3" != "disabled.local" ]]; then
    domains+=("$DOMAIN3")
fi

for domain in "${domains[@]}"; do
    if [[ ! "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
        print_warning "Domain format may be invalid: $domain"
    fi
    
    # Test DNS resolution
    if command -v dig >/dev/null 2>&1; then
        if dig +short "$domain" >/dev/null 2>&1; then
            print_success "Domain DNS resolution successful: $domain"
        else
            print_warning "Domain DNS resolution failed: $domain - ensure DNS records are configured"
        fi
    fi
done

print_success "Configuration validated"

# Create necessary directories
print_header "Creating Directories"

mkdir -p traefik/acme
chmod 700 traefik/acme
print_success "Created traefik/acme directory with correct permissions"

# Secure ACME file if it exists
if [[ -f "traefik/acme/acme.json" ]]; then
    chmod 600 traefik/acme/acme.json
    print_success "Secured existing acme.json file"
fi

# Create backup directory
mkdir -p backups
print_success "Created backups directory"

# Check if Docker is running
print_header "Checking Docker"
if ! docker info >/dev/null 2>&1; then
    print_error "Docker is not running or not accessible"
    exit 1
fi
print_success "Docker is running"

# Check if Compose is available
if ! docker compose version >/dev/null 2>&1; then
    print_error "Docker Compose is not available"
    exit 1
fi
print_success "Docker Compose is available"

# Pull images
print_header "Pulling Images"
docker compose --profile base pull
print_success "Images pulled successfully"

# Start services
print_header "Starting Services"
docker compose --profile base up -d
print_success "Services started"

# Wait for services to be healthy
print_header "Waiting for Services"
print_info "Waiting for services to become healthy (this may take a minute)..."

# Wait for Traefik to be healthy
max_attempts=30
attempt=0
while [[ $attempt -lt $max_attempts ]]; do
    if docker compose ps --format "{{.Health}}" traefik | grep -q "healthy"; then
        print_success "Traefik is healthy"
        break
    fi
    ((attempt++))
    echo -n "."
    sleep 2
done

if [[ $attempt -eq $max_attempts ]]; then
    print_warning "Traefik health check timeout - services may still be starting"
fi

# Additional health verification
print_header "Service Health Verification"
if command -v curl >/dev/null 2>&1; then
    if curl -s http://localhost:8080/ping >/dev/null 2>&1; then
        print_success "Traefik API responding"
    else
        print_warning "Traefik API not responding on localhost:8080"
    fi
fi

# Check service status
print_header "Service Status"
docker compose --profile base ps

# Show access information
print_header "Access Information"
echo -e "Your homelab is ready! Access your services at:"
echo -e "• Portainer: ${GREEN}https://portainer.${DOMAIN}${NC}"
echo -e "• Whoami (test): ${GREEN}https://whoami.${DOMAIN}${NC}"
echo -e "• Traefik Dashboard: ${GREEN}https://traefik.${DOMAIN}${NC}"
echo ""
echo -e "Make sure your DNS records point to this server:"
echo -e "• A/AAAA record: ${YELLOW}*.${DOMAIN}${NC} -> $(curl -s ifconfig.me 2>/dev/null || echo "YOUR_IP")"
echo ""
print_warning "If using Cloudflare Tunnel, configure public hostnames in Zero Trust dashboard"

print_success "Setup completed successfully!"

# Disable error trap for normal completion
trap - ERR

# Run validation
print_header "Running Setup Validation"
./validate.sh

print_header "Next Steps"
echo -e "1. ${YELLOW}Test your setup:${NC} Visit https://whoami.${DOMAIN}"
echo -e "2. ${YELLOW}Monitor logs:${NC} Run 'source aliases.sh && dclogs'"
echo -e "3. ${YELLOW}Add more services:${NC} Check profiles in docker-compose.yml"
echo -e "4. ${YELLOW}Backup:${NC} Consider setting up automated backups"
echo ""
print_info "For troubleshooting, check: docker compose logs traefik"
print_info "For detailed diagnostics: ./health-check.sh"
