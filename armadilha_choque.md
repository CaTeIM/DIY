# ⚡🚨 Projeto: Armadilha de Choque Controlada (Tasmota + HA)

## 📦 Descrição Geral

Sistema de proteção ativa usando uma malha eletrificada de 110V/127V. O controle é feito via Sonoff RE5V1C (com Tasmota) e um sensor PIR DYP-ME003 (ou HC-SR501). O acionamento é automatizado localmente (Edge) e o agendamento de ativação/desativação é feito via Home Assistant.

**Recursos de Segurança:**
- Lâmpada incandescente em série para limitar corrente (evita curto-circuito fatal e desarme de disjuntor).
- Regra de loop restritivo: Choque máximo de 3s seguido de pausa obrigatória de 10s.
- Inicialização segura: Em caso de queda de energia, o sistema volta 100% desarmado.

## 🧰 Materiais Necessários

- 1x Sonoff RE5V1C (com Tasmota)
- 1x Sensor PIR DYP-ME003 (ou HC-SR501)
- 1x Fonte 5V (para alimentar o Sonoff)
- 1x Bocal de lâmpada + Lâmpada Incandescente (60W a 100W)
- Fios rígidos de cobre (para a malha)
- Placa isolante (PVC, Acrílico ou Madeira seca)
- Cabos elétricos padrão e plugue de tomada

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
- [Firmware Tasmota-Sensors](https://ota.tasmota.com/tasmota/release/tasmota-sensors.bin)

## 🔥 Flash do Tasmota

1. Abra o Tasmotizer
2. Selecione a porta COM
3. Marque: `Erase before flashing`
4. Marque: `Self-resetting device`
5. Selecione `tasmota-sensors.bin`
6. Clique em **Tasmotize!**
7. Aguarde e desconecte

## ⚙️ Configuração Tasmota

1. Ligue o Sonoff
2. Conecte no Wi-Fi "tasmota-XXXX" e acesse [http://192.168.4.1](http://192.168.4.1)
3. Configure sua rede Wi-Fi e acesse o IP atribuído pelo roteador.
4. Vá em **Configuration > Configure Other** e cole o template do Sonoff RE5V1C:
   ```json
   {"NAME":"Sonoff RE5V1C","GPIO":[17,255,255,255,255,255,0,0,21,56,0,0,0],"FLAG":0,"BASE":18}
   ```
5. Marque **Activate** e salve.
6. Coloque **IP estático** acessando o **Console** (ajuste `192.168.68.X` para a sua rede):
   ```text
   IPAddress1 192.168.68.X
   IPAddress2 192.168.68.1
   IPAddress3 255.255.255.0
   IPAddress4 8.8.8.8
   IPAddress5 1.1.1.1
   Restart 1
   ```
7. Em **Configuration > Configure Module**, defina o pino do sensor (ele continua selecionado como Generic):
   - `GPIO3 (RX)`: `Switch1`
   *(O GPIO12 de Relay já estará configurado pelo template acima)*
8. Em **Configuration > Configure MQTT**:
   - Configure os dados do seu broker Mosquitto (Host, Porta, Usuário, Senha).
   - Topic: `armadilha_choque`
9. No **Console** (Travas de Segurança):
   ```text
   PowerOnState 0
   SetOption65 1
   TelePeriod 10
   PulseTime1 30
   SwitchMode1 1
   SetOption114 1
   Timezone -3
   SerialLog 0
   Mem1 0
   ```
   - `SwitchMode1 1` = modo Follow (o Switch acompanha o sinal HIGH/LOW do PIR)
   - `SetOption114 1` = desacopla o Switch do Relay (o PIR não aciona o relé diretamente — quem aciona é a Rule)

## 🧱 Montagem Física

### 1. O Cérebro (5V)
- Ligar a Fonte 5V nos pinos `5V` e `GND` do Sonoff.
- Ligar o DYP-ME003:
  - `VCC` -> `5V` do Sonoff (o sensor aceita 4.5V~20V)
  - `GND` -> `GND`
  - `OUT` -> `RX` (GPIO3) do Sonoff (saída digital 3.3V, compatível direto com o ESP8266)

> [!NOTE]
> O DYP-ME003 possui dois trimpots na placa:
> - **Sensibilidade (SX):** ajusta o alcance da detecção (3m a ~7m). Gire no sentido horário para aumentar.
> - **Delay (TX):** ajusta por quanto tempo a saída fica em HIGH após a detecção (~5s a ~300s).

### 2. O Músculo (110V) e a Malha
A lâmpada atua como um resistor de proteção. Se a malha fechar curto contínuo, a lâmpada apenas acende, protegendo o relé do Sonoff (que suporta pouca amperagem) e a rede da casa.

1. Pegue a Fase da tomada e ligue em um dos lados do bocal da lâmpada.
2. O outro lado do bocal vai para o borne **COM** do relé do Sonoff.
3. Do borne **NO** do relé, puxe o fio que será a Fase da malha.
4. O Neutro da tomada vai direto para a malha.
5. Na placa isolante, trance os fios rígidos paralelamente com 1 a 1.5cm de distância: Fase, Neutro, Fase, Neutro.

## 🧠 Lógica de Acionamento (Rules)

Para que a placa funcione de forma independente do Wi-Fi na hora de atirar, a regra fica salva no próprio Tasmota.

No **Console**, cole a regra e ative:

```text
Rule1 ON Switch1#state=1 DO IF (%mem1%==0) Mem1 1; Power1 1; RuleTimer1 10 ENDIF ENDON ON Rules#Timer=1 DO Mem1 0 ENDON
Rule1 1
```

*Funcionamento: Quando o PIR detecta movimento (`Switch1#state=1`) e o sistema está pronto (`Mem1=0`), ele trava (`Mem1=1`), aciona o relé (choque de 3s via `PulseTime1 30`) e inicia o timer de cooldown de 10s. Após os 10s, o sistema destrava (`Mem1=0`). Qualquer nova detecção durante o cooldown é ignorada pela condição `IF`.*

*Ciclo completo: **Detecção PIR → 3s choque → 10s pausa → pronto***

## 🏠 Integração Home Assistant (Agendamento)

A armadilha deve ficar ativa apenas durante a madrugada. A automação abaixo arma (liga a Rule1) às 21h30 e desarma às 4h50 enviando comandos MQTT.

Adicione esta automação no seu HA (`automations.yaml` ou via interface):

```yaml
alias: "Armadilha Choque"
description: "Ativa a regra do Tasmota às 21h30 e desativa às 4h50"
trigger:
  - platform: time
    at: "21:30:00"
    id: "ativar"
  - platform: time
    at: "04:50:00"
    id: "desativar"
action:
  - choose:
      - conditions:
          - condition: trigger
            id: "ativar"
        sequence:
          - service: mqtt.publish
            data:
              topic: cmnd/armadilha_choque/Rule1
              payload: "1"
      - conditions:
          - condition: trigger
            id: "desativar"
        sequence:
          - service: mqtt.publish
            data:
              topic: cmnd/armadilha_choque/Rule1
              payload: "0"
mode: single
```

## ⚠️ Aviso de Segurança Crítico

Este projeto envolve alta tensão (110V/127V) e pode causar ferimentos graves ou morte se manuseado incorretamente. O autor não se responsabiliza por danos materiais ou pessoais decorrentes do uso ou mau uso deste projeto. Prossiga por sua conta e risco.
