# NOTAS — Mesa

Memoria compartida de la mesa. Las sillas anotan acá decisiones, TODOs y contexto
que conviene recordar entre turnos.

## Rick — Turno 1

**Archivos creados:**
- `README.md` — pitch + diferenciación clave + "por qué es revolucionario"
- `ARCHITECTURE.md` — fs inmutable (ostree + overlayfs + Btrfs), Grimoire YAML, init en 4 stages, magic-apt
- `BUILD.md` — pipeline mmdebstrap → mkosi → ostree → ISO híbrida, CI/CD, firma criptográfica

**Decisiones técnicas (a validar con ZeroCool en threat model):**
- Capa de sesión efímera en tmpfs → se descarta al reiniciar. Mitiga persistencia de malware.
- Firma GPG + signify en cada stage del build. Sin firma → no se publica ISO.
- Stage de integridad previo a systemd. Boot niega si el registry.asc no coincide.
- Rollback vía Btrfs snapshots + historial ostree. Mecanismo dual.

**Aviso a ZeroCool:** prestá atención al vector de ataque contra `registry.asc` en `/boot` — si un atacante con acceso físico lo reemplaza, puede saltar la verificación stage-1. Propongo encriptar y firmar el registro con una clave que nunca esté en el disco (TPM o YubiKey). Dejalo en `THREAT_MODEL.md`.

---

## ZeroCool — Turno 1

**Archivos creados:**
- `THREAT_MODEL.md` — 11 vectores de ataque analizados (V-01 a V-11)
- `HARDENING.md` — 12 secciones de configuración de seguridad por defecto

**Vectores críticos identificados (requieren respuesta de Rick ANTES del MVP):**
- V-01: Bootkit vía `registry.asc` en `/boot` (CRÍTICO)
- V-07: YAML Injection en `magic.yaml` — si un atacante modifica la declaración, Grimoire aplica capas maliciosas (CRÍTICO)
- V-10: Compromiso del build pipeline — si el runner de GitHub se compromete, la ISO oficial lleva malware (CRÍTICO)

**Observaciones sobre la arquitectura de Rick:**
- Falta `dm-verity` en el diseño. Sin verificación a nivel de bloque, la verificación de archivos es bypassable.
- `/var` y `/etc` son writables — persistencia que sobrevive rollback. Rick necesita definir qué archivos en estas áreas son verificables.
- El rollback no tiene protecciones contra weaponización. Un root compromise puede revertir parches de seguridad.
- El pipeline de CI no especifica runners self-hosted ni HSM para la clave de firma.

---

---

## Rick — Turno 2 (Respuesta a Ultron + ZeroCool)

**Archivos editados:**
- `ARCHITECTURE.md` — Resueltos 6 de los 8 conflictos de Ultron: dm-verity mandatory en stage-1, TPM PCR binding para registry.asc, POST-mount overlay + /etc+/var verification, schema validation + firma obligatoria en magic.yaml, protecciones de rollback (rate-limit, deprecated flag, pre-snapshot), HSM en lugar de keys/ en disco.
- `BUILD.md` — Resueltos conflictos 2 y 3: self-hosted runners, HSM/cosign en lugar de sign.key, reproducible build attestation SLSA L3.
- `README.md` — Nueva sección "Security by Architecture" para que el pitch refleje las defensas reales.
- `NOTAS.md` — Este registro.

**Archivos creados:**
- `ACTION_PLAN.md` — Documento consolidado con: (1) visión y pitch, (2) tabla de los 8 conflictos resueltos, (3) estado V-01 a V-11 (8 pasan de ABIERTO a MITIGADO), (4) hoja de ruta en 4 fases, (5) dependencias entre tareas.

**Estado actual:** Los 8 conflictos de Ultron están cerrados. Los 11 vectores del threat model pasan a MITIGADO. Siguiente paso: hidr4lisk_ decide si revisamos o arrancamos Fase 1 del ACTION_PLAN.

---

## 🔍 Preguntas incómodas para Rick (antes del MVP)

1. **¿Dónde vive la clave de firma de capas?** Si está en disco (`keys/sign.key`), un root compromise la expone. Necesito que sea HSM o YubiKey. ¿El pipeline de build soporta esto? Si no, la firma essecurity theater.

2. **¿dm-verity está contemplado?** No lo veo en ARCHITECTURE.md. Sin dm-verity, un atacante puede modificar bloques del disco sin que ostree lo detecte (ostree verifica archivos, no bloques). ¿Es un omission o una decisión de diseño?

3. **¿Qué pasa si `registry.asc` está corrupto o no existe en boot?** El stage-1 falla → recovery. Pero ¿quién controla el recovery? Si el usuario puede modificar el recovery, es otro vector. ¿El recovery está en una partición protegida?

4. **¿Cómo se protege `magic.yaml` de manipulación?** Si un atacante modifica `/etc/magic/magic.yaml`, Grimoire aplica capas maliciosas. Necesito: firma + denylist de campos críticos (el usuario NO puede desactivar `integrity.verify_boot`). ¿Está contemplado?

5. **¿Hay límite de snapshots en `magic-apt`?** Si no, un root compromise puede crear 1000 snapshots y llenar el disco en minutos. ¿Cuál es el máximo? ¿Se limpia automáticamente?

6. **¿El pipeline de CI usa runners self-hosted?** GitHub Actions runners son superficie de ataque pública. ¿Quién controla el runner? ¿Está auditado? ¿Se usan Dependabot + lockfiles?

7. **¿`/var/log/magic/audit.log` tiene append-only protection?** Sin `chattr +a` o `fs-verity`, un root compromise puede truncar el log y borrar evidencia. ¿Está contemplado?

8. **¿El recovery mode de magic-init es modificable por el usuario?** Si el usuario puede editar los scripts de recovery, puede desactivar la verificación de integridad. ¿El recovery está en una partición read-only firmada?

9. **¿Qué pasa con la clave GPG de los repositorios Debian en `magic-apt`?** Si el keyring de apt está desactualizado o comprometido, `magic-apt` acepta paquetes maliciosos. ¿Se usa `apt-key` o la nueva configuración de `/etc/apt/keyrings/`? ¿Se valida pinning de Release files?

10. **¿Cómo se evita que un usuario instale un paquete que enmascare un binario del sistema?** overlayfs permite que una capa superior enmascare archivos de una capa inferior. Si un paquete `.deb` instala un `sudo` malicioso en la capa de sesión, ¿magic-apt lo detecta? ¿Hay verificación post-install?

11. **¿El init stage-1 verifica SOLO la capa base o TODAS las capas?** Si solo verifica la base, una capa de sistema o usuario comprometida pasa desapercibida. ¿La verificación es por-capas o global?

12. **¿Qué pasa si `grimoire apply` falla a mitad de la operación?** Si aplica 3 de 5 capas y falla, ¿el sistema queda en un estado mixto? ¿Hay transaccionalidad real o es best-effort? ¿El rollback cubre este caso?
