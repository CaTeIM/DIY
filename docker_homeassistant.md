## 1. Preparação do Servidor (Host)

Execute todos os comandos no terminal SSH do servidor.

### 1.1. Criar Estrutura de Pastas

Criamos todas as pastas necessárias dentro de `/srv/` para persistir os dados.

```bash
# Criar pastas principais
sudo mkdir -p /srv/homeassistant
sudo mkdir -p /srv/esphome
sudo mkdir -p /srv/mosquitto
sudo mkdir -p /srv/nodered

# Criar subpastas do Mosquitto
sudo mkdir -p /srv/mosquitto/config
sudo mkdir -p /srv/mosquitto/data
sudo mkdir -p /srv/mosquitto/log
```

### 1.2. Criar Arquivo de Configuração do Mosquitto

Crie o arquivo `mosquitto.conf` com o conteúdo exato.

```bash
sudo nano /srv/mosquitto/config/mosquitto.conf
```

Cole o seguinte conteúdo dentro do arquivo:

```ini
persistence true
allow_anonymous false
password_file /mosquitto/config/passwd
listener 1883
```

### 1.3. Ajustar Permissão do Mosquitto (Crítico)

O container do Mosquitto roda com o usuário `1883`. Precisamos que ele seja o "dono" da pasta para que possa escrever nela.

```bash
sudo chown -R 1883:1883 /srv/mosquitto
```

### 1.4. Configurar o Firewall (UFW)

Precisamos liberar as portas para todos os serviços.

```bash
# Porta do Home Assistant (Bridge)
sudo ufw allow 8123

# Porta do Mosquitto (Bridge)
sudo ufw allow 1883

# Porta do Node-RED (Host)
sudo ufw allow 1880

# Porta do ESPHome (Host)
sudo ufw allow 6052

# Recarregar o firewall
sudo ufw reload
```

-----

## 2. A Stack (Portainer)

No Portainer, vá em **Stacks**, clique em **+ Add Stack**.

1.  **Nome:** `homeassistant`
2.  **Editor Web:** Cole o código YAML abaixo.

<!-- end list -->

```yaml
version: "3.8"

services:
  homeassistant:
    container_name: homeassistant
    image: ghcr.io/home-assistant/home-assistant:stable
    privileged: true
    restart: unless-stopped
    environment:
      - TZ=America/Sao_Paulo
    volumes:
      - /srv/homeassistant:/config
      - /run/dbus:/run/dbus:ro
      - /etc/localtime:/etc/localtime:ro
    network_mode: bridge
    ports:
      - "8123:8123"
      - "4357:4357"
    hostname: homeassistant

  esphome:
    container_name: esphome
    image: ghcr.io/esphome/esphome:latest
    privileged: true
    restart: always
    environment:
      # Opcional: Adiciona login ao dashboard do ESPHome
      # - USERNAME=seu_usuario
      # - PASSWORD=sua_senha
      - TZ=America/Sao_Paulo
    volumes:
      - /srv/esphome:/config
      - /etc/localtime:/etc/localtime:ro
    network_mode: host
    hostname: esphome

  mosquitto:
    container_name: mosquitto
    image: eclipse-mosquitto:latest
    restart: unless-stopped
    user: "1883:1883"
    volumes:
      - /srv/mosquitto/config:/mosquitto/config
      - /srv/mosquitto/data:/mosquitto/data
      - /srv/mosquitto/log:/mosquitto/log
      - /etc/localtime:/etc/localtime:ro
    network_mode: bridge
    ports:
      - "1883:1883"
    hostname: mosquitto

  nodered:
    container_name: nodered
    image: nodered/node-red:latest
    user: root
    restart: unless-stopped
    environment:
      - TZ=America/Sao_Paulo
    volumes:
      - /srv/nodered:/data
      - /etc/localtime:/etc/localtime:ro
    network_mode: host
    hostname: nodered
```

3.  Clique em **Deploy the stack**.

-----

## 3. Configuração Pós-Deploy

Após o deploy, a stack estará rodando, mas precisamos configurar a comunicação.

### 3.1. Criar Senha do Mosquitto

Execute no terminal do servidor (apenas uma vez) para criar o usuário e senha do MQTT.

```bash
# Sintaxe: docker exec [container] mosquitto_passwd -c -b [arquivo] [usuario] [senha]
docker exec mosquitto mosquitto_passwd -c -b /mosquitto/config/passwd mqtt mqtt.123
```

O container `mosquitto` irá reiniciar automaticamente e ficará saudável.

### 3.2. Configurar MQTT no Home Assistant

1.  Acesse o Home Assistant (ex: `http://IP_DO_SERVIDOR:8123`).
2.  Vá em **Configurações** > **Dispositivos e Serviços**.
3.  Encontre o **MQTT** e clique em **Configurar**.
4.  No campo **Corretor** (Broker), **NÃO** use `mosquitto`.
5.  Use o **IP do Servidor Host** (ex: `192.168.68.9`).
6.  **Porta:** `1883`
7.  **Usuário:** `seu_usuario`
8.  **Senha:** `sua_senha`
9.  Clique em **Próximo**. A conexão deve ser estabelecida com sucesso.

-----

## 4. Acessos Finais

  * **Home Assistant:** `http://[IP_DO_SERVIDOR]:8123`
  * **Node-RED:** `http://[IP_DO_SERVIDOR]:1880`
  * **ESPHome:** `http://[IP_DO_SERVIDOR]:6052`