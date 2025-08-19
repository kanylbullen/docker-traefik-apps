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

# Check Docker installation and install if missing
check_and_install_docker() {
    print_header "Docker Installation Check"
    
    # Check if Docker is installed
    if ! command -v docker >/dev/null 2>&1; then
        print_warning "Docker is not installed. Installing Docker..."
        
        # Detect the operating system
        if [[ -f /etc/os-release ]]; then
            . /etc/os-release
            OS=$ID
        else
            print_error "Cannot detect operating system"
            exit 1
        fi
        
        case $OS in
            "ubuntu"|"debian")
                print_info "Detected Debian/Ubuntu - installing Docker via official script"
                # Install prerequisites
                apt-get update
                apt-get install -y curl ca-certificates
                
                # Install Docker using official script
                curl -fsSL https://get.docker.com -o get-docker.sh
                sh get-docker.sh
                rm get-docker.sh
                
                # Enable and start Docker service
                systemctl enable docker
                systemctl start docker
                ;;
            "centos"|"rhel"|"fedora")
                print_info "Detected Red Hat/CentOS/Fedora - installing Docker"
                if command -v dnf >/dev/null 2>&1; then
                    dnf install -y docker-ce docker-ce-cli containerd.io
                else
                    yum install -y docker-ce docker-ce-cli containerd.io
                fi
                systemctl enable docker
                systemctl start docker
                ;;
            "alpine")
                print_info "Detected Alpine - installing Docker"
                apk update
                apk add docker docker-compose
                rc-update add docker boot
                service docker start
                ;;
            *)
                print_warning "Unknown OS: $OS - trying generic installation"
                curl -fsSL https://get.docker.com -o get-docker.sh
                sh get-docker.sh
                rm get-docker.sh
                ;;
        esac
        
        # Verify installation
        sleep 5
        if command -v docker >/dev/null 2>&1; then
            print_success "Docker installed successfully"
        else
            print_error "Docker installation failed"
            exit 1
        fi
    else
        print_success "Docker is already installed"
    fi
    
    # Check Docker service status
    if ! docker info >/dev/null 2>&1; then
        print_info "Starting Docker service..."
        
        # Try different service managers
        if systemctl is-active --quiet docker 2>/dev/null; then
            print_success "Docker service is running"
        elif systemctl start docker 2>/dev/null; then
            print_success "Docker service started via systemctl"
        elif service docker start 2>/dev/null; then
            print_success "Docker service started via service command"
        else
            print_error "Could not start Docker service"
            print_info "Please start Docker manually and re-run the script"
            exit 1
        fi
        
        # Wait for Docker to be ready
        print_info "Waiting for Docker to be ready..."
        for i in {1..30}; do
            if docker info >/dev/null 2>&1; then
                break
            fi
            sleep 1
        done
    fi
    
    # Final Docker check
    if docker info >/dev/null 2>&1; then
        print_success "Docker is running and accessible"
        DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
        print_info "Docker version: $DOCKER_VERSION"
    else
        print_error "Docker is installed but not accessible"
        print_info "You may need to:"
        print_info "1. Add your user to the docker group: sudo usermod -aG docker \$USER"
        print_info "2. Restart your session or run: newgrp docker"
        print_info "3. Start Docker service: sudo systemctl start docker"
        exit 1
    fi
    
    # Check Docker Compose
    if ! docker compose version >/dev/null 2>&1; then
        print_warning "Docker Compose plugin not found - trying to install"
        
        # Docker Compose should come with modern Docker installations
        # Try to install it manually if missing
        if [[ -f /etc/os-release ]]; then
            . /etc/os-release
            case $ID in
                "ubuntu"|"debian")
                    apt-get update
                    apt-get install -y docker-compose-plugin
                    ;;
                "centos"|"rhel"|"fedora")
                    if command -v dnf >/dev/null 2>&1; then
                        dnf install -y docker-compose-plugin
                    else
                        yum install -y docker-compose-plugin
                    fi
                    ;;
                "alpine")
                    apk add docker-compose
                    ;;
            esac
        fi
        
        # Final check
        if docker compose version >/dev/null 2>&1; then
            print_success "Docker Compose is available"
        else
            print_error "Docker Compose installation failed"
            print_info "Please install Docker Compose manually"
            exit 1
        fi
    else
        print_success "Docker Compose is available"
        COMPOSE_VERSION=$(docker compose version --short 2>/dev/null || echo "unknown")
        print_info "Docker Compose version: $COMPOSE_VERSION"
    fi
}

# Minimum system requirements check
check_system_requirements() {
    print_header "System Requirements Check"
    
    # Check available disk space (minimum 1GB)
    available_space=$(df . | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 1048576 ]]; then  # 1GB in KB
        print_error "Insufficient disk space. At least 1GB required."
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
}

print_header "Homelab Setup Script - Enhanced"

# Run system requirements check
check_system_requirements

# Check and install Docker if needed
check_and_install_docker

# Check container environment and adjust services
check_container_environment() {
    print_header "Container Environment Check"
    
    # Detect if running in LXC/container
    if systemd-detect-virt >/dev/null 2>&1; then
        VIRT_TYPE=$(systemd-detect-virt)
        print_info "Detected virtualization: $VIRT_TYPE"
        
        if [[ "$VIRT_TYPE" == "lxc" ]]; then
            print_warning "Running in LXC container - Tailscale requires host configuration"
            
            # Check if TUN device is available
            if [[ ! -e /dev/net/tun ]]; then
                print_warning "TUN device not available - Tailscale will be disabled"
                print_info ""
                print_info "🔧 To enable Tailscale in Proxmox LXC:"
                print_info "1. Exit this container and run on the Proxmox VE host:"
                print_info "   bash -c \"\$(wget -qLO - https://github.com/community-scripts/ProxmoxVE/raw/main/misc/add-tailscale-lxc.sh)\""
                print_info "2. Follow the script prompts to configure your container"
                print_info "3. Restart this container and re-run the setup"
                print_info ""
                print_info "📖 More info: https://community-scripts.github.io/ProxmoxVE/scripts?id=add-tailscale-lxc"
                print_info ""
                print_info "🌐 Alternative: Use Cloudflare Tunnel for remote access (works without TUN device)"
                
                # Set flag to skip Tailscale
                export SKIP_TAILSCALE=true
            else
                print_success "TUN device available - Tailscale should work"
                print_info "Tailscale appears to be properly configured for this LXC container"
            fi
        fi
    else
        print_success "Running on bare metal or VM - all features should work"
    fi
}

# Check container environment
check_container_environment

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

# Pull images
print_header "Pulling Images"
if [[ "${SKIP_TAILSCALE:-false}" == "true" ]]; then
    print_info "Skipping Tailscale due to LXC environment"
    docker compose pull traefik portainer socket-proxy whoami cloudflared
else
    docker compose --profile base pull
fi
print_success "Images pulled successfully"

# Start services
print_header "Starting Services"
if [[ "${SKIP_TAILSCALE:-false}" == "true" ]]; then
    print_info "Starting services without Tailscale"
    docker compose up -d traefik portainer socket-proxy whoami cloudflared
else
    docker compose --profile base up -d
fi
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
if [[ "${SKIP_TAILSCALE:-false}" == "true" ]]; then
    docker compose ps traefik portainer socket-proxy whoami cloudflared
    print_info "Note: Tailscale skipped due to LXC environment"
else
    docker compose --profile base ps
fi

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
if [[ "${SKIP_TAILSCALE:-false}" == "true" ]]; then
    echo -e "1. ${YELLOW}Test your setup:${NC} Visit https://whoami.${DOMAIN}"
    echo -e "2. ${YELLOW}Monitor logs:${NC} Run 'source aliases.sh && dclogs'"
    echo -e "3. ${YELLOW}Enable Tailscale (optional):${NC} Run the Proxmox community script on the host:"
    echo -e "   ${BLUE}bash -c \"\$(wget -qLO - https://github.com/community-scripts/ProxmoxVE/raw/main/misc/add-tailscale-lxc.sh)\"${NC}"
    echo -e "4. ${YELLOW}Alternative remote access:${NC} Configure CLOUDFLARED_TOKEN in .env"
    echo -e "5. ${YELLOW}Add more services:${NC} Check profiles in docker-compose.yml"
    echo -e "6. ${YELLOW}Backup:${NC} Consider setting up automated backups"
else
    echo -e "1. ${YELLOW}Test your setup:${NC} Visit https://whoami.${DOMAIN}"
    echo -e "2. ${YELLOW}Monitor logs:${NC} Run 'source aliases.sh && dclogs'"
    echo -e "3. ${YELLOW}Add more services:${NC} Check profiles in docker-compose.yml"
    echo -e "4. ${YELLOW}Backup:${NC} Consider setting up automated backups"
fi
echo ""
print_info "For troubleshooting, check: docker compose logs traefik"
print_info "For detailed diagnostics: ./health-check.sh"
if [[ "${SKIP_TAILSCALE:-false}" == "true" ]]; then
    print_info "LXC-specific guide: cat LXC-SETUP.md"
fi
