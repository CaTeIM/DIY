# 🔗 n8n (Automação de Workflows via Docker + PostgreSQL + Cloudflare Tunnel)

Este guia sobe o **n8n** — uma plataforma de automação de workflows self-hosted (alternativa ao Zapier/Make), onde você conecta APIs, webhooks, bancos, IA e scripts num editor visual. É a base do projeto **radar** e dos próximos que vierem. A stack usa **Docker Compose** com **PostgreSQL dedicado**, exposição via **Cloudflare Tunnel** e tudo centralizado em `/srv`, no mesmo padrão dos outros guias do repo.

**Pré-requisito:** Docker Engine + Docker Compose instalados. Se ainda não tem, veja o guia [Docker + Portainer no Debian](./portainer-debian.md). Para o acesso externo, assume-se um `cloudflared` já rodando **bare metal no host** (você só adiciona o subdomínio pelo painel do Cloudflare One — ver [Parte 4](#parte-4-acesso-externo-via-cloudflare-tunnel)).

A stack pronta está em [`assets/stacks/n8n.yml`](../assets/stacks/n8n.yml).

## Arquitetura

```
┌─ INTERNET / SERVIÇOS EXTERNOS ─────────────────────────────────────┐
│                                                                    │
│  Navegador / Webhook (Telegram, GitHub, Stripe…)                   │
│  ──► https://n8n.exemplo.com                                       │
│  ──► Cloudflare Edge (termina o TLS)                               │
│  ──► Tunnel (cloudflared bare metal no host)                       │
│  ──► localhost:5678 ──► n8n (HTTP puro) ──► PostgreSQL (n8n-db)    │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

**Portas no host:**

| Porta Host | Porta Container | Uso                                                 |
| :--------- | :-------------- | :-------------------------------------------------- |
| `5678/tcp` | `5678`          | n8n (Web UI + API + Webhooks) — alvo do `cloudflared` e da LAN |

> O PostgreSQL **não** expõe porta no host (só conversa com o n8n pela rede interna `n8n-net`), reduzindo a superfície de ataque.

---

## Parte 1: Preparar as Pastas de Dados

Seguindo o padrão `/srv`, crie as pastas onde o n8n e o banco vão persistir os dados.

```bash
sudo mkdir -p /srv/n8n/data /srv/n8n/db

# o container do n8n roda como o usuario 'node' (UID/GID 1000);
# a pasta de dados precisa ser dele, senao da EACCES ao gravar /home/node/.n8n/config
sudo chown -R 1000:1000 /srv/n8n/data
```

> `data` é a pasta `/home/node/.n8n` do container — guarda a **chave de criptografia**, logs e assets de source control. `db` guarda o PostgreSQL (workflows, execuções e credenciais). Faça backup de `/srv/n8n` inteiro (com os containers parados) e você tem tudo — ver [Parte 8](#parte-8-backup).

## Parte 2: Configurar os Segredos

A stack lê **três variáveis** de ambiente — o domínio público e dois segredos (nunca hardcode no compose). Crie/edite o arquivo `.env` ao lado do compose:

```bash
# .env
N8N_HOST=n8n.seudominio.com                       # so o hostname, sem https://
N8N_DB_PASSWORD=uma-senha-forte-para-o-postgres
N8N_ENCRYPTION_KEY=cole-aqui-a-chave-gerada-abaixo
```

> 🌐 **O domínio fica num lugar só:** o compose reaproveita `N8N_HOST` em `WEBHOOK_URL` e `N8N_EDITOR_BASE_URL` via `${N8N_HOST}` (Parte 4). Trocar de domínio = trocar uma linha.

**Gere a `N8N_ENCRYPTION_KEY`** com uma string aleatória forte:

```bash
openssl rand -base64 32
```

> ⚠️ **A `N8N_ENCRYPTION_KEY` é a coisa mais importante deste guia.** Ela criptografa **todas as credenciais** que você salvar no n8n (tokens, senhas de API, OAuth). Se ela for perdida ou trocada, **todas as credenciais ficam ilegíveis** e você terá que recriá-las uma a uma. Se você **não** definir essa variável, o n8n gera uma aleatória no primeiro boot e a guarda só dentro de `/srv/n8n/data/config` — defina explícito aqui para ela ficar versionada no seu cofre de segredos (Bitwarden etc.) e não depender de um arquivo solto. **Guarde-a junto do backup do banco.**

> O `N8N_DB_PASSWORD` é usado tanto pelo serviço `n8n` (para conectar) quanto pelo `n8n-db` (para criar o usuário). Mantenha o `.env` fora do versionamento.

## Parte 3: A Stack (Docker Compose)

O arquivo [`n8n.yml`](../assets/stacks/n8n.yml) define **dois serviços**:

- **`n8n`** → imagem oficial `docker.n8n.io/n8nio/n8n`, roda como UID/GID `1000`, conecta no Postgres via `n8n-db:5432` e expõe a porta `5678` (Web UI + API + Webhooks). Já vem com `N8N_RUNNERS_ENABLED=true` (task runners — a forma recomendada de executar nós de código, no modo `internal`) e as variáveis de URL pública/proxy preenchidas para o Cloudflare Tunnel.
- **`n8n-db`** → PostgreSQL `16-alpine`, dados em `/srv/n8n/db`. Tem `healthcheck` (`pg_isready`) — o `n8n` só inicia depois que o banco está pronto, evitando erro de conexão no primeiro boot.

> ✏️ **Domínio parametrizado:** você não edita o YAML para o domínio — define `N8N_HOST` uma vez (no `.env` ou nas env vars do Portainer) e o compose o reaproveita em `WEBHOOK_URL`/`N8N_EDITOR_BASE_URL`. No YAML, só confira o fuso em `GENERIC_TIMEZONE`/`TZ`.

### Deploy via Portainer (Stack)

1. Acesse o Portainer → **Stacks** → **Add Stack**.
2. **Nome:** `n8n`.
3. Cole o conteúdo de [`assets/stacks/n8n.yml`](../assets/stacks/n8n.yml) no **Web editor**.
4. Na aba **Environment variables**, adicione (no Portainer **não** se usa o arquivo `.env`):
   - `N8N_HOST` — seu subdomínio público (ex.: `n8n.seudominio.com`, sem `https://`).
   - `N8N_DB_PASSWORD` — senha do PostgreSQL.
   - `N8N_ENCRYPTION_KEY` — a chave gerada na [Parte 2](#parte-2-configurar-os-segredos).
5. Clique em **Deploy the stack**.

> ⚠️ **Crie as pastas da [Parte 1](#parte-1-preparar-as-pastas-de-dados) via SSH _antes_ do Deploy.** Se o Portainer subir primeiro, o Docker cria `/srv/n8n/*` como `root` e o n8n (uid 1000) não consegue gravar em `/home/node/.n8n` (`EACCES`).

> 🐚 **Alternativa via SSH (sem Portainer):** com o `.env` preenchido ao lado do compose, rode `docker compose -f n8n.yml up -d`.

## Parte 4: Acesso Externo via Cloudflare Tunnel

Os webhooks do n8n só funcionam de verdade quando serviços externos (Telegram, GitHub, Stripe, etc.) conseguem **alcançar uma URL pública HTTPS**. Como o `cloudflared` já roda **bare metal no host**, basta publicar um hostname novo — **a stack não leva sidecar de cloudflared**.

1. No painel **Cloudflare One** (Zero Trust) → **Networks → Tunnels** → seu tunnel → aba **Public Hostname** → **Add a public hostname**:
   - **Subdomain/Domain:** `n8n.exemplo.com`
   - **Service:** `HTTP` → `localhost:5678` (ou `IP_DO_HOST:5678`)
2. O Cloudflare termina o TLS na borda; o container do n8n roda **HTTP puro** internamente.

**Por que as variáveis de URL no compose importam:** o n8n monta a URL dos webhooks combinando `N8N_PROTOCOL` + `N8N_HOST` + `N8N_PORT`. Atrás de um túnel isso quebraria (ele registraria `http://localhost:5678/...`), então fixamos a URL pública à mão:

| Variável                | Valor                                  | Para quê                                                        |
| :---------------------- | :------------------------------------- | :-------------------------------------------------------------- |
| `N8N_HOST`              | `${N8N_HOST}` (ex.: `n8n.exemplo.com`) | Hostname público. Definido **uma vez** (env var); as duas URLs abaixo o reaproveitam. |
| `N8N_PROTOCOL`          | `http`                                 | O **container** fala HTTP (quem faz HTTPS é o Cloudflare). Não use `https` aqui — o container não tem certificado e quebra. |
| `WEBHOOK_URL`           | `https://${N8N_HOST}/`                 | URL pública registrada nos webhooks dos serviços externos.      |
| `N8N_EDITOR_BASE_URL`   | `https://${N8N_HOST}/`                 | Links que o editor gera (ex.: URL de webhook exibida na tela).  |
| `N8N_PROXY_HOPS`        | `1`                                    | Nº de proxies à frente (1 = o Cloudflare Tunnel). Faz o n8n confiar nos headers `X-Forwarded-*` (IP real, rate limiting). |

> ⏱️ **Limite de ~100 s do Cloudflare:** webhooks **síncronos** que demoram mais de ~100 s para responder retornam **erro 524**. Para fluxos longos, responda cedo com o nó **"Respond to Webhook"** (modo assíncrono) em vez de segurar a conexão até o fim do workflow.

## Parte 5: Configuração Inicial

1. Acesse `https://n8n.exemplo.com` no navegador (use o **domínio HTTPS**, não o IP — ver a pegadinha do cookie abaixo).
2. Na primeira vez, o n8n pede para criar a **conta Owner** (e-mail + senha). É a conta de dono da instância; o gerenciamento de usuários já vem habilitado.
3. Pronto! Comece a montar workflows. 🚀

> 🔐 **Pegadinha do login (`N8N_SECURE_COOKIE`):** o default é `true`, ou seja, o cookie de sessão **só trafega por HTTPS**. Acessar via `http://IP_DO_HOST:5678` faz o **login falhar silenciosamente** (a sessão nunca persiste). Faça a configuração inicial pelo **domínio HTTPS do túnel**. Se você *precisar* acessar direto por HTTP/IP na LAN, adicione `N8N_SECURE_COOKIE=false` ao `environment:` (menos seguro — evite em produção) e atualize a stack.

---

## Parte 6: Escala — Instância Única vs Queue Mode (opcional)

Esta stack roda em **instância única** (regular mode): um processo n8n cuida de tudo (UI, API, triggers, webhooks **e** executa os workflows). Com **task runners** ligados (já está, `N8N_RUNNERS_ENABLED=true`), os nós de código (JS/Python) rodam num processo isolado — isso é **estabilidade/segurança**, não escala. Para o radar e a grande maioria dos casos de home lab, **isto basta**.

Considere **Queue mode** apenas quando a instância única não der conta do volume/picos de execuções, ou você quiser paralelismo real entre processos. Aí o `main` enfileira execuções no **Redis** e processos **worker** (`n8n worker`) as executam:

```yaml
# Referencia (NAO faz parte da stack padrao). Adicione um Redis e 1+ workers,
# e sete EXECUTIONS_MODE=queue no main E em TODOS os workers:
#   n8n (main):
#     environment:
#       - EXECUTIONS_MODE=queue
#       - QUEUE_BULL_REDIS_HOST=redis
#   n8n-worker:
#     image: docker.n8n.io/n8nio/n8n:2.23.4
#     command: worker --concurrency=5
#     environment:
#       - EXECUTIONS_MODE=queue
#       - QUEUE_BULL_REDIS_HOST=redis
#       - DB_TYPE=postgresdb            # MESMO banco do main
#       - N8N_ENCRYPTION_KEY=...        # MESMA chave do main (obrigatorio!)
#   redis:
#     image: redis:7-alpine
```

> 🔁 **Migrar depois é barato.** Como já usamos PostgreSQL (e não SQLite), virar queue mode é uma mudança de topologia: sobe Redis + workers e seta `EXECUTIONS_MODE=queue` em todos. **Você não perde** workflows, credenciais nem histórico — o banco é o mesmo. Regra de ouro: o `N8N_ENCRYPTION_KEY` precisa ser **idêntico** no main e em todos os workers, senão as credenciais não descriptografam.

---

## Parte 7: Atualização

A imagem usa a tag rolling (`docker.n8n.io/n8nio/n8n`, equivalente a **stable**). O n8n libera uma minor quase toda semana — a recomendação oficial é **atualizar com frequência** (ao menos 1×/mês). As **migrações de schema rodam automaticamente no boot** do container.

**Via Portainer (recomendado):**

1. Portainer → **Stacks** → `n8n`.
2. Clique em **Editor** (ou **Update the stack**) e marque **`Re-pull image and redeploy`** (em alguns temas: _"Pull latest image version"_).
3. Clique em **Update the stack**. Sem marcar isso, o Redeploy comum **reusa o cache** e não baixa a imagem nova.

> 🔒 **Quer reprodutibilidade?** Fixe a versão na imagem (ex.: `docker.n8n.io/n8nio/n8n:2.23.4` — veja as [release notes](https://docs.n8n.io/release-notes/)) e, para atualizar, bump a tag. Aí você sempre sabe qual versão está rodando (é o padrão que o Forgejo usa no repo).

**Via SSH:**

```bash
docker compose -f n8n.yml pull
docker compose -f n8n.yml up -d
```

> 💾 Os dados ficam nos bind mounts `/srv/n8n/data` e `/srv/n8n/db` (no host), então atualizar/recriar os containers **não apaga** nada.

> ⚠️ **Não pule vários majors de uma vez.** Em saltos de major (ex.: 1.x → 2.x): (1) **faça backup completo** (Parte 8), (2) suba primeiro para a **última release do major atual** e confirme que sobe limpo, (3) leia as **Breaking Changes** das release notes, e só então pule para o próximo major. Para reverter uma migração problemática, use `docker exec n8n n8n db:revert` (desfaz **uma** migração por vez).

## Parte 8: Backup

Três coisas precisam ir junto no backup — perder qualquer uma quebra a restauração:

1. **O banco PostgreSQL** — workflows, execuções e credenciais (criptografadas).

   ```bash
   docker exec n8n-db pg_dump -U n8n n8n > n8n-backup-$(date +%F).sql
   ```

2. **A `N8N_ENCRYPTION_KEY`** (do seu `.env` / cofre de segredos). Sem ela, o dump do banco é inútil: as credenciais ficam **indecifráveis**.
3. **A pasta `/srv/n8n/data`** (`/home/node/.n8n`) — guarda a chave (se você não fixou no `.env`), logs e assets de source control.

> O caminho mais simples: **pare os containers** e copie `/srv/n8n` inteiro + o `.env`. Isso captura banco, chave e dados num snapshot consistente.

---

## Troubleshooting

| Sintoma                                            | Causa provável / Correção                                                                                          |
| :------------------------------------------------- | :----------------------------------------------------------------------------------------------------------------- |
| `EACCES: permission denied, open /home/node/.n8n/config` | A pasta de dados é de `root`. Pare a stack e rode `sudo chown -R 1000:1000 /srv/n8n/data` (Parte 1).          |
| Login não persiste / volta pra tela de login       | `N8N_SECURE_COOKIE=true` + acesso por **HTTP/IP**. Acesse via `https://n8n.exemplo.com` (túnel) ou sete `N8N_SECURE_COOKIE=false` (Parte 5). |
| Webhook chega como `http://localhost:5678/...`     | `WEBHOOK_URL` não foi setada/ajustada. Confira `WEBHOOK_URL` e `N8N_EDITOR_BASE_URL` com o domínio real (Parte 4). |
| Erro **524** em webhook síncrono longo             | Limite de ~100 s do Cloudflare. Use o nó **"Respond to Webhook"** (resposta antecipada/assíncrona) (Parte 4).      |
| Execuções não atualizam ao vivo na UI              | O proxy não faz upgrade de WebSocket. Adicione `N8N_PUSH_BACKEND=sse` ao `environment:` e atualize a stack.        |
| Credenciais "não descriptografam" após restaurar   | A `N8N_ENCRYPTION_KEY` não bate com a do backup. Restaure **a mesma** chave de antes (Parte 8).                    |
| `n8n` reinicia / não conecta no banco no 1º boot   | Normal por alguns segundos: o `depends_on: service_healthy` segura o n8n até o `pg_isready` passar.                |

---

## Notas Importantes

- **Por que PostgreSQL dedicado (e não compartilhar 1 Postgres entre projetos):** cada stack do repo é **self-contained** — backup de `/srv/n8n` resolve tudo, sem acoplar ciclo de vida/versão com outros projetos. Compartilhar **uma** instância Postgres entre vários apps é **viável** (1 `DATABASE` + 1 `ROLE` por projeto, **nunca** o superuser compartilhado), mas cria ponto único de falha, acopla o upgrade do Postgres de todos de uma vez, e abre risco de _noisy neighbor_/segurança se os roles não forem isolados. Para um home lab, o custo de RAM de um Postgres dedicado é irrelevante perto do ganho de isolamento.
- **Task runners (`internal` vs `external`):** a stack usa o modo `internal` (runner como processo-filho — simples e suficiente numa instância privada e só sua). A doc oficial recomenda o modo `external` (sidecar `n8nio/runners`, com a **mesma versão** da imagem do n8n) para isolamento mais forte em produção multiusuário — adicione-o se for expor o n8n a terceiros.
- **Não use `--tunnel` em produção:** o n8n tem um túnel embutido (`n8n start --tunnel`) **só para desenvolvimento/teste**. O acesso de verdade é pelo seu Cloudflare Tunnel (Parte 4).
- **MySQL/MariaDB foi descontinuado** no n8n desde a v1.0 — só `sqlite` e `postgresdb` são válidos em `DB_TYPE`. Use PostgreSQL.

---

## Acessos

| Recurso              | URL / Local                          |
| :------------------- | :----------------------------------- |
| **Web UI (público)** | `https://n8n.exemplo.com`            |
| **Local (LAN)**      | `http://IP_DO_HOST:5678`             |
| **Portainer**        | Stack `n8n`                          |

---

## Referências

- [n8n — Docker Installation (oficial)](https://docs.n8n.io/hosting/installation/docker/)
- [n8n — Configuration / Environment variables](https://docs.n8n.io/hosting/configuration/environment-variables/)
- [n8n — Task runners](https://docs.n8n.io/hosting/configuration/task-runners/)
- [n8n — Scaling / Queue mode](https://docs.n8n.io/hosting/scaling/queue-mode/)
- [n8n — Reverse proxy](https://docs.n8n.io/hosting/configuration/configuration-examples/reverse-proxy/)
- [n8n-hosting — exemplos oficiais de docker-compose](https://github.com/n8n-io/n8n-hosting)
