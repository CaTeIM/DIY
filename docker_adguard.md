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

---

## Parte 1: Preparação do Host (Debian) 🛠️

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

### 1.2. Criar Pastas de Persistência 📂

```bash
sudo mkdir -p /srv/adguard/work
sudo mkdir -p /srv/adguard/conf
```

### 1.3. Liberar Portas no Firewall (se UFW ativo) 🛡️

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

## Parte 2: Deploy via Portainer 📦

### 2.1. Criar a Stack

No Portainer: **Stacks** > **+ Add Stack**

- **Nome:** `adguard`
- **Editor Web:** Copie o conteúdo do arquivo [`assets/stack_adguard.yml`](./assets/stack_adguard.yml) e cole no editor.

Clique em **Deploy the stack**.

---

## Parte 3: Setup Inicial do AdGuard Home ⚙️

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

## Parte 4: Habilitar DoH sem TLS (Cloudflare Tunnel) 🔐

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

## Parte 5: Configurar o Cloudflare Tunnel 🌐

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

## Parte 6: Configurar o Roteador (Deco S7) 📡

Para que TODOS os dispositivos da rede usem o AdGuard automaticamente:

1. Abrir o app **Deco** no celular
2. Ir em **Mais** > **Avançado** > **LAN** (ou **IPv4**)
3. Em **DNS Address**, mudar de Automático para Manual
4. **DNS Primário:** IP da Orange Pi (ex: `192.168.68.9`)
5. **DNS Secundário:** `1.1.1.1` _(fallback caso a Orange Pi caia)_
6. Salvar e aguardar

Os dispositivos passam a usar o AdGuard ao renovarem o DHCP (pode forçar desconectando e reconectando ao Wi-Fi).

---

## Parte 7: Clientes DNS Externos 📱

Para usar o AdGuard fora de casa, configure o DoH nos dispositivos conforme abaixo.

### 7.1. iOS — Perfil .mobileconfig

Para o iPhone usar DoH em **qualquer rede** (local, 4G, Wi-Fi externo):

Nossa arquitetura terceiriza o TLS para a Cloudflare. Por causa disso, a interface do AdGuard oculta o gerador automático de perfis da Apple. Você deve usar o perfil pronto fornecido neste repositório:

1. Acesse **[cateim.github.io/DIY](https://cateim.github.io/DIY/)** no seu iPhone.
2. Abra o link **obrigatoriamente pelo Safari** e clique em "Instalar Perfil DNS" (outros navegadores farão o download de um arquivo .txt e não acionarão a instalação).
3. Vá em **Ajustes** (Settings) > vai aparecer um aviso "Perfil Baixado" no topo > toque nele e instale.
4. Vá em **Ajustes** > **Geral** > **VPN e Gerenciamento de Dispositivo** > **DNS** e selecione o perfil do AdGuard.

> **Nota sobre redes locais:** Com o perfil ativo, o iPhone usará sempre o DoH externo (`adguard.selflabs.org`), mesmo dentro de casa. O AdGuard vai filtrar normalmente — não é um problema, só uma curiosidade.

> **Nota sobre assinatura:** O perfil é assinado automaticamente pelo GitHub Actions com um certificado self-signed na hora do deploy. O iOS vai exibir "Assinado por Self-Labs DNS Profile" (emissor não verificado pela Apple — esperado para certificados self-signed). Para regenerar o certificado de assinatura, veja a seção [Gerando o Certificado de Assinatura](#gerando-o-certificado-de-assinatura).

---

### Gerando o Certificado de Assinatura

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

### 7.2. Android — DoH via App

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

## Parte 8: Proteção do Painel Admin (Cloudflare Access) 🔒

Com o tunnel ativo, `https://adguard.selflabs.org` expõe o painel admin publicamente. O Cloudflare Access permite exigir autenticação para acessar o painel enquanto mantém o endpoint `/dns-query` público (sem bloqueio).

### 8.1. Criar a Aplicação no Zero Trust

1. Acessar [Cloudflare Zero Trust](https://dash.cloudflare.com/one)
2. Ir em **Access** > **Applications** > **+ Add an Application**
3. Selecionar **Self-hosted**
4. Preencher:
   - **Application name:** `AdGuard Home`
   - **Session Duration:** `24 hours` (ou conforme preferir)
   - **Application domain:** `adguard.selflabs.org`
5. Avançar para **Policies**

### 8.2. Configurar as Políticas

Precisamos de **duas políticas** — uma para liberar o endpoint DoH sem autenticação, e outra para exigir login no restante.

**Política 1 — Bypass (liberar `/dns-query`)**

- **Policy name:** `Allow DNS Query`
- **Action:** `Bypass`
- **Rules:** Em **Include**, selecionar **Path** e preencher `/dns-query`

**Política 2 — Allow (proteger o painel)**

- **Policy name:** `Admin Access`
- **Action:** `Allow`
- **Rules:** Em **Include**, selecionar **Emails** e adicionar seu e-mail
  > Ou usar **Email domain** com `selflabs.org` se preferir.

> **Ordem importa:** A política de Bypass deve ficar **acima** da política Allow na lista. O Cloudflare avalia as políticas de cima para baixo.

### 8.3. Método de Autenticação

1. Ainda na configuração da aplicação, ir em **Authentication**
2. Em **Login methods**, confirmar que **One-time PIN** está habilitado
   - Isso permite login por OTP enviado ao e-mail, sem precisar configurar nenhum IdP externo
3. Finalizar com **Save**

**Resultado:**

- `https://adguard.selflabs.org/dns-query` → Acesso público (DoH funciona)
- `https://adguard.selflabs.org` → Exige login por e-mail OTP

---

## Parte 9: Validação Final ✅

### No Servidor (Debian)

```bash
# 1. Testar DNS plain
dig @IP_DA_ORANGEPI google.com

# 2. Testar DoH local
curl -s -H "accept: application/dns-json" \
  "http://localhost:8084/dns-query?name=google.com&type=A"

# 3. Testar DoH externo (após configurar o tunnel)
curl -s -H "accept: application/dns-json" \
  "https://adguard.selflabs.org/dns-query?name=google.com&type=A"
```

### No Painel do AdGuard

- **Dashboard:** Verificar se as queries aparecem no **Query Log**
- **Filtros:** Confirmar que as listas de bloqueio estão ativas (em **Filters**)
- **Clientes:** Após configurar o Deco S7, os IPs dos dispositivos devem aparecer na aba **Top Clients**

### Nos Dispositivos Externos

1. **iOS:** Instalar o perfil `.mobileconfig` e acessar um site com anúncios (ex: `uol.com.br`)
2. **Android:** Ativar o app DoH e acessar um site com anúncios
3. Verificar no **Query Log** do AdGuard que as queries aparecem e os domínios bloqueados estão marcados
4. Testar que o painel admin (`https://adguard.selflabs.org`) exige login, mas `https://adguard.selflabs.org/dns-query` responde sem autenticação

---

## Acessos 🌐

| Serviço                | Endereço                                 |
| :--------------------- | :--------------------------------------- |
| Painel Admin (local)   | `http://IP_DA_ORANGEPI:8084`             |
| Painel Admin (externo) | `https://adguard.selflabs.org`           |
| DoH endpoint           | `https://adguard.selflabs.org/dns-query` |
