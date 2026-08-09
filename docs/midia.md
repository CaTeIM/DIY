# 🎬 Stack de Mídia (Plex + Jellyfin + *arrs + qBittorrent)

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

| Serviço           | Papel                                                                                  |
| :---------------- | :------------------------------------------------------------------------------------- |
| **qBittorrent**   | Cliente de torrent. Recebe os magnet links e baixa                                     |
| **Prowlarr**      | Agregador de indexadores. Alimenta Radarr e Sonarr com as fontes de torrent            |
| **FlareSolverr**  | Proxy que resolve desafios Cloudflare de indexadores protegidos                        |
| **Radarr**        | Gerencia filmes: procura, baixa, renomeia, organiza e faz upgrade de qualidade         |
| **Sonarr**        | O mesmo para séries e animes, com agenda de episódios que ainda vão ao ar              |
| **Bazarr**        | Busca e sincroniza legendas para o que Radarr e Sonarr importaram                      |
| **Seerr**         | Portal de requisições. Fork do Overseerr. É por aqui que a família pede conteúdo        |
| **Plex**          | Player principal. Interface polida, apps em toda TV, console e celular                 |
| **Jellyfin**      | Player alternativo, 100% aberto e o **único com transcode por hardware nesta placa**   |
| **Tautulli**      | Estatísticas e monitoramento de quem assistiu o quê no Plex                             |
| **PlexTraktSync** | Sincroniza histórico e listas do Plex com o Trakt.tv                                   |
| **FileBot**       | Renomeador manual (interface gráfica via navegador) para o que os `*arrs` não pegaram  |

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
                                                │
                                   ┌────────────┴────────────┐
                                   ▼                         ▼
                            ┌────────────┐          ┌───────────────┐
                            │  Tautulli  │          │ PlexTraktSync │
                            └────────────┘          └───────────────┘
```

### Portas no host

| Porta          | Serviço      | Observação                                       |
| :------------- | :----------- | :----------------------------------------------- |
| `8080/tcp`     | qBittorrent  | Web UI                                           |
| `62609/tcp+udp`| qBittorrent  | Porta de escuta do BitTorrent. Precisa ser aberta no roteador |
| `9696/tcp`     | Prowlarr     | Web UI                                           |
| `8191/tcp`     | FlareSolverr | API interna. **Não** expor à internet            |
| `7878/tcp`     | Radarr       | Web UI                                           |
| `8989/tcp`     | Sonarr       | Web UI                                           |
| `6767/tcp`     | Bazarr       | Web UI                                           |
| `5055/tcp`     | Seerr        | Web UI                                           |
| `32400/tcp`    | Plex         | `network_mode: host`                             |
| `8096/tcp`     | Jellyfin     | `network_mode: host`                             |
| `8181/tcp`     | Tautulli     | Web UI                                           |
| `5800/tcp`     | FileBot      | Interface gráfica via navegador (noVNC)          |

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
sudo mkdir -p /srv/plextrakt/{config,xdg}
sudo mkdir -p /srv/filebot/config
```

### 1.3. Ajustar as permissões

Os containers rodam como UID/GID `1000`. Se as pastas ficarem como `root`, os serviços sobem e
falham com `EACCES` na primeira escrita.

```bash
sudo chown -R 1000:1000 /srv/midia
sudo chown -R 1000:1000 /srv/{qbittorrent,prowlarr,radarr,sonarr,bazarr,overseerr}
sudo chown -R 1000:1000 /srv/{plex,jellyfin,tautulli,plextrakt,filebot}
```

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

### 1.5. Conferir os devices de vídeo do Rockchip

```bash
ls -l /dev/mpp_service /dev/rga /dev/mali0 && ls /dev/dri /dev/dma_heap
```

Todos devem existir. Se `/dev/mpp_service` faltar, o kernel não está com os drivers de VPU do
Rockchip e o transcode por hardware do Jellyfin não vai funcionar.

---

## 🔑 Parte 2: Configurar os Segredos

Na criação da stack, aba **Environment variables** do Portainer:

| Variável                | Obrigatória | Descrição                                                                 |
| :---------------------- | :---------- | :------------------------------------------------------------------------ |
| `FILEBOT_VNC_PASSWORD`  | Sim         | Senha de acesso à interface gráfica do FileBot                            |
| `PLEX_CLAIM`            | Não         | Token de [plex.tv/claim](https://plex.tv/claim), válido por 4 minutos. Só no primeiro boot |
| `PLEX_ADVERTISE_IP`     | Não         | Ex.: `http://192.168.x.x:32400/`. Ajuda o Plex a se anunciar na LAN       |

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

Plex, Jellyfin e PlexTraktSync são a exceção e ficam em `network_mode: host`, porque dependem de
multicast para o discovery na rede local e de acesso direto aos devices de vídeo.

Para os containers da rede bridge falarem com o Plex (que está na rede do host), a stack define
`extra_hosts: host.docker.internal:host-gateway` no Tautulli e no Seerr.

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

| Configuração                                  | Valor                           |
| :-------------------------------------------- | :------------------------------ |
| Modo de gerenciamento padrão dos torrents     | **Automático**                  |
| Quando a categoria do torrent for mudada      | Re-alocar torrent               |
| Quando o caminho padrão de salvamento mudar   | Re-alocar torrents afetados     |
| Caminho padrão de salvamento                  | `/data/Downloads/torrents`      |
| Pré-alocar espaço em disco para todos os arquivos | Marcado                     |

> [!IMPORTANT]
> O modo **Automático** é o que faz o qBittorrent respeitar as pastas por categoria que o Radarr e
> o Sonarr enviam. No modo Manual, tudo cai na mesma pasta e a organização não acontece.

### 4.4. Categorias

O Radarr e o Sonarr criam as categorias sozinhos no primeiro download. Se quiser adiantar, clique
com o botão direito em **Categorias** → **Adicionar categoria**:

| Categoria   | Caminho de salvamento               |
| :---------- | :---------------------------------- |
| `radarr`    | `/data/Downloads/torrents/radarr`   |
| `tv-sonarr` | `/data/Downloads/torrents/tv-sonarr`|

### 4.5. Porta de conexão

Em **Opções** → **Conexão**, defina a porta de entrada como **62609** (a mesma publicada no YAML) e
abra essa porta TCP e UDP no roteador. Sem redirecionamento, você só consegue conexões de saída e a
velocidade despenca.

---

## 🔍 Parte 5: Prowlarr e FlareSolverr

Acesse `http://192.168.x.x:9696`.

### 5.1. Registrar o FlareSolverr

**Settings** → **Indexers** → **+** (em Indexer Proxies) → **FlareSolverr**:

| Campo | Valor                     |
| :---- | :------------------------ |
| Name  | `FlareSolverr`            |
| Tags  | `flaresolverr`            |
| Host  | `http://flaresolverr:8191`|

Depois, em cada indexador que exija Cloudflare, adicione a tag `flaresolverr`.

### 5.2. Conectar Radarr e Sonarr

**Settings** → **Apps** → **+** → **Radarr**:

| Campo             | Valor                     |
| :---------------- | :------------------------ |
| Sync Level        | `Full Sync`               |
| Prowlarr Server   | `http://prowlarr:9696`    |
| Radarr Server     | `http://radarr:7878`      |
| API Key           | Radarr → Settings → General → API Key |

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

| Configuração                        | Valor       |
| :---------------------------------- | :---------- |
| **Use Hard Links instead of Copy**  | **Marcado** |
| Skip Free Space Check               | Marcado     |
| Import Extra Files                  | Desmarcado  |

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
> ```bash
> ls -la /srv/midia/radarr/
> ```
> Se houver, mova para `/srv/midia/Filmes/` e rode **Movies** → **Mass Editor** para reapontar a
> pasta raiz dos filmes afetados. Só então remova a raiz antiga.

### 6.5. Formatos personalizados

**Settings** → **Custom Formats** → **+** → **Import**.

Os três essenciais, com os `trash_id` do [TRaSH Guides](https://trash-guides.info/):

| Formato        | `trash_id`                         | Pontuação | Para quê                                                    |
| :------------- | :--------------------------------- | :-------- | :---------------------------------------------------------- |
| **BR-DISK**    | `ed38b889b31be83fda192888e2286d83` | `-10000`  | Bloqueia releases ISO/BD completos, de 50 GB, que o Plex nem abre |
| **3D**         | `b8cd450cbfa689c0259a01d9e29ba3d6` | `-10000`  | Bloqueia releases 3D (SBS, Half-OU)                          |
| **Open Matte** | `09d9dd29a0fc958f9796e65c2a8864b4` | `25`      | Prefere versões com o quadro completo, sem corte             |

> [!TIP]
> Pegue o JSON sempre atualizado em
> [trash-guides.info/Radarr/Radarr-collection-of-custom-formats](https://trash-guides.info/Radarr/Radarr-collection-of-custom-formats/).
> Os regex mudam com o tempo, e um regex velho de BR-DISK deixa passar exatamente o que ele deveria
> bloquear. Quem quiser automatizar, o [Recyclarr](https://recyclarr.dev/) sincroniza os formatos do
> TRaSH direto para o Radarr e o Sonarr.

Qualquer formato com pontuação negativa nunca é baixado. É assim que você impede o servidor de
encher com um único BD-REMUX de 80 GB.

### 6.6. Perfil de qualidade

**Settings** → **Profiles** → editar `Any`:

- Marcar as qualidades que interessam, até o teto desejado (por exemplo, `Bluray-1080p`)
- **Upgrades Allowed:** marcado
- **Upgrade Until:** `Bluray-1080p`
- **Language:** `Original`
- **Minimum Custom Format Score:** `0`
- **Upgrade Until Custom Format Score:** `0`

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

| Campo                 | Valor            |
| :-------------------- | :--------------- |
| Enable Automatic Add  | Marcado          |
| Monitor               | `Movie Only`     |
| Search on Add         | Marcado          |
| Minimum Availability  | `Announced`      |
| Root Folder           | `/data/Filmes`   |
| List URL              | a URL gerada     |

Em **Options** → **Clean Library Level**: `Remove Movie and Delete Files` faz o filme sumir do
servidor quando você tira da lista. Útil com pouco espaço, perigoso se você esquecer que está ligado.

---

## 📺 Parte 7: Sonarr (séries e animes)

Acesse `http://192.168.x.x:8989`.

### 7.1. Nomenclatura

**Settings** → **Media Management**, marcar **Rename Episodes** e **Replace Illegal Characters**.

**Standard Episode Format:**

```
{Series TitleYear} - S{season:00}E{episode:00} - {Episode CleanTitle} [{Preferred Words }{Quality Full}]{[MediaInfo VideoDynamicRangeType]}{[Mediainfo AudioCodec}{ Mediainfo AudioChannels]}{[MediaInfo VideoCodec]}{-Release Group}
```

**Daily Episode Format:**

```
{Series TitleYear} - {Air-Date} - {Episode CleanTitle} [{Preferred Words }{Quality Full}]{[MediaInfo VideoDynamicRangeType]}{[Mediainfo AudioCodec}{ Mediainfo AudioChannels]}{[MediaInfo VideoCodec]}{-Release Group}
```

**Anime Episode Format:**

```
{Series TitleYear} - S{season:00}E{episode:00} - {absolute:000} - {Episode CleanTitle} [{Preferred Words }{Quality Full}]{[MediaInfo VideoDynamicRangeType]}[{MediaInfo VideoBitDepth}bit]{[MediaInfo VideoCodec]}[{Mediainfo AudioCodec} { Mediainfo AudioChannels}]{MediaInfo AudioLanguages}{-Release Group}
```

**Series Folder Format:**

```
{Series TitleYear} {imdb-{ImdbId}}
```

O formato de anime inclui `{absolute:000}` (numeração absoluta do episódio) e
`{MediaInfo AudioLanguages}`, que separa versão legendada de dublada no nome do arquivo.

### 7.2. Importação e pastas raiz

- **Use Hard Links instead of Copy:** marcado
- **Root Folders:** `/data/Series` e `/data/Animes`

Ao adicionar uma série, escolha **Series Type: Anime** para animes, o que faz o Sonarr usar o formato
de nomenclatura de anime e a numeração absoluta.

> [!WARNING]
> **Limpeza necessária nesta instalação.** O Sonarr tem hoje **quatro** pastas raiz cadastradas:
> `/data/Series`, `/data/Animes`, `/data/sonarr/tv` e `/data/sonarr/anime`. Aplique o mesmo
> procedimento da seção 6.4: verifique `/srv/midia/sonarr/`, mova o que houver e use o
> **Mass Editor** antes de remover as raízes antigas.

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

| Configuração                        | Valor                                              |
| :---------------------------------- | :------------------------------------------------- |
| Subtitle Folder                     | `Alongside Media File`                             |
| Upgrade Previously Downloaded Subtitles | Marcado                                        |
| **Automatic Subtitle Synchronization** | **Marcado**                                     |

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

| Biblioteca | Tipo         | Pasta          |
| :--------- | :----------- | :------------- |
| Filmes     | Movies       | `/data/Filmes` |
| Séries     | TV Shows     | `/data/Series` |
| Animes     | TV Shows     | `/data/Animes` |

### 10.3. Configurações recomendadas

**Configurações** → **Biblioteca**:

| Configuração                                        | Estado       |
| :-------------------------------------------------- | :----------- |
| Digitalizar minha biblioteca automaticamente        | Habilitado   |
| Executar varredura parcial quando detectar alterações| Habilitado  |
| Escanear minha biblioteca periodicamente            | Desabilitado |
| Esvaziar lixeira automaticamente após cada varredura| Habilitado   |
| Permitir exclusão de mídia                          | Desabilitado |
| Executar tarefas de varredura em prioridade menor   | Habilitado   |

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

### 11.2. Habilitar a aceleração

**Painel** → **Reprodução** → **Transcodificação**:

| Configuração                                     | Valor                                     |
| :----------------------------------------------- | :---------------------------------------- |
| Aceleração de hardware                            | **Rockchip RKMPP**                        |
| Habilitar decodificação por hardware              | H264, HEVC, VP9, AV1 (marque o que a placa suportar) |
| Habilitar codificação por hardware                | Marcado                                   |
| Permitir codificação HEVC                         | Marcado                                   |
| Habilitar tone mapping por hardware               | Marcado                                   |
| Caminho de transcodificação                       | deixe o padrão                            |

### 11.3. Validar que está funcionando

Reproduza um arquivo forçando qualidade menor que a original (para provocar transcode) e observe:

```bash
# O log deve mostrar rkmpp na linha de comando do ffmpeg
docker logs jellyfin 2>&1 | grep -i rkmpp | tail -5

# Uso de CPU durante o transcode: com HW fica baixo, com software vai a 100% nos 8 cores
docker stats jellyfin --no-stream
```

Se aparecer `-hwaccel rkmpp` e a CPU ficar abaixo de uns 30%, a aceleração está ativa.

### 11.4. Erros comuns de permissão

Se o transcode falhar com "Permission denied" nos devices:

```bash
# Os devices precisam pertencer ao grupo video
ls -l /dev/mpp_service /dev/rga /dev/mali0

# Confirmar os GIDs e conferir contra o group_add do YAML
getent group video render
```

---

## 📊 Parte 12: Tautulli, PlexTraktSync e FileBot

### 12.1. Tautulli

Acesse `http://192.168.x.x:8181`. Na configuração inicial, aponte para o Plex:

| Campo         | Valor                     |
| :------------ | :------------------------ |
| Plex IP/Host  | `host.docker.internal`    |
| Port          | `32400`                   |

### 12.2. PlexTraktSync

Sincroniza o que você assistiu no Plex com o Trakt.tv. Exige autenticação OAuth nos dois serviços,
feita **uma vez** por linha de comando:

```bash
docker exec -it plextraktsync plextraktsync login
```

Siga as instruções (ele abre um código para você colar no site do Trakt).

> [!WARNING]
> **O token do Trakt expira.** Nesta instalação o container está hoje em crash loop:
>
> ```
> INFO     OAuth token has expired, refreshing now...
> ERROR    invalid_grant: session not found
> CRITICAL Error running sync command: Trakt error: Unable to refresh token
> ```
>
> A correção é refazer o login:
> ```bash
> docker exec -it plextraktsync plextraktsync login
> docker restart plextraktsync
> ```
> Se persistir, apague o token e refaça: `rm /srv/plextrakt/config/.pytrakt.json`

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
> ```bash
> sudo timeshift --create --comments "antes de atualizar a stack midia"
> ```

---

## 💾 Parte 14: Backup

O que realmente importa nesta stack não são os arquivos de vídeo (esses você baixa de novo), e sim a
**configuração**: indexadores, perfis de qualidade, formatos personalizados, histórico, chaves de API
e o banco de metadados do Plex.

Tudo isso vive em `/srv/<serviço>`, no disco do sistema, e é coberto pelos snapshots do Timeshift.

| Caminho                    | Conteúdo                                  | No Timeshift? |
| :------------------------- | :---------------------------------------- | :------------ |
| `/srv/radarr/appdata`      | Banco, perfis, formatos, histórico        | Sim           |
| `/srv/sonarr/appdata`      | Idem, para séries                         | Sim           |
| `/srv/prowlarr/config`     | Indexadores e apps                        | Sim           |
| `/srv/qbittorrent/config`  | Torrents ativos, categorias, preferências | Sim           |
| `/srv/bazarr/appdata`      | Provedores e perfis de idioma             | Sim           |
| `/srv/overseerr/config`    | Usuários e requisições do Seerr           | Sim           |
| `/srv/plex/config`         | Biblioteca, metadados, histórico          | Sim           |
| `/srv/jellyfin/config`     | Biblioteca e usuários                     | Sim           |
| `/srv/midia`               | Os arquivos de vídeo                      | **Não** (excluído de propósito) |

> 💾 O procedimento completo, incluindo o que fazer se a placa queimar, está em
> [`./orangepi5-backup-restore.md`](./orangepi5-backup-restore.md).

---

## ⚠️ Troubleshooting

| Sintoma                                              | Causa provável                                      | Solução                                                                 |
| :--------------------------------------------------- | :-------------------------------------------------- | :---------------------------------------------------------------------- |
| Radarr/Sonarr: `401 Unauthorized` no qBittorrent     | Validação de cabeçalho Host ativa                   | qBittorrent → Opções → Interface Web → desmarcar host header validation  |
| Import cai para cópia e o disco enche                | Downloads e biblioteca em volumes Docker diferentes | Usar mount único `/srv/midia:/data` em todos os containers               |
| `find /srv/midia -links +1` não retorna nada         | Hardlink desligado nos `*arrs`                      | Marcar "Use Hard Links instead of Copy" no Radarr e no Sonarr            |
| Indexador dá `Cloudflare protection detected`        | Falta o FlareSolverr no indexador                   | Adicionar a tag `flaresolverr` ao indexador no Prowlarr                  |
| Nada baixa, mas a busca encontra resultados          | Formato personalizado com pontuação negativa demais | Conferir Custom Formats: nota abaixo de 0 bloqueia o download            |
| Torrent fica em `Stalled` para sempre                | Porta de entrada fechada                            | Redirecionar 62609 TCP/UDP no roteador e conferir a porta no qBittorrent |
| Vídeo engasga no Plex                                | Transcode por software                               | Ver Parte 10.4. Use Direct Play ou migre para o Jellyfin                 |
| Jellyfin: "Permission denied" nos devices            | GID errado no `group_add`                           | `getent group video render` e ajustar o YAML                            |
| `plextraktsync` reiniciando em loop                  | Token OAuth do Trakt expirado                       | `docker exec -it plextraktsync plextraktsync login`                     |
| Container sobe e morre com `EACCES`                  | Pasta em `/srv` criada como `root`                  | `sudo chown -R 1000:1000 /srv/<serviço>`                                |
| Filme importado some da pasta e o torrent para       | Clean Library Level em `Remove and Delete`          | Radarr → Lists → Options → revisar a opção                              |
| Plex não aparece na conta                            | Falta o claim token                                 | Gerar em plex.tv/claim e redeployar em até 4 minutos                     |

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

| Serviço      | URL local                    | Portainer     |
| :----------- | :--------------------------- | :------------ |
| qBittorrent  | `http://192.168.x.x:8080`    | Stack `midia` |
| Prowlarr     | `http://192.168.x.x:9696`    | Stack `midia` |
| Radarr       | `http://192.168.x.x:7878`    | Stack `midia` |
| Sonarr       | `http://192.168.x.x:8989`    | Stack `midia` |
| Bazarr       | `http://192.168.x.x:6767`    | Stack `midia` |
| Seerr        | `http://192.168.x.x:5055`    | Stack `midia` |
| Plex         | `http://192.168.x.x:32400/web` | Stack `midia` |
| Jellyfin     | `http://192.168.x.x:8096`    | Stack `midia` |
| Tautulli     | `http://192.168.x.x:8181`    | Stack `midia` |
| FileBot      | `http://192.168.x.x:5800`    | Stack `midia` |

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
