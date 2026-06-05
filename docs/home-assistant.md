## 1. Preparação do Servidor (Host) 🛠️

Execute todos os comandos no terminal SSH do servidor.

### 1.1. Criar Estrutura de Pastas 📂

Criamos todas as pastas necessárias dentro de `/srv/` para persistir os dados.

```bash
# Criar pastas principais
sudo mkdir -p /srv/homeassistant
sudo mkdir -p /srv/esphome
sudo mkdir -p /srv/mosquitto
sudo mkdir -p /srv/nodered
sudo mkdir -p /srv/habridge

# Criar subpastas
sudo mkdir -p /srv/mosquitto/config
sudo mkdir -p /srv/mosquitto/data
sudo mkdir -p /srv/mosquitto/log
sudo mkdir -p /srv/habridge/scripts

# Ajustar permissão (Crítico: não usar root no container)
sudo chown -R 1000:1000 /srv/nodered
sudo chown -R 1000:1000 /srv/habridge
```

_(**Nota:** O `file-editor` usa a pasta `/srv/homeassistant`, que já foi criada acima, então não precisamos de uma pasta nova para ele.)_

### 1.2. Criar Arquivo de Configuração do Mosquitto 📝

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

### 1.3. Ajustar Permissão do Mosquitto (Crítico) 🔐

O container do Mosquitto roda com o usuário `1883`. Precisamos que ele seja o "dono" da pasta para que possa escrever nela.

```bash
sudo chown -R 1883:1883 /srv/mosquitto
```

### 1.4. Criar Senha do Mosquitto (À Prova de Falhas) 🔑

Precisamos criar o arquivo de senha. No entanto, o container `mosquitto` (como configurado no `mosquitto.conf`) não inicia se o arquivo de senha não existir, causando um "crash loop".

Para resolver isso, usamos um **container temporário** para criar o arquivo na pasta correta, antes mesmo de subir a stack.

```bash
# Rode este comando para criar o arquivo /srv/mosquitto/config/passwd
# Substitua seu_usuario_mqtt e sua_senha_mqtt
docker run --rm -u 1883 \
  -v /srv/mosquitto/config:/mosquitto/config \
  eclipse-mosquitto:latest \
  mosquitto_passwd -c -b /mosquitto/config/passwd seu_usuario_mqtt sua_senha_mqtt
```

_(**Nota:** O `-u 1883` garante que o arquivo seja criado com o "dono" correto, o mesmo do Passo 1.3)_

### 1.5. Configurar o Firewall (UFW) 🛡️

Precisamos liberar as portas para todos os serviços.

```bash
# Instala o UFW (Firewall)
sudo apt install ufw

# Porta do SSH (Verifique em sudo nano /etc/ssh/sshd_config)
sudo ufw allow 22/tcp

# Porta do Home Assistant (Bridge)
sudo ufw allow 8123

# Porta do Mosquitto (Bridge)
sudo ufw allow 1883

# Porta do Node-RED (Host)
sudo ufw allow 1880

# Porta do ESPHome (Host)
sudo ufw allow 6052

# Porta do File Editor (Bridge)
sudo ufw allow 3218

# Portas do HA Bridge (Host networking — Emulação Hue para a Alexa)
sudo ufw allow 80/tcp        # WebUI do bridge + API Hue consultada pela Alexa
sudo ufw allow 1900/udp      # Descoberta UPnP/SSDP (multicast)
sudo ufw allow 50000/udp     # Porta de resposta UPnP do bridge

# Habilita o Firewall
sudo ufw enable

# Recarregar o Firewall (Se UFW já tiver instalado)
sudo ufw reload

# Verifique o Status do Firewall
sudo ufw status
```

### 1.6. Pré-criar a Configuração do HA Bridge (Crítico) 🔌

O HA Bridge precisa rodar na **porta 80** — a Alexa, depois de descobrir o bridge, faz toda a API Hue (criar usuário e listar luzes) na **porta 80 fixa**. Em qualquer outra porta ela até descobre o "bridge", mas nunca lista os dispositivos. A porta padrão da imagem (`8080`) não serve aqui (além de já estar ocupada no nosso servidor), e a porta web vem do `ha-bridge.config`, não do `compose`.

A imagem da LinuxServer só cria o `ha-bridge.config` **se ele ainda não existir**. Então criamos o arquivo **antes do primeiro deploy**, já com a porta `80` e a interface da LAN fixada. (A permissão para o container não-root abrir a porta 80 vem no Passo 1.7.)

```bash
# Descubra o IP do servidor na LAN (anote — você vai usá-lo no comando sed mais abaixo)
hostname -I

# Cria o config já na porta 80, fixando a interface da LAN (useupnpiface) e a resposta UPnP 50000
sudo tee /srv/habridge/ha-bridge.config > /dev/null <<'EOF'
{
  "upnpconfigaddress": "SEU_IP_DO_HOST",
  "useupnpiface": true,
  "userooms": false,
  "serverport": 80,
  "upnpresponseport": 50000,
  "upnpdevicedb": "/config/device.db",
  "upnpgroupdb": "/config/group.db",
  "buttonsleep": 100,
  "traceupnp": false,
  "farenheit": true,
  "configfile": "/config/ha-bridge.config",
  "numberoflogmessages": 512,
  "myechourl": "alexa.amazon.com/spa/index.html#cards",
  "webaddress": "0.0.0.0",
  "hubversion": "9999999999",
  "securityData": "f5qxk/NdTo2Zwnc6ubLZJESM4p5nAvp+0wS+aEwuuxTwAJD/PhyGiHIvDYZBwI7eOO2+zHuK6LEMPdGRS72FO85svgHrVZh9LnBwmxVN8CrFKu1rViuxB+T9uYyVPH2Xj/8uKbXbgsVcUeK7/O6vAcOeErUQVsVna+1rxRIj4Pg/3wz1xULDLnoCBIPYjfi5/PGlQmu0GoHVniI0P2e3LQ85yV99IYekU04bu9poPGgyo25Xa/WZfKw/ROAHuKKO3/3ZI7LZcFZiKAPUx2Vg6A==",
  "upnpsenddelay": 650,
  "lifxconfigured": false,
  "broadlinkconfigured": false,
  "settingsChanged": false,
  "veraconfigured": false,
  "fibaroconfigured": false,
  "harmonyconfigured": false,
  "hueconfigured": false,
  "nestconfigured": false,
  "halconfigured": false,
  "mqttconfigured": false,
  "hassconfigured": false,
  "domoticzconfigured": false,
  "somfyconfigured": false,
  "homewizardconfigured": false,
  "openhabconfigured": false,
  "fhemconfigured": false,
  "upnpstrict": true
}
EOF
```

```bash
# Troque SEU_IP_DO_HOST pelo IP FIXO do servidor na LAN (o que apareceu no hostname -I)
sudo sed -i 's/SEU_IP_DO_HOST/192.168.x.x/' /srv/habridge/ha-bridge.config

# Dono correto (mesmo PUID/PGID do container)
sudo chown -R 1000:1000 /srv/habridge
```

> [!IMPORTANT]
> Campos que importam aqui:
>
> - **`serverport`: `80`** → a Alexa faz a API Hue na **porta 80 fixa**. Em outra porta ela descobre o "bridge" mas nunca lista os dispositivos. O Passo 1.7 libera o bind da 80.
> - **`upnpconfigaddress`** → o IP fixo do servidor na LAN que o bridge **anuncia** para a Alexa. Se ficar `0.0.0.0` ou errado, a Alexa descobre mas não conecta.
> - **`useupnpiface`: `true`** → faz o bridge usar **só a interface da LAN**. Essencial quando o host tem várias redes Docker (`172.x`): senão o bridge responde à descoberta por todas elas e confunde a Alexa.
> - **`upnpresponseport`: `50000`** → porta de resposta do UPnP (liberada no firewall).
>
> O `securityData` é o valor padrão da imagem e funciona com `HABRIDGE_SEC_KEY` **vazia** (veja a Seção 6.8 para proteger a UI).

> [!WARNING]
> **Edite o `ha-bridge.config` sempre com o container parado** (`sudo docker stop habridge`). Com o bridge rodando, ele **regrava o arquivo** ao reiniciar — ou ao clicar **Save/Bridge Reinitialize** na UI — e desfaz a sua edição manual.

### 1.7. Liberar a porta 80 para o HA Bridge (sysctl) 🔓

O container roda o Java como usuário **não-root** (`uid 1000`) e, no Linux, portas abaixo de 1024 são privilegiadas. Como ele está em `network_mode: host`, **não** dá para resolver isso pelo `compose` (o Docker recusa `sysctls` de rede com host networking) — o ajuste é no **host**:

```bash
# Permite que processo não-root abra portas >= 80 (aplica agora + persiste no boot)
sudo sysctl -w net.ipv4.ip_unprivileged_port_start=80
echo 'net.ipv4.ip_unprivileged_port_start=80' | sudo tee /etc/sysctl.d/99-habridge.conf

# Confere (deve retornar 80)
cat /proc/sys/net/ipv4/ip_unprivileged_port_start
```

---

## 2. As Stacks (Portainer) 📦

Vamos criar duas stacks separadas. No Portainer, vá em **Stacks**, clique em **+ Add Stack**.

### 2.1. Stack Principal: `homeassistant` 🏠

1. **Nome:** `homeassistant`
2. **Editor Web:** Copie o conteúdo do arquivo [`assets/stacks/home-assistant.yml`](../assets/stacks/home-assistant.yml) e cole no editor.
3. **Environment variables:** Adicione as seguintes variáveis (você precisará criar senhas fortes):
   - `ESPHOME_USERNAME`: Seu usuário para o painel do ESPHome.
   - `ESPHOME_PASSWORD`: Sua senha para o painel do ESPHome.
   - `FILE_EDITOR_USERNAME`: Seu usuário para o File Editor.
   - `FILE_EDITOR_PASSWORD`: Sua senha para o File Editor.
   - `FILE_EDITOR_TOKEN`: Deixe vazio por enquanto.
   - `HABRIDGE_SEC_KEY`: Deixe **vazio** (só preencha se for proteger a UI do HA Bridge com login — veja a Seção 6.8).
4. Clique em **Deploy the stack**.

_(**Nota:** O `file-editor` vai iniciar, mas pode dar erro nos logs até você completar o Passo 3.2)_

### 2.2. Stack de Manutenção: `watchtower` 🧹

Esta stack atualiza os containers automaticamente e limpa imagens velhas.

1. Crie uma **Nova Stack**.
2. **Nome:** `watchtower`
3. **Editor Web:** Cole o código abaixo.

```yaml
name: "watchtower"

services:
  watchtower:
    image: containrrr/watchtower
    container_name: watchtower
    command: --cleanup --include-restarting --include-stopped --schedule "0 0 3 * * *"
    restart: unless-stopped
    environment:
      - TZ=America/Sao_Paulo
      - DOCKER_API_VERSION=1.40
      - WATCHTOWER_WARN_ON_HEAD_FAILURE=never
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /root/.docker/config.json:/config.json
    network_mode: host
```

4. Clique em **Deploy the stack**.

---

## 3. Configuração Pós-Deploy ⚙️

Após o deploy, a stack estará rodando, mas precisamos configurar a comunicação.

### 3.1. Configurar MQTT no Home Assistant

1. Acesse o Home Assistant (ex: `http://IP_DO_SERVIDOR:8123`).
2. Vá em **Configurações** > **Dispositivos e Serviços**.
3. Encontre o **MQTT** e clique em **Configurar**.
4. No campo **Corretor** (Broker), **NÃO** use `mosquitto`.
5. Use o **IP do Servidor Host** (ex: `192.168.x.x`).
6. **Porta:** `1883`
7. **Usuário:** `seu_usuario_mqtt` (o que você criou no passo 1.4)
8. **Senha:** `sua_senha_mqtt` (a que você criou no passo 1.4)
9. Clique em **Próximo**. A conexão deve ser estabelecida com sucesso.

### 3.2. Configurar o File Editor (Token)

O `file-editor` precisa de um Token (chave) para poder se comunicar com o Home Assistant (e assim poder checar a config e reiniciar o HA).

1. No Home Assistant, clique no seu nome de usuário (canto inferior esquerdo) para abrir seu **Perfil**.
2. Role até o final da página e clique em **"Tokens de Acesso de Longa Duração"**.
3. Clique em **"Criar Token"**.
4. Dê um nome para ele (ex: `file-editor`) e clique em **OK**.
5. O HA vai gerar um token gigante. **Copie esse token imediatamente** (ele só é mostrado uma vez).
6. Agora, volte ao **Portainer**.
7. Vá em **Stacks** > clique na sua stack `homeassistant` > clique na aba **Editor**.
8. Role para baixo até a seção **Environment variables**.
9. Cole o token que você copiou no valor da variável `FILE_EDITOR_TOKEN`.
10. Clique em **Update the stack**.

O `file-editor` irá reiniciar e agora terá acesso total ao seu Home Assistant.

---

## 4. Acessos Finais 🌐

- **Home Assistant:** `http://[IP_DO_SERVIDOR]:8123`
- **Node-RED:** `http://[IP_DO_SERVIDOR]:1880`
- **ESPHome Dashboard:** `http://[IP_DO_SERVIDOR]:6052`
- **File Editor:** `http://[IP_DO_SERVIDOR]:3218`
- **HA Bridge:** `http://[IP_DO_SERVIDOR]` (porta 80)

---

## 5. Configurando um Dispositivo ESPHome (Placa) 🔌

Esta seção cobre a instalação e segurança de uma placa física (ex: `a16v3`) usando o Dashboard do ESPHome que acabamos de instalar.

### 5.1. Gerar Chave de Criptografia (API)

O método `password:` está obsoleto. Usaremos `encryption: key:`.

1. Acesse o Dashboard do ESPHome (`http://[IP_DO_SERVIDOR]:6052`).
2. Clique em **+ NEW DEVICE**. Dê um nome temporário (ex: `gerador-de-chave`) e avance.
3. Clique em **EDIT** no dispositivo `gerador-de-chave` que apareceu.
4. O YAML terá um bloco `api:` com uma chave. **Copie a chave** (o texto longo em Base64).

```yaml
api:
  encryption:
    key: "ABCDEfghijklmNOPQRSTuvwxyz0123456789/+=ABCD=" # (Algo assim)
```

5. Delete o dispositivo `gerador-de-chave`.

### 5.2. Criar o Firmware da Placa

1. Clique em **+ NEW DEVICE** novamente e crie seu dispositivo real (ex: `a16v3`).
2. Clique em **EDIT** no seu dispositivo `a16v3`.
3. Cole o YAML da sua placa.
4. **Configure a Segurança:** Adicione a chave (do Passo 5.1) e a senha do site (Web Server).

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
    username: "admin"
    password: "uma_senha_muito_forte_aqui"
```

> [!WARNING]
> Nunca versione esse arquivo YAML no GitHub com senhas reais se o repositório for público. Para repositórios públicos, use o recurso `!secret` nativo do ESPHome.

### 5.3. Primeira Instalação (Factory Flash)

Como a placa está com o firmware de fábrica (KinCony), a primeira instalação deve ser via USB.

1. No dashboard, clique em **INSTALL** no dispositivo `a16v3`.
2. O servidor irá compilar o firmware. Aguarde o "Preparing download..." terminar (pode demorar vários minutos).
3. Um arquivo `.bin` (ex: `a16v3-factory.bin`) será baixado.
4. Conecte a placa `a16v3` ao seu computador via **cabo USB**.
5. Na mesma tela do ESPHome, clique em **"Open ESPHome Web"**.
6. Um site (esphome.io) abrirá. Clique em **CONNECT**, selecione a porta USB da sua placa e clique em **INSTALL**.
7. Selecione o arquivo `.bin` que você baixou.
8. Aguarde o processo "Flashing..." terminar.

### 5.4. Adicionar Placa ao Home Assistant

1. Após o flash, a placa irá reiniciar e conectar na rede com o IP estático que você definiu (ex: `192.168.68.30`).
2. No Home Assistant, vá em **Configurações > Dispositivos > Adicionar Integração**.
3. Procure por **ESPHome**.
4. **Host:** Digite o IP da _placa_ (ex: `192.168.68.30`).
5. **Encryption Key:** Cole a mesma chave de criptografia (do Passo 5.1) que você colocou no YAML.
6. A placa será adicionada.

### 5.5. Atualizações Futuras (OTA)

A partir de agora, você **não precisa mais do cabo**. Para qualquer mudança no YAML, apenas clique em **INSTALL** e escolha **OTA (Over-the-Air)**.

---

## 6. Configurando o HA Bridge (Emulação Hue para a Alexa) 🗣️

O **HA Bridge** finge ser uma **Philips Hue Bridge** na sua rede. Com isso, a **Amazon Alexa** descobre as entidades do seu Home Assistant como se fossem luzes/tomadas Hue — **sem nuvem e sem Nabu Casa**. Você fala _"Alexa, ligar a sala"_ e o bridge chama a API do Home Assistant para executar a ação.

> [!NOTE]
> Funciona com **Amazon Echo** (Echo, Dot, Plus, Spot, Show, Tap). A descoberta é mais confiável em modelos antigos; alguns Echos novos podem precisar de uma segunda tentativa. **Não funciona com Google Home/Nest** (o Google exige conexão de nuvem que este bridge não emula).

### 6.1. Como funciona (host networking + porta 80)

A descoberta tem **duas fases**, e as duas importam:

1. **Descoberta (UPnP/SSDP):** a Alexa manda um pacote **multicast** para `239.255.255.250:1900`. O bridge escuta nessa porta e responde com o endereço da sua "descrição" (`http://[IP_DO_SERVIDOR]/description.xml`). Esse multicast **não atravessa a rede `bridge` do Docker** — por isso o serviço roda em `network_mode: host`.
2. **API Hue (porta 80):** depois de ler o `description.xml`, a Alexa **cria um usuário e pede a lista de luzes na porta 80 fixa**. Se o bridge estiver em outra porta, ela descobre o "bridge" mas nunca lista os dispositivos. Por isso fixamos a porta `80` (Passo 1.6) e liberamos o bind dela (Passo 1.7).

É também por isso que o firewall libera `1900/udp`, `50000/udp` e `80/tcp` (Passo 1.5).

### 6.2. Primeiro acesso e verificação

1. Acesse a interface: `http://[IP_DO_SERVIDOR]` (porta 80).
2. Vá na aba **Bridge Control** e confirme:
   - **UPNP IP Address** = o **IP fixo do servidor na LAN** (Passo 1.6).
   - **Use UPNP Address Interface Only** = **marcado** (`true`) — limita o UPnP à interface da LAN; sem isso, num host com várias redes Docker o bridge responde por todas e a Alexa se perde.
3. Se mudar algo aqui, clique em **Save** e **Bridge Reinitialize**.

### 6.3. Criar o Token do Home Assistant 🔑

O bridge precisa de um token para chamar a API do Home Assistant (mesmo procedimento do Passo 3.2):

1. No Home Assistant, clique no seu **Perfil** (canto inferior esquerdo).
2. Role até **"Tokens de Acesso de Longa Duração"** e clique em **"Criar Token"**.
3. Nomeie como `habridge` e clique em **OK**.
4. **Copie o token imediatamente** (ele só aparece uma vez).

### 6.4. Conectar o HA Bridge ao Home Assistant 🔗

Ainda na aba **Bridge Control**, localize a seção de **gateways do Home Assistant** e adicione um novo:

| Campo                | Valor                                                                |
| -------------------- | -------------------------------------------------------------------- |
| **Name**             | `hass` (um nome qualquer para identificar)                           |
| **IP Address**       | `[IP_DO_SERVIDOR]` (em host networking, `localhost` também funciona) |
| **Port**             | `8123`                                                               |
| **Secure**           | desmarcado (usamos `http`)                                           |
| **Password / Token** | cole o **Long-Lived Access Token** do Passo 6.3                      |

Clique em **Add/Save**. Após salvar, uma nova aba **Home Assistant** aparece no menu superior.

> [!NOTE]
> O **Auth Type** define como o bridge autentica no HA. No Home Assistant atual, o token de longa duração é um **Bearer token** — se o **controle** (ligar/desligar) falhar mesmo com a descoberta OK, troque o tipo de autenticação do gateway (não use "Legacy Password", que era para o antigo `api_password`).

### 6.5. Criar os Dispositivos (importar entidades) 💡

1. Abra a aba **Home Assistant** (a que surgiu no passo anterior). Ela lista as **entidades** do seu HA (luzes, interruptores, scripts, cenas, etc.).
2. Marque as entidades que você quer controlar por voz.
3. Clique no botão de **adicionar/importar** (ex.: _Bulk Add_) para gerar os dispositivos automaticamente — o bridge cria o `on`/`off` chamando `homeassistant.turn_on` / `turn_off` para cada entidade.
4. Vá na aba **Bridge Devices** e ajuste o **Name** de cada dispositivo: **esse nome é exatamente o que você falará** _("Alexa, ligar **abajur do quarto**")_. Use nomes curtos e sem ambiguidade.

### 6.6. Ajustar o `uniqueid` dos dispositivos para a Alexa 🧩

Por padrão, o ha-bridge gera o `uniqueid` de cada luz num **formato curto** (ex.: `5f:93:f9:83:52:4d:ef-3d`). A Alexa atual só aceita o formato completo da Hue real, com **um octeto a mais** (`00:5f:93:f9:83:52:4d:ef-3d`). Sem isso, **a Alexa descobre o bridge mas descarta as luzes** ("nenhum dispositivo novo encontrado").

1. **Bridge Control** → marque **"Unique ID to use 9 Octets (Renumber after saving this setting)"** → **Save**.
2. **Bridge Devices** → clique em **"Renumber Devices"** (regenera os `uniqueid` no formato novo).
3. (Opcional) Confirme via terminal que agora há **8 grupos** antes do hífen:

```bash
curl -s http://[IP_DO_SERVIDOR]/api/qualquercoisa/lights | head -c 300; echo
```

### 6.7. Descobrir os dispositivos na Alexa 🔍

1. No app **Alexa**, **remova/esqueça** quaisquer luzes ou bridge Hue de tentativas anteriores (limpa o cache com `uniqueid` antigos).
2. **Dispositivos** → **➕** → **Adicionar dispositivo** → role até **"Outro"** → **Detectar dispositivos** (ou diga _"Alexa, procurar dispositivos"_).
3. Aguarde os ~45 segundos completos. Os dispositivos entram como luzes Hue.
4. Teste por voz: _"Alexa, ligar [nome do dispositivo]"_.

### 6.8. (Opcional) Proteger o painel do HA Bridge 🛡️

Por padrão o painel fica aberto na LAN. O login tem **duas peças**:

- **`HABRIDGE_SEC_KEY`** → a chave que **criptografa** o usuário/senha dentro do `ha-bridge.config` (a "tranca do cofre").
- **usuário/senha** → a credencial que você cria na UI para **entrar** no painel.

> [!IMPORTANT]
> Mantenha **"Use username/password for HUE Api" DESMARCADO** — essa opção protege a API que a Alexa usa e **quebraria a integração**. Aqui protegemos só o painel.

1. **Gere a chave** e guarde-a (é permanente): `openssl rand -hex 24`.
2. **Portainer** → stack `homeassistant` → **Environment variables** → cole a chave em `HABRIDGE_SEC_KEY` → **Update the stack**. _(No log surge uma vez `Could not get security data ... bad key` — é esperado.)_
3. Na UI → **Bridge Control → Update Security Settings**:
   - **Add/Delete User**: digite o usuário (ex.: `admin`).
   - **Change Password** + **Confirm Password**: digite a **mesma** senha forte → botão **Change Password**.
4. Recarregue `http://[IP_DO_SERVIDOR]` — o navegador deve **pedir login**.

> [!WARNING]
> A `HABRIDGE_SEC_KEY` **não pode mudar** depois de criar o usuário (é a chave que o descriptografa). Se trocar, você perde o acesso ao painel — recuperável apagando o `securityData` do `ha-bridge.config` (com o container parado).

### 6.9. Solução de Problemas 🩺

> [!TIP]
> O melhor diagnóstico é o **Trace UPNP**: em **Bridge Control** marque **"Trace UPNP Calls"** → Save, mande a Alexa procurar e acompanhe `sudo docker logs -f habridge`. Dá para ver cada fase: `M-SEARCH` → `description.xml` → `hue api user create` → `hue lights list`. Desmarque depois para o log parar de encher.

- **A Alexa não encontra nada (nenhum `M-SEARCH` no log):** problema de **rede**. Confirme `network_mode: host`, o firewall (`1900/udp`, `50000/udp`, `80/tcp`), que o Echo está na **mesma sub-rede** do servidor, e que nenhum outro serviço usa `1900/udp` (Plex/Jellyfin/DLNA).
- **Vê o `M-SEARCH` e baixa o `description.xml`, mas para aí (sem `hue api user create`/`lights list`):** o bridge **não está na porta 80**. Confirme `serverport: 80` no config + o `sysctl` do Passo 1.7.
- **Descobre o bridge, mas diz "nenhum dispositivo novo":** o **`uniqueid`** está no formato curto — aplique o Passo 6.6 (opção "9 Octets" + Renumber) e redescubra.
- **`upnpconfigaddress` errado:** o bridge anuncia um IP que não é o dele; tem que ser o **IP fixo da LAN**. Corrija (Passo 1.6) e reinicie.
- **Log poluído com respostas por interfaces `172.x`:** ative **`useupnpiface: true`** (Passo 1.6 / "Use UPNP Address Interface Only" na UI) para usar só a interface da LAN.
- **Editou o config e a mudança "voltou":** você editou com o **container rodando**. Pare-o antes (`sudo docker stop habridge`), edite, e só então inicie — o ha-bridge regrava o arquivo ao reiniciar/salvar.
- **Descobre e lista, mas não controla (a luz não acende):** problema no **gateway do Home Assistant**, não na Alexa. Teste com **"Test ON"** na aba Bridge Devices; se falhar, revise o **token** e o **Auth Type** do gateway (Passo 6.4).
- **Mudou algo no HA e a Alexa não reflete:** rode a descoberta de novo e **remova dispositivos antigos** no app Alexa para evitar duplicatas.
