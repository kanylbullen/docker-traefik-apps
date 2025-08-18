#!/bin/bash

# =============================================================================
# Homelab Health Monitor
# =============================================================================
# Monitor and report on the health of homelab services

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

# Load environment variables
if [[ -f ".env" ]]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

print_header "Homelab Health Monitor"

# Check Docker daemon
check_docker() {
    print_header "Docker System Status"
    
    if docker info >/dev/null 2>&1; then
        print_success "Docker daemon is running"
        
        # Docker system info
        DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
        print_info "Docker version: $DOCKER_VERSION"
        
        # System resources
        docker system df
        echo ""
        
    else
        print_error "Docker daemon is not running"
        return 1
    fi
}

# Check service health
check_services() {
    print_header "Service Health Status"
    
    # Get service status
    docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Health}}"
    echo ""
    
    # Check individual service health
    services=("traefik" "portainer" "socket-proxy")
    
    for service in "${services[@]}"; do
        if docker compose ps --services | grep -q "^${service}$"; then
            status=$(docker compose ps --format "{{.Status}}" "$service" 2>/dev/null || echo "not found")
            health=$(docker compose ps --format "{{.Health}}" "$service" 2>/dev/null || echo "unknown")
            
            if [[ "$status" == *"Up"* ]]; then
                if [[ "$health" == "healthy" ]] || [[ "$health" == "" ]]; then
                    print_success "$service: Running"
                else
                    print_warning "$service: Running but health status: $health"
                fi
            else
                print_error "$service: $status"
            fi
        else
            print_info "$service: Not deployed"
        fi
    done
}

# Check network connectivity
check_connectivity() {
    print_header "Network Connectivity"
    
    # Check Traefik API
    if curl -s http://localhost:8080/ping >/dev/null 2>&1; then
        print_success "Traefik API responding on localhost:8080"
    else
        print_warning "Traefik API not responding on localhost:8080"
    fi
    
    # Check external connectivity
    if curl -s https://1.1.1.1 >/dev/null 2>&1; then
        print_success "External connectivity: OK"
    else
        print_error "External connectivity: FAILED"
    fi
    
    # Check domain resolution if domain is configured
    if [[ -n "${DOMAIN:-}" ]] && [[ "$DOMAIN" != "example.com" ]]; then
        if command -v dig >/dev/null 2>&1; then
            if dig +short "$DOMAIN" >/dev/null 2>&1; then
                print_success "Domain resolution: $DOMAIN"
            else
                print_warning "Domain resolution failed: $DOMAIN"
            fi
        fi
    fi
}

# Check SSL certificates
check_certificates() {
    print_header "SSL Certificate Status"
    
    if [[ -f "traefik/acme/acme.json" ]]; then
        # Check if acme.json has content (certificates)
        if [[ -s "traefik/acme/acme.json" ]]; then
            print_success "ACME certificates file exists and has content"
            
            # Check file permissions
            PERMS=$(stat -c "%a" traefik/acme/acme.json 2>/dev/null || echo "unknown")
            if [[ "$PERMS" == "600" ]]; then
                print_success "ACME file permissions: secure ($PERMS)"
            else
                print_warning "ACME file permissions: $PERMS (should be 600)"
            fi
        else
            print_warning "ACME certificates file exists but is empty"
        fi
    else
        print_info "ACME certificates file not found (first run?)"
    fi
    
    # Test HTTPS if domain is configured
    if [[ -n "${DOMAIN:-}" ]] && [[ "$DOMAIN" != "example.com" ]]; then
        print_info "Testing HTTPS certificate for $DOMAIN..."
        
        # Test whoami endpoint
        if curl -s --max-time 10 "https://whoami.$DOMAIN" >/dev/null 2>&1; then
            print_success "HTTPS certificate working for whoami.$DOMAIN"
        else
            print_warning "HTTPS test failed for whoami.$DOMAIN"
        fi
    fi
}

# Check resource usage
check_resources() {
    print_header "Resource Usage"
    
    # Docker stats for running containers
    echo "Container Resource Usage:"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.PIDs}}" 2>/dev/null || echo "No running containers"
    echo ""
    
    # Disk usage
    echo "Disk Usage:"
    df -h . | grep -v "Filesystem"
    echo ""
    
    # Docker system usage
    echo "Docker System Usage:"
    docker system df
}

# Check log health (recent errors)
check_logs() {
    print_header "Recent Log Analysis"
    
    # Check for recent errors in Traefik logs
    if docker compose logs --since 1h traefik 2>/dev/null | grep -i "error\|fatal\|panic" | tail -5; then
        print_warning "Recent errors found in Traefik logs (last 5 shown)"
    else
        print_success "No recent errors in Traefik logs"
    fi
    
    echo ""
    
    # Check for certificate issues
    if docker compose logs --since 24h traefik 2>/dev/null | grep -i "certificate\|acme\|letsencrypt" | grep -i "error\|fail" | tail -3; then
        print_warning "Recent certificate-related issues found"
    else
        print_success "No recent certificate issues"
    fi
}

# Generate summary report
generate_summary() {
    print_header "Health Summary"
    
    # Count healthy vs unhealthy services
    total_services=$(docker compose config --services | wc -l)
    running_services=$(docker compose ps --services --filter "status=running" | wc -l || echo 0)
    
    if [[ $running_services -eq $total_services ]]; then
        print_success "All services are running ($running_services/$total_services)"
    else
        print_warning "Some services are not running ($running_services/$total_services)"
    fi
    
    # Overall health assessment
    if [[ $running_services -ge 3 ]]; then  # Core services: traefik, portainer, socket-proxy
        print_success "Homelab appears to be healthy"
    else
        print_error "Homelab may have issues - check individual services"
    fi
    
    echo ""
    print_info "For detailed logs: docker compose logs -f"
    print_info "For service management: source aliases.sh"
}

# Main execution
main() {
    case "${1:-all}" in
        "docker")
            check_docker
            ;;
        "services")
            check_services
            ;;
        "network")
            check_connectivity
            ;;
        "certs")
            check_certificates
            ;;
        "resources")
            check_resources
            ;;
        "logs")
            check_logs
            ;;
        "summary")
            generate_summary
            ;;
        "all")
            check_docker
            echo ""
            check_services
            echo ""
            check_connectivity
            echo ""
            check_certificates
            echo ""
            check_resources
            echo ""
            check_logs
            echo ""
            generate_summary
            ;;
        *)
            echo "Usage: $0 {all|docker|services|network|certs|resources|logs|summary}"
            echo ""
            echo "Commands:"
            echo "  all        Run all health checks (default)"
            echo "  docker     Check Docker daemon status"
            echo "  services   Check service health"
            echo "  network    Check network connectivity"
            echo "  certs      Check SSL certificates"
            echo "  resources  Check resource usage"
            echo "  logs       Analyze recent logs"
            echo "  summary    Generate health summary"
            exit 1
            ;;
    esac
}

main "$@"
