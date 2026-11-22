# Hito 3: normalización (S17 a S20)

**750006C Bases de Datos · Universidad del Valle · Grupo 9**

Integrantes: Eisin Yeiner Tobar Bravo · Giovanny Mora Segura

La explicación completa está en el [README principal](../../README.md), secciones 10 a 13.

**Entrega del Hito 3:** [`hito3-documento-normalizacion.md`](hito3-documento-normalizacion.md) (documento de normalización) y [`hito3-evidencias.md`](hito3-evidencias.md) (salidas de `psql`).

## Documentos de esta carpeta

| Documento | Qué tiene |
|---|---|
| [`hito3-documento-normalizacion.md`](hito3-documento-normalizacion.md) | **Entrega del Hito 3**: esquema antes, dependencias con su regla, formas normales y evidencia, cambios y migración, desnormalizaciones y esquema después |
| [`hito3-evidencias.md`](hito3-evidencias.md) | Salidas de `psql` del grupo: la migración, el `init/` en una base vacía y los reportes del S16 sobre el esquema nuevo |
| [`S18-taller-normalizacion.md`](S18-taller-normalizacion.md) | Taller S18: diagnóstico de 6 relaciones (A1), El Pistón llevado a 3FN (A2), la descomposición en PostgreSQL (B) y 3FN frente a FNBC (C) |
| [`S19-taller-esquemas.md`](S19-taller-esquemas.md) | Taller S19: los 4 esquemas mal diseñados (Parte A) y **la tabla del esquema `biblioteca`** (Parte B), que es el punto de partida del documento de normalización del Hito 3 |
| [`S19-salida-psql.txt`](S19-salida-psql.txt) | Salida de `psql` del taller S19, corrida en el Docker del grupo |
| [`S20-taller-desnormalizacion.md`](S20-taller-desnormalizacion.md) | Taller S20, Parte A: tabla de mediciones (sin índices, con índices y desnormalizada) y las respuestas de A1 a A5 |

## Scripts del Hito 3

Están en [`postgres/scripts/hito3/`](../../postgres/scripts/hito3/). Dentro de Docker, la ruta es `/scripts/hito3/…`.

| Script | Sesión | Qué hace |
|---|---|---|
| `normalizacion.sql` | Hito 3 | Migra una base con datos al esquema del Hito 3 (el mismo que crea `postgres/init/`) |
| `parte-b-evidencia.sql` | S19 | Consultas de evidencia sobre el esquema `biblioteca`. Solo lee |
| `taller-S18/S18-automotriz.sql` | S18 | Script del profesor: la planilla plana del taller El Pistón |
| `taller-S18/normalizacion.sql` | S18 | La planilla llevada a 3FN, con `EXCEPT` y las tres anomalías |
| `taller-S19/S19-esquemas.sql` | S19 | Script del profesor: los cuatro esquemas mal diseñados |
| `taller-S19/casos.sql` | S19 | Los cuatro casos: diagnóstico, evidencia, migración y verificación |
| `taller-S20/S20-rendimiento.sql` | S20 | Script del profesor: la biblioteca grande para medir (esquema `rendimiento`) |
| `taller-S20/a1-catalogo.sql` a `a5-derivado-o-historico.sql` | S20 | Parte A: medir, indexar, desnormalizar, vista materializada y dato histórico |

Los comandos están en el [README, sección 2](../../README.md#2-cómo-levantar-el-proyecto-desde-cero), paso 5.
