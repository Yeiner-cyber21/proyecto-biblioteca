# Hito 3: normalización (S17 a S20)

**750006C Bases de Datos · Universidad del Valle · Grupo 9**

Integrantes: Eisin Yeiner Tobar Bravo · Giovanny Mora Segura

La explicación completa está en el [README principal](../../README.md), secciones 10 y 11.

## Documentos de esta carpeta

| Documento | Qué tiene |
|---|---|
| [`S18-taller-normalizacion.md`](S18-taller-normalizacion.md) | Taller S18: diagnóstico de 6 relaciones (A1), El Pistón llevado a 3FN (A2), la descomposición en PostgreSQL (B) y 3FN frente a FNBC (C) |
| [`S19-taller-esquemas.md`](S19-taller-esquemas.md) | Taller S19: los 4 esquemas mal diseñados (Parte A) y **la tabla del esquema `biblioteca`** (Parte B), que es el punto de partida del documento de normalización del Hito 3 |
| [`S19-salida-psql.txt`](S19-salida-psql.txt) | Salida de `psql` del taller S19, corrida en el Docker del grupo |

## Scripts del Hito 3

Están en [`postgres/scripts/hito3/`](../../postgres/scripts/hito3/). Dentro de Docker, la ruta es `/scripts/hito3/…`.

| Script | Sesión | Qué hace |
|---|---|---|
| `parte-b-evidencia.sql` | S19 | Consultas de evidencia sobre el esquema `biblioteca`. Solo lee |
| `taller-S18/S18-automotriz.sql` | S18 | Script del profesor: la planilla plana del taller El Pistón |
| `taller-S18/normalizacion.sql` | S18 | La planilla llevada a 3FN, con `EXCEPT` y las tres anomalías |
| `taller-S19/S19-esquemas.sql` | S19 | Script del profesor: los cuatro esquemas mal diseñados |
| `taller-S19/casos.sql` | S19 | Los cuatro casos: diagnóstico, evidencia, migración y verificación |

Los comandos están en el [README, sección 2](../../README.md#2-cómo-levantar-el-proyecto-desde-cero), paso 5.
