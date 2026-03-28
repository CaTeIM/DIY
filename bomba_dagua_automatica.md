# 🚰💡 Projeto: Acionamento Automático de Bomba d’Água

## 📦 Descrição Geral

Sistema automatizado para acionamento remoto de uma bomba d’água em local sem cabeamento, usando rede Wi-Fi ponto a ponto, Sonoff com Tasmota e sensores de nível.

## 🧱 Estrutura Física

| Local     | O que tem                                                |
|-----------|----------------------------------------------------------|
| Ponto A   | Bomba d'água + Sonoff RE5V1C (Tasmota) + RE5V1C (original eWeLink) |
| Ponto B   | 2x CPE210 (modo AP), uma apontando para A e outra para C |
| Ponto C   | Caixa d’água + Sonoff RE5V1C (Tasmota) com sensor de nível impermeável (RCWL-1655 / JSN-SR04T) |

## 🌐 Conectividade

- 2x CPE210 TP-Link no Ponto B (modo Access Point):
  - CPE1 → `SSID: link_para_ponto_A`
  - CPE2 → `SSID: link_para_ponto_C`
- Sonoff RE5V1C se conectam diretamente ao Wi-Fi da CPE correspondente.
- IPs fixos recomendados:
  - Ponto A (Sonoff Bomba): `192.168.3.101`
  - Ponto C (Sonoff Sensor): `192.168.3.102`

## ⚙️ Funcionamento

- Sensor no Ponto C (RCWL-1655) mede a distância da água.
- Quando a água atinge nível baixo, Sonoff (Tasmota) envia comando WebSend:
	 ```
	 WebSend [192.168.3.101] /cm?cmnd=Power1%20On
	 ```
- O Sonoff Tasmota do Ponto A simula o botão do Sonoff original (eWeLink), ativando a bomba.
- Quando enche, o sensor envia comando para desligar.

## ⚡ Preparando o Sonoff para o Flash

### 🔎 Identificação dos Pinos

**Sonoff RE5V1C**
- GND
- 3V3 (⚠️ Nunca use 5V durante o flash!)
- ERX
- ETX

**CH341A Pro**
- GND
- 3.3V
- TXD
- RXD

### 🔗 Ligações

| CH341A | Sonoff RE5V1C  |
|--------|----------------|
| GND    | GND            |
| 3.3V   | 3V3            |
| TXD    | ERX            |
| RXD    | ETX            |

### 🕹️ Modo Bootloader

1. Mantenha o botão do RE5V1C pressionado
2. Conecte o USB-TTL ao PC
3. Aguarde 5s e solte

## 💻 Instalando Drivers e Software

- [Driver CH341A](https://wch.cn/downloads/CH341SER_EXE.html)
- [Tasmotizer](https://github.com/tasmota/tasmotizer/releases)
- [Firmware Tasmota-Sensors](https://ota.tasmota.com/tasmota/release/tasmota-sensors.bin) (⚠️ **Obrigatório:** A versão `tasmota.bin` normal não possui os drivers de sensores)

## 🔥 Flash do Tasmota

1. Abra o Tasmotizer
2. Selecione a porta COM
3. Marque: `Erase before flashing`
4. Marque: `Self-resetting device`
5. Selecione `tasmota-sensors.bin`
6. Clique em **Tasmotize!**
7. Aguarde e desconecte

## 🔧 Configurações Tasmota

1. Ligue o Sonoff
2. Conecte no Wi-Fi “tasmota-XXXX”
3. Acesse [http://192.168.4.1](http://192.168.4.1)
4. Configure sua rede Wi-Fi
5. Acesse o IP atribuído no seu roteador
6. Vá em **Configuration > Configure Other**
7. Cole o template:

```json
{"NAME":"Sonoff RE5V1C","GPIO":[17,255,255,255,255,255,0,0,21,56,0,0,0],"FLAG":0,"BASE":18}
```

8. Marque **Activate** e salve.
9. Desabilite o `reset` via ciclos de energia. Acesse **Console**:

```
 SetOption65 1
 Timezone -3
 SerialLog 0
 ``` 

### Ponto A (Bomba)
- Power1 controla um relé que simula o botão do Sonoff original
- `PulseTime1 10` (para clique curto)
- Exemplo:
 ```
 Power1 ON
 ```

- Coloque **IP estático** no módulo:

 ```
 IPAddress1 192.168.3.101
 IPAddress2 192.168.3.1
 IPAddress3 255.255.255.0
 IPAddress4 8.8.8.8
 IPAddress5 1.1.1.1
 Restart 1
 ```

### Ponto C (Sensor de Nível)

#### Hardware: RCWL-1655

O RCWL-1655 suporta 4 modos de operação, selecionados pelo resistor **R7** no verso do módulo:

| Modo | R7 | Protocolo | Compatível com Tasmota SR04? |
|------|----|-----------|-------------------------------|
| **GPIO (padrão)** | **NC (vazio)** | HC-SR04 (Trig/Echo) | ✅ **SIM** |
| UART | 10K | Serial 9600bps | ❌ Não |
| I2C | 100K | 0x57 | ❌ Não |
| 1-Wire | 0 ohm | Single bus | ❌ Não |

> [!IMPORTANT]
> Antes de ligar, vire o módulo e verifique o pad **R7**. Ele deve estar **vazio (NC)**. Se houver um resistor soldado, remova-o para ativar o modo GPIO.

#### Ligação Física (Pino Sonoff RE5V1C)

Pinagem confirmada pela tabela oficial do ESPHome para os pads da borda superior do Sonoff:

| RCWL-1655 | Pino físico Sonoff | GPIO Tasmota | Função Tasmota |
|-----------|--------------------|--------------|----------------|
| VCC | `5V` | — | Alimentação |
| GND | `GND` | — | Terra |
| **Trig** | pad **`RX`** | **GPIO4** | `SR04 Tri/Tx` |
| **Echo** | pad **`TX`** | **GPIO5** | `SR04 Ech/Rx` |

> [!NOTE]
> A zona cega do RCWL-1655 é de **20cm** (muito maior que o HC-SR04 comum de ~2cm). Certifique-se de que o sensor esteja a mais de 20cm da superfície da água, ou as leituras serão inválidas.

#### Configuração Tasmota (Ponto C)

Após aplicar o template principal, defina os pinos em **Configuration » Configure Module**:
- **D2 GPIO4** → `SR04 Tri/Tx`
- **D1 GPIO5** → `SR04 Ech/Rx`

No **Console**:
```text
PowerOnState 0
SetOption65 1
TelePeriod 10
Timezone -3
SerialLog 0
```

Verificar leitura do sensor:
```text
Status 10
```
Deve retornar algo como `{"SR04":{"Distance":85.3}}`. Se retornar `null` ou não aparecer, revisar a ligação física e o estado do R7.

> [!WARNING]
> **🚧 TESTE PENDENTE** — A pinagem GPIO4/GPIO5 ainda não foi validada fisicamente com o RCWL-1655 neste módulo. Realizar os seguintes passos ao conectar:
> 1. Verificar R7 = NC (vazio)
> 2. Ligar: Trig → pad `RX` (GPIO4), Echo → pad `TX` (GPIO5)
> 3. Configurar GPIO4=SR04 Tri/Tx e GPIO5=SR04 Ech/Rx no Tasmota
> 4. Rodar `Status 10` e confirmar leitura de distância

#### Regras (Ponto C)

A regra envia comando para ligar a bomba quando a distância medida for maior que 80cm (caixa baixa):

```text
Rule1 ON Tele-SR04#Distance>80 DO WebSend [192.168.3.101] /cm?cmnd=Power1%20On ENDON ON Tele-SR04#Distance<30 DO WebSend [192.168.3.101] /cm?cmnd=Power1%20Off ENDON
Rule1 1
```

*Ajuste os valores `80` (nível baixo) e `30` (nível cheio) conforme a altura real da sua caixa d’água.*

- Coloque **IP estático** no módulo:

 ```
 IPAddress1 192.168.3.102
 IPAddress2 192.168.3.1
 IPAddress3 255.255.255.0
 IPAddress4 8.8.8.8
 IPAddress5 1.1.1.1
 Restart 1
 ```

## 🛠️ Equipamentos

| Item                         | Quantidade |
|------------------------------|------------|
| TP-Link CPE210               | 2          |
| Injetor PoE 24V              | 2          |
| Switch PoE Passivo 24v       | 1          |
| Sonoff RE5V1C (original)     | 1          |
| Sonoff RE5V1C com Tasmota    | 2          |
| Sensor RCWL-1655 (JSN-SR04T) | 1          |
| Caixa hermética              | 1          |
| Protetor Eletrônico          | 1          |
| Fontes e cabos               | Conforme necessidade |

## ✅ Resultado Esperado

- Acionamento da bomba totalmente automatizado e remoto.
- Rede 100% local (sem internet obrigatória).
- Visualização via app eWeLink do estado atual da bomba.
- Fácil manutenção e expansão futura.

## 🧠 Observação final

Projeto simples, funcional e econômico. Ideal para áreas rurais ou locais de difícil cabeamento.
