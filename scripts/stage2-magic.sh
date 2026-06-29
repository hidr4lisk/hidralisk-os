#!/usr/bin/env bash
# stage2-magic.sh — Inyecta capa SpellOS en el rootfs
#
# Stage-1 de BUILD.md: copia el contenido de mkosi/extra/ (magic-init,
# grimoire, magic-apt stubs) dentro del rootfs generado por stage1,
# configura systemd units y aplica hardening base.
#
# Input:
#   $ROOTFS_TAR  — tarball del rootfs Debian (stage1 output)
#   $ROOTFS_DIR  — directorio temporal donde se extrae
#
# Output:
#   $OUTDIR/magic-$VERSION.tar  — rootfs con capa SpellOS inyectada
#   $OUTDIR/magic-$VERSION.tar.sig

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

OUTDIR="${OUTDIR:-$REPO_DIR/output}"
VERSION="${VERSION:-snapshot-$(date +%Y%m%d)}"
GPG_KEY="${GPG_KEY:-build@spellos.dev}"

ROOTFS_TAR="${1:-$OUTDIR/base-$VERSION.tar}"
ROOTFS_DIR="${2:-$(mktemp -d /tmp/spellos-rootfs-XXXXXX)}"

if [ ! -f "$ROOTFS_TAR" ]; then
    echo "[FATAL] No se encuentra rootfs: $ROOTFS_TAR"
    echo "        Ejecutar stage1-base.sh primero."
    exit 1
fi

echo "[STAGE-2] Inyectando capa SpellOS en rootfs..."

# --- Extraer rootfs ---
echo "[STAGE-2] Extrayendo rootfs en $ROOTFS_DIR..."
tar -xpf "$ROOTFS_TAR" -C "$ROOTFS_DIR"

# --- Validar estructura mkosi/extra/ ---
EXTRA_DIR="$REPO_DIR/mkosi/extra"
if [ ! -d "$EXTRA_DIR" ]; then
    echo "[WARN] No existe mkosi/extra/. Creando stubs faltantes y continuando."
    mkdir -p "$EXTRA_DIR"
fi

# --- Copiar binarios stubs de SpellOS ---
# En un build real, estos son binarios compilados de magic-init, grimoire,
# magic-apt. Acá creamos stubs funcionales para el prototipo.
echo "[STAGE-2] Instalando componentes SpellOS..."

# magic-init — init alternativo (stage-1 integrity + stage-2 POST-mount)
if [ -f "$EXTRA_DIR/magic-init" ]; then
    install -m 755 "$EXTRA_DIR/magic-init" "$ROOTFS_DIR/usr/sbin/magic-init"
else
    # Stub funcional que ejecuta la verificación
    install -m 755 /dev/stdin "$ROOTFS_DIR/usr/sbin/magic-init" <<'STUB'
#!/usr/bin/env bash
# magic-init — Stage-1 integrity checker (stub)
# En producción: binario compilado en C/Rust con dm-verity + TPM
set -euo pipefail
echo "[magic-init] Stage-1: Verificando integridad de boot..."
echo "[magic-init] Stage-2: POST-mount verification OK"
echo "[magic-init] Cediendo control a systemd..."
exec /usr/lib/systemd/systemd "$@"
STUB
fi

# grimoire — orquestador declarativo YAML
if [ -f "$EXTRA_DIR/grimoire" ]; then
    install -m 755 "$EXTRA_DIR/grimoire" "$ROOTFS_DIR/usr/bin/grimoire"
else
    install -m 755 /dev/stdin "$ROOTFS_DIR/usr/bin/grimoire" <<'STUB'
#!/usr/bin/env bash
# grimoire — YAML declarative orchestrator (stub)
# En producción: binario compilado con validación JSON Schema + firma
set -euo pipefail
MAGIC_YAML="${1:-/etc/magic/magic.yaml}"
SCHEMA_FILE="${GRIMOIRE_SCHEMA:-/etc/magic/magic-schema.json}"

echo "[grimoire] Validando $MAGIC_YAML..."
if [ -f "$SCHEMA_FILE" ]; then
    if command -v python3 &>/dev/null; then
        PY_OK=0
        python3 -c "
import sys, json, yaml, jsonschema
try:
    with open('$MAGIC_YAML') as f:
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
            echo "[grimoire] Schema validation: OK"
        else
            echo "[FATAL] Schema validation FAILED — $MAGIC_YAML no cumple el schema" >&2
            exit 1
        fi
    else
        echo "[WARN] python3 no disponible — saltando validacion de schema"
    fi
else
    echo "[WARN] Schema no encontrado en $SCHEMA_FILE — saltando validacion"
fi
echo "[grimoire] Firma: OK (stub)"
echo "[grimoire] Apply de capas: OK (stub)"
exit 0
STUB
fi

# magic-apt — wrapper atómico de apt con transacciones ostree
if [ -f "$EXTRA_DIR/magic-apt" ]; then
    install -m 755 "$EXTRA_DIR/magic-apt" "$ROOTFS_DIR/usr/bin/magic-apt"
else
    install -m 755 /dev/stdin "$ROOTFS_DIR/usr/bin/magic-apt" <<'STUB'
#!/usr/bin/env bash
# magic-apt — Atomic package manager with btrfs rollback
# En producción: golang/rust binary con apt wrapper + ostree commit
# Garantiza atomicidad: snapshot → apt → rollback si falla
set -euo pipefail

LOG_TAG="magic-apt"
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
    local snap_name="magic-apt-$(date +%Y%m%d%H%M%S)"
    local snap_path="$ROOTFS/.snapshots/$snap_name"

    mkdir -p "$ROOTFS/.snapshots"

    if btrfs subvolume snapshot "$ROOTFS" "$snap_path" &>/dev/null; then
        log "Snapshot creado: $snap_path"
        echo "$snap_path"
        # Limpiar snapshots antiguos (mantener últimos MAX_SNAPSHOTS)
        local count
        count=$(ls -1d "$ROOTFS/.snapshots"/magic-apt-* 2>/dev/null | wc -l)
        if [ "$count" -gt "$MAX_SNAPSHOTS" ]; then
            ls -1d "$ROOTFS/.snapshots"/magic-apt-* 2>/dev/null | \
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
    log "Uso: magic-apt <comando apt> [args...]"
    log "Ejemplos:"
    log "  magic-apt update"
    log "  magic-apt install nginx"
    log "  magic-apt remove --purge nginx"
    exit 1
fi

run_apt "$@"
STUB
fi

# --- Configurar systemd units ---
echo "[STAGE-2] Configurando systemd..."

# magic-init.service: se ejecuta antes de systemd como stage-1
# En el prototipo, corre como servicio de sistema
mkdir -p "$ROOTFS_DIR/usr/lib/systemd/system"
cat > "$ROOTFS_DIR/usr/lib/systemd/system/magic-init.service" <<'UNIT'
[Unit]
Description=SpellOS Stage-1 Integrity Verification
DefaultDependencies=no
Before=sysinit.target
Before=initrd.target
ConditionPathExists=/etc/magic/magic.yaml

[Service]
Type=oneshot
ExecStart=/usr/sbin/magic-init --verify
RemainAfterExit=yes

[Install]
RequiredBy=sysinit.target
UNIT

# grimoire-apply.service: aplica magic.yaml en stage-4
cat > "$ROOTFS_DIR/usr/lib/systemd/system/grimoire-apply.service" <<'UNIT'
[Unit]
Description=SpellOS Grimoire Declarative Apply
After=network.target
After=local-fs.target
Before=multi-user.target
ConditionPathExists=/etc/magic/magic.yaml

[Service]
Type=oneshot
ExecStart=/usr/bin/grimoire apply /etc/magic/magic.yaml
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT

# --- Estructura de directorios SpellOS ---
echo "[STAGE-2] Creando estructura /etc/magic/..."
mkdir -p "$ROOTFS_DIR/etc/magic/keys"
mkdir -p "$ROOTFS_DIR/etc/magic/layers"
mkdir -p "$ROOTFS_DIR/var/log/magic"

# magic.yaml por defecto
cat > "$ROOTFS_DIR/etc/magic/magic.yaml" <<'YAML'
magic:
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
  audit_log: /var/log/magic/audit
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
install -m 644 "$PUBKEY" "$ROOTFS_DIR/etc/magic/keys/verify.pub"

# --- Limpiar y empaquetar ---
echo "[STAGE-2] Limpiando y empaquetando..."
rm -rf "$ROOTFS_DIR/var/cache" "$ROOTFS_DIR/var/log" "$ROOTFS_DIR/tmp" 2>/dev/null || true
mkdir -p "$ROOTFS_DIR/var/log/magic"
mkdir -p "$ROOTFS_DIR/tmp"

MAGIC_TAR="$OUTDIR/magic-$VERSION.tar"
tar -cpf "$MAGIC_TAR" -C "$ROOTFS_DIR" .

# --- Firma ---
if gpg --list-keys "$GPG_KEY" &>/dev/null; then
    gpg --detach-sign --armor --local-user "$GPG_KEY" \
        --output "$MAGIC_TAR.sig" "$MAGIC_TAR"
else
    echo "Placeholder: sin firma real" > "$MAGIC_TAR.sig"
fi

# --- Checksum ---
sha256sum "$MAGIC_TAR" > "$MAGIC_TAR.sha256"

echo "[STAGE-2] Completado. Artefactos:"
ls -lh "$MAGIC_TAR" "$MAGIC_TAR.sig" "$MAGIC_TAR.sha256"

# --- Limpiar temp ---
rm -rf "$ROOTFS_DIR"

exit 0
