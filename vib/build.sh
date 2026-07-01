#!/bin/sh
# Build de la imagen OCI de Hidralisk OS. Correr EN EL LABORATORIO (donde estan vib-amd64,
# podman y el login a GHCR). Encapsula los dos gotchas del pipeline:
#   1) `vib build` VACIA vib/sources/  -> se restaura con git antes del podman build.
#   2) podman CACHEA la capa RUN aunque cambien archivos de vib/sources/ (el --mount no
#      invalida el cache) -> usar --no-cache cuando cambiaste SOLO fuentes (no el recipe).
#
# Uso:
#   vib/build.sh                 # build (usa cache; ok si cambiaste el recipe)
#   vib/build.sh --no-cache      # fuerza rebuild (cambios de SOLO fuentes, p.ej. hidrafetch)
#   vib/build.sh --push          # ademas tag + push a ghcr.io :latest y :main
#   vib/build.sh --no-cache --push
#
# Requisitos: `vib-amd64` en la raiz del repo; `sudo podman`; para --push, estar logueado a
# GHCR (`podman login ghcr.io -u hidr4lisk`). Para sudo no-interactivo: exportar SUDO_ASKPASS.
set -e

REPO=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO"

NOCACHE=""
PUSH=0
for a in "$@"; do
    case "$a" in
        --no-cache) NOCACHE="--no-cache" ;;
        --push)     PUSH=1 ;;
        *) echo "arg desconocido: $a (uso: [--no-cache] [--push])"; exit 2 ;;
    esac
done

IMG=hidralisk-os:vib
REMOTE=ghcr.io/hidr4lisk/hidralisk-os

[ -x ./vib-amd64 ] || { echo "falta ./vib-amd64 en la raiz del repo"; exit 1; }

echo "[build] 1/3 vib build (genera vib/Containerfile; ojo: vacia vib/sources)"
./vib-amd64 build vib/recipe.yml

echo "[build] 2/3 restaurando vib/sources (vib lo vacia)"
git checkout -- vib/sources

echo "[build] 3/3 podman build ${NOCACHE:-(con cache)}"
sudo podman build $NOCACHE -t "$IMG" -f vib/Containerfile vib

if [ "$PUSH" -eq 1 ]; then
    echo "[build] tag + push $REMOTE :latest + :main"
    sudo podman tag "$IMG" "$REMOTE:latest"
    sudo podman tag "$IMG" "$REMOTE:main"
    sudo podman push "$REMOTE:latest"
    sudo podman push "$REMOTE:main"
fi

echo "[build] OK -> $IMG"
