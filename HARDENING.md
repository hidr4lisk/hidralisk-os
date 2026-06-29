# Hardening — Hidralisk

**Autor:** ZeroCool (Red Team)
**Fecha:** 2026-06-27
**Objetivo:** Configuración de seguridad por defecto. Cada línea es una decisión de defensa.

---

## 1. Kernel Hardening

```bash
# /etc/sysctl.d/99-hidra-hardening.conf

# --- Protección de memoria ---
kernel.randomize_va_space=2                    # ASLR completo (stack, heap, mmap, VDSO)
fs.suid_dumpable=0                             # No core dumps de binarios setuid
kernel.core_pattern=|/bin/false                # Neutralizar core dumps
vm.mmap_min_addr=65536                         # No mapear página 0 (NULL pointer deref)
vm.mmap_rnd_bits=32                            # Randomización de mmap
vm.mmap_rnd_compat_bits=16                     # Randomización para compat 32-bit

# --- Protección de kernel ---
kernel.kptr_restrict=2                          # Ocultar punteros del kernel
kernel.dmesg_restrict=1                         # dmesg solo para root
kernel.perf_event_paranoid=3                    # Perf restringido
kernel.yama.ptrace_scope=2                      # Ptrace solo para parent directo
kernel.unprivileged_bpf_disabled=1              # BPF solo para root
net.core.bpf_jit_harden=2                       # JIT hardening para BPF
kernel.unprivileged_userns_clone=0              # Sin user namespaces para no-root

# --- Protección de red ---
net.ipv4.conf.all.rp_filter=1                  # Reverse path filtering
net.ipv4.conf.default.rp_filter=1
net.ipv4.conf.all.accept_redirects=0           # No ICMP redirects
net.ipv4.conf.default.accept_redirects=0
net.ipv6.conf.all.accept_redirects=0
net.ipv6.conf.default.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.all.accept_source_route=0        # Sin source routing
net.ipv4.icmp_echo_ignore_broadcasts=1          # Ignorar broadcast pings
net.ipv4.icmp_ignore_bogus_error_responses=1
net.ipv4.tcp_syncookies=1                       # SYN cookies
net.ipv4.conf.all.log_martians=1               # Log de paquetes sospechosos

# --- Protección de filesystem ---
fs.protected_symlinks=1                         # Protección contra symlink race
fs.protected_hardlinks=1                        # Protección contra hardlink race
fs.protected_fifos=2
fs.protected_regular=2

# --- Deshabilitar módulos peligrosos ---
# Estos se cargan via blacklist en /etc/modprobe.d/
```

### Blacklist de módulos del kernel

```bash
# /etc/modprobe.d/hidra-blacklist.conf

# Módulos de debugging/acceso directo — NUNCA en producción
blacklist cramfs
blacklist freevxfs
blacklist hfs
blacklist hfsplus
blacklist udf
blacklist dccp
blacklist sctp
blacklist rds
blacklist tipc
blacklist usb-storage                         # Deshabilitar por defecto, habilitar bajo demanda
blacklist firewire-core
blacklist firewire-ohci
blacklist firewire-sbp2
blacklist nd_btt                              # NVDIMM testing
blacklist nbd                                 # Network block device
blacklist vsock                               # VM socket transport
```

---

## 2. AppArmor — Profiles estrictos

### Profile para `hidra-init`

```bash
# /etc/apparmor.d/usr.sbin.hidra-init

#include <tunables/global>

/usr/sbin/hidra-init {
  #include <abstractions/base>

  # Lectura de archivos del sistema — solo paths específicos
  /boot/.hidra/registry.asc       r,
  /etc/hidra/keys/*.pub            r,
  /etc/hidra/hidra.yaml           r,
  /var/log/hidra/audit.log        w,

  # Escritura SOLO al audit log
  /var/log/hidra/audit.log        w,

  # No acceso a /etc, /var/lib, o cualquier otra cosa
  deny /etc/**                    w,
  deny /var/lib/**                w,
  deny /home/**                   rw,
  deny /tmp/**                    rw,

  # No elevación de privilegios
  deny capability sys_admin,
  deny capability sys_rawio,
  deny capability sys_module,
}
```

### Profile para `hidra-apt`

```bash
# /etc/apparmor.d/usr.bin.hidra-apt

#include <tunables/global>

/usr/bin/hidra-apt {
  #include <abstractions/base>
  #include <abstractions/apt>

  # Acceso a apt — solo para descarga
  /usr/bin/apt                   mr,
  /usr/bin/apt-get               mr,
  /var/cache/apt/**              rw,

  # Creación de capas ostree — sandboxed
  /usr/bin/ostree                mr,
  /var/lib/ostree/**             rw,

  # Claves de firma — SOLO lectura
  /etc/hidra/keys/verify.pub     r,
  deny /etc/hidra/keys/*.pub     w,

  # Registro — append-only
  /var/log/hidra/audit.log       w,
  /var/log/hidra/transactions.log w,

  # Snapshot Btrfs
  /usr/sbin/btrfs                mr,
  /dev/btrfs-control             rw,

  # Denegar acceso peligroso
  deny /boot/**                  rw,
  deny /etc/systemd/**           w,
  deny /etc/cron*/**             w,
  deny /root/**                  rw,
}
```

### Profile para `overmind`

```bash
# /etc/apparmor.d/usr.bin.overmind

#include <tunables/global>

/usr/bin/overmind {
  #include <abstractions/base>

  # Lectura de hidra.yaml — ÚNICO archivo de configuración
  /etc/hidra/hidra.yaml          r,
  /etc/hidra/hidra.yaml.d/**     r,

  # Escritura a /etc SOLO vía overlay (nunca directo)
  /run/overlay/**                rw,

  # Ejecución de servicios declarados — controlada
  /usr/bin/systemctl             Px -> /usr/bin/systemctl,

  # Log
  /var/log/hidra/audit.log       w,

  # Denegar escritura directa a /etc
  deny /etc/**                   w,
  deny /var/lib/**               rw,
  deny /home/**                  rw,

  # No elevation
  deny capability sys_admin,
}
```

---

## 3. dm-verity en raíz

dm-egrity proporciona verificación de integridad a nivel de bloque. Cada bloque leído se verifica contra un hash tree almacenado.

### Implementación

```bash
# Configuración de dm-verity para la capa base
# Se aplica en stage-1 de hidra-init, ANTES de montar el rootfs

# 1. Generar hash tree durante el build
veritysetup format /dev/mapper/hidra-base /dev/mapper/hidra-base-hash

# 2. Montar con verificación
mount -o ro,verity /dev/dm-0 /mnt/root

# 3. Configurar en /etc/fstab para boot futuro
# /dev/mapper/hidra-base    /    ext4    ro,verity    0 1
```

### Integración con hidra-init

```bash
# En stage-1 de hidra-init:
# 1. Verificar hash tree del rootfs
# 2. Si falla → NO montar rootfs, ir a recovery
# 3. Si pasa → montar con dm-verity habilitado
# 4. Cada lectura de bloque se verifica en runtime
```

---

## 4. Firma de Capas con Sigstore

Sigstore permite firma sin gestionar claves locales. usa identidades OIDC (GitHub, Google, etc.) para firmar.

### Setup

```bash
# Durante el build:
# 1. Generar clave de firma efímera
cosign generate-key-pair

# 2. Firmar cada capa ostree
cosign sign-blob \
  --key cosign.key \
  --output-signature layer-v1.0.sig \
  --output-certificate layer-v1.0.cert \
  layer-v1.0.tar

# 3. Verificar durante boot
cosign verify-blob \
  --key cosign.pub \
  --signature layer-v1.0.sig \
  --certificate layer-v1.0.cert \
  layer-v1.0.tar

# 4. Publicar en rekor (transparency log)
cosign upload blob \
  --rekor-url https://rekor.sigstore.dev \
  layer-v1.0.tar
```

### Ventaja sobre GPG

- Sin gestión de keyring local
- Transparency log: cada firma es pública y auditable
- Revocación vía OIDC identity, no vía keyserver
- Integración nativa con GitHub Actions

---

## 5. Aislamiento de Sesiones con Bubblewrap

### Configuración del sandbox

```bash
# Ejemplo de invocación de bwrap para sesión de usuario
bwrap \
  --ro-bind /usr /usr \
  --ro-bind /lib /lib \
  --ro-bind /lib64 /lib64 \
  --ro-bind /bin /bin \
  --ro-bind /sbin /sbin \
  --proc /proc \
  --dev /dev \
  --tmpfs /tmp \
  --tmpfs /run \
  --bind /run/overlay/session /run/overlay/session \
  --die-with-parent \
  --unshare-all \
  --new-session \
  --hostname sandbox-$(id -u) \
  --args-file /etc/hidra/bwrap-args.conf \
  /bin/bash
```

### Restricciones del sandbox

```bash
# /etc/hidra/bwrap-args.conf

# No acceso a /dev excepto dispositivos específicos
--dev /dev/null
--dev /dev/urandom
--dev /dev/random

# No acceso a /sys
--ro-bind /sys/fs /sys/fs

# No acceso a /boot
--bind /dev/null /boot

# No acceso a /etc/hidra (configuración del sistema)
--bind /dev/null /etc/hidra

# No acceso a /var/log (logs del sistema)
--bind /dev/null /var/log

# No montaje de filesystems
--unshare-pid
--unshare-ipc
--unshare-net
--unshare-user
```

### Protecciones contra escape

```bash
# Sysctl para restringir user namespaces (requiere que bwrap NO necesite ellos)
# Si bubblewrap usa user namespaces, estos están restringidos a root
kernel.unprivileged_userns_clone=0

# Seccomp-bpf para filtrar llamadas al sistema
# En el sandbox: solo syscalls necesarios para aplicaciones de usuario
# Bloquear: mount, umount2, pivot_root, chroot, ptrace, keyctl, etc.
```

---

## 6. Protección del Audit Log

```bash
# /etc/apparmor.d/var.log.hidra.audit.log

#include <tunables/global>

/var/log/hidra/audit.log {
  # Solo append — nunca truncar ni sobreescribir
  append-only,

  # Solo hidra-init y hidra-apt pueden escribir
  owner /usr/sbin/hidra-init w,
  owner /usr/bin/hidra-apt w,
  owner /usr/bin/overmind w,

  # Nadie más puede leer o modificar
  deny user r,
  deny user w,
  deny user x,
}
```

### Complemento: Log shipping

```bash
# /etc/hidra/log-shipper.conf
# Envía cada entrada de audit log a un SIEM remoto en tiempo real

[audit-shipper]
type = file
path = /var/log/hidra/audit.log
format = json
endpoint = https://siem.example.com/ingest
auth_token = ${HIDRA_SSIEM_TOKEN}
batch_size = 1
flush_interval = 1s
```

---

## 7. Secure Boot Enforcement

```bash
# /etc/grub.d/40_secure_boot_check

# Verificar que Secure Boot está activo antes de permitir boot
if ! mokutil --sb-state | grep -q "SecureBoot enabled"; then
  echo "⚠️  HIDRALISK: SecureBoot DESHABILITADO"
  echo "   Hidralisk requiere Secure Boot para operar correctamente."
  echo "   El sistema arrancará en modo DEGRADED (sin verificación de integridad)."
  echo ""
  echo "   Para habilitar Secure Boot:"
  echo "   1. Reiniciar a UEFI/BIOS"
  echo "   2. Habilitar Secure Boot"
  echo "   3. Si es necesario, usar mokutil para inscribir claves"
  echo ""
  read -p "   Presioná Enter para continuar en modo degradado..."
fi
```

---

## 8. Hardening de Red (por defecto)

```bash
# /etc/nftables.conf

#!/usr/sbin/nft -f

flush ruleset

table inet hidra-filter {
  chain input {
    type filter hook input priority 0; policy drop;

    # Permitir loopback
    iif "lo" accept

    # Permitir conexiones establecidas y related
    ct state established,related accept

    # Permitir SSH (si habilitado)
    tcp dport 22 ct state new limit rate 3/minute accept

    # Permitir HTTP/HTTPS para actualizaciones
    tcp dport { 80, 443 } ct state new accept

    # Permitir DNS
    udp dport 53 accept
    tcp dport 53 accept

    # Log y drop el resto
    log prefix "[HIDRA-DROP] " drop
  }

  chain forward {
    type filter hook forward priority 0; policy drop;
  }

  chain output {
    type filter hook output priority 0; policy accept;
  }
}
```

---

## 9. Firewall por Defecto: DENY ALL

```bash
# Política por defecto: DENEGAR todo inbound
# Solo puertos explícitamente permitidos:
# - 22/tcp (SSH) — rate limited
# - 80/tcp (HTTP) — para actualizaciones
# - 443/tcp (HTTPS) — para actualizaciones
# - 53/udp, 53/tcp (DNS)

# Política de output: ACCEPT (pero auditada)
# El audit log registra cada conexión saliente
```

---

## 10. Checklist de Seguridad por Defecto

| Componente | Estado por defecto | Justificación |
|-----------|-------------------|---------------|
| dm-verity | HABILITADO | Integridad a nivel de bloque |
| AppArmor | ENFORCE | Mandatory access control |
| Secure Boot | REQUERIDO | Cadena de confianza desde UEFI |
| Firewall | DENY ALL INBOUND | Zero trust network |
| User namespaces | DESHABILITADO | Reduce superficie de kernel |
| Core dumps | DESHABILITADO | No filtración de memoria |
| Audit log | APPEND-ONLY | Evidencia forense |
| Snapshots | LÍMITE 10 | Prevención de DoS |
| Rollback deprecated | REQUIERE --force | No reversión accidental de parches |
| hidra.yaml | FIRMA REQUERIDA | No manipulación de configuración |
| Registro de capas | TPM-bound | No reemplazo sin hardware token |
| Build pipeline | REPRODUCIBLE | Verificabilidad independiente |

---

## 11. Parámetros de Kernel para Producción

```bash
# /etc/default/grub (agregar a GRUB_CMDLINE_LINUX)

GRUB_CMDLINE_LINUX="\
  init_on_alloc=1 \
  init_on_free=1 \
  slab_nomerge \
  slab_debug=FZP \
  page_alloc.shuffle=1 \
  randomize_kstack_offset=on \
  vsyscall=none \
  lockdown=confidentiality \
  module.sig_enforce=1 \
  oops=panic \
  panic_on_warn=1 \
"
```

| Parámetro | Efecto |
|-----------|--------|
| `init_on_alloc=1` | Cero-initializa memoria al allocar (previene info leaks) |
| `init_on_free=1` | Cero-initializa memoria al liberar |
| `slab_nomerge` | Previene merge de slab objects (mitiga heap spraying) |
| `page_alloc.shuffle=1` | Randomiza page allocator |
| `randomize_kstack_offset=on` | Randomiza kernel stack offset por syscall |
| `vsyscall=none` | Deshabilita vsyscall (ataques ROP) |
| `lockdown=confidentiality` | Restringe acceso a /dev/mem, kexec, etc. |
| `module.sig_enforce=1` | Solo carga módulos firmados |
| `oops=panic` | Kernel panic ante oops (previene estado corrupto) |
| `panic_on_warn=1` | Kernel panic ante warnings (failsafe) |

---

## 12. Resumen de Postura

Hidralisk por defecto debe ser:

1. **DENY-BY-DEFAULT** en red, filesystem, y capabilities
2. **VERIFIED** en boot, capas, y configuración (dm-verity + firma + TPM)
3. **AUDITED** en cada operación (append-only log + SIEM shipping)
4. **IMMUTABLE** en sistema base (readonly + overlay protection)
5. **RECOVERABLE** pero no abusable (rollback con protecciones)
6. **SANDBOXED** en sesiones de usuario (bubblewrap + seccomp + AppArmor)

La seguridad NO es un feature. Es la arquitectura.
