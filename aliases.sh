# Useful Docker Compose commands for homelab management
# Enhanced with backup, monitoring, and troubleshooting functions

# Basic operations
alias dc='docker compose'
alias dcup='docker compose --profile base up -d'
alias dcdown='docker compose down'
alias dcrestart='docker compose restart'
alias dcpull='docker compose pull'

# Profiles
alias dcbase='docker compose --profile base'
alias dcwp='docker compose --profile base --profile wordpress'
alias dcall='docker compose --profile base --profile wordpress --profile monitoring'

# Logs
alias dclogs='docker compose logs -f --tail=100'
alias dclogst='docker compose logs -f --tail=100 traefik'
alias dclogsp='docker compose logs -f --tail=100 portainer'

# Status and cleanup
alias dcps='docker compose ps'
alias dcstats='docker stats'
alias dcprune='docker system prune -f'
alias dcprunea='docker system prune -af'

# Enhanced backup and monitoring
alias backup='./backup.sh backup'
alias backup-list='./backup.sh list'
alias health='./health-check.sh'
alias monitor='./health-check.sh all'

# Security checks
alias check-perms='find traefik/acme -name "*.json" -exec ls -la {} \;'
alias fix-perms='chmod 600 traefik/acme/acme.json 2>/dev/null || echo "No acme.json file found"'

# Backup and restore
alias backup-volumes='docker run --rm -v /var/lib/docker/volumes:/backup -v $(pwd):/host alpine tar czf /host/volumes-backup-$(date +%Y%m%d-%H%M%S).tar.gz /backup'

# Enhanced troubleshooting functions
troubleshoot() {
    echo "=== Homelab Troubleshooting ==="
    echo "1. Service Status:"
    docker compose ps
    echo ""
    echo "2. Recent Errors (last 50 lines):"
    docker compose logs --tail=50 | grep -i "error\|fail\|fatal" || echo "No errors found"
    echo ""
    echo "3. Resource Usage:"
    docker stats --no-stream
    echo ""
    echo "4. Network Test:"
    curl -s http://localhost:8080/ping && echo "Traefik: OK" || echo "Traefik: FAIL"
}

# Enhanced health checks
check-health() {
    echo "=== Service Health Status ==="
    docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Health}}"
    echo ""
    echo "=== Traefik Health ==="
    curl -s http://localhost:8080/ping && echo "Traefik: OK" || echo "Traefik: FAIL"
    echo ""
    echo "=== SSL Certificate Status ==="
    if [[ -f "traefik/acme/acme.json" ]]; then
        echo "ACME file exists: $(ls -la traefik/acme/acme.json)"
        if [[ -s "traefik/acme/acme.json" ]]; then
            echo "ACME file has content (certificates present)"
        else
            echo "ACME file is empty (no certificates yet)"
        fi
    else
        echo "ACME file not found"
    fi
}

# Quick service restart
restart-service() {
    if [ -z "$1" ]; then
        echo "Usage: restart-service <service-name>"
        return 1
    fi
    docker compose restart "$1"
    docker compose logs -f --tail=20 "$1"
}

# Enhanced update function with backup
update-all() {
    echo "=== Updating Homelab Services ==="
    
    # Create backup before update
    echo "Creating backup before update..."
    ./backup.sh backup
    
    echo "Pulling latest images..."
    docker compose pull
    echo "Recreating services..."
    docker compose up -d
    echo "Pruning old images..."
    docker image prune -f
    
    # Health check after update
    echo "Waiting for services to be healthy..."
    sleep 30
    ./health-check.sh services
    
    echo "Update complete!"
    echo "If issues occur, restore with: ./backup.sh restore <backup-file>"
}

# Show service URLs for all configured domains
show-urls() {
    DOMAIN=$(grep DOMAIN .env | cut -d '=' -f2)
    DOMAIN2=$(grep DOMAIN2 .env | cut -d '=' -f2 2>/dev/null || echo "")
    DOMAIN3=$(grep DOMAIN3 .env | cut -d '=' -f2 2>/dev/null || echo "")
    
    echo "=== Service URLs ==="
    echo "Primary Domain ($DOMAIN):"
    echo "  Portainer:    https://portainer.$DOMAIN"
    echo "  Whoami:       https://whoami.$DOMAIN"
    echo "  Traefik:      https://traefik.$DOMAIN"
    
    if [[ -n "$DOMAIN2" && "$DOMAIN2" != "disabled.local" ]]; then
        echo ""
        echo "Secondary Domain ($DOMAIN2):"
        echo "  Portainer:    https://portainer.$DOMAIN2"
        echo "  Whoami:       https://whoami.$DOMAIN2"
        echo "  Traefik:      https://traefik.$DOMAIN2"
    fi
    
    if [[ -n "$DOMAIN3" && "$DOMAIN3" != "disabled.local" ]]; then
        echo ""
        echo "Third Domain ($DOMAIN3):"
        echo "  Portainer:    https://portainer.$DOMAIN3"
        echo "  Whoami:       https://whoami.$DOMAIN3"
        echo "  Traefik:      https://traefik.$DOMAIN3"
    fi
    
    echo ""
    echo "Local Traefik API: http://localhost:8080 (if exposed)"
}

# Monitor logs from all services
monitor-all() {
    docker compose logs -f --tail=50
}
