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
