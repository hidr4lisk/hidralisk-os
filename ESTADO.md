# ESTADO — proyecto distro (ex "SpellOS")

> **Léeme primero.** Este doc es el estado real del proyecto al sacarlo del enjambre.
> El resto de los `.md` (README, ARCHITECTURE, BUILD, THREAT_MODEL, HARDENING, ACTION_PLAN)
> son el **diseño** producido por la mesa 177 del enjambre. Esto de acá es la lectura fría
> de qué hay, qué falta y qué decidir **antes** de seguir.

**Fecha:** 2026-06-29 · **Origen:** enjambre mesa-177 (Rick · arquitectura, ZeroCool · threat
model/hardening, Ultron · integración). La mesa se borró de la DB; los archivos persisten acá.

---

## 1. Qué es esto hoy

Un **whitepaper + esqueleto de build de buena calidad**, NO una distro.

- **Diseño:** sólido. Inmutable por capas (ostree + overlayfs + Btrfs), compatible `.deb`,
  orquestador declarativo (`hidra.yaml`), seguridad por arquitectura (dm-verity, TPM-PCR binding,
  firma obligatoria, audit log append-only, SLSA L3). Threat model con 11 vectores cruzados
  contra mitigaciones en `ACTION_PLAN.md`.
- **Implementación:** ~10%. Los `scripts/stageN-*.sh` (mmdebstrap → ostree → ISO) son andamiaje
  correcto, pero **el corazón no existe todavía**: `overmind` (orquestador), `hidra-apt` (gestor
  atómico) y `hidra-init` (init de verificación por capas) son conceptos en YAML, no binarios.
  Lo más difícil es justo lo que falta.

## 2. Lo crítico ANTES de seguir

### 2.1 NO reinventar lo que ya está inventado ⚠️ (prioridad)

Buena parte del diseño re-crea estándares maduros. Antes de escribir una línea más del
orquestador/init propios, mapear cada pieza contra lo que ya existe y decidir
**construir-encima vs. construir-de-cero**:

| Pieza inventada acá | Ya existe (madurо) | Decisión a tomar |
|---|---|---|
| `overmind` + `hidra.yaml` (config declarativa) | **Butane/Ignition**, cloud-init | ¿Es un wrapper de UX o algo nuevo de verdad? |
| Init de capas + rootfs inmutable + `.deb` encima | **bootc** / **ostree native containers** (camino de Fedora/RHEL), **systemd-sysext/confext** | bootc te da el 70% del trabajo de bajo nivel ya resuelto y mantenido |
| `hidra-apt` (capas atómicas sobre apt) | `rpm-ostree`, `apt` + overlay, **bootc** layering | ¿overlay propio o el modelo de bootc? |
| Firma/verificación de capas | **dm-verity + composefs**, fs-verity, **cosign/Sigstore + Rekor** | usar los de upstream, no firmar a mano |
| Reproducible build / attestation | **SLSA**, `mkosi` (ya genera la imagen), in-toto | el diseño ya apunta acá — bien |

> **Regla del proyecto:** cada componente "propio" tiene que justificar por qué no es
> simplemente `bootc + composefs + Butane + cosign` con una capa de UX encima. Si la respuesta
> es "no se me ocurre por qué", entonces es eso y nos ahorramos meses + el riesgo de seguridad
> de un init casero.

**Spike recomendado (1-2 días) antes de comprometerse al roadmap de 12 semanas:**
¿bootea en QEMU el rootfs base ostree que generan los scripts actuales? Eso convierte el 90%
de teoría en algo tangible y dice rápido si vale la pena.

### 2.2 Rename — RESUELTO ✅ (2026-06-29)

**Nombre elegido: `Hidralisk OS`** (con `i`, la grafía de la marca de fede — comparte ADN con la
shell OS `hidralisk` del ecosistema, a propósito). Motivos del rename desde "SpellOS":
1. **Colisión de marca:** `spell-os.com` ya existía (sitio React/Vercel — auditado en la mesa-182).
2. **Coherencia con el ecosistema HIDRA:** todo tiene ADN Zerg (hidralisk, hidr4lisk, nodos HIDRA,
   sillas del enjambre = broods). La distro engancha con los Zerg, no con magia.

Se migró todo el tema "magia/spell/grimoire" al **esquema A: `hidra*` + Overmind**. Mapeo aplicado:

| Antes | Ahora |
|---|---|
| `SpellOS` / `spellos` (display) | **Hidralisk OS** / `hidralisk` (token corto, sin espacio, para paths/ISO) |
| `grimoire` (orquestador declarativo) | **overmind** (el Overmind dirige al enjambre = orquesta las capas) |
| `magic-apt` / `magic-init` / `magic-rollback` | `hidra-apt` / `hidra-init` / `hidra-rollback` |
| `magic.yaml` / `magic-schema.json` | `hidra.yaml` / `hidra-schema.json` |
| `/etc/magic/` · `/var/log/magic/` | `/etc/hidra/` · `/var/log/hidra/` |
| `magic:` (raíz del YAML) | `hidra:` |
| archivo `scripts/stage2-magic.sh` | `scripts/stage2-hidra.sh` |
| `MagicLinux` (residuo viejo) | `Hidralisk` |

> **Nota de token:** el display es "Hidralisk OS" (con espacio) solo en títulos; el identificador
> en código/paths/ISO es `Hidralisk`/`hidralisk` (sin espacio) para no romper nombres de archivo
> ni labels. Patrón "Fedora" vs "Fedora Linux".
>
> **Pendiente humano (fede):** verificar que el dominio/marca que se use de placeholder
> (`hidralisk.dev`, `github.com/hidralisk/hidralisk` en la attestation SLSA) sea el real cuando se
> publique. `keys/verify.pub` se dejó intacto a propósito (no tocar la clave GPG con sed).

### 2.3 TPM-PCR binding: ojo

Atar `registry.asc` a PCRs del TPM cierra V-01 en papel, pero es **el dolor operativo clásico**
de las distros inmutables: un update de firmware/kernel cambia los PCRs y brickea el boot si no
manejás el *resealing* automático. Está bien que esté en el diseño; hay que saber que ahí vive
el 80% del sufrimiento futuro.

## 3. Estado del repo (housekeeping)

- Es repo git con historial real de la mesa (branch `master`, ~10 commits).
- **Archivos creados por el container del enjambre como `root`** → para poder editarlos:
  ```
  sudo chown -R patadamortal:patadamortal ~/repos/spellos
  ```
- Hay cambios sin commitear del último turno de la mesa (`M Makefile`, `M build.sh`,
  `M stage2/stage5`, `?? smoke-test.sh`, `?? lint.yml`) — revisar y commitear o descartar.

## 4. Veredicto

Como documento de arquitectura para arrancar algo serio, está muy bueno y la dinámica del
enjambre funcionó (ZeroCool encontró agujeros reales, Rick los cerró). Como software, está en
la línea de salida. El mayor riesgo NO es técnico: es construir de cero lo que bootc/composefs/
Butane ya resuelven. Resolver §2.1 (no reinventar) y §2.2 (nombre) **antes** de meterle meses.
