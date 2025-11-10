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


## 4. Acessos Finais

  * **Home Assistant:** `http://[IP_DO_SERVIDOR]:8123`
  * **Node-RED:** `http://[IP_DO_SERVIDOR]:1880`
  * **ESPHome Dashboard:** `http://[IP_DO_SERVIDOR]:6052`

## 5. Configurando um Dispositivo ESPHome (Placa)

Esta seção cobre a instalação e segurança de uma placa física (ex: `a16v3`) usando o Dashboard do ESPHome que acabamos de instalar.

### 5.1. Gerar Chave de Criptografia (API)

O método `password:` está obsoleto. Usaremos `encryption: key:`.

1.  Acesse o Dashboard do ESPHome (`http://[IP_DO_SERVIDOR]:6052`).
2.  Clique em **+ NEW DEVICE**. Dê um nome temporário (ex: `gerador-de-chave`) e avance.
3.  Clique em **EDIT** no dispositivo `gerador-de-chave` que apareceu.
4.  O YAML terá um bloco `api:` com uma chave. **Copie a chave** (o texto longo em Base64).
    ```yaml
    api:
      encryption:
        key: "ABCDEfghijklmNOPQRSTuvwxyz0123456789/+=ABCD=" # (Algo assim)
    ```
5.  Delete o dispositivo `gerador-de-chave`.

### 5.2. Criar o Firmware da Placa

1.  Clique em **+ NEW DEVICE** novamente e crie seu dispositivo real (ex: `a16v3`).
2.  Clique em **EDIT** no seu dispositivo `a16v3`.
3.  Cole o YAML da sua placa.
4.  **Configure a Segurança:** Adicione a chave (do Passo 5.1) e a senha do site (Web Server).

<!-- end list -->

```yaml
esphome:
  name: a16v3
  # ... (resto da sua config) ...

# 1. Segurança da API (para o Home Assistant)
api:
  encryption:
    key: "COLE_A_CHAVE_QUE_VOCE_COPIOU_AQUI"

# ... (resto da sua config, ethernet, i2c, etc.) ...

# 2. Segurança do Web Server (para o navegador)
web_server:
  port: 80
  auth:
    username: "seu_usuario"
    password: "sua_senha"
```

### 5.3. Primeira Instalação (Factory Flash)

Como a placa está com o firmware de fábrica (KinCony), a primeira instalação deve ser via USB.

1.  No dashboard, clique em **INSTALL** no dispositivo `a16v3`.
2.  O servidor irá compilar o firmware. Aguarde o "Preparing download..." terminar (pode demorar vários minutos).
3.  Um arquivo `.bin` (ex: `a16v3-factory.bin`) será baixado.
4.  Conecte a placa `a16v3` ao seu computador via **cabo USB**.
5.  Na mesma tela do ESPHome, clique em **"Open ESPHome Web"**.
6.  Um site (esphome.io) abrirá. Clique em **CONNECT**, selecione a porta USB da sua placa e clique em **INSTALL**.
7.  Selecione o arquivo `.bin` que você baixou.
8.  Aguarde o processo "Flashing..." terminar.

### 5.4. Adicionar Placa ao Home Assistant

1.  Após o flash, a placa irá reiniciar e conectar na rede com o IP estático que você definiu (ex: `192.168.68.30`).
2.  No Home Assistant, vá em **Configurações > Dispositivos > Adicionar Integração**.
3.  Procure por **ESPHome**.
4.  **Host:** Digite o IP da *placa* (ex: `192.168.68.30`).
5.  **Encryption Key:** Cole a mesma chave de criptografia (do Passo 5.1) que você colocou no YAML.
6.  A placa será adicionada.

### 5.5. Atualizações Futuras (OTA)

A partir de agora, você **não precisa mais do cabo**. Para qualquer mudança no YAML, apenas clique em **INSTALL** e escolha **OTA (Over-the-Air)**.