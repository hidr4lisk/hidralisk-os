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
  orquestador declarativo (`magic.yaml`), seguridad por arquitectura (dm-verity, TPM-PCR binding,
  firma obligatoria, audit log append-only, SLSA L3). Threat model con 11 vectores cruzados
  contra mitigaciones en `ACTION_PLAN.md`.
- **Implementación:** ~10%. Los `scripts/stageN-*.sh` (mmdebstrap → ostree → ISO) son andamiaje
  correcto, pero **el corazón no existe todavía**: `grimoire` (orquestador), `magic-apt` (gestor
  atómico) y `magic-init` (init de verificación por capas) son conceptos en YAML, no binarios.
  Lo más difícil es justo lo que falta.

## 2. Lo crítico ANTES de seguir

### 2.1 NO reinventar lo que ya está inventado ⚠️ (prioridad)

Buena parte del diseño re-crea estándares maduros. Antes de escribir una línea más del
orquestador/init propios, mapear cada pieza contra lo que ya existe y decidir
**construir-encima vs. construir-de-cero**:

| Pieza inventada acá | Ya existe (madurо) | Decisión a tomar |
|---|---|---|
| `grimoire` + `magic.yaml` (config declarativa) | **Butane/Ignition**, cloud-init | ¿Es un wrapper de UX o algo nuevo de verdad? |
| Init de capas + rootfs inmutable + `.deb` encima | **bootc** / **ostree native containers** (camino de Fedora/RHEL), **systemd-sysext/confext** | bootc te da el 70% del trabajo de bajo nivel ya resuelto y mantenido |
| `magic-apt` (capas atómicas sobre apt) | `rpm-ostree`, `apt` + overlay, **bootc** layering | ¿overlay propio o el modelo de bootc? |
| Firma/verificación de capas | **dm-verity + composefs**, fs-verity, **cosign/Sigstore + Rekor** | usar los de upstream, no firmar a mano |
| Reproducible build / attestation | **SLSA**, `mkosi` (ya genera la imagen), in-toto | el diseño ya apunta acá — bien |

> **Regla del proyecto:** cada componente "propio" tiene que justificar por qué no es
> simplemente `bootc + composefs + Butane + cosign` con una capa de UX encima. Si la respuesta
> es "no se me ocurre por qué", entonces es eso y nos ahorramos meses + el riesgo de seguridad
> de un init casero.

**Spike recomendado (1-2 días) antes de comprometerse al roadmap de 12 semanas:**
¿bootea en QEMU el rootfs base ostree que generan los scripts actuales? Eso convierte el 90%
de teoría en algo tangible y dice rápido si vale la pena.

### 2.2 Rename obligatorio 🐝

Dos motivos:
1. **Colisión de marca:** `spell-os.com` ya existe (sitio React/Vercel — auditado en la mesa-182
   del enjambre). Si ese dominio no es nuestro, "SpellOS" está tomado.
2. **Coherencia con el ecosistema HIDRA:** todo tiene ADN Zerg (hidralisk, hidr4lisk, nodos HIDRA,
   sillas del enjambre = broods). La distro tiene que **enganchar con los Zerg**, no con magia.

El tema "magia/spell/grimoire" hay que migrarlo a tema Zerg. **Restricción (fede, 2026-06-29):
el nombre tiene que tener que ver con CAPAS** — que es el corazón del diseño (base/system/user/
session). Y el Zerg engancha perfecto: su blindaje es un **caparazón hecho de capas de quitina**
(en StarCraft la mejora de armadura terrestre Zerg se llama literalmente **Carapace**: cada
mejora = otra capa). Candidatos ordenados por encaje con "capas":

| Nombre | Conexión con CAPAS + Zerg | Nota |
|---|---|---|
| **Carapace** (recomendado) | Caparazón Zerg = armadura **en capas** de quitina; en SC es el nombre de la mejora de armadura. Base inmutable readonly = la carapace; cada overlay = otra placa. "Seguridad por arquitectura" cae redonda. | verificar dominio |
| **Chitin** | La **sustancia** de cada capa del caparazón. Cada commit ostree = una placa de quitina. Corto/técnico. | `ChitinOS` |
| **Creep** | Sustrato Zerg que se expande **en capa** = la capa base sobre la que crece todo. | "creep" suena raro en inglés |
| **Molt** | El Zerg **muda** el caparazón para crecer una capa nueva → rollback = "molt back". | mejor como **verbo de comando** que como nombre |

Mapeo de renombres si se elige **Carapace** (+ `molt` como verbo de capa):
- `SpellOS` → **Carapace**
- `grimoire` (orquestador) → **overmind** (el Overmind dirige al enjambre = orquesta las capas)
- `magic.yaml` → `carapace.yaml` / `layers.yaml`
- `magic-apt` → `molt-apt`; comandos de capa: `molt apply` / `molt rollback`
- verbos "spell/cast" → "morph" / "molt"

> **Pendiente humano (fede):** elegir nombre + verificar dominio/marca libre, y recién ahí hacer
> el rename global (hay precedente: ya se hizo `MagicLinux → SpellOS` en 1 commit, ~34 ocurrencias).

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
