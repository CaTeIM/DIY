# 🧠 Setup do AI-Memory (AkitaOnRails)

Este documento detalha a instalação do [ai-memory](https://github.com/akitaonrails/ai-memory) em uma arquitetura dividida:

1. **O Cérebro (Servidor):** Container Docker rodando no Orange Pi (Linux/Portainer).
2. **O Espião (Cliente):** CLI nativo em Rust rodando no Windows interceptando o Claude Code via Antigravity IDE.

## 🏗️ 1. O Cérebro (Orange Pi / Servidor)

O backend é responsável pelo banco vetorial, consolidação de memórias e comunicação com a API do Gemini.

### Preparação do Host

Crie o diretório de dados e ajuste a permissão para o usuário interno do container (UID 1000):

```bash
sudo mkdir -p /srv/ai-memory/data
sudo chown -R 1000:1000 /srv/ai-memory/data
```

### Build da Imagem Local

Como a imagem oficial pode não estar disponível no GHCR, clone e compile localmente no Orange Pi:

```bash
cd /srv/ai-memory/
git clone https://github.com/akitaonrails/ai-memory.git source
cd source
docker build -t ai-memory:local -f docker/Dockerfile .
```

### Stack no Portainer (docker-compose.yml)

Crie uma nova Stack no Portainer chamada `ai-memory`:

1. Acesse o Portainer → **Stacks** → **Add Stack**
2. **Nome:** `ai-memory`
3. Cole o conteúdo do arquivo [`assets/stacks/ai-memory.yml`](../assets/stacks/ai-memory.yml) no Editor Web.
4. Clique em **Deploy the stack**.

_Nota: Substitua `IP_DO_SERVIDOR` pelo IP real do seu servidor onde está rodando `docker-compose.yml`._

**Environment Variables no Portainer:**

- `AI_MEMORY_AUTH_TOKEN`: Senha forte gerada (ex: via Bitwarden).
- `GEMINI_API_KEY`: Chave gerada no Google AI Studio vinculada ao projeto do GCP.

## 🕵️ 2. O Espião (Windows / Cliente Local)

Os scripts de interceptação (hooks) no Windows precisam ser em PowerShell (`.ps1`). Para gerá-los e comunicá-los com o servidor, precisamos do CLI compilado nativamente.

### Instalação do Rust

No PowerShell (como Administrador, se necessário), instale o Rustup:

```powershell
winget install Rustlang.Rustup
```

_⚠️ Feche e abra o terminal após a instalação para recarregar as variáveis de ambiente._

### Compilação do CLI

Clone o repositório no Windows e instale o binário globalmente:

```powershell
cd "D:\cateim\Google Drive\GitHub\ai-memory"
cargo install --path crates/ai-memory-cli
```

### Instalação do MCP e Hooks no Claude Code

Com o binário `ai-memory` disponível, aponte os instaladores diretamente para o IP do Orange Pi e forneça o token.

**1. Instalar o servidor MCP:**

```powershell
ai-memory install-mcp --client claude-code --apply --server-url "http://IP_DO_SERVIDOR:49374/mcp" --auth-token "SUA_SENHA_AQUI"
```

**2. Instalar os Hooks de ciclo de vida:**
_Nota: É obrigatório apontar `--hooks-dir` para a pasta original do repositório clonado no Windows._

```powershell
ai-memory install-hooks --agent claude-code --apply --hooks-dir "D:\cateim\Google Drive\GitHub\ai-memory\hooks" --server-url "http://IP_DO_SERVIDOR:49374" --auth-token "SUA_SENHA_AQUI"
```

## 🧪 3. Verificação e Teste

Abra o terminal no Antigravity IDE, inicie o `claude` e envie o prompt:

> "Use suas tools do ai-memory para verificar o status da minha memória e me diga se há conexão."

**Resultado Esperado:** O Claude deverá exibir uma tabela com as métricas do banco de dados (Sessões, Observações, Páginas), provando que o hook interceptou o envio e o MCP buscou o status real no Orange Pi.
