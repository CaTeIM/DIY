# 🔐 Carteira Jade na TTGO T-Display com Secure Boot

Este tutorial mostra o processo completo para instalar e customizar o firmware da [Blockstream Jade](https://github.com/Blockstream/Jade) em uma placa **TTGO T-Display de 16MB**, ativando o **Secure Boot** e removendo o ícone de bateria para um visual mais limpo.

O resultado é uma hardware wallet DIY robusta, segura e com acabamento profissional.

## 🧰 Materiais Necessários

### Hardware

* 1x Placa [LILYGO TTGO T-Display (ESP32)](https://s.click.aliexpress.com/e/_mqRUCxl) com **16MB de Flash**
* 1x Cabo USB-C de dados

### Software

* [ESP-IDF Tools Installer for Windows](https://github.com/espressif/idf-installer/releases/)
* [Git](https://git-scm.com/downloads)
* Um editor de texto simples (ex: Bloco de Notas, VS Code, Notepad++)

## 🛠️ Parte 1: Preparando o Ambiente (Do Zero)

### 1.1. Verificar a Versão Correta do ESP-IDF

Para evitar erros de compilação, é **crucial** usar a mesma versão do ESP-IDF para a qual o projeto Jade foi desenvolvido.

1.  **Acesse o repositório** oficial da [Blockstream Jade no GitHub](https://github.com/Blockstream/Jade).
2.  **Navegue até o arquivo de configuração** de testes do projeto. Geralmente, ele se encontra em: `.github/workflows/github-actions-test.yml`.
3.  **Abra o arquivo** e procure pela linha que define a versão do ESP-IDF, que será algo como: `esp_idf_version: v5.4`.
4.  **Anote essa versão.** É ela que você deve baixar e instalar. Para este guia, usaremos a **v5.4**.

### 1.2. Instalar o ESP-IDF v5.4

1.  **Limpeza:** Garanta que desinstalou versões antigas do ESP-IDF e apagou a pasta `C:\Espressif`.
2.  **Baixe o Instalador Offline:** Use o link para a versão que descobrimos: [**ESP-IDF v5.4 Offline Installer**](https://github.com/espressif/idf-installer/releases/download/offline-5.4/esp-idf-tools-setup-offline-5.4.exe)
3.  **Execute a Instalação:** Siga os passos do instalador. Ao final, marque a opção para abrir o terminal.
4.  **Abra o Terminal Correto:** Após instalar, procure por **"ESP-IDF 5.4 CMD"** no seu menu Iniciar. **Use sempre este terminal** para os comandos a seguir.

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

4.  **Baixar as dependências (submódulos):** Passo crucial para evitar erros.
    ```powershell
    git submodule update --init --recursive
    ```

## 🔥 Parte 2: Customizar, Compilar e Gravar

### 2.1. Remover o Ícone da Bateria

1.  **Edite o arquivo `gui.c`:**
    -   Abra o arquivo `C:\Espressif\frameworks\Jade\main\gui.c` no seu editor de texto.
2.  **Encontre a função `update_status_bar`**.
3.  **Comente o bloco da bateria:** Adicione `/*` no início e `*/` no final do bloco `if (status_bar.battery_update_counter == 0) { ... }`.
    ```c
    /*
        if (status_bar.battery_update_counter == 0) {
            uint8_t new_bat = power_get_battery_status();
            color_t color = new_bat == 0 ? TFT_RED : new_bat == 1 ? TFT_ORANGE : TFT_WHITE;
            if (power_get_battery_charging()) {
                new_bat = new_bat + 12;
            }
            if (new_bat != status_bar.last_battery_val) {
                status_bar.last_battery_val = new_bat;
                gui_set_color(status_bar.battery_text, color);
                update_text_node_text(status_bar.battery_text, (char[]){ new_bat + '0', '\0' });
                status_bar.updated = true;
            }
            status_bar.battery_update_counter = 60;
        }
    */
    ```
4.  **Salve o arquivo `gui.c`**.

### 2.2. Criar o Mapa de Partição para 16MB

1.  **Copie o arquivo de partição padrão:**
    ```powershell
    copy partitions.csv partitions_custom.csv
    ```

2.  **Edite o novo arquivo:** Abra o `partitions_custom.csv`, apague todo o conteúdo e cole o seguinte:
    ```csv
    # Espressif ESP32 Partition Table - CUSTOM 16MB by CaTeIM
    # Name,   Type, SubType, Offset,  Size, Flags
    nvs,      data, nvs,     0xA000,  0x4000,
    otadata,  data, ota,     0xE000,  0x2000, encrypted
    ota_0,    app,  ota_0,   ,         6144K,
    ota_1,    app,  ota_1,   ,         6144K,
    nvs_key,  data, nvs_keys,,            4K, encrypted
    ```

3.  Salve e feche o arquivo.

### 2.3. Configurar o Projeto (`menuconfig`)

1.  **Abra o Menu de Configuração:**
    ```powershell
    idf.py menuconfig
    ```

2.  **Ative o Secure Boot:**
    -   Vá em `Security features` -> `[*] Enable hardware Secure Boot in bootloader`.
    -   Deixe `Secure bootloader mode (One-time flash)`.
    -   Marque `[*] Sign binaries during build`.

3.  **Ajuste o Tamanho da Flash:**
    -   Vá em `Serial flasher config` -> `Flash size (4 MB) --->`.
    -   Selecione **`(X) 16 MB`**.

4.  **Aponte para o Mapa de Partição:**
    -   Vá em `Partition Table` -> `Partition Table (Custom partition CSV) --->`.
    -   Marque `(X) Custom partition table CSV`.
    -   Saia desse sub-menu (ESC) e no campo `Custom partition CSV file` digite: **`partitions_custom.csv`**.

5.  **Salve e Saia:** Tecle `S`, depois `Enter`, e `Q`.

### 2.4. Gerar a Chave de Assinatura

1.  **Limpe compilações antigas:**
    ```powershell
    idf.py fullclean
    ```

2.  **Gere a chave de assinatura:**
    ```powershell
    espsecure.py generate_signing_key secure_boot_signing_key.pem
    ```

> 🚨 **AVISO IRREVERSÍVEL!** 🚨
> O arquivo `secure_boot_signing_key.pem` é a chave mestra da sua placa. Um resumo dela será **permanentemente gravado** no hardware no próximo passo.
> - **FAÇA BACKUP DESTE ARQUIVO!**
> - Se você perder esta chave, **NUNCA MAIS poderá atualizar o firmware desta placa**.

### 2.5. A Gravação (Flash)

1.  **Conecte a TTGO T-Display** no seu computador.
2.  **Descubra a porta serial (COM)** no Gerenciador de Dispositivos do Windows.
3.  **Execute o comando de flash** (substitua `COM3` pela sua porta):
    ```powershell
    idf.py flash -p COM3
    ```
4.  Se travar em "Connecting...", coloque a placa em modo bootloader manualmente:
    -   Segure o botão `BOOT`, aperte e solte o `RST`, depois solte o `BOOT`.

## ✅ Verificação Final

A placa irá reiniciar com o firmware da Jade, com Secure Boot, usando os 16MB e sem o ícone de bateria. Operação concluída com sucesso!

*Tutorial criado para o repositório* [_DIY na Prática_](https://github.com/CaTeIM/DIY). _Adaptado e testado para entusiastas de hardware e Bitcoin._ 🚀