# ACTION_PLAN — MagicLinux

**Fecha:** 2026-06-27
**Estado:** Consolidado post-mesa (Rick arquitectura + ZeroCool threat/hardening + Ultron consistencia)

---

## 1. Visión y Pitch

MagicLinux es la primera distribución Linux que resuelve la tensión histórica entre inmutabilidad y flexibilidad, entre declaratividad y compatibilidad, entre seguridad y usabilidad.

**Diferenciación clave:**
- Sistema inmutable por capas (ostree + overlayfs) compatible con paquetes `.deb`
- Grimoire: orquestador declarativo YAML-based con firma obligatoria y schema validation
- Magic-apt: gestor atómico con rollback vía Btrfs snapshots
- Seguridad por arquitectura: dm-verity + TPM binding + Secure Boot + audit log inmutable
- Reproducible builds con SLSA Level 3 attestation

---

## 2. Arquitectura Final (8 conflictos resueltos)

| # | Conflicto (Ultron) | Resolución | Documento |
|---|-------------------|------------|-----------|
| 1 | **dm-verity ausente** | Agregado como mandatory en stage-1 de `magic-init`. Verificación a nivel de bloque antes de montar rootfs. | `ARCHITECTURE.md:79` |
| 2 | **Clave de firma en disco** | Clave privada NUNCA en disco. Firma vía HSM (YubiKey/Nitrokey) o cosign con identidad OIDC (Sigstore). Solo `verify.pub` en `keys/`. | `ARCHITECTURE.md:113`, `BUILD.md:56-57` |
| 3 | **CI/CD público (GitHub runners)** | Cambiado a `runs-on: [self-hosted, linux, x64]`. Runners aislados con Secure Boot + TPM + disco encriptado. SLSA Level 3 requerido. | `BUILD.md:79` |
| 4 | **`/var` y `/etc` zona libre** | Grimoire como source of truth + verificación en boot de archivos protegidos contra manifest firmado. AppArmor profiles deniegan escritura directa. | `ARCHITECTURE.md:25-34`, `ARCHITECTURE.md:80-83` |
| 5 | **`magic.yaml` sin firma ni schema** | JSON Schema validation en cada apply. Firma obligatoria. Campos críticos inmutables. Denylist de campos ejecutables. SRI para fuentes remotas. | `ARCHITECTURE.md:66-72` |
| 6 | **Rollback sin protección** | Rate limiting (3/hora), versiones deprecated con flag `--force-deprecated`, pre-snapshot de seguridad, rollback no afecta audit log. | `ARCHITECTURE.md:100-105` |
| 7 | **`registry.asc` en `/boot`** | Vinculado a TPM PCR measurements. Si el archivo se reemplaza, los PCRs no matchean y el boot se niega. | `ARCHITECTURE.md:79` |
| 8 | **Overlay toxicity (binarios enmascarados)** | POST-mount overlay verification en stage-2: verificación de hashes de binarios críticos contra `registry.asc`. Allowlist de capas. | `ARCHITECTURE.md:80-83` |

---

## 3. Estado de los 11 Vectores (V-01 a V-11)

| ID | Vector | Impacto | Feasibility | Estado Anterior | Estado Actual | Mitigación |
|----|--------|---------|-------------|-----------------|---------------|------------|
| V-01 | Bootkit (registry.asc) | CRÍTICO | MEDIA | **ABIERTO** | **MITIGADO** | TPM PCR binding + dm-verity + recovery sin modificación |
| V-02 | Evil Maid (Secure Boot) | CRÍTICO | BAJA-MEDIA | **ABIERTO** | **MITIGADO** | Secure Boot mandatory + stage-0 verificación |
| V-03 | Supply Chain (magic-apt) | ALTO | MEDIA | **ABIERTO** | **MITIGADO** | HSM/cosign + reproducible builds + sandbox apt |
| V-04 | Overlay Toxicity | ALTO | MEDIA | **ABIERTO** | **MITIGADO** | POST-mount hash verification + allowlist de capas |
| V-05 | Persistencia en /var, /etc | ALTO | ALTA | **ABIERTO** | **MITIGADO** | Grimoire source of truth + boot verification + AppArmor |
| V-06 | Weaponización de Rollback | MEDIO-ALTO | BAJA | **ABIERTO** | **MITIGADO** | Rate limit + deprecated flag + pre-snapshot |
| V-07 | YAML Injection (Grimoire) | CRÍTICO | MEDIA | **ABIERTO** | **MITIGADO** | Schema validation + firma + denylist + SRI |
| V-08 | Bubblewrap Escape | MEDIO | BAJA | **MITIGADO parcialmente** | **MITIGADO** | Seccomp-bpf + AppArmor profile + kernel hardening |
| V-09 | DoS por Snapshots | MEDIO | ALTA | **ABIERTO** | **MITIGADO** | Límite 10 snapshots + cleanup automático + alertas |
| V-10 | Compromiso CI/CD | CRÍTICO | BAJA | **ABIERTO** | **MITIGADO** | Self-hosted runners + HSM + SLSA L3 + reproducible builds |
| V-11 | Audit Log Tampering | MEDIO | ALTA | **ABIERTO** | **MITIGADO** | `chattr +a` + log shipping en tiempo real + TPM integrity |

**8 vectores pasaron de ABIERTO a MITIGADO.** V-08 subió de parcial a completo. Quedan 0 vectores críticos abiertos.

---

## 4. Hoja de Ruta

### Fase 1: Prototype (Semanas 1-4)
**Objetivo:** ISO booteable con arquitectura base funcionando.

| Tarea | Dependencia | Responsable |
|-------|-------------|-------------|
| P1.1 | mmdebstrap + mkosi: generar rootfs Debian minimizado | — | Build |
| P1.2 | ostree commit de la capa base | P1.1 | Build |
| P1.3 | magic-init stage-1 básico (verificación de hashes) | P1.2 | Core |
| P1.4 | magic-apt MVP (apt wrapper + capa ostree) | P1.2 | Core |
| P1.5 | Grimoire MVP (parseo YAML + apply de capas) | P1.2 | Core |
| P1.6 | ISO híbrida booteable | P1.1-P1.5 | Build |

**Entregable:** ISO funcional en QEMU/VirtualBox. magic.yaml declarativo aplica paquetes.

### Fase 2: Hardening (Semanas 5-8)
**Objetivo:** Cerrar los 11 vectores del threat model.

| Tarea | Dependencia | Responsable |
|-------|-------------|-------------|
| P2.1 | dm-verity: hash tree generation + integración en stage-1 | P1.3 | Core |
| P2.2 | TPM PCR binding para registry.asc | P1.3 | Core |
| P2.3 | POST-mount overlay verification + allowlist | P1.5 | Core |
| P2.4 | AppArmor profiles para magic-init, magic-apt, grimoire | P1.3-P1.5 | Hardening |
| P2.5 | Kernel hardening (sysctl + blacklist + cmdline) | P1.3 | Hardening |
| P2.6 | Bubblewrap sandbox + seccomp-bpf | P1.5 | Hardening |
| P2.7 | Audit log inmutable (chattr +a) + log shipping | P1.2 | Hardening |
| P2.8 | Secure Boot enforcement en ISO y runtime | P1.6 | Core |
| P2.9 | Rollback protections: rate limit + deprecated + pre-snapshot | P1.4 | Core |
| P2.10 | Grimoire schema validation + firma + denylist | P1.5 | Core |

**Entregable:** Todas las defensas activas. ISO verificable con dm-verity + TPM.

### Fase 3: CI/CD Pipeline (Semanas 9-10)
**Objetivo:** Pipeline de build seguro, reproducible y auditable.

| Tarea | Dependencia | Responsable |
|-------|-------------|-------------|
| P3.1 | Self-hosted runner setup (HW aislado + TPM + Secure Boot) | — | Infra |
| P3.2 | Integración cosign/Sigstore con identidad OIDC | — | Build |
| P3.3 | Reproducible build attestation (SLSA L3) | P1.1-P1.6 | Build |
| P3.4 | Pipeline CI/CD completo con verificación en cada stage | P3.1-P3.3 | Build |
| P3.5 | Firma de ISO con HSM remoto vía cosign | P3.2 | Build |
| P3.6 | Transparency log (Rekor) para todas las firmas | P3.2 | Build |

**Entregable:** CI/CD pipeline con SLSA Level 3 attestation. Cualquier persona puede reproducir el build.

### Fase 4: Beta (Semanas 11-12)
**Objetivo:** ISO lista para pruebas externas.

| Tarea | Dependencia | Responsable |
|-------|-------------|-------------|
| P4.1 | Secure Boot enforcement en instalador | P2.8 + P1.6 | Core |
| P4.2 | magic-apt con pinning de repositorios + hash verification | P1.4 | Core |
| P4.3 | MagicLinux ISO híbrida final con todas las defensas | P1-P3 | Build |
| P4.4 | Documentación de instalación y hardening | P4.3 | Docs |
| P4.5 | Release pública + transparency log + diffs reproducibles | P4.3 | Build |

**Entregable:** ISO híbrida lista para beta testers con todas las capas de seguridad activas.

---

## 5. Dependencias entre Tareas

```
Fase 1 (Prototype)
├── P1.1 (mmdebstrap + mkosi)
│   └── P1.2 (ostree commit)
│       ├── P1.3 (magic-init stage-1)
│       │   ├── P2.1 (dm-verity)
│       │   ├── P2.2 (TPM binding)
│       │   └── P2.9 (rollback protections)
│       ├── P1.4 (magic-apt)
│       │   └── P2.9 (rollback protections)
│       └── P1.5 (Grimoire)
│           ├── P2.3 (POST-mount verification)
│           ├── P2.10 (schema + firma)
│           └── P2.6 (bubblewrap)
├── P1.5 (Grimoire) ─── P2.3 (POST-mount) ─── P2.10 (schema)
└── P1.6 (ISO) ─── P2.8 (Secure Boot) ─── P4.1 (enforcement)

Fase 2 (Hardening)
├── P2.4 (AppArmor) → P2.7 (audit log)
├── P2.5 (kernel hardening)
└── P2.7 (audit log)

Fase 3 (CI/CD)
├── P3.1 (self-hosted runners)
├── P3.2 (cosign/Sigstore) ─── P3.5 (HSM firmado) ─── P3.6 (Rekor)
├── P3.3 (SLSA attestation) ─── P3.4 (pipeline completo)
└── P3.4 ─── P4.5 (release pública)

Fase 4 (Beta)
├── P4.1 (Secure Boot enforcement)
├── P4.2 (apt pinning)
├── P4.3 (ISO final)
├── P4.4 (documentación)
└── P4.5 (release)
```

---

## Resumen de Archivos Tocados

| Archivo | Cambio |
|---------|--------|
| `README.md` | Nueva sección "Security by Architecture" con tabla de principios defensivos |
| `ARCHITECTURE.md` | dm-verity en stage-1, TPM binding, POST-mount verification, /etc+/var defensas, schema validation, firma de magic.yaml, protecciones de rollback, HSM para claves |
| `BUILD.md` | Self-hosted runners, HSM/cosign en lugar de keys/sign.key, reproducible build attestation SLSA L3 |
| `ACTION_PLAN.md` | **NUEVO** — documento consolidado con visión, conflictos resueltos, estado de vectores, hoja de ruta y dependencias |
