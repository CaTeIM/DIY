# ⚡🚨 Projeto: Armadilha de Choque Controlada (Tasmota + HA)

## 📦 Descrição Geral

Sistema de proteção ativa usando uma malha eletrificada de 110V/127V. O controle é feito via Sonoff RE5V1C (com Tasmota) e um sensor PIR DYP-ME003 (ou HC-SR501). O acionamento é automatizado localmente (Edge) e o agendamento de ativação/desativação é feito via Home Assistant.

**Recursos de Segurança:**
- Lâmpada incandescente em série para limitar corrente (evita curto-circuito fatal e desarme de disjuntor).
- Regra de loop restritivo: Choque máximo de 5s seguido de pausa obrigatória de 5s.
- Watchdog automático: se a lógica travar, o Tasmota reinicia sozinho após 8s.
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
   - `GPIO4 (User)` (Pino **RX** físico da placa): `Switch1`
   *(O GPIO12 de Relay já estará configurado pelo template acima)*
8. Em **Configuration > Configure MQTT**:
   - Configure os dados do seu broker Mosquitto (Host, Porta, Usuário, Senha).
   - Topic: `armadilha_choque`
9. No **Console** (Travas de Segurança):
   ```text
   PowerOnState 0
   SetOption65 1
   TelePeriod 10
   PulseTime1 50
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
  - `OUT` -> `RX` do Sonoff (saída digital 3.3V, ligar no pino físico **RX**, que no Tasmota é o **GPIO4**)

> [!IMPORTANT]
> **Calibração obrigatória do DYP-ME003 antes de usar:**
> 
> **Jumper de modo (entre os trimpots):**
> - ⚠️ Posição **`L` (Single Trigger)** — **USE ESTA**. Gera um pulso HIGH por detecção e retorna a LOW. O Tasmota precisa capturar a transição `0→1` para a Rule disparar.
> - ❌ Posição `H` (Repeatable): mantém HIGH enquanto houver movimento contínuo. O sinal nunca cai e a Rule **nunca re-dispara**.
> 
> **Trimpot TX (Delay) — gire totalmente para a ESQUERDA (mínimo, ~5s).**
> - Se estiver no máximo (~300s), o sinal fica HIGH por 5 minutos após cada detecção, bloqueando novos disparos.
> 
> **Trimpot SX (Sensibilidade) — ajuste conforme o alcance desejado (3m a ~7m).**
> 
> **Aguarde 30-60 segundos** após energizar o sensor antes de iniciar testes. O DYP-ME003 precisa se estabilizar.

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
Rule1 ON Switch1#state=1 DO IF (%mem1%==0) Mem1 1; Power1 1; RuleTimer1 5 ENDIF ENDON ON Rules#Timer=1 DO Mem1 0 ENDON ON System#Boot DO Mem1 0 ENDON
Rule1 1
```

*Funcionamento: Quando o PIR detecta movimento (`Switch1#state=1`) e o sistema está pronto (`Mem1=0`), ele trava (`Mem1=1`), aciona o relé (choque de 5s via `PulseTime1 50`) e inicia o timer de cooldown de 5s. Após os 5s, o sistema destrava (`Mem1=0`). Qualquer nova detecção durante o cooldown é ignorada pela condição `IF`.*

*A cláusula `ON System#Boot DO Mem1 0 ENDON` garante que o `Mem1` sempre reinicia em `0` após queda de energia ou reboot, evitando travamento permanente do sistema.*

*Ciclo completo: **Detecção PIR → 5s choque → 5s pausa → pronto***

### Watchdog (Rule2)

Garante que o sistema nunca fique travado. Se o `Mem1` não for resetado dentro de 8s após uma detecção (por falha do Timer1), o Tasmota reinicia automaticamente:

```text
Rule2 ON Switch1#state=1 DO RuleTimer2 8 ENDON ON Rules#Timer=2 DO IF (%mem1%==1) Restart 1 ENDIF ENDON
Rule2 1
```

*Lógica: Em toda detecção de movimento, um timer de 8s é iniciado. Quando disparar, se `Mem1` ainda for `1` (Rule1 não resetou no prazo esperado de 5s), reinicia o dispositivo. Se `Mem1` for `0` (fluxo normal), nada acontece.*

## 🏠 Integração Home Assistant (Agendamento)

A armadilha deve ficar ativa apenas durante a madrugada. A automação abaixo arma (liga a Rule1) às 21h30 e desarma às 4h50 enviando comandos MQTT.

Adicione esta automação no seu HA (`automations.yaml` ou via interface):

> [!NOTE]
> O topic MQTT do Tasmota usa o padrão `armadilha_choque_%06X`, onde `%06X` é substituído pelos últimos 3 bytes do MAC em hex (ex: `armadilha_choque_61E4E8`). Isso garante unicidade entre dispositivos. Verifique o seu em **Configuration > Configure MQTT** e substitua abaixo.

```yaml
alias: "Armadilha Choque"
description: "Ativa as regras do Tasmota às 21h30 e desativa às 4h50"
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
              topic: cmnd/armadilha_choque_61E4E8/Rule1
              payload: "1"
          - service: mqtt.publish
            data:
              topic: cmnd/armadilha_choque_61E4E8/Rule2
              payload: "1"
      - conditions:
          - condition: trigger
            id: "desativar"
        sequence:
          - service: mqtt.publish
            data:
              topic: cmnd/armadilha_choque_61E4E8/Rule1
              payload: "0"
          - service: mqtt.publish
            data:
              topic: cmnd/armadilha_choque_61E4E8/Rule2
              payload: "0"
mode: single
```

## ⚠️ Aviso de Segurança Crítico

Este projeto envolve alta tensão (110V/127V) e pode causar ferimentos graves ou morte se manuseado incorretamente. O autor não se responsabiliza por danos materiais ou pessoais decorrentes do uso ou mau uso deste projeto. Prossiga por sua conta e risco.
