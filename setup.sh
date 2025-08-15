#!/bin/bash

# =============================================================================
# Homelab Quick Setup Script
# =============================================================================
# This script helps you get your homelab up and running quickly

set -e

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

print_header "Homelab Setup Script"

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

print_success "Configuration validated"

# Create necessary directories
print_header "Creating Directories"

mkdir -p traefik/acme
chmod 700 traefik/acme
print_success "Created traefik/acme directory with correct permissions"

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
sleep 10

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
