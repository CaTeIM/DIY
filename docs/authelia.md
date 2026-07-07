# 🔐 Authelia + lldap (login SSO para usuários ilimitados)

Um **provedor de identidade (IdP) self-hosted**: o **Authelia** faz o login (e MFA opcional) e o **lldap** é o diretório de usuários com **UI web** (criar/remover usuários e grupos). Juntos com o **[Reverse Proxy (Caddy)](./reverse-proxy.md)**, eles protegem qualquer app via *forward-auth* — **um login só** cobre todos os `*.selflabs.org` (SSO), com **usuários ilimitados** e sem depender do login pago de nenhum app.

> ℹ️ É o "cérebro de identidade". A metade "porteiro de rota" (o Caddy que chama o Authelia) está em **[reverse-proxy](./reverse-proxy.md)**. Suba **esta** stack primeiro.

**Pré-requisito:** Docker + Portainer ([./portainer-debian.md](./portainer-debian.md)).

A stack pronta está em [`assets/stacks/authelia.yml`](../assets/stacks/authelia.yml) e a config do Authelia em [`assets/configs/authelia-configuration.yml`](../assets/configs/authelia-configuration.yml).

## Componentes

| Serviço | Papel | Portas (internas, sem host) |
| :--- | :--- | :--- |
| `lldap` | diretório LDAP + UI web de usuários | `3890` (LDAP), `17170` (UI) |
| `authelia` | login, sessão, políticas, MFA | `9091` (API/authz) |

Ambos ficam só na rede `auth-net` (não na `caddy-net` dos apps) — só o Caddy os alcança.

## Parte 1: Rede e pastas (via SSH, uma vez)

```bash
docker network create auth-net
sudo mkdir -p /srv/authelia/{config,lldap}
sudo chown -R 1000:1000 /srv/authelia
```

Grave a config em `/srv/authelia/config/configuration.yml` (conteúdo de [`assets/configs/authelia-configuration.yml`](../assets/configs/authelia-configuration.yml)). Troque `selflabs.org` pelo seu domínio em **todo** o arquivo.

## Parte 2: Segredos

Gere cada valor no próprio Orange Pi e preencha na aba **Environment variables** do Portainer (ou num `.env` via SSH — **nunca** faça commit dos valores):

```bash
# Authelia
openssl rand -hex 64   # AUTHELIA_SESSION_SECRET
openssl rand -hex 32   # AUTHELIA_STORAGE_ENCRYPTION_KEY      (>= 20 chars; FAÇA BACKUP)
openssl rand -hex 64   # AUTHELIA_IDENTITY_VALIDATION_RESET_PASSWORD_JWT_SECRET
openssl rand -hex 24   # AUTHELIA_AUTHENTICATION_BACKEND_LDAP_PASSWORD  (senha de bind)

# lldap
openssl rand -hex 32     # LLDAP_JWT_SECRET
openssl rand -base64 36  # LLDAP_KEY_SEED           (GERE UMA VEZ, FAÇA BACKUP, não rotacione)
openssl rand -hex 24     # LLDAP_LDAP_ADMIN_PASSWORD (senha do admin do lldap)
```

> 💾 `AUTHELIA_STORAGE_ENCRYPTION_KEY` e `LLDAP_KEY_SEED` criptografam dados persistidos (TOTP/WebAuthn, segredos). Se perder/trocar, o que está criptografado é **irrecuperável**. Faça backup junto com `/srv/authelia`.

## Parte 3: Deploy no Portainer

1. Portainer → **Stacks** → **Add Stack** → Nome: `authelia`.
2. Cole o YAML de [`assets/stacks/authelia.yml`](../assets/stacks/authelia.yml).
3. Preencha as 7 variáveis da Parte 2 em **Environment variables**.
4. **Deploy**. Ordem de subida: `lldap` (fica *healthy*) → `authelia`.

## Parte 4: Bootstrap — criar o bind do Authelia e seu usuário

No 1º boot o lldap cria sozinho `ou=people`, `ou=groups` e o super-admin `admin` (senha = `LLDAP_LDAP_ADMIN_PASSWORD`).

> ⚠️ **Ovo e galinha:** `users.selflabs.org` já é protegido pelo Authelia, mas o Authelia só autentica se conseguir dar bind como `uid=authelia` — que **ainda não existe**. Então o 1º acesso à UI precisa passar por fora. Escolha um caminho:
>
> - **A (recomendado, temporário):** adicione ao serviço `lldap` `ports: ["127.0.0.1:17170:17170"]`, redeploy, e faça um túnel SSH: `ssh -L 17170:127.0.0.1:17170 orangepi` → abra `http://127.0.0.1:17170`.
> - **B:** troque a regra de `users.selflabs.org` para `policy: 'bypass'` na config, reinicie o `authelia`, acesse `https://users.selflabs.org`.

Logado como `admin` na UI do lldap:

1. **Crie o usuário de bind do Authelia:**
   - User ID: `authelia` (vira `uid=authelia,ou=people,dc=selflabs,dc=org`).
   - Senha: **exatamente** o valor de `AUTHELIA_AUTHENTICATION_BACKEND_LDAP_PASSWORD` (tem que bater, senão ninguém loga).
   - Adicione-o ao grupo embutido **`lldap_strict_readonly`** (só leitura — é tudo que o Authelia precisa).
2. **Crie o seu usuário** (ex.: `gustavo`): defina e-mail e uma senha forte.
   - (Opcional) crie um grupo `admins` e coloque seu usuário, para restringir apps com `subject: ['group:admins']` numa regra do Authelia.
3. **Reverta o bootstrap:** remova o `ports` temporário (caminho A) ou volte a regra para `one_factor` (caminho B) e redeploy.

## Parte 5: Como a proteção funciona

1. Cloudflare Tunnel → cloudflared → Caddy. O Caddy casa `pdf.selflabs.org`, faz `import authelia` → subrequest a `authelia:9091 /api/authz/forward-auth`.
2. Sem sessão válida, o Authelia responde **302** para `https://auth.selflabs.org`; você loga com as credenciais do lldap.
3. No sucesso, grava o cookie `authelia_session` no domínio-pai `selflabs.org`; o Caddy recebe 2xx, copia `Remote-User/Groups/Name/Email` e faz o proxy para o app.
4. Como o cookie é do domínio-pai, **um login cobre todos os subdomínios** (`pdf`, `users`, `auth`).

## Parte 6: Proteger outro app

Adicione uma regra em `access_control` na config (`one_factor` por padrão) e um bloco `import authelia` no Caddyfile — passo a passo em **[reverse-proxy → Parte 4](./reverse-proxy.md#parte-4-proteger-um-app-novo-o-reuso)**.

## Parte 7: Atualizar e backup

- **Atualizar:** Portainer → stack `authelia` → **Re-pull image and redeploy**. O Authelia usa a tag `:4.39` (linha estável); a `lldap:stable` é rolling.
- **Backup:** `/srv/authelia` (SQLite do Authelia + `users.db` do lldap + config) **+** os 7 segredos. Restaurar os dois recompõe tudo.

## Troubleshooting

| Sintoma | Causa provável | Correção |
| :--- | :--- | :--- |
| Ninguém consegue logar | Senha de bind divergente | `AUTHELIA_AUTHENTICATION_BACKEND_LDAP_PASSWORD` **=** senha do usuário `authelia` no lldap |
| Loop de redirect | `X-Forwarded-Proto` errado | Ver [reverse-proxy → Troubleshooting](./reverse-proxy.md#troubleshooting) (trusted_proxies no Caddy) |
| Authelia não sobe | `authelia_url` não é subdomínio HTTPS do cookie, ou falta segredo | `authelia_url: https://auth.selflabs.org`; confira as 4 envs `AUTHELIA_*` |
| Não consigo abrir `users.` no 1º acesso | Ovo e galinha | Use o caminho A ou B da Parte 4 |
| E-mail de reset não chega | Notifier é `filesystem` (sem SMTP) | `docker exec authelia cat /config/notification.txt` |

## Notas Importantes

- **SQLite = instância única:** nem Authelia nem lldap escalam para réplicas. Um container de cada.
- **Sem Redis/Postgres:** sessão em memória (cai no restart do Authelia — aceitável num host único) e storage SQLite.
- **MFA:** tudo está em `one_factor`. Para exigir 2FA (TOTP/WebAuthn) num app, troque a regra para `two_factor` — o usuário registra o 2FA no portal.
- **`admin` do lldap ≠ `authelia`:** o `admin` é só para administrar o lldap; o `authelia` é conta de serviço **somente-leitura**. Nunca use o `admin` como bind.

## Acessos

| O quê | Onde | Credencial |
| :--- | :--- | :--- |
| Portal de login | `https://auth.selflabs.org` | usuário do lldap |
| UI de usuários | `https://users.selflabs.org` | `admin` / `LLDAP_LDAP_ADMIN_PASSWORD` |

## Referências

- [Authelia — documentação](https://www.authelia.com/configuration/prologue/introduction/)
- [Authelia — backend LDAP (lldap)](https://www.authelia.com/reference/guides/ldap/)
- [lldap — GitHub](https://github.com/lldap/lldap)
- [Reverse Proxy (Caddy) — este repo](./reverse-proxy.md)
