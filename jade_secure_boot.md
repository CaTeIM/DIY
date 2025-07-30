# 🔐 Carteira Hardware Jade na TTGO com Secure Boot v2

Este tutorial mostra o processo completo para instalar o firmware da [Blockstream Jade](https://github.com/Blockstream/Jade) em uma placa de desenvolvimento **TTGO T-Display de 16MB**, ativando a camada extra de segurança **Secure Boot v2**.

Isso transforma um hardware de baixo custo em uma hardware wallet muito mais robusta, onde a placa só aceitará firmwares assinados por você.

## 🧰 Materiais Necessários

### Hardware
- 1x Placa [LILYGO TTGO T-Display (ESP32)](https://s.click.aliexpress.com/e/_mqRUCxl) com **16MB de Flash**
- 1x Cabo USB-C de dados

### Software
- [ESP-IDF Tools Installer](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/get-started/windows-setup.html) (para Windows)
- [Git](https://git-scm.com/downloads)
- Um editor de texto simples (ex: Bloco de Notas, VS Code)

## 🛠️ Parte 1: Preparando o Ambiente (Do Zero)

Aqui vamos instalar as ferramentas necessárias no computador para compilar e gravar o firmware.

### 1.1. Instalar o ESP-IDF
1.  **Baixe o Instalador:** Vá para a [página de downloads da Espressif](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/get-started/windows-setup.html), clique em **Windows Installer Download** e pegue o **Universal Online Installer**.
2.  **Execute a Instalação:** Siga os passos. Quando perguntar a versão, escolha uma estável recente (ex: `v5.1` ou superior). Mantenha os caminhos de instalação padrão.
3.  **Abra o Terminal Correto:** Após instalar, procure por **"ESP-IDF X.X CMD"** no seu menu Iniciar. **Use sempre este terminal** para os comandos a seguir.

### 1.2. Baixar o Código da Jade
Dentro do terminal do ESP-IDF que você abriu:

1.  **Clonar o repositório:**
    ```powershell
    git clone https://github.com/Blockstream/Jade.git
    ```
2.  **Entrar na pasta:**
    ```powershell
    cd Jade
    ```
3.  **Baixar as dependências (submódulos):** Este passo é crucial e evita erros de compilação.
    ```powershell
    git submodule update --init --recursive
    ```

## 🔥 Parte 2: Compilar e Gravar com Secure Boot

Agora vamos configurar o projeto para a placa de 16MB, ativar o Secure Boot e mandar para a placa.

### 2.1. Criar o Mapa de Partição para 16MB
1.  **Copie o arquivo de partição padrão:**
    ```powershell
    copy partitions.csv partitions_custom.csv
    ```
2.  **Edite o novo arquivo:** Abra o `partitions_custom.csv` com um editor de texto. Apague todo o conteúdo e cole o seguinte:

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

### 2.2. Configurar o Projeto (`menuconfig`)
1.  **Abra o Menu de Configuração:**
    ```powershell
    idf.py menuconfig
    ```
2.  **Ative o Secure Boot (O Ponto de Não Retorno):**
    - Navegue até `Security features` e tecle `Enter`.
    - Marque com a barra de espaço a opção `[*] Enable hardware Secure Boot in bootloader`.
    - Deixe `Secure bootloader mode` como `One-time flash (Recommended)`.
    - Deixe `Secure Boot signing key` como `Generate signing key automatically...`.

3.  **Ajuste o Tamanho da Flash:**
    - Navegue até `Serial flasher config` -> `Flash size (4 MB) --->`.
    - Selecione **`16 MB`** e tecle `Enter`.
    - Tecle `Esc` para voltar ao menu principal.

4.  **Aponte para o Mapa de Partição Customizado:**
    - Navegue até `Partition Table`.
    - Em `Custom partition CSV file`, digite o nome do nosso novo arquivo: **`partitions_custom.csv`**.

5.  **Salve e Saia:**
    - Tecle `S` para salvar.
    - Tecle `Enter` para confirmar.
    - Tecle `Q` para sair.

🚨 **AVISO IRREVERSÍVEL!** 🚨

Ao executar o próximo passo (`flash`), uma chave de assinatura (`secure_boot_signing_key.pem`) será criada. Um "resumo" dessa chave será **permanentemente gravado** na sua placa.

- **FAÇA BACKUP IMEDIATO DO ARQUIVO `secure_boot_signing_key.pem`!**
- Se você perder esta chave, **você NUNCA MAIS poderá atualizar o firmware desta placa**.

### 2.3. A Gravação (Flash)
1.  **Conecte a TTGO T-Display** no seu computador.
2.  Execute o comando de flash:
    ```powershell
    idf.py flash
    ```
3.  O processo de compilação vai começar. No final, ele tentará se conectar à placa. Se ele ficar parado em "Connecting...", coloque a placa em modo bootloader manualmente:
    - Segure o botão `BOOT`.
    - Aperte e solte o botão `RST`.
    - Solte o botão `BOOT`.

Se tudo der certo, a placa irá reiniciar com o firmware da Jade, Secure Boot ativado e usando todo o potencial dos seus 16MB de flash.

## ✅ Verificação Final
Após a instalação, a Jade vai iniciar. O Secure Boot é verificado silenciosamente a cada boot. Se a placa ligar e mostrar a interface da Jade, a operação foi um sucesso!

---
*Tutorial criado para o repositório [DIY na Prática](https://github.com/CaTeIM/DIY). Adaptado e testado para entusiastas de hardware e Bitcoin.* 🚀