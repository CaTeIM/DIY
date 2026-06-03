# 📲🚨 Automação com Sonoff RE5V1C, Tasmota e Tasker para Acionamento de Sirene por Chamada Telefônica

Este projeto permite acionar automaticamente uma sirene conectada ao relé do Sonoff RE5V1C quando seu celular Android recebe uma chamada. O controle é feito via Tasmota + Tasker.

## 🧰 Materiais Necessários

- 1x Sonoff RE5V1C
- 1x Adaptador USB-TTL (ex: CH341A Pro)
- Fios/jumpers fêmea-fêmea
- Computador com Windows
- Cabo microUSB
- Ferro de solda (se necessário)
- Firmware [Tasmota](https://ota.tasmota.com/tasmota/release/tasmota.bin)
- Celular Android com [Tasker](https://play.google.com/store/apps/details?id=net.dinglisch.android.taskerm)

## ⚡ 1. Preparando o Sonoff para o Flash

### 🔎 1.1. Identificação dos Pinos

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

### 🔗 1.2. Ligações

| CH341A | Sonoff RE5V1C  |
|--------|----------------|
| GND    | GND            |
| 3.3V   | 3V3            |
| TXD    | ERX            |
| RXD    | ETX            |

### 🕹️ 1.3. Modo Bootloader

1. Mantenha o botão do RE5V1C pressionado
2. Conecte o USB-TTL ao PC
3. Aguarde 5s e solte

## 💻 2. Instalando Drivers e Software

- [Driver CH341A](https://wch.cn/downloads/CH341SER_EXE.html)
- [Tasmotizer](https://github.com/tasmota/tasmotizer/releases)
- [Firmware Tasmota](https://ota.tasmota.com/tasmota/release/tasmota.bin)

## 🔥 3. Flash do Tasmota

1. Abra o Tasmotizer
2. Selecione a porta COM
3. Marque: `Erase before flashing`
4. Marque: `Self-resetting device`
5. Selecione o `tasmota.bin`
6. Clique em **Tasmotize!**
7. Aguarde e desconecte

## 📡 4. Configurando o Tasmota

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
``` 

10. Coloque **IP estático** no módulo:

```
IPAddress1 192.168.3.10
IPAddress2 192.168.3.1
IPAddress3 255.255.255.0
IPAddress4 8.8.8.8
IPAddress5 1.1.1.1
Restart 1
```

## 🤖 5. Testando o Relé

Acesse a interface web do Tasmota e clique em **Toggle**.

## 🔗🤳 6. Automação com Tasker

### ✅ Requisitos

- Tasker instalado
- IP fixo para o Sonoff RE5V1C

### a) Perfil: **Telefone Chamando** 📲

- Evento: Telefone > Telefone Chamando
- Tarefa: `Sirene_ON`
  - HTTP Get → `http://IP_DO_TASMOTA/cm?cmnd=Power%20On`
- Exit Task: `Sirene_OFF_20s`
  - Esperar 20s
  - HTTP Get → `http://IP_DO_TASMOTA/cm?cmnd=Power%20Off`

### b) Perfil: **Chamada em andamento** ☎️

- Evento: Telefone > Chamada em andamento
- Tarefa: `Sirene_OFF`
  - HTTP Get → `http://IP_DO_TASMOTA/cm?cmnd=Power%20Off`

### c) Perfil: **Chamada Perdida** ❌

- Evento: Telefone > Chamada perdida
- Tarefa: `Sirene_OFF`
  - HTTP Get → `http://IP_DO_TASMOTA/cm?cmnd=Power%20Off`

## 🔁 Fluxo Completo

| Ação do Celular          | Ação do Sonoff    |
|--------------------------|-------------------|
| Recebe chamada 📲        | Liga sirene 🚨   |
| Atende / Rejeita / Perde | Desliga sirene 📴 |

## 📝 Considerações Finais

- Teste tudo separadamente
- Use IP fixo no Tasmota
- Confira bem as ligações no flash
- Pode acionar outros dispositivos também!

💡 *Este projeto foi construído e documentado com base em uma necessidade real, para automação prática e útil no dia a dia.* 🚀
