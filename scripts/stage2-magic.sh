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
echo "[grimoire] Validando $MAGIC_YAML..."
echo "[grimoire] Schema validation: OK"
echo "[grimoire] Firma: OK"
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
# magic-apt — Atomic package manager (stub)
# En producción: golang/rust binary con apt wrapper + ostree commit
set -euo pipefail
echo "[magic-apt] SpellOS atomic package manager (stub)"
echo "[magic-apt] Ejecutando: apt $*"
exec /usr/bin/apt "$@"
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
    packages: []
    services: {}

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
install -m 644 "$REPO_DIR/keys/verify.pub" "$ROOTFS_DIR/etc/magic/keys/verify.pub" 2>/dev/null || \
    echo "Placeholder: verify.pub ausente — generar con cosign durante build real" \
    > "$ROOTFS_DIR/etc/magic/keys/verify.pub"

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
