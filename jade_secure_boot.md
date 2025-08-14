# 🔐 Carteira Jade ₿🪙 na TTGO T-Display com Secure Boot

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

### 2.2. 🩹 Corrigindo a Lógica dos Botões (Cirurgia no Kconfig)

O perfil padrão da TTGO T-Display vem com a lógica dos botões invertida, o que causa o bug do "aperto fantasma" na conexão USB. Vamos corrigir isso na fonte, antes de compilar.

1.  **Abra o arquivo** `C:\Espressif\frameworks\Jade\main\Kconfig.projbuild` no seu editor de texto.
2.  **Procure (`Ctrl+F`)** pelo termo `INPUT_BTN_A`.
3.  Você encontrará um bloco de código que define os botões. **Altere os valores `default`** para inverter os pinos dos botões A e B.

    **Antes:**
    ```
        config INPUT_BTN_A
            int "BTN A"
            default 0 if BOARD_TYPE_TTGO_TDISPLAY || BOARD_TYPE_TTGO_TDISPLAYS3
        config INPUT_BTN_B
            int "BTN B"
            default 35 if BOARD_TYPE_TTGO_TDISPLAY || BOARD_TYPE_M5_STICKC_PLUS_2
    ```

    **Depois (o jeito certo):**
    ```
        config INPUT_BTN_A
            int "BTN A"
            default 35 if BOARD_TYPE_TTGO_TDISPLAY || BOARD_TYPE_TTGO_TDISPLAYS3
        config INPUT_BTN_B
            int "BTN B"
            default 0 if BOARD_TYPE_TTGO_TDISPLAY || BOARD_TYPE_M5_STICKC_PLUS_2
    ```
4.  **Salve e feche** o arquivo `Kconfig.projbuild`.

### 2.3. 🎨 Adicionando a Logo da Blockstream (Cirurgia no Código)

Por padrão, o firmware só mostra a logo de splash em placas oficiais da Jade. Vamos adicionar a TTGO T-Display na "lista VIP".

#### 2.3.1. Modificando o `CMakeLists.txt`

1.  **Abra o arquivo** `C:\Espressif\frameworks\Jade\main\CMakeLists.txt`.
2.  **Encontre a linha** (por volta da linha 12) que começa com `if (CONFIG_BOARD_TYPE_JADE...`.
3.  **Adicione a nossa placa** no final da condição.

    **A linha deve ficar assim:**
    ```cmake
    if (CONFIG_BOARD_TYPE_JADE OR CONFIG_BOARD_TYPE_JADE_V1_1 OR CONFIG_BOARD_TYPE_JADE_V2 OR CONFIG_BOARD_TYPE_TTGO_TDISPLAY)
    ```
4.  **Salve e feche** o arquivo.

#### 2.3.2. Modificando o `gui.c`

1.  **Abra o arquivo** `C:\Espressif\frameworks\Jade\main\gui.c`.
2.  **Encontre as DUAS linhas** (por volta das linhas 2594 e 2606) que começam com `#if defined(CONFIG_BOARD_TYPE_JADE)...`.
3.  **Adicione a nossa placa** no final da condição em **AMBAS** as linhas.

    **As duas linhas devem ficar assim:**
    ```c
    #if defined(CONFIG_BOARD_TYPE_JADE) || defined(CONFIG_BOARD_TYPE_JADE_V1_1) || defined(CONFIG_BOARD_TYPE_JADE_V2) || defined(CONFIG_BOARD_TYPE_TTGO_TDISPLAY)
    ```
4.  **Salve e feche** o arquivo.

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

### 2.5. Configurar o Projeto (`menuconfig`)

1.  **Abra o Menu de Configuração:**
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
* **Causa:** É um bug de hardware. O app no PC ativa uma linha do cabo USB que é fisicamente ligada ao pino `GPIO 0` na placa. O firmware da Jade usa esse pino como o botão principal. A correção que fizemos no passo 2.2 inverte os botões para contornar esse problema.

## ✅ Verificação Final

A placa irá reiniciar com o firmware da Jade. Agora você pode conectar seu celular via Bluetooth, criar sua carteira e usá-la. Operação concluída com sucesso!

## 🤓 Nerdologia: Os Bastidores do Debugging (Como Chegamos nas Soluções)

Essa jornada foi longa. Veja como isolamos os problemas:

1.  **Teste do `hello_world`:** Primeiro, compilamos um "Olá, Mundo" padrão. O log apareceu limpo. Isso provou que a placa, o cabo e o ambiente ESP-IDF estavam **perfeitos**. A culpa era do firmware da Jade.
2.  **Correção do Log:** Ao ver que o log da Jade era corrompido, mas o do `hello_world` não, concluímos que a Jade usava um sistema de log customizado e bugado. A solução foi "operar" o `main.c` e desativá-lo.

*Tutorial criado para o repositório* [*DIY na Prática*](https://github.com/CaTeIM/DIY). *Adaptado e testado para entusiastas de hardware e Bitcoin.* ₿🪙🚀
