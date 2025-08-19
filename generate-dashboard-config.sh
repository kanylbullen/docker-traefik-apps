#!/bin/bash

# Load environment variables
source .env

# Generate dashboard.yml based on TRAEFIK_DASHBOARD_AUTH setting
if [ -n "$TRAEFIK_DASHBOARD_AUTH" ]; then
    # Authentication enabled
    cat > traefik/dynamic/dashboard.yml << YAML
http:
  middlewares:
    dashboard-auth:
      basicAuth:
        users:
          - "$TRAEFIK_DASHBOARD_AUTH"

  routers:
    traefik-dashboard:
      rule: "Host(\`traefik.$DOMAIN\`)"
      entryPoints: [websecure]
      service: api@internal
      tls:
        certresolver: letsencrypt
      middlewares:
        - compress@file
        - security-headers@file
        - dashboard-auth
YAML
    echo "Dashboard authentication ENABLED"
else
    # No authentication
    cat > traefik/dynamic/dashboard.yml << YAML
http:
  routers:
    traefik-dashboard:
      rule: "Host(\`traefik.$DOMAIN\`)"
      entryPoints: [websecure]
      service: api@internal
      tls:
        certresolver: letsencrypt
      middlewares:
        - compress@file
        - security-headers@file
YAML
    echo "Dashboard authentication DISABLED"
fi
