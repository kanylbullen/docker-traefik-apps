#!/bin/bash

# =============================================================================
# Setup Validation Script
# =============================================================================
# Quick validation to ensure everything is working correctly

set -euo pipefail

# Colors
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

# Load environment
if [[ -f ".env" ]]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

print_header "Homelab Setup Validation"

# Test 1: Check if services are running
print_info "Checking service status..."
if docker compose ps --services --filter "status=running" | grep -q "traefik"; then
    print_success "Core services are running"
else
    print_error "Core services are not running"
    exit 1
fi

# Test 2: Check Traefik API
print_info "Testing Traefik API..."
if curl -s http://localhost:8080/ping >/dev/null 2>&1; then
    print_success "Traefik API is responding"
else
    print_warning "Traefik API not responding (may be disabled for security)"
fi

# Test 3: Check SSL certificates
print_info "Checking SSL certificate status..."
if [[ -f "traefik/acme/acme.json" && -s "traefik/acme/acme.json" ]]; then
    print_success "SSL certificates are present"
else
    print_warning "SSL certificates not yet obtained (may take a few minutes on first run)"
fi

# Test 4: Test HTTPS endpoints (if domain is configured)
if [[ -n "${DOMAIN:-}" && "$DOMAIN" != "example.com" ]]; then
    print_info "Testing HTTPS endpoints..."
    
    # Test whoami endpoint
    if curl -s --max-time 10 "https://whoami.$DOMAIN" >/dev/null 2>&1; then
        print_success "HTTPS is working for whoami.$DOMAIN"
    else
        print_warning "HTTPS test failed for whoami.$DOMAIN (DNS or certificate issue)"
    fi
    
    # Test Portainer endpoint
    if curl -s --max-time 10 "https://portainer.$DOMAIN" >/dev/null 2>&1; then
        print_success "HTTPS is working for portainer.$DOMAIN"
    else
        print_warning "HTTPS test failed for portainer.$DOMAIN"
    fi
else
    print_info "Domain not configured or using example.com - skipping HTTPS tests"
fi

# Test 5: Check file permissions
print_info "Checking security permissions..."
if [[ -f "traefik/acme/acme.json" ]]; then
    PERMS=$(stat -c "%a" traefik/acme/acme.json 2>/dev/null || echo "unknown")
    if [[ "$PERMS" == "600" ]]; then
        print_success "ACME file permissions are secure"
    else
        print_warning "ACME file permissions: $PERMS (should be 600)"
        print_info "Fix with: chmod 600 traefik/acme/acme.json"
    fi
fi

# Test 6: Check resource usage
print_info "Checking resource usage..."
CONTAINER_COUNT=$(docker compose ps -q | wc -l)
if [[ $CONTAINER_COUNT -ge 3 ]]; then
    print_success "$CONTAINER_COUNT containers running"
else
    print_warning "Only $CONTAINER_COUNT containers running (expected 3+)"
fi

# Summary
print_header "Validation Summary"

# Check overall health
ISSUES=0

# Count any warnings or errors from above tests
if ! docker compose ps --services --filter "status=running" | grep -q "traefik"; then
    ((ISSUES++))
fi

if [[ -n "${DOMAIN:-}" && "$DOMAIN" != "example.com" ]]; then
    if ! curl -s --max-time 5 "https://whoami.$DOMAIN" >/dev/null 2>&1; then
        ((ISSUES++))
    fi
fi

if [[ $ISSUES -eq 0 ]]; then
    print_success "Homelab validation passed! 🎉"
    echo ""
    print_info "Access your services:"
    if [[ -n "${DOMAIN:-}" && "$DOMAIN" != "example.com" ]]; then
        echo -e "  • Portainer: ${GREEN}https://portainer.$DOMAIN${NC}"
        echo -e "  • Whoami:    ${GREEN}https://whoami.$DOMAIN${NC}"
        echo -e "  • Traefik:   ${GREEN}https://traefik.$DOMAIN${NC}"
    else
        echo -e "  • Configure your domain in .env to see service URLs"
    fi
    echo ""
    print_info "Useful commands:"
    echo "  • View logs: docker compose logs -f"
    echo "  • Health check: ./health-check.sh"
    echo "  • Create backup: ./backup.sh"
    echo "  • Troubleshoot: source aliases.sh && troubleshoot"
else
    print_warning "Validation found $ISSUES potential issues"
    print_info "Run './health-check.sh' for detailed diagnostics"
    print_info "Check 'TROUBLESHOOTING.md' for solutions"
fi
