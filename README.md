# MagicLinux

**MagicLinux** no es una distro más. Es la primera distribución Linux que resuelve la tensión histórica entre inmutabilidad y flexibilidad, entre declaratividad y compatibilidad, entre seguridad y usabilidad.

## Diferenciación clave

### Sistema inmutable por capas
Inspirado en Fedora Silverblue y NixOS, MagicLinux lleva la inmutabilidad al siguiente nivel con un modelo de **capas atómicas apilables**. Cada capa (base, sistema, usuario, sesión) es un artefacto firmado e inmutable. El usuario nunca modifica el sistema en caliente: declara el estado deseado y el orquestador lo materializa atómicamente.

### Compatibilidad total con `.deb`
A diferencia de Silverblue (aislado de RPM) o NixOS (ecosistema cerrado), MagicLinux ejecuta cualquier paquete `.deb` sin fricción. El gestor `magic-apt` envuelve apt dentro del modelo de capas: cada instalación crea una nueva capa overlay sobre la base, no un parche sobre el sistema vivo. Rollback nativo con Btrfs snapshots.

### Grimoire — Orquestador declarativo nativo
`grimoire` es el corazón de MagicLinux. Un lenguaje declarativo YAML-based donde definís el estado completo del sistema: paquetes, servicios, usuarios, monturas, kernels, firmas. Un solo archivo `magic.yaml` versionable en git describe una máquina entera. `grimoire apply` materializa, verifica y firma cada capa.

## Security by Architecture

MagicLinux no agrega seguridad como capa adicional — la seguridad es la arquitectura.

| Principio | Implementación |
|-----------|---------------|
| **Integridad de bloque** | dm-verity verifica cada bloque del rootfs en lectura. No alcanza con modificar archivos — el hash tree detecta manipulación a nivel de disco. |
| **TPM binding** | El registro de capas `registry.asc` no es un archivo reemplazable: está vinculado a PCR measurements del TPM. Sin el hardware correcto, no hay boot. |
| **Firma de configuración** | `magic.yaml` debe estar firmado con la clave del administrador. Grimoire rechaza archivos no firmados. Campos críticos (verify_boot, enforce_signing) son inmutables para el usuario. |
| **Audit log inmutable** | Cada operación del sistema queda registrada en `/var/log/magic/audit.log` con protección append-only vía `chattr +a`. El log sobrevive rollbacks y reinicios. |
| **Overlay verification** | Después de montar overlays, `magic-init` verifica hashes de binarios críticos contra el registro. Si un overlay enmascara binarios del sistema, el boot se niega. |
| **Rollback seguro** | Protegido con rate limiting, marca de deprecated, y pre-snapshot del estado de seguridad antes de revertir. |
| **Build pipeline aislado** | Self-hosted runners + HSM para firma + reproducible build attestation (SLSA Level 3). |

## ¿Por qué esto es revolucionario?

1. **Fin del "dependency hell"**: cada capa es un entorno hermético. No hay conflicto entre librerías de distintas aplicaciones porque conviven en overlays separados.
2. **Rollback instantáneo y seguro**: si una actualización rompe algo, `magic-rollback` te devuelve al estado anterior en segundos. No hay "broken system after apt upgrade".
3. **Seguridad por arquitectura**: el sistema base es de solo lectura. Un compromiso de `root` no puede modificar binarios del sistema porque la capa base está firmada y montada readonly. Los overlays de sesión se descartan al reiniciar.
4. **Reproducibilidad**: `magic.yaml` + un tag de repositorio = la misma máquina siempre. Adiós al "works on my machine".
5. **Puente entre mundos**: no tenés que elegir entre la inmutabilidad de Nix y el ecosistema Debian. MagicLinux te da ambos.
