# ⚡🚨 Projeto: Armadilha de Choque Controlada (Tasmota + HA)

## 📦 Descrição Geral

Sistema de proteção ativa usando uma malha eletrificada de 110V/127V. O controle é feito via Sonoff RE5V1C (com Tasmota) e um sensor ultrassônico RCWL-1655 (frequentemente integrado no módulo JSN-SR04T V3.0). O acionamento é automatizado localmente (Edge) e o agendamento de ativação/desativação é feito via Home Assistant.

**Recursos de Segurança:**
- Lâmpada incandescente em série para limitar corrente (evita curto-circuito fatal e desarme de disjuntor).
- Regra de loop restritivo: Choque máximo de 3s seguido de pausa obrigatória de 10s.
- Inicialização segura: Em caso de queda de energia, o sistema volta 100% desarmado.

## 🧰 Materiais Necessários

- 1x Sonoff RE5V1C (com Tasmota)
- 1x Sensor Ultrassônico RCWL-1655 (JSN-SR04T V3.0)
- 1x Fonte 5V (para alimentar o Sonoff)
- 1x Bocal de lâmpada + Lâmpada Incandescente (60W a 100W)
- Fios rígidos de cobre (para a malha)
- Placa isolante (PVC, Acrílico ou Madeira seca)
- Cabos elétricos padrão e plugue de tomada

## 🧱 Montagem Física

### 1. O Cérebro (5V)
- Ligar a Fonte 5V nos pinos `5V` e `GND` do Sonoff.
- Ligar o RCWL-1655:
  - `VCC` -> `5V`
  - `GND` -> `GND`
  - `Trig` -> `RX` do Sonoff
  - `Echo` -> `TX` do Sonoff

### 2. O Músculo (110V) e a Malha
A lâmpada atua como um resistor de proteção. Se a malha fechar curto contínuo, a lâmpada apenas acende, protegendo o relé do Sonoff (que suporta pouca amperagem) e a rede da casa.

1. Pegue a Fase da tomada e ligue em um dos lados do bocal da lâmpada.
2. O outro lado do bocal vai para o borne **COM** do relé do Sonoff.
3. Do borne **NO** do relé, puxe o fio que será a Fase da malha.
4. O Neutro da tomada vai direto para a malha.
5. Na placa isolante, trance os fios rígidos paralelamente com 1 a 1.5cm de distância: Fase, Neutro, Fase, Neutro.

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
- [Firmware Tasmota](https://ota.tasmota.com/tasmota/release/tasmota.bin)

## 🔥 Flash do Tasmota

1. Abra o Tasmotizer
2. Selecione a porta COM
3. Marque: `Erase before flashing`
4. Marque: `Self-resetting device`
5. Selecione o `tasmota.bin`
6. Clique em **Tasmotize!**
7. Aguarde e desconecte

## ⚙️ Configuração Tasmota

1. Em **Configuration > Configure Module**:
   - Module type: `Generic (18)`
   - `GPIO1 (TX)`: `SR04 Echo` *(Selecione SR04 mesmo sendo o RCWL-1655)*
   - `GPIO3 (RX)`: `SR04 Trig`
   - `GPIO12`: `Relay 1`
2. Em **Configuration > Configure MQTT**:
   - Configure os dados do seu broker Mosquitto (Host, Porta, Usuário, Senha).
   - Topic: `armadilha_choque`
3. No **Console** (Travas de Segurança):
   ```text
   PowerOnState 0
   SetOption65 1
   TelePeriod 10
   PulseTime1 30
   Mem1 0
   ```
> [!WARNING]
> **Modo de Operação do RCWL-1655 (UART vs GPIO)**
> Para que o Tasmota leia o sensor diretamente com a configuração `SR04` acima, o RCWL-1655 **deve** estar operando no **Modo 0 (GPIO / Ping)**.
> Se o sensor não estiver enviando as leituras de distância, é muito provável que ele tenha vindo de fábrica configurado no **Modo UART** (Serial), o que é comum. Para corrigir isso e torná-lo 100% compatível com o comportamento do HC-SR04 no Tasmota, basta remover o resistor SMD de seleção de modo (indicado como **R7** no datasheet, ou M1/R27 dependendo da revisão da placa) para deixá-lo em "circuito aberto" (NC - Not Connected).

## 🧠 Lógica de Acionamento (Rules)

Para que a placa funcione de forma independente do Wi-Fi na hora de atirar, a regra fica salva no próprio Tasmota.

A regra abaixo utiliza o gatilho `SR04#Distance`, pois o Tasmota trata o RCWL-1655 (em Modo 0) internamente usando o driver padrão do SR04.

No **Console**, cole a regra e ative:

```text
Rule1 ON SR04#Distance<80 DO IF (%mem1%==0) Mem1 1; RuleTimer1 2 ENDIF ENDON ON Rules#Timer=1 DO Power1 1; RuleTimer2 10 ENDON ON Rules#Timer=2 DO Mem1 0 ENDON
Rule1 1
```

*Funcionamento: Se algo chegar a menos de 80cm e o sistema estiver pronto (Mem1=0), ele trava (Mem1=1) e inicia um timer de 2s (RuleTimer2). Após os 2s, o relé é ativado (choque de 3s via PulseTime) e o timer de reset (RuleTimer1 10s) começa. Após os 10s, o sistema destrava (Mem1=0) para o próximo ciclo.*

*Ciclo completo: **Detecção → 2s espera → 3s choque → 10s pausa → pronto***

## 🏠 Integração Home Assistant (Agendamento)

A armadilha deve ficar ativa apenas durante a madrugada. A automação abaixo arma (liga a Rule1) às 22h e desarma às 04h50 enviando comandos MQTT.

Adicione esta automação no seu HA (`automations.yaml` ou via interface):

```yaml
alias: "Armadilha Choque"
description: "Ativa a regra do Tasmota às 22h e desativa às 04h50"
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
