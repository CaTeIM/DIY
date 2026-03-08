# Guia de Configuração: RustDesk Headless no Debian com XFCE Virtual

Este guia detalha o processo de instalação e configuração do RustDesk em um servidor Debian "headless" (sem monitor), garantindo que uma sessão gráfica virtual (XFCE) esteja sempre ativa, mesmo sem login de usuário, permitindo o acesso remoto a qualquer momento.

## 🎯 Objetivo

O objetivo é fazer o `rustdesk.service` (o servidor do RustDesk) ser iniciado apenas **após** uma sessão gráfica XFCE virtual (criada com `Xvfb`) estar pronta e, mais importante, fazer o RustDesk "enxergar" essa sessão virtual.

Isso resolve o problema comum em que o RustDesk funciona, mas só exibe uma tela preta ou só funciona *depois* que um usuário faz login manualmente e inicia um `startx`.

## 🛠️ Componentes Utilizados

1.  **Debian (13, 12, etc.)**: O sistema operacional do servidor.
2.  **RustDesk**: O software de acesso remoto.
3.  **XFCE4**: Um ambiente de desktop leve.
4.  **Xvfb (X Virtual Framebuffer)**: Cria um "monitor virtual" na memória.
5.  **systemd**: O gerenciador de serviços do Linux, usado para orquestrar tudo.

## Passo 1: Instalação das Dependências (Versão Mínima)

Primeiro, instalamos o mínimo necessário para um ambiente de desktop funcional. Usar `--no-install-recommends` é **crucial** em servidores para evitar pacotes desnecessários (como players de mídia, jogos, temas, etc.).

Como o `--no-install-recommends` é muito rigoroso, em vez de usar o metapacote `xfce4`, vamos instalar os componentes essenciais um por um para garantir que o desktop seja funcional:

```bash
sudo apt update

# Instala os componentes essenciais do XFCE e o Xvfb
sudo apt install --no-install-recommends \
    xvfb \
    dbus-x11 \
    x11-utils \
    x11-xserver-utils \
    xfce4-session \
    xfwm4 \
    xfce4-panel \
    xfce4-settings \
    thunar \
    xfce4-terminal

# Instala o RustDesk (baixe o .deb apropriado no site oficial: https://github.com/rustdesk/rustdesk/releases)
sudo apt install ./rustdesk-*.deb
```

**Nota:** A lista acima inclui o essencial para um desktop funcional:

-   `xvfb`, `dbus-x11`: O display virtual e barramento de sessão.
-   `x11-utils`: Utilitários X11, inclui `xdpyinfo` (necessário para o script de inicialização).
-   `x11-xserver-utils`: Utilitários do servidor X (`xrandr`, `xrdb`, etc.).
-   `xfce4-session`: O gerenciador de login/sessão.
-   `xfwm4`: O gerenciador de janelas (para mover/fechar janelas).
-   `xfce4-panel`: A barra de tarefas/menu.
-   `xfce4-settings`: O painel de controle.
-   `thunar`: O gerenciador de arquivos.
-   `xfce4-terminal`: Um terminal (essencial!).
    
Se algo faltar (ex: `mousepad` como editor de texto), você pode instalá-lo da mesma forma.

## Passo 2: Identificar o Usuário de Sessão

Vamos usar o usuário que já existe no sistema com UID 1000 (normalmente o primeiro usuário criado durante a instalação do Debian).

Execute o comando abaixo para saber o nome desse usuário:

```bash
getent passwd 1000 | cut -d: -f1
# Exemplo de saída: meunome
```

**Anote esse nome** — ele será usado nos passos seguintes no lugar de `<usuario>`.

> Se o comando não retornar nada, significa que não há usuário com UID 1000. Nesse caso, crie um:
> ```bash
> sudo useradd --uid 1000 --create-home --shell /bin/bash meuusuario
> ```



## Passo 3: Habilitar "Linger" para o Usuário

Este é um passo **crítico**. Por padrão, os serviços de um usuário (`user@1000.service`) só são iniciados quando esse usuário faz login.

"Habilitar o Linger" diz ao systemd para iniciar os serviços desse usuário **durante o boot**, mesmo sem login. Isso é essencial para que nosso XFCE virtual (que depende desses serviços) possa iniciar.

```bash
# Substitua <usuario> pelo nome obtido no Passo 2
sudo loginctl enable-linger <usuario>
```

-   **Para verificar:** `loginctl show-user <usuario> -p Linger` (deve retornar `Linger=yes`).
    
## Passo 4: Criar o Script de Inicialização da Sessão

Vamos criar um script simples que será responsável por iniciar o `Xvfb` (o monitor virtual) e, em seguida, o `xfce4-session` (o desktop) dentro dele.

Crie o arquivo:
```bash
sudo nano /usr/local/bin/start-virtual-session.sh
```

Cole o seguinte conteúdo:
```bash
#!/bin/bash

# Inicia o Xvfb no display :0 com resolução 1920x1080
Xvfb :0 -screen 0 1920x1080x24 -nolisten tcp &

# Exporta a variável DISPLAY para que os próximos comandos
# saibam onde encontrar o display virtual
export DISPLAY=:0

# Aguarda o display :0 estar realmente disponível
until xdpyinfo -display :0 >/dev/null 2>&1; do
    sleep 0.5
done

# Inicia a sessão XFCE dentro do display virtual
exec xfce4-session
```

Depois de salvar, torne o script executável:
```bash
sudo chmod +x /usr/local/bin/start-virtual-session.sh
```

## Passo 5: Criar o Serviço systemd para o XFCE Virtual

Agora, criamos um serviço de **sistema** que executará o script acima como o nosso usuário (`rustdesk`).

Crie o arquivo:
```bash
sudo nano /etc/systemd/system/xfce-virtual.service
```

Cole o seguinte conteúdo:


```ini
[Unit]
Description=Start Virtual XFCE Session (Xvfb) for RustDesk
# Inicia somente após a rede estar pronta
After=network.target

[Service]
# IMPORTANTE: Rode como o usuário identificado no Passo 2
User=<usuario>
Type=simple
ExecStart=/usr/local/bin/start-virtual-session.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

## Passo 6: "Amarrar" o XFCE Virtual ao Serviço de Usuário

Aqui está o **primeiro pulo do gato**. O serviço `xfce-virtual.service` (um serviço de sistema) precisa esperar que os serviços do **usuário** com UID 1000 estejam prontos. (É por isso que habilitamos o "linger" no Passo 3).

Vamos criar um _override_ para adicionar essa dependência.
```bash
# Este comando cria o diretório e o arquivo de override
sudo systemctl edit xfce-virtual.service
```

Isso abrirá um editor. Cole o seguinte **exatamente assim** — o nome da unit usa o número do UID (`1000`), não o nome do usuário:
```ini
[Unit]
# Espera o serviço de usuário do UID 1000 estar pronto
After=user@1000.service
Requires=user@1000.service
```

Salve e saia. O `systemd` automaticamente lerá este arquivo.

## Passo 7: "Amarrar" o RustDesk ao XFCE Virtual

Este é o **segundo pulo do gato** e a solução final. O serviço `rustdesk.service` precisa de duas coisas:

1.  Ser iniciado **somente depois** que o `xfce-virtual.service` estiver pronto.
2.  "Saber" que a sessão gráfica existe no `DISPLAY=:0`.

Vamos criar um _override_ para o RustDesk:
```bash
sudo systemctl edit rustdesk.service
```

Isso abrirá um editor. Cole o seguinte:
```ini
[Unit]
# 1. Faz o RustDesk esperar pelo nosso XFCE
After=xfce-virtual.service
Requires=xfce-virtual.service

[Service]
# 2. Injeta a variável de ambiente que diz ao RustDesk onde está o display
Environment="DISPLAY=:0"
```

Salve e saia.

## Passo 8: Aplicar Tudo e Testar

Agora que todas as peças estão configuradas, vamos recarregar o `systemd` e reiniciar os serviços na ordem correta (que o `systemd` agora fará automaticamente graças aos `Requires=`).

```bash
# Recarrega o systemd para ler os novos arquivos e overrides
sudo systemctl daemon-reload

# Habilita o serviço XFCE para iniciar no boot
sudo systemctl enable xfce-virtual.service

# (O rustdesk.service já deve estar habilitado)

# Reinicia os serviços
# O systemd garantirá que o xfce-virtual inicie primeiro
sudo systemctl restart rustdesk.service
```

Para uma garantia extra, você pode reiniciar a máquina:
```bash
sudo reboot
```

Após reiniciar, **não faça login no terminal**. Tente se conectar diretamente usando seu cliente RustDesk. Você deverá ver o desktop XFCE completo e funcional.

## 🔎 Solução de Problemas (Troubleshooting)

Se algo der errado, aqui estão os comandos para investigar:

**1. O XFCE Virtual subiu?**

```bash
systemctl status xfce-virtual.service
```

-   Procure por `Active: active (running)`.
-   Veja se o `Drop-In:` para o `override.conf` foi lido.
-   Nos logs (abaixo), procure pela árvore de processos (`xfce4-session`, `Xvfb`, `xfwm4`, etc.).

**2. O RustDesk subiu?**

```bash
systemctl status rustdesk.service
```

-   Procure por `Active: active (running)`.
-   Veja se o `Drop-In:` para o `override.conf` foi lido.

**3. O que os logs dizem?**

```bash
# Logs do serviço XFCE (últimas 50 linhas)
journalctl -u xfce-virtual.service -n 50

# Logs do serviço RustDesk (últimas 50 linhas)
journalctl -u rustdesk.service -n 50
```

**4. O linger está ativo?**

```bash
loginctl show-user <usuario> -p Linger
# Deve retornar: Linger=yes
# Se retornar 'no', rode: sudo loginctl enable-linger <usuario>
```

**5. O display `:0` está rodando?**

```bash
# Verifica se o processo Xvfb está ativo
pgrep -a Xvfb

# Testa a conexão com o display (rode como o usuário identificado no Passo 2)
su -s /bin/bash <usuario> -c 'DISPLAY=:0 xdpyinfo | head -5'
```

**6. Erro de permissão de display (MIT-MAGIC-COOKIE)?**

Se nos logs aparecer `No protocol specified` ou `cannot open display`, o arquivo `.Xauthority` pode estar com permissão errada:

```bash
# Verifica o dono do arquivo
ls -la /home/<usuario>/.Xauthority

# Corrige o dono se necessário
sudo chown <usuario>:<usuario> /home/<usuario>/.Xauthority
```