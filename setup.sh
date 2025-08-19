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

# Deployment mode configuration
configure_deployment_mode() {
    print_header "Deployment Configuration"
    
    # Load environment variables if .env exists
    if [[ -f ".env" ]]; then
        set -a
        source .env
        set +a
    fi
    
    # Get deployment type from .env or default to PRIVATE_LOCAL
    local deployment_type="${DEPLOYMENT_TYPE:-PRIVATE_LOCAL}"
    
    case "$deployment_type" in
        "PUBLIC_DIRECT")
            export DEPLOYMENT_MODE="public"
            export COMPOSE_FILE="docker-compose.public-direct.yml"
            print_info "Selected: Public Direct Access (port forwarding required)"
            print_info "• Requires port forwarding: 80, 443"
            print_info "• Auto-detects public IP and creates DNS records"
            print_info "• Uses Traefik for reverse proxy and SSL"
            configure_public_direct_deployment
            ;;
        "PUBLIC_TUNNEL")
            export DEPLOYMENT_MODE="tunnel"
            export COMPOSE_FILE="docker-compose.public-tunnel.yml"
            print_info "Selected: Public Tunnel Access (no port forwarding needed)"
            print_info "• Uses Cloudflare Tunnel for secure access"
            print_info "• No port forwarding required"
            print_info "• Traefik for internal routing"
            configure_public_tunnel_deployment
            ;;
        "PRIVATE_LOCAL")
            export DEPLOYMENT_MODE="local"
            export COMPOSE_FILE="docker-compose.private-local.yml"
            print_info "Selected: Private Local Access"
            print_info "• Local network access only"
            print_info "• SSL certificates via DNS challenge"
            print_info "• No public exposure"
            configure_private_local_deployment
            ;;
        *)
            print_error "Invalid DEPLOYMENT_TYPE in .env: $deployment_type"
            print_info "Valid options: PUBLIC_DIRECT, PUBLIC_TUNNEL, PRIVATE_LOCAL"
            exit 1
            ;;
    esac
}

configure_public_direct_deployment() {
    print_header "Public Direct Access Configuration"
    
    # Check required variables
    local required_vars=("DOMAIN" "ACME_EMAIL" "CF_DNS_API_TOKEN")
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        print_error "Missing required variables for PUBLIC_DIRECT: ${missing_vars[*]}"
        print_info "Please configure these in your .env file"
        exit 1
    fi
    
    # Auto-detect or use configured public IP
    if [[ "${AUTO_DETECT_IP:-true}" == "true" ]] || [[ -z "${PUBLIC_IP:-}" ]]; then
        print_info "Auto-detecting public IP..."
        if ! PUBLIC_IP=$(./dns-manager.sh get-ip); then
            print_error "Failed to detect public IP. Please set PUBLIC_IP in .env"
            exit 1
        fi
        print_success "Detected public IP: $PUBLIC_IP"
    else
        print_info "Using configured public IP: $PUBLIC_IP"
    fi
    
    # Setup DNS records
    print_info "Setting up DNS records..."
    if ./dns-manager.sh setup-public; then
        print_success "DNS records configured successfully"
    else
        print_error "Failed to setup DNS records"
        print_info "You may need to configure DNS manually"
    fi
    
    export PUBLIC_IP
}

configure_public_tunnel_deployment() {
    print_header "Public Tunnel Access Configuration"
    
    # Check required variables
    local required_vars=("DOMAIN" "CLOUDFLARED_TOKEN")
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        print_error "Missing required variables for PUBLIC_TUNNEL: ${missing_vars[*]}"
        print_info "Please configure these in your .env file"
        print_info "Get CLOUDFLARED_TOKEN from: https://one.dash.cloudflare.com/ -> Networks -> Tunnels"
        exit 1
    fi
    
    print_success "Cloudflare Tunnel configuration validated"
    print_info "Make sure to configure public hostnames in your Cloudflare Zero Trust dashboard"
}

configure_private_local_deployment() {

configure_private_local_deployment() {
    print_header "Private Local Access Configuration"
    
    # For private local, we still use DNS challenge for valid certificates
    if [[ -n "${CF_DNS_API_TOKEN:-}" && -n "${DOMAIN:-}" ]]; then
        print_info "DNS challenge available - will issue valid SSL certificates"
        print_info "Domain: $DOMAIN (local access only)"
    else
        print_warning "No Cloudflare DNS token configured"
        print_info "Self-signed certificates will be used"
        export SKIP_ACME="true"
    fi
    
    print_info "Services will be accessible on local network only"
    print_info "No public exposure or port forwarding required"
}

# Legacy function for compatibility
configure_local_deployment() {
    configure_private_local_deployment
    print_header "Local Network Configuration"
    
    # Get server IP
    SERVER_IP=$(hostname -I | awk '{print $1}' || echo "127.0.0.1")
    
    echo -e "\n${BLUE}Local deployment configuration:${NC}"
    echo -e "• Access method: ${YELLOW}IP address or local hostname${NC}"
    echo -e "• SSL certificates: ${YELLOW}Self-signed or disabled${NC}"
    echo -e "• DNS requirements: ${GREEN}None${NC}"
    echo -e "• Port forwarding: ${GREEN}Not required${NC}"
    echo -e ""
    echo -e "Your services will be accessible at:"
    echo -e "• Portainer: ${GREEN}http://${SERVER_IP}:9000${NC} or ${GREEN}https://portainer.local${NC}"
    echo -e "• Traefik Dashboard: ${GREEN}http://${SERVER_IP}:8080${NC} or ${GREEN}https://traefik.local${NC}"
    echo -e "• Whoami: ${GREEN}https://whoami.local${NC}"
    echo -e ""
    
    # Set local configuration
    export USE_SSL="false"
    export LOCAL_DOMAIN="local"
    export SKIP_ACME="true"
    export ENABLE_DASHBOARD_API="true"
    
    print_success "Local deployment configured"
}

configure_public_deployment() {
    print_header "Public Internet Configuration"
    
    echo -e "\n${BLUE}Public deployment requirements:${NC}"
    echo -e "• ${YELLOW}Domain name${NC} (e.g., yourdomain.com)"
    echo -e "• ${YELLOW}DNS records${NC} pointing to your server"
    echo -e "• ${YELLOW}Port forwarding${NC} (80, 443) on your router/firewall"
    echo -e "• ${YELLOW}SSL certificates${NC} (Let's Encrypt)"
    echo -e ""
    
    while true; do
        read -p "Do you have a domain and DNS configured? (y/N): " dns_ready
        case $dns_ready in
            [Yy]*)
                print_info "Proceeding with public deployment"
                break
                ;;
            [Nn]*|"")
                print_warning "Public deployment requires:"
                echo -e "1. ${YELLOW}Domain registration${NC} (e.g., from Cloudflare, Namecheap, etc.)"
                echo -e "2. ${YELLOW}DNS A record${NC}: *.yourdomain.com -> $(curl -s ifconfig.me 2>/dev/null || echo "YOUR_PUBLIC_IP")"
                echo -e "3. ${YELLOW}Router port forwarding${NC}: External 80,443 -> Server $(hostname -I | awk '{print $1}'):80,443"
                echo -e ""
                read -p "Would you like to continue with local deployment instead? (Y/n): " switch_local
                case $switch_local in
                    [Nn]*)
                        print_info "Setup cancelled. Configure DNS and port forwarding, then re-run."
                        exit 0
                        ;;
                    *)
                        export DEPLOYMENT_MODE="local"
                        configure_local_deployment
                        return
                        ;;
                esac
                ;;
        esac
    done
    
    # Set public configuration
    export USE_SSL="true"
    export SKIP_ACME="false"
    export ENABLE_DASHBOARD_API="false"  # Disable API for security
    
    print_success "Public deployment configured"
}

print_header "Homelab Setup Script - Enhanced"

# Configure deployment mode first
configure_deployment_mode

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
    
    if [[ "$DEPLOYMENT_MODE" == "local" ]]; then
        print_info "Configuring .env for local deployment..."
        # Set local-friendly defaults
        sed -i 's/DOMAIN=.*/DOMAIN=local/' .env
        sed -i 's/ACME_EMAIL=.*/ACME_EMAIL=admin@local/' .env
        sed -i 's/CF_DNS_API_TOKEN=.*/CF_DNS_API_TOKEN=not-needed-for-local/' .env
        sed -i 's/TS_AUTHKEY=.*/TS_AUTHKEY=optional-for-local/' .env
        print_success "Configured .env for local deployment"
    else
        print_warning "Please edit .env file with your domain and API credentials!"
        read -p "Press enter when you've configured .env..."
    fi
fi

# Source environment variables
if [[ -f ".env" ]]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# Override domain if local deployment
if [[ "$DEPLOYMENT_MODE" == "local" ]]; then
    export DOMAIN="${LOCAL_DOMAIN}"
fi

# Validate required environment variables based on deployment mode
print_header "Validating Configuration"

if [[ "$DEPLOYMENT_MODE" == "public" ]]; then
    required_vars=("DOMAIN" "ACME_EMAIL" "CF_DNS_API_TOKEN")
    optional_vars=("TS_AUTHKEY")
    
    print_info "Validating public deployment configuration..."
else
    required_vars=("DOMAIN")
    optional_vars=("TS_AUTHKEY" "CF_DNS_API_TOKEN" "ACME_EMAIL")
    
    print_info "Validating local deployment configuration..."
fi

missing_vars=()

for var in "${required_vars[@]}"; do
    if [[ -z "${!var}" ]] || [[ "${!var}" == "example.com" ]] || [[ "${!var}" == *"change-me"* ]] || [[ "${!var}" == *"put-your"* ]]; then
        missing_vars+=("$var")
    fi
done

if [[ ${#missing_vars[@]} -gt 0 ]]; then
    print_error "Missing or placeholder values for: ${missing_vars[*]}"
    if [[ "$DEPLOYMENT_MODE" == "public" ]]; then
        print_error "Please edit .env file with real values for public deployment"
    else
        print_error "Configuration error for local deployment"
    fi
    exit 1
fi

# Validate domain formats and DNS (only for public deployment)
if [[ "$DEPLOYMENT_MODE" == "public" ]]; then
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
else
    print_info "Skipping DNS validation for local deployment"
fi

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

# Determine services based on deployment mode and environment
if [[ "$DEPLOYMENT_MODE" == "local" ]]; then
    if [[ "${SKIP_TAILSCALE:-false}" == "true" ]]; then
        SERVICES="traefik socket-proxy portainer whoami"
        print_info "Using private local deployment (without Tailscale due to LXC environment)"
    else
        SERVICES=""  # Use profiles when Tailscale is available
        print_info "Using private local deployment with Tailscale"
    fi
elif [[ "$DEPLOYMENT_MODE" == "tunnel" ]]; then
    SERVICES="traefik socket-proxy portainer whoami cloudflared"
    print_info "Using public tunnel deployment with Cloudflare tunnel"
else  # public direct
    if [[ "${SKIP_TAILSCALE:-false}" == "true" ]]; then
        SERVICES="traefik socket-proxy portainer whoami"
        print_info "Using public direct deployment (without Tailscale due to LXC environment)"
    else
        SERVICES=""  # Use profiles when Tailscale is available
        print_info "Using public direct deployment with all services"
    fi
fi

print_info "Using compose file: $COMPOSE_FILE"

# Create proxy network if it doesn't exist
if ! docker network ls | grep -q proxy; then
    print_info "Creating proxy network..."
    docker network create proxy
    print_success "Created proxy network"
fi

# Create volumes if they don't exist
if ! docker volume ls | grep -q portainer_data; then
    print_info "Creating portainer_data volume..."
    docker volume create portainer_data
    print_success "Created portainer_data volume"
fi

if [[ "$DEPLOYMENT_MODE" == "local" ]]; then
    docker compose -f "$COMPOSE_FILE" pull
else
    if [[ "${SKIP_TAILSCALE:-false}" == "true" ]]; then
        docker compose -f "$COMPOSE_FILE" pull $SERVICES
    else
        docker compose -f "$COMPOSE_FILE" --profile base pull
    fi
fi
print_success "Images pulled successfully"

# Start services
print_header "Starting Services"

if [[ "$DEPLOYMENT_MODE" == "local" ]]; then
    docker compose -f "$COMPOSE_FILE" up -d
    print_success "Local services started"
else
    if [[ "${SKIP_TAILSCALE:-false}" == "true" ]]; then
        docker compose -f "$COMPOSE_FILE" up -d $SERVICES
        print_success "Public services started (without Tailscale)"
    else
        docker compose -f "$COMPOSE_FILE" --profile base up -d
        print_success "Public services started"
    fi
fi

# Wait for services to be healthy
print_header "Waiting for Services"
print_info "Waiting for services to become healthy (this may take a minute)..."

# Wait for Traefik to be healthy
max_attempts=30
attempt=0
while [[ $attempt -lt $max_attempts ]]; do
    if docker compose -f "$COMPOSE_FILE" ps --format "{{.Health}}" traefik | grep -q "healthy"; then
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
    if [[ "$DEPLOYMENT_MODE" == "local" ]]; then
        if curl -s http://localhost:8080/ping >/dev/null 2>&1; then
            print_success "Traefik API responding on port 8080"
        else
            print_warning "Traefik API not responding on localhost:8080"
        fi
    else
        if curl -s http://localhost:8080/ping >/dev/null 2>&1; then
            print_success "Traefik API responding"
        else
            print_warning "Traefik API not responding on localhost:8080"
        fi
    fi
fi

# Check service status
print_header "Service Status"
docker compose -f "$COMPOSE_FILE" ps

if [[ "$DEPLOYMENT_MODE" == "local" ]]; then
    print_info "Local deployment - Tailscale not included"
elif [[ "${SKIP_TAILSCALE:-false}" == "true" ]]; then
    print_info "Note: Tailscale skipped due to LXC environment"
fi

# Show access information
print_header "Access Information"

if [[ "$DEPLOYMENT_MODE" == "local" ]]; then
    SERVER_IP=$(hostname -I | awk '{print $1}' || echo "127.0.0.1")
    
    echo -e "Your homelab is ready! Access your services via:"
    echo -e ""
    echo -e "${GREEN}Option 1: Direct IP Access${NC}"
    echo -e "• Portainer: ${GREEN}http://${SERVER_IP}:9000${NC}"
    echo -e "• Traefik Dashboard: ${GREEN}http://${SERVER_IP}:8080${NC}"
    echo -e ""
    echo -e "${GREEN}Option 2: Local Hostnames${NC} (add to /etc/hosts)"
    echo -e "• Portainer: ${GREEN}http://portainer.local${NC}"
    echo -e "• Traefik Dashboard: ${GREEN}http://traefik.local${NC}"
    echo -e "• Whoami (test): ${GREEN}http://whoami.local${NC}"
    echo -e ""
    echo -e "${YELLOW}To use local hostnames, add these lines to /etc/hosts:${NC}"
    echo -e "${BLUE}${SERVER_IP} portainer.local traefik.local whoami.local test.local${NC}"
    echo -e ""
    print_info "Local deployment - no DNS or port forwarding required!"
    
else
    echo -e "Your homelab is ready! Access your services at:"
    echo -e "• Portainer: ${GREEN}https://portainer.${DOMAIN}${NC}"
    echo -e "• Whoami (test): ${GREEN}https://whoami.${DOMAIN}${NC}"
    echo -e "• Traefik Dashboard: ${GREEN}https://traefik.${DOMAIN}${NC}"
    echo -e ""
    echo -e "Make sure your DNS records point to this server:"
    echo -e "• A/AAAA record: ${YELLOW}*.${DOMAIN}${NC} -> $(curl -s ifconfig.me 2>/dev/null || echo "YOUR_PUBLIC_IP")"
    echo -e ""
    print_warning "If using Cloudflare Tunnel, configure public hostnames in Zero Trust dashboard"
fi

print_success "Setup completed successfully!"

# Disable error trap for normal completion
trap - ERR

# Run validation
print_header "Running Setup Validation"
./validate.sh

print_header "Next Steps"

if [[ "$DEPLOYMENT_MODE" == "local" ]]; then
    SERVER_IP=$(hostname -I | awk '{print $1}' || echo "127.0.0.1")
    echo -e "1. ${YELLOW}Test your setup:${NC}"
    echo -e "   • Direct: ${GREEN}http://${SERVER_IP}:9000${NC} (Portainer)"
    echo -e "   • Hostname: ${GREEN}http://whoami.local${NC} (after updating /etc/hosts)"
    echo -e "2. ${YELLOW}Add local hostnames:${NC}"
    echo -e "   ${BLUE}echo '${SERVER_IP} portainer.local traefik.local whoami.local' >> /etc/hosts${NC}"
    echo -e "3. ${YELLOW}Monitor logs:${NC} Run 'docker compose -f $COMPOSE_FILE logs -f'"
    echo -e "4. ${YELLOW}Add more services:${NC} Modify $COMPOSE_FILE"
    echo -e "5. ${YELLOW}Upgrade to public:${NC} Re-run setup and choose public deployment"
    echo -e ""
    print_info "🏠 Local deployment complete - no internet setup required!"
    
else
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
    echo -e ""
    print_info "🌐 Public deployment - ensure DNS and port forwarding are configured!"
fi

echo ""
print_info "For troubleshooting, check: docker compose logs traefik"
print_info "For detailed diagnostics: ./health-check.sh"
if [[ "${SKIP_TAILSCALE:-false}" == "true" ]]; then
    print_info "LXC-specific guide: cat LXC-SETUP.md"
fi
