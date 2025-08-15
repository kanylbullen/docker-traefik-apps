# 📋 Homelab Project Structure

## 🏗️ File Organization

```
docker-traefik-apps/
├── 📄 docker-compose.yml          # Main service definitions
├── 📄 .env.example               # Configuration template
├── 📄 .gitignore                 # Git ignore rules
├── 📄 README.md                  # Documentation
├── 📄 setup.sh                   # Linux/macOS setup script
├── 📄 setup.ps1                  # Windows setup script
├── 📄 aliases.sh                 # Helper aliases and functions
├── 📁 traefik/
│   ├── 📄 traefik.yml            # Static Traefik configuration
│   ├── 📁 dynamic/
│   │   ├── 📄 common.yml         # Middlewares, TLS settings
│   │   └── 📄 dashboard.yml      # Dashboard routing config
│   └── 📁 acme/                  # Let's Encrypt certificates
└── 📁 cloudflared/
    └── 📄 README.md              # Cloudflare tunnel setup
```

## 🚀 Service Architecture

### Core Components

1. **Traefik** (Reverse Proxy)
   - Automatic HTTPS with Let's Encrypt
   - DNS-01 challenge via Cloudflare
   - Dynamic service discovery
   - Security headers and middleware

2. **Socket Proxy** (Security)
   - Read-only Docker socket access
   - Prevents direct socket exposure
   - Minimal permissions for Traefik

3. **Tailscale** (VPN Access)
   - Secure remote administration
   - Exit node capability
   - Mesh networking

4. **Cloudflare Tunnel** (Optional)
   - Zero-trust public access
   - No port forwarding required
   - Cloudflare network protection

5. **Portainer** (Container Management)
   - Web-based Docker UI
   - Stack and container management
   - Resource monitoring

## 🔧 Configuration System

### Environment Variables (.env)

```bash
# Core settings
DOMAIN=                    # Your domain name
ACME_EMAIL=               # Let's Encrypt email
TZ=UTC                    # Timezone

# Cloudflare integration
CF_DNS_API_TOKEN=         # DNS challenge token
CF_ZONE_API_TOKEN=        # Optional: Zone ID for performance

# Tailscale configuration
TS_AUTHKEY=               # Authentication key
TS_HOSTNAME=              # Node hostname
TS_ROUTES=                # Optional: Routes to advertise
TS_EXTRA_ARGS=            # Optional: Additional arguments

# Security
TRAEFIK_DASHBOARD_AUTH=   # Basic auth for dashboard
ADMIN_IP_WHITELIST=       # IP ranges for admin access

# Container images
TRAEFIK_IMAGE=            # Traefik version
PORTAINER_IMAGE=          # Portainer version
# ... other images
```

### Profile System

```bash
# Base infrastructure
docker compose --profile base up -d

# Add application profiles
docker compose --profile base --profile wordpress up -d
docker compose --profile base --profile monitoring up -d

# Multiple profiles
docker compose --profile base --profile wordpress --profile monitoring up -d
```

## 🔐 Security Model

### Defense in Depth

1. **Network Isolation**
   - Separate networks for different services
   - Socket proxy on isolated network
   - Internal-only communication where possible

2. **Access Control**
   - IP whitelisting for admin interfaces
   - Basic authentication for dashboards
   - Tailscale-only access options

3. **Transport Security**
   - TLS 1.2+ enforcement
   - Modern cipher suites
   - HSTS headers
   - Security headers middleware

4. **Container Security**
   - Read-only Docker socket access
   - Minimal container permissions
   - Health checks and restart policies

### Security Headers Applied

```yaml
# From traefik/dynamic/common.yml
headers:
  sslRedirect: true                    # Force HTTPS
  stsSeconds: 63072000                 # HSTS (2 years)
  stsIncludeSubdomains: true          # Include subdomains
  stsPreload: true                    # HSTS preload list
  browserXssFilter: true              # XSS protection
  contentTypeNosniff: true            # MIME type sniffing protection
  referrerPolicy: "strict-origin-when-cross-origin"
  permissionsPolicy: "..."            # Restrict browser features
  frameDeny: true                     # Clickjacking protection
```

## 🌐 Traffic Flow

```
Internet → Cloudflare → Traefik → Services
   ↓
Tailscale → Direct Access → Services
   ↓
Local Network → Traefik → Services
```

### Routing Examples

```bash
# Public access via Cloudflare Tunnel
Internet → tunnel.yourdomain.com → Cloudflare Edge → CF Tunnel → traefik:80 → service:port

# Direct access (port forwarding)
Internet → yourdomain.com:443 → Your Server → traefik:443 → service:port

# Tailscale access
Tailscale Client → homelab.tailnet → Your Server → traefik:443 → service:port
```

## 📊 Monitoring & Observability

### Built-in Monitoring

1. **Health Checks**
   - Traefik: `/ping` endpoint
   - Portainer: HTTP check on port 9000
   - Custom health checks for added services

2. **Logging**
   - Structured JSON logging
   - Configurable log levels
   - Access logs with filtering

3. **Metrics** (Optional)
   - Prometheus metrics endpoint
   - Service-level metrics
   - Infrastructure metrics

### Log Management

```bash
# View logs
docker compose logs -f traefik
docker compose logs -f --tail=100

# Log rotation (configured)
max-size: "10m"
max-file: "3"
```

## 🔄 Update Strategy

### Automated Updates

```bash
# Using helper scripts
update-all                    # Pull, recreate, cleanup

# Manual process
docker compose pull          # Pull latest images
docker compose up -d         # Recreate changed containers
docker image prune -f        # Clean old images
```

### Version Pinning

```bash
# In .env - pin specific versions for stability
TRAEFIK_IMAGE=traefik:v3.0
PORTAINER_IMAGE=portainer/portainer-ce:2.19.4

# Or use latest for development
TRAEFIK_IMAGE=traefik:latest
```

## 📦 Backup Strategy

### Critical Data

1. **Configuration Files**
   - `docker-compose.yml`
   - `.env` (encrypted storage recommended)
   - `traefik/` directory

2. **Certificates**
   - `traefik/acme/acme.json`
   - Automatic renewal via Let's Encrypt

3. **Persistent Data**
   - Docker volumes (`portainer_data`, `tailscale`)
   - Application data volumes

### Backup Script Example

```bash
#!/bin/bash
BACKUP_DIR="/backup/homelab/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Configuration
cp -r traefik/ "$BACKUP_DIR/"
cp docker-compose.yml .env "$BACKUP_DIR/"

# Volumes
docker run --rm -v /var/lib/docker/volumes:/source -v "$BACKUP_DIR":/backup \
  alpine tar czf /backup/volumes.tar.gz /source

echo "Backup completed: $BACKUP_DIR"
```

## 🚀 Expansion Guidelines

### Adding New Services

1. **Service Definition**
   - Use YAML anchors for common settings
   - Apply appropriate profile
   - Configure health checks

2. **Traefik Integration**
   - Add routing labels
   - Configure middleware
   - Set up TLS

3. **Security Considerations**
   - Network placement
   - Access restrictions
   - Data persistence

### Example Service Template

```yaml
  service-name:
    image: ${SERVICE_IMAGE}
    <<: [*default-restart, *default-logging, *proxy-network]
    depends_on:
      traefik:
        condition: service_healthy
    environment:
      <<: *common-env
      SERVICE_VAR: ${SERVICE_VAR}
    volumes:
      - service_data:/data
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.service.rule=Host(`service.${DOMAIN}`)"
      - "traefik.http.routers.service.entrypoints=websecure"
      - "traefik.http.routers.service.tls.certresolver=letsencrypt"
      - "traefik.http.routers.service.middlewares=compress@file,security-headers@file"
      - "traefik.http.services.service.loadbalancer.server.port=8080"
    profiles: [service-profile]
```

This architecture provides a solid foundation for a production homelab with security, scalability, and maintainability in mind.
