#!/bin/bash

# DNS Management Helper for Cloudflare
# Handles automatic DNS record creation and IP detection

set -euo pipefail

# Source environment variables
if [[ -f ".env" ]]; then
    set -a
    source .env
    set +a
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

# Check required environment variables
check_cloudflare_config() {
    if [[ -z "${CF_DNS_API_TOKEN:-}" ]]; then
        log_error "CF_DNS_API_TOKEN is required for DNS management"
        return 1
    fi
    
    if [[ -z "${DOMAIN:-}" ]]; then
        log_error "DOMAIN is required for DNS management"
        return 1
    fi
}

# Get public IP address
get_public_ip() {
    local ip=""
    
    # Try multiple services for reliability
    for service in "ipv4.icanhazip.com" "ipinfo.io/ip" "ifconfig.me" "checkip.amazonaws.com"; do
        if ip=$(curl -s --max-time 5 "$service" 2>/dev/null); then
            # Validate IP format
            if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                echo "$ip"
                return 0
            fi
        fi
    done
    
    log_error "Failed to detect public IP address"
    return 1
}

# Get zone ID for domain
get_zone_id() {
    local domain="$1"
    local response
    
    response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$domain" \
        -H "Authorization: Bearer $CF_DNS_API_TOKEN" \
        -H "Content-Type: application/json")
    
    local zone_id
    zone_id=$(echo "$response" | jq -r '.result[0].id // empty')
    
    if [[ -z "$zone_id" || "$zone_id" == "null" ]]; then
        log_error "Failed to get zone ID for domain: $domain"
        return 1
    fi
    
    echo "$zone_id"
}

# Check if DNS record exists
check_dns_record() {
    local zone_id="$1"
    local name="$2"
    local type="${3:-A}"
    
    local response
    response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?name=$name&type=$type" \
        -H "Authorization: Bearer $CF_DNS_API_TOKEN" \
        -H "Content-Type: application/json")
    
    local record_id
    record_id=$(echo "$response" | jq -r '.result[0].id // empty')
    
    if [[ -n "$record_id" && "$record_id" != "null" ]]; then
        echo "$record_id"
        return 0
    fi
    
    return 1
}

# Create or update DNS record
create_or_update_dns_record() {
    local zone_id="$1"
    local name="$2"
    local content="$3"
    local type="${4:-A}"
    local proxied="${5:-false}"
    
    local record_id
    if record_id=$(check_dns_record "$zone_id" "$name" "$type"); then
        # Update existing record
        log_info "Updating existing DNS record: $name"
        local response
        response=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$record_id" \
            -H "Authorization: Bearer $CF_DNS_API_TOKEN" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"$type\",\"name\":\"$name\",\"content\":\"$content\",\"proxied\":$proxied}")
    else
        # Create new record
        log_info "Creating new DNS record: $name"
        local response
        response=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records" \
            -H "Authorization: Bearer $CF_DNS_API_TOKEN" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"$type\",\"name\":\"$name\",\"content\":\"$content\",\"proxied\":$proxied}")
    fi
    
    local success
    success=$(echo "$response" | jq -r '.success')
    
    if [[ "$success" == "true" ]]; then
        local proxy_status
        if [[ "$proxied" == "true" ]]; then
            proxy_status="(proxied - orange cloud)"
        else
            proxy_status="(DNS only - gray cloud)"
        fi
        log_success "DNS record created/updated: $name -> $content $proxy_status"
        return 0
    else
        local error
        error=$(echo "$response" | jq -r '.errors[0].message // "Unknown error"')
        log_error "Failed to create/update DNS record: $error"
        return 1
    fi
}

# Setup DNS records for public direct access
setup_public_dns() {
    local public_ip="$1"
    local proxied="${2:-false}"
    
    log_info "Setting up DNS records for public access..."
    
    check_cloudflare_config || return 1
    
    local zone_id
    zone_id=$(get_zone_id "$DOMAIN") || return 1
    
    log_info "Found zone ID: $zone_id"
    log_info "Public IP: $public_ip"
    log_info "Proxy mode: $proxied"
    
    # Create wildcard record
    create_or_update_dns_record "$zone_id" "*.${DOMAIN}" "$public_ip" "A" "$proxied" || return 1
    
    # Create specific service records (optional, wildcard covers these)
    for subdomain in "traefik" "portainer" "whoami"; do
        create_or_update_dns_record "$zone_id" "${subdomain}.${DOMAIN}" "$public_ip" "A" "$proxied" || return 1
    done
    
    log_success "DNS records configured successfully!"
    
    if [[ "$proxied" == "true" ]]; then
        log_info "🔶 Records are proxied through Cloudflare (orange cloud)"
        log_warning "Note: Some features may not work with proxied records (e.g., non-HTTP protocols)"
    else
        log_info "🔘 Records are DNS-only (gray cloud)"
        log_info "Direct connection to your server IP"
    fi
}

# Validate DNS resolution
validate_dns() {
    local subdomain="$1"
    local expected_ip="$2"
    
    log_info "Validating DNS resolution for $subdomain..."
    
    local resolved_ip
    resolved_ip=$(dig +short "${subdomain}.${DOMAIN}" @1.1.1.1 | head -n1)
    
    if [[ -z "$resolved_ip" ]]; then
        log_warning "DNS resolution failed for ${subdomain}.${DOMAIN}"
        return 1
    fi
    
    # For proxied records, we won't get the original IP
    if [[ "${CLOUDFLARE_PROXY:-false}" == "true" ]]; then
        log_success "DNS resolves to Cloudflare IP: $resolved_ip (proxied)"
        return 0
    fi
    
    if [[ "$resolved_ip" == "$expected_ip" ]]; then
        log_success "DNS resolves correctly: ${subdomain}.${DOMAIN} -> $resolved_ip"
        return 0
    else
        log_warning "DNS mismatch: ${subdomain}.${DOMAIN} -> $resolved_ip (expected: $expected_ip)"
        log_info "DNS propagation may take up to 24 hours"
        return 1
    fi
}

# Main function
main() {
    case "${1:-help}" in
        "setup-public")
            local public_ip="${PUBLIC_IP:-}"
            if [[ -z "$public_ip" || "$public_ip" == "auto" ]]; then
                log_info "Auto-detecting public IP..."
                public_ip=$(get_public_ip) || exit 1
            fi
            
            local proxied="${CLOUDFLARE_PROXY:-false}"
            setup_public_dns "$public_ip" "$proxied"
            
            # Validate a few key records
            sleep 2  # Brief pause for immediate DNS updates
            validate_dns "whoami" "$public_ip" || true
            validate_dns "portainer" "$public_ip" || true
            ;;
        "validate")
            local public_ip="${PUBLIC_IP:-}"
            if [[ -z "$public_ip" ]]; then
                public_ip=$(get_public_ip) || exit 1
            fi
            
            validate_dns "whoami" "$public_ip"
            validate_dns "portainer" "$public_ip"
            validate_dns "traefik" "$public_ip"
            ;;
        "get-ip")
            get_public_ip
            ;;
        *)
            echo "DNS Management Helper"
            echo ""
            echo "Usage: $0 <command>"
            echo ""
            echo "Commands:"
            echo "  setup-public  - Create DNS records for public access"
            echo "  validate      - Validate DNS resolution"
            echo "  get-ip        - Get current public IP"
            echo ""
            echo "Environment variables:"
            echo "  DEPLOYMENT_TYPE     - Deployment type (PUBLIC_DIRECT|PUBLIC_TUNNEL|PRIVATE_LOCAL)"
            echo "  CF_DNS_API_TOKEN    - Cloudflare API token"
            echo "  DOMAIN              - Primary domain"
            echo "  PUBLIC_IP           - Public IP (auto-detect if not set)"
            echo "  CLOUDFLARE_PROXY    - Enable Cloudflare proxy (true|false)"
            ;;
    esac
}

# Run main function with all arguments
main "$@"
