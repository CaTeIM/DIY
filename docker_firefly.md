# 💰 Firefly III no Home Lab (Debian + Cloudflare Tunnel)

Gerenciador financeiro self-hosted avançado com suporte a importação de extratos (CSV) via Data Importer. Acesso seguro através de túnel do Cloudflare em `https://firefly.exemplo.com`.

## Arquitetura

```
┌─ REDE LOCAL / EXTERNA ────────────────────────────────────────┐
│                                                               │
│  Dispositivo ──► https://firefly.exemplo.com                 │
│  ──► Cloudflare Edge (TLS) ──► Tunnel ──► localhost:8080      │
│  ──► Firefly App (App) ──► Banco de Dados MariaDB (DB)        │
│                                                               │
│  Importação de CSV ──► http://IP_DO_SERVIDOR:8081             │
│  ──► Data Importer ──► Firefly App (API)                      │
└───────────────────────────────────────────────────────────────┘
```

**Portas no host:**

| Porta Host | Porta Container | Uso                                         |
| :--------- | :-------------- | :------------------------------------------ |
| `8080/tcp` | `8080`          | App Principal (Web UI + API)                |
| `8081/tcp` | `8080`          | Data Importer (Conversão e Envio via API)   |

---

## 🛠️ Parte 1: Preparação do Host (Debian)

Execute todos os comandos no terminal SSH do servidor.

### 1.1. Criar diretórios de persistência

O Firefly precisa persistir o banco de dados e os anexos (uploads).

```bash
sudo mkdir -p /srv/firefly/db
sudo mkdir -p /srv/firefly/upload
```

### 1.2. Ajustar Permissões (Crítico)

O container do Firefly App roda internamente usando o usuário `www-data` (ID `33`). Para que o sistema consiga salvar os arquivos e exportações, ele precisa ser o dono da pasta de upload.

```bash
sudo chown -R 33:33 /srv/firefly/upload
```

### 1.3. Liberar Portas no Firewall (se UFW ativo)

```bash
# App principal
sudo ufw allow 8080/tcp

# Data Importer
sudo ufw allow 8081/tcp

sudo ufw reload
```

---

## 📦 Parte 2: Deploy via Portainer (Stack)

### 2.1. Criar a Stack

1. Acessar o Portainer → **Stacks** → **Add Stack**
2. **Nome:** `firefly`
3. Colar o conteúdo do arquivo [`assets/stack_firefly.yml`](./assets/stack_firefly.yml) no Editor Web.
4. Na aba **Environment variables**, adicione manualmente (Add environment variable) ou carregue do seu `.env` as seguintes chaves:
   - `FIREFLY_APP_KEY`: Senha mestra (string de 32 caracteres exatos, sem caracteres especiais).
   - `FIREFLY_DB_PASSWORD`: Senha para o banco de dados.
   - `FIREFLY_APP_TOKEN`: Pode deixar vazio no deploy inicial.
5. Clicar em **Deploy the stack**.

---

## ⚙️ Parte 3: Configuração Pós-Deploy

### 3.1. Ajustes no Cloudflare (Crítico)

> [!WARNING]
> O Firefly é muito sensível a proxies reversos e proteções HTTP. Faça a configuração abaixo no painel do Cloudflare para evitar falhas graves na interface, como o mascaramento do seu login.

No painel do Cloudflare:
1. Vá em **Scrape Shield** → **Email Address Obfuscation** e desative (**Off**). O Cloudflare ofusca emails como proteção anti-bot, o que quebra a interface do Firefly, substituindo seu email por `[email protected]`.

> [!NOTE]
> A variável `TRUSTED_PROXIES=**` já está definida na sua stack `assets/stack_firefly.yml`. Ela é obrigatória para resolver o erro "Could not delete" (falha de CSRF no Laravel ao usar túneis).

### 3.2. Gerar Token para o Data Importer

O `firefly-importer` acessa a API do app principal para realizar a inserção de dados em massa. Ele precisa de um *Personal Access Token*.

1. Acesse o Firefly (`http://192.168.x.x:8080` ou via Domínio) e crie sua conta admin.
2. Menu lateral → **Opções** → **Perfil**.
3. Aba **OAuth** → Seção **Personal Access Tokens**.
4. Clique em **Criar Novo Token**, nomeie como `Importer` e copie o código gigante.
5. Volte no **Portainer** → Stack `firefly` → **Editor**.
6. Insira o token copiado no valor da variável `FIREFLY_APP_TOKEN`.
7. Clique em **Update the stack**.

---

## 📥 Parte 4: Importação de Dados (Migração do Mobills)

A migração utiliza o Data Importer, acessível apenas localmente.

### 4.1. Conversão UTF-8

> [!IMPORTANT]
> A maioria dos apps financeiros, como o Mobills, exporta relatórios CSV em formato `UTF-16 LE`. O Firefly Data Importer **exige** UTF-8 e falhará miseravelmente se a conversão não for feita.

No Windows (PowerShell), rode o comando abaixo na pasta do relatório original para convertê-lo com segurança:

```powershell
Get-Content "RELATORIO_TRANSACOES.csv" -Encoding Unicode | Set-Content "RELATORIO_UTF8.csv" -Encoding UTF8
```

### 4.2. Cadastro Prévio de Contas

O Data Importer **não cria contas automaticamente**. 
Abra o CSV, verifique as contas financeiras presentes (ex: *Nubank, Carteira, Sicoob*) e crie cada uma manualmente no Firefly em **Contas** → **Contas de Ativo (Asset accounts)**.

### 4.3. Dividindo CSV Gigante (Evitando 504 Gateway Timeout)

Se o arquivo exportado passar de ~2.000 linhas, a interface web do importador sofrerá Timeout (504). A solução recomendada pela documentação oficial é fatiar o arquivo, mas mantendo a linha do cabeçalho em todas as partes.

Script PowerShell para automatizar a divisão (`RELATORIO_UTF8.csv`):

```powershell
$source = "RELATORIO_UTF8.csv"
$destDir = "split"
New-Item -ItemType Directory -Force -Path $destDir | Out-Null
$reader = New-Object System.IO.StreamReader($source, [System.Text.Encoding]::UTF8)
$header = $reader.ReadLine()
$chunkSize = 2000
$fileCount = 1
$lineCount = 0
$writer = $null

while ($null -ne ($line = $reader.ReadLine())) {
    if ($lineCount % $chunkSize -eq 0) {
        if ($null -ne $writer) { $writer.Close() }
        $destFile = Join-Path $destDir "RELATORIO_UTF8_part$fileCount.csv"
        $writer = New-Object System.IO.StreamWriter($destFile, $false, [System.Text.Encoding]::UTF8)
        $writer.WriteLine($header)
        $fileCount++
    }
    $writer.WriteLine($line)
    $lineCount++
}
if ($null -ne $writer) { $writer.Close() }
$reader.Close()
```

### 4.4. Importação Acelerada ("Skip form")

1. Acesse o importador: `http://192.168.x.x:8081`
2. Suba o primeiro lote (`part1.csv`) e faça o mapeamento visual das colunas (Data, Valor, Conta) e a ligação dos papéis (Account Mapping).
3. Na penúltima tela, antes do envio para a API, **baixe o arquivo de configuração (.json)** disponibilizado.
4. Processe a `part1.csv`.
5. Volte para o início (Start Over). Faça upload da `part2.csv` **junto com o arquivo .json baixado**.
6. Na seção inferior, marque a opção **Skip form: Yes** e confirme. O sistema usará o mapeamento prévio e enviará diretamente para a nuvem. Repita para as demais partes.

---

## ⚠️ Troubleshooting

### Aviso de "valor precisa ser maior do que zero"

Log exibe:
```text
Line #384: [a117]: transactions.0.amount: O valor precisa ser maior do que zero. (original value: "0.00")
```
**Causa:** O Mobills e outros apps aceitam transações zeradas (como rascunhos, estornos ou marcações). O Firefly exige que toda transação tenha um valor financeiro real.
**Fix:** Nenhuma ação necessária. O importador ignora a linha infratora com segurança e prossegue com sucesso para o restante do lote.

### Erro "Could not delete" ou Logout Aleatório

**Causa:** O mecanismo CSRF do Laravel está rejeitando pacotes HTTP por considerar a origem não-confiável.
**Fix:** Certifique-se de que a variável `TRUSTED_PROXIES=**` está presente no Portainer na stack do `firefly-app` e recarregue o container.

### Erro "There is no import job with identifier"

**Causa:** Ocorre após a tela de erro 504 no Data Importer. O tempo de execução excedeu o limite do PHP/Nginx e o container web perdeu o contexto temporário do processamento em andamento.
**Fix:** Aplique a solução descrita na etapa *4.3. Dividindo CSV Gigante*.

---

## 🌐 Acessos

| Recurso                 | URL                                   |
| :---------------------- | :------------------------------------ |
| **Web UI (App)**        | `https://firefly.exemplo.com`        |
| **Local (App)**         | `http://IP_DO_SERVIDOR:8080`          |
| **Data Importer**       | `http://IP_DO_SERVIDOR:8081`          |
| **Portainer**           | Stack `firefly`                       |

---

## 📚 Referências

- [Firefly III Documentação Oficial](https://docs.firefly-iii.org/)
- [Firefly III Data Importer Oficial](https://github.com/firefly-iii/data-importer)
- [Configurando Trusted Proxies no Laravel](https://laravel.com/docs/11.x/requests#configuring-trusted-proxies)


