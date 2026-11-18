# Hito 2: esquema, carga desde CSV y los 4 reportes (S14 a S16)

**750006C Bases de Datos · Universidad del Valle · Grupo 9**

Integrantes: Eisin Yeiner Tobar Bravo · Giovanny Mora Segura

La explicación completa está en el [README principal](../../README.md), secciones 4 a 9.

## Documentos de esta carpeta

| Documento | Qué tiene |
|---|---|
| [`mapeo-y-criterios.md`](mapeo-y-criterios.md) | Mapeo CSV → esquema y los criterios por tipo de error de la carga (S14) |
| [`evidencias.md`](evidencias.md) | Salidas de `psql` de todas las ejecuciones: cargas, CSV propio, última línea de defensa, préstamos de prueba, los 4 reportes, la verificación de la parte B y el taller S16 |
| [`capturas/`](capturas/) | Capturas de pantalla de las ejecuciones (las que se muestran en el README, sección 9) |

## Scripts del Hito 2

Están en [`postgres/scripts/hito2/`](../../postgres/scripts/hito2/). Dentro de Docker, la ruta es `/scripts/hito2/…`.

| Script | Sesión | Qué hace |
|---|---|---|
| `carga-libros.sql` y `carga-lectores.sql` | S14 | Carga desde CSV con tabla de paso, validación y bitácora de rechazos |
| `pruebas-restricciones.sql` | S11 | Comprueba que el esquema rechaza los `INSERT` inválidos |
| `datos-prueba.sql` | S16 | Bibliotecaria y 30 préstamos que cubren los 8 casos de prueba |
| `reportes.sql` | S16 | Los 4 reportes, guardados como vistas |
| `verificacion-parte-b.sql` | S16 | Tabla de verificación de los 8 casos (9 de 9 coinciden) |
| `taller-S16/S16-tienda.sql` y `taller-S16/parte-a.sql` | S16 | Taller de consultas, Parte A (11 de 11) |

Los comandos, en orden, están en el [README, sección 2](../../README.md#2-cómo-levantar-el-proyecto-desde-cero).
