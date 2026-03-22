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

O runner é uma aplicação independente. Instale-o em uma pasta separada do projeto.

```bash
mkdir ~/actions-runner && cd ~/actions-runner
```

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
        needs: backend          # só roda se backend passar
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
        needs: [backend, frontend]   # só deploya se CI passar 100%
        if: github.event_name == 'push'  # não deploya em PRs

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

| Campo | Valor |
|-------|-------|
| Name | `DEPLOY_DIR` |
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
