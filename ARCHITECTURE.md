# Arquitectura de MagicLinux

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

## Grimoire — Lenguaje declarativo YAML-based

`grimoire` es el orquestador declarativo nativo de MagicLinux. Su entrada es `magic.yaml` en la raíz del repositorio de configuración:

```yaml
magic:
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
  audit_log: /var/log/magic/audit
```

Grimoire transforma estas declaraciones en capas ostree compuestas, resolviendo dependencias entre paquetes aisladas por overlay. Soporta herencia, composición y plantillas.

## Init personalizado

Systemd opera con un stage previo de verificación:

1. **stage-0 (bootloader)**: GRUB verifica firma del kernel e initramfs
2. **stage-1 (integrity)**: `magic-init` verifica hashes de la capa base contra el registro firmado en `/boot/.magic/registry.asc`. Si hay discrepancia → boot niega, consola de recovery
3. **stage-2 (systemd)**: systemd arranca normal sobre el rootfs validado
4. **stage-3 (grimoire apply)**: si hay cambios pendientes en magic.yaml, se aplican antes de que los servicios de red levanten

## magic-apt — Gestor de paquetes atómico

`magic-apt` envuelve `apt` en transacciones de capas:

```
$ magic-apt install nginx
  → apt download nginx
  → crear capa ostree con los nuevos binarios
  → firmar capa con clave del repositorio local
  → Btrfs snapshot del estado actual
  → aplicar capa como nuevo deploy
  → si falla → rollback automático al snapshot
```

El historial de operaciones es un árbol de commits ostree. Se puede navegar con `magic-rollback --list` y revertir con `magic-rollback --to <commit>`.

### Estructura de repositorio local

```
/etc/magic/
├── magic.yaml          → configuración declarativa
├── layers/             → capas ostree locales
├── keys/               → claves de firma
└── registry.asc        → registro firmado de capas

/var/log/magic/
├── audit.log           → toda operación queda auditada
└── transactions.log    → historial de magic-apt
```
