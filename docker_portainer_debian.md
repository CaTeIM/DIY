# Guia de Instalação: Docker + Portainer no Debian 13

Este guia mostra os passos para instalar o Docker Engine, Docker Compose e a interface de gerenciamento Portainer em um servidor Debian 13, centralizando os dados de configuração na pasta `/srv`.

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

### 3. Instalar o Docker e o Docker Compose

Com o repositório configurado, atualizamos o `apt` novamente e instalamos o Docker.

```bash
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

### 4. (Importante!) Adicionar seu Usuário ao Grupo Docker

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
mkdir -p /srv/portainer
```

### 2. Iniciar o Container do Portainer

Este comando irá baixar e executar o Portainer. A imagem `portainer/portainer-ce:latest` é multi-arquitetura e funcionará automaticamente.

**Observação:** O comando abaixo mapeia a porta `9000` do seu servidor para a porta `9443` (HTTPS) do Portainer. Você pode ajustar a porta `9000` se preferir outra.

```bash
docker run -d \
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
2.  Acesse o endereço: `https://IP_DO_SEU_DEBIAN:9000`
      * (Substitua `IP_DO_SEU_DEBIAN` pelo IP do seu servidor).
3.  O navegador exibirá um aviso de segurança (pois o certificado é autoassinado). Clique em "Avançado" e "Aceitar o risco" ou "Continuar".
4.  Na primeira tela, crie seu usuário administrador e senha.
5.  Selecione a opção "Gerenciar o ambiente Docker local" e clique em "Conectar".

Pronto! Seu ambiente Docker e Portainer está 100% operacional. 🚀
