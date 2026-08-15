#!/bin/bash
# Backup das camadas que o Timeshift NAO cobre em uma Orange Pi 5 (RK3588).
#
# Captura, com a placa ligada e em producao:
#   1. SPI NOR (bootloader da placa)          ~16 MB
#   2. Area de bootloader do NVMe             ~30 MB
#   3. Tabela de particoes (GPT), 2 formatos  ~40 KB
#   4. Inventario do sistema + stacks do Portainer
#   5. Volumes nomeados do Docker             (variavel)
#   6. /home e /root                          (opcional, ver INCLUDE_HOME)
#
# Uso:
#   sudo ./orangepi5-backup-boot.sh [destino]
#
# Variaveis de ambiente:
#   BOOT_DISK=/dev/nvme0n1   disco de sistema
#   SPI_DEV=/dev/mtdblock0   SPI NOR
#   KEEP=4                   quantas rodadas manter
#   INCLUDE_HOME=0           1 para incluir /home e /root no tar (ver nota abaixo)
#
# Cron semanal (domingo 03:00):
#   0 3 * * 0 root /usr/local/bin/orangepi5-backup-boot.sh >> /var/log/backup-boot.log 2>&1
#
# NOTA sobre INCLUDE_HOME: /home e /root podem somar varios GB, e um tar completo
# a cada rodada nao faz dedupe. A alternativa melhor e remover "/home/**" e
# "/root/**" das exclusoes do Timeshift, que faz snapshot incremental com hardlink
# e nao duplica nada. Use INCLUDE_HOME=1 apenas se preferir mante-los excluidos la.
#
# Ver docs/orangepi5-backup-restore.md

set -euo pipefail

# ─── Configuracao ────────────────────────────────────────────────────────────
BOOT_DISK="${BOOT_DISK:-/dev/nvme0n1}"
SPI_DEV="${SPI_DEV:-/dev/mtdblock0}"
DEST="${1:-/srv/backup-boot}"
KEEP="${KEEP:-4}"
INCLUDE_HOME="${INCLUDE_HOME:-0}"

STAMP="$(date +%Y-%m-%d_%H-%M-%S)"
OUT="${DEST}/${STAMP}"

falhas=0
aviso() { echo "AVISO: $*" >&2; falhas=$((falhas + 1)); }

if [[ $EUID -ne 0 ]]; then
  echo "ERRO: rode com sudo." >&2
  exit 1
fi

if [[ ! -b "$BOOT_DISK" ]]; then
  echo "ERRO: $BOOT_DISK nao e um dispositivo de bloco. Ajuste BOOT_DISK." >&2
  exit 1
fi

mkdir -p "$OUT"
echo "==> Destino: $OUT"

# Espaco livre minimo (MB). Sobe para 6 GB se for incluir /home e /root.
MIN_LIVRE=200
[[ "$INCLUDE_HOME" == "1" ]] && MIN_LIVRE=6000
LIVRE_MB="$(df -Pm "$DEST" | awk 'NR==2 {print $4}')"
if [[ "$LIVRE_MB" -lt "$MIN_LIVRE" ]]; then
  echo "ERRO: apenas ${LIVRE_MB} MB livres em $DEST, precisa de ${MIN_LIVRE} MB." >&2
  exit 1
fi

# ─── 1. SPI NOR ──────────────────────────────────────────────────────────────
if [[ -e "$SPI_DEV" ]]; then
  echo "==> [1/6] SPI NOR ($SPI_DEV)"
  dd if="$SPI_DEV" of="${OUT}/spi-nor.img" bs=1M status=none
  # Assinatura Rockchip (RKNS = 52 4b 4e 53) no setor 64
  if dd if="${OUT}/spi-nor.img" bs=512 skip=64 count=1 2>/dev/null \
       | od -An -t x1 | head -1 | grep -q "52 4b 4e 53"; then
    echo "    OK, assinatura RKNS presente ($(du -h "${OUT}/spi-nor.img" | cut -f1))"
  else
    aviso "SPI sem assinatura RKNS no setor 64. Esta placa pode nao bootar pela SPI."
  fi
else
  aviso "SPI NOR nao encontrada em $SPI_DEV, pulando."
fi

# ─── 2. Bootloader raw do NVMe ───────────────────────────────────────────────
# Copia tudo que existe ANTES da primeira particao: MBR protetor, GPT primaria,
# idbloader (setor 64) e u-boot.itb (setor 16384).
echo "==> [2/6] Bootloader do NVMe"
FIRST_SECTOR="$(partx -g -o START "$BOOT_DISK" 2>/dev/null | head -1 | tr -d ' ')"
if ! [[ "$FIRST_SECTOR" =~ ^[0-9]+$ ]] || [[ "$FIRST_SECTOR" -lt 2048 ]]; then
  echo "ERRO: nao consegui ler o primeiro setor de $BOOT_DISK (valor: '${FIRST_SECTOR}')." >&2
  exit 1
fi
COUNT_MB=$(( FIRST_SECTOR * 512 / 1024 / 1024 ))
[[ "$COUNT_MB" -lt 1 ]] && COUNT_MB=1
echo "    primeira particao no setor ${FIRST_SECTOR}, copiando ${COUNT_MB} MB"
dd if="$BOOT_DISK" of="${OUT}/bootloader-raw.img" bs=1M count="$COUNT_MB" status=none
echo "$FIRST_SECTOR" > "${OUT}/primeiro-setor.txt"

# Magic do FIT (u-boot.itb) no setor 16384: d0 0d fe ed
if dd if="${OUT}/bootloader-raw.img" bs=512 skip=16384 count=1 2>/dev/null \
     | od -An -t x1 | head -1 | grep -q "d0 0d fe ed"; then
  echo "    OK, u-boot.itb presente ($(du -h "${OUT}/bootloader-raw.img" | cut -f1))"
else
  aviso "u-boot.itb nao encontrado no setor 16384 do NVMe."
fi

# ─── 3. Tabela de particoes ──────────────────────────────────────────────────
echo "==> [3/6] Tabela de particoes"
sfdisk --dump "$BOOT_DISK" > "${OUT}/particoes.sfdisk"
if command -v sgdisk >/dev/null 2>&1; then
  sgdisk --backup="${OUT}/particoes.gpt" "$BOOT_DISK" >/dev/null
  echo "    sfdisk + sgdisk"
else
  echo "    apenas sfdisk (instale 'gdisk' para o backup binario da GPT)"
fi

# ─── 4. Inventario do sistema ────────────────────────────────────────────────
echo "==> [4/6] Inventario"
{
  echo "### Gerado em $STAMP"
  echo
  echo "### hostname"; hostname
  echo
  echo "### modelo"; cat /proc/device-tree/model 2>/dev/null; echo
  echo
  echo "### kernel"; uname -a
  echo
  echo "### so"; cat /etc/os-release
  echo
  echo "### lsblk"; lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINT
  echo
  echo "### blkid"; blkid
  echo
  echo "### fstab"; cat /etc/fstab
  echo
  echo "### orangepiEnv.txt"; cat /boot/orangepiEnv.txt 2>/dev/null
  echo
  echo "### pacotes de boot"; dpkg -l | grep -iE "u-boot|linux-image|orangepi|openmediavault" || true
  echo
  echo "### docker: containers"; docker ps -a --format '{{.Names}}\t{{.Image}}' 2>/dev/null || true
  echo
  echo "### docker: volumes"; docker volume ls 2>/dev/null || true
  echo
  echo "### timeshift"; cat /etc/timeshift/timeshift.json 2>/dev/null
} > "${OUT}/inventario.txt"

dpkg --get-selections > "${OUT}/pacotes.list"

# Os YAML de todas as stacks do Portainer
if [[ -d /srv/portainer/compose ]]; then
  tar czf "${OUT}/portainer-compose.tgz" -C /srv/portainer compose 2>/dev/null \
    || aviso "falha ao arquivar /srv/portainer/compose"
fi

# ─── 5. Volumes nomeados do Docker ───────────────────────────────────────────
# O Timeshift exclui /var/lib/docker internamente, entao volumes nomeados NAO
# entram nos snapshots. Bind mounts em /srv entram normalmente.
echo "==> [5/6] Volumes nomeados do Docker"
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  # Apenas volumes com nome legivel; os de hash sao camadas anonimas descartaveis.
  # O `|| true` evita que o grep sem match derrube o script sob `pipefail`.
  VOLUMES="$(docker volume ls --format '{{.Name}}' 2>/dev/null \
             | grep -vE '^[0-9a-f]{64}$' || true)"
  if [[ -n "$VOLUMES" ]]; then
    if ! docker image inspect alpine >/dev/null 2>&1; then
      echo "    baixando a imagem alpine (necessaria para exportar os volumes)"
      docker pull -q alpine >/dev/null 2>&1 || aviso "sem a imagem alpine, volumes nao exportados"
    fi
    mkdir -p "${OUT}/docker-volumes"
    while read -r vol; do
      [[ -z "$vol" ]] && continue
      echo "    - $vol"
      docker run --rm \
        -v "${vol}:/origem:ro" \
        -v "${OUT}/docker-volumes:/destino" \
        alpine tar czf "/destino/${vol}.tgz" -C /origem . 2>/dev/null \
        || aviso "falha ao exportar o volume $vol"
    done <<< "$VOLUMES"
  else
    echo "    nenhum volume nomeado, nada a fazer"
  fi
else
  echo "    Docker indisponivel, pulando"
fi

# ─── 6. /home e /root (opcional) ─────────────────────────────────────────────
if [[ "$INCLUDE_HOME" == "1" ]]; then
  echo "==> [6/6] /home e /root"
  tar czf "${OUT}/home.tgz" -C / home 2>/dev/null || aviso "falha ao arquivar /home"
  tar czf "${OUT}/root.tgz" -C / root 2>/dev/null || aviso "falha ao arquivar /root"
else
  echo "==> [6/6] /home e /root: pulados (INCLUDE_HOME=0)"
  echo "    Prefira remover '/home/**' e '/root/**' das exclusoes do Timeshift:"
  echo "    ele faz snapshot incremental com hardlink e nao duplica os dados."
fi

# ─── Checksums e rotacao ─────────────────────────────────────────────────────
( cd "$OUT" && find . -type f ! -name SHA256SUMS -exec sha256sum {} + > SHA256SUMS )

echo "==> Rodadas antigas (mantendo as ultimas ${KEEP})"
find "$DEST" -maxdepth 1 -mindepth 1 -type d -name '20*' \
  | sort -r | tail -n +"$((KEEP + 1))" \
  | while read -r old; do echo "    removendo $old"; rm -rf "$old"; done

echo
echo "==> Concluido: $OUT  ($(du -sh "$OUT" | cut -f1))"
if [[ "$falhas" -gt 0 ]]; then
  echo "==> ATENCAO: ${falhas} aviso(s) acima. Revise antes de confiar neste backup."
fi
echo
echo "LEMBRETE: copie esta pasta para FORA do servidor."
exit 0
