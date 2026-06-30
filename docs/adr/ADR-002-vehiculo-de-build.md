# ADR-002 — Vehículo de build: Vib/Vanilla

- **Estado:** ✅ Aceptada (fede, 2026-06-29) · **Fecha:** 2026-06-29
- **Origen:** resultados de un spike de validación en el Laboratorio (192.168.0.7, KVM)

---

## 1. Contexto

**Principio fundacional del proyecto:** no construir init/pkg-mgr/integridad propios, sino derivar
de tecnología inmutable existente (madura y mantenida). El primer candidato concreto fue
**bootc-on-Debian** (`ghcr.io/bootcrew/debian-bootc` + `bootc-image-builder`). El spike fue a
validarlo en el Lab.

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
- Sigue siendo **OCI + atómico + A/B** (el principio fundacional intacto).
- No nos atamos a tooling RHEL que asume SELinux.

## 4. Alternativas descartadas

- **Forkear `bootcrew/mono` y arreglarlo** — adoptar el mantenimiento del experimento ajeno (DB de
  dpkg, deployment ostree roto, etc.). Mucho riesgo, poco control.
- **Construir nuestra propia base Debian-bootc de cero** — contradice el principio fundacional (no reinventar la plomería).
- **Esperar a que `debian-bootc` madure** — nos bloquea hoy; lo re-evaluamos más adelante (la tecnología
  de fondo es la correcta, solo está verde para Debian).

## 5. Consecuencias

- El experimento bootc quedó como aprendizaje (la tecnología de fondo es correcta, solo está verde
  para Debian), no como base del proyecto.
- **Vehículo de build:** receta [Vib](https://vib.vanillaos.org/) → imagen OCI
  (`ghcr.io/hidr4lisk/hidralisk-os`) + ISO custom. Ver [`../../vib/README.md`](../../vib/README.md)
  e [`../../iso/README.md`](../../iso/README.md).
- El **hardening** ([`../../HARDENING.md`](../../HARDENING.md)) es el diferenciador y se materializa
  como pasos del recipe Vib.
- Revisar bootc-on-Debian en ~6-12 meses; si madura, es un destino natural a largo plazo.

## 6. Estado de validación

- [x] Spike-1/2 — bootc-on-Debian: **descartado hoy** (evidencia §2)
- [x] **Spike-3 — Vib/Vanilla: ✅ VALIDADO (2026-06-29).** Receta Vib mínima sobre
  `ghcr.io/vanilla-os/core` construyó la imagen **Hidralisk OS** con `apt` instalando
  openssh-server/ufw/htop/ca-certificates (binarios presentes) + identidad en
  `/etc/hidralisk-os-release`. **La pared #1 (apt-layering sobre base inmutable) resuelta.**
  Nota: `core` no necesita `lpkg --unlock` (su capa no está trabada; eso es de `desktop`).
  Detalle → [`../../vib/README.md`](../../vib/README.md).
- [x] **Spike-4a — ✅ VALIDADO (2026-06-29).** Construimos la ISO live de Vanilla en el Lab
  (`live-iso` vía contenedor `pico` + `live-build`) → `VanillaOS-2-stable.20260629.iso` (2.2 GB) y
  **booteó en KVM con GUI** (UEFI/OVMF, virt-manager). Valida el toolchain de build+boot end-to-end
  sobre nuestra infra. (Contenido stock de Vanilla todavía — nuestra imagen entra en 4b.)
- [x] **Spike-4b — ✅ VALIDADO (2026-06-29).** Un sistema **Hidralisk OS** instalado en KVM,
  booteando **desde nuestra imagen OCI**. Prueba dura (`abroot status` en el instalado):
  ```
  ABRoot Partitions: Present: vos-a ✓  ·  Future: vos-b
  ABImage:  Image: ghcr.io/hidr4lisk/hidralisk-os:latest
            Digest: sha256:1905d5a5…  ·  Timestamp: 2026-06-29 20:39:52
  Kernel Arguments: … lsm=integrity
  ```
  Más `/etc/hidralisk-os-release` → `NAME="Hidralisk OS"`, `sshd active`, `qemu-guest-agent`
  respondiendo (entré por SSH a verificar). **Camino que funcionó (b): ISO custom.**

  **Dos lecciones duras del spike (claves para repetirlo):**
  1. **`core` NO es base instalable.** El instalador (albius) corre un pre-script de initramfs
     `lpkg --unlock` al desplegar, y `core` **no trae `lpkg`** → `panic: initramfs pre-script
     'lpkg --unlock' failed`. Hay que construir sobre **`ghcr.io/vanilla-os/desktop`** (la base
     instalable, que sí trae `lpkg` + kernel + ABRoot + GRUB), con el patrón oficial de Vanilla
     (`vm-image/recipe.yml`): **`lpkg --unlock` → apt → `lpkg --lock`**. El recipe nuevo
     (`vib/recipe.yml`) ya usa esto + agrega `qemu-guest-agent`/`spice-vdagent` (acceso a la VM).
     > Nota: el Spike-3 eligió `core` por evitar `lpkg`; vale para *validar apt-layering*, pero
     > `core` es base de **build**, no de **install**. Para producto: `desktop`.
  2. **El instalador elige la imagen por su `recipe.json`** (`/etc/vanilla-installer/recipe.json`).
     Shippeamos uno propio en la ISO vía hook del chroot (`iso/hooks/078-hidralisk-recipe.chroot`):
     `distro_name: "Hidralisk OS"` + las 3 imágenes (`default`/`nvidia`/**`vm`**, ojo: en KVM
     dispara `vm`) → `ghcr.io/hidr4lisk/hidralisk-os`. El `abroot upgrade` manual (camino a) quedó
     descartado: en la práctica chocó con el contenedor apx read-only y el teclado por VNC.
- [x] **Spike-5 — branding ✅ (2026-06-29).** os-release ("Hidralisk OS", `ID=vanilla` intacto a
  propósito), VSO First-Setup deshabilitado, instalador renombrado (`.desktop`, hook 079) +
  **flor→dragón** (hook 080), GRUB "Install Hidralisk OS", logo GDM/distribuidor + watermark de
  Plymouth (dragón blanco), **wallpaper** (escritorio + login GDM + sesión live de la ISO) con
  dragón + "Hidralisk OS", y **avatar** de usuario por defecto (oneshot `hidralisk-firstboot`,
  UID 1000). Assets en `vib/sources/hidralisk/branding/` + hooks en `iso/`.
- [x] **Spike-6 — shell por defecto ✅ (2026-06-29).** zsh + starship (tema Hidralisk) +
  zsh-autosuggestions + zsh-syntax-highlighting + Hack Nerd Font + **Ptyxis** (terminal), config
  **system-wide** (`/etc/zsh/zshrc` + `/etc/starship.toml`), neutra (sin nada personal). El cambio
  de shell del usuario instalado lo hace el oneshot de firstboot.
- [x] **Spike-7 — hardening por defecto ✅ source (2026-06-30).** El diferenciador real,
  materializado en el recipe: `sysctl` endurecido (`vib/sources/hidralisk/hardening/99-hidra-hardening.conf`)
  + `ufw default-deny incoming`, **reconciliado con `apx`** (se omiten userns/bpf que romperían los
  contenedores rootless). Detalle → [`../../HARDENING.md`](../../HARDENING.md). Falta el build de la
  imagen con esta capa + el showcase de instalación end-to-end (ver [`../../ROADMAP.md`](../../ROADMAP.md)).
- [ ] **Pendiente:** botón final "Install Vanilla OS" dentro del instalador (en
  `vanilla-installer.gresource` → requiere build propio del instalador); verificar que el fondo del
  login GDM renderice en el greeter; fases siguientes de hardening y experiencia de escritorio
  (ver [`../../ROADMAP.md`](../../ROADMAP.md)).
