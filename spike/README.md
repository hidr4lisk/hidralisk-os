# Spike — validar el ADR-001 en concreto

Objetivo: probar que la tesis del [ADR-001](../docs/adr/ADR-001-base-tecnologica.md) funciona —
**derivar de una base Debian-bootc** y agregar solo nuestra capa de valor, en vez de construir
init/pkg-mgr/integridad propios.

> Se corre en el **Laboratorio** (192.168.0.7, KVM), NO en jarvis (server en vivo). El Lab tiene
> recursos de sobra y KVM para bootear de verdad.

## Spike-1 — build + lint (necesita Docker o Podman)

```bash
# en el Laboratorio, dentro del repo:
podman build -t hidralisk-os:spike spike/     # o: docker build -t hidralisk-os:spike spike/
```

Valida:
1. **FROM** una base Debian-bootc real (`ghcr.io/bootcrew/debian-bootc:latest`).
2. **Layering apt** en build (instala openssh-server, ufw, htop…).
3. **`bootc container lint`** pasa tras nuestra capa → sigue siendo una imagen bootc bien formada.

## Spike-2 — bootear la imagen como SO real (necesita KVM + bootc-image-builder)

Convertir la imagen OCI en un disco booteable y arrancarlo en una VM:

```bash
mkdir -p output
sudo podman run --rm -it --privileged \
  -v ./output:/output \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  quay.io/centos-bootc/bootc-image-builder:latest \
  --type qcow2 --local localhost/hidralisk-os:spike

# arrancar el qcow2 resultante en KVM/qemu y validar:
#   - bootea
#   - cat /etc/hidralisk-os-release  → "Hidralisk OS"
#   - sysctl kernel.kptr_restrict    → 2  (hardening aplicado)
```

Valida: la imagen **arranca como SO inmutable de verdad** (no solo lintea). Si `debian-bootc`
da problemas en este paso (es experimental), el plan B del ADR es Vanilla OS / ABRoot.

## Estado — descartado (ver ADR-002)

Corrido en el Laboratorio (2026-06-29). Resultado: **el combo `bootcrew/debian-bootc` +
`bootc-image-builder` está demasiado crudo para Debian hoy** — 5 fallas concretas (sin DB de
dpkg para layerizar apt, sin VERSION_ID, sin DefaultRootFs, stage SELinux hardcodeado en bib, y
deployment ostree roto en el `bootc install` nativo). La KVM y el tooling de fondo (bootc/ostree/
**verity**) funcionan; la imagen base experimental no.

→ **Decisión: pivotar a Vib/Vanilla.** Detalle y evidencia en
[`../docs/adr/ADR-002-vehiculo-de-build.md`](../docs/adr/ADR-002-vehiculo-de-build.md).

- [x] Spike-1/2 — bootc-on-Debian → **descartado** (evidencia en ADR-002)
- [ ] Spike-3 — receta **Vib** mínima + boot en KVM (siguiente)

> Este `Containerfile` queda como registro del experimento, no como base del proyecto.
