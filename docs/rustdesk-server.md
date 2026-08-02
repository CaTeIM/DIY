# 🖧 RustDesk Server self-hosted (hbbs/hbbr na VPS)

Migrar o seu **RustDesk Server** (hoje no Windows Server 2025) para a **VPS Oracle** como stack Docker,
preservando a mesma **Key** para não reconfigurar cliente nenhum. Um servidor de ID/relay próprio para
controlar todas as suas máquinas com o cliente nativo do RustDesk, sem depender da nuvem pública da RustDesk.

**Pré-requisitos:** Docker + Portainer ([./portainer-debian.md](./portainer-debian.md)) e uma VPS com IP
público e portas abertas ([./vps-oracle.md](./vps-oracle.md)).

A stack pronta está em [`assets/stacks/rustdesk-server.yml`](../assets/stacks/rustdesk-server.yml).

> ℹ️ **Quer acessar pelo navegador, inclusive na máquina da empresa?** O web client **oficial** do RustDesk é
> servido por `https://rustdesk.com/web`, que a empresa bloqueia por categoria, então ele não abre lá. A
> **[Parte 6](#parte-6-opcional-console-e-web-client-no-navegador-com-cortendesk)** monta o **CortenDesk**: um
> console + web client **OSS e gratuito**, com a **página no seu próprio domínio**, que por isso **funciona na
> empresa** e traz login próprio com 2FA. Alternativa já pronta e testada para a empresa: os targets de
> RDP/VNC/SSH do [RDP no Navegador (Cloudflare Access)](./cloudflare-browser-rdp.md). **O grosso deste guia**
> é gerenciar as máquinas a partir dos seus próprios dispositivos com o cliente nativo, e consolidar o
> servidor na VPS.

## Arquitetura

```
   Suas máquinas (cliente nativo)                       VPS Oracle (ARM)
   ┌────────────────────────────────┐                   ┌─────────────────────────────┐
   │ RustDesk (casa, trabalho...)   │   protocolo       │ stack rustdesk-server       │
   │  ID Server: rustdesk-id.<dom>  │   binário próprio │ ┌────────────┐ ┌──────────┐ │
   │  Key: <a mesma de sempre>      │──21116 tcp+udp───►│ │ hbbs (ID)  │ │ hbbr     │ │
   │                                │   21115/21117 tcp │ │ 21115/16/18│ │ (relay)  │ │
   └────────────────────────────────┘                   │ └────────────┘ │ 21117/19 │ │
                                                        │                └──────────┘ │
        Portas nativas expostas direto na VPS           └─────────────────────────────┘
        (Security List Oracle + firewall do host).
        NÃO passam por Cloudflare Tunnel (é UDP + protocolo próprio, não HTTP).
```

> ℹ️ **Por que as portas ficam expostas na internet:** o registro de ID usa **21116/UDP** e o protocolo do
> RustDesk **não é HTTP**. Cloudflare Tunnel só transporta HTTP/WebSocket, então essas portas não passam por
> ele. A segurança dessa camada é **app-layer**: a **Key** (criptografia ed25519, imposta com `-k _`) mais a
> **senha permanente forte por máquina**. O firewall por IP é complemento, não a defesa principal.

## Parte 1: Pegar a Key no servidor Windows

A "Key" é um **par de chaves** que o `hbbs` gerou no primeiro boot: `id_ed25519` (privada, **secreta**) e
`id_ed25519.pub` (pública, que os clientes colam no campo Key). Preservar esses dois arquivos mantém a Key
idêntica, então **nenhum cliente precisa ser reconfigurado**.

No Windows Server, os arquivos ficam na **pasta onde o `hbbs.exe` roda** (o servidor OSS é um ZIP portátil,
sem caminho fixo). Localize com:

```powershell
Get-ChildItem C:\ -Recurse -Filter 'id_ed25519*' -ErrorAction SilentlyContinue | Select-Object FullName
```

Copie os **dois** arquivos para um pendrive ou direto para a VPS. Transfira em **modo binário** (`scp`,
`docker cp`), nunca colando num editor de texto, para não inserir CRLF/BOM.

> ℹ️ **Alternativa sem arquivo (útil no Portainer):** em vez de mover os arquivos, você pode passar o
> **conteúdo do `id_ed25519`** (a chave secreta, base64 de linha única) na variável de ambiente `KEY`. O
> servidor deriva a mesma chave pública a partir dela. Se preferir esse caminho, adicione `-k ${KEY}` no
> `command` no lugar de `-k _` e defina `KEY` na aba Environment variables.

## Parte 2: Pastas e Key na VPS (via SSH, antes do deploy)

Crie a pasta antes de subir a stack, senão o Docker a cria como `root` e você pode ter dor de cabeça de
permissão depois:

```bash
ssh vps-oracle 'sudo mkdir -p /srv/rustdesk/data'
```

Coloque os dois arquivos da Key em `/srv/rustdesk/data/` **antes do primeiro boot**:

```bash
scp id_ed25519 id_ed25519.pub vps-oracle:/tmp/
ssh vps-oracle 'sudo mv /tmp/id_ed25519* /srv/rustdesk/data/ && \
  sudo chmod 600 /srv/rustdesk/data/id_ed25519 && \
  sudo chmod 644 /srv/rustdesk/data/id_ed25519.pub && \
  sudo chown root:root /srv/rustdesk/data/id_ed25519*'
```

> ⚠️ **Ordem importa.** Se o `hbbs` subir sem os arquivos, ele **gera um par novo** e sobrescreve a Key. Aí
> todos os clientes passam a falhar com "Key Mismatch" até você atualizar a Key em cada um. Coloque a Key
> antiga **primeiro**, depois faça o deploy.

## Parte 3: Abrir as portas na Oracle e no firewall do host

As portas nativas precisam estar abertas em **dois lugares**: na **Security List / NSG** do painel Oracle
**e** no firewall do host (`iptables`, ver [./vps-oracle.md](./vps-oracle.md#firewall)).

| Porta | Protocolo     | Serviço                                       |
| :---- | :------------ | :-------------------------------------------- |
| 21115 | TCP           | teste de tipo de NAT (hbbs)                   |
| 21116 | **TCP e UDP** | registro de ID (UDP) e hole punching (TCP)    |
| 21117 | TCP           | relay (hbbr)                                  |
| 21118 | TCP           | WebSocket do hbbs: **NÃO abrir** na Oracle    |
| 21119 | TCP           | WebSocket do hbbr: **NÃO abrir** na Oracle    |

> ⚠️ Não esqueça o **UDP na 21116**. É a porta de registro de ID: sem ela, os clientes não aparecem online.
> É o erro mais comum nesse setup.

> 🔒 **Deixe 21118/21119 fechadas na Oracle** (abra só `21115-21117` TCP + `21116` UDP). A stack as publica no
> host de propósito, para o CortenDesk ([Parte 6](#parte-6-opcional-console-e-web-client-no-navegador-com-cortendesk))
> alcançá-las por dentro. Expostas na internet seriam um risco real: o hbbs/hbbr **confiam cegamente** no
> `X-Real-IP` das conexões WebSocket, então dá para falsificar o IP de origem e furar log/allowlist.

## Parte 4: Deploy da stack no Portainer

1. Portainer → **Stacks** → **Add Stack** → Nome: `rustdesk-server`.
2. Cole o YAML de [`assets/stacks/rustdesk-server.yml`](../assets/stacks/rustdesk-server.yml).
3. Na aba **Environment variables**, adicione:
   - `RUSTDESK_RELAY_HOST` = o host público do relay, ex.: `rustdesk-id.selflabs.org` (ver Parte 5).
4. **Deploy the stack**.

Confira que subiu e que reaproveitou a Key (não gerou uma nova):

```bash
docker logs rustdesk-hbbs 2>&1 | grep -i 'key\|Listening'
# a chave pública servida (leia no host; a imagem é scratch, sem shell):
sudo cat /srv/rustdesk/data/id_ed25519.pub
```

> ℹ️ O `-k _` no `command` **exige** que os clientes usem a Key correta e recusa conexões sem criptografia.

## Parte 5: Repontar os clientes para a VPS

A **Key não muda** ao trocar de servidor (ela vem do par de chaves, não do endereço). Só o **endereço** muda.
Recomendo apontar para um **hostname**, não para o IP cru, para a próxima migração não exigir mexer em cliente:

1. No DNS do `selflabs.org`, crie um registro **A** `rustdesk-id` → **IP público da VPS**, com **proxy
   DESLIGADO** (nuvem cinza). O tráfego nativo não é HTTP, então não pode passar pelo proxy laranja.
2. Em cada cliente RustDesk → **Configurações → Rede → ID/Relay Server**:
   - **ID Server:** `rustdesk-id.selflabs.org`
   - **Relay Server:** deixe em branco (o cliente deduz da 21117 do ID Server).
   - **Key:** a mesma de sempre (o conteúdo do `id_ed25519.pub`).

> 💾 Como a Key foi preservada, o campo Key nos clientes **continua válido**. Você só troca o endereço do
> servidor.

## Parte 6: (Opcional) Console e web client no navegador com CortenDesk

O **[CortenDesk](https://github.com/marcpope/cortendesk)** dá ao seu servidor OSS um **console web** (frota,
usuários, address book, audit, OIDC, 2FA) e um **web client nativo** (TypeScript, WebCodecs, com transferência
de arquivo) que rodam **100% no seu domínio**. Como a página é servida por você (não pelo `rustdesk.com/web`),
ele **funciona até na máquina da empresa** que bloqueia `rustdesk.com`. Imagem multi-arch com **arm64 nativo**.

A stack está em [`assets/stacks/cortendesk.yml`](../assets/stacks/cortendesk.yml).

```
  Browser → Cloudflare (TLS) → cloudflared → Caddy → cortendesk:8080
                                                         │ (bridge WSS embutido)
                                                         ▼
                                         host.docker.internal:21118 (hbbs)
                                         host.docker.internal:21119 (hbbr)
```

> ℹ️ O container **já embute o bridge WSS**: faz `/ws/id` → hbbs:21118 e `/ws/relay` → hbbr:21119 sozinho,
> alcançando essas portas **publicadas no host** via `host.docker.internal`. O Caddy só aponta **tudo** para a
> 8080; não precisa rotear `/ws/*` na mão.

1. **Feche 21118/21119 na Oracle** (deixe só `21115-21117` TCP + `21116` UDP). O CortenDesk alcança as WS por
   dentro, e o hbbs/hbbr **confiam cegamente** no `X-Real-IP` do WebSocket, então essas portas não podem ficar
   expostas na internet (permitiria falsificar IP e furar log/allowlist).
2. **Crie um subdomínio novo** para o console (ex.: `rustdesk.selflabs.org`), **diferente** do `rustdesk-id`
   (que é nativo, nuvem cinza). No cloudflared, publique-o → `http://localhost:8080`.
3. **Pasta + permissão** (o passo que mais quebra). O php-fpm roda como `www-data`, e o SQLite precisa
   escrever **no diretório** (arquivos `-journal`/`-wal`), não só no `.sqlite`. Se a pasta ficar `root:root`,
   o login falha com `500` e `attempt to write a readonly database`:
   ```bash
   ssh vps-oracle 'sudo mkdir -p /srv/cortendesk/data'
   # depois do primeiro deploy, ajuste o dono para o UID real do www-data do container:
   ssh vps-oracle 'U=$(docker exec cortendesk id -u www-data); G=$(docker exec cortendesk id -g www-data); \
     sudo chown -R $U:$G /srv/cortendesk/data && sudo chmod 775 /srv/cortendesk/data && docker restart cortendesk'
   ```
4. **Caddy** ([./caddy.md](./caddy.md)): app com login **próprio**, **sem** `import authelia` (o forward-auth
   quebraria os WebSockets do web client):
   ```caddyfile
   http://rustdesk.selflabs.org {
           reverse_proxy cortendesk:8080
   }
   ```
   Recarregue com `docker restart caddy`.
5. **Deploy** no Portainer (stack `cortendesk`), com as **Environment variables** (a stack referencia tudo por
   `${VAR}`, então nada de domínio ou segredo fica hardcoded no arquivo):
   - `CORTENDESK_DOMAIN` = o subdomínio do console (ex.: `rustdesk.selflabs.org`)
   - `CORTENDESK_ID_SERVER` = `rustdesk-id.selflabs.org:21116`
   - `CORTENDESK_RELAY_SERVER` = `rustdesk-id.selflabs.org:21117`
   - `CORTENDESK_PUBLIC_KEY` = o conteúdo do `id_ed25519.pub`
   - `RUSTDESK_WS_HOST` = **o IP** do gateway do docker0, normalmente `172.17.0.1` (confira com
     `docker exec cortendesk getent hosts host.docker.internal`). Tem que ser IP, veja o aviso abaixo.
   - `CORTENDESK_ADMIN_USER` / `CORTENDESK_ADMIN_PASSWORD`

   > ⚠️ **Não use `host.docker.internal` no `RUSTDESK_WS_HOST`.** O nginx do container usa uma variável no
   > `proxy_pass`, e nesse caso ele resolve o nome em tempo de requisição pelo **resolver do Docker**
   > (`127.0.0.11`), **ignorando o `/etc/hosts`**. Como esse nome só existe no `/etc/hosts` (via
   > `extra_hosts`), o WebSocket falha com `could not be resolved (3: Host not found)` mesmo com o
   > `getent` e o `nc` funcionando (esses dois **usam** o `/etc/hosts`).
6. Abra `https://<console>`, faça login e **ative o 2FA** (TOTP). Como a página fica exposta com login próprio,
   sem Authelia na frente, o 2FA é a sua camada extra.
7. Para os **dispositivos aparecerem no console** (frota, address book, audit), aponte o **API Server** dos
   clientes RustDesk para o mesmo subdomínio. O connect-by-ID do web client já funciona sem isso.

> ⚠️ **Limitações do web client:** o navegador não abre socket cru, então **não há P2P nem IP direto**, toda
> sessão passa pelo **relay** (hbbr). Latência e banda dependem do relay na VPS (a Free Tier da Oracle tem cota
> de egress). Transferência de arquivo funciona; áudio e alguns codecs são limitados vs. o app nativo.

## Parte 7: Desativar o servidor Windows

Depois de validar que os clientes conectam pela VPS (registram, conectam e a sessão abre), pare o serviço do
RustDesk Server no Windows Server 2025. Mantenha uma cópia dos arquivos `id_ed25519*` guardada até ter certeza.

## Parte 8: Atualizar e backup

- **Atualizar:** Portainer → stack `rustdesk-server` → **Re-pull image and redeploy**. A stack usa a tag
  rolante `:latest`; um re-pull puxa a versão mais nova (a Key e o banco ficam no volume, então nada se perde).
- **Backup:** `/srv/rustdesk/data` inteiro. O crítico é o `id_ed25519` (privado): sem ele você perde a Key e
  reconfigura todos os clientes. Guarde-o cifrado, fora da VPS.

## Troubleshooting

| Sintoma                                          | Causa provável                                 | Correção                                                                                                                                        |
| :----------------------------------------------- | :--------------------------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------- |
| Clientes nunca ficam online (bolinha verde)      | **21116/UDP** fechada                          | Abra 21116 UDP na Security List Oracle **e** no `iptables` do host                                                                              |
| Todos os clientes com "Key Mismatch"             | Key não migrada; hbbs gerou par novo           | Pare a stack, ponha os `id_ed25519*` antigos em `/srv/rustdesk/data`, suba de novo                                                              |
| Conecta mas cai para relay sempre                | 21115/21116 TCP bloqueadas (sem hole punching) | Abra 21115 e 21116 TCP; confira NAT dos dois lados                                                                                              |
| Web client: `websocket error before open: wss://.../ws/id` e o log do nginx diz `host.docker.internal could not be resolved` | o nginx resolve variável do `proxy_pass` pelo DNS do Docker e ignora o `/etc/hosts` | Ponha **o IP** em `RUSTDESK_WS_HOST` (ex.: `172.17.0.1`), não o nome |
| Web client (CortenDesk) não conecta / tela preta | bridge WSS não alcança 21118/21119             | Confira o `RUSTDESK_WS_HOST` e as 21118/21119 publicadas no host pela stack `rustdesk-server`   |
| CortenDesk: login retorna `500` e o log diz `attempt to write a readonly database` | `/srv/cortendesk/data` está `root:root`; o `www-data` não consegue criar o journal/WAL do SQLite **no diretório** | `chown -R` para o UID real do `www-data` do container e `chmod 775` na pasta (Parte 6, passo 3), depois `docker restart cortendesk` |
| Container reinicia em loop                       | Key com permissão errada, ou volume vazio      | `chmod 600 id_ed25519`; confira o bind mount `/srv/rustdesk/data:/root`                                                                         |
| Imagem não sobe no ARM                           | tag sem manifesto arm64                        | A `:latest` do `rustdesk-server` e a do `cortendesk` são multi-arch com arm64 nativo                                                            |

## Notas Importantes

- **A Key é a defesa, não a rede.** As portas nativas ficam expostas na internet por necessidade do protocolo.
  Quem protege é a Key (`-k _`) e a **senha permanente forte por máquina**. Sem senha forte, IP direto na
  internet é risco real.
- **UDP obrigatório.** 21116 precisa de TCP **e** UDP. É o esquecimento nº 1.
- **Web client OSS é limitado e não serve à empresa.** Página em `rustdesk.com/web`, sem P2P, só relay. Para
  navegador na empresa, os targets do Cloudflare Access são o caminho.
- **Uma instância por stack.** Este servidor é self-contained; não compartilhe o volume com outra coisa.

## Acessos

| O quê                     | Onde                                                | Proteção                |
| :------------------------ | :-------------------------------------------------- | :---------------------- |
| Servidor de ID/Relay      | `rustdesk-id.selflabs.org` (portas nativas)         | Key + senha por máquina |
| Web client (redes livres) | `https://rustdesk.com/web` → seu ID Server          | Key + senha por máquina |
| Navegador na empresa      | ver [RDP no Navegador](./cloudflare-browser-rdp.md) | Cloudflare Access + MFA |

## Referências

- [RustDesk Server OSS (GitHub)](https://github.com/rustdesk/rustdesk-server)
- [RustDesk Docs: self-host OSS](https://rustdesk.com/docs/en/self-host/rustdesk-server-oss/)
- [RustDesk Server no Docker Hub](https://hub.docker.com/r/rustdesk/rustdesk-server/tags)
- [RDP no Navegador (este repo)](./cloudflare-browser-rdp.md) · [RustDesk Headless (este repo)](./rustdesk-headless.md) · [Caddy (este repo)](./caddy.md)
