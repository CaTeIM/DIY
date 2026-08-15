# 🎬 Stack de Mídia (Plex + Jellyfin + \*arrs + qBittorrent)

Servidor de streaming doméstico automatizado rodando em uma Orange Pi 5 (Rockchip RK3588S). Você pede
um filme pelo celular, e alguns minutos depois ele aparece na sua "Netflix particular" já renomeado,
catalogado e legendado em português. Tudo self-hosted, sem nenhum serviço externo pago.

A stack pronta está em [`assets/stacks/midia.yml`](../assets/stacks/midia.yml).

> **Pré-requisito:** Docker e Portainer instalados. Ver [`./portainer-debian.md`](./portainer-debian.md).

> [!IMPORTANT]
> Antes de subir esta stack, leia [`./orangepi5-backup-restore.md`](./orangepi5-backup-restore.md).
> A configuração dos `*arrs` acumulada ao longo de meses (indexadores, perfis, formatos
> personalizados, histórico) vale mais que os arquivos de mídia, e ela só existe em `/srv`.

---

## Quem é quem

| Serviço          | Papel                                                                                 |
| :--------------- | :------------------------------------------------------------------------------------ |
| **qBittorrent**  | Cliente de torrent. Recebe os magnet links e baixa                                    |
| **Prowlarr**     | Agregador de indexadores. Alimenta Radarr e Sonarr com as fontes de torrent           |
| **FlareSolverr** | Proxy que resolve desafios Cloudflare de indexadores protegidos                       |
| **Radarr**       | Gerencia filmes: procura, baixa, renomeia, organiza e faz upgrade de qualidade        |
| **Sonarr**       | O mesmo para séries e animes, com agenda de episódios que ainda vão ao ar             |
| **Bazarr**       | Busca e sincroniza legendas para o que Radarr e Sonarr importaram                     |
| **Seerr**        | Portal de requisições. Fork do Overseerr. É por aqui que a família pede conteúdo      |
| **Plex**         | Player principal. Interface polida, apps em toda TV, console e celular                |
| **Jellyfin**     | Player alternativo, 100% aberto e o **único com transcode por hardware nesta placa**  |
| **Tautulli**     | Estatísticas e monitoramento de quem assistiu o quê no Plex                           |
| **Yamtrack**     | Histórico de exibição self-hosted. Recebe por webhook o que você assiste              |
| **FileBot**      | Renomeador manual (interface gráfica via navegador) para o que os `*arrs` não pegaram |

---

## Arquitetura

```
                        ┌──────────────┐
   Você / família ─────►│    Seerr     │  "quero assistir X"
                        └──────┬───────┘
                               │
                 ┌─────────────┴─────────────┐
                 ▼                           ▼
          ┌────────────┐              ┌────────────┐
          │   Radarr   │              │   Sonarr   │
          │  (filmes)  │              │  (séries)  │
          └─────┬──────┘              └──────┬─────┘
                │                            │
                └────────────┬───────────────┘
                             ▼
                     ┌───────────────┐      ┌───────────────┐
                     │   Prowlarr    │◄────►│  FlareSolverr │
                     │ (indexadores) │      │  (anti-CF)    │
                     └───────┬───────┘      └───────────────┘
                             │ magnet link
                             ▼
                     ┌───────────────┐
                     │  qBittorrent  │
                     └───────┬───────┘
                             │ baixa em /data/Downloads/torrents/
                             ▼
                 ╔═══════════════════════════╗
                 ║   /srv/midia  (HD 1 TB)   ║
                 ║  hardlink, sem duplicar   ║
                 ╚═══════╤═══════════╤═══════╝
                         │           │
              ┌──────────┘           └──────────┐
              ▼                                 ▼
       ┌────────────┐                    ┌────────────┐
       │   Bazarr   │  legendas          │ Plex/Jelly │──► TV, celular, PC
       └────────────┘                    └──────┬─────┘
                                                │ webhook ao assistir
                                   ┌────────────┴────────────┐
                                   ▼                         ▼
                            ┌────────────┐          ┌───────────────┐
                            │  Tautulli  │          │   Yamtrack    │
                            │ (só Plex)  │          │ (histórico)   │
                            └────────────┘          └───────┬───────┘
                                                            │
                                                    ┌───────▼───────┐
                                                    │ yamtrack-redis│
                                                    └───────────────┘
```

### Portas no host

| Porta           | Serviço      | Observação                                                                        |
| :-------------- | :----------- | :-------------------------------------------------------------------------------- |
| `8080/tcp`      | qBittorrent  | Web UI                                                                            |
| `62609/tcp+udp` | qBittorrent  | Porta de escuta do BitTorrent. Precisa ser aberta no roteador                     |
| `9696/tcp`      | Prowlarr     | Web UI                                                                            |
| `8191/tcp`      | FlareSolverr | API interna. **Não** expor à internet                                             |
| `7878/tcp`      | Radarr       | Web UI                                                                            |
| `8989/tcp`      | Sonarr       | Web UI                                                                            |
| `6767/tcp`      | Bazarr       | Web UI                                                                            |
| `5055/tcp`      | Seerr        | Web UI                                                                            |
| `32400/tcp`     | Plex         | `network_mode: host`                                                              |
| `8096/tcp`      | Jellyfin     | `network_mode: host`                                                              |
| `8181/tcp`      | Tautulli     | Web UI                                                                            |
| `8010/tcp`      | Yamtrack     | Web UI. Mapeia para a `8000` do container, porque a `8000` do host é do Portainer |
| `5800/tcp`      | FileBot      | Interface gráfica via navegador (noVNC)                                           |

---

## 🛠️ Parte 1: Preparação do Host

### 1.1. A regra de ouro: um volume só

Este é o ponto que separa uma stack que funciona de uma que enche o disco pela metade. Todos os
containers montam **o mesmo caminho**:

```yaml
- /srv/midia:/data
```

Quando o Radarr importa um filme baixado, ele cria um **hardlink**: um segundo nome apontando para
os mesmos blocos no disco. O arquivo aparece em `Filmes/` e continua em `Downloads/` para semear,
ocupando o espaço **uma vez só**. A operação é instantânea, mesmo num arquivo de 40 GB.

> [!WARNING]
> Hardlink só funciona **dentro do mesmo sistema de arquivos**. Se você montar
> `/srv/midia/Downloads:/downloads` e `/srv/midia/Filmes:/movies` como volumes separados, o Docker
> apresenta os dois como dispositivos diferentes dentro do container, o hardlink falha e o Radarr
> cai para cópia. Cada filme passa a ocupar o dobro.
>
> É exatamente por isso que esta stack diverge do tutorial do AkitaOnRails, que separa `/tv` e
> `/downloads`. Aqui seguimos o padrão do [TRaSH Guides](https://trash-guides.info/File-and-Folder-Structure/Hardlinks-and-Instant-Moves/).

Para conferir se está funcionando, procure arquivos com mais de um link:

```bash
find /srv/midia -type f -links +1 | head
```

Se a saída listar arquivos, os hardlinks estão ativos.

### 1.2. Criar a estrutura de pastas

```bash
# Biblioteca (no HD grande)
sudo mkdir -p /srv/midia/{Filmes,Series,Animes}
sudo mkdir -p /srv/midia/Downloads/torrents/{radarr,tv-sonarr}

# Configurações dos containers (no disco do sistema)
sudo mkdir -p /srv/qbittorrent/config
sudo mkdir -p /srv/prowlarr/config
sudo mkdir -p /srv/radarr/appdata/config
sudo mkdir -p /srv/sonarr/appdata/config
sudo mkdir -p /srv/bazarr/appdata/config
sudo mkdir -p /srv/overseerr/config
sudo mkdir -p /srv/plex/{config,transcode}
sudo mkdir -p /srv/jellyfin/{config,cache}
sudo mkdir -p /srv/tautulli/config
sudo mkdir -p /srv/yamtrack/{db,redis}
sudo mkdir -p /srv/filebot/config
```

> [!NOTE]
> O Jellyfin usa `tmpfs` para os arquivos temporários de transcode, então **não** existe pasta
> criada para eles. A pasta `/srv/jellyfin/cache` continua servindo para imagens e metadados.

### 1.3. Ajustar as permissões

Os containers rodam como UID/GID `1000`. Se as pastas ficarem como `root`, os serviços sobem e
falham com `EACCES` na primeira escrita.

```bash
sudo chown -R 1000:1000 /srv/midia
sudo chown -R 1000:1000 /srv/{qbittorrent,prowlarr,radarr,sonarr,bazarr,overseerr}
sudo chown -R 1000:1000 /srv/{plex,jellyfin,tautulli,yamtrack,filebot}
```

> O `yamtrack-redis` roda com `user: "1000:1000"` na stack justamente para caber nesse mesmo
> `chown`. A imagem oficial do Redis usaria o UID `999` e exigiria um comando à parte.

### 1.4. Confirmar os GIDs de vídeo (para o Jellyfin)

```bash
getent group video render
```

Saída esperada em uma Orange Pi 5:

```
video:x:44:orangepi
render:x:105:orangepi
```

Se os números forem diferentes na sua placa, ajuste o `group_add` do serviço `jellyfin` no YAML.

### 1.5. Liberar as portas no firewall (só para Plex e Jellyfin)

Esta é a pegadinha menos óbvia da stack, e ela atinge **apenas** os serviços em `network_mode: host`.

Containers que publicam portas com `ports:` são alcançáveis mesmo com o firewall fechado, porque o
Docker escreve as próprias regras na chain `DOCKER` do iptables e **contorna o UFW**. Já Plex e
Jellyfin usam a rede do host, então o tráfego bate na chain `INPUT` e obedece ao firewall.

O resultado confunde: Radarr e Sonarr abrem normalmente, e o Jellyfin não abre, mesmo com o
container saudável e respondendo em `localhost` dentro do servidor.

```bash
# O firewall está ativo e com política DROP?
sudo ufw status

# Liberar o Jellyfin
sudo ufw allow 8096/tcp comment 'Jellyfin'

# Opcional: descoberta automática pelos apps de TV e celular na LAN
sudo ufw allow 7359/udp comment 'Jellyfin discovery'
sudo ufw allow 1900/udp comment 'DLNA'

# O Plex costuma já estar liberado, confirme
sudo ufw status | grep 32400
```

Como diagnosticar quando algo em `network_mode: host` não abre:

```bash
# Dentro do servidor: o serviço está escutando e respondendo?
sudo ss -tlnp | grep 8096
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8096/
```

Se aqui responder (o Jellyfin devolve `302`, que é o redirect para `/web/`) e mesmo assim não abrir
de outra máquina, o problema é firewall, não o container.

### 1.6. Conferir os devices de vídeo do Rockchip

```bash
ls -l /dev/mpp_service /dev/rga /dev/mali0 && ls /dev/dri /dev/dma_heap
```

Todos devem existir. Se `/dev/mpp_service` faltar, o kernel não está com os drivers de VPU do
Rockchip e o transcode por hardware do Jellyfin não vai funcionar.

---

## 🔑 Parte 2: Configurar os Segredos

Na criação da stack, aba **Environment variables** do Portainer:

| Variável                | Obrigatória | Descrição                                                                                        |
| :---------------------- | :---------- | :----------------------------------------------------------------------------------------------- |
| `FILEBOT_VNC_PASSWORD`  | Sim         | Senha de acesso à interface gráfica do FileBot                                                   |
| `YAMTRACK_SECRET`       | Sim         | Chave de assinatura do Django no Yamtrack. Gere com `openssl rand -base64 48`                    |
| `YAMTRACK_REGISTRATION` | Não         | `True` no primeiro boot para criar sua conta. Troque para `False` depois                         |
| `YAMTRACK_URLS`         | Não         | Origens públicas confiáveis, se for expor por proxy reverso. Ex.: `https://yamtrack.exemplo.com` |
| `PLEX_CLAIM`            | Não         | Token de [plex.tv/claim](https://plex.tv/claim), válido por 4 minutos. Só no primeiro boot       |
| `PLEX_ADVERTISE_IP`     | Não         | Ex.: `http://192.168.x.x:32400/`. Ajuda o Plex a se anunciar na LAN                              |

Para gerar o segredo do Yamtrack:

```bash
openssl rand -base64 48
```

> [!WARNING]
> Trocar o `YAMTRACK_SECRET` depois invalida as sessões de login. Gere uma vez e guarde junto dos
> seus outros segredos.

> [!CAUTION]
> Nunca escreva senha diretamente no YAML. O arquivo da stack acaba no Git, em backup e no export
> do Portainer.

---

## 📦 Parte 3: Deploy via Portainer

1. Portainer → **Stacks** → **Add Stack**
2. **Nome:** `midia`
3. Colar o conteúdo de [`assets/stacks/midia.yml`](../assets/stacks/midia.yml) no **Web editor**
4. Preencher as **Environment variables** da Parte 2
5. **Deploy the stack**

> Alternativa via SSH: `docker compose -f midia.yml up -d`

### 3.1. Sobre a rede `midia-net`

Os serviços web ficam em uma rede bridge dedicada e **se enxergam por nome**. Ao configurar o
Radarr, o endereço do qBittorrent é `qbittorrent`, não o IP da máquina.

Isso importa: se a stack usar `network_mode: bridge` sem rede dedicada, cada serviço só alcança os
outros pelo IP do host. No dia em que o servidor mudar de IP (troca de roteador, DHCP, mudança de
faixa), **todos** os apontamentos quebram de uma vez.

Plex e Jellyfin são a exceção e ficam em `network_mode: host`, porque dependem de multicast para o
discovery na rede local e de acesso direto aos devices de vídeo.

Para os containers da rede bridge falarem com o Plex (que está na rede do host), a stack define
`extra_hosts: host.docker.internal:host-gateway` no Tautulli e no Seerr.

No sentido inverso, quando o Jellyfin (rede do host) precisa alcançar o Yamtrack (rede bridge com
porta publicada), o endereço é simplesmente `http://localhost:8010`.

---

## ⬇️ Parte 4: qBittorrent

Acesse `http://192.168.x.x:8080`.

### 4.1. Primeiro login

Versões recentes geram uma senha temporária no log:

```bash
docker logs qbittorrent 2>&1 | grep -i "temporary password"
```

Troque em **Ferramentas** → **Opções** → **Interface Web**.

### 4.2. Liberar o acesso por nome de host

Este passo é obrigatório com a rede `midia-net` e é a causa mais comum de "o Radarr não conecta no
qBittorrent" depois da migração.

Em **Opções** → **Interface Web**, na seção **Segurança**:

- **Desmarcar** "Habilitar validação do cabeçalho Host" (`Enable host header validation`)

Sem isso, o qBittorrent devolve `401 Unauthorized` para requisições que chegam com `Host: qbittorrent`.

### 4.3. Downloads

Em **Opções** → **Downloads**:

| Configuração                                      | Valor                       |
| :------------------------------------------------ | :-------------------------- |
| Modo de gerenciamento padrão dos torrents         | **Automático**              |
| Quando a categoria do torrent for mudada          | Re-alocar torrent           |
| Quando o caminho padrão de salvamento mudar       | Re-alocar torrents afetados |
| Caminho padrão de salvamento                      | `/data/Downloads/torrents`  |
| Pré-alocar espaço em disco para todos os arquivos | Marcado                     |

> [!IMPORTANT]
> O modo **Automático** é o que faz o qBittorrent respeitar as pastas por categoria que o Radarr e
> o Sonarr enviam. No modo Manual, tudo cai na mesma pasta e a organização não acontece.

### 4.4. Categorias

O Radarr e o Sonarr criam as categorias sozinhos no primeiro download. Se quiser adiantar, clique
com o botão direito em **Categorias** → **Adicionar categoria**:

| Categoria   | Caminho de salvamento                |
| :---------- | :----------------------------------- |
| `radarr`    | `/data/Downloads/torrents/radarr`    |
| `tv-sonarr` | `/data/Downloads/torrents/tv-sonarr` |

### 4.5. Porta de conexão

Em **Opções** → **Conexão**, defina a porta de entrada como **62609** (a mesma publicada no YAML) e
abra essa porta TCP e UDP no roteador. Sem redirecionamento, você só consegue conexões de saída e a
velocidade despenca.

---

## 🔍 Parte 5: Prowlarr e FlareSolverr

Acesse `http://192.168.x.x:9696`.

### 5.1. Registrar o FlareSolverr

**Settings** → **Indexers** → **+** (em Indexer Proxies) → **FlareSolverr**:

| Campo | Valor                      |
| :---- | :------------------------- |
| Name  | `FlareSolverr`             |
| Tags  | `flaresolverr`             |
| Host  | `http://flaresolverr:8191` |

Depois, em cada indexador que exija Cloudflare, adicione a tag `flaresolverr`.

### 5.2. Conectar Radarr e Sonarr

**Settings** → **Apps** → **+** → **Radarr**:

| Campo           | Valor                                 |
| :-------------- | :------------------------------------ |
| Sync Level      | `Full Sync`                           |
| Prowlarr Server | `http://prowlarr:9696`                |
| Radarr Server   | `http://radarr:7878`                  |
| API Key         | Radarr → Settings → General → API Key |

Repita para o Sonarr com `http://sonarr:8989`.

Com `Full Sync`, o Prowlarr cadastra, atualiza e remove indexadores no Radarr e no Sonarr sozinho.
Você nunca mais mexe em indexador dentro deles.

### 5.3. Adicionar indexadores

**Indexers** → **Add Indexer**. Filtre por **Privacy: Public** e **Categories: Movies, TV**.

Referência do que está em uso hoje nesta instalação (18 ativos):

`1337x`, `Bangumi Moe`, `BitSearch`, `Internet Archive`, `Knaben`, `LimeTorrents`, `nekoBT`,
`NoNaMe Club`, `Nyaa.si`, `SubsPlease`, `sukebei.nyaa.si`, `The Pirate Bay`, `Torrent Downloads`,
`TorrentDownload`, `TorrentGalaxyClone`, `Uindex`, `UniOtaku`, `YTS`.

> `Nyaa.si`, `SubsPlease`, `Bangumi Moe`, `nekoBT` e `UniOtaku` são os que realmente entregam anime.
> Para filme e série em português, `Knaben` e `BitSearch` costumam render mais que os genéricos.

Depois de adicionar, clique em **Test All Indexers** e remova os que falharem. Por fim,
**Sync App Indexers**.

> [!TIP]
> Não habilite tudo. Cada indexador é uma requisição a mais em cada busca. Passando de uns 20, a
> busca fica lenta e alguns indexadores começam a dar timeout.

---

## 🎞️ Parte 6: Radarr (filmes)

Acesse `http://192.168.x.x:7878`.

### 6.1. Nomenclatura

**Settings** → **Media Management** → marcar **Rename Movies** e **Replace Illegal Characters**.

- **Colon Replacement:** `Delete`
- **Standard Movie Format:**

```
{Movie CleanTitle} {(Release Year)} {imdb-{ImdbId}} {edition-{Edition Tags}} {[Custom Formats]}{[Quality Full]}{[MediaInfo 3D]}{[MediaInfo VideoDynamicRangeType]}{[Mediainfo AudioCodec}{ Mediainfo AudioChannels]}{[Mediainfo VideoCodec]}{-Release Group}
```

- **Movie Folder Format:**

```
{Movie CleanTitle} ({Release Year}) {imdb-{ImdbId}}
```

O `{imdb-{ImdbId}}` é o detalhe que mais economiza dor de cabeça: com o ID do IMDb no nome da pasta,
o Plex e o Jellyfin acertam o filme na primeira varredura, sem depender de heurística de título.

### 6.2. Importação

Ainda em **Media Management**, seção **Importing**:

| Configuração                       | Valor       |
| :--------------------------------- | :---------- |
| **Use Hard Links instead of Copy** | **Marcado** |
| Skip Free Space Check              | Marcado     |
| Import Extra Files                 | Desmarcado  |

### 6.3. Lixeira

Em **Media Management** → **File Management** → **Recycling Bin**, informe um caminho, por exemplo
`/data/Downloads/lixeira`.

> [!NOTE]
> Neste servidor a lixeira está **vazia** hoje. Sem ela, quando o Radarr faz upgrade de qualidade,
> o arquivo antigo é apagado direto, sem rede de segurança. Com a lixeira configurada, você tem
> alguns dias para perceber que o "upgrade" ficou pior que o original.

Também em **File Management**: **Propers and Repacks** → `Do not Prefer`.

### 6.4. Pastas raiz

**Settings** → **Media Management** → **Root Folders** → adicionar `/data/Filmes`.

> [!WARNING]
> **Limpeza necessária nesta instalação.** Hoje o Radarr tem duas pastas raiz cadastradas:
> `/data/Filmes` e `/data/radarr/movies`. Duas raízes fazem o Radarr espalhar filmes em dois
> lugares dependendo de onde o item foi adicionado.
>
> Antes de remover a raiz sobrando, verifique se há mídia nela:
>
> ```bash
> ls -la /srv/midia/radarr/
> ```
>
> Se houver, mova para `/srv/midia/Filmes/` e reaponte a pasta raiz dos filmes afetados pelo modo
> de seleção em massa (ver quadro na Parte 7.1). Só então remova a raiz antiga.

### 6.5. Formatos personalizados

**Settings** → **Custom Formats** → **+** → **Import**.

Os três essenciais, com os `trash_id` do [TRaSH Guides](https://trash-guides.info/):

| Formato        | `trash_id`                         | Pontuação | Para quê                                                          |
| :------------- | :--------------------------------- | :-------- | :---------------------------------------------------------------- |
| **BR-DISK**    | `ed38b889b31be83fda192888e2286d83` | `-10000`  | Bloqueia releases ISO/BD completos, de 50 GB, que o Plex nem abre |
| **3D**         | `b8cd450cbfa689c0259a01d9e29ba3d6` | `-10000`  | Bloqueia releases 3D (SBS, Half-OU)                               |
| **Open Matte** | `09d9dd29a0fc958f9796e65c2a8864b4` | `25`      | Prefere versões com o quadro completo, sem corte                  |

> [!TIP]
> Pegue o JSON sempre atualizado em
> [trash-guides.info/Radarr/Radarr-collection-of-custom-formats](https://trash-guides.info/Radarr/Radarr-collection-of-custom-formats/).
> Os regex mudam com o tempo, e um regex velho de BR-DISK deixa passar exatamente o que ele deveria
> bloquear. Quem quiser automatizar, o [Recyclarr](https://recyclarr.dev/) sincroniza os formatos do
> TRaSH direto para o Radarr e o Sonarr.

> [!CAUTION]
> **Criar o formato não bloqueia nada.** Esta é a parte que mais confunde, e é onde a configuração
> costuma ficar pela metade.
>
> O formato personalizado só define **o que casar** (o regex). Quem define **o peso** é o
> **perfil de qualidade**, numa tela completamente diferente (Parte 6.6). Um formato recém-criado
> nasce com pontuação **0** em todos os perfis, e pontuação 0 significa "tanto faz": o BR-DISK
> continua sendo baixado normalmente.
>
> Ou seja, são **dois passos obrigatórios**:
>
> 1. **Settings → Custom Formats**: criar o formato com o regex (define o "o quê")
> 2. **Settings → Profiles → editar o perfil**: descer até **Custom Formats** e atribuir a
>    pontuação (define o "quanto")
>
> Se você abrir o perfil e vir `3D 0` e `BR-DISK 0`, os filtros **estão inativos**, mesmo com os
> formatos criados e os regex corretos.

Qualquer formato com pontuação negativa nunca é baixado. É assim que você impede o servidor de
encher com um único BD-REMUX de 80 GB.

### 6.6. Perfil de qualidade

**Settings** → **Profiles** → editar `Any`. A tela tem três blocos, e é comum configurar só o
primeiro.

**Bloco 1: regras de upgrade** (topo da tela)

| Campo                                 | Valor sugerido                | O que faz                                                                               |
| :------------------------------------ | :---------------------------- | :-------------------------------------------------------------------------------------- |
| Upgrades Allowed                      | marcado                       | Permite trocar por uma versão melhor depois                                             |
| Upgrade Until                         | `WEB 1080p` ou `Bluray-1080p` | Teto de qualidade. Chegou aqui, para de procurar                                        |
| Minimum Custom Format Score           | `0`                           | Nota mínima aceita. Abaixo disso, não baixa                                             |
| Upgrade Until Custom Format Score     | `10000`                       | Teto de nota. Serve para continuar melhorando por formato mesmo já no teto de qualidade |
| Minimum Custom Format Score Increment | `1`                           | Ganho mínimo para valer a pena trocar o arquivo                                         |
| Language                              | `Any` ou `Original`           | `Original` evita baixar dublagem por engano                                             |

**Bloco 2: qualidades** (a lista com caixas)

Marque da melhor até o piso que você tolera. Ordem = preferência, o topo é o mais desejado.

> [!TIP]
> **Desmarque `Remux-1080p`, `Remux-2160p`, `Bluray-2160p` e `Raw-HD`** se o espaço importa. Um
> Remux tem de 40 a 80 GB e, nesta placa, ainda força transcode em quase todo cliente. Deixar
> `WEB 1080p` como teto entrega arquivos de 2 a 5 GB que tocam em Direct Play.
>
> Manter as qualidades baixas marcadas (`CAM`, `TELESYNC`, `SDTV`) só faz sentido com **Upgrades
> Allowed** ligado: o Radarr baixa a porcaria agora e troca sozinho quando sair coisa melhor. Se
> você prefere esperar, desmarque todas abaixo de `WEB 720p`.

**Bloco 3: pontuação dos formatos personalizados** (o final da tela, precisa rolar)

É aqui que os formatos da Parte 6.5 ganham efeito:

| Formato           | Pontuação | Efeito                                                                           |
| :---------------- | --------: | :------------------------------------------------------------------------------- |
| **BR-DISK**       |  `-10000` | Nunca baixa                                                                      |
| **3D**            |  `-10000` | Nunca baixa                                                                      |
| **Open Matte**    |      `25` | Prefere, mas aceita outros se não houver                                         |
| HEVC              |    `1000` | Prefere fortemente HEVC (economiza espaço, e o Jellyfin decodifica por hardware) |
| WEBRip Preference |      `10` | Leve preferência por WEBRip                                                      |

> [!WARNING]
> Qualquer formato deixado em `0` **não faz nada**. Se o seu BR-DISK e o 3D estiverem zerados, eles
> não estão bloqueando release nenhum, por mais correto que esteja o regex.
>
> Uma pontuação negativa só bloqueia de fato se for **menor que o `Minimum Custom Format Score`**.
> Com o mínimo em `0`, qualquer valor negativo já barra, e é por isso que `-10000` é o exagero
> proposital recomendado pelo TRaSH: garante o bloqueio mesmo somado a bônus de outros formatos.

Com upgrade ligado, um filme que só existe em CAM é baixado agora e substituído automaticamente
quando sair o Bluray.

> Para conteúdo dublado, existe um guia complementar do mesmo autor:
> [Guia: filmes dublados automáticos no Radarr](https://www.reddit.com/r/pirataria/comments/1d3i69f/guia_filmes_dublados_autom%C3%A1ticos_no_radarr_e/).

### 6.7. Cliente de download

**Settings** → **Download Clients** → **+** → **qBittorrent**:

| Campo    | Valor         |
| :------- | :------------ |
| Host     | `qbittorrent` |
| Port     | `8080`        |
| Username | seu usuário   |
| Password | sua senha     |
| Category | `radarr`      |

Em **Completed Download Handling**, marcar **Remove Completed**.

> [!NOTE]
> Hoje esta instalação usa `192.168.68.9` como host. Depois de migrar para a rede `midia-net`, troque
> pelo nome `qbittorrent`. Se der `401 Unauthorized`, falta o passo 4.2.

### 6.8. Listas automáticas (opcional)

Dá para o Radarr monitorar uma lista do Letterboxd e baixar tudo que você adicionar lá pelo celular.

1. Crie a lista no [Letterboxd](https://letterboxd.com/)
2. Troque `letterboxd.com` por `letterboxd-list-radarr.onrender.com` na URL. Isso gera um feed que o
   Radarr entende
3. **Settings** → **Lists** → **+** → **Advanced** → **Custom Lists**

| Campo                | Valor          |
| :------------------- | :------------- |
| Enable Automatic Add | Marcado        |
| Monitor              | `Movie Only`   |
| Search on Add        | Marcado        |
| Minimum Availability | `Announced`    |
| Root Folder          | `/data/Filmes` |
| List URL             | a URL gerada   |

Em **Options** → **Clean Library Level**: `Remove Movie and Delete Files` faz o filme sumir do
servidor quando você tira da lista. Útil com pouco espaço, perigoso se você esquecer que está ligado.

---

## 📺 Parte 7: Sonarr (séries e animes)

Acesse `http://192.168.x.x:8989`.

### 7.1. Nomenclatura

**Settings** → **Media Management**, marcar **Rename Episodes** e **Replace Illegal Characters**.

Há duas escolas aqui, e as duas funcionam. A diferença é o quanto de metadado você quer dentro do
nome do arquivo.

#### Formato enxuto (o usado nesta instalação)

Nomes curtos e legíveis. A informação técnica fica dentro do arquivo, não no nome.

| Campo                           | Valor                                           |
| :------------------------------ | :---------------------------------------------- |
| Formato do Episódio Padrão      | `S{Season:00}E{Episode:00} - {Episode Title}`   |
| Formato do episódio diário      | `{Series Title} - {Air-Date} - {Episode Title}` |
| Formato do episódio de anime    | `S{Season:00}E{Episode:00} - {Episode Title}`   |
| Formato de Pasta das Séries     | `{Series Title}`                                |
| Formato da Pasta da Temporada   | `Season {season:00}`                            |
| Formato da Pasta para Especiais | `Specials`                                      |
| Estilo de multiepisódio         | `Faixa Prefixada`                               |
| Substituto para dois-pontos     | `Substituição inteligente`                      |

Resultado: `Steins;Gate/Season 01/S01E12 - Dogma in Event Horizon.mkv`

#### Formato completo (TRaSH Guides)

Carrega qualidade, codec, canais de áudio e grupo de release no nome, o que ajuda a decidir sem
abrir o arquivo e a diferenciar duas versões do mesmo episódio.

```
{Series TitleYear} - S{season:00}E{episode:00} - {Episode CleanTitle} [{Preferred Words }{Quality Full}]{[MediaInfo VideoDynamicRangeType]}{[Mediainfo AudioCodec}{ Mediainfo AudioChannels]}{[MediaInfo VideoCodec]}{-Release Group}
```

Para anime, o formato do TRaSH acrescenta `{absolute:000}` (numeração absoluta, que muitos grupos de
fansub usam) e `{MediaInfo AudioLanguages}`, que separa legendado de dublado:

```
{Series TitleYear} - S{season:00}E{episode:00} - {absolute:000} - {Episode CleanTitle} [{Preferred Words }{Quality Full}]{[MediaInfo VideoDynamicRangeType]}[{MediaInfo VideoBitDepth}bit]{[MediaInfo VideoCodec]}[{Mediainfo AudioCodec} { Mediainfo AudioChannels}]{MediaInfo AudioLanguages}{-Release Group}
```

#### O que realmente importa: o ID na pasta da série

> [!IMPORTANT]
> Independente do formato escolhido para o **arquivo**, coloque o ID externo no **nome da pasta da
> série**:
>
> ```
> {Series TitleYear} {tvdb-{TvdbId}}
> ```
>
> Sem isso, Plex e Jellyfin identificam a série **adivinhando pelo título**, e erram. É exatamente
> essa a causa de uma pasta de anime ser catalogada como um documentário da BBC, com pôster e
> sinopse errados: o scanner achou um título parecido no banco de dados e assumiu.
>
> Com o ID no nome, não há adivinhação. O scanner lê o identificador e busca o registro exato.
> Para séries e animes o Sonarr usa **TVDB**, então prefira `{tvdb-{TvdbId}}`. O Radarr usa
> **IMDb**, e por isso a Parte 6.1 usa `{imdb-{ImdbId}}` nas pastas de filme.

#### Como aplicar em massa (Sonarr v4)

O antigo **Mass Editor** saiu do menu lateral na versão 4. As ações em massa agora ficam atrás de um
modo de seleção:

1. **Séries** → botão **Selecionar a Série** na barra de ferramentas do topo
2. Marque as séries, ou use **Selecionar tudo**
3. Uma barra de ações aparece **no rodapé** da página:

| Ação no rodapé                         | Para que serve                                                                   |
| :------------------------------------- | :------------------------------------------------------------------------------- |
| **Editar**                             | É o antigo Mass Editor: Perfil de Qualidade, **Pasta Raiz**, Tipo de Série, Tags |
| **Renomear Arquivos**                  | Renomeia **apenas os arquivos** de episódio, nunca as pastas                     |
| Definir tags / Atualizar Monitoramento | O que o nome diz                                                                 |

> [!CAUTION]
> **"Renomear Arquivos" não renomeia pastas, e é aí que quase todo mundo trava.** O próprio modal
> avisa: _"deseja organizar todos os **arquivos** da N série selecionada?"_. Se você mudou o
> **Formato de Pasta das Séries** e rodou o Organizar, os arquivos são renomeados e as pastas
> continuam com o nome velho, sem o `{tvdb-...}`.

**Para renomear as PASTAS**, o caminho é outro, e a própria interface o descreve:

1. **Séries** → **Selecionar a Série** → **Selecionar tudo**
2. No rodapé, **Editar**
3. Deixe tudo em "Sem alteração", **exceto Pasta raiz**
4. Em **Pasta raiz**, escolha **a mesma pasta em que as séries já estão** (`/data/Animes`)
5. **Aplicar mudanças**

A dica embaixo do campo confirma: _"Mover séries para a mesma pasta raiz pode ser usado para
renomear pastas de séries para corresponder ao título atualizado ou formato de nomenclatura"_.

Parece que não faz nada, mas o Sonarr recalcula o nome de cada pasta com o formato novo e move as
séries. Como origem e destino estão no mesmo sistema de arquivos, é um `rename` de inode:
**instantâneo, mesmo com centenas de GB, e sem quebrar os hardlinks** que o qBittorrent usa para
semear.

Resumindo qual botão usar:

| Você mudou...                         | Use                                             |
| :------------------------------------ | :---------------------------------------------- |
| Formato do Episódio (nome do arquivo) | **Renomear Arquivos**                           |
| **Formato de Pasta das Séries**       | **Editar** → **Pasta raiz** → a mesma pasta     |
| Os dois                               | Primeiro a Pasta raiz, depois Renomear Arquivos |

Feito isso, rode **Update Library** no Plex e **Atualizar metadados** no Jellyfin.

> [!TIP]
> Como as séries normais e os animes estão em raízes diferentes, repita o processo uma vez por raiz,
> filtrando a lista antes de selecionar. Selecionar séries de `/data/Animes` e apontar para
> `/data/Series` moveria tudo de lugar.

### 7.2. Importação e pastas raiz

- **Use Hard Links instead of Copy:** marcado
- **Root Folders:** `/data/Series` e `/data/Animes`

Ao adicionar uma série, escolha **Series Type: Anime** para animes, o que faz o Sonarr usar o formato
de nomenclatura de anime e a numeração absoluta.

> [!WARNING]
> **Limpeza necessária nesta instalação.** O Sonarr tem hoje **quatro** pastas raiz cadastradas:
> `/data/Series`, `/data/Animes`, `/data/sonarr/tv` e `/data/sonarr/anime`. Aplique o mesmo
> procedimento da seção 6.4: verifique `/srv/midia/sonarr/`, mova o que houver e use o
> modo de seleção em massa antes de remover as raízes antigas.

### 7.3. Cliente de download

Igual ao Radarr, com **Category:** `tv-sonarr`.

---

## 💬 Parte 8: Bazarr (legendas)

Acesse `http://192.168.x.x:6767`.

### 8.1. Conectar aos `*arrs`

**Settings** → **Sonarr**: habilitar, Address `sonarr`, Port `8989`, API Key do Sonarr.
**Settings** → **Radarr**: habilitar, Address `radarr`, Port `7878`, API Key do Radarr.

### 8.2. Idiomas

**Settings** → **Languages**:

1. **Languages Filter:** `Brazilian Portuguese`
2. **Add New Profile** → nome `Português` → **Add Language** → `Brazilian Portuguese`
3. Em **Default Settings**, habilitar **Series** e **Movies**, ambos com o perfil `Português`

### 8.3. Legendas

**Settings** → **Subtitles**:

A tela é longa, então vai por blocos.

**Subtitle File Options**

| Configuração                            | Valor                  | Por quê                                                       |
| :-------------------------------------- | :--------------------- | :------------------------------------------------------------ |
| Subtitle Folder                         | `AlongSide Media File` | A legenda fica ao lado do vídeo, como Plex e Jellyfin esperam |
| Encode Subtitles To UTF-8               | ligado                 | Evita acento quebrado em legenda pt-BR                        |
| Change Subtitle File Permission (chmod) | `0644`                 | Ver aviso abaixo                                              |

> [!WARNING]
> **`0640` é arriscado.** Com esse valor só o dono e o grupo leem o arquivo. Como Bazarr, Plex e
> Jellyfin rodam todos com UID `1000`, funciona por coincidência, até você mexer em alguma
> permissão ou adicionar um serviço com outro UID. Use **`0644`**.

**Embedded Subtitles Handling**

| Configuração                           | Valor     | Por quê                                        |
| :------------------------------------- | :-------- | :--------------------------------------------- |
| Treat Embedded Subtitles as Downloaded | ligado    | Não baixa legenda se o arquivo já tem uma      |
| Parser                                 | `ffprobe` | Mais rápido que o mediainfo e já vem instalado |
| **Ignore Embedded PGS Subtitles**      | **ligar** | Ver dica abaixo                                |
| Ignore Embedded VobSub Subtitles       | ligar     | Mesmo motivo do PGS                            |
| Show Only Desired Languages            | ligado    | Esconde o que não interessa                    |

> [!TIP]
> **Ligue "Ignore Embedded PGS/VobSub".** As duas são legenda em **imagem**, não em texto. Para
> exibir, o player precisa **queimar a legenda no vídeo**, e isso força transcode mesmo num arquivo
> que seria Direct Play.
>
> Ignorando as embutidas, o Bazarr entende que falta legenda de texto e baixa um `.srt` externo, que
> não força transcode nenhum. Nesta placa isso é a diferença entre assistir e engasgar.

**Performance / Optimization**

| Configuração                            | Valor     | Observação                                                                       |
| :-------------------------------------- | :-------- | :------------------------------------------------------------------------------- |
| Adaptive Searching                      | ligado    | Evita martelar provedores atrás de legenda que não existe                        |
| Search Enabled Providers Simultaneously | ligado    | A tela desaconselha em "low powered devices", mas com 8 núcleos aqui é tranquilo |
| Skip video file hash calculation        | desligado | O hash é o que dá o melhor casamento de legenda                                  |

**Sub-Zero Modifications**

| Configuração     | Valor     | Por quê                                                             |
| :--------------- | :-------- | :------------------------------------------------------------------ |
| OCR Fixes        | ligado    | Corrige `I`/`l`/`1` trocados em legenda vinda de OCR                |
| **Common Fixes** | **ligar** | Arruma espaçamento e pontuação. Não há motivo para deixar desligado |
| Hearing Impaired | desligado | Só ligue para remover marcações de som                              |
| Fix Uppercase    | desligado | Ligue apenas se pegar legenda toda em caixa alta                    |

**Audio Synchronization**, a parte que mais resolve na prática

| Configuração                                     | Valor                          | Por quê                                 |
| :----------------------------------------------- | :----------------------------- | :-------------------------------------- |
| Enable Automatic Subtitles Audio Synchronization | ligado                         | Alinha a legenda com o áudio            |
| Synchronization Reference                        | `Use Audio Track as Reference` | Mais confiável que usar outra legenda   |
| **Do Not Fix Framerate Mismatch**                | **DESLIGAR**                   | Ver aviso abaixo                        |
| Golden-Section Search                            | ligado                         | Busca o melhor ajuste                   |
| Max Offset Seconds                               | `60`                           | Suficiente para o desalinhamento normal |

> [!CAUTION]
> **"Do Not Fix Framerate Mismatch" ligado atrapalha justamente o pior caso de dessincronia.**
>
> Quando a legenda foi feita para uma versão em 23,976 fps e o arquivo é 25 fps (ou o contrário), o
> erro **cresce ao longo do episódio**: começa certo e termina minutos fora. Corrigir isso exige
> ajustar o framerate, que é exatamente o que essa opção impede.
>
> Desligue. O nome confunde: você quer **sim** que ele corrija o framerate.

**Translating** (opcional)

Com um tradutor selecionado e score alto, o Bazarr **traduz por máquina** quando não encontra legenda
em português. Resolve a ausência, mas a qualidade fica bem abaixo de uma legenda humana. Se preferir
só legenda de verdade, deixe o tradutor vazio.

A sincronização automática é o recurso que mais vale a pena aqui: o Bazarr alinha o tempo da legenda
com o áudio do arquivo, resolvendo o clássico "a legenda está 3 segundos adiantada".

### 8.4. Provedores

**Settings** → **Providers** → **+** → `OpenSubtitles.com` (o `.org` foi descontinuado). Crie a conta
no site e informe usuário e senha.

---

## 🎯 Parte 9: Seerr (requisições)

Acesse `http://192.168.x.x:5055`.

O Seerr é o fork comunitário do Overseerr. É a interface que você compartilha com a família: eles
pesquisam, clicam em "Request", e o pedido cai direto no Radarr ou no Sonarr.

1. Login com a conta Plex
2. **Settings** → **Plex**: hostname `host.docker.internal`, porta `32400`
3. **Settings** → **Services** → **Radarr**: hostname `radarr`, porta `7878`, API Key, Root Folder
   `/data/Filmes`
4. **Settings** → **Services** → **Sonarr**: hostname `sonarr`, porta `8989`, API Key, Root Folder
   `/data/Series`
5. **Settings** → **Users**: crie contas para a família com permissão de request, mas sem
   auto-aprovação, se quiser dar o aval antes de cada download

> O hostname do Plex é `host.docker.internal` porque o Plex roda em `network_mode: host` enquanto o
> Seerr está na rede `midia-net`. A stack já declara o `extra_hosts` que faz esse nome resolver.

---

## 🎥 Parte 10: Plex

Acesse `http://192.168.x.x:32400/web`.

### 10.1. Primeiro boot

Se o servidor não aparecer vinculado à sua conta, pegue um token em
[plex.tv/claim](https://plex.tv/claim) e coloque em `PLEX_CLAIM` nas Environment variables do
Portainer. O token vale **4 minutos**, então gere e faça o redeploy na sequência.

### 10.2. Bibliotecas

| Biblioteca | Tipo     | Pasta          |
| :--------- | :------- | :------------- |
| Filmes     | Movies   | `/data/Filmes` |
| Séries     | TV Shows | `/data/Series` |
| Animes     | TV Shows | `/data/Animes` |

### 10.3. Configurações recomendadas

**Configurações** → **Biblioteca**:

| Configuração                                          | Estado       |
| :---------------------------------------------------- | :----------- |
| Digitalizar minha biblioteca automaticamente          | Habilitado   |
| Executar varredura parcial quando detectar alterações | Habilitado   |
| Escanear minha biblioteca periodicamente              | Desabilitado |
| Esvaziar lixeira automaticamente após cada varredura  | Habilitado   |
| Permitir exclusão de mídia                            | Desabilitado |
| Executar tarefas de varredura em prioridade menor     | Habilitado   |

Desligar a varredura periódica e deixar só a detecção de alterações economiza bastante CPU numa
placa ARM.

**Gerenciar** → **Bibliotecas** → **Editar** → **Avançado**, para Filmes:

- Scanner e Agente: `Plex Movie`
- **Usar recursos locais:** habilitado
- **Metadados locais preferidos:** desabilitado
- Coleções: `Hide collections but show their items`

Para Séries e Animes:

- Scanner e Agente: `Plex TV Series`
- **Ordem dos episódios:** `The Movie Database`
- **Usar títulos da temporada:** habilitado

### 10.4. Transcode no RK3588: o que esperar

> [!CAUTION]
> **O Plex não faz transcode por hardware nesta placa.** São dois bloqueios independentes:
>
> 1. A aceleração do Plex usa Intel Quick Sync, AMD ou NVIDIA. O RK3588 tem GPU Mali e VPU RKMPP,
>    que o Plex não implementa.
> 2. Mesmo em hardware compatível, é recurso exclusivo de assinantes do **Plex Pass**.
>
> Mapear `/dev/dri` e definir `PLEX_HW_TRANS_MAX` não muda nada: o Plex simplesmente ignora. Foi
> por isso que essas linhas saíram do YAML.

Na prática, isso significa que o Plex desta placa depende de **Direct Play**: o arquivo precisa ser
reproduzido sem conversão. Para conseguir isso:

- Prefira releases em **H.264** quando o cliente for antigo (TV de linha básica, PS4, navegador)
- Evite **HDR** se a TV for SDR, porque o tone-mapping força transcode
- Evite **legenda PGS/VobSub embutida**, porque queimar legenda na imagem força transcode. Legenda
  externa `.srt` (o que o Bazarr baixa) não força
- Nos apps cliente, deixe a qualidade em **Original / Maximum**

Se o vídeo travar e engasgar, é quase certo que o Plex entrou em transcode por software. Confirme na
aba **Atividade** do painel: aparece "Transcode" em vez de "Direct Play".

Para transcode acelerado de verdade nesta placa, use o Jellyfin.

---

## ⚡ Parte 11: Jellyfin com transcode por hardware (RKMPP)

Acesse `http://192.168.x.x:8096`.

Esta é a diferença técnica real entre os dois players nesta placa. A imagem
`nyanmisaka/jellyfin:latest-rockchip` traz um `jellyfin-ffmpeg` compilado com o pipeline completo
**RKMPP** (decode/encode pela VPU) e **RGA** (scaling por hardware) do RK3588.

> [!NOTE]
> A imagem **oficial** `jellyfin/jellyfin` não tem esse suporte. Precisa ser a `latest-rockchip` do
> nyanmisaka, e ela é **exclusiva para arm64**.

### 11.1. Bibliotecas

As mesmas pastas do Plex: `/data/Filmes`, `/data/Series`, `/data/Animes`.

#### Idioma dos metadados: por que os animes aparecem em japonês

Se a biblioteca mostra 進撃の巨人 em vez de "Attack on Titan", **não é bug**: o Jellyfin está pedindo
ao TMDB o título no idioma configurado **na biblioteca**, e o padrão é o idioma original da obra.

A configuração **não** fica no perfil do usuário nem no idioma da interface, e existe em **dois
níveis**. É por isso que ajustar só um deles não resolve.

**Nível 1, o padrão do servidor**

**Painel** → **Bibliotecas** → **Metadados**:

| Campo       | Valor                 |
| :---------- | :-------------------- |
| Idioma      | `Portuguese (Brazil)` |
| País/Região | `Brazil`              |

A própria tela avisa: _"Estas são suas configurações padrão e podem ser personalizadas por
biblioteca"_.

**Nível 2, o override de cada biblioteca**

> [!IMPORTANT]
> **É aqui que os animes ficam em japonês.** Cada biblioteca guarda o próprio idioma, e ele
> **sobrescreve** o padrão do servidor. Uma biblioteca de anime costuma vir com `Japanese`, porque
> foi o idioma detectado ou escolhido na criação.

**Painel** → **Bibliotecas** → clicar na biblioteca (ou no **⋮** → **Gerenciar biblioteca**) → rolar
até **Configurações da Biblioteca**:

| Campo                            | Trocar para           |
| :------------------------------- | :-------------------- |
| **Idioma preferido de download** | `Portuguese (Brazil)` |
| **País/Região**                  | `Brazil`              |

O nome do campo confunde: "Idioma preferido de **download**" não tem a ver com baixar arquivos, e sim
com o idioma dos **metadados** que o Jellyfin busca no TMDB.

Repita para **cada** biblioteca: Filmes, Séries e Animes.

**Aplicar no que já existe**

Mudar o idioma **não** reescreve o que já foi baixado. O aviso no topo da própria tela diz isso:

> _"Alterações nas configurações de metadados e artes baixados serão aplicadas apenas a novos
> conteúdos adicionados a sua biblioteca. Para aplicar as alterações nos títulos existentes, será
> necessário atualizar os metadados deles manualmente."_

Então, depois de salvar:

1. **Painel** → **Bibliotecas** → **⋮** na biblioteca → **Atualizar metadados**
2. Escolha **"Substituir todos os metadados"** (`Replace all metadata`)

Sem marcar essa opção, o Jellyfin preserva o que já tem e nada muda.

> [!WARNING]
> "Substituir todos os metadados" **apaga edições manuais** que você tenha feito, inclusive as
> correções por "Identificar". Por isso vale fazer a limpeza de identificação **depois** dessa
> atualização, e não antes.

> [!TIP]
> Nem todo anime tem título em português no TMDB. Quando não houver tradução, o Jellyfin cai para o
> idioma original de novo, e não há o que fazer pelo painel. Nesses casos, edite o item e ajuste o
> título manualmente, ou aceite o inglês como segundo idioma.

#### Quando o Jellyfin identifica a série errada

O sintoma é inconfundível: um anime aparece com pôster e sinopse de um documentário da BBC, e o
episódio "a seguir" mostra o nome certo em português. Isso significa que o **item da biblioteca**
está casado com o registro errado no banco de metadados, mesmo com os arquivos corretos.

A causa quase sempre é a mesma: **a pasta da série não tem o ID externo no nome**, então o scanner
tentou adivinhar pelo título e acertou outra coisa. Ver o aviso da Parte 7.1.

Correção pontual, item a item:

1. Abrir a série → menu **⋮** → **Identificar**
2. Preencher o **TVDB ID** ou o **TMDB ID** da série correta, ou buscar pelo nome
3. Confirmar. O Jellyfin refaz os metadados daquele item

Correção definitiva, para não voltar a acontecer:

1. No Sonarr, mudar o **Series Folder Format** para incluir `{tvdb-{TvdbId}}` (Parte 7.1)
2. **Séries** → **Selecionar a Série** → selecionar tudo → **Editar** → **Pasta raiz** = a mesma
   pasta atual (isso renomeia as pastas, ver Parte 7.1)
3. No Jellyfin, **Atualizar metadados** com **Substituir todos os metadados** marcado

> [!NOTE]
> Enquanto as pastas não tiverem ID, todo item novo continua sujeito ao mesmo erro. Corrigir pelo
> "Identificar" resolve um de cada vez, mas não previne o próximo.

### 11.2. Habilitar a aceleração

**Painel** → **Reprodução** → **Transcodificação**:

| Configuração                    | Valor                                                                  |
| :------------------------------ | :--------------------------------------------------------------------- |
| Aceleração de hardware          | **Rockchip MPP (RKMPP)**                                               |
| Decodificação por hardware      | H264, HEVC, VP9, AV1, HEVC 10bit, VP9 10bit                            |
| Decodificação, opcionais        | MPEG1, MPEG2, MPEG4, VP8 (a VPU também faz, útil para material antigo) |
| Ativar codificação por hardware | Marcado                                                                |
| Permitir codificação HEVC       | Marcado                                                                |
| **Permitir codificação AV1**    | **DESMARCADO** (ver aviso abaixo)                                      |
| Ativar mapeamento de tons       | Marcado, algoritmo `BT.2390`                                           |
| Local de transcodificação       | `/cache/transcodes`, que a stack monta como `tmpfs`                    |

> [!CAUTION]
> **Deixe "Permitir codificação em formato AV1" desmarcado.** O RK3588 **decodifica** AV1, mas não
> **codifica**. Confira você mesmo:
>
> ```bash
> docker exec jellyfin /usr/lib/jellyfin-ffmpeg/ffmpeg -hide_banner -encoders | grep rkmpp
> ```
>
> A saída lista apenas três encoders de hardware:
>
> ```
> V..... h264_rkmpp    Rockchip MPP H264 encoder
> V..... hevc_rkmpp    Rockchip MPP HEVC encoder
> V..... mjpeg_rkmpp   Rockchip MPP MJPEG encoder
> ```
>
> Não existe `av1_rkmpp`. Com a opção marcada, o Jellyfin cai no `libsvtav1` **por software**, e
> numa placa ARM o transcode nunca acompanha a reprodução. A própria tela avisa: "O Jellyfin usará
> codificação por software quando a aceleração de hardware para o formato selecionado não estiver
> disponível."

Para conferir a lista de decoders que a sua VPU realmente entrega:

```bash
docker exec jellyfin /usr/lib/jellyfin-ffmpeg/ffmpeg -hide_banner -decoders | grep rkmpp
```

No RK3588 saem dez: `av1`, `h263`, `h264`, `hevc`, `mjpeg`, `mpeg1`, `mpeg2`, `mpeg4`, `vp8` e `vp9`.

> [!TIP]
> **Transcode em RAM.** A stack monta `/cache/transcodes` como `tmpfs` de 2 GB. Os arquivos
> temporários de transcode são descartáveis e escrevê-los no NVMe só desgasta o SSD à toa. Se você
> transcodifica 4K com frequência, aumente o `size` no YAML, lembrando que sai da RAM da placa.

### 11.3. Validar que está funcionando

Reproduza um arquivo forçando qualidade menor que a original (para provocar transcode) e observe:

```bash
# O log deve mostrar rkmpp na linha de comando do ffmpeg
docker logs jellyfin 2>&1 | grep -i rkmpp | tail -5

# Uso de CPU durante o transcode: com HW fica baixo, com software vai a 100% nos 8 cores
docker stats jellyfin --no-stream
```

Se aparecer `-hwaccel rkmpp` e a CPU ficar abaixo de uns 30%, a aceleração está ativa.

#### Medir o ganho, sem depender de "parece mais rápido"

O melhor indicador é o `speed=` do próprio FFmpeg. Rode os dois e compare:

```bash
ARQ="/data/Animes/ALGUMA_SERIE/ALGUM_EPISODIO.mkv"

# Hardware: decode RKMPP -> RGA -> encode RKMPP
docker exec jellyfin /usr/lib/jellyfin-ffmpeg/ffmpeg -hide_banner -nostats -loglevel info \
  -init_hw_device rkmpp=rk -hwaccel rkmpp -hwaccel_output_format drm_prime \
  -i "$ARQ" -t 60 -an -vf "scale_rkrga=w=1280:h=720:format=nv12" \
  -c:v h264_rkmpp -b:v 3M -f null - 2>&1 | grep -E "^frame=" | tail -1

# Software, para comparar
docker exec jellyfin /usr/lib/jellyfin-ffmpeg/ffmpeg -hide_banner -nostats -loglevel info \
  -i "$ARQ" -t 60 -an -vf "scale=1280:720" \
  -c:v libx264 -preset veryfast -b:v 3M -f null - 2>&1 | grep -E "^frame=" | tail -1
```

Medição real nesta placa, transcodificando 60 s de HEVC 1080p 10-bit para H.264 720p:

| Modo | fps | `speed` |
| :--- | ---: | ---: |
| **Hardware** (RKMPP + RGA) | 664 | **27,7x** |
| Software (libx264 veryfast) | 24 | **1,02x** |

O número que realmente importa é o `1,02x` do software: o transcode mal empatava com a reprodução em
tempo real, então qualquer seek, segundo cliente ou tarefa concorrente já causava engasgo. Com a VPU
sobra folga de 27 vezes.

> [!TIP]
> O `rga_api version 1.10.4` que aparece no início da saída é informativo, não é erro: significa que
> a biblioteca de scaling por hardware inicializou.

Se o teste de hardware falhar com `Unsupported input pixel format 'nv15'`, não é defeito: o decode de
HEVC **10-bit** no Rockchip devolve `nv15`, e o encoder só aceita `nv12`. É exatamente para isso que
serve o filtro `scale_rkrga=...:format=nv12` no meio do comando. O Jellyfin monta essa conversão
sozinho, então isso só aparece em teste manual mal montado.

### 11.4. `Failed to init MPP context: -1`, o erro que exige `privileged`

Este é o erro que trava o transcode por hardware e engana quem procura a causa, porque **parece**
permissão de device e não é.

Sintoma no navegador: **"Erro na Reprodução: a reprodução falhou devido a um erro fatal do player"**.
No log do FFmpeg:

```
[hevc_rkmpp @ ...] Failed to init MPP context: -1
[dec:hevc_rkmpp @ ...] Error while opening decoder: Generic error in an external library
```

O que **não** resolve, tudo testado nesta placa:

| Tentativa                                                            | Resultado    |
| :------------------------------------------------------------------- | :----------- |
| Mapear os 5 devices e usar `group_add: [44, 105]`                    | falha        |
| Rodar o container como `root` (`docker exec -u 0`)                   | falha        |
| Montar `/dev` inteiro (`-v /dev:/dev`)                               | falha        |
| Fazer bind de `/sys/firmware/devicetree/base` em `/proc/device-tree` | falha        |
| **`privileged: true`**                                               | **funciona** |

A `librockchip_mpp` precisa de um acesso que o **cgroup de devices do Docker** bloqueia, e rodar como
root dentro do container não contorna cgroup. É por isso que o mantenedor da imagem responde
exatamente isto em [jellyfin/jellyfin#12174](https://github.com/jellyfin/jellyfin/issues/12174):

> This is usually a permissions issue. The easiest way to get around this is to use sudo and
> `--privileged` in docker.

> [!WARNING]
> `privileged: true` remove o isolamento de dispositivos e capabilities desse container. É uma
> concessão real de segurança, e por isso ela está **apenas** no Jellyfin, nunca nos demais serviços.
> O container continua rodando como `user: "1000:1000"`, então não vira root. Se você não usa
> transcode (todos os seus clientes fazem Direct Play), pode remover a linha.

Para validar sem mexer na stack que está no ar:

```bash
sudo docker run --rm --privileged --user 1000:1000 \
  -v /srv/midia:/data:ro \
  --entrypoint /usr/lib/jellyfin-ffmpeg/ffmpeg nyanmisaka/jellyfin:latest-rockchip \
  -hide_banner -loglevel error -init_hw_device rkmpp=rk -hwaccel rkmpp \
  -i "/data/Filmes/ALGUM_ARQUIVO.mkv" -t 2 -f null -
```

Saída vazia significa que o RKMPP inicializou.

### 11.5. Por que funciona no celular e falha no navegador

Se o app do iPhone reproduz normalmente e o navegador dá erro, **o transcode é a única diferença**:

- O **iOS** decodifica HEVC nativamente, então o Jellyfin entrega o arquivo sem tocar nele
  (**Direct Play**) e o RKMPP nem é chamado
- O **navegador** não reproduz HEVC, então o Jellyfin precisa transcodificar, o RKMPP falha e a
  reprodução morre

O sintoma "o vídeo volta ao começo do episódio em vez de continuar" é consequência disso: quando o
transcode falha, a sessão morre antes de reportar a posição, e o Jellyfin não tem o que salvar.
Depois de corrigir o transcode, o resume volta a funcionar também no navegador.

### 11.6. Outros erros de permissão

Se o erro for explicitamente "Permission denied" nos devices:

```bash
# Os devices precisam pertencer ao grupo video
ls -l /dev/mpp_service /dev/rga /dev/mali0

# Confirmar os GIDs e conferir contra o group_add do YAML
getent group video render
```

---

## 📊 Parte 12: Tautulli, Yamtrack e FileBot

### 12.1. Tautulli

Acesse `http://192.168.x.x:8181`. Na configuração inicial, aponte para o Plex:

| Campo        | Valor                  |
| :----------- | :--------------------- |
| Plex IP/Host | `host.docker.internal` |
| Port         | `32400`                |

### 12.2. Yamtrack (histórico de exibição)

O Yamtrack é um rastreador de mídia self-hosted. Ele guarda o que você assistiu, com nota, progresso
por episódio, datas e rewatches, e recebe os eventos automaticamente por **webhook** do Jellyfin, do
Plex e do Emby.

> [!NOTE]
> **Por que ele está aqui no lugar do PlexTraktSync.** Em julho de 2026 o Trakt passou a exigir
> assinatura **VIP** para criar aplicativos OAuth, e apagou os apps de contas gratuitas mesmo tendo
> dito que as conexões existentes seriam mantidas. O sintoma era o container em crash loop com
> `invalid_grant: session not found`, e o Trakt respondendo `invalid_client: client not found` na
> tentativa de reautenticar.
>
> Não havia correção possível do lado do projeto, como discutido em
> [Taxel/PlexTraktSync#2548](https://github.com/Taxel/PlexTraktSync/issues/2548). A diferença de
> fundo é que o Yamtrack **guarda o histórico na sua própria placa**, então nenhuma mudança de
> política de terceiros derruba o serviço de novo.

Ele usa Redis para tarefas em segundo plano, por isso a stack tem dois containers: `yamtrack` e
`yamtrack-redis`.

> [!TIP]
> **Quer continuar no Trakt mesmo sem VIP? Use o plugin do Jellyfin.** A restrição de julho de 2026
> atinge apenas quem precisa **criar** um aplicativo OAuth, que é o caso do PlexTraktSync.
>
> O [plugin Trakt para Jellyfin](https://github.com/jellyfin/jellyfin-plugin-trakt) embute o client
> ID do próprio plugin: você só autoriza por device code, sem criar app nenhum e sem assinatura.
> Instale em **Painel** → **Plugins** → **Catálogo** → **Trakt**.
>
> Os dois convivem bem: o plugin mantém seu perfil público do Trakt atualizado, e o Yamtrack guarda
> a cópia que não depende de ninguém.

#### Diagnóstico: erro 422 do plugin Trakt

Se o log do Jellyfin mostrar isto, **não é problema de autenticação**:

```
Trakt.Api.TraktApi: Exception handled in PostToTrakt
System.Net.Http.HttpRequestException: Response status code does not indicate success: 422
   at Trakt.Api.TraktApi.SendEpisodeStatusUpdateAsync(...)
```

`422 Unprocessable Entity` significa que o Trakt entendeu a requisição e recusou o **conteúdo**. As
duas causas comuns, e as duas são sintoma de outro problema:

1. **A reprodução parou em `0 ms`.** Procure `Playback stopped ... Stopped at 0 ms` logo acima no
   log. Um scrobble com posição zero é inválido para o Trakt. Isso acontece quando o transcode
   falha, ou seja, é o problema da Parte 11.4 aparecendo em outro lugar
2. **O item está identificado errado**, então os IDs enviados não casam com nada no Trakt.
   Ver Parte 11.1

Antes de mexer no plugin, confira o token em `/srv/jellyfin/config/plugins/configurations/Trakt.xml`:

```bash
sudo grep -E "AccessTokenExpiration|LinkedMbUserId" \
  /srv/jellyfin/config/plugins/configurations/Trakt.xml
```

Se a data de expiração estiver no futuro, a autenticação está boa e o 422 vem de uma das duas causas
acima.

#### 12.2.1. Primeiro acesso

Acesse `http://192.168.x.x:8010`.

1. Crie sua conta na tela de cadastro
2. Depois de criada, troque `YAMTRACK_REGISTRATION` para `False` nas Environment variables do
   Portainer e redeploy. Isso fecha o cadastro para estranhos, e você continua podendo criar contas
   pelo painel administrativo

#### 12.2.2. Rastreamento automático pelo Jellyfin

O Jellyfin envia um webhook ao Yamtrack sempre que você assiste algo.

1. No **Yamtrack**, abra as configurações do seu usuário e copie a **URL de webhook do Jellyfin**.
   Ela tem o formato `/webhook/jellyfin/<token>`, onde o token identifica a sua conta
2. No **Jellyfin**, vá em **Painel** → **Plugins** → **Catálogo** e instale o plugin **Webhook**
3. Reinicie o Jellyfin: `docker restart jellyfin`
4. Em **Painel** → **Plugins** → **Webhook**, adicione um **Generic Destination** com a URL
   `http://localhost:8010/webhook/jellyfin/SEU_TOKEN`

> O endereço é `localhost:8010` porque o Jellyfin roda em `network_mode: host` e o Yamtrack publica
> a porta `8010` nesse mesmo host. Não use `yamtrack:8000`: esse nome só resolve **dentro** da rede
> `midia-net`, e o Jellyfin não está nela.

##### O template é obrigatório

> [!CAUTION]
> **Sem template, o webhook não funciona.** O Generic Destination monta o corpo da requisição a
> partir de um **template Handlebars**. Deixando em branco, o Jellyfin faz o POST com corpo vazio e
> o Yamtrack responde:
>
> ```
> Notification failed with response status code BadRequest: Missing payload
> ```
>
> Do outro lado, o log do Yamtrack mostra `Missing payload in Jellyfin webhook request` e `400`.

O Yamtrack espera este formato, com o objeto `Item` aninhado:

```json
{
  "Event": "Stop",
  "Item": {
    "Type": "Episode",
    "Name": "...",
    "SeriesName": "...",
    "ParentIndexNumber": 1,
    "IndexNumber": 12,
    "ProductionYear": 2021,
    "ProviderIds": { "Tmdb": "...", "Imdb": "...", "Tvdb": "..." },
    "UserData": { "Played": true }
  }
}
```

Eventos aceitos: **`Play`**, **`Stop`**, **`MarkPlayed`** e **`MarkUnplayed`**.

##### Template para episódios

Em **Notification Type** marque `Playback Stop`, em **Item Type** marque apenas `Episodes`, e cole
no campo de template:

```handlebars
{
  "Event": "Stop",
  "Item": {
    "Type": "Episode",
    "Name": "{{Name}}",
    "SeriesName": "{{SeriesName}}",
    "ParentIndexNumber": {{SeasonNumber}},
    "IndexNumber": {{EpisodeNumber}},
    "ProductionYear": {{Year}},
    "ProviderIds": {
      "Tmdb": "{{Provider_tmdb}}",
      "Imdb": "{{Provider_imdb}}",
      "Tvdb": "{{Provider_tvdb}}"
    },
    "UserData": { "Played": {{PlayedToCompletion}} }
  }
}
```

##### Template para filmes

Crie um **segundo** destination, com **Item Type** apenas `Movies`. Filme não tem temporada nem
episódio, e deixar esses campos vazios geraria um JSON inválido:

```handlebars
{
  "Event": "Stop",
  "Item": {
    "Type": "Movie",
    "Name": "{{Name}}",
    "ProductionYear": {{Year}},
    "ProviderIds": {
      "Tmdb": "{{Provider_tmdb}}",
      "Imdb": "{{Provider_imdb}}",
      "Tvdb": "{{Provider_tvdb}}"
    },
    "UserData": { "Played": {{PlayedToCompletion}} }
  }
}
```

Nos dois, use o **User Filter** para registrar só o que **você** assiste, e não o que a família vê.

##### Validar sem depender de assistir nada

```bash
curl -s -o /dev/null -w "HTTP %{http_code}\n" \
  -X POST "http://localhost:8010/webhook/jellyfin/SEU_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"Event":"MarkPlayed","Item":{"Type":"Episode","Name":"Teste",
       "SeriesName":"Dr. Stone","ParentIndexNumber":1,"IndexNumber":1,
       "ProductionYear":2019,"ProviderIds":{"Tmdb":"86031"},
       "UserData":{"Played":true}}}'
```

`HTTP 200` significa formato aceito. Acompanhe o outro lado com:

```bash
docker logs -f yamtrack 2>&1 | grep -i webhook
```

Uma requisição bem processada aparece como `Received webhook for tv: Dr. Stone S01E01`.

##### Os três erros possíveis

| Resposta                                  | Significado                                                                                                                         |
| :---------------------------------------- | :---------------------------------------------------------------------------------------------------------------------------------- |
| `400 Missing payload`                     | Template vazio ou ausente                                                                                                           |
| `500` com `Tvdb error: NotFoundException` | O payload chegou certo, mas os **IDs não casam** com nada                                                                           |
| `504`                                     | O Yamtrack ainda está buscando metadados. Nesta placa, a primeira consulta de um item novo é lenta e pode estourar o tempo do proxy |

> [!IMPORTANT]
> O `500` com `NotFoundException` amarra com a Parte 11.1: se a série está **identificada errada** no
> Jellyfin, os `ProviderIds` enviados apontam para outra obra e o Yamtrack não acha o episódio.
> Corrigir a identificação, e colocar o ID no nome da pasta pelo Sonarr, é pré-requisito para o
> rastreamento funcionar de forma confiável.

#### 12.2.3. Rastreamento pelo Plex

O endpoint existe (`/webhook/plex/<token>`), mas há uma barreira do lado do Plex:

> [!WARNING]
> **Webhooks do Plex são recurso exclusivo de assinantes do Plex Pass.** Sem a assinatura, o menu de
> webhooks nem aparece nas configurações da conta. É a mesma barreira comercial que impede o
> transcode por hardware (ver Parte 10.4).

Se você tem Plex Pass, o caminho é **Configurações da conta** → **Webhooks** → **Add Webhook**, com a
URL `http://localhost:8010/webhook/plex/SEU_TOKEN`.

Se não tem, o rastreamento automático fica só pelo Jellyfin, o que é mais um motivo para concentrar
a reprodução nele nesta placa.

#### 12.2.4. Importar o histórico do Trakt

Você não perde o que já tinha, e **não precisa de API key nem de VIP** para isso.

1. Exporte seus dados em <https://app.trakt.tv/settings/data>
2. No Yamtrack, vá em **Importar** e escolha a origem **Trakt**

O Yamtrack aceita duas rotas: informar o **nome de usuário de um perfil público** do Trakt, que
dispensa qualquer credencial, ou autorizar por OAuth. Além do Trakt, ele importa de **Simkl**,
**MyAnimeList**, **AniList**, **Kitsu**, **IMDb**, **Steam** e **Goodreads**, e aceita CSV.

> [!TIP]
> Se o seu perfil do Trakt for privado, torne-o público por alguns minutos para usar a rota simples,
> e depois volte a fechá-lo.

#### 12.2.5. O que fica no backup

| Caminho               | Conteúdo                              |
| :-------------------- | :------------------------------------ |
| `/srv/yamtrack/db`    | Banco SQLite com todo o seu histórico |
| `/srv/yamtrack/redis` | Fila de tarefas, descartável          |

A stack usa **bind mount** em vez de volume nomeado justamente para que o banco entre nos snapshots
do Timeshift. Volumes nomeados vivem em `/var/lib/docker`, que o Timeshift exclui internamente.
Ver [`./orangepi5-backup-restore.md`](./orangepi5-backup-restore.md).

### 12.3. FileBot

Acesse `http://192.168.x.x:5800` e informe a senha definida em `FILEBOT_VNC_PASSWORD`.

O FileBot é a ferramenta manual para o que os `*arrs` não conseguiram identificar: coleções antigas,
arquivos com nome bagunçado, mídia importada de outro servidor. A biblioteca aparece em `/storage`
dentro dele.

> [!CAUTION]
> A interface do FileBot dá acesso de escrita a toda a biblioteca. Não exponha a porta `5800` à
> internet, e use uma senha forte. Não deixe o valor no YAML.

---

## 🔄 Parte 13: Atualização

Todos os serviços seguem tags móveis (`:latest`). Um redeploy comum reaproveita o cache e **não**
atualiza nada.

No Portainer: **Stacks** → `midia` → **Re-pull image and redeploy**.

Via SSH:

```bash
docker compose -f midia.yml pull && docker compose -f midia.yml up -d
```

> [!TIP]
> O Plex quebra compatibilidade com apps antigos de vez em quando, e o Sonarr teve migrações de
> banco pesadas entre versões maiores. Antes de atualizar, tire um snapshot manual do Timeshift:
>
> ```bash
> sudo timeshift --create --comments "antes de atualizar a stack midia"
> ```

---

## 💾 Parte 14: Backup

O que realmente importa nesta stack não são os arquivos de vídeo (esses você baixa de novo), e sim a
**configuração**: indexadores, perfis de qualidade, formatos personalizados, histórico, chaves de API
e o banco de metadados do Plex.

Tudo isso vive em `/srv/<serviço>`, no disco do sistema, e é coberto pelos snapshots do Timeshift.

| Caminho                   | Conteúdo                                  | No Timeshift?                   |
| :------------------------ | :---------------------------------------- | :------------------------------ |
| `/srv/radarr/appdata`     | Banco, perfis, formatos, histórico        | Sim                             |
| `/srv/sonarr/appdata`     | Idem, para séries                         | Sim                             |
| `/srv/prowlarr/config`    | Indexadores e apps                        | Sim                             |
| `/srv/qbittorrent/config` | Torrents ativos, categorias, preferências | Sim                             |
| `/srv/bazarr/appdata`     | Provedores e perfis de idioma             | Sim                             |
| `/srv/overseerr/config`   | Usuários e requisições do Seerr           | Sim                             |
| `/srv/plex/config`        | Biblioteca, metadados, histórico          | Sim                             |
| `/srv/jellyfin/config`    | Biblioteca e usuários                     | Sim                             |
| `/srv/yamtrack/db`        | Histórico de exibição (SQLite)            | Sim                             |
| `/srv/midia`              | Os arquivos de vídeo                      | **Não** (excluído de propósito) |

> 💾 O procedimento completo, incluindo o que fazer se a placa queimar, está em
> [`./orangepi5-backup-restore.md`](./orangepi5-backup-restore.md).

---

## ⚠️ Troubleshooting

| Sintoma                                           | Causa provável                                                 | Solução                                                                  |
| :------------------------------------------------ | :------------------------------------------------------------- | :----------------------------------------------------------------------- |
| Radarr/Sonarr: `401 Unauthorized` no qBittorrent  | Validação de cabeçalho Host ativa                              | qBittorrent → Opções → Interface Web → desmarcar host header validation  |
| Import cai para cópia e o disco enche             | Downloads e biblioteca em volumes Docker diferentes            | Usar mount único `/srv/midia:/data` em todos os containers               |
| `find /srv/midia -links +1` não retorna nada      | Hardlink desligado nos `*arrs`                                 | Marcar "Use Hard Links instead of Copy" no Radarr e no Sonarr            |
| Indexador dá `Cloudflare protection detected`     | Falta o FlareSolverr no indexador                              | Adicionar a tag `flaresolverr` ao indexador no Prowlarr                  |
| Nada baixa, mas a busca encontra resultados       | Formato personalizado com pontuação negativa demais            | Conferir Custom Formats: nota abaixo de 0 bloqueia o download            |
| Torrent fica em `Stalled` para sempre             | Porta de entrada fechada                                       | Redirecionar 62609 TCP/UDP no roteador e conferir a porta no qBittorrent |
| Vídeo engasga no Plex                             | Transcode por software                                         | Ver Parte 10.4. Use Direct Play ou migre para o Jellyfin                 |
| Jellyfin: "Permission denied" nos devices         | GID errado no `group_add`                                      | `getent group video render` e ajustar o YAML                             |
| Jellyfin não abre, mas o container está healthy   | Porta 8096 bloqueada pelo UFW (só afeta `network_mode: host`)  | `sudo ufw allow 8096/tcp`. Ver Parte 1.5                                 |
| Jellyfin transcodifica AV1 e trava                | "Permitir codificação AV1" marcado                             | Desmarcar. O RK3588 decodifica AV1 mas não codifica. Ver Parte 11.2      |
| Jellyfin: "Erro na Reprodução" só no navegador    | `Failed to init MPP context: -1` no transcode                  | Adicionar `privileged: true` ao serviço. Ver Parte 11.4                  |
| Vídeo volta ao começo em vez de continuar         | A sessão morre junto com o transcode e não salva a posição     | Mesma correção da Parte 11.4                                             |
| Toca no celular mas falha no navegador            | iOS faz Direct Play, navegador força transcode                 | Ver Parte 11.5                                                           |
| Jellyfin mostra títulos em japonês                | A biblioteca tem override de idioma sobre o padrão do servidor | Trocar "Idioma preferido de download" na biblioteca. Ver Parte 11.1      |
| Série identificada como outra obra                | Pasta sem ID externo, o scanner adivinha pelo título           | Ver Parte 11.1 e o aviso da Parte 7.1                                    |
| Mudei o formato da pasta e nada foi renomeado     | "Renomear Arquivos" só mexe em arquivos, não em pastas         | Editar → Pasta raiz → a mesma pasta atual. Ver Parte 7.1                 |
| Formato personalizado não bloqueia nada           | Pontuação `0` no perfil de qualidade                           | Criar o formato é só metade, pontue em Profiles. Ver Partes 6.5 e 6.6    |
| Legenda dessincroniza ao longo do episódio        | "Do Not Fix Framerate Mismatch" ligado no Bazarr               | Desligar. Ver Parte 8.3                                                  |
| Arquivo com legenda embutida sempre transcodifica | Legenda PGS/VobSub é imagem e precisa ser queimada no vídeo    | Ligar "Ignore Embedded PGS/VobSub" no Bazarr. Ver Parte 8.3              |
| Yamtrack não registra o que você assiste          | Webhook do Jellyfin não configurado ou token errado            | Ver Parte 12.2.2. Conferir com `docker logs yamtrack`                    |
| Yamtrack: `DisallowedHost` ou erro de CSRF        | Origem não confiável no Django                                 | Preencher `YAMTRACK_URLS` com o endereço usado no navegador              |
| Yamtrack não sobe: `SECRET` ausente               | Variável obrigatória não definida                              | Gerar com `openssl rand -base64 48` e pôr em `YAMTRACK_SECRET`           |
| Plex não mostra o menu de Webhooks                | Recurso exclusivo de Plex Pass                                 | Usar o rastreamento pelo Jellyfin. Ver Parte 12.2.3                      |
| Container sobe e morre com `EACCES`               | Pasta em `/srv` criada como `root`                             | `sudo chown -R 1000:1000 /srv/<serviço>`                                 |
| Filme importado some da pasta e o torrent para    | Clean Library Level em `Remove and Delete`                     | Radarr → Lists → Options → revisar a opção                               |
| Plex não aparece na conta                         | Falta o claim token                                            | Gerar em plex.tv/claim e redeployar em até 4 minutos                     |

---

## 📌 Notas Importantes

- **Seedar é o preço da entrada.** O qBittorrent continua semeando depois que o Radarr importa,
  porque o hardlink mantém o arquivo original vivo. Apagar do qBittorrent apaga uma das duas
  referências, e a mídia continua na biblioteca.
- **Espaço em disco.** A pasta `Downloads` cresce sem parar. Hoje ela ocupa mais que a biblioteca
  inteira nesta instalação. Defina uma regra de seed (razão ou tempo) no qBittorrent para os torrents
  se auto-removerem.
- **Uma raiz por tipo de conteúdo.** Cada pasta raiz extra é uma chance de mídia acabar em lugar
  errado e sumir do player.
- **FlareSolverr é pesado.** Ele sobe um Chrome headless a cada desafio. Numa placa ARM com 8 GB,
  use apenas nos indexadores que realmente precisam.
- **A porta 8191 não vai para a internet.** O FlareSolverr não tem autenticação nenhuma.
- **Plex e Jellyfin podem conviver.** Eles apenas leem as mesmas pastas. Não há conflito, só uso a
  mais de RAM e de CPU nas varreduras. Se for migrar de vez, mantenha os dois por um tempo até
  confirmar que os apps das TVs atendem bem o Jellyfin.

---

## 🌐 Acessos

| Serviço     | URL local                      | Portainer     |
| :---------- | :----------------------------- | :------------ |
| qBittorrent | `http://192.168.x.x:8080`      | Stack `midia` |
| Prowlarr    | `http://192.168.x.x:9696`      | Stack `midia` |
| Radarr      | `http://192.168.x.x:7878`      | Stack `midia` |
| Sonarr      | `http://192.168.x.x:8989`      | Stack `midia` |
| Bazarr      | `http://192.168.x.x:6767`      | Stack `midia` |
| Seerr       | `http://192.168.x.x:5055`      | Stack `midia` |
| Plex        | `http://192.168.x.x:32400/web` | Stack `midia` |
| Jellyfin    | `http://192.168.x.x:8096`      | Stack `midia` |
| Tautulli    | `http://192.168.x.x:8181`      | Stack `midia` |
| Yamtrack    | `http://192.168.x.x:8010`      | Stack `midia` |
| FileBot     | `http://192.168.x.x:5800`      | Stack `midia` |

---

## 📚 Referências

- [Meu "Netflix Pessoal" com Docker Compose, AkitaOnRails](https://akitaonrails.com/2024/04/03/meu-netflix-pessoal-com-docker-compose/)
- [Guia do Streaming Doméstico Automatizado, r/pirataria](https://www.reddit.com/r/pirataria/comments/18ch7bt/guia_do_streaming_dom%C3%A9stico_automatizado_sonarr/)
- [TRaSH Guides: Hardlinks and Instant Moves](https://trash-guides.info/File-and-Folder-Structure/Hardlinks-and-Instant-Moves/)
- [TRaSH Guides: Radarr custom formats](https://trash-guides.info/Radarr/Radarr-collection-of-custom-formats/)
- [TRaSH Guides: qBittorrent Basic Setup](https://trash-guides.info/Downloaders/qBittorrent/Basic-Setup/)
- [Recyclarr, sincroniza o TRaSH Guides automaticamente](https://recyclarr.dev/)
- [nyanmisaka/jellyfin, imagem com RKMPP para Rockchip](https://hub.docker.com/r/nyanmisaka/jellyfin)
- [Jellyfin: Hardware Acceleration](https://jellyfin.org/docs/general/post-install/transcoding/hardware-acceleration/)
- [Plex: Using Hardware-Accelerated Streaming](https://support.plex.tv/articles/115002178853-using-hardware-accelerated-streaming/)
- [Seerr (fork do Overseerr)](https://github.com/seerr-team/seerr)
- [Yamtrack, rastreador de mídia self-hosted](https://github.com/FuzzyGrim/Yamtrack)
- [Yamtrack: variáveis de ambiente](https://fuzzygrim.github.io/Yamtrack/release/env-variables/)
- [Jellyfin: plugin Webhook](https://github.com/jellyfin/jellyfin-plugin-webhook)
- [PlexTraktSync #2548: o Trakt exigindo VIP para apps OAuth](https://github.com/Taxel/PlexTraktSync/issues/2548)
