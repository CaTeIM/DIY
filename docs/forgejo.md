# Guia de Instalação: Forgejo (Git Self-Hosted via Docker + PostgreSQL + CI/CD)

Este guia sobe o **Forgejo** — um servidor Git self-hosted leve (fork comunitário do Gitea), alternativa ao GitHub/GitLab para hospedar seus próprios repositórios, issues e **CI/CD** na sua infra. A stack usa **Docker Compose** com **PostgreSQL** e já inclui o **Forgejo Actions** (runner + Docker-in-Docker) subindo junto. Tudo centralizado em `/srv`, no mesmo padrão dos outros guias do repo.

**Pré-requisito:** Docker Engine + Docker Compose instalados. Se ainda não tem, veja o guia [Docker + Portainer no Debian](./portainer-debian.md).

A stack pronta está em [`assets/stacks/forgejo.yml`](../assets/stacks/forgejo.yml).

---

## Parte 1: Preparar as Pastas de Dados

Seguindo o padrão `/srv`, crie as pastas onde o Forgejo, o banco e o runner vão persistir os dados.

```bash
sudo mkdir -p /srv/forgejo/data /srv/forgejo/db /srv/forgejo/runner /srv/forgejo/dind

# o runner roda como uid/gid 1000 (igual ao server); garanta a posse da pasta dele:
sudo chown -R 1000:1000 /srv/forgejo/runner
```

> `data` guarda repositórios, anexos, config (`app.ini`) e avatares; `db` guarda o PostgreSQL; `runner` guarda a config e o estado do Forgejo Actions; `dind` guarda o cache de imagens Docker dos jobs do CI. Faça backup de `/srv/forgejo` inteiro (com os containers parados) e você tem tudo.

## Parte 2: Configurar o Segredo do Banco

A stack lê a senha do banco de uma variável de ambiente (nunca hardcode senha no compose). Crie/edite o arquivo `.env` ao lado do compose:

```bash
# .env
FORGEJO_DB_PASSWORD=uma-senha-forte-aqui
```

> O mesmo valor é usado pelo serviço `server` (para conectar) e pelo `db` (para criar o usuário). Mantenha o `.env` fora do versionamento.

## Parte 3: A Stack (Docker Compose)

O arquivo [`forgejo.yml`](../assets/stacks/forgejo.yml) define **quatro serviços** (Git + CI/CD juntos):

- **`server`** → Forgejo `15.0.2`, com `FORGEJO__actions__ENABLED=true`. Roda como UID/GID `1000`, conecta no Postgres via `db:5432` e expõe:
  - `3000:3000` → interface **web** (HTTP)
  - `8122:22` → **SSH do Git** (porta alta no host pra não colidir com o SSH do servidor; clones ficam `ssh://git@host:8122/...`)
- **`db`** → PostgreSQL `15-alpine`, dados em `/srv/forgejo/db`. Tem `healthcheck` (`pg_isready`) — o `server` só inicia depois que o banco está pronto, evitando erro de conexão no primeiro boot.
- **`docker-in-docker`** → daemon Docker isolado (`docker:dind`) onde os jobs do CI rodam — **sem tocar o Docker do host**. O cache de imagens fica em `/srv/forgejo/dind`, então sobrevive a redeploys (não rebaixa node/ubuntu a cada vez).
- **`runner`** → `data.forgejo.org/forgejo/runner:12`, executa os workflows. **Precisa ser registrado uma vez** (Parte 5) antes de funcionar; até o `runner-config.yml` existir ele fica reiniciando à espera dele.

Suba a stack (via `docker compose` ou colando o YAML como **Stack** no Portainer):

```bash
docker compose -f forgejo.yml up -d
```

> Numa primeira subida só pra configurar o Git, os serviços `server` e `db` já bastam. O `runner` só roda de verdade depois da Parte 5 — o que é esperado.

> **Usando Portainer (Stack)?** Três coisas mudam em relação ao shell:
>
> 1. **Crie as pastas da Parte 1 via SSH _antes_ de criar a Stack.** Se o Portainer subir primeiro, o Docker cria `/srv/forgejo/*` como `root` e o runner (uid 1000) não consegue gravar o config.
> 2. **Não crie o arquivo `.env`** — adicione `FORGEJO_DB_PASSWORD` na seção **Environment variables** do editor da Stack.
> 3. O Portainer sobe os **4 serviços de uma vez**; o `runner` fica reiniciando até você gravar o `runner-config.yml` (Parte 5, ainda via SSH). Assim que o arquivo existir, ele pega sozinho — **nem precisa atualizar a Stack**.

## Parte 4: Configuração Inicial

1. Acesse `http://IP_DO_SERVIDOR:3000` no navegador.
2. Na tela de **instalação inicial**, os campos de banco já vêm pré-preenchidos pelas variáveis `FORGEJO__database__*` do compose (tipo `PostgreSQL`, host `db:5432`, base/usuário `forgejo`). Confira e siga.
3. Em **Configurações Gerais**, ajuste o **Server Domain** e a **Base URL** para o endereço real (ex.: `https://git.exemplo.com`) — isso é usado em links de clone, webhooks **e pelo CI** (Parte 5.5).
4. Crie a **conta de administrador** ainda nessa tela (se não criar, o primeiro usuário registrado vira admin).
5. **Recomendado (instância privada):** desative o registro aberto. **Não existe toggle no _Site Administration_** (a página _Configuration_ do admin é só leitura) — o controle é a config `[service] DISABLE_REGISTRATION`, que aqui se faz por **variável de ambiente**. Adicione no `environment:` do serviço `server` (no compose / editor da Stack) e atualize a stack:

   ```yaml
   - FORGEJO__service__DISABLE_REGISTRATION=true
   # opcional — exige login até para VER qualquer página/repo:
   # - FORGEJO__service__REQUIRE_SIGNIN_VIEW=true
   ```

   O botão "Registrar" some e só admin cria usuários novos (sua conta admin não é afetada). Editar `/srv/forgejo/data/gitea/conf/app.ini` na mão também funciona, mas exige SSH e é menos consistente com o resto da stack.

Pronto! Seu servidor Git self-hosted está no ar. 🚀

---

## Parte 5: CI/CD com Forgejo Actions

O **Forgejo Actions** é embutido e **compatível com a sintaxe do GitHub Actions**. A engine só **agenda** os jobs — quem **executa** é o **Forgejo Runner**, que já está no `forgejo.yml` (serviços `runner` + `docker-in-docker`). Falta só registrá-lo.

### 5.1 — Actions já vem ligado

Desde o **Forgejo v1.21 o Actions é habilitado por padrão** (a stack ainda fixa `FORGEJO__actions__ENABLED=true` por clareza). Habilite a unidade **por repositório** em _Settings → Actions_. O `DEFAULT_ACTIONS_URL` padrão é `https://data.forgejo.org`, então `uses: actions/checkout@v4` é resolvido desse mirror oficial.

### 5.2 — Criar o runner e obter UUID + Token

Crie o runner na UI, escolhendo o **escopo** (define quais repositórios ele atende):

| Escopo      | Onde criar                                       | Atende                |
| :---------- | :----------------------------------------------- | :-------------------- |
| Instância   | _Site Administration_ → `/admin/actions/runners` | todos os repositórios |
| Organização | `/org/{org}/settings/actions/runners`            | repos da organização  |
| Usuário     | `/user/settings/actions/runners`                 | repos do usuário      |
| Repositório | `/{owner}/{repo}/settings/actions/runners`       | um único repositório  |

Clique em **Create new runner**, dê um nome e copie o **UUID** e o **Token** exibidos.

> **Alternativa offline (IaC):** dentro do container do server, `forgejo forgejo-cli actions register --secret <hex40>` registra o runner a partir de um segredo de 40 caracteres hexadecimais que você mesmo gera e compartilha entre Forgejo e runner. Útil para Ansible/Kubernetes; exige acesso de admin à instância.

### 5.3 — Gerar e preencher o `runner-config.yml`

Gere o arquivo de configuração padrão dentro de `/srv/forgejo/runner`:

```bash
docker run --rm data.forgejo.org/forgejo/runner:12 forgejo-runner generate-config \
  | sudo tee /srv/forgejo/runner/runner-config.yml > /dev/null
sudo chown 1000:1000 /srv/forgejo/runner/runner-config.yml
```

O arquivo gerado tem **~250 linhas** — mas quase tudo é comentário e valor padrão que **você não toca**. Só precisa de **duas coisas**: os **labels** e a **conexão**. Você pode editar esses dois blocos no arquivo grande, ou simplesmente **substituir todo o conteúdo por este mínimo funcional** (faz exatamente o mesmo):

```yaml
runner:
  # (1) LABELS — mapeiam `runs-on` → imagem. OBRIGATÓRIO.
  labels:
    - docker:docker://node:24-bookworm
    - ubuntu-latest:docker://ghcr.io/catthehacker/ubuntu:act-22.04

server:
  connections:
    forgejo:
      # (2) CONEXÃO — cole o UUID/Token da UI e a URL alcançável pelos jobs (ver 5.5):
      url: https://git.exemplo.com/
      uuid: <UUID_DA_UI>
      token: <TOKEN_DA_UI>
```

> 📄 Esse mínimo está pronto em [`assets/configs/forgejo-runner-config.yml`](../assets/configs/forgejo-runner-config.yml) — copie, preencha `url`/`uuid`/`token` e salve em `/srv/forgejo/runner/runner-config.yml`.

> Estrutura do label: **`<nome>:<tipo>://<imagem>`**. O `<nome>` é o que vai no `runs-on`. O `<tipo>` define a conteinerização: `docker` (Docker/Podman), `lxc` ou `host`. Ex.: `docker:docker://node:24-bookworm` faz `runs-on: docker` rodar dentro da imagem `node:24-bookworm`.

> **Os outros blocos do arquivo gerado** (`log`, `cache`, `container`, `runner.capacity`, timeouts…) têm defaults que funcionam — deixe quietos. Dois pontos do setup dind: o `cache` (ligado por padrão) é _best-effort_ e pode logar avisos sem quebrar o job (desligue com `cache.enabled: false` se incomodar); e `container.docker_host: "-"` (default) significa que o job **não** tem acesso ao Docker — pra `docker build` dentro do job, ver 5.6.

### 5.4 — Subir junto da stack

Com o `runner-config.yml` no lugar:

```bash
docker compose -f forgejo.yml up -d
```

O `runner` usa o `docker-in-docker` (`DOCKER_HOST=tcp://docker-in-docker:2375`), então os jobs rodam **isolados**, sem acesso ao Docker do host. Confirme na UI (_Settings → Actions → Runners_) que ele aparece como **Idle**.

### 5.5 — Como os jobs alcançam o Forgejo (importante!)

Cada job roda num container efêmero **dentro do dind**, numa rede isolada (`FORGEJO-ACTIONS-TASK-...`). O `url` em `server.connections.*.url` precisa ser alcançável **tanto pelo runner quanto pelos containers dos jobs** — senão o `actions/checkout` falha ao clonar. Escolha conforme seu cenário:

- ✅ **Homelab (tudo num host só) — mais confiável:** use o **IP da LAN do host** + porta, ex.: `http://192.168.68.10:3000/`. Funciona do runner E de dentro dos jobs (ambos roteiam pra fora até o host), sem depender de DNS público. ⚠️ Em **VPS com firewall restritivo** (Oracle/Hetzner) isso pode dar `no route to host` (o INPUT do host rejeita container→host:porta) — aí vá de **DOOD + nome interno** (5.9).
- ✅ **Domínio público:** `https://git.exemplo.com/` — só se o próprio servidor consegue se acessar por esse nome (hairpin NAT/split-DNS, ou via Cloudflare Tunnel). Ideal definir a **Base URL** (Parte 4) com o mesmo endereço.
- ❌ **Nunca use o nome interno** `http://server:3000` / `http://forgejo:3000`: o runner até alcança, mas os jobs dentro do dind **não resolvem** esse nome e o checkout quebra.
- 🔁 **Alternativa só-interna (sem IP/domínio alcançável):** use o **modo socket (DOOD)** em vez do dind e ponha os jobs na `forgejo-net` (`container.network`) para resolver `server` internamente — ver 5.6.

### 5.6 — Modos de execução (todas as possibilidades)

- **Docker-in-Docker (dind) — padrão da stack.** Isolado e mais seguro: os jobs não enxergam o Docker do host. É o que o `forgejo.yml` já faz (`docker:dind` + `DOCKER_HOST`).
- **Docker do host (DOOD).** Mais leve: remova o dind, monte `/var/run/docker.sock` no `runner` e configure `container.docker_host` no config. **Risco:** o runner passa a controlar o Docker do host. Para os jobs alcançarem `server`/`db` internamente, defina `container.network: forgejo-net`.
- **`host`.** Um label do tipo `host` (ex.: `self-hosted:host`) roda os steps **direto no host, sem container** — **zero isolamento**, um job pode destruir a máquina. Use só para deploy controlado.
- **`docker build` dentro de um job.** O container do job não tem socket Docker por padrão (erro `Cannot connect to the Docker daemon`). Para buildar imagens, use o **dind** (já presente) ou configure `container.docker_host` (doc oficial _"Utilizing Docker within Actions"_).

### 5.7 — O workflow padrão (Node/npm)

Coloque em **`.github/workflows/ci.yml`** (o Forgejo também lê `.forgejo/workflows/`, `.gitea/workflows/` e `.github/workflows/`). O `runs-on:` precisa casar um **label** do runner. Este é o **padrão recomendado** para a maioria dos projetos Node/JS — `lint`/`test` em todo push pra branch principal e em todo pull request:

> 📄 Pronto para copiar em [`assets/configs/forgejo-ci.yml`](../assets/configs/forgejo-ci.yml) → coloque em `.github/workflows/ci.yml` no seu repositório.

**O que ajustar por projeto:**

- **`branches`** — deixe só `main` ou `master` conforme o seu repo (manter os dois não atrapalha).
- **`node-version`** — a versão que o projeto usa. _Obs.:_ como o label `docker` já é `node:24-bookworm`, o `setup-node` é tecnicamente redundante para Node 24; mantemos por compatibilidade com a sintaxe GitHub e portabilidade. Para CI mais enxuta num runner que já tem o Node certo, pode remover o passo `setup-node`.
- **`npm ci` / `npm test`** — trocar pelos comandos da sua stack (ex.: `yarn`/`pnpm`, ou `pytest`/`go test` com o `setup-*` correspondente).

**Opcionais (recomendados conforme o uso):**

```yaml
# 1. Cancela runs antigos do mesmo branch/PR quando você empurra de novo:
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

# 2. Trava de segurança contra job travado consumindo o runner (dentro de `test:`):
#    timeout-minutes: 15

# 3. Cache de dependências npm (dentro do setup-node):
#    with:
#      node-version: 24
#      cache: 'npm'
#    Depende do cache server do runner estar alcançável de dentro do dind —
#    se a CI ficar instável com cache, remova.
```

> **Secrets e variables** ficam em _Settings → Actions → Secrets/Variables_ (no repositório ou na organização) e chegam como `${{ secrets.X }}` / `${{ vars.X }}`.

### 5.8 — Troubleshooting

| Sintoma                                       | Causa provável / Correção                                                                           |
| :-------------------------------------------- | :-------------------------------------------------------------------------------------------------- |
| Runner não pega o job ("no matching runner")  | `runs-on` não casa nenhum label — confira `runner.labels` no config                                 |
| Runner reiniciando em loop                    | falta o `runner-config.yml` com a seção `server` (registre — 5.2/5.3)                               |
| `actions/checkout` falha (não acha o host)    | registre a conexão com a **URL pública** da instância (5.5)                                         |
| `Cannot connect to the Docker daemon` num job | falta dind/`container.docker_host` para `docker build` (5.6)                                        |
| Job sem internet (não baixa actions/imagens)  | o `uses:` resolve via `DEFAULT_ACTIONS_URL=https://data.forgejo.org`; garanta saída de rede do dind |
| Runner **Offline** / runs "Canceled" em 0s após trocar domínio ou ir pra **.onion** | o `url` do runner aponta pro domínio aposentado ou pro `.onion` (sem Tor nos containers) — ver **5.9** |

> O conceito de runner self-hosted é o mesmo do guia [CI/CD com GitHub Actions + Self-Hosted Runner](./cicd-github-actions.md) — a diferença é que aqui o runner é o `forgejo-runner`, registrado via `runner-config.yml`, e os workflows vivem em `.github/workflows/`.

### 5.9 — Migrei pro `.onion` (ou troquei o domínio) e o CI parou

**Sintoma:** depois de trocar o `ROOT_URL`/domínio da instância (ex.: ir pra `.onion`), o runner fica **Offline** e os runs aparecem **"Canceled" em 0s** (não rodam nenhum step). Conforme você corrige cada camada, o `docker logs forgejo-runner` revela a próxima:

- `dial tcp <domínio-antigo>: no such host` / recusado → o `url` do runner ainda aponta pro domínio que você **aposentou**;
- `dial tcp <IP-do-host>:3000: no route to host` → o **IP do host não serve** (ver abaixo);
- `permission denied ... /var/run/docker.sock` → modo **DOOD** sem acesso ao socket.

> ⚠️ O `url` do runner vive em **`/srv/forgejo/runner/runner-config.yml`** (`server.connections.*.url`) — **não** no compose. Redeploy da stack **não** edita esse arquivo: altere à mão e reinicie o `runner`.

**Por que o IP do host falha** quando runner/jobs estão na **mesma bridge** do Forgejo: o tráfego container→`IP-do-host:3000` ou bate no **firewall do host** (VPS tipo Oracle têm `INPUT ... REJECT` → `no route to host`) ou não passa pelo DNAT da porta publicada (o Docker exclui a própria bridge — sem _hairpin_). E o `.onion` exige **Tor**, que os containers não têm. Sobra o **nome interno `forgejo:3000`** — que só resolve dentro dos jobs se eles estiverem na `forgejo-net`, o que **o dind não permite** (rede isolada). A saída é trocar o dind por **DOOD**.

**Solução (DOOD + nome interno):**

1. **Stack — `server`:** aponte o endereço interno pro checkout/links internos (mantém o `.onion` só na UI):

   ```yaml
   - FORGEJO__server__ROOT_URL=http://<seu-endereco>.onion/
   - FORGEJO__server__LOCAL_ROOT_URL=http://forgejo:3000/
   ```

2. **Stack — troque dind por DOOD:** remova o serviço `docker-in-docker` e ajuste o `runner` (sem `DOCKER_HOST`; monta o socket do host; entra no grupo `docker`):

   ```yaml
   runner:
     image: data.forgejo.org/forgejo/runner:12
     command: forgejo-runner daemon --config runner-config.yml
     restart: always
     group_add:
       - '989' # GID do `getent group docker` no host (3º campo)
     volumes:
       - /srv/forgejo/runner:/data
       - /var/run/docker.sock:/var/run/docker.sock
     depends_on: [server]
     networks: [forgejo-net]
   ```

   > Sem o `group_add`, o runner (não-root) leva `permission denied` no socket. Alternativa GID-independente: `user: "0:0"` (root). Como o DOOD já dá controle do Docker do host, rodar como root não aumenta o risco de forma relevante.

3. **`runner-config.yml`:** url interna + jobs na `forgejo-net`:

   ```yaml
   container:
     network: forgejo-net # jobs entram na forgejo-net e resolvem "forgejo"

   server:
     connections:
       forgejo:
         url: http://forgejo:3000/
         uuid: <seu>
         token: <seu>
   ```

4. Redeploy e `sudo docker logs -f forgejo-runner` → deve logar `declared successfully` + `[poller] launched`, e o runner vira **Idle**. (Alguns `connection refused` no boot são só a corrida de subida do `server` — o `restart: always` reconecta.)

> **Tradeoff:** DOOD dá ao runner controle do Docker do **host** (menos isolamento que o dind). Aceitável para CI de **repositórios privados próprios**; evite num runner que execute PRs de terceiros.

---

## Parte 6: Atualização de dependências (Renovate)

O **Renovate** é o equivalente self-hosted do Dependabot (que é exclusivo do GitHub): ele varre seus repositórios, detecta dependências desatualizadas e abre **pull requests** de atualização automaticamente. Tem suporte oficial à plataforma **Forgejo** e **reaproveita o runner da Parte 5** — rodamos ele como um workflow **agendado** do Forgejo Actions, usando a **imagem FULL** (já vem com os gerenciadores de pacote pré-instalados). Sem serviço extra na stack, sem cron no host.

> A ideia: um único repositório central (`renovate`) agenda a varredura; uma conta-bot abre os PRs; o `autodiscover` descobre todos os repos sozinho.

### 6.1 — Conta-bot + PAT

Crie um usuário dedicado (ex.: `renovate-bot`) e preencha **Full Name** e **Email** no perfil — o Renovate usa os dois como autor dos commits; sem eles os PRs falham. O `gitAuthor` do `config.js` deve bater com esse e-mail. Logado **como o bot**, gere um **PAT** em _Settings → Applications_ com os escopos do Forgejo v15:

- **write:repository** — ler arquivos, criar branches e PRs
- **read:user** — identificar o bot
- **write:issue** — Dependency Dashboard e comentários
- **read:organization** — ler labels/times de organizações

Em **Repository and organization access**, escolha **All (public, private, and limited)**. Para o `autodiscover` enxergar um repo, o bot precisa de permissão de **Write** nele — adicione-o a um _time_ da organização (cobre vários de uma vez) ou como **Collaborator**. O Renovate pula mirrors, repos sem push/pull e repos com PRs desabilitados.

### 6.2 — Repositório central + secret

Crie um repositório `renovate` só para agendar a varredura. Em _Settings → Actions → Secrets_, crie o secret **`RENOVATE_TOKEN`** com o PAT do passo 6.1 (chega ao workflow como `${{ secrets.RENOVATE_TOKEN }}` — nunca hardcode o token nos arquivos).

### 6.3 — Workflow + config

Adicione dois arquivos ao repositório central, **na branch padrão** (obrigatório: schedules fora da branch padrão são ignorados pelo Forgejo):

> 📄 Templates prontos em [`../assets/configs/forgejo-renovate.yml`](../assets/configs/forgejo-renovate.yml) (→ `.github/workflows/renovate.yml`) e [`../assets/configs/forgejo-renovate-config.js`](../assets/configs/forgejo-renovate-config.js) (→ `config.js`, na raiz do repo).

- **`.github/workflows/renovate.yml`** — `runs-on: docker` (o mesmo runner dind da Parte 5) e `container.image: ghcr.io/renovatebot/renovate:<versão>-full`. Agendado com `on.schedule` (cron POSIX de 5 campos, UTC) + `workflow_dispatch` (para testar na mão). O Forgejo substitui o entrypoint da imagem pelo seu runner de steps, então o workflow chama `run: renovate` explicitamente.
- **`config.js`** — config global: `platform: 'forgejo'`, `endpoint` (só a URL base pública — ver 6.3.2), `autodiscover: true`, `gitAuthor`, `onboarding: true`, `dependencyDashboard: true`.

**6.3.1 — Carregar o `config.js` (não pule!).** Num job do Forgejo, o `config.js` **não** é auto-carregado da imagem: o diretório de trabalho dos steps é o _workspace_, não o `/usr/src/app` da imagem. Por isso o workflow faz **`actions/checkout`** (traz o `config.js` do repo central pro workspace) **e** define `RENOVATE_CONFIG_FILE: ${{ github.workspace }}/config.js`. Sem isso, o Renovate roda só com as variáveis de ambiente e **ignora silenciosamente** `gitAuthor`, `onboarding`, dashboard etc. (Esse `checkout` carrega só o config global — os repos-alvo o Renovate clona sozinho via API.)

**6.3.2 — O endpoint (cuidado!).** Use **só a URL base pública** do Cloudflare Tunnel — `https://git.exemplo.com/` — **sem** `/api/v1` (o Renovate acrescenta sozinho). Como na Parte 5.5, os jobs rodam no dind numa rede isolada e só alcançam o Forgejo pela **URL pública**, nunca pelo nome interno do docker. O `RENOVATE_ENDPOINT` do workflow e o `endpoint` do `config.js` devem apontar pro mesmo host.

**6.3.3 — Validar (e evitar "sucesso com 0 repos").** Dispare manualmente em _Actions → renovate → Run workflow_. Na primeira execução, troque `LOG_LEVEL` para `debug` e **confirme no log a linha que lista os repositórios descobertos**. Se descobrir **0 repos**, o job fica verde mas nada acontece (falha silenciosa) — quase sempre é o PAT sem acesso **All (public, private, and limited)** ou o bot sem **Write** em nenhum repo.

### 6.4 — Onboarding (ativar por repositório)

Com `onboarding: true`, a **primeira** varredura não altera nada: só abre um PR **"Configure Renovate"** em cada repo descoberto (adicionando um `renovate.json`). **Nenhum PR de atualização aparece até você mergear o onboarding daquele repo** — é assim que você ativa o Renovate repo a repo. Para opt-out, feche o PR sem mergear (reversível).

> Quer modo 100% automático (sem PR de onboarding)? Troque para `onboarding: false` e adicione `requireConfig: 'optional'` no `config.js` — aí o Renovate roda em todo repo acessível sem precisar de config por repositório.

### 6.5 — Opcionais

- **Token do github.com p/ changelogs (recomendado):** o Renovate lê os changelogs das dependências **no github.com** (não tem relação com o seu Forgejo — as deps vivem lá). Crie um PAT _classic read-only_ em qualquer conta github.com e guarde como secret **`GH_TOKEN`**. ⚠️ **Não** use o nome `GITHUB_TOKEN`: ele é **reservado** (o Forgejo injeta um `GITHUB_TOKEN` automático em todo job), então o secret colidiria e o Renovate receberia o token errado. Depois descomente `RENOVATE_GITHUB_COM_TOKEN: ${{ secrets.GH_TOKEN }}` no workflow (o nome do **env var** `RENOVATE_GITHUB_COM_TOKEN` é fixo do Renovate; só o **secret** é livre). Sem o token, o Renovate bate no rate-limit anônimo do github.com e passa a fechar/reabrir PRs.
- **Automerge:** descomente o bloco `packageRules` do `config.js` para auto-mergear `patch`/`minor` após o CI passar. O `platformAutomerge` (auto-merge nativo do Forgejo) é suportado a partir do v10.0.0 — esta instância é v15.0.2. Use com proteção de branch/status checks.
- **Alcance e limites:** `autodiscoverFilter: ['minha-org/*']` restringe a descoberta; `prHourlyLimit` controla o teto de PRs por hora (deixamos `0` pra não afunilar a primeira varredura; volte pra `2` se um sweep grande gerar PRs demais).
- **Tag da imagem FULL:** fixe uma versão (`:<versão>-full`) e re-pingue periodicamente — `:full`/`:latest` são mutáveis. Depois de ativado, o próprio Renovate passa a abrir PRs pra atualizar essa tag.

> Como na Parte 5, o runner já existe e é reaproveitado: o Renovate é só mais um workflow em `.github/workflows/`. A diferença é que ele roda **agendado** (não por push) e clona os repos-alvo sozinho via API.

### 6.6 — Portabilidade (se migrar pro GitHub)

O **`renovate.json` é portátil**: o mesmo arquivo funciona no GitHub, GitLab ou Forgejo sem mudança. O que é específico do Forgejo aqui é só o **motor** (o workflow self-hosted + runner + PAT do bot). Se um repositório for parar no **GitHub**:

- **O Renovate continua funcionando** — o GitHub é a plataforma original dele. Você **não precisa** do workflow self-hosted: basta instalar o **Renovate App** (gratuito, hospedado pela Mend) no repo, e ele usa o seu mesmo `renovate.json`.
- O **Dependabot** (nativo do GitHub) é só uma **alternativa**, não obrigatório. Quem prefere o Renovate fica com ele e mantém o `renovate.json`.
- ⚠️ **Dual-host (GitHub + Forgejo ao mesmo tempo):** workflows em `.github/workflows/` com `runs-on: docker` e endpoint do Forgejo **quebram** no GitHub Actions. Nesse caso, use a **App do Renovate** no lado GitHub e deixe o self-hosted só no Forgejo.

---

## Notas Importantes

- **Segurança do CI:** o `docker-in-docker` roda **privileged** (necessário pro dockerd interno) e executa código arbitrário dos workflows. Em instância **privada e só sua** é aceitável; se abrir para terceiros, revise a doc oficial _"Securing Forgejo Actions Deployments"_ e considere isolar o runner num host/VM separado.
- **SSH na porta 8122:** como o `22` do host costuma ser o SSH do próprio servidor, o Git do Forgejo foi mapeado para `8122`. Configure seus remotes como `ssh://git@SEU_HOST:8122/usuario/repo.git`.
- **Backup:** copie `/srv/forgejo` com os containers parados para um snapshot consistente. O essencial é `data` + `db` + `runner`; o `dind` é só cache de imagens e pode ser descartado.
- **Atualização:** troque as tags das imagens (`forgejo:15.0.2`, `runner:12`) e rode `docker compose -f forgejo.yml up -d`; o Forgejo aplica as migrations do banco no boot.
- **Dependências (Renovate, não Dependabot):** o Dependabot é exclusivo do GitHub. No Forgejo, o equivalente para atualização automática de dependências é o **Renovate**, que tem suporte oficial à plataforma — configurado na [Parte 6](#parte-6-atualização-de-dependências-renovate).
