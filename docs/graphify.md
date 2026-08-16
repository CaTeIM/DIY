# 🧬 Graphify — Knowledge Graph para Codebases

Ferramenta CLI + skill para agentes de IA que transforma qualquer codebase (código, docs, PDFs, schemas SQL, configs, imagens) em um **knowledge graph consultável**. Em vez de grep e leitura bruta de arquivos, o agente navega por um grafo persistente de conceitos e relações — **71,5× menos tokens por consulta** e contexto que sobrevive entre sessões.

> [!NOTE]
> O Graphify **não é um serviço Docker**: é uma CLI Python instalada localmente que gera artefatos estáticos. Não há stack, container nem porta exposta. Este guia documenta a instalação e uso no ambiente de desenvolvimento (Windows/macOS/Linux).

## Arquitetura

```
┌─ MÁQUINA LOCAL ───────────────────────────────────────────────────┐
│                                                                   │
│  Agente (Claude Code / Cursor / Codex / Gemini CLI)               │
│    └─► /graphify .                                                │
│          └─► CLI graphify (Python)                                │
│                ├─ tree-sitter → AST parsing (determinístico)      │
│                ├─ Claude Vision → extrai conceitos de PDFs/imgs   │
│                └─► graphify-out/                                  │
│                      ├── graph.html         (visualização)        │
│                      ├── graph.json         (contexto p/ agente)  │
│                      ├── GRAPH_REPORT.md    (resumo)              │
│                      ├── obsidian/          (vault Obsidian)      │
│                      ├── wiki/              (artigos navegáveis)  │
│                      └── cache/             (SHA256, incremental) │
└───────────────────────────────────────────────────────────────────┘
```

**Como funciona:**

- **Código-fonte:** parsing AST local via [tree-sitter](https://tree-sitter.github.io/tree-sitter/) — determinístico, nenhum código sai da máquina.
- **Não-código (PDFs, imagens, diagramas, screenshots):** usa Claude Vision para extrair conceitos e relações.
- **Resultado:** um grafo de nós (conceitos) e arestas (relações) persistido em `graph.json`. O agente consulta o grafo em vez de reler os arquivos brutos.

---

## 🛠️ Parte 1: Pré-requisitos

- **Python 3.10+** instalado e no PATH.
- **Um agente compatível:** Claude Code, Cursor, Codex ou Gemini CLI.
- **(Opcional) Obsidian** para abrir o vault gerado como wiki visual.

> ⚠️ **Windows:** se o comando `graphify` não for reconhecido após a instalação, adicione a pasta de Scripts do Python ao PATH: `%APPDATA%\Python\Python3xx\Scripts` (substitua `3xx` pela sua versão, ex: `313`). Ou use `pipx install graphifyy` que gerencia o PATH automaticamente.

> ⚠️ **macOS (externally managed):** se `pip install` falhar com erro de "externally-managed-environment", use `pipx install graphifyy`.

---

## 📦 Parte 2: Instalação

### 2.1. Instalar o pacote

```bash
pip install graphifyy && graphify install
```

> ℹ️ O pacote no PyPI se chama `graphifyy` (com dois "y") temporariamente enquanto o nome `graphify` está sendo reivindicado. A CLI e o comando de skill continuam sendo `graphify`.

### 2.2. Instalação manual (alternativa via curl)

Se preferir instalar apenas a skill sem o pacote Python:

```bash
mkdir -p ~/.claude/skills/graphify
curl -fsSL https://raw.githubusercontent.com/safishamsi/graphify/v1/skills/graphify/skill.md \
  > ~/.claude/skills/graphify/SKILL.md
```

Adicione ao `~/.claude/CLAUDE.md`:

```markdown
- **graphify** (`~/.claude/skills/graphify/SKILL.md`) - any input to knowledge graph. Trigger: `/graphify`
  When the user types `/graphify`, invoke the Skill tool with `skill: "graphify"` before doing anything else.
```

### 2.3. Verificar a instalação

```bash
graphify --version
```

---

## 🚀 Parte 3: Uso

### 3.1. Comandos básicos

Dentro do agente (Claude Code, Cursor, etc.), digite:

```
/graphify                          # roda no diretório atual
/graphify ./src                    # roda em uma pasta específica
/graphify ./raw --mode deep        # extração mais agressiva de arestas INFERRED
/graphify ./raw --update           # re-extrai apenas arquivos alterados, merge no grafo existente
```

### 3.2. Adicionar fontes externas

```
/graphify add https://arxiv.org/abs/1706.03762        # busca um paper, salva e atualiza o grafo
/graphify add https://x.com/karpathy/status/...       # busca um tweet
```

### 3.3. Consultar o grafo

```
/graphify query "what connects attention to the optimizer?"
/graphify path
```

### 3.4. Outputs gerados

Todos os artefatos ficam na pasta `graphify-out/` do projeto:

| Arquivo / Pasta   | Descrição                                                                        |
| :---------------- | :------------------------------------------------------------------------------- |
| `graph.html`      | Visualização interativa do grafo — clique nos nós, busque, filtre por comunidade |
| `graph.json`      | Grafo persistente em JSON — o agente consulta semanas depois sem re-processar    |
| `GRAPH_REPORT.md` | Resumo: god nodes, conexões surpreendentes, perguntas sugeridas                  |
| `obsidian/`       | Vault Obsidian — abra como vault para navegar visualmente                        |
| `wiki/`           | Artigos estilo Wikipedia para navegação do agente (com `--wiki`)                 |
| `cache/`          | Cache SHA256 — re-runs processam apenas arquivos modificados                     |

### 3.5. Multimodal

O Graphify é **totalmente multimodal**: aceita código, PDFs, Markdown, screenshots, diagramas, fotos de quadro branco e até imagens em outros idiomas. Ele usa Claude Vision para extrair conceitos e conectá-los no grafo.

---

## 🔄 Parte 4: Atualização

```bash
pip install --upgrade graphifyy
```

O cache em `graphify-out/cache/` é preservado — uma atualização do pacote não reprocessa arquivos já analisados.

---

## ⚠️ Troubleshooting

### `graphify: command not found` (Windows)

O pip instalou o binário em uma pasta que não está no PATH. Soluções:

1. Adicionar `%APPDATA%\Python\Python3xx\Scripts` ao PATH do sistema.
2. Ou usar `pipx install graphifyy` (gerencia PATH automaticamente).

### `graphify: command not found` (macOS)

Provavelmente o Python está em modo "externally managed" (Homebrew). Use:

```bash
pipx install graphifyy
```

### Grafo vazio ou com poucos nós

- Verifique se a pasta alvo contém arquivos suportados (código, `.md`, `.pdf`, `.sql`, `.yml`, etc.).
- Use `--mode deep` para extração mais agressiva.
- Arquivos binários não-suportados são ignorados silenciosamente.

### Re-run não detecta alterações

O cache usa SHA256 dos arquivos. Se o conteúdo não mudou, o arquivo é pulado. Para forçar reprocessamento completo, apague `graphify-out/cache/`.

---

## 🌐 Acessos

| Recurso            | URL / Caminho                                                       |
| :----------------- | :------------------------------------------------------------------ |
| **PyPI**           | [`graphifyy`](https://pypi.org/project/graphifyy/)                  |
| **GitHub**         | [Graphify-Labs/graphify](https://github.com/Graphify-Labs/graphify) |
| **Outputs locais** | `./graphify-out/` (relativo ao projeto)                             |

---

## 📚 Referências

- [Graphify GitHub](https://github.com/Graphify-Labs/graphify)
- [PyPI — graphifyy](https://pypi.org/project/graphifyy/)
- [tree-sitter (parsing AST)](https://tree-sitter.github.io/tree-sitter/)
- [Obsidian (vault viewer)](https://obsidian.md/)
