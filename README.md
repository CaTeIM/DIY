[![Android](https://img.shields.io/badge/Android-3DDC84?logo=android&logoColor=white)](https://www.android.com/) [![Tasmota](https://img.shields.io/badge/Tasmota-00A6A6?logo=tasmota&logoColor=white)](https://tasmota.github.io/docs/) [![ESP8266](https://img.shields.io/badge/ESP8266-E73525?logo=espressif&logoColor=white)](https://www.espressif.com/en/products/socs/esp8266) [![Wi-Fi](https://img.shields.io/badge/Wi--Fi-0078D4?logo=wifi&logoColor=white)](https://www.wi-fi.org/) [![IoT](https://img.shields.io/badge/IoT-20948B?logo=homeassistantcommunitystore&logoColor=white)](https://en.wikipedia.org/wiki/Internet_of_things) [![DIY](https://img.shields.io/badge/DIY-Faça_Você_Mesmo-orange)](https://en.wikipedia.org/wiki/Do_it_yourself) [![License: MIT](https://img.shields.io/badge/license-MIT-blue)](./LICENSE)

# 🚀 Soluções DIY na Prática

Um repositório para guardar e compartilhar projetos de automação e soluções tecnológicas "faça você mesmo" (DIY). A ideia aqui é resolver problemas do dia a dia de forma criativa e de baixo custo, sem frescura. 

Se dá pra automatizar com um módulo `low-cost`, um sensor e um pouco de código, o lugar é aqui! 👨‍💻🔧

## 📂 Projetos

Aqui estão os projetos documentados até agora. Cada link contém um `README` com o passo a passo completo.

| Projeto                                                         | Descrição Resumida                                                                                             | Tecnologias Principais                                           |
| :-------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------- | :--------------------------------------------------------------- |
| **[🔐 Jade HW com Secure Boot](./jade_secure_boot.md)** | Transforma uma placa TTGO T-Display em uma Hardware Wallet segura, ativando o Secure Boot v2 do ESP32. | `Blockstream Jade`, `ESP-IDF`, `TTGO T-Display`, `Secure Boot v2` |
| **[🚨 Sirene Ativada por Chamada](./sirene_por_chamada.md)** | Aciona uma sirene (ou qualquer outra coisa) automaticamente quando o celular Android recebe uma ligação. | `Sonoff RE5V1C`, `Tasmota`, `Tasker`, `Android` |
| **[💧 Bomba d'Água Automática](./bomba_dagua_automatica.md)** | Controla uma bomba d'água remotamente com base no nível do reservatório, usando uma rede Wi-Fi local ponto a ponto. | `Sonoff RE5V1C`, `Tasmota`, `Sensor HC-SR04`, `TP-Link CPE` |

## 🛠️ Tecnologias no DNA do Repo

A maioria dos projetos por aqui gira em torno destas tecnologias:

-   **Hardware:**
    -   📦 **Sonoff:** Especialmente o versátil `RE5V1C` no modo "faça você mesmo".
    -   🧠 **ESP8266/ESP32:** O cérebro por trás de muitos dispositivos IoT de baixo custo.
    -   📡 **Sensores:** Como o ultrassônico `HC-SR04` para medir distâncias.
    -   📶 **Rede:** Antenas `TP-Link CPE` para links Wi-Fi de longa distância e equipamentos de rede local.
-   **Software & Firmware:**
    -   ⚫ **Tasmota:** O firmware open-source que liberta o poder dos dispositivos Sonoff/ESP.
	-   ⚫ **ESP-IDF:** O framework oficial da Espressif para desenvolvimento avançado em ESP32.
    -   🤖 **Tasker:** Para criar automações complexas no Android, servindo como gatilho ou interface.
    -   🌐 **Comandos HTTP/WebSend:** A cola que une os dispositivos na rede local de forma simples e direta.

## 💬 Dúvidas ou Sugestões?

Se tiver qualquer dúvida, encontrar um problema ou tiver uma sugestão de projeto, sinta-se à vontade para abrir uma **[Issue](https://github.com/CaTeIM/DIY/issues)**. Ficarei feliz em ajudar!

---

*Repositório mantido com café e curiosidade.* ☕