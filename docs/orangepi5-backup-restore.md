# 💾 Backup Total e Restauração da Orange Pi 5 (OMV + Timeshift)

Como fazer o backup completo de uma Orange Pi 5 rodando OpenMediaVault, e como reconstruir o
servidor inteiro do zero se a placa queimar, o SSD morrer ou o sistema corromper.

Este guia não é específico de nenhuma stack: ele cobre o servidor inteiro, com todas as suas stacks
Docker de uma vez.

O script de backup está em
[`assets/configs/orangepi5-backup-boot.sh`](../assets/configs/orangepi5-backup-boot.sh).

> [!CAUTION]
> **Timeshift sozinho não recupera esta placa.** Ele copia arquivos, e uma Orange Pi 5 precisa
> também de setores brutos (bootloader) que ficam fora de qualquer sistema de arquivos. Um NVMe novo
> com todos os arquivos restaurados corretamente **não dá boot**. A Parte 3 resolve isso, e são
> apenas 46 MB.

---

## O mapa desta placa

Levantado em 2026-08-09. Confira o seu com `lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINT`.

| Dispositivo  | Tamanho | Formato | Papel                                  | Montagem                              |
| :----------- | :------ | :------ | :------------------------------------- | :------------------------------------ |
| `mtd0`       | 16 MB   | raw     | **SPI NOR: bootloader da placa**       | não montado                           |
| `nvme0n1`    | 119 GB  | GPT     | disco de sistema (WD SN520)            |                                       |
| ├ `p1`       | 1 GB    | vfat    | `opi_boot`: kernel, dtb, boot.scr      | `/boot`                               |
| └ `p2`       | 117 GB  | ext4    | `opi_root`: o sistema e `/srv`         | `/`                                   |
| `sda1`       | 931 GB  | ext4    | biblioteca de mídia                    | `/srv/dev-disk-by-uuid-8662b1ab-.../` |
| `sdb1`       | 238 GB  | ext4    | **destino do Timeshift**               | `/srv/dev-disk-by-uuid-ac8dc031-.../` |
| `zram1`      | 200 MB  | ext4    | `/var/log` em RAM (plugin flashmemory) | `/var/log`                            |

Detalhe importante: **`/srv/midia` é um symlink**, não um mount:

```
/srv/midia -> /srv/dev-disk-by-uuid-8662b1ab-1ae5-4c34-b0de-adc4257fe34f/midia
```

Se o UUID do HD de mídia mudar, o symlink quebra e todas as stacks de mídia param.

### Identificadores desta instalação

Anote em papel ou guarde junto do backup. **Sem eles, a restauração da Parte 7 exige edição manual
de `fstab` e `orangepiEnv.txt`.**

| O quê                    | Valor                                  |
| :----------------------- | :------------------------------------- |
| UUID do root (`p2`)      | `773d663c-ff20-4993-a1f6-877050b5ca39` |
| Volume ID do boot (`p1`) | `53EF-2995`                            |
| UUID do HD de mídia      | `8662b1ab-1ae5-4c34-b0de-adc4257fe34f` |
| UUID do disco de backup  | `ac8dc031-1e89-495a-b7df-002c7652b786` |
| Primeiro setor da `p1`   | `61440` (ou seja, 30 MB)               |
| Label da `p1` / `p2`     | `opi_boot` / `opi_root`                |

Para obter os seus:

```bash
sudo blkid
sudo partx -o NR,START,END,SECTORS,SIZE,NAME /dev/nvme0n1
```

---

## 🔌 Parte 1: Como esta placa dá boot

Entender isso é o que separa um backup que funciona de um que só parece funcionar.

```
  ┌──────────────────┐
  │  BootROM RK3588  │  gravado de fábrica no silício, não pode ser alterado
  └────────┬─────────┘
           │ procura um loader em: eMMC → SD → SPI NOR → USB
           ▼
  ┌──────────────────┐
  │  SPI NOR (16 MB) │  idbloader (assinatura RKNS) + U-Boot
  │   /dev/mtdblock0 │  ◄── NÃO está em nenhum sistema de arquivos
  └────────┬─────────┘
           │ U-Boot inicializa o controlador PCIe e enxerga o NVMe
           ▼
  ┌──────────────────┐
  │  NVMe, setor 64  │  idbloader (RKNS)      ◄── setores brutos, antes da p1
  │  NVMe, setor 16384│ u-boot.itb (FIT)      ◄── setores brutos, antes da p1
  └────────┬─────────┘
           │ lê /boot/boot.scr e /boot/orangepiEnv.txt
           ▼
  ┌──────────────────┐
  │  nvme0n1p1 /boot │  Image (kernel), initrd, dtb
  └────────┬─────────┘
           │ rootdev=UUID=773d663c-...
           ▼
  ┌──────────────────┐
  │  nvme0n1p2  /    │  sistema, /srv, Docker
  └──────────────────┘
```

O ponto crítico: **os dois primeiros estágios vivem em setores brutos**. O Timeshift copia arquivos.
Ele nunca viu, e nunca vai ver, esses bytes.

A primeira partição começa no **setor 61440**, o que equivale a 30 MB. Tudo antes disso é área de
bootloader, e é isso que precisa ser capturado separadamente.

---

## 🕐 Parte 2: Camada 1, Timeshift (os arquivos do sistema)

### 2.1. O que já está configurado

| Item              | Valor atual                                                  |
| :---------------- | :----------------------------------------------------------- |
| Modo              | RSYNC com hardlinks entre snapshots                          |
| Destino           | `/dev/sdb1`, disco **separado** do sistema                   |
| Snapshots         | 16 em rodízio, com 153,9 GB livres no destino                |
| Espaço ocupado    | 5,9 GB para os 16 snapshots (o hardlink evita duplicar)      |
| Retenção          | mensal 6, semanal 4, diário 7, boot 1, horário desligado     |
| Agendamento       | `/etc/cron.d/timeshift-hourly` roda `timeshift --check` de hora em hora |
| Snapshot de boot  | `/etc/cron.d/timeshift-boot`, 10 minutos após cada reboot    |
| Exclusões         | `/srv/midia/**`, `/srv/dev-disk-by-uuid*/**`, `/mnt/**`, `/media/**` |

Verificar a qualquer momento:

```bash
sudo timeshift --list
```

### 2.2. O que ele cobre nesta configuração

Confirmado por inspeção dentro do snapshot mais recente:

- `/boot` completo (`Image`, `dtb`, `boot.scr`, `orangepiEnv.txt`)
- `/etc` inteiro, incluindo `fstab`, configuração do OMV e do Docker
- **`/srv/<serviço>`** de todas as stacks: bancos dos `*arrs`, config do Plex, Vaultwarden,
  Home Assistant, Forgejo, e assim por diante
- `/srv/portainer/compose`, ou seja, o YAML de todas as stacks do Portainer

### 2.3. O que ele NÃO cobre

| Caminho                     | Motivo                                                    | Coberto por          |
| :-------------------------- | :-------------------------------------------------------- | :------------------- |
| Bootloader (SPI + raw NVMe) | Não é arquivo, são setores brutos                         | **Parte 3**          |
| Tabela de partições (GPT)   | Idem                                                      | **Parte 3**          |
| `/var/lib/docker`           | **Exclusão interna do Timeshift**, não configurável       | **Parte 4**          |
| `/home/**` e `/root/**`     | Eram excluídos aqui. **Corrigido em 2026-08-13**, hoje entram no snapshot | Parte 2.4 |
| `/srv/midia/**`             | Exclusão proposital: é a biblioteca de vídeo              | (não faz backup)     |
| `/srv/dev-disk-by-uuid*/**` | Exclusão proposital: são os discos de dados do OMV        | (não faz backup)     |

> [!WARNING]
> **`/var/lib/docker` é a pegadinha mais silenciosa aqui.** A pasta aparece dentro do snapshot, mas
> está **vazia**. O Timeshift a exclui internamente, e essa exclusão não aparece na lista de
> exclusões do painel do OMV.
>
> Na prática: imagens são re-baixáveis, e as stacks deste repositório usam bind mounts em `/srv`,
> que estão salvos. Mas **volumes nomeados não voltam**. Neste servidor existe pelo menos um:
> `logistics_pgdata`, que é o banco de dados de uma stack inteira.

### 2.4. Ajuste recomendado nas exclusões

`/home` e `/root` costumam guardar chave SSH, script solto, `.env` e histórico de shell. Para
incluí-los, edite as exclusões no painel do OMV (**Serviços** → **Timeshift**) removendo as linhas
`/home/**` e `/root/**`, ou direto no arquivo:

```bash
sudo nano /etc/timeshift/timeshift.json
```

A lista de exclusões deste servidor depois do ajuste:

```json
"exclude" : [
  "/srv/midia/**",
  "/srv/dev-disk-by-uuid*/**",
  "/mnt/**",
  "/media/**"
],
```

Confirme que funcionou olhando dentro do próximo snapshot:

```bash
SNAP=/srv/dev-disk-by-uuid-ac8dc031-1e89-495a-b7df-002c7652b786/timeshift/snapshots
sudo ls "$SNAP/$(sudo ls -t $SNAP | head -1)/localhost/home/"
```

Deve listar os usuários. Se vier vazio, a exclusão continua ativa.

> A alternativa é manter as exclusões e usar `INCLUDE_HOME=1` no script da Parte 6, que faz um `tar`
> separado. É pior: o `tar` é completo a cada rodada, sem dedupe. Ver Parte 4.2.

### 2.5. Snapshot manual antes de mexer em algo

```bash
sudo timeshift --create --comments "antes de atualizar o OMV"
```

---

## 🔧 Parte 3: Camada 2, o bootloader (46 MB que salvam o servidor)

Esta é a camada que faltava. Tudo aqui pode ser capturado **com a placa ligada e em produção**,
porque são regiões que não mudam durante a operação normal.

> Os comandos a seguir são a versão manual, útil para entender o que está sendo salvo. Se quiser
> apenas rodar, pule para a **Parte 6**: o script faz tudo isso com verificação e rotação.

Crie a pasta de destino antes:

```bash
sudo mkdir -p /srv/backup-boot
```

### 3.1. SPI NOR: o bootloader da placa (16 MB)

```bash
sudo dd if=/dev/mtdblock0 of=/srv/backup-boot/spi-nor.img bs=1M status=progress
```

Confirme que não veio vazio:

```bash
# Se o md5 for igual ao de 16 MB de zeros, a SPI está em branco e algo está errado
md5sum /srv/backup-boot/spi-nor.img
dd if=/dev/zero bs=1M count=16 2>/dev/null | md5sum
```

Você também pode confirmar a assinatura Rockchip diretamente:

```bash
sudo dd if=/dev/mtdblock0 bs=512 skip=64 count=1 2>/dev/null | od -A d -t x1z | head -1
```

A saída deve começar com `52 4b 4e 53`, que em ASCII é **RKNS**.

### 3.2. Área de bootloader do NVMe (30 MB)

Copia tudo que existe antes da primeira partição: MBR protetor, GPT primária, idbloader e
`u-boot.itb`.

```bash
# Descobrir onde começa a primeira partição (aqui: setor 61440 = 30 MB)
sudo partx -g -o START /dev/nvme0n1 | head -1

sudo dd if=/dev/nvme0n1 of=/srv/backup-boot/bootloader-raw.img bs=1M count=30 status=progress
```

### 3.3. Tabela de partições (40 KB)

Em dois formatos, porque cada um serve melhor a um cenário:

```bash
# Texto, legível e editável. Restaura com: sfdisk /dev/nvme0n1 < particoes.sfdisk
sudo sfdisk --dump /dev/nvme0n1 | sudo tee /srv/backup-boot/particoes.sfdisk > /dev/null

# Binário, preserva GUIDs exatos das partições
sudo sgdisk --backup=/srv/backup-boot/particoes.gpt /dev/nvme0n1
```

> [!IMPORTANT]
> Repare no `| sudo tee` em vez de `>`. O redirecionamento `>` é executado pelo **seu shell**, não
> pelo `sudo`, então ele tenta criar o arquivo com o seu usuário e falha com
> `permissão negada` numa pasta que pertence ao `root`:
>
> ```
> ❯ sudo sfdisk --dump /dev/nvme0n1 > /srv/backup-boot/particoes.sfdisk
> zsh: permissão negada: /srv/backup-boot/particoes.sfdisk
> ```
>
> Isso vale para qualquer `sudo comando > arquivo` deste guia. Use `| sudo tee arquivo > /dev/null`.
> Comandos como `dd of=...` e `sgdisk --backup=...` não têm esse problema, porque quem abre o
> arquivo é o próprio programa, já elevado pelo `sudo`.

> [!NOTE]
> O `sgdisk` vem do pacote `gdisk`, que **já está instalado** neste servidor (o OMV depende dele).
> Ele mora em `/sbin`, fora do `PATH` de usuário comum: se der `command not found`, use o caminho
> completo `/sbin/sgdisk` ou rode com `sudo`. Em um sistema recém-instalado, `sudo apt install gdisk`.

### 3.4. Por que não uma imagem completa do NVMe

Um `dd` dos 119 GB inteiros funciona, mas:

- É lento e ocupa dezenas de GB por rodada
- Feito com o sistema ligado, produz um rootfs **inconsistente** (bancos SQLite abertos no meio de
  uma escrita)
- Para ser consistente, exige desligar a placa e bootar por cartão SD

As três peças acima somam 46 MB, são consistentes por natureza (não mudam em produção), e combinadas
aos snapshots do Timeshift reconstroem exatamente o mesmo sistema.

> A imagem completa continua sendo uma alternativa válida, e está documentada na Parte 7.5 como
> plano B para quem prefere restaurar em um passo só.

---

## 📦 Parte 4: Camada 3, o que o Timeshift exclui

### 4.1. Volumes nomeados do Docker

```bash
# Listar os que têm nome legível (os de hash são camadas anônimas, descartáveis)
docker volume ls --format '{{.Name}}' | grep -vE '^[0-9a-f]{64}$'

# Exportar um volume
docker run --rm \
  -v logistics_pgdata:/origem:ro \
  -v /srv/backup-boot:/destino \
  alpine tar czf /destino/logistics_pgdata.tgz -C /origem .
```

> [!TIP]
> A melhor correção de longo prazo é **não usar volume nomeado**. As stacks deste repositório usam
> bind mount em `/srv/<serviço>`, que o Timeshift cobre automaticamente. Se uma stack sua ainda usa
> volume nomeado, migrar para bind mount elimina esse ponto cego de uma vez.

### 4.2. `/home` e `/root`

Neste servidor eles somam **4,8 GB** (`/home` 3,4 GB e `/root` 1,4 GB). Há dois caminhos, e o
primeiro é claramente melhor:

**Opção A, recomendada: incluir nos snapshots do Timeshift.** Remova `/home/**` e `/root/**` das
exclusões (Parte 2.4). O Timeshift faz snapshot incremental com hardlink, então os 4,8 GB entram uma
vez só e os snapshots seguintes só guardam o que mudou.

**Opção B: `tar` separado.** Mantém as exclusões e arquiva à parte. O custo é que cada rodada gera um
`tar` completo, sem dedupe algum:

```bash
sudo tar czf /srv/backup-boot/home.tgz -C / home
sudo tar czf /srv/backup-boot/root.tgz -C / root
```

> [!WARNING]
> Com a opção B em backup semanal e 4 rodadas retidas, são cerca de 20 GB de cópias quase idênticas
> numa partição que hoje tem 79 GB livres. Por isso o script da Parte 6 vem com essa etapa
> **desligada por padrão**, atrás da variável `INCLUDE_HOME`.

### 4.3. Inventário do sistema

O que você vai querer ter em mãos com o servidor fora do ar:

```bash
{
  lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINT
  sudo blkid
  cat /etc/fstab
  cat /boot/orangepiEnv.txt
  uname -a
  sudo docker ps -a --format '{{.Names}}\t{{.Image}}'
} | sudo tee /srv/backup-boot/inventario.txt > /dev/null

# Lista de pacotes, para reinstalar tudo de uma vez em um sistema novo
dpkg --get-selections | sudo tee /srv/backup-boot/pacotes.list > /dev/null
```

> [!TIP]
> O `sudo` fica **dentro** do bloco, nos comandos que precisam dele, e o `sudo tee` fica na saída.
> Não tente escrever `sudo { ... }`: o `{ }` é uma construção do shell, não um programa, e o
> resultado é `parse error near '}'`.

---

## 🌍 Parte 5: Tirar o backup de dentro do gabinete

O Timeshift grava no `sdb1`, que está **no mesmo servidor**. Isso cobre falha da placa e do NVMe.
Não cobre furto, incêndio, raio na rede elétrica nem apagar tudo por engano.

A regra 3-2-1: 3 cópias, em 2 mídias diferentes, 1 fora do local.

A boa notícia é que o essencial é pequeno. Sem a biblioteca de vídeo:

| Item                          | Tamanho aproximado |
| :---------------------------- | :----------------- |
| Pacote de boot (Parte 3)      | 46 MB              |
| Snapshots do Timeshift        | 5,9 GB             |
| `/srv` das stacks (sem mídia) | poucos GB          |

Uma cópia semanal do pacote de boot mais o `/srv` comprimido cabe em qualquer nuvem ou pendrive.

```bash
# Exemplo com rclone para um remote já configurado
rclone sync /srv/backup-boot remote:orangepi5/backup-boot --progress
```

> [!NOTE]
> Se for enviar para armazenamento de terceiros, criptografe antes. O `/srv` contém chaves de API,
> tokens e bancos com dados pessoais. O `rclone crypt` ou um `tar` com `gpg -c` resolvem.

---

## 🤖 Parte 6: Automatizar

O script [`assets/configs/orangepi5-backup-boot.sh`](../assets/configs/orangepi5-backup-boot.sh) faz
as Partes 3 e 4 de uma vez, com rotação e checksums.

```bash
# Instalar
sudo cp orangepi5-backup-boot.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/orangepi5-backup-boot.sh

# Rodar uma vez para testar
sudo /usr/local/bin/orangepi5-backup-boot.sh

# Agendar toda semana, domingo às 03:00
echo '0 3 * * 0 root /usr/local/bin/orangepi5-backup-boot.sh >> /var/log/backup-boot.log 2>&1' \
  | sudo tee /etc/cron.d/backup-boot
```

Ele grava em `/srv/backup-boot/<data>/` e mantém as 4 rodadas mais recentes.

### 6.1. Variáveis de ajuste

| Variável       | Padrão            | Para quê                                                        |
| :------------- | :---------------- | :-------------------------------------------------------------- |
| `BOOT_DISK`    | `/dev/nvme0n1`    | Disco de sistema                                                 |
| `SPI_DEV`      | `/dev/mtdblock0`  | SPI NOR                                                          |
| `KEEP`         | `4`               | Quantas rodadas manter                                           |
| `INCLUDE_HOME` | `0`               | `1` inclui `/home` e `/root` no `tar` (ver o aviso da Parte 4.2) |

```bash
# Exemplo: uma rodada incluindo /home e /root
sudo INCLUDE_HOME=1 /usr/local/bin/orangepi5-backup-boot.sh
```

### 6.2. O que o script valida sozinho

Ele não confia que o `dd` deu certo só porque não deu erro. Depois de copiar, verifica:

- assinatura `RKNS` no setor 64 da imagem da SPI
- magic FIT (`d0 0d fe ed`) no setor 16384 da imagem do NVMe
- espaço livre no destino, antes de começar
- que o primeiro setor lido é um número plausível, abortando se não for

Qualquer falha vira um `AVISO` contado no final, com a mensagem
`ATENCAO: N aviso(s) acima. Revise antes de confiar neste backup.`

### 6.3. Saída esperada

Execução real nesta placa, com `INCLUDE_HOME=0`:

```
==> [1/6] SPI NOR (/dev/mtdblock0)
    OK, assinatura RKNS presente (16M)
==> [2/6] Bootloader do NVMe
    primeira particao no setor 61440, copiando 30 MB
    OK, u-boot.itb presente (30M)
==> [3/6] Tabela de particoes
    sfdisk + sgdisk
==> [4/6] Inventario
==> [5/6] Volumes nomeados do Docker
    - logistics_pgdata
==> [6/6] /home e /root: pulados (INCLUDE_HOME=0)
==> Concluido: /srv/backup-boot/2026-08-09_19-46-18  (57M)
```

Os 57 MB se dividem em: 30 MB de bootloader do NVMe, 16 MB de SPI, 2,1 MB dos YAML das stacks do
Portainer, 8 MB do volume `logistics_pgdata` comprimido e o resto entre inventário, lista de pacotes
e tabelas de partição.

> [!IMPORTANT]
> `/srv/backup-boot` fica na partição raiz, que **é** coberta pelo Timeshift. Isso é proposital: o
> pacote de boot passa a viajar junto com os snapshots. Ainda assim, copie para fora do servidor
> conforme a Parte 5.

---

## 🚑 Parte 7: Restauração

### Antes de tudo: qual é o seu cenário?

| Situação                                        | Vá para       |
| :---------------------------------------------- | :------------ |
| Sistema corrompeu, placa e NVMe funcionam        | **Cenário A** |
| NVMe morreu, placa funciona                      | **Cenário B** |
| Placa queimou, NVMe está intacto                 | **Cenário C** |
| Perdi os dois, tenho só o backup                 | **Cenário D** |

---

### Cenário A: sistema corrompido, hardware vivo

O caso mais simples, e o único em que o Timeshift resolve sozinho.

**Se o sistema ainda dá boot:**

```bash
sudo timeshift --list
sudo timeshift --restore --snapshot '2026-08-08_17-00-01' --skip-grub
```

**Se não dá boot**, use um cartão SD com Orange Pi OS ou Armbian, boote por ele e restaure apontando
os dispositivos:

```bash
sudo apt install -y timeshift
sudo timeshift --restore \
  --snapshot-device /dev/sdb1 \
  --snapshot '2026-08-08_17-00-01' \
  --target /dev/nvme0n1p2 \
  --skip-grub
```

> [!IMPORTANT]
> **`--skip-grub` é obrigatório.** Esta placa não usa GRUB, e sim U-Boot. Sem essa flag, o Timeshift
> tenta reinstalar o GRUB e o processo falha, podendo deixar o sistema em estado pior.

---

### Cenário B: NVMe morreu, placa viva

A SPI da placa está intacta, então o U-Boot ainda existe. Você precisa recriar apenas o NVMe.

**1. Instale o NVMe novo e boote por cartão SD.**

**2. Recrie a área de bootloader e a tabela de partições.**

O arquivo `bootloader-raw.img` já contém o MBR protetor, a GPT primária e o bootloader, então uma
única gravação resolve os dois:

```bash
sudo dd if=/mnt/backup/bootloader-raw.img of=/dev/nvme0n1 bs=1M status=progress
sudo sync
sudo partprobe /dev/nvme0n1
```

Se o NVMe novo tiver **capacidade diferente** do antigo, a GPT secundária (que fica no fim do disco)
vai estar no lugar errado. Corrija com:

```bash
sudo apt install -y gdisk
sudo sgdisk -e /dev/nvme0n1     # move a GPT de backup para o fim real do disco
sudo partprobe /dev/nvme0n1
lsblk /dev/nvme0n1              # p1 e p2 devem aparecer
```

> [!CAUTION]
> **O disco novo precisa ser igual ou maior que o original.** A GPT restaurada declara a última LBA
> do disco antigo (aqui, `250069646`, ou seja, 119 GB). Em um disco menor, a `p2` aponta para
> setores que não existem e o `ext4` fica inacessível. Nesse caso, use a alternativa abaixo e
> reduza a `p2` manualmente antes de formatar.

> Alternativa, se preferir recriar as partições a partir do dump em texto:
> ```bash
> sudo sfdisk /dev/nvme0n1 < /mnt/backup/particoes.sfdisk
> # e só então gravar o bootloader, pulando os 34 primeiros setores para não sobrescrever a GPT:
> sudo dd if=/mnt/backup/bootloader-raw.img of=/dev/nvme0n1 bs=512 skip=34 seek=34 status=progress
> ```

**3. Formate as partições com os MESMOS identificadores.**

Este passo é o que evita ter que editar `fstab` e `orangepiEnv.txt` depois, porque os dois apontam
para UUID.

```bash
# /boot: vfat. O -i recebe o volume ID SEM o hífen (53EF-2995 vira 53EF2995)
sudo mkfs.vfat -F 32 -n opi_boot -i 53EF2995 /dev/nvme0n1p1

# /: ext4, com o UUID original
sudo mkfs.ext4 -L opi_root -U 773d663c-ff20-4993-a1f6-877050b5ca39 /dev/nvme0n1p2
```

Confirme:

```bash
sudo blkid /dev/nvme0n1p1 /dev/nvme0n1p2
```

**4. Restaure os arquivos com o Timeshift.**

```bash
sudo timeshift --restore \
  --snapshot-device /dev/sdb1 \
  --snapshot '2026-08-08_17-00-01' \
  --target /dev/nvme0n1p2 \
  --skip-grub
```

**5. Confirme que `/boot` foi restaurado.**

O Timeshift restaura `/boot` como parte do rootfs, mas nesta placa `/boot` é uma partição separada.
Monte as duas e copie manualmente se necessário:

```bash
sudo mkdir -p /mnt/{root,boot}
sudo mount /dev/nvme0n1p2 /mnt/root
sudo mount /dev/nvme0n1p1 /mnt/boot

ls /mnt/boot     # precisa ter Image, boot.scr, orangepiEnv.txt, dtb/

# Se estiver vazio, copie do rootfs restaurado:
sudo cp -a /mnt/root/boot/. /mnt/boot/
sudo sync
```

**6. Desligue, remova o SD e ligue.**

---

### Cenário C: placa queimou, NVMe intacto

**Se a placa nova já tiver o bootloader na SPI** (placas vendidas com sistema pré-instalado
costumam ter), basta transplantar o NVMe e ligar. É o caminho feliz.

**Se a placa nova tiver a SPI em branco**, o NVMe não vai dar boot, porque o BootROM do RK3588 não
lê PCIe sozinho. Restaure a SPI:

**1. Boote a placa nova por cartão SD com Orange Pi OS ou Armbian.**

**2. Grave a SPI.** Duas formas:

```bash
# Forma A: restaurar a imagem da SUA placa antiga (preserva a versão exata do U-Boot)
sudo dd if=/mnt/backup/spi-nor.img of=/dev/mtdblock0 bs=1M status=progress
sudo sync
```

```bash
# Forma B: instalar um bootloader novo pela ferramenta oficial
sudo orangepi-config
#   → System → Install → "Install bootloader on SPI Flash"
```

> Prefira a forma A se o backup for da mesma revisão de placa. Se a placa nova for de outra revisão
> ou tiver hardware diferente, use a forma B, que instala o loader correto para ela.

**3. Desligue, remova o SD, instale o NVMe e ligue.**

**4. Se o hostname ou a rede vierem errados**, é porque a placa nova tem outro MAC. Ajuste em
`/etc/netplan` ou pelo painel do OMV.

---

### Cenário D: reconstrução completa do zero

Placa nova e NVMe novo. Você tem apenas o disco de backup (`sdb1`) e o pacote da Parte 3.

**1. Grave o Orange Pi OS ou Armbian em um cartão SD** e boote a placa nova.

**2. Grave a SPI** conforme o Cenário C, passo 2.

**3. Prepare o NVMe** conforme o Cenário B, passos 2 e 3.

**4. Restaure o Timeshift** conforme o Cenário B, passo 4.

**5. Boote pelo NVMe e valide:**

```bash
# O OMV deve subir sozinho, pois /etc está restaurado
sudo systemctl status openmediavault-engined
sudo omv-salt deploy run fstab     # reaplica as montagens do OMV, se necessário

# Os discos de dados precisam estar montados
lsblk
df -hT | grep srv

# O symlink da mídia precisa apontar para um caminho que existe
ls -la /srv/midia
```

**6. Recoloque o Docker de pé.**

As imagens não estão no backup (`/var/lib/docker` é excluído), então o Docker vai baixar tudo de
novo no primeiro `up`. Como o Portainer e suas stacks estão em `/srv/portainer`, elas reaparecem no
painel:

```bash
sudo systemctl status docker
docker ps -a

# Se as stacks não subirem sozinhas, redeploy pelo Portainer, ou via SSH:
cd /srv/portainer/compose/<id>/ && docker compose up -d
```

**7. Restaure os volumes nomeados** que você exportou na Parte 4.1:

```bash
docker volume create logistics_pgdata
docker run --rm \
  -v logistics_pgdata:/destino \
  -v /mnt/backup:/origem:ro \
  alpine tar xzf /origem/logistics_pgdata.tgz -C /destino
```

**8. Restaure `/home` e `/root`.**

Se você seguiu a **opção A** da Parte 4.2 (removeu as exclusões do Timeshift), eles já vieram junto
com o snapshot e não há nada a fazer. Confira:

```bash
ls -la /home /root
```

Se você usou a **opção B** (`INCLUDE_HOME=1` no script), restaure os arquivos:

```bash
sudo tar xzf /mnt/backup/home.tgz -C /
sudo tar xzf /mnt/backup/root.tgz -C /
```

---

### 7.5. Plano B: imagem completa do NVMe

Se preferir restaurar em um passo só, faça a imagem **com a placa desligada**, bootando por cartão
SD, para que o rootfs fique consistente:

```bash
# Gerar (a partir de um boot por SD)
sudo dd if=/dev/nvme0n1 bs=4M status=progress | gzip -1 > /mnt/backup/nvme-completo.img.gz

# Restaurar
gunzip -c /mnt/backup/nvme-completo.img.gz | sudo dd of=/dev/nvme0n1 bs=4M status=progress
sudo sync
sudo sgdisk -e /dev/nvme0n1     # se o disco novo tiver capacidade diferente
```

> Isso captura tudo de uma vez, incluindo bootloader e partições. O custo é o tamanho e a
> necessidade de parar o servidor.

---

## ✅ Parte 8: Testar o backup

Backup que nunca foi restaurado é só uma esperança organizada. Teste pelo menos uma vez.

### 8.1. Teste barato (15 minutos, sem risco)

Verifica se o pacote da Parte 3 está íntegro e legível, sem tocar no servidor:

```bash
cd /srv/backup-boot/<data>/

# Os checksums batem?
sha256sum -c SHA256SUMS

# A SPI tem a assinatura Rockchip no setor 64?
dd if=spi-nor.img bs=512 skip=64 count=1 2>/dev/null | od -A d -t x1z | head -1
# esperado: 52 4b 4e 53  (RKNS)

# O bootloader do NVMe tem RKNS no setor 64 e o magic FIT no 16384?
dd if=bootloader-raw.img bs=512 skip=64 count=1 2>/dev/null | od -A d -t x1z | head -1
dd if=bootloader-raw.img bs=512 skip=16384 count=1 2>/dev/null | od -A d -t x1z | head -1
# esperado: d0 0d fe ed

# A tabela de partições está legível?
cat particoes.sfdisk
```

### 8.2. Teste real (a única prova que vale)

Pegue **outro** NVMe ou cartão SD, e execute o Cenário B inteiro nele, sem tocar no disco de
produção. Se a placa bootar pelo disco de teste, o backup está provado.

Faça isso uma vez agora, e depois de qualquer mudança grande no sistema (upgrade de OMV, troca de
kernel, mudança de particionamento).

---

## ⚠️ Troubleshooting

| Sintoma                                                    | Causa provável                                | Solução                                                                       |
| :--------------------------------------------------------- | :-------------------------------------------- | :---------------------------------------------------------------------------- |
| Placa não dá sinal de vídeo nem de rede após restaurar      | SPI em branco na placa nova                   | Cenário C, passo 2                                                            |
| U-Boot aparece mas não encontra o sistema                   | UUID do root diferente do esperado            | Conferir `rootdev=` em `/boot/orangepiEnv.txt` contra `blkid`                  |
| Boot para em `Failed to mount /boot`                        | `p1` formatada com volume ID diferente        | `mkfs.vfat -i 53EF2995` ou corrigir a linha do `/boot` no `/etc/fstab`         |
| Timeshift falha com erro de GRUB                            | Faltou `--skip-grub`                          | Refazer o restore com a flag                                                   |
| Sistema sobe mas as stacks somem                            | Docker baixando imagens do zero               | Normal. Aguardar, ou redeployar pelo Portainer                                 |
| Stack sobe mas o banco está vazio                           | Volume nomeado não restaurado                 | Parte 7, Cenário D, passo 7                                                    |
| `/srv/midia` aponta para lugar nenhum                       | UUID do HD de mídia mudou                     | Recriar o symlink para o novo caminho `/srv/dev-disk-by-uuid-.../midia`        |
| Discos de dados não montam após restaurar                   | OMV precisa reaplicar a configuração          | `sudo omv-salt deploy run fstab`                                               |
| `sgdisk: command not found`                                 | Binário em `/sbin`, fora do `PATH` do usuário | Usar `sudo sgdisk` ou `/sbin/sgdisk`. Se faltar mesmo: `sudo apt install gdisk` |
| `permissão negada` em `sudo comando > arquivo`              | O `>` é do shell, não do `sudo`               | `sudo comando \| sudo tee arquivo > /dev/null`                                  |
| `parse error near '}'` ao tentar `sudo { ... }`             | `{ }` é construção do shell, não um programa  | Pôr o `sudo` nos comandos de dentro do bloco, e `\| sudo tee` na saída          |
| `permission denied ... docker.sock`                         | Usuário fora do grupo `docker`                | Usar `sudo docker`, ou `sudo usermod -aG docker $USER` e reabrir a sessão       |
| Arquivo de backup gerado com 20 bytes                       | Dump de um banco que não existe mais          | 20 bytes é um gzip vazio. Ver **Notas Importantes**, backup que falha em silêncio |
| `dd` da SPI resulta em arquivo só de zeros                   | Placa sem bootloader na SPI (boota de SD/eMMC)| Normal em algumas configurações. Nesse caso o Cenário C exige a forma B        |
| GPT inválida após restaurar em disco maior                  | GPT secundária no lugar antigo                | `sudo sgdisk -e /dev/nvme0n1`                                                  |

---

## 📌 Notas Importantes

- **`--skip-grub` sempre.** Placa ARM com U-Boot, não GRUB.
- **O backup vive no mesmo gabinete.** Enquanto não houver cópia fora do local, um único evento
  físico leva original e backup juntos.
- **`/var/log` está em zram**, ou seja, em RAM. Os logs somem a cada reboot, por decisão do plugin
  `openmediavault-flashmemory` para poupar escritas. Não conte com log histórico para investigar um
  problema pós-reboot.
- **Backup que falha em silêncio é pior que backup nenhum**, porque ele te dá confiança falsa.
  Caso real neste servidor: o `/srv/logistics/infra/backup.sh` roda todo dia às 03:00 e gera
  `atlas_AAAAMMDD.sql.gz`. Quando o container do banco foi removido, o `pg_dump` passou a falhar,
  mas o `gzip` continuou produzindo um arquivo. O resultado são dumps de **20 bytes** (um gzip
  vazio) com data de hoje, que parecem backups recentes numa listagem por data. Monitore
  **tamanho**, não só existência:

  ```bash
  # Alerta se o dump de hoje tiver menos de 1 KB
  find /srv/<serviço>/backups -name '*.sql.gz' -mtime -1 -size -1k \
    -exec echo "ALERTA: backup suspeito: {}" \;
  ```

  Em scripts de dump, use `set -o pipefail` e verifique o código de saída do `pg_dump` antes de
  compactar. Sem isso, o `pg_dump ... | gzip > arquivo` retorna sucesso mesmo com o `pg_dump`
  falhando.

- **Arquivos soltos na raiz de `/srv/backup-boot` não são rotacionados.** O script só remove
  subpastas com nome de data (`20*`). Se você rodar os comandos manuais da Parte 3 apontando para a
  raiz, esses arquivos ficam lá para sempre, ocupando espaço em duplicidade. Rode-os em uma subpasta
  ou apague depois de conferir.

- **Anote os UUIDs em papel.** Eles estão no `inventario.txt` do backup, mas se o backup não abrir,
  você vai querer esses números em algum lugar que não dependa do servidor.
- **Snapshot manual antes de qualquer mudança grande.** Upgrade de OMV, troca de kernel,
  reparticionamento.
- **Migre volumes nomeados para bind mount em `/srv`.** É a correção definitiva para o ponto cego do
  `/var/lib/docker`.
- **A biblioteca de mídia não tem backup, e isso é uma decisão consciente.** São 438 GB de conteúdo
  re-baixável. Se algo lá for insubstituível (vídeo de família, acervo raro), tire desse disco e
  trate separadamente.

---

## 🌐 Acessos

| Recurso                     | Onde                                                       |
| :-------------------------- | :--------------------------------------------------------- |
| Painel do OMV               | `http://192.168.x.x`                                        |
| Timeshift no OMV            | **Serviços** → **Timeshift**                                |
| Snapshots (arquivos)        | `/srv/dev-disk-by-uuid-ac8dc031-.../timeshift/snapshots/`   |
| Pacote de boot              | `/srv/backup-boot/<data>/`                                  |
| Script de backup            | `/usr/local/bin/orangepi5-backup-boot.sh`                   |
| Log do backup               | `/var/log/backup-boot.log`                                  |

---

## 📚 Referências

- [Documentação do Timeshift](https://github.com/linuxmint/timeshift)
- [Plugin openmediavault-timeshift](https://github.com/OpenMediaVault-Plugin-Developers/openmediavault-timeshift)
- [Orange Pi 5, manual do usuário](http://www.orangepi.org/orangepiwiki/index.php/Orange_Pi_5)
- [Armbian, boot em placas Rockchip](https://docs.armbian.com/User-Guide_Getting-Started/)
- [Rockchip: layout de boot e idbloader](https://opensource.rock-chips.com/wiki_Boot_option)
- [`./portainer-debian.md`](./portainer-debian.md), instalação do Docker e Portainer
- [`./midia.md`](./midia.md), a stack de mídia deste servidor
