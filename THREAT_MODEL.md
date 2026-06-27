# Threat Model — MagicLinux

**Autor:** ZeroCool (Red Team)
**Fecha:** 2026-06-27
**Objetivo:** Romper la arquitectura de Rick. Encontrar los ángulos ciegos.

---

## Metodología

Analizo la arquitectura desde el modelo STRIDE + vectores específicos de sistemas inmutables con overlays. Cada vector incluye: descripción, impacto, feasibility, y mitigación propuesta.

---

## V-01: Bootkit — Compromiso de `registry.asc` en `/boot`

**Descripción:** El stage-1 de `magic-init` verifica integridad de la capa base contra `/boot/.magic/registry.asc`. Si un atacante con acceso físico (o remoto vía otro vector) reemplaza este archivo, puede:
- Inyectar hashes que coincidan con una capa maliciosa
- Desactivar la verificación completa del sistema

**Impacto:** CRÍTICO. El rootfs completo queda bajo control del atacante. El modelo de inmutabilidad se vuelve irrelevante.

**Feasibility:** MEDIA (requiere acceso físico o compromiso previo de /boot que es vfat sin protección)

**Mitigación propuesta:**
- `registry.asc` NO debe vivir en disco sin protección. Opciones:
  - **TPM 2.0 binding:** Llave de verificación encadenada al TPM. El registro se valida contra measurements del PCR. Si el atacante modifica el archivo, el PCR no matchea.
  - **YubiKey challenge-response:** La verificación stage-1 requiere un challenge-response con hardware token.
  - **Lectura desde red (fail-safe):** Si el registro local no es verificable, intentar fetch de un registry remoto firmado. Si tampoco → consola de recovery, NO boot.
- **dm-verity** en la partición `/boot` para detectar modificaciones a nivel de bloque (no solo de archivo).

---

## V-02: Evil Maid — Compromiso del chain de Secure Boot

**Descripción:** El stage-0 depende de GRUB verificando firma del kernel e initramfs. Si el atacante puede:
- Reemplazar GRUB por uno firmado con su propia clave (si Secure Boot está en setup mode)
- Modificar la UEFI para deshabilitar Secure Boot
- Inyectar un shim malicioso

**Impacto:** CRÍTICO. Se salta toda la cadena de verificación.

**Feasibility:** BAJA-MEDIA (requiere acceso físico + conocimiento de UEFI, pero herramientas como `mokutil` lo facilitan)

**Mitigación propuesta:**
- Secure Boot MANDATORIO en producción. La ISO debe rechazar instalar si Secure Boot está deshabilitado.
- `sbctl` o `sbupdate` para mantener las firmas UEFI bajo control de MagicLinux, no del usuario.
- Alerta en stage-1 si Secure Boot no está activo (log + notificación al usuario).

---

## V-03: Supply Chain — `magic-apt` envuelve apt puro

**Descripción:** `magic-apt` es un wrapper sobre apt. Esto significa:
- TODOS los CVEs de apt aplican (dependencias, resolución de paquetes, repositorios)
- La capa ostree que genera agrega superficie de ataque: si el proceso de creación de capa tiene un bug (path traversal, symlink following), se puede inyectar contenido malicioso en la capa
- El repositorio local `/etc/magic/keys/` contiene la clave de firma. Si se compromete, todas las capas "firmadas" son trampa.

**Impacto:** ALTO. Compromiso de supply chain = cada actualización futura puede ser maliciosa.

**Feasibility:** MEDIA (requiere compromiso del keyring o del mirror Debian)

**Mitigación propuesta:**
- **Clave de firma offline:** La clave de firma de capas NUNCA debe estar en el disco del usuario. Generarla en build time, almacenarla en HSM o YubiKey.
- **Reproducible builds:** Cada capa ostree debe ser verificable independentemente. Publicar diffs de build para auditoría.
- **Pinning de repositorios:** `magic-apt` debe validar hash SHA256 de cada paquete descargado contra un manifest firmado. No confiar solo en GPG del mirror.
- **Isolación del proceso de creación de capas:** Ejecutar `apt download` en un sandbox (bubblewrap o namespaces) con mínimo privilegio. El proceso de creación de capa NUNCA debe correr como root sobre el filesystem real.

---

## V-04: Toxicidad de Overlays — Enmascaramiento de binarios críticos

**Descripción:** overlayfs permite que una capa superior enmascare archivos de una capa inferior. Un atacante que logre escribir en la capa de sesión (o en una capa persistent si `/etc` o `/var` están comprometidos) puede:
- Reemplazar `/usr/bin/sudo` por un binario malicioso
- Enmascarear `/etc/passwd` o `/etc/shadow`
- Sobreescribir bibliotecas compartidas críticas

**Impacto:** ALTO. El sistema parece intacto (ostree reporta la capa base como válida) pero los binarios ejecutados son trampa.

**Feasibility:** MEDIA (requiere write a una capa que se monte sobre el sistema)

**Mitigación propuesta:**
- **Verificación de integridad POST-mount:** Después de montar overlays, `magic-init` debe verificar hashes de binarios críticos (systemd, login, kernel) contra el registro. Si hay discrepancia → rechazar boot.
- **Allowlist de capas:** Solo las capas cuyo hash esté en `registry.asc` se permiten montar. Sin allowlist → no hay overlay.
- **dm-verity** en la capa base: incluso si un overlay enmascara un archivo, dm-verity detecta la modificación a nivel de bloque del subvolumen Btrfs subyacente.

---

## V-05: Persistencia en Áreas Writables (`/var`, `/etc`)

**Descripción:** La arquitectura define `/var` y `/etc` como subvolúmenes Btrfs persistentes. Un atacante con root puede:
- Inyectar servicios systemd en `/etc/systemd/system/`
- Modificar crontabs en `/etc/cron.*`
- Plantar scripts en `/var/lib/` que se ejecuten en cada boot
- Alterar `/etc/magic/magic.yaml` para que Grimoire aplique capas maliciosas

**Impacto:** ALTO. Persistencia que sobrevive reinicios y rollback de capas del sistema.

**Feasibility:** ALTA (cualquier root compromise tiene acceso directo)

**Mitigación propuesta:**
- **Verificación de `/etc` y `/var` en boot:** Antes de que systemd arranque, verificar hashes de archivos críticos en estas áreas contra un manifest firmado.
- **Grimoire como single source of truth:** Si `magic.yaml` es la definición del sistema, CUALQUIER cambio en `/etc` que no venga de Grimoire debe ser detectado y revertido.
- **AppArmor/SELinux estricto:** Restringir qué procesos pueden modificar archivos en `/etc/systemd/`, `/etc/cron.*`, y `/var/lib/`.
- **Audit log inmutable:** `/var/log/magic/audit.log` debe ser write-only append. Si es atacable, el atacante borra evidencia.

---

## V-06: Weaponización de Rollback

**Descripción:** `magic-rollback` permite volver a un commit ostree anterior. Un atacante puede:
- Revertir parches de seguridad aplicados en la última actualización
- Forzar rollback a una versión con CVEs conocidos
- Hacer rollback de cambios de configuración de seguridad

**Impacto:** MEDIO-ALTO. El mecanismo de recuperación se convierte en vector de ataque.

**Feasibility:** BAJA (requiere root + conocer el historial de commits)

**Mitigación propuesta:**
- **Rollback solo a versiones con soporte:** `magic-rollback --list` debe marcar versiones sin soporte de seguridad como "deprecated". Rollback a deprecated requiere flag explícito `--force-deprecated` + warning.
- **Snapshot del manifest de seguridad antes de rollback:** Guardar el estado de parches conocidos. Si el rollback revierte un CVE crítico → alerta obligatoria.
- **Rate limiting:** No permitir más de N rollbacks en un período (evitar abuso para análisis de diferencias).

---

## V-07: YAML Injection en Grimoire

**Descripción:** `magic.yaml` es el corazón declarativo. Un atacante que comprometa el repositorio del usuario puede:
- Inyectar paquetes maliciosos en la sección `packages`
- Modificar `dotfiles.source` para apuntar a un repo malicioso
- Alterar `integrity.verify_boot: false` para desactivar verificación
- Inyectar servicios systemd que ejecuten código arbitrario

**Impacto:** CRÍTICO. La declaración se convierte en vector de ejecución remota.

**Feasibility:** MEDIA (requiere compromiso del repo git del usuario o MITM en dotfiles)

**Mitigación propuesta:**
- **Validación de esquema:** `grimoire apply` debe validar contra un JSON Schema estricto. Campos como `integrity.verify_boot` no deben ser modificables por el usuario.
- **Allowlist de campos modificables:** El usuario puede declarar paquetes y servicios, pero NO puede desactivar verificación de integridad, firmado, o audit log.
- **Firma de `magic.yaml`:** El archivo debe ser firmado con la clave del administrador. `grimoire apply` rechaza archivos no firmados o con firma inválida.
- **Subresource Integrity (SRI) para dotfiles:** Si `dotfiles.source` es remoto, verificar hash del contenido descargado.

---

## V-08: Escape de Bubblewrap (Aislamiento de Sesiones)

**Descripción:** La capa de sesión usa bubblewrap para aislamiento. Ataques conocidos:
- **Namespace escape vía kernel:** CVEs de Linux que permiten escape de user namespaces
- **/proc poisoning:** Montar un `/proc` malicioso para engañar al sandbox
- **Device access:** Si el sandbox tiene acceso a `/dev/`, puede interactuar con hardware

**Impacto:** MEDIO. El aislamiento de sesión es la última línea de defensa. Si falla, el atacante alcanza la capa del sistema.

**Feasibility:** BAJA (requiere kernel vulnerable)

**Mitigación propuesta:**
- **Kernel actualizado:** Mantener kernel LTS con parches de seguridad.
- **No mount de /dev/ en session sandbox:** Solo dispositivos específicos necesarios.
- **Seccomp-bpf:** Filtrar llamadas al sistema peligrosas dentro del sandbox.
- **User namespace restrictions:** Deshabilitar `unprivileged_userns_clone` si es posible, o usar AppArmor para restringir qué namespaces puede crear el proceso.

---

## V-09: DoS por Exhaustión de Snapshots Btrfs

**Descripción:** Cada operación de `magic-apt` crea un Btrfs snapshot. Un atacante puede:
- Llenar el disco con snapshots acumulados
- Provocar que el sistema falle al intentar crear un nuevo snapshot
- Degradar performance con demasiados subvolúmenes

**Impacto:** MEDIO. Disponibilidad comprometida.

**Feasibility:** ALTA (cualquier usuario con acceso a `magic-apt` puede hacerlo accidentalmente)

**Mitigación propuesta:**
- **Límite configurable de snapshots:** `magic-apt` debe tener un máximo de snapshots (ej: 10). Al exceder, eliminar el más antiguo automáticamente.
- **Alertas de uso de disco:** Si los snapshots ocupan >20% del disco → warning al usuario.
- **Snapshot cleanup automático:** `magic-apt cleanup` que elimine snapshots deprecated.

---

## V-10: Compromiso del Build Pipeline (CI/CD)

**Descripción:** El pipeline de GitHub Actions puede ser comprometido:
- **Poisoned runner:** El runner de GitHub ejecuta código arbitrario en la ISO final
- **Secrets exfiltration:** La clave de firma (`keys/sign.key`) se expone en variables de entorno
- **Dependency confusion:** Paquetes maliciosos en dependencias de build

**Impacto:** CRÍTICO. La ISO oficial contiene malware. Todos los usuarios se comprometen.

**Feasibility:** BAJA (requiere compromiso de GitHub o del repo)

**Mitigación propuesta:**
- **Self-hosted runners:** Nunca usar runners de GitHub para builds de producción.
- **Llave de firma en HSM:** La clave de firma debe estar en un HSM que nunca exponga la clave privada al pipeline.
- **SLSA Level 3+ compliance:** Build provenance, attestations, y verificación de fuente.
- **Reproducible builds:** Cualquier persona debe poder verificar que la ISO publicada fue generada del código fuente exacto.
- **Dependabot + lockfiles:** Todas las dependencias de build con hashes fijos.

---

## V-11: Audit Log Tampering

**Descripción:** `/var/log/magic/audit.log` es write-only append en teoría, pero:
- Si `/var` es writable y no hay verificación de integridad del log, un atacante puede truncar o modificar el log
- Sin log inmutable, no hay evidencia forense de compromiso

**Impacto:** MEDIO. Pérdida de capacidad de detección y forense.

**Feasibility:** ALTA (cualquier root compromise tiene acceso)

**Mitigación propuesta:**
- **Append-only con kernel support:** Usar `chattr +a` o `fs-verity` en el archivo de log.
- **Log shipping en tiempo real:** Enviar cada entrada de log a un servidor remoto (SIEM) antes de persistir localmente.
- **Integrity measurement:** Calcular hash del log periódicamente y almacenarlo en una ubicación protegida (TPM o remote).

---

## Resumen de Vectores

| ID | Vector | Impacto | Feasibility | Estado | Mitigación |
|----|--------|---------|-------------|--------|------------|
| V-01 | Bootkit (registry.asc) | CRÍTICO | MEDIA | **MITIGADO** | TPM PCR binding + dm-verity en stage-1 + recovery read-only firmado |
| V-02 | Evil Maid (Secure Boot) | CRÍTICO | BAJA-MEDIA | **MITIGADO** | Secure Boot mandatory + verificación en stage-0 |
| V-03 | Supply Chain (magic-apt) | ALTO | MEDIA | **MITIGADO** | HSM/cosign (clave privada nunca en disco) + sandbox bubblewrap para apt + reproducible builds |
| V-04 | Overlay Toxicity | ALTO | MEDIA | **MITIGADO** | POST-mount hash verification en stage-2 + allowlist de capas + dm-verity |
| V-05 | Persistencia en /var, /etc | ALTO | ALTA | **MITIGADO** | Grimoire source of truth + verificación POST-mount contra manifest firmado + AppArmor mandatory |
| V-06 | Weaponización de Rollback | MEDIO-ALTO | BAJA | **MITIGADO** | Rate limiting (3/hora) + deprecated flag + pre-snapshot de seguridad |
| V-07 | YAML Injection (Grimoire) | CRÍTICO | MEDIA | **MITIGADO** | JSON Schema validation + firma obligatoria + denylist de campos + SRI para fuentes remotas |
| V-08 | Bubblewrap Escape | MEDIO | BAJA | **MITIGADO** | Seccomp-bpf + AppArmor profile estricto + kernel hardening (unprivileged_userns_clone=0) |
| V-09 | DoS por Snapshots | MEDIO | ALTA | **MITIGADO** | Límite de 10 snapshots + cleanup automático + alertas de uso de disco |
| V-10 | Compromiso CI/CD | CRÍTICO | BAJA | **MITIGADO** | Self-hosted runners + HSM + SLSA Level 3 attestation + reproducible builds |
| V-11 | Audit Log Tampering | MEDIO | ALTA | **MITIGADO** | `chattr +a` (append-only) + log shipping en tiempo real a SIEM + integrity measurement |

---

## Preguntas para Rick (antes del MVP) — CERRADAS

> Todas las preguntas fueron respondidas por Rick en `ARCHITECTURE.md` (commit 7afb0ba). Cierro esta sección.

1. **✅ ¿Dónde vive la clave de firma?** → HSM externo. Solo `verify.pub` en disco. `ARCHITECTURE.md:127`
2. **✅ ¿dm-verity está contemplado?** → Sí, mandatory en stage-1. `ARCHITECTURE.md:90`
3. **✅ ¿Qué pasa si `registry.asc` está corrupto?** → TPM PCR binding. Si el archivo se reemplaza, los PCRs no matchean → boot denegado. `ARCHITECTURE.md:90`
4. **✅ ¿Cómo se protege `magic.yaml`?** → JSON Schema + firma obligatoria + denylist de campos + SRI. `ARCHITECTURE.md:66-72`
5. **✅ ¿Hay rate limiting en `magic-apt`?** → Sí, máximo 3 rollbacks/hora. `ARCHITECTURE.md:117`
6. **✅ ¿El pipeline de CI usa runners self-hosted?** → Sí, SLSA Level 3. `BUILD.md:79`
7. **✅ ¿`audit.log` tiene append-only?** → Sí, `chattr +a` + log shipping a SIEM. `ARCHITECTURE.md:83`
8. **✅ ¿El recovery es modificable?** → No. Consola de recovery read-only firmada. Requiere challenge-response con clave fuera del disco. `ARCHITECTURE.md:90`
9. **✅ ¿Keyring de apt?** → Valida SHA256 de cada paquete contra manifest firmado + sandbox bubblewrap. `ARCHITECTURE.md:98-110`
10. **✅ ¿Cómo se evita paquete que enmascare binario?** → POST-mount verification en stage-2: hashes contra `registry.asc` + allowlist de capas. `ARCHITECTURE.md:91-94`
11. **✅ ¿stage-1 verifica solo la base o todas las capas?** → POST-mount verifica TODAS las capas activas. `ARCHITECTURE.md:91-94`
12. **✅ ¿Qué pasa si `grimoire apply` falla a mitad?** → Rollback automático al estado anterior. Transacción atómica. `ARCHITECTURE.md:96`
