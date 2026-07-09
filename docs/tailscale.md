# 🔗 Tailscale (acesso privado aos seus serviços via tailnet)

Um **hub Tailscale**: um único node que publica **os seus serviços internos** na **tailnet** (rede privada WireGuard, ponto a ponto e criptografada) usando o **Tailscale Serve** (HTTPS), distinguindo cada serviço por **porta**. Sem expor porta no host para a internet, **sem Cloudflare** e **sem Authelia** — só os **seus próprios devices** logados na tailnet alcançam.

> 🎯 **Primeiro caso deste guia:** o **Portainer**. É o painel de controle do Docker (poderoso e sensível) — em vez de deixá-lo aberto na internet, você o alcança por uma **rota privada** de qualquer device seu. Depois é só somar mais serviços no mesmo hub, por porta.

**Pré-requisito:** Docker + Portainer ([./portainer-debian.md](./portainer-debian.md)) e a rede `caddy-net` criada (vem com a stack **[caddy](./caddy.md)**).

A stack pronta está em [`assets/stacks/tailscale.yml`](../assets/stacks/tailscale.yml) e o serve config em [`assets/configs/tailscale-serve.json`](../assets/configs/tailscale-serve.json).

## Arquitetura

```
   Seus devices (na tailnet)                          Host / VPS
   ┌───────────────────────────────────┐              ┌──────────────────────────────┐
   │ Navegador                         │              │  stack "tailscale" (hub)     │
   │ https://selflabs.<tailnet>.ts.net │   tailnet    │  ┌────────────────────────┐  │
   │   :443  -> Portainer              │─(WireGuard)──┼─►│ container tailscale     │  │
   │   :8443 -> (futuro)               │ criptografado│  └───────────┬────────────┘  │
   └───────────────────────────────────┘              │    caddy-net │  proxy        │
                                                      │              ▼               │
                                                      │      portainer:9000           │
                                                      └──────────────────────────────┘
        Rota privada — só a sua tailnet entra. Nada exposto na internet pública.
```

O node (`selflabs`) faz `serve` HTTPS: a **porta 443** encaminha para o Portainer, e cada serviço novo entra numa **porta própria** (8443, 9443, …). Qualquer device seu abre `https://selflabs.<sua-tailnet>.ts.net[:porta]`.

> ℹ️ **Como o container alcança o backend:** pela **rede docker**. O `tailscale` fica na `caddy-net`, e o alvo (ex.: `portainer`) também — então o proxy é só `http://<container>:porta`. Para expor um serviço de outra rede, adicione essa rede à stack `tailscale.yml`.

## Parte 1: Conta Tailscale + MagicDNS + HTTPS

1. Crie a conta grátis em **[login.tailscale.com](https://login.tailscale.com)** (login com Google/GitHub/Microsoft). O plano **Personal** cobre **até 100 devices / 3 usuários**.
2. No **admin console → [DNS](https://login.tailscale.com/admin/dns)**:
   - Ligue **MagicDNS** (dá nomes tipo `selflabs.<tailnet>.ts.net` aos nodes).
   - Ligue **HTTPS Certificates** (necessário para o `serve` servir HTTPS com certificado válido `*.ts.net`).

> ℹ️ O nome da sua tailnet (ex.: `tailb4da57.ts.net`) aparece no topo do admin console. O FQDN do hub vira `selflabs.<esse-nome>`.

## Parte 2: Auth key (segredo `TS_AUTHKEY`)

No **admin console → [Settings → Keys](https://login.tailscale.com/admin/settings/keys) → Generate auth key**:

- **Reusable:** ✅ (permite recriar o container sem gerar key nova).
- **Ephemeral:** ❌ (queremos um node **persistente**).
- **Tags:** `tag:server` (recomendado — o node não expira e não conta como device pessoal). Crie a tag antes em **Access controls** (`tagOwners`: `"tag:server": ["autogroup:admin"]`).

Copie o valor (`tskey-auth-...`) → vai na aba **Environment variables** do Portainer como `TS_AUTHKEY` (**nunca** faça commit).

> ℹ️ Como o estado é persistido em `/srv/tailscale/state`, a key só é usada no **1º registro**. Guarde-a: se o volume de estado sumir, ela re-registra o node.

## Parte 3: Pastas e serve config (via SSH, uma vez)

```bash
sudo mkdir -p /srv/tailscale/{state,config}   # o container roda como root; sem chown
```

Grave o serve config em `/srv/tailscale/config/serve.json` (conteúdo de [`assets/configs/tailscale-serve.json`](../assets/configs/tailscale-serve.json)) — Portainer na 443:

```json
{
  "TCP": { "443": { "HTTPS": true } },
  "Web": {
    "${TS_CERT_DOMAIN}:443": {
      "Handlers": { "/": { "Proxy": "http://portainer:9000" } }
    }
  }
}
```

> ℹ️ `${TS_CERT_DOMAIN}` é trocado **pelo container** pelo FQDN do node (`selflabs.<tailnet>.ts.net`) — não hardcode. O `Proxy` aponta para o container-alvo pelo nome na `caddy-net`.

## Parte 4: Deploy no Portainer

1. Portainer → **Stacks** → **Add Stack** → Nome: `tailscale`.
2. Cole o YAML de [`assets/stacks/tailscale.yml`](../assets/stacks/tailscale.yml) (ou aponte para o repositório Git).
3. Na aba **Environment variables**, adicione `TS_AUTHKEY` = sua key `tskey-auth-...`.
4. **Deploy the stack**.

Confira que registrou:

```bash
docker exec tailscale tailscale status     # deve listar o node 'selflabs' com IP 100.x.x.x
docker logs tailscale 2>&1 | grep -iE 'serve|proxy'
```

No **admin console → [Machines](https://login.tailscale.com/admin/machines)** aparece o node **`selflabs`**. Anote o FQDN (`selflabs.<sua-tailnet>.ts.net`).

> ⚠️ O Portainer precisa estar na **`caddy-net`** para o `tailscale` alcançá-lo por `portainer:9000`. Se ele foi criado via `docker run` (bare-metal), ver [Parte 6](#parte-6-portainer-privado-fechar-a-porta-p%C3%BAblica).

## Parte 5: Instalar no seu device e acessar

1. Instale o **Tailscale** no seu PC: **[tailscale.com/download](https://tailscale.com/download)** e **logue na mesma conta**. O PC vira um node na tailnet.
2. No **navegador**, abra `https://selflabs.<sua-tailnet>.ts.net` → deve cair no **Portainer**.
   - O **1º acesso** pode levar ~5–10s (o Tailscale provisiona o certificado HTTPS na hora).

## Parte 6: Portainer privado (fechar a porta pública)

Por padrão o guia do [Portainer](./portainer-debian.md) publica `9000/9443/8000` em `0.0.0.0` — **aberto na internet**. Para deixá-lo **só** na tailnet (e opcionalmente no Cloudflare atrás do Caddy), coloque-o na `caddy-net` sem publicar porta.

**Migre sem downtime, valide, e só então feche:**

```bash
# 1) conectar à caddy-net sem recriar (mantém o publish atual no ar)
docker network connect caddy-net portainer

# 2) apontar o Caddy (portainervps.selflabs.org -> portainer:9000) e o Tailscale
#    (serve.json -> http://portainer:9000), e testar os dois caminhos + webhooks

# 3) validado? recrie SEM -p (fecha 9000/9443/8000 do host):
docker rm -f portainer
docker run -d --name portainer --restart=always \
  --network caddy-net \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /srv/portainer:/data \
  portainer/portainer-ee:<sua-versão>
```

Os dados vivem em `/srv/portainer` (volume) — recriar o container não perde nada. Rollback: recrie com `-p 9000:9000 -p 9443:9443` de volta.

> ⚠️ **Webhooks:** se o Portainer também é publicado no Cloudflare (ex.: `portainervps.selflabs.org`) e recebe **webhooks do GitHub**, **não** ponha o Authelia na frente — o forward-auth barra chamadas programáticas (POST sem sessão) e quebra o webhook. Deixe o Portainer só com o **login próprio** dele.

## Parte 7: (Opcional) Hardening da tailnet

- **Node como servidor:** use `tag:server` (Parte 2) — não expira, não conta como device pessoal. Se criou sem tag, aplique em Machines → node → `⋯` → **Edit ACL tags** → `tag:server`, e **Disable key expiry**.
- **ACL restritiva:** por padrão a tailnet é _allow-all_ entre os seus devices. Para limitar, edite as **Access controls**.
- **Nunca ligue o Funnel** — ele exporia o serviço na internet pública. Este guia usa só `serve` (tailnet).

## Parte 8: Somar outro serviço ao hub (➕)

O mesmo node serve vários serviços, um por **porta**. Ex.: adicionar um Grafana (na `caddy-net`):

1. **serve.json** — adicione a porta (`8443`) e o backend:
   ```json
   {
     "TCP": { "443": { "HTTPS": true }, "8443": { "HTTPS": true } },
     "Web": {
       "${TS_CERT_DOMAIN}:443":  { "Handlers": { "/": { "Proxy": "http://portainer:9000" } } },
       "${TS_CERT_DOMAIN}:8443": { "Handlers": { "/": { "Proxy": "http://grafana:3000" } } }
     }
   }
   ```
2. **Rede** — se o serviço não está na `caddy-net`, adicione a rede dele à stack `tailscale.yml` (nas duas listas `networks`) e redeploy.
3. Acesse em `https://selflabs.<sua-tailnet>.ts.net:8443`.

## Parte 9: Atualizar e backup

- **Atualizar:** Portainer → stack `tailscale` → **Re-pull image and redeploy** (tag `:latest`).
- **Backup:** `/srv/tailscale/state` (identidade do node) + `/srv/tailscale/config` (serve.json) + a `TS_AUTHKEY`.

## Troubleshooting

| Sintoma | Causa provável | Correção |
| :--- | :--- | :--- |
| `https://selflabs…ts.net` não resolve no PC | MagicDNS off, ou Tailscale não roda no PC | Ligue MagicDNS (Parte 1); confirme o Tailscale ativo (ícone na bandeja) |
| Erro de **certificado** ao abrir a URL | HTTPS Certificates off na tailnet | Ligue **HTTPS Certificates** (Parte 1) e redeploy o container |
| `502`/página em branco | backend errado, ou alvo fora da `caddy-net` | Confira o `Proxy` (`http://<container>:porta`); garanta que o alvo está na `caddy-net` |
| serve.json alterado não aplicou | o container lê no boot | `docker restart tailscale` |
| Node não aparece em Machines | `TS_AUTHKEY` inválida/expirada | Gere nova auth key (Parte 2) e redeploy |

## Notas Importantes

- **Rota privada, não pública:** só devices logados na **sua** tailnet alcançam. `serve` é tailnet-only; **Funnel** (público) fica desligado.
- **Não expõe porta nova:** o proxy da tailnet não abre nada na internet. Pelo contrário — permite **fechar** exposições públicas existentes (Parte 6).
- **Userspace:** `TS_USERSPACE=true` (sem `/dev/net/tun`/`NET_ADMIN`) — o `serve` funciona assim e o container fica sem privilégios extras.
- **Hub por porta:** um node serve vários serviços (Parte 8). Para URLs sem porta, use um node dedicado por serviço.

## Acessos

| O quê | Onde | Proteção |
| :--- | :--- | :--- |
| Serviços via tailnet | `https://selflabs.<sua-tailnet>.ts.net[:porta]` | tailnet (seus devices) |
| Admin da tailnet | [login.tailscale.com/admin](https://login.tailscale.com/admin) | conta Tailscale |

## Referências

- [Tailscale — Docker](https://tailscale.com/kb/1282/docker)
- [Tailscale — Serve](https://tailscale.com/kb/1312/serve)
- [Tailscale — Auth keys](https://tailscale.com/kb/1085/auth-keys)
- [Tailscale — Download clients](https://tailscale.com/download)
- [Portainer (este repo)](./portainer-debian.md) · [Caddy (este repo)](./caddy.md)
