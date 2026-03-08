# Guia de Instalação: Docker (v5.28) + Portainer no Debian 13

Este guia mostra os passos para instalar uma versão específica do Docker Engine (v5.28.x) e Docker Compose, compatível com o Portainer CE 2.33.3. A interface de gerenciamento Portainer será instalada em um servidor Debian 13, centralizando os dados de configuração na pasta `/srv`.

**Nota de Arquitetura:** Este guia é universal e funciona tanto para arquiteturas **x86_64** (Intel/AMD) quanto **ARM** (como Raspberry Pi, Orange Pi, etc.), desde que estejam rodando Debian 13. Os scripts de instalação detectarão automaticamente a arquitetura correta.

## Parte 1: Instalação do Docker Engine

Siga estes passos no terminal do seu servidor Debian.

### 1. Atualizar Pacotes e Instalar Dependências

Vamos garantir que o sistema está atualizado e tem os certificados necessários.

```bash
sudo apt-get update
sudo apt-get install ca-certificates curl gnupg
```

### 2. Adicionar o Repositório Oficial do Docker

Adicionamos a chave GPG e o repositório oficial do Docker. O script detecta sua arquitetura automaticamente.

```bash
# Criar pasta para a chave
sudo install -m 0755 -d /etc/apt/keyrings

# Baixar a chave GPG
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Adicionar o repositório à lista do apt
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

> **Nota de Compatibilidade (Muito Importante):**
> O **Portainer CE versão 2.33.3** (e possivelmente outras) **não é compatível** com as versões mais recentes do Docker (ex: 5:29.x+).
>
> Os passos a seguir instalam **especificamente a versão `5:28.5.2`**, que é a última compatível conhecida. Também incluímos um passo para "travar" (hold) essa versão e impedir atualizações automáticas indesejadas.

### 3. Instalar Versão Específica do Docker

Com o repositório configurado, atualizamos o `apt` e instalamos a versão exata do Docker e seus componentes.

```bash
# Atualiza a lista de pacotes após adicionar o repo
sudo apt-get update

# Define a string da versão exata (baseado no Trixie/Debian 13)
VERSION_STRING=5:28.5.2-1~debian.13~trixie

# Instala os pacotes com a versão "pinada"
sudo apt-get install \
  docker-ce=$VERSION_STRING \
  docker-ce-cli=$VERSION_STRING \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

# Verifica se o Docker instalou corretamente
sudo docker version
```

### 4. (Crítico!) Travar a Versão do Docker

Para evitar que um `sudo apt upgrade` acidental atualize o Docker e quebre a compatibilidade com o Portainer, nós "travamos" (hold) os pacotes na versão instalada.

```bash
sudo apt-mark hold docker-ce docker-ce-cli
```

### 5. (Importante!) Adicionar seu Usuário ao Grupo Docker

Isso permite que você execute comandos do Docker sem precisar usar `sudo` toda vez.

```bash
sudo usermod -aG docker $USER
```

**⚠️ Atenção:** Após rodar este comando, você precisa **reiniciar o servidor** ou **sair e entrar novamente** (fazer logoff/login) para que a mudança tenha efeito.

## Parte 2: Instalação do Portainer

Agora que o Docker está funcionando, vamos instalar o Portainer para gerenciá-lo.

### 1. Criar a Pasta de Dados do Portainer

Seguindo nosso padrão, vamos criar a pasta de configuração dentro de `/srv`.

```bash
sudo mkdir -p /srv/portainer
```

### 2. Iniciar o Container do Portainer

Este comando irá baixar e executar o Portainer. A imagem `portainer/portainer-ce:latest` é multi-arquitetura e funcionará automaticamente.

**Portas mapeadas:**
- `9000:9000` → Interface web via **HTTP**
- `9443:9443` → Interface web via **HTTPS** (certificado autoassinado)
- `8000:8000` → Comunicação com agentes Portainer (Edge Agents)

```bash
sudo docker run -d \
  -p 9000:9000 \
  -p 9443:9443 \
  -p 8000:8000 \
  --name portainer \
  --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /srv/portainer:/data \
  portainer/portainer-ce:latest
```

## Parte 3: Acesso ao Portainer

Após alguns segundos, o Portainer estará no ar e pronto para ser configurado.

1.  Abra seu navegador de internet.
2.  Acesse o endereço: `http://IP_DO_SEU_DEBIAN:9000`
      * (Substitua `IP_DO_SEU_DEBIAN` pelo IP do seu servidor).
3.  Na primeira tela, crie seu usuário administrador e senha.
      * Se preferir acessar via HTTPS, use `https://IP_DO_SEU_DEBIAN:9443`. Nesse caso, o navegador exibirá um aviso de certificado autoassinado — clique em "Avançado" e "Aceitar o risco".
4.  Selecione a opção "Gerenciar o ambiente Docker local" e clique em "Conectar".

Pronto! Seu ambiente Docker e Portainer está 100% operacional. 🚀

## Anexo: Como Atualizar o Docker (Destravando a Versão)

No futuro, quando o Portainer for atualizado e se tornar compatível com versões mais novas do Docker, siga estes passos para atualizar:

### 1. Destravar os Pacotes

Primeiro, libere os pacotes que você "travou":

```bash
sudo apt-mark unhold docker-ce docker-ce-cli
```

### 2. Atualizar os Pacotes

Agora, você pode rodar uma atualização normal, que pegará a versão "latest" (mais recente) do repositório:

```bash
sudo apt-get update
sudo apt-get upgrade
```

*OU*, se você quiser atualizar para *outra versão específica* (ex: `5:29.0.1`), use o mesmo método de instalação pinada:

```bash
# Exemplo de atualização para uma versão específica futura
NEW_VERSION=5:29.0.1-1~debian.13~trixie

sudo apt-get install \
  docker-ce=$NEW_VERSION \
  docker-ce-cli=$NEW_VERSION
```

### 3. Travar Novamente (Opcional)

Se você atualizou para uma nova versão específica e quer *manter* essa versão (e não a "latest"), trave os pacotes novamente:

```bash
sudo apt-mark hold docker-ce docker-ce-cli
```