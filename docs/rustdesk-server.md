# 🖧 RustDesk Server self-hosted (hbbs/hbbr na VPS)

Migrar o seu **RustDesk Server** (hoje no Windows Server 2025) para a **VPS Oracle** como stack Docker,
preservando a mesma **Key** para não reconfigurar cliente nenhum. Um servidor de ID/relay próprio para
controlar todas as suas máquinas com o cliente nativo do RustDesk, sem depender da nuvem pública da RustDesk.

**Pré-requisitos:** Docker + Portainer ([./portainer-debian.md](./portainer-debian.md)) e uma VPS com IP
público e portas abertas ([./vps-oracle.md](./vps-oracle.md)).

A stack pronta está em [`assets/stacks/rustdesk-server.yml`](../assets/stacks/rustdesk-server.yml).

> ⚠️ **Leia antes de esperar acessar pelo navegador da empresa.** O **web client** (RustDesk no navegador)
> **não** é a peça certa para a máquina corporativa, e a razão é técnica, não preguiça de configuração:
>
> - No RustDesk **OSS**, a **página** do web client é servida por `https://rustdesk.com/web`, e você só
>   aponta ela para o seu servidor. A máquina da empresa bloqueia `rustdesk.com` por categoria, então a
>   página **nem carrega** lá. Só os WebSockets iriam para o seu domínio, mas sem a página não há o que abrir.
> - Servir a **página no seu próprio domínio** é recurso do **RustDesk Server Pro** (pago, a partir de
>   US$ 47,88/mês), que já traz login próprio, OIDC/LDAP/2FA e controle de acesso por usuário.
> - Pôr **Authelia só na página** e deixar o WebSocket público **não protege nada**: o HTML é um cliente
>   genérico e substituível (qualquer um usa o `rustdesk.com/web` público apontando para o seu WSS), e a Key
>   é um valor único compartilhado, não autenticação por usuário. Seria teatro de segurança.
>
> **Para acessar pelo navegador da empresa, use os targets de RDP/VNC/SSH do
> [RDP no Navegador (Cloudflare Access)](./cloudflare-browser-rdp.md)**, que já resolvem isso com página e
> transporte 100% no seu domínio, autenticação real com MFA e nada de `rustdesk.com`. **Este guia aqui serve
> para gerenciar as suas máquinas a partir dos seus próprios dispositivos** (cliente nativo), e para
> consolidar o servidor na VPS. Se você quiser mesmo o RustDesk no navegador sob o seu domínio, o caminho
> limpo é o Server Pro.

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
| 21118 | TCP           | WebSocket do hbbs (só se for usar web client) |
| 21119 | TCP           | WebSocket do hbbr (só se for usar web client) |

> ⚠️ Não esqueça o **UDP na 21116**. É a porta de registro de ID: sem ela, os clientes não aparecem online.
> É o erro mais comum nesse setup.

## Parte 4: Deploy da stack no Portainer

1. Portainer → **Stacks** → **Add Stack** → Nome: `rustdesk-server`.
2. Cole o YAML de [`assets/stacks/rustdesk-server.yml`](../assets/stacks/rustdesk-server.yml).
3. Na aba **Environment variables**, adicione:
   - `RUSTDESK_RELAY_HOST` = o host público do relay, ex.: `rustdesk-id.selflabs.org` (ver Parte 5).
4. **Deploy the stack**.

Confira que subiu e que reaproveitou a Key (não gerou uma nova):

```bash
docker logs rustdesk-hbbs 2>&1 | grep -i 'key\|Listening'
# a chave pública em uso deve bater com o seu id_ed25519.pub antigo:
docker exec rustdesk-hbbs cat /root/id_ed25519.pub
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

## Parte 6: (Opcional) Web client via `rustdesk.com/web`

Isto habilita o acesso pelo navegador **de qualquer rede que NÃO bloqueie `rustdesk.com`** (a sua casa, por
exemplo). **Não funciona na máquina da empresa**, pelo motivo explicado no callout do topo. Para a empresa,
use o [RDP no Navegador](./cloudflare-browser-rdp.md).

1. Publique um hostname que faça o proxy dos **dois WebSockets** (a página vem de `rustdesk.com/web`, só os
   sockets passam pelo seu domínio). No seu Caddy ([./caddy.md](./caddy.md)):

   ```caddyfile
   rustdesk.selflabs.org {
       reverse_proxy /ws/id     host.docker.internal:21118 {
           header_up X-Real-IP {remote_host}
       }
       reverse_proxy /ws/relay  host.docker.internal:21119 {
           header_up X-Real-IP {remote_host}
       }
   }
   ```

2. Abra `https://rustdesk.com/web`, e em **Settings** aponte o **ID Server** para `rustdesk.selflabs.org` e
   cole a **Key**. Conecte pelo ID da máquina.

> ℹ️ **Limitações do web client:** o navegador não abre socket cru, então **não há P2P nem IP direto**, toda
> sessão passa **obrigatoriamente pelo relay** (hbbr). Latência e banda dependem do relay na VPS, e a Free
> Tier da Oracle tem cota de egress. Transferência de arquivo e áudio são limitados.

## Parte 7: Desativar o servidor Windows

Depois de validar que os clientes conectam pela VPS (registram, conectam e a sessão abre), pare o serviço do
RustDesk Server no Windows Server 2025. Mantenha uma cópia dos arquivos `id_ed25519*` guardada até ter certeza.

## Parte 8: Atualizar e backup

- **Atualizar:** Portainer → stack `rustdesk-server` → **Re-pull image and redeploy**. A stack pina
  `:1.1.16`; para saltar de versão, edite a tag (confira as versões em
  [hub.docker.com/r/rustdesk/rustdesk-server](https://hub.docker.com/r/rustdesk/rustdesk-server/tags)).
- **Backup:** `/srv/rustdesk/data` inteiro. O crítico é o `id_ed25519` (privado): sem ele você perde a Key e
  reconfigura todos os clientes. Guarde-o cifrado, fora da VPS.

## Troubleshooting

| Sintoma                                     | Causa provável                                 | Correção                                                                           |
| :------------------------------------------ | :--------------------------------------------- | :--------------------------------------------------------------------------------- |
| Clientes nunca ficam online (bolinha verde) | **21116/UDP** fechada                          | Abra 21116 UDP na Security List Oracle **e** no `iptables` do host                 |
| Todos os clientes com "Key Mismatch"        | Key não migrada; hbbs gerou par novo           | Pare a stack, ponha os `id_ed25519*` antigos em `/srv/rustdesk/data`, suba de novo |
| Conecta mas cai para relay sempre           | 21115/21116 TCP bloqueadas (sem hole punching) | Abra 21115 e 21116 TCP; confira NAT dos dois lados                                 |
| Web client não abre na máquina da empresa   | página vem de `rustdesk.com` (bloqueado)       | Esperado; use o [RDP no Navegador](./cloudflare-browser-rdp.md)                    |
| Container reinicia em loop                  | Key com permissão errada, ou volume vazio      | `chmod 600 id_ed25519`; confira o bind mount `/srv/rustdesk/data:/root`            |
| Imagem não sobe no ARM                      | tag sem manifesto arm64                        | A `:1.1.16` é multi-arch; se preciso, force `:1.1.16-arm64v8`                      |

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
