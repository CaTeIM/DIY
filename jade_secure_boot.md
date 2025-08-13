# 🔐 Carteira Jade ₿🪙 na TTGO T-Display com Secure Boot (Versão Definitiva)

Este tutorial mostra o processo completo para instalar e customizar o firmware da [Blockstream Jade](https://github.com/Blockstream/Jade) em uma placa **TTGO T-Display de 16MB** (ou clones compatíveis). Passamos por uma longa jornada de debugging para fazer tudo funcionar, e este guia inclui todas as correções para evitar os erros mais comuns.

O resultado é uma hardware wallet DIY robusta, segura e com acabamento profissional.

## 🧰 Materiais Necessários

### Hardware

* 1x Placa [LILYGO TTGO T-Display (ESP32)](https://s.click.aliexpress.com/e/_mqRUCxl) ou clone com **16MB de Flash**
* 1x Cabo USB-C de dados de boa qualidade

### Software

* [ESP-IDF Tools Installer for Windows](https://github.com/espressif/idf-installer/releases/)
* [Git](https://git-scm.com/downloads)
* Um editor de texto (ex: VS Code, Notepad++)

## 🛠️ Parte 1: Preparando o Ambiente (Do Zero)

### 1.1. Verificar a Versão Correta do ESP-IDF

Para evitar erros de compilação, é **crucial** usar a mesma versão do ESP-IDF para a qual o projeto Jade foi desenvolvido.

1.  **Acesse o repositório** oficial da [Blockstream Jade no GitHub](https://github.com/Blockstream/Jade).
2.  **Navegue até o arquivo** [`.github/workflows/github-actions-test.yml`](https://github.com/Blockstream/Jade/blob/master/.github/workflows/github-actions-test.yml).
3.  **Abra o arquivo** e procure pela linha `esp_idf_version:`. Para este guia, usaremos a **v5.4**.

### 1.2. Instalar o ESP-IDF v5.4

1.  **Limpeza:** Garanta que desinstalou versões antigas do ESP-IDF e apagou a pasta `C:\Espressif`.
2.  **Baixe o Instalador Offline:** [**ESP-IDF v5.4 Offline Installer**](https://github.com/espressif/idf-installer/releases/download/offline-5.4/esp-idf-tools-setup-offline-5.4.exe)
3.  **Execute a Instalação:** Siga os passos do instalador. Ao final, marque a opção para abrir o terminal.
4.  **Abra o Terminal Correto:** Após instalar, procure por **"ESP-IDF 5.4 CMD"** no seu menu Iniciar. **Use sempre este terminal**.

### 1.3. Baixar o Código da Jade

Dentro do terminal do **ESP-IDF 5.4 CMD**:

1.  **Navegue para a pasta de frameworks:**
    ```powershell
    cd C:\Espressif\frameworks
    ```
2.  **Clonar o repositório:**
    ```powershell
    git clone https://github.com/Blockstream/Jade.git
    ```
3.  **Entrar na pasta:**
    ```powershell
    cd Jade
    ```
4.  **Baixar as dependências (submódulos):**
    ```powershell
    git submodule update --init --recursive
    ```

## 🔥 Parte 2: Customizar, Compilar e Gravar

### 2.1. Aplicar Configuração Base da Placa

1.  **Limpe configs antigas (por segurança):**
    ```powershell
    del sdkconfig
    ```
2.  **Copie a configuração da TTGO T-Display:**
    ```powershell
    copy configs\sdkconfig_display_ttgo_tdisplay.defaults sdkconfig.defaults
    ```

### 2.2. 🩹 Corrigir a Configuração Base (`sdkconfig.defaults`)

O arquivo de configuração padrão que copiamos contém erros para clones de 16MB. Vamos corrigi-los:

1.  **Abra o arquivo** `sdkconfig.defaults` na pasta `C:\Espressif\frameworks\Jade`.
2.  **Comente** (adicione um `#` no início) as duas linhas a seguir:
    * `CONFIG_ESP_CONSOLE_NONE=y`
    * `CONFIG_ESPTOOLPY_FLASHSIZE_4MB=y`

    **Elas devem ficar assim:**
    ```
    # CONFIG_ESP_CONSOLE_NONE=y
    # CONFIG_ESPTOOLPY_FLASHSIZE_4MB=y
    ```
3.  Agora, vá até o **final do arquivo** e adicione estas linhas para forçar a configuração correta:
    ```
    # CORREÇÃO: Força o console para UART0 para evitar log corrompido
    CONFIG_ESP_CONSOLE_UART_DEFAULT=y
    CONFIG_ESP_CONSOLE_UART_NUM=0
    
    # CORREÇÃO: Define o tamanho correto da flash para 16MB
    CONFIG_ESPTOOLPY_FLASHSIZE_16MB=y
    ```
4.  **Salve e feche** o arquivo.

### 2.3. 🩹 Correções Críticas para Clones (Log e Bluetooth)

Agora vamos aplicar as correções que resolvem o log corrompido e a instabilidade do Bluetooth.

#### 2.3.1. Correção do Log (Cirurgia no Código)

1.  **Abra o arquivo** `C:\Espressif\frameworks\Jade\main\main.c`.
2.  **Encontre a função `boot_process(void)`** (por volta da linha 179).
3.  **Comente a linha** `esp_log_set_vprintf(serial_logger);` para desativar o logger customizado da Jade.

    **Antes:**
    ```c
    #ifndef CONFIG_LOG_DEFAULT_LEVEL_NONE
        esp_log_set_vprintf(serial_logger);
    #endif
    ```
    **Depois (o jeito certo):**
    ```c
    #ifndef CONFIG_LOG_DEFAULT_LEVEL_NONE
        // esp_log_set_vprintf(serial_logger);
    #endif
    ```
4.  **Salve e feche** o arquivo `main.c`.

#### 2.3.2. Correção do Bluetooth (`menuconfig`)

1.  **Abra o Menu de Configuração:**
    ```powershell
    idf.py menuconfig
    ```
2.  **Navegue até** `Component config ---> Bluetooth ---> NimBLE Options`.
3.  **Faça estas três mudanças** para deixar o Bluetooth mais estável, como no exemplo que funcionou:
    * Mude o valor de `(517) Preferred MTU size in octets` para **`256`**.
    * **Desmarque** a opção `[*] Persist BLE bonding keys in NVS` (deve ficar `[ ]`).
    * **Desmarque** a opção `[*] Blob transfer` (deve ficar `[ ]`).
4.  **Salve e Saia:** Tecle `S`, depois `Enter`, e `Q`.

### 2.4. Criar o Mapa de Partição para 16MB

1.  **Copie o arquivo de partição padrão:**
    ```powershell
    copy partitions.csv partitions_custom.csv
    ```
2.  **Edite o `partitions_custom.csv`**, apague todo o conteúdo e cole o seguinte:
    ```csv
    # Espressif ESP32 Partition Table - CUSTOM 16MB
    # Name,    Type, SubType, Offset,  Size, Flags
    nvs,       data, nvs,     0xA000,  0x4000,
    otadata,   data, ota,     0xE000,  0x2000, encrypted
    ota_0,     app,  ota_0,   ,        6144K,
    ota_1,     app,  ota_1,   ,        6144K,
    nvs_key,   data, nvs_keys,,        4K, encrypted
    ```
3.  Salve e feche o arquivo.

### 2.5. Configurar o Restante do Projeto (`menuconfig`)

1.  **Abra o Menu de Configuração novamente:**
    ```powershell
    idf.py menuconfig
    ```
2.  **Ative o Secure Boot (Opcional):**
    * Vá em `Security features` -> `[*] Enable hardware Secure Boot in bootloader`.
    * Deixe `Secure bootloader mode (One-time flash)`.
    * Marque `[*] Sign binaries during build`.
3.  **Ajuste o Tamanho da Flash:**
    * Vá em `Serial flasher config` -> `Flash size (4 MB) --->`.
    * Selecione **`(X) 16 MB`**.
4.  **Aponte para o Mapa de Partição:**
    * Vá em `Partition Table` -> `Partition Table (Custom partition CSV) --->`.
    * Marque `(X) Custom partition table CSV`.
    * No campo `Custom partition CSV file`, digite: **`partitions_custom.csv`**.
5.  **Salve e Saia:** Tecle `S`, depois `Enter`, e `Q`.

### 2.6. Compilar e Gravar

1.  **Limpe compilações antigas:**
    ```powershell
    idf.py fullclean
    ```
2.  **Se estiver usando Secure Boot, gere a chave:**
    ```powershell
    espsecure.py generate_signing_key secure_boot_signing_key.pem
    ```
    > 🚨 **AVISO IRREVERSÍVEL!** 🚨
    > O arquivo `secure_boot_signing_key.pem` é a chave mestra da sua placa. Um resumo dela será **permanentemente gravado** no hardware no próximo passo.
    > - **FAÇA BACKUP DESTE ARQUIVO!**
    > - Se você perder esta chave, **NUNCA MAIS poderá atualizar o firmware desta placa**.

3.  **Grave tudo na placa** (substitua `COM5` pela sua porta):
    * **Sem Secure Boot (Recomendado):**
        ```powershell
        idf.py -p COM5 flash
        ```
    * **Com Secure Boot:**
        ```powershell
        # Primeiro o bootloader (passo irreversível)
        idf.py -p COM5 bootloader-flash
        # Depois o resto
        idf.py -p COM5 app-flash partition-table-flash
        ```

## 🐞 Troubleshooting: Resolvendo Erros Comuns

#### Erro de Rede ou Falha ao Criar o PIN (O Problema do "Pin Server")

* **Sintoma:** Ao tentar criar a carteira pela primeira vez via Bluetooth, o processo falha depois de você criar o PIN, com um erro de rede no celular.
* **Causa:** A Jade, por segurança, tenta contatar um servidor da Blockstream pela internet do seu celular durante a criação do PIN.
* **Solução:** Garanta que seu celular esteja com uma **conexão de internet estável e ativa (Wi-Fi ou 4G/5G)** durante o processo de inicialização da carteira.

#### Tela Maluca ao Conectar no PC (O Bug do "Aperto Fantasma")

* **Sintoma:** A tela da Jade fica avançando sozinha, como se um botão estivesse pressionado, **apenas** quando você tenta conectar com um app no PC (Blockstream Green, Sparrow).
* **Causa:** É um bug de hardware. O app no PC ativa uma linha do cabo USB que é fisicamente ligada ao pino `GPIO 0` na placa. O firmware da Jade usa esse pino como o botão principal.
* **Solução:** A solução ideal (inverter os botões via software) ainda não foi encontrada de forma estável. A melhor abordagem é **inicializar e usar a Jade via Bluetooth**, evitando o bug da conexão USB.

## ✅ Verificação Final

A placa irá reiniciar com o firmware da Jade. Agora você pode conectar seu celular via Bluetooth, criar sua carteira e usá-la. Operação concluída com sucesso!

## 🤓 Nerdologia: Os Bastidores do Debugging (Como Chegamos nas Soluções)

Essa jornada foi longa. Veja como isolamos os problemas:

1.  **Teste do `hello_world`:** Primeiro, compilamos um "Olá, Mundo" padrão. O log apareceu limpo. Isso provou que a placa, o cabo e o ambiente ESP-IDF estavam **perfeitos**. A culpa era do firmware da Jade.
2.  **Correção do Log:** Ao ver que o log da Jade era corrompido, mas o do `hello_world` não, concluímos que a Jade usava um sistema de log customizado e bugado. A solução foi "operar" o `main.c` e desativá-lo.
3.  **Teste do `bleprph`:** Compilamos um exemplo de Bluetooth padrão do ESP-IDF. A conexão ficou 100% estável. Isso provou que o **hardware do Bluetooth era bom**, e que o bug estava nas configurações ou no código da Jade.
4.  **Comparação dos `sdkconfig`:** Com a prova de que o `bleprph` funcionava, comparamos seu arquivo de configuração com o da Jade, linha por linha. Foi assim que encontramos as diferenças cruciais (MTU, NVS, Blob Transfer) e as aplicamos na Jade para consertar a instabilidade.

*Tutorial criado para o repositório* [*DIY na Prática*](https://github.com/CaTeIM/DIY). *Adaptado e testado para entusiastas de hardware e Bitcoin.* ₿🪙🚀
