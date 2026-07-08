# Guia: CI/CD com GitHub Actions + Self-Hosted Runner no Debian

Este guia documenta como configurar um pipeline de **integração e entrega contínua (CI/CD)** usando o GitHub Actions com um runner self-hosted instalado em um servidor Debian (OrangePi 5, Raspberry Pi, etc.).

A ideia é simples: a cada push no branch `master`, o GitHub roda os testes e verificações automaticamente na nuvem (CI). Se tudo passar, o servidor recebe o comando de atualização e faz o deploy de forma automatizada (CD), sem nenhuma intervenção manual.

**Arquitetura:**

- **CI (testes, lint, build)** → roda nos servidores do GitHub (`ubuntu-latest`)
- **CD (deploy)** → roda no seu servidor via self-hosted runner

> **Pré-requisito:** O servidor deve ter um script de deploy funcional (ex: `update.sh`) e o projeto já clonado com o `.env` configurado.

---

## Parte 1: Instalar o Self-Hosted Runner no Servidor

### 1. Criar a Pasta do Runner

O runner é uma aplicação independente. Instale-o em uma pasta separada do projeto. Seguindo o padrão deste repo (dados sempre em `/srv/<serviço>`), use `/srv/actions-runner`:

```bash
sudo mkdir -p /srv/actions-runner && cd /srv/actions-runner
```

> **Nota:** o runner costuma rodar como **root** em OrangePi bare-metal, então `/srv/actions-runner` é coerente com o restante da infra. Se você já tem um runner em `~/actions-runner` ou `/root/actions-runner`, veja [Mover o Runner](#mover-o-runner-para-outra-pasta-sem-re-registrar) para realocá-lo **sem perder o registro**.

### 2. Baixar o Runner

No GitHub, navegue até o **repositório** (não a organização) e acesse:

```
github.com/SEU_USUARIO/SEU_REPO → Settings → Actions → Runners → New self-hosted runner
```

> **Dica de navegação:** a aba **Settings** fica na barra horizontal do repositório, ao lado de Insights. Se não aparecer, você precisa ser admin do repositório.

Selecione **Linux** e a arquitetura do seu servidor:

- `ARM64` → OrangePi 5, Raspberry Pi 4/5
- `x64` → Intel/AMD

O GitHub vai gerar os comandos personalizados com token e versão já preenchidos. O download é parecido com este (o token e versão mudam):

```bash
curl -o actions-runner-linux-arm64-2.332.0.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.332.0/actions-runner-linux-arm64-2.332.0.tar.gz

# Verificar integridade (hash fornecido pelo GitHub)
echo "HASH_AQUI  actions-runner-linux-arm64-2.332.0.tar.gz" | shasum -a 256 -c

# Extrair
tar xzf ./actions-runner-linux-arm64-2.332.0.tar.gz
```

### 3. Configurar o Runner

Use o token gerado pelo GitHub (expira em 1h):

```bash
# Se rodar como root (comum em servidores pessoais)
RUNNER_ALLOW_RUNASROOT=1 ./config.sh \
  --url https://github.com/SEU_ORG_OU_USUARIO \
  --token TOKEN_GERADO_PELO_GITHUB
```

Durante a configuração interativa, pressione Enter para aceitar os padrões:

- **Runner group:** Default
- **Runner name:** nome do servidor (ex: `orangepi5`)
- **Labels:** `self-hosted, Linux, ARM64` (gerado automaticamente)
- **Work folder:** `_work`

> **Nota:** Se o servidor roda como root (usual em Orange Pi bare-metal), a variável `RUNNER_ALLOW_RUNASROOT=1` é obrigatória em todos os comandos do runner.

### 4. Garantir Acesso ao Docker

O runner precisa executar comandos Docker durante o deploy:

```bash
# Se estiver usando usuário não-root
usermod -aG docker $USER
# Relogar ou executar: newgrp docker

# Se root, já tem acesso (verificar)
docker ps
```

### 5. Instalar como Serviço (Autostart)

Para que o runner inicie automaticamente com o servidor:

```bash
RUNNER_ALLOW_RUNASROOT=1 ./svc.sh install
RUNNER_ALLOW_RUNASROOT=1 ./svc.sh start

# Verificar status
./svc.sh status
```

O runner agora fica escutando jobs do GitHub permanentemente, mesmo após reinicializações do servidor.

---

## Parte 2: Configurar o Workflow no Repositório

Crie o arquivo `.github/workflows/ci.yml` na raiz do repositório:

```yaml
name: CI/CD

on:
  push:
    branches: ["master", "main"]
  pull_request:
    branches: ["master", "main"]

permissions:
  contents: read

jobs:
  # --- CI: roda na nuvem do GitHub ---

  backend:
    name: Backend — Tests & SAST
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: backend

    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.12"
          cache: "pip"
          cache-dependency-path: backend/requirements.txt

      - name: Install Dependencies
        run: |
          python -m pip install --upgrade pip
          pip install -r requirements.txt bandit

      - name: Run Tests
        env:
          SECRET_KEY: "test-secret-key-for-ci-only"
          # ... outras env vars de teste
        run: python manage.py test --settings=setup.test_settings

      - name: Security Scan (Bandit)
        run: bandit -r . -ll -x ./tests

  frontend:
    name: Frontend — Lint & Build
    runs-on: ubuntu-latest
    needs: backend # só roda se backend passar
    defaults:
      run:
        working-directory: frontend

    steps:
      - uses: actions/checkout@v4

      - name: Set up Node.js
        uses: actions/setup-node@v4
        with:
          node-version: "22"
          cache: "npm"
          cache-dependency-path: frontend/package-lock.json

      - name: Install Dependencies
        run: npm ci

      - name: Lint
        run: npm run lint

      - name: Build
        run: npm run build

  # --- CD: roda no seu servidor via self-hosted runner ---

  deploy:
    name: Deploy — Production
    runs-on: self-hosted
    needs: [backend, frontend] # só deploya se CI passar 100%
    if: github.event_name == 'push' # não deploya em PRs

    steps:
      - name: Run deploy script
        run: cd "${{ secrets.DEPLOY_DIR }}" && ./update.sh
```

**Fluxo resultante:**

```
push → [backend] → [frontend] → [deploy no servidor]
PR   → [backend] → [frontend]  (sem deploy)
```

---

## Parte 3: Configurar o Secret DEPLOY_DIR

O job de deploy precisa saber onde o projeto está no servidor.

No GitHub, navegue até o **repositório** e acesse:

```
github.com/SEU_USUARIO/SEU_REPO → Settings → Security → Secrets and variables → Actions → New repository secret
```

> **Dica de navegação:** no menu lateral esquerdo da página de Settings, procure a seção **Security** e depois **Secrets and variables**. Clique em **Actions** e depois no botão verde **New repository secret**.

| Campo  | Valor                                                        |
| ------ | ------------------------------------------------------------ |
| Name   | `DEPLOY_DIR`                                                 |
| Secret | Caminho absoluto do projeto no servidor (ex: `/srv/projeto`) |

> **Importante:** Use **repository secrets** (Settings do repositório), não organization secrets. No plano gratuito do GitHub, secrets de organização não funcionam com repositórios privados.

---

## Parte 4: Verificar o Pipeline

Após configurar tudo, faça um push para `master` e acompanhe em:

```
github.com/SEU_USUARIO/SEU_REPO → aba Actions → selecione o workflow → veja os jobs em tempo real
```

Para confirmar que o runner está online e sendo reconhecido:

```
github.com/SEU_USUARIO/SEU_REPO → Settings → Actions → Runners
```

O servidor deve aparecer com o status **Idle** (aguardando jobs) ou **Active** (executando).

---

## Mover o Runner para Outra Pasta (sem re-registrar)

Se o runner foi instalado em `~/actions-runner` ou `/root/actions-runner` e você quer movê-lo (ex.: padronizar em `/srv/actions-runner`), **não precisa do token nem re-registrar**. As credenciais persistentes ficam nos arquivos ocultos da pasta (`.credentials`, `.credentials_rsaparams`, `.runner`) — mover a pasta preserva o registro e o runner reconecta sozinho com o mesmo nome e labels.

> ⚠️ **A pegadinha:** os symlinks `bin` e `externals` dentro da pasta são **absolutos** (apontam para o caminho antigo). Depois do `mv` eles quebram e precisam ser recriados — senão o serviço não inicia.

```bash
# 1. Parar e DESINSTALAR o serviço (não desregistra do GitHub — só mexe no systemd)
cd /root/actions-runner   # ou ~/actions-runner
sudo ./svc.sh stop
sudo ./svc.sh uninstall

# 2. Mover a pasta inteira (preserva credenciais, permissões e arquivos ocultos)
sudo mv /root/actions-runner /srv/actions-runner

# 3. Recriar os symlinks que apontavam para o caminho antigo
cd /srv/actions-runner
for link in bin externals; do
  base=$(basename "$(readlink "$link")")          # ex.: bin.2.335.1
  sudo ln -sfn "/srv/actions-runner/$base" "$link"
done

# 4. Conferir se sobrou referência ao caminho antigo (fora de logs) — deve voltar VAZIO
grep -rlI "/root/actions-runner" /srv/actions-runner \
  --exclude-dir=_diag --exclude-dir=_work 2>/dev/null

# 5. Reinstalar o serviço a partir do novo local e iniciar
sudo ./svc.sh install root
sudo ./svc.sh start
sudo ./svc.sh status
```

Confirme que o serviço aponta para o novo caminho e que o runner reconectou:

```bash
grep -E 'WorkingDirectory|ExecStart' /etc/systemd/system/actions.runner.*.service   # deve mostrar /srv/actions-runner
journalctl -u 'actions.runner.*' --no-pager | tail -5   # procure "√ Connected to GitHub" e "Listening for Jobs"
```

Na página **Settings → Actions → Runners** o runner fica alguns segundos offline e volta para **Idle** 🟢.

> ℹ️ **Rollback:** `sudo ./svc.sh uninstall` → `sudo mv /srv/actions-runner /root/actions-runner` → recriar os symlinks apontando de volta para `/root/...` → `sudo ./svc.sh install root && sudo ./svc.sh start`.

> 💾 **Limpeza opcional:** após a migração dá pra apagar o tarball do instalador (`actions-runner-linux-arm64-*.tar.gz`) e versões antigas de `bin.*`/`externals.*` que sobram dos auto-updates.

---

## Build Nativo ARM64 (evitar emulação QEMU)

Quando o CI **builda imagens Docker arm64** (para rodar em OrangePi/Raspberry), buildar num runner hospedado x86 (`ubuntu-latest`) exige **emulação QEMU** — cada compilação nativa (gcc, deps de Python/Node) roda 10-30x mais lenta, e um build simples passa fácil de **30 minutos**. Como o próprio runner self-hosted é ARM64, a solução é buildar **nativo nele**.

No job que constrói as imagens, troque o runner e **remova o QEMU**:

```yaml
build-push:
  runs-on: [self-hosted, ARM64] # nativo na OrangePi (antes: ubuntu-latest + QEMU)
  needs: [backend, frontend]

  steps:
    - uses: actions/checkout@v4

    # (NÃO usar docker/setup-qemu-action — o build é nativo)
    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v3

    - name: Log in to GHCR
      uses: docker/login-action@v3
      with:
        registry: ghcr.io
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}

    - name: Build & Push
      uses: docker/build-push-action@v6
      with:
        context: ./backend
        push: true
        platforms: linux/arm64
        tags: ghcr.io/ORG/IMAGEM:latest
        cache-from: type=gha,scope=backend
        cache-to: type=gha,mode=max,scope=backend
```

Resultado: **~30 min → poucos minutos** (e segundos quando o cache pega, desde que o Dockerfile copie as dependências **antes** do código-fonte).

> ℹ️ **Repo privado:** runners ARM64 **hospedados** do GitHub são grátis só em repos **públicos**. Em repo privado, o self-hosted ARM (esta OrangePi) é o que dá build nativo sem custo.

> ⚠️ **Docker no runner:** o build executa `docker` na máquina do runner. Como ele roda como **root**, já tem acesso ao socket. Se rodar como usuário comum, adicione-o ao grupo `docker` (`usermod -aG docker <user>`).

---

## Referência: Comandos do Runner

```bash
# Iniciar manualmente (sem instalar como serviço)
RUNNER_ALLOW_RUNASROOT=1 ./run.sh

# Gerenciar o serviço
RUNNER_ALLOW_RUNASROOT=1 ./svc.sh start
RUNNER_ALLOW_RUNASROOT=1 ./svc.sh stop
RUNNER_ALLOW_RUNASROOT=1 ./svc.sh status
RUNNER_ALLOW_RUNASROOT=1 ./svc.sh uninstall

# Reconfigurar (novo token ou nova URL)
RUNNER_ALLOW_RUNASROOT=1 ./config.sh remove
RUNNER_ALLOW_RUNASROOT=1 ./config.sh --url URL --token TOKEN
```

> **Nota sobre tokens:** O token de registro do runner expira em **1 hora**. Se precisar reconfigurar, gere um novo em Settings → Actions → Runners → New self-hosted runner.

---

## Notas Importantes

**Por que self-hosted para deploy e não SSH?**
O runner roda direto no servidor, então tem acesso nativo ao Docker e ao sistema de arquivos. Não precisa de chaves SSH nem de expor portas extras — mais simples e mais seguro.

**O script `update.sh`**
O job de deploy apenas executa o script de atualização do projeto (`./update.sh`). Esse script cuida de tudo: `git pull`, `docker compose build`, restart dos containers e migrations. Mantenha a lógica de deploy centralizada nesse script — o workflow só precisa chamar ele.

**Múltiplos projetos no mesmo servidor**
Um único runner atende todos os repositórios que precisarem. Para cada novo projeto:

1. Adicione `runs-on: self-hosted` ao job de deploy
2. Crie o secret `DEPLOY_DIR` no novo repositório com o caminho correto
3. O mesmo runner vai escutar e processar os jobs dos dois projetos

Para compartilhar o runner entre **todos os repos de uma organização** de uma vez, registre-o no nível da **organização** (`--url https://github.com/ORG`, em vez do repo) em **Org → Settings → Actions → Runners**. Ele aparece com a tag `Organization` e fica disponível para os repositórios do grupo escolhido — foi assim que o `orangepi5` foi registrado para a org `Self-Labs`.
