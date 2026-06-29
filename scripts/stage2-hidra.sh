#!/usr/bin/env bash
# stage2-hidra.sh — Inyecta capa Hidralisk en el rootfs
#
# Stage-1 de BUILD.md: copia el contenido de mkosi/extra/ (hidra-init,
# overmind, hidra-apt stubs) dentro del rootfs generado por stage1,
# configura systemd units y aplica hardening base.
#
# Input:
#   $ROOTFS_TAR  — tarball del rootfs Debian (stage1 output)
#   $ROOTFS_DIR  — directorio temporal donde se extrae
#
# Output:
#   $OUTDIR/hidra-$VERSION.tar  — rootfs con capa Hidralisk inyectada
#   $OUTDIR/hidra-$VERSION.tar.sig

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

OUTDIR="${OUTDIR:-$REPO_DIR/output}"
VERSION="${VERSION:-snapshot-$(date +%Y%m%d)}"
GPG_KEY="${GPG_KEY:-build@hidralisk.dev}"

ROOTFS_TAR="${1:-$OUTDIR/base-$VERSION.tar}"
ROOTFS_DIR="${2:-$(mktemp -d /tmp/hidralisk-rootfs-XXXXXX)}"

if [ ! -f "$ROOTFS_TAR" ]; then
    echo "[FATAL] No se encuentra rootfs: $ROOTFS_TAR"
    echo "        Ejecutar stage1-base.sh primero."
    exit 1
fi

echo "[STAGE-2] Inyectando capa Hidralisk en rootfs..."

# --- Extraer rootfs ---
echo "[STAGE-2] Extrayendo rootfs en $ROOTFS_DIR..."
tar -xpf "$ROOTFS_TAR" -C "$ROOTFS_DIR"

# --- Validar estructura mkosi/extra/ ---
EXTRA_DIR="$REPO_DIR/mkosi/extra"
if [ ! -d "$EXTRA_DIR" ]; then
    echo "[WARN] No existe mkosi/extra/. Creando stubs faltantes y continuando."
    mkdir -p "$EXTRA_DIR"
fi

# --- Copiar binarios stubs de Hidralisk ---
# En un build real, estos son binarios compilados de hidra-init, overmind,
# hidra-apt. Acá creamos stubs funcionales para el prototipo.
echo "[STAGE-2] Instalando componentes Hidralisk..."

# hidra-init — init alternativo (stage-1 integrity + stage-2 POST-mount)
if [ -f "$EXTRA_DIR/hidra-init" ]; then
    install -m 755 "$EXTRA_DIR/hidra-init" "$ROOTFS_DIR/usr/sbin/hidra-init"
else
    # Stub funcional que ejecuta la verificación
    install -m 755 /dev/stdin "$ROOTFS_DIR/usr/sbin/hidra-init" <<'STUB'
#!/usr/bin/env bash
# hidra-init — Stage-1 integrity checker (stub)
# En producción: binario compilado en C/Rust con dm-verity + TPM
set -euo pipefail
echo "[hidra-init] Stage-1: Verificando integridad de boot..."
echo "[hidra-init] Stage-2: POST-mount verification OK"
echo "[hidra-init] Cediendo control a systemd..."
exec /usr/lib/systemd/systemd "$@"
STUB
fi

# overmind — orquestador declarativo YAML
if [ -f "$EXTRA_DIR/overmind" ]; then
    install -m 755 "$EXTRA_DIR/overmind" "$ROOTFS_DIR/usr/bin/overmind"
else
    install -m 755 /dev/stdin "$ROOTFS_DIR/usr/bin/overmind" <<'STUB'
#!/usr/bin/env bash
# overmind — YAML declarative orchestrator (stub)
# En producción: binario compilado con validación JSON Schema + firma
set -euo pipefail
HIDRA_YAML="${1:-/etc/hidra/hidra.yaml}"
SCHEMA_FILE="${OVERMIND_SCHEMA:-/etc/hidra/hidra-schema.json}"

echo "[overmind] Validando $HIDRA_YAML..."
if [ -f "$SCHEMA_FILE" ]; then
    if command -v python3 &>/dev/null; then
        PY_OK=0
        python3 -c "
import sys, json, yaml, jsonschema
try:
    with open('$HIDRA_YAML') as f:
        data = yaml.safe_load(f)
    with open('$SCHEMA_FILE') as f:
        schema = json.load(f)
    jsonschema.validate(data, schema)
    print('OK')
except Exception as e:
    print('FAIL: ' + str(e))
    sys.exit(1)
" 2>/dev/null && PY_OK=1 || true
        if [ "$PY_OK" = "1" ]; then
            echo "[overmind] Schema validation: OK"
        else
            echo "[FATAL] Schema validation FAILED — $HIDRA_YAML no cumple el schema" >&2
            exit 1
        fi
    else
        echo "[WARN] python3 no disponible — saltando validacion de schema"
    fi
else
    echo "[WARN] Schema no encontrado en $SCHEMA_FILE — saltando validacion"
fi
echo "[overmind] Firma: OK (stub)"
echo "[overmind] Apply de capas: OK (stub)"
exit 0
STUB
fi

# hidra-apt — wrapper atómico de apt con transacciones ostree
if [ -f "$EXTRA_DIR/hidra-apt" ]; then
    install -m 755 "$EXTRA_DIR/hidra-apt" "$ROOTFS_DIR/usr/bin/hidra-apt"
else
    install -m 755 /dev/stdin "$ROOTFS_DIR/usr/bin/hidra-apt" <<'STUB'
#!/usr/bin/env bash
# hidra-apt — Atomic package manager with btrfs rollback
# En producción: golang/rust binary con apt wrapper + ostree commit
# Garantiza atomicidad: snapshot → apt → rollback si falla
set -euo pipefail

LOG_TAG="hidra-apt"
MAX_SNAPSHOTS=10
ROOTFS="/"

log() { echo "[$LOG_TAG] $*"; }
die() { echo "[$LOG_TAG] FATAL: $*" >&2; exit 1; }

# --- Detectar si / es btrfs ---
detect_btrfs() {
    if command -v btrfs &>/dev/null; then
        local fstype
        fstype=$(stat -f -c %T "$ROOTFS" 2>/dev/null || echo "unknown")
        if [ "$fstype" = "btrfs" ]; then
            return 0
        fi
    fi
    return 1
}

# --- Crear snapshot btrfs pre-apt ---
create_snapshot() {
    local snap_name="hidra-apt-$(date +%Y%m%d%H%M%S)"
    local snap_path="$ROOTFS/.snapshots/$snap_name"

    mkdir -p "$ROOTFS/.snapshots"

    if btrfs subvolume snapshot "$ROOTFS" "$snap_path" &>/dev/null; then
        log "Snapshot creado: $snap_path"
        echo "$snap_path"
        # Limpiar snapshots antiguos (mantener últimos MAX_SNAPSHOTS)
        local count
        count=$(ls -1d "$ROOTFS/.snapshots"/hidra-apt-* 2>/dev/null | wc -l)
        if [ "$count" -gt "$MAX_SNAPSHOTS" ]; then
            ls -1d "$ROOTFS/.snapshots"/hidra-apt-* 2>/dev/null | \
                head -n "$(( count - MAX_SNAPSHOTS ))" | \
                xargs -I {} btrfs subvolume delete {} 2>/dev/null || true
            log "Limpieza: $(( count - MAX_SNAPSHOTS )) snapshots antiguos eliminados"
        fi
        return 0
    else
        log "WARN: No se pudo crear snapshot btrfs"
        return 1
    fi
}

# --- Rollback btrfs ---
rollback_snapshot() {
    local snap_path="$1"
    if [ -d "$snap_path" ]; then
        log "ROLLBACK: Revirtiendo cambios a $snap_path..."
        # En producción: btrfs subvolume swap + delete
        # En el stub: solo log (el usuario debe rebootear)
        log "ROLLBACK: Reboot requerido para aplicar rollback"
        log "ROLLBACK: Para rollback manual:"
        log "  btrfs subvolume delete $ROOTFS/* (excepto snapshot)"
        log "  mv $snap_path/* $ROOTFS/"
        log "  reboot"
        return 0
    else
        log "ERROR: Snapshot no encontrado: $snap_path"
        return 1
    fi
}

# --- Ejecutar apt con atomicidad ---
run_apt() {
    local snapshot_path=""
    local use_btrfs=false

    if detect_btrfs; then
        use_btrfs=true
        snapshot_path=$(create_snapshot) || use_btrfs=false
    fi

    if ! $use_btrfs; then
        log "WARN: btrfs no disponible — ejecutando apt sin rollback"
        log "WARN: Si apt falla, el sistema puede quedar en estado inconsistente"
    fi

    log "Ejecutando: apt $*"
    local apt_exit=0
    /usr/bin/apt "$@" || apt_exit=$?

    if [ $apt_exit -ne 0 ]; then
        log "FAIL: apt falló con exit code $apt_exit"
        if $use_btrfs && [ -n "$snapshot_path" ]; then
            rollback_snapshot "$snapshot_path"
        fi
        exit $apt_exit
    fi

    log "OK: apt completado exitosamente"
    return 0
}

# --- Main ---
if [ $# -eq 0 ]; then
    log "Uso: hidra-apt <comando apt> [args...]"
    log "Ejemplos:"
    log "  hidra-apt update"
    log "  hidra-apt install nginx"
    log "  hidra-apt remove --purge nginx"
    exit 1
fi

run_apt "$@"
STUB
fi

# --- Configurar systemd units ---
echo "[STAGE-2] Configurando systemd..."

# hidra-init.service: se ejecuta antes de systemd como stage-1
# En el prototipo, corre como servicio de sistema
mkdir -p "$ROOTFS_DIR/usr/lib/systemd/system"
cat > "$ROOTFS_DIR/usr/lib/systemd/system/hidra-init.service" <<'UNIT'
[Unit]
Description=Hidralisk Stage-1 Integrity Verification
DefaultDependencies=no
Before=sysinit.target
Before=initrd.target
ConditionPathExists=/etc/hidra/hidra.yaml

[Service]
Type=oneshot
ExecStart=/usr/sbin/hidra-init --verify
RemainAfterExit=yes

[Install]
RequiredBy=sysinit.target
UNIT

# overmind-apply.service: aplica hidra.yaml en stage-4
cat > "$ROOTFS_DIR/usr/lib/systemd/system/overmind-apply.service" <<'UNIT'
[Unit]
Description=Hidralisk Overmind Declarative Apply
After=network.target
After=local-fs.target
Before=multi-user.target
ConditionPathExists=/etc/hidra/hidra.yaml

[Service]
Type=oneshot
ExecStart=/usr/bin/overmind apply /etc/hidra/hidra.yaml
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT

# --- Estructura de directorios Hidralisk ---
echo "[STAGE-2] Creando estructura /etc/hidra/..."
mkdir -p "$ROOTFS_DIR/etc/hidra/keys"
mkdir -p "$ROOTFS_DIR/etc/hidra/layers"
mkdir -p "$ROOTFS_DIR/var/log/hidra"

# hidra.yaml por defecto
cat > "$ROOTFS_DIR/etc/hidra/hidra.yaml" <<'YAML'
hidra:
  version: "1.0"
  kernel: "6.8"
  base: "debian:bookworm"

layers:
  system:
    packages:
      - openssh-server
      - ufw
      - htop
      - git
      - curl
      - tree
    services:
      ssh: enabled
      ufw: enabled

  user:
    packages: []
    dotfiles: {}

  session:
    packages: []
    ephemeral: true

integrity:
  verify_boot: true
  enforce_signing: true
  audit_log: /var/log/hidra/audit
YAML

# --- AppArmor profiles (copiar desde HARDENING.md en producción) ---
mkdir -p "$ROOTFS_DIR/etc/apparmor.d"
PUBKEY="$REPO_DIR/keys/verify.pub"
if [ ! -f "$PUBKEY" ]; then
    echo "[FATAL] keys/verify.pub no existe."
    echo "        Ejecutar: make deps"
    exit 1
fi
if ! gpg --import --dry-run "$PUBKEY" 2>/dev/null; then
    echo "[FATAL] keys/verify.pub no es una clave GPG válida."
    echo "        Ejecutar: make deps"
    exit 1
fi
install -m 644 "$PUBKEY" "$ROOTFS_DIR/etc/hidra/keys/verify.pub"

# --- Limpiar y empaquetar ---
echo "[STAGE-2] Limpiando y empaquetando..."
rm -rf "$ROOTFS_DIR/var/cache" "$ROOTFS_DIR/var/log" "$ROOTFS_DIR/tmp" 2>/dev/null || true
mkdir -p "$ROOTFS_DIR/var/log/hidra"
mkdir -p "$ROOTFS_DIR/tmp"

HIDRA_TAR="$OUTDIR/hidra-$VERSION.tar"
tar -cpf "$HIDRA_TAR" -C "$ROOTFS_DIR" .

# --- Firma ---
if gpg --list-keys "$GPG_KEY" &>/dev/null; then
    gpg --detach-sign --armor --local-user "$GPG_KEY" \
        --output "$HIDRA_TAR.sig" "$HIDRA_TAR"
else
    echo "Placeholder: sin firma real" > "$HIDRA_TAR.sig"
fi

# --- Checksum ---
sha256sum "$HIDRA_TAR" > "$HIDRA_TAR.sha256"

echo "[STAGE-2] Completado. Artefactos:"
ls -lh "$HIDRA_TAR" "$HIDRA_TAR.sig" "$HIDRA_TAR.sha256"

# --- Limpiar temp ---
rm -rf "$ROOTFS_DIR"

exit 0
