# 🔧 Troubleshooting Guide

This guide helps you diagnose and fix common issues with your homelab setup.

## 🚀 Quick Diagnostics

### Run the Health Check
```bash
./health-check.sh
```

### Check Service Status
```bash
source aliases.sh
check-health
```

### View Recent Logs
```bash
dclogs | tail -100
```

## 🔍 Common Issues and Solutions

### 1. Services Won't Start

**Symptoms:**
- `docker compose up -d` fails
- Services show as "Exited" status

**Diagnosis:**
```bash
docker compose ps
docker compose logs traefik
```

**Solutions:**
- **Port conflicts:** Check if ports 80/443 are in use
  ```bash
  sudo ss -tulpn | grep ':80\|:443'
  ```
- **Permission issues:** Fix ACME directory permissions
  ```bash
  sudo chown -R root:root traefik/acme
  sudo chmod 700 traefik/acme
  sudo chmod 600 traefik/acme/acme.json 2>/dev/null || true
  ```
- **Invalid configuration:** Validate environment variables
  ```bash
  docker compose config
  ```

### 2. SSL Certificate Issues

**Symptoms:**
- "Certificate not valid" errors
- HTTP works but HTTPS doesn't
- Empty `acme.json` file

**Diagnosis:**
```bash
# Check ACME file
ls -la traefik/acme/acme.json
cat traefik/acme/acme.json | jq . 2>/dev/null || echo "Invalid JSON or empty"

# Check Traefik logs for ACME issues
docker compose logs traefik | grep -i "acme\|certificate\|letsencrypt"
```

**Solutions:**
- **DNS issues:** Verify Cloudflare API token and domain settings
  ```bash
  # Test DNS resolution
  dig +short $DOMAIN
  dig +short _acme-challenge.$DOMAIN TXT
  ```
- **Rate limiting:** Let's Encrypt has rate limits. Wait and retry.
- **Reset certificates:** Remove and recreate ACME file
  ```bash
  docker compose down
  rm -f traefik/acme/acme.json
  touch traefik/acme/acme.json
  chmod 600 traefik/acme/acme.json
  docker compose up -d
  ```

### 3. Services Not Accessible

**Symptoms:**
- "This site can't be reached"
- Timeout errors
- Services running but not responding

**Diagnosis:**
```bash
# Check Traefik dashboard
curl -v http://localhost:8080/api/http/routers

# Test internal connectivity
docker compose exec traefik wget -qO- http://portainer:9000/ || echo "Internal connection failed"

# Check DNS resolution
nslookup portainer.$DOMAIN
```

**Solutions:**
- **DNS configuration:** Ensure `*.${DOMAIN}` points to your server
- **Firewall issues:** Check if ports are blocked
  ```bash
  sudo ufw status
  sudo iptables -L
  ```
- **Network issues:** Restart networking
  ```bash
  docker compose down
  docker network prune -f
  docker compose up -d
  ```

### 4. Traefik Dashboard Not Accessible

**Symptoms:**
- 401 Unauthorized
- 403 Forbidden
- Connection refused

**Diagnosis:**
```bash
# Check auth configuration
echo $TRAEFIK_DASHBOARD_AUTH

# Test auth string
echo "admin:password" | htpasswd -ni admin
```

**Solutions:**
- **Authentication issues:** Regenerate auth string
  ```bash
  # Generate new auth string
  htpasswd -nb admin 'your-password'
  # Update in .env file: TRAEFIK_DASHBOARD_AUTH=admin:$apr1$...
  ```
- **IP allowlist:** Check if your IP is allowed
  ```bash
  # Check your current IP
  curl ifconfig.me
  # Verify it's in the allowed range (100.64.0.0/10 for Tailscale)
  ```

### 5. Tailscale Connection Issues

**Symptoms:**
- Can't access services via Tailscale IP
- Tailscale service not starting

**Diagnosis:**
```bash
docker compose logs tailscale
```

**Solutions:**
- **Auth key expired:** Generate new Tailscale auth key
- **Network conflicts:** Check for IP conflicts
  ```bash
  ip route show
  ```
- **Restart Tailscale:**
  ```bash
  docker compose restart tailscale
  ```

### 6. Cloudflare Tunnel Issues

**Symptoms:**
- Services not accessible via public domain
- Tunnel disconnects frequently

**Diagnosis:**
```bash
docker compose logs cloudflared
```

**Solutions:**
- **Token issues:** Verify `CLOUDFLARED_TOKEN` in `.env`
- **Public hostname configuration:** Check Cloudflare Zero Trust dashboard
- **Restart tunnel:**
  ```bash
  docker compose restart cloudflared
  ```

## 🛠 Advanced Troubleshooting

### Docker System Issues

**Clean up Docker system:**
```bash
# Stop all services
docker compose down

# Clean up everything
docker system prune -af
docker volume prune -f

# Restart Docker daemon (if needed)
sudo systemctl restart docker

# Restart services
docker compose up -d
```

### Network Debugging

**Test internal Docker networks:**
```bash
# List networks
docker network ls

# Inspect proxy network
docker network inspect proxy

# Test connectivity between containers
docker compose exec traefik ping socket-proxy
```

### Certificate Debugging

**Manual certificate request:**
```bash
# Enter Traefik container
docker compose exec traefik sh

# Manual ACME request (inside container)
traefik acme --email=$ACME_EMAIL --domains=$DOMAIN
```

### Configuration Validation

**Validate Docker Compose:**
```bash
# Check syntax
docker compose config

# Validate specific service
docker compose config traefik
```

**Validate Traefik configuration:**
```bash
# Check static config
docker compose exec traefik traefik version

# Check dynamic config
curl -s http://localhost:8080/api/http/routers | jq .
```

## 📊 Monitoring and Logs

### Continuous Monitoring
```bash
# Monitor all logs
monitor-all

# Monitor specific service
docker compose logs -f traefik

# Monitor system resources
watch -n 5 'docker stats --no-stream'
```

### Log Analysis
```bash
# Find errors in last hour
docker compose logs --since 1h | grep -i "error\|fail\|fatal"

# Certificate-related logs
docker compose logs traefik | grep -i "certificate\|acme\|letsencrypt"

# Network-related logs
docker compose logs traefik | grep -i "timeout\|connection\|network"
```

## 🆘 Emergency Recovery

### Complete Reset
```bash
# Backup current state
./backup.sh backup

# Stop everything
docker compose down --remove-orphans

# Remove volumes (WARNING: This deletes all data!)
docker volume rm $(docker volume ls -q | grep $(basename $(pwd)))

# Clean up networks
docker network prune -f

# Restart from scratch
./setup.sh
```

### Restore from Backup
```bash
# List available backups
./backup.sh list

# Restore specific backup
./backup.sh restore backups/homelab-backup-YYYYMMDD-HHMMSS.tar.gz
```

## 📞 Getting Help

### Gather Information for Support
```bash
# Create support bundle
./health-check.sh all > support-info.txt
docker compose logs --tail=500 >> support-info.txt
docker version >> support-info.txt
docker compose version >> support-info.txt
```

### Useful Commands for Debugging
```bash
# System information
uname -a
docker info
df -h

# Network information
ip addr show
ip route show
ss -tulpn

# Service-specific debugging
docker compose exec traefik traefik version
docker compose exec portainer portainer --version
```

## 🔒 Security Checklist

After resolving issues, ensure security:

```bash
# Check file permissions
find traefik/ -type f -exec ls -la {} \;

# Verify no sensitive data in logs
docker compose logs | grep -i "password\|token\|secret" || echo "Clean"

# Check for exposed ports
nmap -sT localhost

# Verify SSL configuration
curl -I https://traefik.$DOMAIN
```
