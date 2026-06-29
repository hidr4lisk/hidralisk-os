# Arquitectura de Hidralisk

## Filesystem inmutable: ostree + overlayfs

```
/boot          → vfat, firmware firmado
/              → subvolumen Btrfs readonly (base layer)
/run/current   → symlink a la capa activa (atomically switched)
/run/overlay   → tmpfs para overlays efímeros de sesión
/etc           → subvolumen Btrfs con estado persistente mínimo
/var           → subvolumen Btrfs para datos de aplicaciones
```

El modelo de capas se organiza en cuatro niveles:

| Capa | Contenido | Inmutabilidad | Persistencia |
|------|-----------|---------------|--------------|
| **Base** | Kernel, glibc, systemd, drivers | Readonly, firmado | Permanente |
| **System** | Paquetes del sistema (apt) | Readonly, firmado | Hasta rollback |
| **User** | Aplicaciones de usuario | Readonly | Hasta rollback |
| **Session** | /run/overlay efímero | Descartable | Solo duración sesión |

`ostree` maneja el versionado atómico del rootfs. Cada deploy es un commit firmado con GPG. Btrfs subvolumes proveen snapshots eficientes para rollback sin duplicación.

## Overmind — Lenguaje declarativo YAML-based

`overmind` es el orquestador declarativo nativo de Hidralisk. Su entrada es `hidra.yaml` en la raíz del repositorio de configuración:

```yaml
hidra:
  version: "1.0"
  kernel: "6.8"
  base: "debian:bookworm"

layers:
  system:
    packages:
      - nginx
      - postgresql-16
    services:
      nginx: enabled
      postgresql: enabled

  user:
    packages:
      - neovim
      - gh
    dotfiles:
      source: "https://github.com/user/dotfiles"
      target: /home/user

  session:
    packages:
      - firefox
      - slack
    ephemeral: true

integrity:
  verify_boot: true
  enforce_signing: true
  audit_log: /var/log/hidra/audit
```

Overmind transforma estas declaraciones en capas ostree compuestas, resolviendo dependencias entre paquetes aisladas por overlay. Soporta herencia, composición y plantillas.

### Seguridad de Overmind

- **Validación de esquema**: `hidra.yaml` se valida contra un JSON Schema estricto en cada `apply`. Campos críticos (`integrity.verify_boot`, `integrity.enforce_signing`) son inmutables — el usuario no puede desactivarlos.
- **Firma obligatoria**: `hidra.yaml` debe estar firmado con la clave del administrador. Overmind rechaza archivos no firmados o con firma inválida.
- **Allowlist de campos**: el usuario declara paquetes y servicios, pero no puede modificar integrity, audit, ni signing settings.
- **Denylist de campos ejecutables**: no se permite `exec`, `script`, `command` inline en la declaración. Todo código corre como capa ostree firmada.
- **Subresource Integrity para fuentes remotas**: `dotfiles.source`, `repo.url` requieren hash SHA-256 verificado al descargar.

## Áreas writables: `/etc` y `/var`

`/etc` y `/var` son subvolúmenes Btrfs persistentes que sobreviven rollback de capas. Esto es necesario para configuraciones de red, usuarios, y datos de aplicaciones, pero es el principal vector de persistencia post-compromiso.

### Mecanismos de defensa

- **Overmind como source of truth**: solo lo declarado en `hidra.yaml` puede modificar archivos de configuración en `/etc` vía capas ostree. Cualquier cambio directo (no vía Overmind) se detecta en stage-2 y se revierte automáticamente al próximo boot.
- **Verificación de integridad en boot**: stage-2 verifica hashes de archivos protegidos (`/etc/systemd/system/*`, `/etc/cron.*`, `/etc/hidra/hidra.yaml`, `/etc/shadow`) contra un manifest firmado. Si hay discrepancia → alerta en audit log + reintento de remediación vía Overmind.
- **AppArmor mandatory**: los procesos del sistema (hidra-init, hidra-apt, overmind) tienen perfiles AppArmor estrictos que deniegan escritura directa a `/etc` y `/var/lib` excepto paths explícitos.
- **Audit log inmutable**: `/var/log/hidra/audit.log` con `chattr +a` (append-only). El log shipping a SIEM externo es en tiempo real.

## Init personalizado

Systemd opera con un stage previo de verificación:

1. **stage-0 (bootloader)**: GRUB verifica firma del kernel e initramfs. Secure Boot MANDATORIO — si está deshabilitado, boot en modo degraded con advertencia visible.
2. **stage-1 (integrity)**: `hidra-init` enciende dm-verity sobre el dispositivo raíz (verificación a nivel de bloque, no de archivo). Luego verifica hashes de la capa base contra el registro firmado en `/boot/.hidra/registry.asc`. El `registry.asc` está vinculado a TPM PCR measurements: si el atacante reemplaza el archivo, los PCRs no matchean y el boot se niega. Si hay discrepancia → boot denegado, consola de recovery protegida (partición read-only firmada). El recovery requiere challenge-response con clave de recuperación almacenada fuera del disco.
3. **stage-2 (POST-mount verification)**: Antes de entregar el control, `hidra-init`:
   - Verifica hashes de binarios críticos (systemd, sudo, login, kernel modules) en la capa montada contra `registry.asc`. Si un overlay enmascara binarios, la verificación falla y se rechaza el boot.
   - Verifica hashes de archivos protegidos en `/etc` y `/var` contra un manifest firmado. Cambios no declarados en `hidra.yaml` se detectan y revierten automáticamente vía Overmind.
   - Solo se montan capas cuyo hash esté en el registro (allowlist).
4. **stage-3 (systemd)**: systemd arranca normal sobre el rootfs validado.
5. **stage-4 (overmind apply)**: si hay cambios pendientes en hidra.yaml, se validan contra JSON Schema estricto, se verifica la firma del archivo, y se aplican en una transacción atómica antes de que los servicios de red levanten. Si falla a mitad → rollback automático al estado anterior.

## hidra-apt — Gestor de paquetes atómico

`hidra-apt` envuelve `apt` en transacciones de capas:

```
$ hidra-apt install nginx
  → apt download nginx
  → crear capa ostree con los nuevos binarios
  → firmar capa con clave del repositorio local
  → Btrfs snapshot del estado actual
  → aplicar capa como nuevo deploy
  → si falla → rollback automático al snapshot
```

El historial de operaciones es un árbol de commits ostree. Se puede navegar con `hidra-rollback --list` y revertir con `hidra-rollback --to <commit>`.

### Protecciones de rollback

- **Versiones deprecated**: commits de versiones sin soporte de seguridad se marcan como "deprecated". Rollback a deprecated requiere flag explícito `--force-deprecated` + warning al usuario.
- **Rate limiting**: máximo 3 rollbacks por hora. Previene abuso para análisis diferencial de capas.
- **Pre-rollback snapshot**: antes de ejecutar rollback, se toma un snapshot del estado actual y del manifest de seguridad. Si el rollback revierte un CVE conocido → alerta obligatoria en audit log.
- **Rollback no revierte audit log**: el log de operaciones es append-only y sobrevive rollbacks.

### Estructura de repositorio local

```
/etc/hidra/
├── hidra.yaml          → configuración declarativa
├── layers/             → capas ostree locales
├── keys/               → claves de firma (SOLO clave pública en disco; privada en HSM externo)
└── registry.asc        → registro firmado de capas (vinculado a TPM PCR)

/var/log/hidra/
├── audit.log           → toda operación queda auditada
└── transactions.log    → historial de hidra-apt
```
