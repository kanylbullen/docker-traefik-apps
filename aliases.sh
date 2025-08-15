# Useful Docker Compose commands for homelab management

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

# Backup and restore
alias backup-volumes='docker run --rm -v /var/lib/docker/volumes:/backup -v $(pwd):/host alpine tar czf /host/volumes-backup-$(date +%Y%m%d-%H%M%S).tar.gz /backup'

# Health checks
check-health() {
    echo "=== Service Health Status ==="
    docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Health}}"
    echo ""
    echo "=== Traefik Health ==="
    curl -s http://localhost:8080/ping && echo "Traefik: OK" || echo "Traefik: FAIL"
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

# Update all services
update-all() {
    echo "Pulling latest images..."
    docker compose pull
    echo "Recreating services..."
    docker compose up -d
    echo "Pruning old images..."
    docker image prune -f
    echo "Update complete!"
}

# Show service URLs
show-urls() {
    DOMAIN=$(grep DOMAIN .env | cut -d '=' -f2)
    echo "=== Service URLs ==="
    echo "Portainer:    https://portainer.$DOMAIN"
    echo "Whoami:       https://whoami.$DOMAIN"
    echo "Traefik:      https://traefik.$DOMAIN"
    echo "Local Traefik: http://localhost:8080 (if exposed)"
}

# Monitor logs from all services
monitor-all() {
    docker compose logs -f --tail=50
}
