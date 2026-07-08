# 🔗 Tailscale (acesso privado aos seus serviços via tailnet)

Um **hub Tailscale**: um único node que publica **os seus serviços internos** na **tailnet** (rede privada WireGuard, ponto a ponto e criptografada) usando o **Tailscale Serve** (HTTPS), distinguindo cada serviço por **porta**. Sem expor porta no host, **sem Cloudflare** e **sem passar pelo Authelia** — só os **seus próprios devices** logados na tailnet alcançam.

> 🎯 **Primeiro caso deste guia:** o **app desktop do Stirling-PDF** (Windows/Mac). Ele fala **direto** com o servidor e **não sabe fazer o login SSO do Authelia** (dá `Failed to fetch server configuration`). A tailnet dá a ele uma rota privada até o Stirling (que roda **aberto**, ver [stirling-pdf.md](./stirling-pdf.md)), contornando o Authelia sem abrir nada pra internet. Depois é só somar mais serviços no mesmo hub.

**Pré-requisito:** Docker + Portainer ([./portainer-debian.md](./portainer-debian.md)) e o(s) serviço(s)-alvo já rodando (aqui, o **[Stirling-PDF](./stirling-pdf.md)** na rede `caddy-net`).

A stack pronta está em [`assets/stacks/tailscale.yml`](../assets/stacks/tailscale.yml) e o serve config em [`assets/configs/tailscale-serve.json`](../assets/configs/tailscale-serve.json).

## Arquitetura

```
   Seus devices (na tailnet)                          Host / VPS
   ┌────────────────────────┐                ┌──────────────────────────────┐
   │ App / navegador        │                │  stack "tailscale" (hub)     │
   │ https://selflabs       │   tailnet      │  ┌────────────────────────┐  │
   │   .<tailnet>.ts.net    │──(WireGuard)───┼─►│ container tailscale    │  │
   │   :443  -> Stirling    │  criptografado │  │ serve HTTPS por porta: │  │
   │   :8443 -> (futuro)    │                │  │  443  -> stirling-pdf  │  │
   └────────────────────────┘                │  │  8443 -> (outro app)   │  │
                                             │  └───────────┬────────────┘  │
                                             │      caddy-net│ proxy        │
                                             │               ▼              │
                                             │  stirling-pdf:8080 (aberto)  │
                                             └──────────────────────────────┘
        NÃO passa pelo Authelia nem pelo Cloudflare — rota privada direta.
```

Um node (`selflabs`) na sua tailnet faz `serve` HTTPS: a **porta 443** encaminha para `http://stirling-pdf:8080`, e cada serviço novo entra numa **porta própria** (8443, 9443, …). Qualquer device seu abre `https://selflabs.<sua-tailnet>.ts.net[:porta]`.

## Parte 1: Conta Tailscale + MagicDNS + HTTPS

1. Crie a conta grátis em **[login.tailscale.com](https://login.tailscale.com)** (login com Google/GitHub/Microsoft). O plano **Personal** cobre **até 100 devices / 3 usuários**.
2. No **admin console → [DNS](https://login.tailscale.com/admin/dns)**:
   - Ligue **MagicDNS** (dá nomes tipo `selflabs.<tailnet>.ts.net` aos nodes).
   - Ligue **HTTPS Certificates** (necessário para o `serve` servir HTTPS com certificado válido `*.ts.net`).

> ℹ️ O nome da sua tailnet (ex.: `tail1a2b3c.ts.net`) aparece no topo do admin console. O FQDN do hub vira `selflabs.<esse-nome>`.

## Parte 2: Auth key (segredo `TS_AUTHKEY`)

No **admin console → [Settings → Keys](https://login.tailscale.com/admin/settings/keys) → Generate auth key**:

- **Reusable:** ✅ (permite recriar o container sem gerar key nova).
- **Expiration:** até 90 dias (a key só é usada no 1º registro; ver nota).
- **Ephemeral:** ❌ (queremos um node **persistente**).
- **Tags:** vazio por ora (hardening opcional na [Parte 6](#parte-6-opcional-hardening)).

Copie o valor (`tskey-auth-...`) — ele vai na aba **Environment variables** do Portainer como `TS_AUTHKEY` (**nunca** faça commit).

> ℹ️ Como o estado do node é persistido em `/srv/tailscale/state`, a auth key só é usada **uma vez** (no 1º registro). Guarde-a: se o volume de estado sumir, ela re-registra o node.

## Parte 3: Pastas e serve config (via SSH, uma vez)

```bash
sudo mkdir -p /srv/tailscale/{state,config}   # o container roda como root; sem chown
```

Grave o serve config em `/srv/tailscale/config/serve.json` (conteúdo de [`assets/configs/tailscale-serve.json`](../assets/configs/tailscale-serve.json)) — hoje só o Stirling na 443:

```json
{
  "TCP": { "443": { "HTTPS": true } },
  "Web": {
    "${TS_CERT_DOMAIN}:443": {
      "Handlers": { "/": { "Proxy": "http://stirling-pdf:8080" } }
    }
  }
}
```

> ℹ️ `${TS_CERT_DOMAIN}` é trocado **pelo próprio container** pelo FQDN do node (`selflabs.<tailnet>.ts.net`) — não hardcode o nome da tailnet. O `Proxy` aponta para o container-alvo pelo nome na rede docker.

## Parte 4: Deploy no Portainer

1. Portainer → **Stacks** → **Add Stack** → Nome: `tailscale`.
2. Cole o YAML de [`assets/stacks/tailscale.yml`](../assets/stacks/tailscale.yml) (ou aponte para o repositório Git).
3. Na aba **Environment variables**, adicione `TS_AUTHKEY` = sua key `tskey-auth-...`.
4. **Deploy the stack**.

Confira que registrou:

```bash
docker logs tailscale 2>&1 | grep -iE 'success|serve|https'   # deve mostrar o node autenticado
```

No **admin console → [Machines](https://login.tailscale.com/admin/machines)** aparece o node **`selflabs`** — anote o **FQDN completo** (`selflabs.<sua-tailnet>.ts.net`).

## Parte 5: Instalar no seu device e apontar o app

1. Instale o **Tailscale** no seu PC: **[tailscale.com/download](https://tailscale.com/download)** (Windows/Mac/Linux/iOS/Android) e **logue na mesma conta**. Seu PC vira um node na tailnet.
2. Teste no navegador do PC: abra `https://selflabs.<sua-tailnet>.ts.net` — deve abrir o Stirling **sem** pedir login do Authelia.
3. No **app desktop do Stirling** → **Connection Mode → Connect to Server**, ponha a **Server URL**:
   ```
   https://selflabs.<sua-tailnet>.ts.net
   ```
   Agora conecta. 🚀

## Parte 6: (Opcional) Hardening

- **Não deixe o node expirar:** admin console → Machines → node `selflabs` → **⋯ → Disable key expiry** (senão o node cai em ~180 dias e todos os serviços perdem a conexão).
- **Tag de servidor** (`tag:server`): evita expiry e não conta como device pessoal. Requer:
  1. Admin console → **Access controls**, no bloco `tagOwners` adicione `"tag:server": ["autogroup:admin"]`.
  2. Regere a auth key marcando a tag, **ou** adicione `TS_EXTRA_ARGS: "--advertise-tags=tag:server"` na stack e redeploy.
- **ACL restritiva:** por padrão a tailnet é _allow-all_ entre os seus devices. Para limitar quem alcança o hub, edite as **Access controls**.
- **Nunca ligue o Funnel** neste node — ele exporia os serviços na **internet pública**. Este guia usa só `serve` (tailnet).

## Parte 7: Somar outro serviço ao hub (➕)

O mesmo node serve vários projetos, um por **porta**. Para expor, digamos, um Grafana:

1. **serve.json** — adicione a porta (ex.: `8443`) no `TCP` e o backend no `Web`:
   ```json
   {
     "TCP": { "443": { "HTTPS": true }, "8443": { "HTTPS": true } },
     "Web": {
       "${TS_CERT_DOMAIN}:443": {
         "Handlers": { "/": { "Proxy": "http://stirling-pdf:8080" } }
       },
       "${TS_CERT_DOMAIN}:8443": {
         "Handlers": { "/": { "Proxy": "http://grafana:3000" } }
       }
     }
   }
   ```
2. **Rede** — se o `grafana` não está na `caddy-net`, adicione a rede dele à stack `tailscale.yml` (nas duas listas `networks`) e redeploy.
3. Acesse em `https://selflabs.<sua-tailnet>.ts.net:8443`.

> 💡 Um serviço por porta mantém tudo num só container. Se preferir **URLs sem porta** (`grafana.<tailnet>.ts.net`), suba um segundo node Tailscale dedicado (copie a stack com outro `container_name`, `hostname` e pasta `/srv/…`).

## Parte 8: Atualizar e backup

- **Atualizar:** Portainer → stack `tailscale` → **Re-pull image and redeploy** (tag `:latest`).
- **Backup:** `/srv/tailscale/state` (identidade do node) + `/srv/tailscale/config` (serve.json) + a `TS_AUTHKEY`. Restaurar o `state` evita re-registrar o node.

## Troubleshooting

| Sintoma                                     | Causa provável                                                        | Correção                                                                      |
| :------------------------------------------ | :-------------------------------------------------------------------- | :---------------------------------------------------------------------------- |
| App ainda dá `Failed to fetch`              | Apontando para `pdf.selflabs.org` (Authelia)                          | Use a URL da tailnet: `https://selflabs.<tailnet>.ts.net`                     |
| `https://selflabs…ts.net` não resolve no PC | MagicDNS off, ou Tailscale não está rodando no PC                     | Ligue MagicDNS (Parte 1); confirme o Tailscale ativo no PC (ícone na bandeja) |
| Erro de **certificado** ao abrir a URL      | HTTPS Certificates off na tailnet                                     | Ligue **HTTPS Certificates** (Parte 1) e redeploy o container                 |
| `502`/página em branco na URL da tailnet    | `serve.json` com backend errado, ou container fora da rede do serviço | `Proxy` = `http://<container>:porta`; confirme o `tailscale` na rede do alvo  |
| Node não aparece em Machines                | `TS_AUTHKEY` inválida/expirada                                        | Gere nova auth key (Parte 2) e redeploy                                       |
| Node sumiu depois de meses                  | Key expiry do node (180 dias)                                         | **Disable key expiry** (Parte 6) ou use `tag:server`                          |

## Notas Importantes

- **Rota privada, não pública:** só devices logados na **sua** tailnet alcançam os serviços. O `serve` é tailnet-only; **Funnel** (público) fica desligado.
- **Convive com o Authelia:** o Stirling continua acessível por `pdf.selflabs.org` (browser, via Authelia) **e** por `selflabs.<tailnet>.ts.net` (app, via tailnet). Dois caminhos para o mesmo app aberto — cada um com sua camada.
- **Userspace:** o container usa `TS_USERSPACE=true` (sem `/dev/net/tun`/`NET_ADMIN`) — o `serve` funciona assim e o container fica sem privilégios extras.
- **Hub por porta:** um node serve vários projetos (Parte 7). Para URLs sem porta, use um node dedicado por serviço.

## Acessos

| O quê                      | Onde                                                           | Proteção               |
| :------------------------- | :------------------------------------------------------------- | :--------------------- |
| Serviços via tailnet (app) | `https://selflabs.<sua-tailnet>.ts.net[:porta]`                | tailnet (seus devices) |
| Stirling via web (browser) | `https://pdf.selflabs.org`                                     | Authelia               |
| Admin da tailnet           | [login.tailscale.com/admin](https://login.tailscale.com/admin) | conta Tailscale        |

## Referências

- [Tailscale — Docker](https://tailscale.com/kb/1282/docker)
- [Tailscale — Serve](https://tailscale.com/kb/1312/serve)
- [Tailscale — Auth keys](https://tailscale.com/kb/1085/auth-keys)
- [Tailscale — Download clients](https://tailscale.com/download)
- [Stirling-PDF (este repo)](./stirling-pdf.md) · [Caddy + Authelia (este repo)](./caddy.md)
