# 🛡️ AdGuard Home no Home Lab (Orange Pi 5 + Cloudflare Tunnel)

DNS server com bloqueio de ads e trackers para toda a rede, com suporte a DNS-over-HTTPS (DoH) via Cloudflare Tunnel. Funciona tanto na rede local (DNS plain na porta 53) quanto externamente (DoH via `https://adguard.selflabs.org/dns-query`).

## Arquitetura

```
┌─ REDE LOCAL ──────────────────────────────────────────────┐
│                                                           │
│  Roteador (Deco S7) ──► DNS :53 ──► AdGuard (Orange Pi)   │
│  Todos os dispositivos herdam via DHCP                    │
└───────────────────────────────────────────────────────────┘

┌─ EXTERNO (iPhone 4G / Wi-Fi externo) ─────────────────────┐
│                                                           │
│  Perfil .mobileconfig ──► DoH                             │
│  ──► https://adguard.selflabs.org/dns-query               │
│  ──► Cloudflare Edge (TLS termination)                    │
│  ──► cloudflared tunnel ──► http://localhost:8084         │
│  ──► AdGuard Home                                         │
└───────────────────────────────────────────────────────────┘
```

**Portas no host:**

| Porta Host   | Porta Container | Uso                               |
| :----------- | :-------------- | :-------------------------------- |
| `53/tcp+udp` | `53`            | DNS plain (rede local)            |
| `8084/tcp`   | `80`            | Painel Admin + endpoint DoH       |
| `3004/tcp`   | `3000`          | Setup Wizard (só na primeira vez) |

> As portas do **host** (`53`, `8084`, `3004`) podem ser alteradas no `stack_adguard.yml` se já estiverem em uso. As portas do **container** (lado direito) são fixas e não devem ser modificadas.

---

## 🛠️ Parte 1: Preparação do Host (Debian)

Execute todos os comandos no terminal SSH do servidor.

### 1.1. Desabilitar DNSStubListener do `systemd-resolved`

O `systemd-resolved` escuta na porta 53 no loopback. Precisamos desabilitá-lo para liberar a porta para o AdGuard.

```bash
# Criar override de configuração
sudo mkdir -p /etc/systemd/resolved.conf.d
sudo tee /etc/systemd/resolved.conf.d/adguardhome.conf > /dev/null <<EOF
[Resolve]
DNS=127.0.0.1
DNSStubListener=no
EOF

# Reconfigurar o resolv.conf para usar o resolved sem stub
sudo mv /etc/resolv.conf /etc/resolv.conf.backup
sudo ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf

# Reiniciar o serviço
sudo systemctl reload-or-restart systemd-resolved
```

Verificar que a porta 53 ficou livre:

```bash
sudo ss -lnp | grep ':53 '
# Não deve aparecer nenhuma linha com 0.0.0.0 ou escuta pública
```

### 📂 1.2. Criar Pastas de Persistência

```bash
sudo mkdir -p /srv/adguard/work
sudo mkdir -p /srv/adguard/conf
```

### 🛡️ 1.3. Liberar Portas no Firewall (se UFW ativo)

```bash
# DNS
sudo ufw allow 53/tcp
sudo ufw allow 53/udp

# Painel Admin
sudo ufw allow 8084/tcp

# Setup Wizard (temporário, só na primeira vez)
sudo ufw allow 3004/tcp

sudo ufw reload
sudo ufw status
```

---

## 📦 Parte 2: Deploy via Portainer

### 2.1. Criar a Stack

No Portainer: **Stacks** > **+ Add Stack**

- **Nome:** `adguard`
- **Editor Web:** Copie o conteúdo do arquivo [`assets/stack_adguard.yml`](./assets/stack_adguard.yml) e cole no editor.

Clique em **Deploy the stack**.

---

## ⚙️ Parte 3: Setup Inicial do AdGuard Home

### 3.1. Acessar o Wizard

Abra no navegador: `http://IP_DA_ORANGEPI:3004`

### 3.2. Configurar no Wizard

- **Admin Web Interface:** Porta `80`, escutar em `0.0.0.0`
  > O Docker mapeia isso para `8084` no host — não precisa se preocupar com essa diferença.
- **DNS Server:** Porta `53`, escutar em `0.0.0.0`
- Criar usuário e senha admin

### 3.3. Finalizar

Após o wizard, o painel fica disponível em: `http://IP_DA_ORANGEPI:8084`

---

## 🔐 Parte 4: Habilitar DoH sem TLS (Cloudflare Tunnel)

O AdGuard por padrão só serve o endpoint `/dns-query` quando TLS está configurado nele. Como o Cloudflare Tunnel gerencia o TLS, precisamos ativar o modo "unencrypted DoH" via arquivo de config.

### 4.1. Parar o container e editar o YAML

```bash
docker stop adguardhome
sudo nano /srv/adguard/conf/AdGuardHome.yaml
```

### 4.2. Ajustar a seção `http:` (Habilitar DoH sem criptografia)

Nas versões mais recentes (schema 34+), o AdGuard moveu essa configuração para o topo do arquivo, no bloco `http`.
Procure por `doh:` dentro de `http:` e altere `insecure_enabled` para `true`:

```yaml
http:
  # ...
  doh:
    routes:
      - GET /dns-query
      # ...
    insecure_enabled: true
```

### 4.3. Ajustar a seção `dns:` (adicionar trusted_proxies)

Isso garante que o AdGuard identifique o IP real dos clientes via headers do Cloudflare.

```yaml
dns:
  # ... (manter as configurações existentes e adicionar) ...
  trusted_proxies:
    - 127.0.0.0/8
    - ::1/128
    - 172.16.0.0/12
```

### 4.4. Reiniciar o container

```bash
docker start adguardhome
```

### 4.5. Validar o DoH local

```bash
curl -s "http://localhost:8084/dns-query"
```

Se retornar `Bad Request`, parabéns! 🎉 O DoH está funcionando.
O fato do AdGuard Home responder `Bad Request` prova que o endpoint está ativo e pronto para receber o tráfego da Cloudflare!

---

## 🌐 Parte 5: Configurar o Cloudflare Tunnel

No dashboard do Cloudflare Zero Trust, no tunnel existente (`cloudflared`):

1. Ir em **Networks** > **Tunnels** > selecionar seu tunnel > **Edit**
2. Aba **Public Hostname** > **+ Add a public hostname**:
   - **Subdomain:** `adguard`
   - **Domain:** `selflabs.org`
   - **Service:** `http://localhost:8084`
3. Salvar

O Cloudflare criará o registro DNS automaticamente.

**Resultado:** `https://adguard.selflabs.org` → Painel Admin + endpoint DoH.

---

## 📡 Parte 6: Configurar o Roteador (Deco S7)

Para que TODOS os dispositivos da rede usem o AdGuard automaticamente:

1. Abrir o app **Deco** no celular
2. Ir em **Mais** > **Avançado** > **LAN** (ou **IPv4**)
3. Em **DNS Address**, mudar de Automático para Manual
4. **DNS Primário:** IP da Orange Pi (ex: `192.168.68.9`)
5. **DNS Secundário:** `1.1.1.1` _(fallback caso a Orange Pi caia)_
6. Salvar e aguardar

Os dispositivos passam a usar o AdGuard ao renovarem o DHCP (pode forçar desconectando e reconectando ao Wi-Fi).

---

## 📱 Parte 7: Clientes DNS Externos

Para usar o AdGuard fora de casa, configure o DoH nos dispositivos conforme abaixo.

### 🍎 7.1. iOS — Perfil .mobileconfig

Para o iPhone usar DoH em **qualquer rede** (local, 4G, Wi-Fi externo):

Nossa arquitetura terceiriza o TLS para a Cloudflare. Por causa disso, a interface do AdGuard oculta o gerador automático de perfis da Apple. Você deve usar o perfil pronto fornecido neste repositório:

1. Acesse **[cateim.github.io/DIY](https://cateim.github.io/DIY/)** no seu iPhone.
2. Abra o link **obrigatoriamente pelo Safari** e clique em "Instalar Perfil DNS" (outros navegadores farão o download de um arquivo .txt e não acionarão a instalação).
3. Vá em **Ajustes** (Settings) > vai aparecer um aviso "Perfil Baixado" no topo > toque nele e instale.
4. Vá em **Ajustes** > **Geral** > **VPN e Gerenciamento de Dispositivo** > **DNS** e selecione o perfil do AdGuard.

> **Nota sobre redes locais:** Com o perfil ativo, o iPhone usará sempre o DoH externo (`adguard.selflabs.org`), mesmo dentro de casa. O AdGuard vai filtrar normalmente — não é um problema, só uma curiosidade.

> **Nota sobre assinatura:** O perfil é assinado automaticamente pelo GitHub Actions com um certificado self-signed na hora do deploy. O iOS vai exibir "Assinado por Self-Labs DNS Profile" (emissor não verificado pela Apple — esperado para certificados self-signed). Para regenerar o certificado de assinatura, veja a seção [Gerando o Certificado de Assinatura](#gerando-o-certificado-de-assinatura).

---

### 🔐 Gerando o Certificado de Assinatura

O certificado é gerado uma única vez e armazenado como **GitHub Secret** no repositório. O Actions usa esses secrets para assinar o perfil a cada deploy.

**1. Gerar o certificado (Git Bash no Windows):**

```bash
openssl req -x509 -newkey rsa:4096 -keyout sign.key -out sign.crt \
  -days 3650 -nodes -subj "/CN=Self-Labs DNS Profile/O=Self-Labs/C=BR"
```

**2. Adicionar ao GitHub:**

Acesse o repositório → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**:

| Nome       | Conteúdo                       |
| ---------- | ------------------------------ |
| `SIGN_KEY` | conteúdo do arquivo `sign.key` |
| `SIGN_CRT` | conteúdo do arquivo `sign.crt` |

**3. Apagar os arquivos locais** — nunca commite a chave privada:

```bash
rm sign.key sign.crt
```

Após adicionar os secrets, qualquer disparo do workflow irá assinar o perfil automaticamente antes do deploy.

---

### 🤖 7.2. Android — DoH via App

O Android nativo usa DNS-over-TLS (porta 853), que não está mapeada no nosso setup. A alternativa é usar um app que suporte DoH com servidor customizado.

**Opção A — App AdGuard para Android (recomendado)**

1. Instalar o **AdGuard** da Play Store (versão gratuita ou paga)
2. Ir em **Configurações** > **DNS** > **Servidor DNS**
3. Selecionar **Adicionar servidor DNS personalizado**
4. Preencher:
   - **Nome:** `Self-Labs AdGuard`
   - **URL DoH:** `https://adguard.selflabs.org/dns-query`
5. Ativar o servidor criado

**Opção B — App Intra (Google/Jigsaw, gratuito e leve)**

1. Instalar o **Intra** da Play Store
2. Abrir o app e ir em **Configurações** > **Servidor DNS-over-HTTPS**
3. Selecionar **Personalizado** e preencher:
   - `https://adguard.selflabs.org/dns-query`
4. Voltar e ativar o Intra

> O Intra cria uma VPN local no dispositivo para interceptar as consultas DNS e redirecioná-las via DoH. É transparente para os apps.

---

## 🔒 Parte 8: Proteção do Painel Admin (Cloudflare Access)

Com o tunnel ativo, `https://adguard.selflabs.org` expõe o painel admin publicamente. O Cloudflare Access permite exigir autenticação para acessar o painel enquanto mantém o endpoint `/dns-query` público (sem bloqueio).

### 8.1. Criar a Aplicação do DNS (Liberar `/dns-query`)

Como o Cloudflare não permite mais usar `Path` dentro das regras de acesso, precisamos criar **duas aplicações separadas**.

1. Acessar [Cloudflare One](https://dash.cloudflare.com/one)
2. Ir em **Access controls** > **Applications** > **+ Create new application**
3. Selecionar **Self-hosted and private**
4. Em **Destinations / Public hostnames**, preencha:
   - **Subdomain:** `adguard`
   - **Domain:** `selflabs.org`
   - **Path:** `/dns-query`
5. Role até **Access policies** e clique em **Create new policy**:
   - **Policy Name:** `Allow DNS Query`
   - **Action:** `Bypass`
   - Em **Policy rules > Include > Selector is...**, escolha `Everyone`
6. Role até o final da página e salve a aplicação (botão **Save** ou **Create**).

### 8.2. Criar a Aplicação do Painel (Exigir Autenticação)

1. Vá novamente em **Access controls** > **Applications** e crie uma nova aplicação **Self-hosted and private**.
2. Em **Destinations / Public hostnames**, preencha:
   - **Subdomain:** `adguard`
   - **Domain:** `selflabs.org`
   - **Path:** *(deixe totalmente em branco)*
3. Role até **Access policies** e clique em **Create new policy**:
   - **Policy Name:** `Admin Access`
   - **Action:** `Allow`
   - Em **Policy rules > Include > Selector is...**, escolha `Emails` e digite o seu e-mail de acesso (ex: `seu@email.com`).
4. Em **Authentication** (na mesma página):
   - Certifique-se de que um provedor de identidade (como **One-time PIN**) está habilitado.
5. Role até o final e salve a aplicação.

> **Nota:** A Cloudflare processa a aplicação mais específica primeiro. Portanto, o acesso ao `/dns-query` cairá na aplicação de Bypass, e qualquer outro acesso ao subdomínio `adguard` exigirá login.

**Resultado:**

- `https://adguard.selflabs.org/dns-query` → Acesso público (DoH funciona)
- `https://adguard.selflabs.org` → Exige login por e-mail OTP

---

## ✅ Parte 9: Validação Final

### No Servidor (Debian)

```bash
# 1. Testar DNS plain — deve retornar o IP de google.com
dig @IP_DA_ORANGEPI google.com

# 2. Testar DoH local — deve retornar "Bad Request" (confirma que o endpoint está ativo)
curl -s "http://localhost:8084/dns-query"

# 3. Testar DoH externo (após configurar o tunnel) — deve retornar "Bad Request"
curl -s "https://adguard.selflabs.org/dns-query"
```

> **Nota:** O `Bad Request` **é o resultado esperado** nos testes DoH (#2 e #3). O AdGuard rejeita a requisição por estar malformada (sem parâmetros DNS válidos), mas o fato de responder prova que o endpoint está ativo e acessível. O formato JSON (`application/dns-json`) não é suportado nesta configuração.

### No Painel do AdGuard

- **Dashboard:** Verificar se as queries aparecem no **Query Log**
- **Filtros:** Confirmar que as listas de bloqueio estão ativas (em **Filters**)
- **Clientes:** Após configurar o Deco S7, os IPs dos dispositivos devem aparecer na aba **Top Clients**

### Nos Dispositivos Externos

1. **iOS:** Instalar o perfil `.mobileconfig` e acessar um site com anúncios (ex: `uol.com.br`)
2. **Android:** Ativar o app DoH e acessar um site com anúncios
3. Verificar no **Query Log** do AdGuard que as queries aparecem e os domínios bloqueados estão marcados
4. Testar que o painel admin (`https://adguard.selflabs.org`) exige login, mas `https://adguard.selflabs.org/dns-query` responde sem autenticação

### ⚠️ Troubleshooting: Filtros não funcionam no Desktop

Se celulares na mesma rede Wi-Fi estão sendo filtrados normalmente, mas o desktop ignora os bloqueios, a causa mais comum é **DNS fixo configurado manualmente no adaptador de rede**, sobrescrevendo o DHCP do roteador.

**Como verificar (Windows):**

```powershell
ipconfig /all
```

No adaptador Wi-Fi ativo, se aparecer:
```
DHCP Habilitado: Não
Servidores DNS: 8.8.8.8 / 1.1.1.1
```

O desktop está ignorando o AdGuard completamente.

**Correção:**

`Configurações > Rede e Internet > Wi-Fi > Propriedades de hardware > Editar atribuição de IP`

Mude de **Manual** para **Automático (DHCP)** e após salvar, execute:

```powershell
ipconfig /flushdns
```

O desktop passará a receber o IP do AdGuard Home via DHCP, igual aos demais dispositivos da rede.

### ⚠️ Troubleshooting: Aviso de permissão no diretório work

Log exibe na inicialização:
```
permcheck: warning: found unexpected permissions path=/opt/adguardhome/work perm=0755 want=0700
```

**Fix** — Rodar no Debian:
```bash
chmod 700 /srv/adguard/work
```

Reiniciar o container após o comando. O aviso desaparece nos logs seguintes.

### ⚠️ Troubleshooting: Upstream DNS falhando (Quad9)

Log exibe repetidamente:
```
dnsproxy: exchange failed upstream=https://dns10.quad9.net:443/dns-query
err="connection reset by peer" / "unexpected EOF"
```

O container não consegue alcançar o Quad9 via DoH. Isso causa resolução DNS instável com retries.

**Fix** — No painel AdGuard, **Configurações > Configurações de DNS > Servidores DNS primário**, substituir por:
```
https://cloudflare-dns.com/dns-query
https://dns.google/dns-query
```

Clicar em **Testar DNS primário** para validar e depois em **Aplicar**.

---

## 🌐 Acessos

| Serviço                | Endereço                                 |
| :--------------------- | :--------------------------------------- |
| Painel Admin (local)   | `http://IP_DA_ORANGEPI:8084`             |
| Painel Admin (externo) | `https://adguard.selflabs.org`           |
| DoH endpoint           | `https://adguard.selflabs.org/dns-query` |
