# DIY — Repository Conventions (for AI agents)

This repo is a personal collection of self-hosting / home-lab / IoT "do it yourself" guides.
The content is **documentation + Infrastructure-as-Code** (Docker Compose stacks), **not** application
source code: there is no build, test runner, or formatter. Optimize edits for clarity and for
matching the existing guides, not for software-engineering ceremony.

## Language (critical)

- All **documentation content is written in Brazilian Portuguese (pt-BR)** with full, correct
  accentuation (ã, ç, é, ô, …). **Never** strip or ASCII-fold accents.
- Code identifiers, env var names, shell commands, image names, and config keys stay in their
  original form.
- **Commit messages are in English** (Conventional Commits — see below).

## Repository layout

- `docs/<service>.md` — one guide per project/service (the main deliverable).
- `assets/stacks/<service>.yml` — the Docker Compose stack referenced by the guide.
- `assets/configs/<service>-*.{yml,js,…}` — copy-paste config templates referenced by guides.
- `assets/datasheets/` — hardware datasheets (PDF).
- `README.md` — the project index table; every guide has a row.
- `.env` is **gitignored** — never commit secrets.

## Deploy: Portainer first (do NOT lead with `docker compose`)

The canonical deploy path in this repo is a **Portainer Stack**. Document it as the primary steps:

1. Portainer → **Stacks** → **Add Stack**.
2. **Nome:** `<service>`.
3. Paste the YAML from `assets/stacks/<service>.yml` into the **Web editor**.
4. Add secrets under the **Environment variables** tab (NOT an `.env` file inside Portainer).
5. **Deploy the stack**.

- `docker compose -f <service>.yml up -d` is documented **only** as a secondary "via SSH"
  alternative — never as the headline step.
- Always tell the user to create the `/srv/<service>` folders via SSH **before** deploying the
  Stack (otherwise Docker creates them as `root` and a non-root container UID can't write).

## Docker Compose stack conventions

Match the existing stacks (`assets/stacks/forgejo.yml`, `firefly.yml`, `n8n.yml`, …):

- `services:` at the top; every service has an explicit `container_name`.
- `restart: unless-stopped` (the repo default — **not** `always`).
- `security_opt: [no-new-privileges:true]`.
- Persist data with **bind mounts under `/srv/<service>/…`** (never named volumes).
- Secrets via `${VAR}` interpolation — **never hardcode** passwords/keys/tokens.
- `TZ=America/Sao_Paulo` (and `GENERIC_TIMEZONE` for apps that schedule/cron).
- Multi-service stacks use a dedicated named bridge network `<service>-net`; single-container
  stacks may use `network_mode: bridge`.
- When a service depends on a database, give the DB a `healthcheck` (e.g. `pg_isready`) and gate
  the app with `depends_on: { <db>: { condition: service_healthy } }`.
- **Image tags:** most stacks track a rolling tag (`:latest` / `:stable`); to update, use Portainer's
  **"Re-pull image and redeploy"** (a plain redeploy reuses the cache). Pin a specific version only
  when you want reproducibility or migrations are sensitive (e.g. `forgejo` pins `:15.0.2`).
- Optional `logging` json-file with `max-size`/`max-file` for chatty services.
- **One database instance per stack** (self-contained). Do not share one Postgres across projects
  unless explicitly requested; if so, use a separate DATABASE + ROLE per app and never a shared
  superuser.

## External access (Cloudflare Tunnel)

- `cloudflared` runs **bare metal on the host**; it is **not** part of the stack. Publish a hostname
  in the Cloudflare One (Zero Trust) panel → Tunnels → Public Hostname → service
  `http://localhost:<port>`.
- Cloudflare terminates TLS; the container serves **plain HTTP**. Set the app's public-URL env vars
  (e.g. `WEBHOOK_URL`, `*_BASE_URL`, `APP_URL`, `OCIS_URL`) to the `https://…` public address and
  keep the container's own protocol as `http` (it has no certificate).

## /srv data & permissions

- All persistent data under `/srv/<service>/…`. Backing up `/srv/<service>` (plus the `.env` /
  encryption keys) gives a complete snapshot.
- If the container runs as a non-root user (e.g. UID 1000 `node`), run
  `sudo chown -R <uid>:<gid> /srv/<service>/<data>` **before** first boot to avoid `EACCES`.

## Documentation style (per guide)

- Title `# <emoji> <Service> (…)` + a one-paragraph intro stating the purpose.
- A **Pré-requisito** line linking `./portainer-debian.md` when Docker is required.
- A line: "A stack pronta está em [`assets/stacks/<service>.yml`](../assets/stacks/<service>.yml)".
- Numbered sections "## Parte N: …" walking host prep → secrets → stack/deploy → config →
  update → backup.
- Blockquote callouts for tips/warnings (`> ⚠️`, `> ℹ️`, `> 💾`, or GitHub `> [!WARNING]` /
  `> [!NOTE]`).
- End with a **Troubleshooting** table, **Notas Importantes**, an **Acessos** table, and
  **Referências**.
- File references use **relative Markdown links** (`./other.md`, `../assets/stacks/x.yml`); internal
  anchors as `#parte-n-…`.

## Adding a new service (checklist)

1. `assets/stacks/<service>.yml` — the stack (conventions above).
2. `docs/<service>.md` — the guide (Portainer-first).
3. `README.md` — add a row to the Projetos table, alphabetical by name.
4. Configs (if any) → `assets/configs/<service>-*`.

## Commits

- **Conventional Commits, in English**, lowercase scope = service name.
  Examples from history: `docs(forgejo): add self-hosted git server guide…`,
  `docs(ai-memory): native Windows hook command…`.
- Never commit secrets; `.env` is gitignored.

## Global rule reminder

This repo lives inside a Google Drive folder. **Never** attribute stray files or working-tree
changes to "Google Drive sync" — find the real cause (a command, a build step, a tool output) or
say you don't know.
