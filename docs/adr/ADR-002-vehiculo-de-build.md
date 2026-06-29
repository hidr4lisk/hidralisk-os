# ADR-002 — Vehículo de build: pivotar de bootc-on-Debian a Vib/Vanilla

- **Estado:** ✅ Aceptada (fede, 2026-06-29) · **Fecha:** 2026-06-29
- **Depende de:** [ADR-001](ADR-001-base-tecnologica.md) (aceptado: "construir sobre lo existente, no de cero")
- **Origen:** resultados del Spike-1/2 en el Laboratorio (192.168.0.7, KVM)

---

## 1. Contexto

ADR-001 decidió **no** construir init/pkg-mgr/integridad propios, sino derivar de tecnología
inmutable existente. El candidato concreto era **bootc-on-Debian** (`ghcr.io/bootcrew/debian-bootc`
+ `bootc-image-builder`). El spike fue a validarlo en el Lab.

## 2. Qué pasó en el spike (evidencia)

Se intentó: derivar la imagen (FROM + capa propia), construir un disco booteable, y bootearlo en KVM.
**Cinco paredes concretas, todas del lado de que el combo es experimental para Debian:**

| # | Paso | Falla |
|---|---|---|
| 1 | `FROM … RUN apt-get install` | La imagen **no shippea la DB de dpkg** (vive en `/var`, vacío en bootc) → **no se puede layerizar paquetes** con la derivación estilo Fedora |
| 2 | `bootc-image-builder` | `missing VERSION_ID in os-release` (Debian sid es rolling) → *fixeable* con un `echo` |
| 3 | `bootc-image-builder` | `missing required info: DefaultRootFs` (bib no conoce `ID=debian`) → *workaround* `--rootfs ext4` |
| 4 | `bootc-image-builder` (osbuild) | Stage **SELinux hardcodeado** (`setfiles` contra `file_contexts` inexistente) — Debian usa AppArmor. **Pared dura: bib asume RHEL.** |
| 5 | `bootc install to-disk` (nativo, sin bib) | Llegó lejos: particionó BIOS+EFI+root, creó **ext4 con verity** y ESP… y murió en `Creating ostree deployment: No such file or directory`. La imagen bootcrew está rota en el deployment. |

**Dato positivo importante:** la KVM del Lab y el tooling (podman, bootc, ostree, **verity/composefs**)
**funcionan** — el paso 5 creó un rootfs con verity sin problema. Lo que falla es **la imagen base
experimental**, no nuestra infra ni la tecnología de fondo.

## 3. Decisión (propuesta)

**Pivotar el vehículo de build al stack de Vanilla OS: [Vib](https://vib.vanillaos.org/) (receta
YAML → imagen OCI) + el modelo [ABRoot](https://github.com/Vanilla-OS/ABRoot) (A/B atómico, OCI).**

Por qué:
- **Es Debian inmutable EN PRODUCCIÓN** (Vanilla OS 2), no un experimento.
- **`apt` funciona**: Vib instala paquetes en una etapa Debian normal (con DB de dpkg real) antes de
  sellar la imagen → resuelve la pared #1, que era la bloqueante.
- Sigue siendo **OCI + atómico + A/B** (la tesis del ADR-001 intacta).
- No nos atamos a tooling RHEL que asume SELinux.

## 4. Alternativas descartadas

- **Forkear `bootcrew/mono` y arreglarlo** — adoptar el mantenimiento del experimento ajeno (DB de
  dpkg, deployment ostree roto, etc.). Mucho riesgo, poco control.
- **Construir nuestra propia base Debian-bootc de cero** — contradice ADR-001 (no reinventar la plomería).
- **Esperar a que `debian-bootc` madure** — nos bloquea hoy; lo re-evaluamos más adelante (la tecnología
  de fondo es la correcta, solo está verde para Debian).

## 5. Consecuencias

- El `spike/` actual (Containerfile bootc) queda como **registro del experimento**, no como base.
- **Próximo paso (Spike-3):** una receta **Vib** mínima que produzca una imagen Hidralisk OS con
  nuestros paquetes + el `hardening.sysctl`, y bootearla (ISO live / ABRoot) en la KVM del Lab.
- `THREAT_MODEL.md` / `HARDENING.md` siguen siendo el diferenciador y se materializan como módulos Vib.
- Revisar bootc-on-Debian en ~6-12 meses; si madura, es el destino natural a largo plazo.

## 6. Estado de validación

- [x] Spike-1/2 — bootc-on-Debian: **descartado hoy** (evidencia §2)
- [x] **Spike-3 — Vib/Vanilla: ✅ VALIDADO (2026-06-29).** Receta Vib mínima sobre
  `ghcr.io/vanilla-os/core` construyó la imagen **Hidralisk OS** con `apt` instalando
  openssh-server/ufw/htop/ca-certificates (binarios presentes) + identidad en
  `/etc/hidralisk-os-release`. **La pared #1 (apt-layering sobre base inmutable) resuelta.**
  Nota: `core` no necesita `lpkg --unlock` (su capa no está trabada; eso es de `desktop`).
  Detalle → [`../../vib/README.md`](../../vib/README.md).
- [ ] Spike-4 — bootear una imagen Hidralisk OS de verdad (ISO live de Vanilla / deploy ABRoot) en KVM.
