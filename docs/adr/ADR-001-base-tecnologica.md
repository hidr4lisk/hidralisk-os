# ADR-001 — Base tecnológica: ¿construir de cero o sobre lo que ya existe?

- **Estado:** Propuesta (espera OK de fede) · **Fecha:** 2026-06-29
- **Contexto previo:** `ESTADO.md` §2.1 ("no reinventar lo inventado")
- **Decisión que cierra:** la pregunta-gate de todo el proyecto, antes de codear `overmind`/`hidra-init`/`hidra-apt`.

---

## 1. Contexto

El diseño que salió del Enjambre (mesa 177) propone una distro Debian inmutable **construida casi
toda a mano**:

- `hidra-init` — init propio que enciende dm-verity, verifica hashes contra un `registry.asc` atado
  a PCRs del TPM, monta capas por allowlist.
- `hidra-apt` — gestor de paquetes propio que envuelve apt en capas ostree atómicas con rollback Btrfs.
- `overmind` + `hidra.yaml` — orquestador declarativo propio (YAML → capas ostree firmadas).
- Integridad propia — dm-verity + `registry.asc` firmado + binding TPM-PCR, todo hecho a mano.

La pregunta de §2.1: **¿cada una de esas piezas justifica existir, o ya hay un estándar maduro que
hace lo mismo?** Investigación al 2026-06-29 abajo.

## 2. Hallazgos — lo que YA existe (y resuelve casi todo el diseño)

| Pieza que el diseño inventa | Ya existe (maduro / upstream) | Veredicto |
|---|---|---|
| Distro **Debian inmutable + apt** completa | **Vanilla OS 2** (base Debian sid, **ABRoot** A/B vía imágenes OCI, **apx** = apt en contenedor) | Ya está hecho, en producción, open source |
| Init de capas + rootfs inmutable + OCI-como-OS | **bootc** (boot desde imagen OCI; ostree por debajo; CLI/API **estable**; **CNCF Sandbox** desde ene-2025, vendor-neutral) | Reemplaza `hidra-init` entero |
| Integridad por bloque + verificación firmada | **composefs + fs-verity + firma Ed25519** (integrado con ostree; valida el árbol entero, RO real, firma en el initrd) | Reemplaza dm-verity+`registry.asc`+TPM hechos a mano |
| `apt` atómico con rollback | **Layering en build** (`Containerfile` `RUN apt-get`) + **apx/distrobox** para apps de usuario en runtime | Reemplaza `hidra-apt` |
| Orquestador declarativo (`hidra.yaml`) | **Vib** (recetas YAML → `Containerfile` → imagen OCI, estilo Flatpak), **Butane/Ignition**, **cloud-init** | Reemplaza `overmind` |
| Build de la imagen (pipeline) | **bootc-image-builder** / **Containerfile** + podman; el experimento **`bootcrew/debian-bootc`** ya corre bootc sobre Debian con backend composefs nativo | Reemplaza casi todo `stage1-5` |
| A/B atómico + rollback (alternativa a ostree) | **ABRoot** (mismo modelo que SteamOS/ChromeOS/Android) | Alternativa probada en Debian |

**Conclusión dura:** el ~80% del diseño (init, pkg-mgr, integridad, orquestador, pipeline) **es
plomería que el ecosistema bootc/ostree/composefs y Vanilla OS ya resolvieron mejor, con
mantenimiento upstream y revisión de seguridad real.** Construir eso de cero es asumir su
mantenimiento eterno + el riesgo de seguridad de un init y una verificación caseros.

## 3. Opciones

- **A — From-scratch (lo de la mesa).** Init/pkg-mgr/integridad propios. ❌ Meses de trabajo, superficie
  de ataque casera, mantenimiento infinito. Solo se justifica si hubiera un requisito que NINGÚN
  stack existente cumple — y no lo hay.
- **B — Debian + bootc (OCI-native).** La OS es una **imagen OCI** (`Containerfile FROM` una base
  Debian-bootc) con composefs+fs-verity para integridad. Build con podman/bootc-image-builder.
  ✅ Es la dirección de la industria (Fedora/RHEL ya, CNCF). ⚠️ El soporte Debian de bootc todavía
  es **experimental** (`debian-bootc`).
- **C — ABRoot / spin de Vanilla OS.** Reusar el motor A/B+OCI ya probado de Vanilla OS (o hacer un
  spin con su imagen base + Vib). ✅ Debian inmutable **probado en prod hoy**. ⚠️ Atás el destino a
  las decisiones de Vanilla OS.

## 4. Decisión (propuesta)

**Adoptar el esquema B (Debian + bootc + composefs), con C (ABRoot/Vanilla) como referencia y red de
seguridad.** Hidralisk OS deja de ser "una distro construida de cero" y pasa a ser:

> **Una imagen Debian *bootc* con una postura de seguridad opinada y una capa de UX/integración
> propia del ecosistema HIDRA.**

El diferenciador **sube en el stack**: ya no competimos reinventando el init y el gestor de paquetes
(donde íbamos a perder), sino en **lo que sí es nuestro y valioso**:

1. **Seguridad por defecto** — acá SÍ aportamos: `THREAT_MODEL.md` y `HARDENING.md` (el mejor trabajo
   de la mesa) se vuelven **configuración real** de la imagen (AppArmor, sysctl, kernel cmdline,
   firma, Secure Boot, audit), no binarios caseros.
2. **Integración con HIDRA** — la imagen viene lista para el ecosistema (hidralisk, nodos, enjambre).
3. **Capa de receta/UX** — opcional: un `hidra.yaml` fino que *compila a un `Containerfile`* (modelo
   Vib), como azúcar declarativa. Eso sí es un diferenciador legítimo; un init propio no.

## 5. Qué sobrevive del repo actual

| Artefacto | Destino |
|---|---|
| `THREAT_MODEL.md`, `HARDENING.md` | ✅ **Se quedan** — son el corazón del valor; se vuelven config de la imagen |
| `README.md`, `ARCHITECTURE.md`, `ACTION_PLAN.md` | ♻️ Reescribir el "cómo" (init/pkg-mgr propios → bootc/composefs); el "qué/por qué" se conserva |
| `hidra-schema.json` | ♻️ Solo si mantenemos la capa-receta `hidra.yaml`; si no, se retira |
| `scripts/stage1-base..stage5` (mmdebstrap→ostree→ISO) | ⚠️ Mayormente **superados** por `Containerfile` + bootc-image-builder. El know-how de mmdebstrap/firma se recicla parcial |
| `overmind`, `hidra-apt`, `hidra-init` (stubs) | ❌ **No se implementan** — los cubre bootc/composefs/apx |
| dm-verity + `registry.asc` + TPM a mano | ❌ Reemplazado por composefs+fs-verity+Ed25519 (y measured boot upstream si hace falta) |

## 6. Consecuencias

- El **roadmap de 4 fases / 12 semanas** de `ACTION_PLAN.md` queda **obsoleto** — se replantea sobre bootc.
- **El spike se vuelve barato y factible en jarvis**: ya no hay que correr mmdebstrap+mkosi+ostree+QEMU.
  El nuevo "hola mundo" es un `Containerfile FROM` una base Debian-bootc + `podman build` + boot de
  prueba. Mucho más liviano sobre el server en vivo.
- **Pendiente de validar (próximo paso):** qué tan usable está hoy `debian-bootc` (es experimental).
  Si bloquea, caemos a la opción C (Vanilla OS/ABRoot) sin cambiar la tesis.

## 7. Próximo paso si se aprueba

Spike-1 (liviano): un `Containerfile` mínimo sobre una base Debian-bootc, `podman build`, y bootearlo
(VM/`bootc install`). Objetivo: validar la opción B en concreto antes de invertir en la capa de seguridad.

---

## Fuentes

- bootc — proyecto y estado: <https://github.com/bootc-dev/bootc> · <https://bootc.dev/bootc/building/guidance.html>
- bootc en CNCF Sandbox + futuro: <https://developers.redhat.com/blog/2025/07/23/shape-future-linux-contribute-bootc-open-source-project>
- Debian + bootc (experimento, backend composefs): <https://github.com/bootcrew/debian-bootc>
- bootc-image-builder: <https://github.com/osbuild/bootc-image-builder>
- Vanilla OS 2 (Debian inmutable): <https://lwn.net/Articles/989629/> · <https://distrowatch.com/vanilla>
- ABRoot (A/B + OCI): <https://github.com/Vanilla-OS/ABRoot> · <https://docs.vanillaos.org/docs/en/abroot>
- apx (apt en contenedor): <https://vanillaos.org/blog/article/2023-01-28/apx-an-unconventional-package-manager>
- Vib (recetas YAML → OCI): <https://vib.vanillaos.org/> · <https://github.com/Vanilla-OS/Vib>
- composefs + fs-verity en ostree: <https://ostreedev.github.io/ostree/composefs/> · <https://blogs.gnome.org/alexl/2023/07/11/composefs-state-of-the-union/>
- OSTree native containers: <https://coreos.github.io/rpm-ostree/container/>
- Estado de Linux inmutable: <https://justingarrison.com/blog/state-of-immutable-linux/>
