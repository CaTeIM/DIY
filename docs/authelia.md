# 🔐 Authelia + lldap (login SSO para usuários ilimitados)

Um **provedor de identidade (IdP) self-hosted**: o **Authelia** faz o login (e MFA opcional) e o **lldap** é o diretório de usuários com **UI web** (criar/remover usuários e grupos). Juntos com o **[Caddy](./caddy.md)**, eles protegem qualquer app via _forward-auth_ — **um login só** cobre todos os `*.selflabs.org` (SSO), com **usuários ilimitados** e sem depender do login pago de nenhum app.

> ℹ️ É o "cérebro de identidade". A metade "porteiro de rota" (o Caddy que chama o Authelia) está em **[caddy](./caddy.md)**. Suba **esta** stack primeiro.

**Pré-requisito:** Docker + Portainer ([./portainer-debian.md](./portainer-debian.md)).

A stack pronta está em [`assets/stacks/authelia.yml`](../assets/stacks/authelia.yml) e a config do Authelia em [`assets/configs/authelia.yml`](../assets/configs/authelia.yml).

## Componentes

| Serviço    | Papel                               | Portas (internas, sem host) |
| :--------- | :---------------------------------- | :-------------------------- |
| `lldap`    | diretório LDAP + UI web de usuários | `3890` (LDAP), `17170` (UI) |
| `authelia` | login, sessão, políticas, MFA       | `9091` (API/authz)          |

Ambos ficam só na rede `auth-net` (não na `caddy-net` dos apps) — só o Caddy os alcança.

## Parte 1: Rede e pastas (via SSH, uma vez)

```bash
docker network create auth-net
sudo mkdir -p /srv/authelia/{config,lldap}
sudo chown -R 1000:1000 /srv/authelia
```

Grave a config em `/srv/authelia/config/configuration.yml` (conteúdo de [`assets/configs/authelia.yml`](../assets/configs/authelia.yml)). Troque `selflabs.org` pelo seu domínio em **todo** o arquivo.

## Parte 2: Segredos

Gere cada valor no próprio host e preencha na aba **Environment variables** do Portainer (ou num `.env` via SSH — **nunca** faça commit dos valores):

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

O **8º segredo** não é gerado — é a **API key do Resend** (para o SMTP do Authelia, ver [Parte 5](#parte-5-e-mail-smtp-via-resend-e-2fa-totp)):

```text
AUTHELIA_NOTIFIER_SMTP_PASSWORD = sua API key `re_...` do painel do Resend
```

> 💾 `AUTHELIA_STORAGE_ENCRYPTION_KEY` e `LLDAP_KEY_SEED` criptografam dados persistidos (TOTP/WebAuthn, segredos). Se perder/trocar, o que está criptografado é **irrecuperável**. Faça backup junto com `/srv/authelia`.

## Parte 3: Deploy no Portainer

1. Portainer → **Stacks** → **Add Stack** → Nome: `authelia`.
2. Cole o YAML de [`assets/stacks/authelia.yml`](../assets/stacks/authelia.yml).
3. Preencha as **8** variáveis da Parte 2 em **Environment variables** (7 geradas + a API key do Resend).
4. **Deploy**. Ordem de subida: `lldap` (fica _healthy_) → `authelia`.

## Parte 4: Bootstrap — criar o bind do Authelia e seu usuário

No 1º boot o lldap cria sozinho `ou=people`, `ou=groups` e o super-admin `admin` (senha = `LLDAP_LDAP_ADMIN_PASSWORD`).

> ⚠️ **Ovo e galinha:** `users.selflabs.org` já é protegido pelo Authelia, mas o Authelia só sobe se conseguir dar bind como `uid=authelia` — que **ainda não existe**. Então o 1º acesso à UI precisa passar **por fora do Authelia**. Use o caminho A:
>
> - **A (recomendado):** acesse a UI do lldap sem passar pelo Authelia. Se a stack está em modo **Git** (não dá pra editar o compose no Portainer), faça um túnel SSH direto pro IP do container na rede docker:
>   ```bash
>   # no host:
>   docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' lldap   # ex.: 172.23.0.2
>   # no seu PC (troque o IP e o <host> do seu ~/.ssh/config):
>   ssh -L 17170:172.23.0.2:17170 <host>     # depois abra http://localhost:17170
>   ```
>   Alternativa (se o compose for editável): adicione `ports: ["127.0.0.1:17170:17170"]` ao serviço `lldap` e redeploy.
> - ~~**B:** trocar a regra de `users.` para `bypass`~~ — **não funciona neste caso.** O Authelia falha no _startup check_ do backend LDAP (o bind da conta `authelia`) e **morre antes** de avaliar o `access_control`, então nenhum `bypass` tem efeito enquanto a conta não existir. Só o caminho A resolve.

Logado como `admin` na UI do lldap:

1. **Crie o usuário de bind do Authelia:**
   - User ID: `authelia` (vira `uid=authelia,ou=people,dc=selflabs,dc=org`).
   - Senha: **exatamente** o valor de `AUTHELIA_AUTHENTICATION_BACKEND_LDAP_PASSWORD` (tem que bater, senão ninguém loga).
   - Grupo: **`lldap_strict_readonly`** (só leitura — suficiente para autenticar). **Mas** se quiser **reset de senha self-service** pelo portal do Authelia, use **`lldap_password_manager`** — o Authelia precisa de permissão de **escrita** para gravar a nova senha (readonly não reseta). Ver [Parte 5](#parte-5-e-mail-smtp-via-resend-e-2fa-totp).
2. **Crie o seu usuário** (ex.: `gustavo`): defina e-mail e uma senha forte.
   - (Opcional) crie um grupo `admins` e coloque seu usuário, para restringir apps com `subject: ['group:admins']` numa regra do Authelia.
3. **Reverta o bootstrap:** remova o `ports` temporário (ou feche o túnel SSH) e redeploy. O Authelia passa a dar bind e sobe.

## Parte 5: E-mail (SMTP via Resend) e 2FA (TOTP)

O notifier do Authelia usa **SMTP** (Resend) — é o que entrega os **links de reset de senha** e os **códigos de verificação** para registrar 2FA. A config está em [`authelia.yml`](../assets/configs/authelia.yml) (bloco `notifier.smtp`); a senha é a env `AUTHELIA_NOTIFIER_SMTP_PASSWORD` (API key `re_...` do Resend).

> ⚠️ O `sender` (`no-reply@selflabs.org`) tem de ser de um **domínio verificado** no Resend → _Domains_ (verde). Remetente não verificado é recusado. O `startup_check` do SMTP fica **desligado** de propósito (alguns relays recusam o probe e derrubariam o Authelia) — teste o envio no 1º uso real.

**2FA (TOTP):** as regras de `access_control` em `two_factor` exigem um segundo fator. No 1º acesso a um app protegido, o Authelia manda registrar um autenticador (Google Authenticator, Aegis, 2FAS…) no portal `auth.selflabs.org` — o **código de verificação do registro chega por e-mail** (por isso o SMTP vem antes). Depois, cada login pede a senha do lldap **+** o código TOTP.

> ℹ️ **Reset self-service** exige a conta `authelia` em **`lldap_password_manager`** (ver [Parte 4](#parte-4-bootstrap--criar-o-bind-do-authelia-e-seu-usuário)). Mantendo-a só-leitura, o reset é feito por **você (admin)** na UI do lldap.

**Testar:** peça um reset no portal (ou registre um 2FA) e confira a chegada. Se não vier: painel do Resend → _Emails_, e `docker logs authelia 2>&1 | grep -i smtp`.

## Parte 6: Como a proteção funciona

1. Cloudflare Tunnel → cloudflared → Caddy. O Caddy casa `pdf.selflabs.org`, faz `import authelia` → subrequest a `authelia:9091 /api/authz/forward-auth`.
2. Sem sessão válida, o Authelia responde **302** para `https://auth.selflabs.org`; você loga com as credenciais do lldap.
3. No sucesso, grava o cookie `authelia_session` no domínio-pai `selflabs.org`; o Caddy recebe 2xx, copia `Remote-User/Groups/Name/Email` e faz o proxy para o app.
4. Como o cookie é do domínio-pai, **um login cobre todos os subdomínios** (`pdf`, `users`, `auth`).

## Parte 7: Proteger outro app

Adicione uma regra em `access_control` na config (`one_factor` = só senha, ou `two_factor` = senha + TOTP) e um bloco `import authelia` no Caddyfile — passo a passo em **[caddy → Parte 4](./caddy.md#parte-4-proteger-um-app-novo-o-reuso)**.

## Parte 8: Atualizar e backup

- **Atualizar:** Portainer → stack `authelia` → **Re-pull image and redeploy**. O Authelia usa a tag `:4.39` (linha estável); a `lldap:stable` é rolling.
- **Backup:** `/srv/authelia` (SQLite do Authelia + `users.db` do lldap + config) **+** os 8 segredos. Restaurar os dois recompõe tudo.

## Troubleshooting

| Sintoma                                 | Causa provável                                                    | Correção                                                                                                                                                          |
| :-------------------------------------- | :---------------------------------------------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Ninguém consegue logar                  | Senha de bind divergente                                          | `AUTHELIA_AUTHENTICATION_BACKEND_LDAP_PASSWORD` **=** senha do usuário `authelia` no lldap                                                                        |
| Loop de redirect                        | `X-Forwarded-Proto` errado                                        | Ver [caddy → Troubleshooting](./caddy.md#troubleshooting) (trusted_proxies no Caddy)                                                                              |
| Authelia não sobe                       | `authelia_url` não é subdomínio HTTPS do cookie, ou falta segredo | `authelia_url: https://auth.selflabs.org`; confira as 4 envs `AUTHELIA_*`                                                                                         |
| Não consigo abrir `users.` no 1º acesso | Ovo e galinha                                                     | Use o **caminho A** da Parte 4 (túnel SSH direto pro IP do container). O caminho `bypass` NÃO serve: o Authelia morre no startup check antes de avaliar as regras |
| E-mail (reset/2FA) não chega            | Domínio do `sender` não verificado no Resend, ou API key errada   | `sender` num domínio verde no Resend; `AUTHELIA_NOTIFIER_SMTP_PASSWORD` = API key `re_...`; `docker logs authelia 2>&1 \| grep -i smtp`                           |
| Reset de senha falha (sem permissão)    | Conta `authelia` é `lldap_strict_readonly`                        | Mova a `authelia` para `lldap_password_manager` na UI do lldap (ou resete você mesmo como admin)                                                                  |
| 2FA não registra                        | SMTP não entrega o código de verificação                          | Ver a linha de e-mail acima — sem SMTP não há como registrar o TOTP                                                                                               |

## Notas Importantes

- **SQLite = instância única:** nem Authelia nem lldap escalam para réplicas. Um container de cada.
- **Sem Redis/Postgres:** sessão em memória (cai no restart do Authelia — aceitável num host único) e storage SQLite.
- **MFA:** `users.` está em `two_factor` (senha + TOTP) e `pdf.` em `one_factor` (só senha) — ajuste por app no `access_control`. O TOTP é registrado no portal; o código de registro chega por e-mail (SMTP, [Parte 5](#parte-5-e-mail-smtp-via-resend-e-2fa-totp)).
- **`admin` do lldap ≠ `authelia`:** o `admin` administra o lldap; o `authelia` é conta de serviço (só-leitura, ou `lldap_password_manager` se quiser reset self-service). Nunca use o `admin` como bind.

## Acessos

| O quê           | Onde                         | Credencial                            |
| :-------------- | :--------------------------- | :------------------------------------ |
| Portal de login | `https://auth.selflabs.org`  | usuário do lldap                      |
| UI de usuários  | `https://users.selflabs.org` | `admin` / `LLDAP_LDAP_ADMIN_PASSWORD` |

## Referências

- [Authelia — documentação](https://www.authelia.com/configuration/prologue/introduction/)
- [Authelia — backend LDAP (lldap)](https://www.authelia.com/reference/guides/ldap/)
- [lldap — GitHub](https://github.com/lldap/lldap)
- [Caddy (reverse proxy) — este repo](./caddy.md)
