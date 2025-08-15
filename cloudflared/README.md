### cloudflared quick notes

this compose uses the token-based method:

- create a tunnel in cloudflare zero trust → networks → tunnels.
- copy the `tunnel token` and put it in `.env` as `CLOUDFLARED_TOKEN`.
- create **public hostnames** in the same ui and point them to `http://traefik:80`.
- the container joins the `proxy` network, so `traefik` resolves by name.
