# 🏠 Docker Homelab Template

A production-ready, security-focused Docker Compose stack for quick homelab deployment with:

- **Traefik** - Reverse proxy with automatic HTTPS (Let's Encrypt via Cloudflare DNS)
- **Tailscale** - Secure remote access to your homelab
- **Cloudflare Tunnel** - Zero-trust public access (optional)
- **Portainer** - Docker management UI
- **Socket Proxy** - Secure Docker socket access for Traefik

## ✨ Features

- 🔒 **Security-first** - Docker socket proxy, security headers, TLS 1.2+
- 🏗️ **Modular** - Profile-based architecture for easy expansion
- 🚀 **Quick deployment** - Automated setup scripts for Linux/Windows
- 📱 **Production-ready** - Health checks, logging, restart policies
- 🌐 **DNS challenge** - Wildcard certificates with Cloudflare
- 🔧 **Easy management** - Helper scripts and aliases

## 🚀 Quick Start

### 1. Clone and Configure

```bash
git clone <your-repo-url>
cd docker-traefik-apps

# Copy and edit configuration
cp .env.example .env
# Edit .env with your settings
```

### 2. Required Configuration

Edit `.env` with these minimum values:

```bash
DOMAIN=yourdomain.com
ACME_EMAIL=you@yourdomain.com
CF_DNS_API_TOKEN=your_cloudflare_token
TS_AUTHKEY=your_tailscale_auth_key
TRAEFIK_DASHBOARD_AUTH=admin:$apr1$encoded_password
```

### 3. Deploy

**Linux/macOS:**
```bash
chmod +x setup.sh
./setup.sh
```

**Windows (PowerShell):**
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
.\setup.ps1
```

**Manual:**
```bash
# Create directories
mkdir -p traefik/acme && chmod 700 traefik/acme

# Start services
docker compose --profile base up -d
```

## 🌐 Access Your Services

After deployment, access your services at:

- **Portainer**: `https://portainer.yourdomain.com`
- **Whoami (test)**: `https://whoami.yourdomain.com` 
- **Traefik Dashboard**: `https://traefik.yourdomain.com`

## 📋 Profiles & Management

### Base Profile
```bash
docker compose --profile base up -d
```
Includes: Traefik, Portainer, Tailscale, Cloudflared, Socket-proxy

### Helper Scripts
Source the aliases for easier management:
```bash
source aliases.sh

# Now you can use:
dcup          # Start base profile
dclogs        # View all logs
dcps          # Show running services
update-all    # Update all services
show-urls     # Display service URLs
```

## 🔐 Security Features

- ✅ Docker socket proxy (read-only access)
- ✅ Security headers (HSTS, XSS protection, etc.)
- ✅ TLS 1.2+ with modern cipher suites
- ✅ IP whitelisting for admin services
- ✅ Basic auth for Traefik dashboard
- ✅ Wildcard certificates

## 🌍 DNS Configuration

### Option 1: Direct (Public IP)
Create DNS records pointing to your server:
```
A    *.yourdomain.com  -> YOUR_PUBLIC_IP
```

### Option 2: Cloudflare Tunnel
1. Create tunnel in Cloudflare Zero Trust
2. Add `CLOUDFLARED_TOKEN` to `.env`
3. Configure public hostnames pointing to `http://traefik:80`

---

## adding roles later (profiles)

keep everything in one compose file and tag services with profiles. examples you can append:

```yaml
# wordpress + mariadb
  mariadb:
    image: mariadb:11
    environment:
      - MYSQL_ROOT_PASSWORD=change-me
      - MYSQL_DATABASE=wp
      - MYSQL_USER=wp
      - MYSQL_PASSWORD=change-me
    volumes:
      - mariadb:/var/lib/mysql
    <<: [*default-restart, *default-logging]
    profiles: [wordpress]

  wordpress:
    image: wordpress:6-apache
    environment:
      - WORDPRESS_DB_HOST=mariadb
      - WORDPRESS_DB_USER=wp
      - WORDPRESS_DB_PASSWORD=change-me
      - WORDPRESS_DB_NAME=wp
    depends_on: [mariadb]
    <<: [*default-restart, *default-logging, *proxy-network]
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.wordpress.rule=Host(`wp.${DOMAIN}`)"
      - "traefik.http.routers.wordpress.entrypoints=websecure"
      - "traefik.http.routers.wordpress.tls.certresolver=letsencrypt"
      - "traefik.http.routers.wordpress.middlewares=compress@file,security-headers@file"
      - "traefik.http.services.wordpress.loadbalancer.server.port=80"
    profiles: [wordpress]

volumes:
  mariadb:
```

run it with:

```bash
docker compose --profile base --profile wordpress up -d
```

---

## notes & tips

- prefer wildcard certs: uncomment the `domains:` block in `traefik.yml` to pre-issue `*.${DOMAIN}`. faster first-hit for new services.
- keep tokens out of git: `.env` should be gitignored. if you want stronger hygiene, load secrets from a file managed by sops/age and export them before `docker compose`.
- docker-socket-proxy is on by default. if you want absolute minimum, you can remove it and set `providers.docker.endpoint` to `unix:///var/run/docker.sock`, but that's weaker from a security pov.
- healthchecks are included for traefik; add them to apps you care about.
- updates: consider **diun** for notifications or **watchtower** for auto-updates (with a maintenance window). keep base stable.
- backups: snapshot volumes (`/var/lib/docker/volumes/...`) with restic or your existing backup flow. portainer stacks are declarative—commit your compose files.
- tailscale-only admin: for sensitive services (portainer, traefik dashboard), either keep their routers commented or add an ip whitelist middleware to only allow your tailnet.
- resource caps: add `deploy.resources.limits` if you run this on small lxc/vm.
- logging: centralize later with loki/promtail + grafana if you want observability.
