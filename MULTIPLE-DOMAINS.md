# 🌐 Multiple Domain Configuration Guide

This guide explains how to configure your homelab to work with multiple domains.

## 📋 Overview

Your setup supports multiple domains through:
- **Wildcard SSL certificates** for each domain
- **Multiple router configurations** in Traefik
- **Flexible service access** across domains

## 🔧 Configuration Steps

### Step 1: Configure Domains in .env

Edit your `.env` file to include multiple domains:

```bash
# Primary domain (required)
DOMAIN=yourdomain.com

# Additional domains (optional)
DOMAIN2=anotherdomain.com
DOMAIN3=thirddomain.org

# Same email for all certificates
ACME_EMAIL=you@yourdomain.com

# Same Cloudflare token (must have access to all domains)
CF_DNS_API_TOKEN=your-cloudflare-token
```

### Step 2: DNS Configuration

For each domain, configure these DNS records:

```
Type    Name    Content
A       *       YOUR_SERVER_IP
A       @       YOUR_SERVER_IP
```

**Example for yourdomain.com:**
- `*.yourdomain.com` → `YOUR_SERVER_IP`
- `yourdomain.com` → `YOUR_SERVER_IP`

**Repeat for each additional domain.**

### Step 3: Cloudflare Token Permissions

Your Cloudflare API token needs access to **all domains**:

1. Go to [Cloudflare API Tokens](https://dash.cloudflare.com/profile/api-tokens)
2. Create Custom Token with:
   - **Permissions:** Zone:Zone:Read, Zone:DNS:Edit
   - **Zone Resources:** Include All zones (or specific zones for each domain)

### Step 4: Enable Multiple Domain Services

Uncomment the additional domain configurations in `docker-compose.yml`:

```yaml
# For Portainer
labels:
  # Primary domain
  - "traefik.http.routers.portainer.rule=Host(`portainer.${DOMAIN}`)"
  # Secondary domain (uncomment these lines)
  - "traefik.http.routers.portainer-alt.rule=Host(`portainer.${DOMAIN2}`)"
  - "traefik.http.routers.portainer-alt.entrypoints=websecure"
  - "traefik.http.routers.portainer-alt.tls.certresolver=letsencrypt"
```

### Step 5: Enable Multiple Dashboard Access

Uncomment the additional dashboard routes in `traefik/dynamic/dashboard.yml`:

```yaml
# Additional domains
traefik-dashboard-alt:
  rule: "Host(`traefik.${DOMAIN2}`)"
  entryPoints: [websecure]
  service: api@internal
  tls:
    certresolver: letsencrypt
  middlewares:
    - compress@file
    - security-headers@file
    - dashboard-auth
    - admin-allowlist@file
```

## 🚀 Running with Multiple Domains

1. **Configure your .env:**
   ```bash
   nano .env
   # Add DOMAIN2=anotherdomain.com
   # Add DOMAIN3=thirddomain.org
   ```

2. **Uncomment service configurations:**
   ```bash
   nano docker-compose.yml
   # Uncomment the alt router configurations
   ```

3. **Run the setup:**
   ```bash
   ./setup.sh
   ```

## 🔍 Verification

After setup, verify each domain works:

```bash
# Check certificate generation
./health-check.sh certs

# Test each domain
curl -I https://portainer.yourdomain.com
curl -I https://portainer.anotherdomain.com
curl -I https://portainer.thirddomain.org

# Show all configured URLs
source aliases.sh && show-urls
```

## 🎯 Use Cases

### 1. Development vs Production
```bash
DOMAIN=myapp-prod.com      # Production
DOMAIN2=myapp-dev.com      # Development
```

### 2. Multiple Organizations
```bash
DOMAIN=company1.com        # Company 1
DOMAIN2=company2.org       # Company 2
```

### 3. Different Service Categories
```bash
DOMAIN=admin.mylab.com     # Admin services
DOMAIN2=apps.mylab.com     # Applications
DOMAIN3=monitoring.mylab.com # Monitoring
```

## 🔧 Advanced Configuration

### Custom Service Routing per Domain

You can route different services to different domains:

```yaml
# Example: Different services per domain
whoami:
  labels:
    # Only on primary domain
    - "traefik.http.routers.whoami.rule=Host(`test.${DOMAIN}`)"

some-app:
  labels:
    # Only on secondary domain
    - "traefik.http.routers.app.rule=Host(`app.${DOMAIN2}`)"
```

### Domain-Specific Middleware

Create domain-specific security rules:

```yaml
# In traefik/dynamic/common.yml
http:
  middlewares:
    # Stricter rules for production domain
    prod-security:
      headers:
        sslRedirect: true
        stsSeconds: 31536000
        
    # Relaxed rules for development domain
    dev-security:
      headers:
        sslRedirect: true
        stsSeconds: 86400
```

## 🛠️ Troubleshooting Multiple Domains

### Certificate Issues

1. **Check certificate generation:**
   ```bash
   docker compose logs traefik | grep -i "certificate\|acme"
   ```

2. **Verify domain DNS:**
   ```bash
   dig +short yourdomain.com
   dig +short anotherdomain.com
   ```

3. **Test certificate validity:**
   ```bash
   echo | openssl s_client -connect portainer.yourdomain.com:443 2>/dev/null | openssl x509 -noout -subject -dates
   ```

### Rate Limiting

Let's Encrypt has rate limits:
- **50 certificates per registered domain per week**
- **5 duplicate certificates per week**

If you hit limits:
1. Wait for the limit to reset
2. Use staging environment first:
   ```yaml
   # In traefik.yml (temporarily)
   caServer: https://acme-staging-v02.api.letsencrypt.org/directory
   ```

### DNS Propagation

If DNS isn't working:
1. Check TTL settings (lower for testing)
2. Use different DNS servers to test:
   ```bash
   dig @8.8.8.8 portainer.yourdomain.com
   dig @1.1.1.1 portainer.yourdomain.com
   ```

## 📊 Monitoring Multiple Domains

The enhanced health check supports multiple domains:

```bash
# Check all domains
./health-check.sh network

# Monitor certificate expiry
./health-check.sh certs

# Show all service URLs
source aliases.sh && show-urls
```

## 🔐 Security Considerations

1. **Same Cloudflare token:** One token has access to all domains
2. **IP allowlisting:** Apply consistently across domains
3. **Certificate storage:** All certificates in same acme.json file
4. **Backup strategy:** Include all domain configurations

## 💡 Pro Tips

1. **Test staging first:** Use a test subdomain before production
2. **Monitor certificates:** Set up alerts for expiry
3. **Document domains:** Keep a list of what each domain is for
4. **Backup configurations:** Regular backups of traefik configs
5. **Use consistent naming:** Keep service names consistent across domains
