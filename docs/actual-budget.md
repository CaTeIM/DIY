# 💰 Actual Budget no Home Lab (Debian)

Gerenciador financeiro pessoal self-hosted baseado em envelope budgeting. Interface web moderna com suporte a importação de CSV, regras de categorização automática e sincronização entre dispositivos via servidor próprio.

## Arquitetura

```
┌─ REDE LOCAL ──────────────────────────────────────────────────┐
│                                                               │
│  Dispositivo ──► http://IP_DO_SERVIDOR:5006                   │
│  ──► Actual Budget Server (container)                         │
│  ──► /srv/actualbudget/data (SQLite + arquivos de orçamento)  │
└───────────────────────────────────────────────────────────────┘
```

**Porta no host:**

| Porta Host | Porta Container | Uso                   |
| :--------- | :-------------- | :-------------------- |
| `5006/tcp` | `5006`          | Web UI + API de Sync  |

> [!NOTE]
> O Actual Budget não requer banco de dados externo. Tudo é persistido em arquivos SQLite dentro do volume `/srv/actualbudget/data`, o que torna o backup extremamente simples.

---

## 🛠️ Parte 1: Preparação do Host (Debian)

Execute todos os comandos no terminal SSH do servidor.

### 1.1. Criar diretório de persistência

```bash
sudo mkdir -p /srv/actualbudget/data
```

### 1.2. Liberar Porta no Firewall (se UFW ativo)

```bash
sudo ufw allow 5006/tcp
sudo ufw reload
```

---

## 📦 Parte 2: Deploy via Portainer (Stack)

1. Acessar o Portainer → **Stacks** → **Add Stack**
2. **Nome:** `actual-budget`
3. Colar o conteúdo do arquivo [`assets/stacks/actual-budget.yml`](../assets/stacks/actual-budget.yml) no Editor Web.
4. Clicar em **Deploy the stack**.

> [!NOTE]
> Não há variáveis de ambiente obrigatórias para o deploy inicial. A senha de acesso ao arquivo de orçamento é definida na primeira vez que você abre a interface web.

---

## ⚙️ Parte 3: Configuração Pós-Deploy

### 3.1. Primeiro Acesso

1. Abra `http://IP_DO_SERVIDOR:5006` no navegador.
2. Clique em **Create new file** para criar seu primeiro orçamento.
3. Defina uma senha para proteger o arquivo (usada na sincronização entre dispositivos).

### 3.2. Criar Categorias

O Actual Budget não importa categorias automaticamente do CSV. Crie-as antes de importar as transações em **Orçamento** → clique no **+** para adicionar grupos e categorias.

---

## 📥 Parte 4: Importação de Dados (Migração do Mobills)

### 4.1. Preparar o CSV

O Mobills exporta em **UTF-16 LE**. Converta para UTF-8 no Windows (PowerShell):

```powershell
Get-Content "RELATORIO_TRANSACOES.csv" -Encoding Unicode | Set-Content "RELATORIO_UTF8.csv" -Encoding UTF8
```

### 4.2. Desmembrar por Conta

O Actual Budget importa **por conta** — uma por vez. Use o script abaixo para dividir o CSV do Mobills em um arquivo por conta, já no formato correto (`Date, Payee, Notes, Category, Amount`):

```powershell
$rows = Import-Csv "RELATORIO_UTF8.csv" -Delimiter ";" -Encoding UTF8
$outDir = "actual_import"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$contas = $rows | Select-Object -ExpandProperty Conta | Sort-Object -Unique

foreach ($conta in $contas) {
    $filtrado = $rows | Where-Object { $_.Conta -eq $conta }

    $result = $filtrado | ForEach-Object {
        $valorStr = $_.Valor -replace '\.', '' -replace ',', '.'
        $valor = [double]$valorStr
        $dataParsed = [datetime]::ParseExact($_.Data, "dd/MM/yyyy", $null)

        [PSCustomObject]@{
            Date     = $dataParsed.ToString("yyyy-MM-dd")
            Payee    = $_.Descricao
            Notes    = $_.Subcategoria
            Category = $_.Categoria
            Amount   = $valor.ToString("F2", [System.Globalization.CultureInfo]::InvariantCulture)
        }
    }

    $safeName = $conta -replace '[\\/:*?"<>|]', '_'
    $result | Export-Csv -Path (Join-Path $outDir "$safeName.csv") -Delimiter "," -NoTypeInformation -Encoding UTF8
}
```

O script gera os arquivos em `actual_import/`, um por conta, prontos para importar.

### 4.3. Consolidar Categorias (Opcional)

Antes de importar, é recomendável unificar categorias duplicadas ou granulares demais. Exemplo de script para renomear em lote todos os arquivos gerados:

```powershell
$mapa = @{
    "Investimento"    = "Investimentos"
    "Reajuste fatura" = "Reajuste"
    "Reajuste*"       = "Reajuste"
    "Roupa"           = "Vestuário"
    # Adicione outros mapeamentos conforme necessário
}

Get-ChildItem "actual_import\*.csv" | ForEach-Object {
    $conteudo = [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8)
    foreach ($de in $mapa.Keys) {
        $conteudo = $conteudo -replace [regex]::Escape("""$de"""), """$($mapa[$de])"""
    }
    [System.IO.File]::WriteAllText($_.FullName, $conteudo, [System.Text.Encoding]::UTF8)
}
```

### 4.4. Importar no Actual Budget

Para cada conta:

1. Clique na conta desejada no menu lateral.
2. Clique em **Importar** e selecione o CSV correspondente.
3. Configure os campos:
   - **Formato de Data:** `YYYY-MM-DD`
   - **Delimitador:** `,`
   - Mapeie: `Date → Data`, `Payee → Beneficiário`, `Notes → Notas`, `Category → Categoria`, `Amount → Valor`
4. Clique em **Importar N transações**.

> [!IMPORTANT]
> As categorias precisam existir no Actual Budget antes de importar. Caso contrário, a coluna Categoria aparecerá vazia no preview, mas os nomes serão importados como texto e poderão ser vinculados às categorias depois via **Regras**.

> [!NOTE]
> Valores negativos no campo `Amount` são interpretados automaticamente como saídas (despesas). Não é necessário usar colunas separadas de entrada/saída.

---

## ⚠️ Troubleshooting

### Categoria aparece vazia no preview da importação

**Causa:** A categoria referenciada no CSV ainda não existe no Actual Budget.
**Fix:** Crie as categorias em **Orçamento** antes de importar, usando exatamente os mesmos nomes que estão no CSV.

### Valores negativos perdem o sinal ao ativar "Selecione a coluna para indicar se é entrada/saída"

**Causa:** Essa opção espera uma coluna separada com um flag de texto (ex: `entrada`/`saída`), não o sinal do número.
**Fix:** Não use essa opção. Deixe apenas `Amount → Valor` mapeado e os sinais serão lidos corretamente.

---

## 🌐 Acessos

| Recurso       | URL                              |
| :------------ | :------------------------------- |
| **Web UI**    | `http://IP_DO_SERVIDOR:5006`     |
| **Portainer** | Stack `actual-budget`            |

---

## 📚 Referências

- [Actual Budget — Documentação Oficial](https://actualbudget.org/docs/)
- [Actual Budget — Importação de CSV](https://actualbudget.org/docs/transactions/importing/)
- [Actual Budget — GitHub](https://github.com/actualbudget/actual)
