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

### Ponto C (Sensor)
- Ligar o RCWL-1655 aos pinos `RX`/`TX` do Sonoff.
- Após aplicar o template principal, vá em **Configuration > Configure Module** e defina os pinos no Tasmota:
  - `GPIO1 (TX)`: `SR04 Ech/Rx` *(O Tasmota trata o RCWL-1655 padronizado como SR04)*
  - `GPIO3 (RX)`: `SR04 Tri/Tx`
  *(O GPIO12 de Relay já estará configurado pelo template)*

> [!WARNING]
> **Modo de Operação do RCWL-1655**
> Certifique-se de que o sensor esteja operando no **Modo 0 (GPIO / Ping)**. Se ele não enviar leituras de distância, remova o resistor SMD de seleção de modo (indicado como **R7** ou M1/R27 na placa) para deixá-lo em modo "circuito aberto" (NC), comportando-se igual a um HC-SR04 comum para o Tasmota.

- Regra (O Tasmota trata o RCWL-1655 internamente como SR04):
 ```
 Rule1 ON Tele-SR04#Distance>80 DO WebSend [192.168.3.101] /cm?cmnd=Power1%20On ENDON
 Rule1 1
 ```
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
