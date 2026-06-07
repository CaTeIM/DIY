# AGENTS.md

This repository's conventions for AI agents live in **[CLAUDE.md](./CLAUDE.md)** — read it before
creating or modifying guides (`docs/*.md`), stacks (`assets/stacks/*.yml`), or the `README.md`.

Quick reference:

- Documentation is written in **Brazilian Portuguese** (keep all accents). Commits are in **English**
  (Conventional Commits).
- **Deploy is via Portainer Stack** — never lead with `docker compose` (it's only an SSH fallback).
- Persist data under **`/srv/<service>`**; secrets via `.env` / Portainer Environment variables
  (never committed — `.env` is gitignored).
- Stacks: `restart: unless-stopped`, `security_opt: no-new-privileges`, **pinned image tags**,
  `${VAR}` secrets, `container_name`, DB `healthcheck` + `depends_on: service_healthy`.
- External access via **Cloudflare Tunnel** (bare-metal on the host; container serves plain HTTP,
  Cloudflare terminates TLS).

See **[CLAUDE.md](./CLAUDE.md)** for the full conventions and the "add a new service" checklist.
