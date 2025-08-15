# overview

minimal, opinionated docker-compose stack for a small self-hosted environment with:

- traefik (reverse proxy, let's encrypt via cloudflare dns)
- tailscale (remote admin over your tailnet)
- cloudflared (cloudflare tunnel; optional, for zero trust/public access without opening ports)
- portainer (docker ui)
- hello-world service (traefik/whoami)

uses compose **profiles** so you can enable base and later add roles (wordpress, mysql, postgres, vaultwarden, plex, jellyfin, etc.). includes docker-socket-proxy to avoid giving traefik full rw access to the docker socket.

---

## repo layout

```
.
├─ .env.example
├─ docker-compose.yml
├─ traefik/
│  ├─ traefik.yml                # static config
│  ├─ dynamic/
│  │  ├─ common.yml             # middlewares, tls options
│  │  └─ dashboard.yml          # optional: secure dashboard router (basic auth)
│  └─ acme/                     # letsencrypt storage (created at runtime)
├─ cloudflared/
│  └─ README.md                 # quick notes for tunnel token method
└─ README.md
```

---

## quickstart

1. copy env and edit secrets

```bash
cp .env.example .env
```

set at minimum:

- `DOMAIN=example.com`
- `ACME_EMAIL=you@example.com`
- `CF_DNS_API_TOKEN=` (cloudflare api token with **zone.dns.edit** on your zone)
- `TS_AUTHKEY=` (tailscale **ephemeral** auth key is fine)
- `CLOUDFLARED_TOKEN=` (only if you plan to use cloudflare tunnel)

2. prepare traefik storage (permissions matter)

```bash
mkdir -p traefik/acme
# acme.json will be created inside this dir by traefik; directory must be writable by the container
chmod 700 traefik/acme
```

3. bring up base profile

```bash
docker compose --profile base up -d
```

4. test

- portainer: https://portainer.${DOMAIN}
- hello world: https://whoami.${DOMAIN}
- (optional) dashboard: see `traefik/dynamic/dashboard.yml` and uncomment if you want it public; otherwise reach it via tailscale on https://traefik.${DOMAIN}

5. cloudflare dns

- if **not** using cloudflared: create `A`/`AAAA` records for `portainer.${DOMAIN}`, `whoami.${DOMAIN}` (or a wildcard `*.${DOMAIN}`) pointing to your public ip.
- if using **cloudflared tunnel**: after you set `CLOUDFLARED_TOKEN`, create public hostnames in cloudflare zero trust and point them to `http://traefik:80`. the container is on the same `proxy` network so `traefik` resolves.

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
