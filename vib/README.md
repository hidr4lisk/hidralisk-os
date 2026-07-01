# Build con Vib — vehículo de Hidralisk OS

Vehículo elegido en [ADR-002](../docs/adr/ADR-002-vehiculo-de-build.md): **Vib** (receta YAML →
imagen OCI) sobre la base inmutable de **Vanilla OS**, en vez de bootc-on-Debian (descartado por
inmaduro). `recipe.yml` es la fuente de verdad de la imagen.

## Cómo construir (en el Laboratorio, 192.168.0.7)

```bash
cd ~/repos/hidralisk-os
# binario Vib (una vez): curl -fsSL -o vib-amd64 \
#   https://github.com/Vanilla-OS/Vib/releases/download/v1.1.0/vib-amd64 && chmod +x vib-amd64
./vib-amd64 build vib/recipe.yml                              # → genera vib/Containerfile
sudo podman build -t hidralisk-os:vib -f vib/Containerfile vib
```

> ⚠️ **Cache de podman:** el `Containerfile` monta `vib/sources/` con `--mount`, y podman cachea la capa
> `RUN` por el TEXTO del comando, **no** por el contenido montado. Si cambiás **solo** un archivo de
> `vib/sources/` (p.ej. `hidrafetch`) sin tocar `recipe.yml`, la imagen sale idéntica (capa cacheada) y el
> cambio **no entra**. En ese caso buildeá con **`--no-cache`**:
> `sudo podman build --no-cache -t hidralisk-os:vib -f vib/Containerfile vib`.
>
> ⚠️ **`vib build` vacía `vib/sources/`** al generar el Containerfile → restaurá con
> `git checkout -- vib/sources` **antes** del `podman build`.

## Spike-3 — ✅ validado (2026-06-29)

Probó la pregunta que bloqueaba todo (pared #1 del ADR-002): **¿se pueden instalar paquetes con
`apt` sobre una base Debian inmutable real?** Sí.

- Base: `ghcr.io/vanilla-os/core:latest` — trae la **DB de dpkg funcional** (962 paquetes), a
  diferencia de `bootcrew/debian-bootc` (que no shippea la DB → bloqueaba apt).
- Resultado: imagen `hidralisk-os:vib` con `openssh-server`, `ufw`, `htop`, `ca-certificates`
  instalados (binarios en `/usr/sbin/sshd`, `/usr/sbin/ufw`, `/usr/bin/htop`) e identidad en
  `/etc/hidralisk-os-release`.
- Aprendizaje: la base `core` **no** necesita `lpkg --unlock` (su capa de paquetes no está trabada;
  eso aplica a la imagen `desktop`). El formato de receta usa `vibversion`, no `version`.

## Próximo — Spike-4 (bootear de verdad)

La imagen OCI todavía no es un sistema booteado. Vanilla OS no usa bootc para instalar: el camino
es **construir una ISO live** (repo `Vanilla-OS/live-iso`) a partir de esta imagen, o **deployarla
con ABRoot** sobre una instalación existente. Spike-4 = generar ese artefacto y arrancarlo en la KVM
del Lab. Recién ahí se materializan la integridad (FsGuard) y el modelo A/B.
