FROM caddy:2.5.1-builder-alpine AS builder
RUN xcaddy build --with github.com/caddy-dns/cloudflare
FROM caddy:latest
COPY --from=builder /usr/bin/caddy /usr/bin/caddy