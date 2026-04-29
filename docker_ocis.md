# ☁️ ownCloud oCIS no Home Lab (Orange Pi 5 + Cloudflare Tunnel)

Cloud storage pessoal com sync de arquivos, compartilhamento e acesso via apps mobile. Acesso externo seguro via Cloudflare Tunnel em `https://drive.selflabs.org`.

## Arquitetura

```
┌─ REDE LOCAL / EXTERNA ────────────────────────────────────────┐
│                                                               │
│  Dispositivo ──► https://drive.selflabs.org                   │
│  ──► Cloudflare Edge (TLS) ──► Tunnel ──► localhost:9200      │
│  ──► oCIS                                                     │
└───────────────────────────────────────────────────────────────┘
```

> **Por design**, o oCIS não funciona acessado por IP direto (`192.168.68.9:9200`). O OIDC requer que a URL de acesso seja exatamente igual ao `OCIS_URL`. O acesso (mesmo local) deve ser feito sempre via domínio para garantir o HTTPS e a autenticação correta.

**Porta no host:**

| Porta Host   | Porta Container | Uso                          |
| :----------- | :-------------- | :--------------------------- |
| `9200/tcp`   | `9200`          | Web UI + API (WebDAV, OIDC)  |

> A porta `9200` é a única necessária. O oCIS é um binário Go que inclui tudo: web server, autenticação (OIDC), storage, search engine. Sem PHP, sem Apache, sem banco de dados externo.

---

## 🛠️ Parte 1: Preparação do Host (Debian)

Execute todos os comandos no terminal SSH do servidor.

### 1.1. Criar diretórios persistentes

```bash
# Criar diretórios para config e dados
sudo mkdir -p /srv/ocis/config /srv/ocis/data

# oCIS roda como UID 1000 dentro do container
sudo chown -Rfv 1000:1000 /srv/ocis
```

### 1.2. Verificar porta livre

```bash
# Confirmar que a porta 9200 não está em uso
sudo ss -tlnp | grep 9200
```

Se não retornar nada, está livre.

---

## 📦 Parte 2: Deploy via Portainer (Stack)

### 2.1. Criar a Stack

1. Acessar o Portainer → **Stacks** → **Add Stack**
2. Nome: `ocis`
3. Colar o conteúdo do arquivo [`assets/stack_ocis.yml`](./assets/stack_ocis.yml)
4. Na seção **Environment variables**, adicionar:

| Variável | Valor |
|:---------|:------|
| `OCIS_ADMIN_PASSWORD` | Sua senha (mín. 8 chars: maiúscula + minúscula + número + especial) |

5. Clicar em **Deploy the stack**

### 2.2. O que acontece no primeiro boot

O `entrypoint` da stack executa:

```bash
ocis init || true; ocis server
```

1. `ocis init` — Gera o `ocis.yaml` com JWT secrets, chaves de criptografia e configurações internas. A env var `OCIS_INSECURE=true` responde automaticamente o prompt interativo
2. `|| true` — Se o `init` já rodou antes (config existe), ignora o erro e segue
3. `ocis server` — Inicia todos os serviços

> Em deploys subsequentes, o `init` é pulado automaticamente porque o `ocis.yaml` já existe no volume persistente.

### 2.3. Variáveis de ambiente explicadas

| Variável | Valor | Descrição |
|:---------|:------|:----------|
| `OCIS_URL` | `https://drive.selflabs.org` | URL pública. Obrigatória para OIDC funcionar |
| `PROXY_TLS` | `false` | Desabilita TLS no container (Cloudflare cuida) |
| `OCIS_INSECURE` | `true` | Desativa validação de cert interno (necessário com `PROXY_TLS=false`) |
| `PROXY_HTTP_ADDR` | `0.0.0.0:9200` | Escuta em todas as interfaces |
| `IDM_ADMIN_PASSWORD` | `${OCIS_ADMIN_PASSWORD}` | Senha admin vinda do .env |
| `OCIS_LOG_LEVEL` | `warn` | `info` para debug, `warn` para produção |

---

## 🌐 Parte 3: Cloudflare Tunnel

### 3.1. Configurar Public Hostname no Tunnel

No painel **Cloudflare Zero Trust** → **Networks** → **Tunnels**:

1. Selecionar o tunnel existente
2. Adicionar **Public Hostname**:
   - **Subdomain:** `drive`
   - **Domain:** `selflabs.org`
   - **Type:** `HTTP`
   - **URL:** `localhost:9200`

> Mesmo fluxo já feito para o `adguard.selflabs.org`. O registro CNAME `drive.selflabs.org` é criado automaticamente no Cloudflare DNS.

### 3.2. Acesso Local

O oCIS não funciona acessado por IP direto — o OIDC exige que a URL seja idêntica ao `OCIS_URL`. Nenhuma configuração extra é necessária: os dispositivos da rede local acessam `https://drive.selflabs.org` normalmente pelo Cloudflare Tunnel.

> [!WARNING]
> **Não use DNS rewrite no AdGuard** apontando `drive.selflabs.org` para `192.168.68.9`. Isso faz o browser tentar `https://192.168.68.9:443`, mas o oCIS escuta apenas na porta `9200`. O resultado é que **tanto o acesso local quanto o externo param de funcionar**.

---

## 📱 Parte 4: Apps Mobile e Desktop

### Clientes Oficiais

| Plataforma | App | Link |
|:-----------|:----|:-----|
| **iOS** | ownCloud | [App Store](https://apps.apple.com/app/owncloud/id1359583808) |
| **Android** | ownCloud | [Google Play](https://play.google.com/store/apps/details?id=com.owncloud.android) |
| **Windows** | ownCloud Desktop | [Download](https://owncloud.com/desktop-app/) |
| **macOS** | ownCloud Desktop | [Download](https://owncloud.com/desktop-app/) |

### Configuração nos Apps

1. Abrir o app → **Adicionar conta**
2. URL do servidor: `https://drive.selflabs.org`
3. Login: `admin` + senha definida no deploy
4. Selecionar pastas para sync

---

## ✅ Parte 5: Validação

### No Servidor (Debian)

```bash
# 1. Verificar se o container está rodando
docker ps | grep ocis

# 2. Testar OIDC discovery (deve retornar JSON)
curl -s http://localhost:9200/.well-known/openid-configuration | head -5

# 3. Verificar logs (procurar erros)
docker logs ocis --tail 50
```

### Acesso Local

Com o DNS rewrite configurado no AdGuard (Parte 3.2), o acesso local é feito pelo mesmo domínio:

1. Abrir `https://drive.selflabs.org` na rede local
2. Login com `admin` + senha

> Acesso por IP (`http://192.168.68.9:9200`) retorna "Configuração ausente ou inválida" — isso é comportamento esperado e não é um bug. O OIDC exige que a URL seja idêntica ao `OCIS_URL`.

### Acesso Externo

1. Abrir `https://drive.selflabs.org`
2. Login com `admin` + senha
3. Upload de arquivo de teste
4. Verificar no app mobile que o arquivo aparece

---

## ⚠️ Troubleshooting

### Login redireciona para URL errada

O `OCIS_URL` está diferente do domínio configurado no Cloudflare. Verificar:

```bash
docker exec ocis env | grep OCIS_URL
```

Deve retornar `OCIS_URL=https://drive.selflabs.org`.

### Erro 502 Bad Gateway no Cloudflare

O tunnel não consegue alcançar o oCIS. Verificar:

```bash
# Container rodando?
docker ps | grep ocis

# Porta respondendo?
curl -s http://localhost:9200
```

### Permissão negada nos arquivos

```bash
# Reajustar permissões
sudo chown -Rfv 1000:1000 /srv/ocis
```

### Reset de senha do admin

```bash
# Parar o container
docker stop ocis

# Rodar reset
docker run --rm -it \
  --mount type=bind,source=/srv/ocis/config,target=/etc/ocis \
  --mount type=bind,source=/srv/ocis/data,target=/var/lib/ocis \
  -e IDM_ADMIN_PASSWORD="NovaSenhaAqui123!" \
  owncloud/ocis idm resetpassword
```

---

## 🌐 Acessos

| Recurso | URL |
|:--------|:----|
| **Web UI** | `https://drive.selflabs.org` |
| **WebDAV** | `https://drive.selflabs.org/dav/files/<username>/` |
| **Portainer** | Stack `ocis` |

---

## 📚 Referências

- [Documentação oficial oCIS](https://doc.owncloud.com/ocis/)
- [oCIS Docker Guide](https://owncloud.dev/ocis/guides/ocis-local-docker/)
- [oCIS GitHub](https://github.com/owncloud/ocis)
- [ownCloud Mobile Apps](https://owncloud.com/mobile-apps/)
