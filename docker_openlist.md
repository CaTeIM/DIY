# 📂 OpenList no Home Lab

File manager self-hosted que serve arquivos existentes do HD diretamente na interface web, sem importação ou banco de índice. Acesso externo seguro via Cloudflare Tunnel em `https://files.selflabs.org`.

> [!NOTE]
> Usamos o **OpenList** (`openlistteam/openlist`), fork comunitário do AList original. O projeto original (`xhofe/alist`) foi vendido em 2025 e recebeu telemetria oculta não declarada. O OpenList é um drop-in replacement sem esse problema.

## Arquitetura

```
┌─ REDE LOCAL / EXTERNA ────────────────────────────────────────┐
│                                                               │
│  Dispositivo ──► https://files.selflabs.org                   │
│  ──► Cloudflare Edge (TLS) ──► Tunnel ──► localhost:5244      │
│  ──► OpenList ──► /srv/midia (HD 1TB)                         │
└───────────────────────────────────────────────────────────────┘
```

> **Diferencial do OpenList:** os arquivos em `/srv/midia` aparecem imediatamente na interface, com a estrutura de pastas original preservada. Não há processo de importação, não há reindexação e **nenhum arquivo da sua pasta é modificado**.

**Portas no host:**

| Porta Host | Porta Container | Uso                                                   |
| :--------- | :-------------- | :---------------------------------------------------- |
| `5244/tcp` | `5244`          | Web UI + WebDAV + API (HTTP)                          |
| `5245/tcp` | `5245`          | HTTPS interno (opcional, se TLS for ativado no painel) |

---

## 🛠️ Parte 1: Preparação do Host (Debian)

Execute todos os comandos no terminal SSH do servidor.

### 1.1. Criar diretório de configuração

```bash
# Apenas a config precisa de pasta dedicada — dados ficam no HD existente
sudo mkdir -p /srv/openlist/config
```

> O diretório `/srv/midia` já existe com seus arquivos. Nenhuma alteração nele é necessária.

### 1.2. Verificar portas livres

```bash
# Confirmar que as portas não estão em uso
sudo ss -tlnp | grep -E "5244|5245"
```

Se não retornar nada, estão livres.

---

## 📦 Parte 2: Deploy via Portainer (Stack)

### 2.1. Criar a Stack

1. Acessar o Portainer → **Stacks** → **Add Stack**
2. Nome: `openlist`
3. Colar o conteúdo do arquivo [`assets/stack_openlist.yml`](./assets/stack_openlist.yml)
4. Clicar em **Deploy the stack**

### 2.2. Recuperar a senha do admin

Na primeira inicialização, o OpenList gera uma senha aleatória. Pegue ela nos logs:

```bash
docker logs openlist 2>&1 | grep -i password
```

O output será algo como:
```
INFO  Successfully created the admin user and the initial password is: xxxxxxxx
```

> Anote essa senha. Você pode alterá-la depois pelo painel.

### 2.3. Adicionar o storage local (/srv/midia)

1. Acessar `http://192.168.68.9:5244`
2. Entrar com `admin` + senha dos logs
3. Menu lateral → **Storages** → **Add**
4. Preencher conforme a tabela abaixo:

| Campo | Valor | Observação |
| :---- | :---- | :--------- |
| **Driver** | `Local` | Tipo de storage |
| **Mount Path** | `/midia` | Caminho virtual no OpenList (aparece na URL) |
| **WebDAV Policy** | `Native proxy` | Correto para uso com Cloudflare Tunnel |
| **Root folder path** | `/midia` | ⚠️ **Crítico** — caminho real dentro do container. Deixar `/` expõe o filesystem inteiro. |
| **Disable index** | OFF | Mantém a busca funcionando |
| **Enable sign** | OFF | Sem token extra — login já protege o acesso |
| **Directory size** | OFF | Calcular tamanho de pastas é pesado no Orange Pi |
| **Thumbnail** | ON | Gera previews de imagem/vídeo |
| **Thumb cache folder** | *(vazio)* | Usa `/opt/openlist/data` por padrão — já é volume persistente. Não preencher para não misturar cache com mídias. |
| **Show hidden** | ON | Exibe arquivos e pastas ocultos (`.` prefixados) |
| **Recycle bin path** | `delete permanently` | Deletes são permanentes, sem lixeira |

> Todos os demais campos (Order, Remark, Download Proxy URL, Order By, etc.) podem ser deixados como padrão.

5. Clicar em **Add**

Seus arquivos aparecem instantaneamente na interface.

### 2.4. Alterar a senha do admin

1. Menu lateral → **Settings** → **User Management**
2. Clicar no usuário `admin` → **Edit**
3. Campo **Password** → nova senha
4. **Save**

---

## 🌐 Parte 3: Cloudflare Tunnel

### 3.1. Configurar Public Hostname no Tunnel

No painel **Cloudflare Zero Trust** → **Networks** → **Tunnels**:

1. Selecionar o tunnel existente
2. Adicionar **Public Hostname**:
   - **Subdomain:** `files`
   - **Domain:** `selflabs.org`
   - **Type:** `HTTP`
   - **URL:** `localhost:5244`

> O registro CNAME `files.selflabs.org` é criado automaticamente no Cloudflare DNS.

## 📱 Parte 4: Acesso via Apps (WebDAV)

O OpenList expõe seus arquivos via WebDAV no caminho `/dav`. Use qualquer cliente WebDAV para montar como drive de rede.

**Dados de conexão:**

| Campo      | Valor                                |
| :--------- | :----------------------------------- |
| **URL**    | `https://files.selflabs.org/dav`     |
| **Usuário** | `admin`                             |
| **Senha**  | sua senha definida no painel         |

### Apps recomendados por plataforma

| Plataforma  | App              | Observação                                              |
| :---------- | :--------------- | :------------------------------------------------------ |
| **Android** | Solid Explorer   | Melhor opção — WebDAV nativo, interface limpa           |
| **Android** | CX File Explorer | Gratuito, funciona bem                                  |
| **iOS**     | Infuse           | Ideal para vídeos e mídias, reprodução direta           |
| **iOS**     | Fileball         | Gerenciador de arquivos geral com WebDAV                |
| **Windows** | RaiDrive         | Monta como drive de rede (Z:) no Explorador de Arquivos |

### Configuração no Solid Explorer (Android)

1. Abrir → **☰** → **+ New connection** → **FTP/SFTP/WebDAV...**
2. Selecionar **WebDAV**
3. Preencher os dados da tabela acima
4. **Connect**

### Configuração no RaiDrive (Windows)

1. Abrir RaiDrive → **Add**
2. Tipo: **WebDAV**
3. Preencher os dados da tabela acima
4. **OK** — aparece como drive de rede no Explorador de Arquivos

---

## ✅ Parte 5: Validação

### No Servidor (Debian)

```bash
# 1. Verificar se o container está rodando
docker ps | grep openlist

# 2. Testar se a interface responde
curl -s http://localhost:5244 | grep -i openlist

# 3. Verificar logs
docker logs openlist --tail 50
```

### No Browser

1. Abrir `https://files.selflabs.org`
2. Login com `admin` + senha
3. Confirmar que a pasta `/midia` aparece com seus arquivos

### WebDAV

```bash
# Testar WebDAV via curl (substituir senha)
curl -u admin:SuaSenha https://files.selflabs.org/dav/ -X PROPFIND
```

---

## ⚠️ Troubleshooting

### Arquivos não aparecem após adicionar storage

Verificar se o mount path do volume no container está correto:

```bash
docker exec openlist ls /midia
```

Deve listar suas pastas. Se estiver vazio, o volume não foi montado — revisar o `stack_openlist.yml`.

### Erro 403 no WebDAV

Por padrão, o OpenList permite WebDAV apenas para usuários com permissão explícita. Verificar em **Settings** → **User Management** → **admin** → habilitar **WebDAV Read** e **WebDAV Manage**.

### Erro 502 Bad Gateway no Cloudflare

O tunnel não consegue alcançar o OpenList. Verificar:

```bash
# Container rodando?
docker ps | grep openlist

# Porta respondendo?
curl -s http://localhost:5244
```

### Permissão negada ao acessar /midia

O OpenList roda como `root` (`user: 0:0`) na stack, o que resolve a maioria dos casos. Se ainda ocorrer:

```bash
# Verificar permissões da pasta
ls -la /srv/midia
```

---

## 🌐 Acessos

| Recurso       | URL                              |
| :------------ | :------------------------------- |
| **Web UI**    | `https://files.selflabs.org`     |
| **WebDAV**    | `https://files.selflabs.org/dav` |
| **Local**     | `http://192.168.68.9:5244`       |
| **Portainer** | Stack `openlist`                 |

---

## 📚 Referências

- [Documentação oficial OpenList](https://doc.oplist.org/)
- [OpenList GitHub](https://github.com/OpenListTeam/OpenList)
- [OpenList Docker Hub](https://hub.docker.com/r/openlistteam/openlist)
- [Solid Explorer (Android)](https://play.google.com/store/apps/details?id=pl.solidexplorer2)
- [RaiDrive (Windows)](https://www.raidrive.com/)
- [Infuse (iOS)](https://apps.apple.com/app/infuse-7/id1136220934)
