# Sistema de gestión de biblioteca: proyecto integrador

**750006C Bases de Datos · Universidad del Valle**

| | |
|---|---|
| **Grupo** | 9 |
| **Integrantes** | Eisin Yeiner Tobar Bravo · Jeovany |
| **Entrega actual** | Hito 2: esquema en PostgreSQL, carga masiva desde CSV (S14), los 4 reportes y el taller de consultas (S15/S16) |
| **Motor** | PostgreSQL 16 sobre el entorno Docker del curso (probado en Windows con PowerShell 5.1) |

Este README es la **bitácora del proyecto**. Explica qué se hizo, dónde está cada archivo, cómo levantar todo desde cero y qué decisiones se tomaron.

## Contenido

1. [Estructura del repositorio](#1-estructura-del-repositorio)
2. [Cómo levantar el proyecto desde cero](#2-cómo-levantar-el-proyecto-desde-cero)
3. [Bitácora](#3-bitácora)
4. [El esquema `biblioteca`](#4-el-esquema-biblioteca)
5. [La carga desde CSV](#5-la-carga-desde-csv)
6. [CSV propio del grupo](#6-csv-propio-del-grupo)
7. [Prueba de la última línea de defensa](#7-prueba-de-la-última-línea-de-defensa)
8. [Los 4 reportes](#8-los-4-reportes)
9. [Evidencias](#9-evidencias)
10. [Lecciones aprendidas](#10-lecciones-aprendidas)
11. [Taller S18: formas normales](#11-taller-s18-formas-normales)

---

## 1. Estructura del repositorio

La estructura parte del entorno Docker entregado por el profesor (`entorno-docker`), sin cambios en `docker-compose.yml`.

```
proyecto-biblioteca/
├── README.md                        ← esta bitácora
├── docker-compose.yml               ← entorno del curso: PostgreSQL 16 + pgAdmin + Node.js
├── postgres/
│   ├── init/                        ← se ejecuta SOLO, una vez, cuando la base está vacía
│   │   ├── 01_esquema.sql           ← esquema "biblioteca" (biblioteca-v2 del taller S11)
│   │   └── 02_carga.sql             ← esquema "carga": bitácora de rechazos y tablas de paso
│   ├── scripts/                     ← se ejecutan a mano (dentro del contenedor: /scripts)
│   │   ├── carga-libros.sql
│   │   ├── carga-lectores.sql
│   │   ├── pruebas-restricciones.sql
│   │   ├── datos-prueba.sql         ← S16 parte B: bibliotecaria y 30 préstamos que cubren los 8 casos
│   │   ├── reportes.sql             ← S16 parte B: los 4 reportes (guardados como vistas)
│   │   ├── verificacion-parte-b.sql ← S16 parte B: tabla de verificación de los 8 casos
│   │   ├── S16-tienda.sql           ← taller S16: esquema de práctica "tienda" (script del profesor)
│   │   ├── parte-a.sql              ← taller S16, Parte A: los 11 ejercicios resueltos por el grupo
│   │   ├── S18-automotriz.sql       ← taller S18: planilla plana del taller "El Pistón" (script del profesor)
│   │   ├── normalizacion.sql        ← taller S18, Parte B: la planilla llevada a 3FN, con verificación
│   │   └── datos/                   ← 4 CSV semilla del curso + CSV propio del grupo
│   └── data/                        ← datos internos de PostgreSQL (no se suben a GitHub)
├── pgadmin/servers.json             ← conexión a PostgreSQL precargada en pgAdmin
├── node/                            ← API REST (Hito 5)
├── docs/
│   ├── mapeo-y-criterios.md         ← mapeo CSV → esquema y criterios por tipo de error
│   ├── evidencias.md                ← salidas de psql de todas las ejecuciones
│   ├── README-entorno-docker.md     ← README original del entorno del profesor
│   ├── S18-taller-normalizacion.md  ← taller S18: partes A1, A2 y C (formas normales)
│   └── pendientes.md                ← lo que falta (S15, S16 y los siguientes hitos)
└── assets/                          ← capturas de las ejecuciones
```

## 2. Cómo levantar el proyecto desde cero

**Requisitos:** Docker Desktop abierto (con "Engine running") y una terminal. Los comandos están escritos para **PowerShell de Windows** y se ejecutan **desde la carpeta del proyecto**, la que contiene `docker-compose.yml`.

**1. Levantar PostgreSQL y pgAdmin.** Con la base vacía, `init/` crea los dos esquemas automáticamente.
```powershell
docker compose up -d postgres pgadmin
docker compose logs postgres | Select-String "running|COMMIT|ERROR|init process complete"
```
En el log deben aparecer `01_esquema.sql` y `02_carga.sql`, cada uno seguido de `COMMIT`.

**2. Cargar los datos, en este orden** (primero los archivos limpios, después los que tienen errores):
```powershell
docker compose exec postgres psql -U curso -d curso -f /scripts/carga-libros.sql
docker compose exec postgres psql -U curso -d curso -v archivo=/scripts/datos/libros_semilla_con_errores.csv -f /scripts/carga-libros.sql
docker compose exec postgres psql -U curso -d curso -f /scripts/carga-lectores.sql
docker compose exec postgres psql -U curso -d curso -v archivo=/scripts/datos/lectores_semilla_con_errores.csv -f /scripts/carga-lectores.sql
docker compose exec postgres psql -U curso -d curso -v archivo=/scripts/datos/libros_propios.csv -f /scripts/carga-libros.sql
```

**3. Crear los préstamos de prueba, correr los 4 reportes y verificarlos.** Deben ejecutarse **el mismo día y seguidos**, porque las fechas de los préstamos son relativas a la fecha en que se crean. El contenedor usa la hora UTC: a las 7 p. m. de Colombia ya es el día siguiente para PostgreSQL.
```powershell
docker compose exec postgres psql -U curso -d curso -f /scripts/datos-prueba.sql
docker compose exec postgres psql -U curso -d curso -f /scripts/reportes.sql
docker compose exec postgres psql -U curso -d curso -f /scripts/verificacion-parte-b.sql
```
La verificación debe mostrar `sí` en las 9 filas.

**4. Taller S16, Parte A** (esquema de práctica `tienda`, independiente de `biblioteca`):
```powershell
docker compose exec postgres psql -U curso -d curso -f /scripts/S16-tienda.sql
docker compose exec postgres psql -U curso -d curso -f /scripts/parte-a.sql
```

**5. Revisar en pgAdmin:** abrir `http://localhost:5050`, entrar al servidor "Curso - PostgreSQL" (contraseña `curso`) e ir a *Databases → curso → Schemas*.

**Reiniciar la base desde cero.** Hace falta cada vez que se cambia `01_esquema.sql` o `02_carga.sql`, porque `init/` solo corre con la base vacía. **Borra todos los datos.**
```powershell
docker compose down
Remove-Item -Recurse -Force .\postgres\data\pgdata
docker compose up -d postgres pgadmin
```
En Linux o Mac, el segundo comando es `rm -rf postgres/data/pgdata`.

## 3. Bitácora

| Fecha | Qué se hizo |
|---|---|
| 31/10/2026 | Se reconstruyó el esquema `biblioteca-v2` (taller S11) con las reglas de traducción E-R → relacional y se dejó como `postgres/init/01_esquema.sql`. Se instaló el entorno Docker del curso en Windows. Se verificó que las 9 tablas se crean solas y que el esquema rechaza los `INSERT` inválidos (`pruebas-restricciones.sql`). |
| 02/11/2026 | Se documentaron el mapeo CSV → esquema y los criterios por tipo de error (`docs/mapeo-y-criterios.md`): 6 principios, los 14 errores del curso y 18 casos propios. Se detectó una discrepancia en los datos del curso (fila `…034`). |
| 03/11/2026 | Se creó el esquema `carga` (`02_carga.sql`) y el script `carga-libros.sql`. Pruebas: limpio (32 cargadas), con errores (8 rechazadas) y limpio otra vez (0 cargadas): **repetir la carga no duplica**. |
| 04/11/2026 | Se creó `carga-lectores.sql`: cada lector se reparte en `usuario` + `lector`, con contraseña inicial cifrada con bcrypt. Pruebas: 20 cargadas, 6 rechazadas y 0 al repetir. Con esto, **los 14 errores del curso quedan atrapados**. |
| 08/11/2026 | Taller de consultas de S16 (en curso): se agregó el script del profesor `S16-tienda.sql` (esquema de práctica `tienda`, separado de `biblioteca`) y `parte-a.sql`, con los 11 ejercicios de la Parte A resueltos. Cada ejercicio anota cuántas filas debe devolver, y las 11 coinciden. |
| 09/11/2026 | Prueba completa desde una base vacía (`init/` crea los dos esquemas solo), carga del CSV propio (5 cargadas, 4 rechazadas), prueba de la última línea de defensa y publicación del repositorio en GitHub. |
| 10/11/2026 | S15/S16: se creó `datos-prestamos.sql` (una bibliotecaria y 30 préstamos, cada uno pensado para un caso de los reportes) y `reportes.sql` con los 4 reportes. Antes de escribir cada consulta se calculó a mano el resultado esperado, y los 4 reportes coincidieron. Las salidas de todas las ejecuciones quedaron en `docs/evidencias.md`. |
| 10/11/2026 | **Cierre del taller S16 (Hito 2).** Se comparó el repositorio con la guía de S16, punto por punto. Cambios: `datos-prestamos.sql` pasó a llamarse `datos-prueba.sql` (el nombre que pide la guía), con el resultado esperado de cada reporte y de los 8 casos escrito en el encabezado; cada reporte de `reportes.sql` lleva su resultado esperado y queda guardado como vista; nuevo `verificacion-parte-b.sql`, que arma la tabla de verificación desde esas vistas. Al revisar los casos se encontró que el caso 6 (préstamo que vence hoy) no se notaba en el reporte 3, porque Juan David ya era moroso por otros préstamos. Ese préstamo pasó a Isabella, que no tiene otro abierto, y los 4 reportes siguieron dando lo mismo. Prueba de control: con `<=` en vez de `<`, la verificación marca el caso 6 como `NO`. En `parte-a.sql` se agregó la respuesta a la pregunta del ejercicio 5. |
| 10/11/2026 | **Corrida final de S16 en el Docker del grupo**, en el orden de la guía: `datos-prueba.sql` (`30 \| 20 \| 10 \| 5`), `reportes.sql` (21, 2, 4 y 5 filas, con las 4 vistas), `verificacion-parte-b.sql` (**9 de 9 coinciden**) y la Parte A (**11 de 11**). Las salidas reales quedaron en `docs/evidencias.md` (secciones 9 a 12) y las capturas, en `assets/paso8-*.png`. |
| 11/11/2026 | **Taller S18 (formas normales).** Se agregó el script del profesor `S18-automotriz.sql` y se resolvió el taller: A2 (1FN → 2FN → 3FN, con el esquema final en FNBC), la Parte B en `normalizacion.sql` y la Parte C (3FN frente a FNBC), en `docs/S18-taller-normalizacion.md`. La Parte B encontró una contradicción en la planilla (dos teléfonos para Jorge Mejía), la corrigió y reconstruyó la planilla exacta con `EXCEPT` (0 filas en los dos sentidos). Todo se probó en PostgreSQL 16. |

## 4. El esquema `biblioteca`

Archivo: [`postgres/init/01_esquema.sql`](postgres/init/01_esquema.sql). Tiene 9 tablas.

| Tabla | Qué guarda | Claves y restricciones principales |
|---|---|---|
| `usuario` | Datos comunes y login de los 4 perfiles | PK `id_usuario`; `documento` y `correo` con `UNIQUE`; `CHECK` de formato; `perfil IN (…)`; hash bcrypt obligatorio |
| `lector` | Perfil lector (teléfono) | PK = FK → `usuario` |
| `bibliotecario` | Perfil bibliotecario (quien registra los préstamos) | PK = FK → `usuario` |
| `categoria` | Categorías del catálogo | `nombre` con `UNIQUE` |
| `autor` | Autores | `nombre` con `UNIQUE` |
| `libro` | Títulos del catálogo | PK `isbn` (13 dígitos); FK → `categoria`; año entre 1450 y 2100 |
| `libro_autor` | Relación N:M libro–autor | PK compuesta `(isbn, id_autor)` |
| `ejemplar` | Copias físicas (entidad débil de `libro`) | PK compuesta `(isbn, numero_copia)` |
| `prestamo` | Préstamos y devoluciones | FK a `lector` y a `bibliotecario`; FK compuesta → `ejemplar`; `CHECK` de fechas |

**Decisiones de diseño**

- **Perfiles:** una tabla general `usuario` (con el login y la columna `perfil`) más una tabla por perfil, **solo** para los que tienen datos propios o a los que apunta una FK (`lector`, `bibliotecario`). Así `prestamo` apunta exactamente a un lector y a un bibliotecario, no a cualquier usuario. Administrador y auditor viven solo en `usuario`.
- **Ejemplares como entidad débil:** cada copia física es una fila, para poder prestar copias concretas. "Ejemplares disponibles" y "en mora" **no se guardan**: son atributos derivados que se calculan en las consultas.
- **Contraseñas:** el `CHECK ck_usuario_hash_bcrypt` solo admite valores con forma de hash bcrypt (`$2a$`/`$2b$`, 60 caracteres). La base **no puede** guardar una contraseña en texto plano.
- **Correo en minúsculas:** `CHECK (correo = lower(correo))`, para que el `UNIQUE` no deje pasar `Ana@X.co` y `ana@x.co` como si fueran distintos.
- **Un ejemplar no puede estar prestado dos veces a la vez:** se garantiza con un índice único **parcial** sobre los préstamos abiertos (`WHERE fecha_devolucion IS NULL`).

**Pruebas de restricciones** ([`pruebas-restricciones.sql`](postgres/scripts/pruebas-restricciones.sql)). Cada `INSERT` inválido es rechazado por la regla esperada, y el script termina en `ROLLBACK`, así que no deja datos:

| Prueba | Regla de negocio | Restricción que la rechaza |
|---|---|---|
| 1 | Un préstamo solo se le hace a un lector registrado | `prestamo_id_lector_fkey` |
| 2 | La devolución no puede ser anterior al préstamo | `ck_prestamo_devolucion` |
| 3 | Un ejemplar no puede estar prestado dos veces a la vez | `ux_prestamo_ejemplar_abierto` |
| Extra | Las contraseñas no se guardan en texto plano | `ck_usuario_hash_bcrypt` |

**Reglas que el esquema NO garantiza** (candidatas a trigger en el Hito 4):

- Todo libro tiene al menos un autor (participación total en una relación N:M). Hoy lo exige la carga.
- Un lector tiene máximo 3 préstamos activos.
- Un lector en mora no puede pedir préstamos.
- Una fila de `lector` debe corresponder a un usuario con `perfil = 'lector'` (lo mismo para `bibliotecario`).
- Solo se prestan ejemplares en estado `activo` a usuarios activos.
- El año de publicación no puede ser posterior al año actual. El `CHECK` usa 2100 fijo; el año actual lo valida la carga.

## 5. La carga desde CSV

**Por qué no un `COPY` directo:** un `COPY` a la tabla final es **todo o nada**. Al primer error se deshace todo el archivo, solo se ve ese primer error y el mensaje es del motor, no del negocio. Por eso se usa el patrón de la tabla de paso:

```
archivo .csv ──COPY──► carga.stg_linea ──partir y normalizar──► carga.stg_libro / stg_lector
                                                                   │  UPDATE … SET motivo = CASE …
                                         motivo IS NULL ◄──────────┴──────────► motivo IS NOT NULL
                                               ▼                                       ▼
                         biblioteca.(categoria, autor, libro,              carga.rechazo_carga
                          libro_autor, ejemplar, usuario, lector)              (bitácora)
```

Las seis etapas de cada script, todas dentro de una transacción (`BEGIN … COMMIT`):

1. **Extraer:** `COPY … FORMAT text` lee cada línea entera en una sola columna, así que ninguna línea rara detiene la lectura.
2. **Transformar:** `split_part` parte la línea en campos y se aplican las correcciones mecánicas (espacios, guiones del ISBN, `initcap` de la categoría, `lower` del correo, puntos del documento, separadores del teléfono).
3. **Validar:** un `UPDATE … SET motivo = CASE …` donde **la primera regla que falla da el motivo**. Cada regla es el espejo de una restricción del esquema.
4. **Duplicados dentro del mismo archivo:** se conserva la primera aparición válida y se rechazan las demás.
5. **Cargar** las filas válidas en las tablas finales, en el orden que exigen las FK. Un CSV de libros se reparte en **5 tablas**; uno de lectores, en **2** (con contraseña inicial bcrypt).
6. **Registrar** las rechazadas en `carga.rechazo_carga`, con archivo, línea, contenido original y motivo.

**Criterios:** [`docs/mapeo-y-criterios.md`](docs/mapeo-y-criterios.md). Resumen: la carga masiva **solo da de alta** (nunca actualiza), solo corrige lo mecánico y rechaza todo lo demás con un motivo legible.

**Resultados, desde una base vacía y en el orden de la sección 2:**

| # | Archivo | Cargadas | Rechazadas |
|---|---|---|---|
| 1 | `libros_semilla.csv` | 32 | 0 |
| 2 | `libros_semilla_con_errores.csv` | 0 | 8 |
| 3 | `lectores_semilla.csv` | 20 | 0 |
| 4 | `lectores_semilla_con_errores.csv` | 0 | 6 |

Estado final: **32 libros, 94 ejemplares, 29 autores, 9 categorías, 20 usuarios lectores y 14 rechazos**. Son los 14 errores del curso, ni uno más ni uno menos:

| Archivo · línea | Motivo registrado |
|---|---|
| libros · 2 | `isbn ya existe en el catálogo` |
| libros · 3 | `título vacío` |
| libros · 4 | `año no numérico` (ver nota) |
| libros · 5 | `año no numérico` |
| libros · 6 | `tiene 7 columnas, se esperaban 6` |
| libros · 7 | `autor vacío` |
| libros · 8 | `isbn vacío` |
| libros · 9 | `ejemplares negativo` |
| lectores · 2 | `documento ya registrado (perfil lector)` |
| lectores · 3 | `correo vacío` |
| lectores · 4 | `correo mal formado` |
| lectores · 5 | `teléfono no numérico o de longitud inválida (7-15 dígitos)` |
| lectores · 6 | `documento vacío` |
| lectores · 7 | `nombres vacíos` |

> **Nota (fila `9780000000034`):** el README de los datos semilla dice que esa fila prueba "ejemplares no numérico", pero en el archivo el texto `dos` está en la columna del **año**. Por eso el motivo correcto es `año no numérico`. La regla `ejemplares no numérico` se comprueba con el CSV propio (sección 6).

**¿Qué pasa si se vuelve a correr la carga limpia?** (la pregunta del profesor en clase). Las 32 filas salen rechazadas con `isbn ya existe en el catálogo`, y los totales no cambian. Con lectores ocurre lo mismo: 20 rechazadas por `documento ya registrado`. **La carga se puede repetir sin duplicar nada.**

## 6. CSV propio del grupo

Archivo: [`postgres/scripts/datos/libros_propios.csv`](postgres/scripts/datos/libros_propios.csv). Tiene 5 libros válidos que no están en la semilla, 3 errores que no aparecen en los archivos del curso y una fila extra.

| Línea | Fila | Resultado | Qué prueba |
|---|---|---|---|
| 2 | *La vorágine* | Cargada | Fila normal; primera aparición del ISBN que se repite en la línea 7 |
| 3 | *María* | Cargada | Corrección: el ISBN `978-0-00-000004-0` se guarda como `9780000000040`, y `novela` como `Novela` |
| 4 | *El coronel no tiene quien le escriba* | Cargada | Corrección: espacios sobrantes; el autor ya existía y no se duplica |
| 5 | *Delirio* | Cargada | Fila normal |
| 6 | *El olvido que seremos* | Cargada | Categoría nueva (`Biografía`), creada automáticamente |
| 7 | ISBN de la línea 2, repetido | Rechazada: **error nuevo** | `isbn repetido en el archivo (primera aparición: línea 2)` |
| 8 | Año 2031 | Rechazada: **error nuevo** | `año en el futuro (posterior a 2026)` |
| 9 | 1000 ejemplares | Rechazada: **error nuevo** | `ejemplares supera el máximo por carga (100)` |
| 10 | Ejemplares `tres` | Rechazada: caso extra | `ejemplares no numérico`: prueba la regla que no activaron los datos del curso |

Resultado: **5 cargadas, 4 rechazadas**. El catálogo queda en 37 libros, 104 ejemplares, 33 autores y 10 categorías.

## 7. Prueba de la última línea de defensa

**Qué se hizo:** se comentó a propósito (`--`) la regla `título vacío` del `CASE` en `carga-libros.sql`, se volvió a cargar `libros_semilla_con_errores.csv`, se observó el resultado y se restauró la regla.

**Resultado:**
```
psql:/scripts/carga-libros.sql:142: ERROR:  new row for relation "libro" violates check constraint "ck_libro_titulo"
DETAIL:  Failing row contains (9780000000033, , 1963, 7, t).
```
Libros y rechazos **antes**: 37 y 27. **Después**: 37 y 27.

**¿Qué pasa con las demás filas de esa carga?**
Ninguna se guarda. La fila sin título pasó la validación, llegó al `INSERT` y chocó con el `CHECK ck_libro_titulo`. Como toda la carga corre en una transacción y `ON_ERROR_STOP` detuvo el script, la transacción se deshizo completa, incluidas las categorías y los autores que esa corrida alcanzó a procesar. Si el archivo trajera 10 000 filas válidas y esta mala, no entraría ninguna: es el mismo "todo o nada" del `COPY` directo que el patrón de la tabla de paso quiere evitar.

**¿Y con la bitácora?**
Queda igual (27 antes y 27 después). Los 7 rechazos legítimos de esa corrida **tampoco** se registraron, porque el `INSERT` en `carga.rechazo_carga` estaba dentro de la misma transacción y nunca llegó a ejecutarse. La única huella es un mensaje del **motor** (`violates check constraint`), no del negocio, y solo informa el **primer** error.

**Conclusión:** el esquema cumplió su papel, porque ningún libro sin título entró a la base, pero lo hizo a costa de perder la carga entera. Por eso la validación debe atrapar el error antes: **si una fila llega a chocar con un `CHECK`, la validación ya falló.**

**Por qué no se comentó la regla de ejemplares negativos (la que sugiere la guía):** se probó, y en nuestro esquema los ejemplares son filas de la tabla `ejemplar`. `generate_series(1, -3)` produce cero filas y no hay ningún `CHECK` que detenga la fila, así que el libro entra **en silencio** con 0 copias. Esto muestra que **donde el esquema no tiene restricción, la validación es la única defensa**.

## 8. Los 4 reportes

Archivo: [`postgres/scripts/reportes.sql`](postgres/scripts/reportes.sql). Son las consultas del Hito 2, adaptadas del `S15-reportes-demo.sql` del profesor a nuestro esquema. Cada reporte queda guardado como **vista** (`biblioteca.reporte_top_libros`, `reporte_mas_lectores`, `reporte_morosos` y `reporte_prestamos_mora`), como sugiere la guía de S16 para la API de M7.

### 8.1 Los datos de prueba

Sin préstamos, los reportes salen vacíos. [`datos-prueba.sql`](postgres/scripts/datos-prueba.sql) (hasta S15 se llamaba `datos-prestamos.sql`) crea:
- Una **bibliotecaria** (Andrea Castillo Ruiz), porque todo préstamo exige un `id_bibliotecario`. Su contraseña se guarda con bcrypt.
- **30 préstamos**: 20 devueltos, 10 abiertos y 5 en mora. Las fechas son relativas a `CURRENT_DATE`, con un plazo de 14 días.

Cada préstamo prueba un caso concreto: un empate en el primer lugar, un lector con 2 préstamos abiertos y ninguno devuelto, un préstamo devuelto tarde (estuvo en mora y ya no), uno que vence hoy, un lector con dos préstamos en mora, el mismo título prestado en 4 copias distintas, 16 libros y 12 lectores sin préstamos. La correspondencia con los 8 casos de la guía está en la [tabla de verificación](#846-tabla-de-verificación-de-la-parte-b).

Los datos respetan las reglas de negocio aunque el esquema todavía no las imponga: nadie tiene más de 3 préstamos abiertos, nadie recibió un préstamo estando en mora y ninguna copia se prestó dos veces al mismo tiempo. El script es re-ejecutable: borra sus propios datos y los vuelve a crear.

**Antes de escribir las consultas, se calculó a mano el resultado esperado de cada reporte.** Quedó escrito en el encabezado de `datos-prueba.sql` y encima de cada reporte en `reportes.sql`. Los 4 reportes coincidieron con lo esperado.

### 8.2 Las consultas

| # | Reporte | Qué hace | Técnica (S15) | Resultado |
|---|---|---|---|---|
| 1 | Los 20 libros más prestados | Cuenta los préstamos de cada **libro**, con todas sus copias sumadas, y toma los 20 primeros **con empates** | `LEFT JOIN` + `count(p.id_prestamo)` + `GROUP BY` + `FETCH FIRST 20 ROWS WITH TIES` | **21 filas**: Cien años de soledad (4), 1984 y Harry Potter (3), El principito y Rayuela (2), y 16 libros con 1, empatados en el puesto 20 |
| 2 | El o los lectores que más han leído | Cuenta los préstamos **devueltos** de cada lector y muestra a **todos** los que tienen el máximo | `WITH` (CTE) + `WHERE fecha_devolucion IS NOT NULL` + subconsulta escalar `= (SELECT max(…))` | **Mariana Gómez y Santiago Rodríguez, con 5** (empate) |
| 3 | Lectores morosos | Lectores con **al menos un** préstamo sin devolver y ya vencido. Una fila por lector | `EXISTS` con subconsulta correlacionada (∃ del cálculo relacional) | **4 lectores**: Sebastián, Valentina, Juan David y Andrés Felipe |
| 4 | Préstamos en mora (lista de notificación) | Cada préstamo vencido, con nombre, correo, teléfono, título, copia, fecha de vencimiento y **días de mora** | `JOIN` de `prestamo`, `lector`, `usuario` y `libro`; resta de fechas | **5 préstamos**: de 31 días (Sebastián) a 2 días (Andrés). Juan David aparece **dos veces** |

### 8.3 Decisiones documentadas

- **Reporte 1:**
  - Se agrupa por **libro** (ISBN), no por copia. Agrupado por copia, *Cien años de soledad* se partiría en 4 filas de 1 préstamo.
  - Cuentan todos los préstamos, abiertos y devueltos.
  - **Libros sin préstamos:** entran al conteo con 0 gracias al `LEFT JOIN`. Se usa `count(p.id_prestamo)` y no `count(*)`, para que un libro nunca prestado cuente 0 y no 1. Con los datos de prueba no se ven en el reporte, porque hay 21 libros con al menos un préstamo; solo aparecerían si menos de 20 libros tuvieran préstamos.
  - El orden alfabético entre empatados se aplica **afuera** del `WITH TIES`; si se hiciera adentro, rompería el empate.
- **Reporte 2:**
  - "Libro leído" = **préstamo devuelto** (sección 3.2 del proyecto). Sin ese filtro, Camila "ganaría" con 6 préstamos, 3 de ellos sin devolver.
  - Se cuentan préstamos, no títulos distintos.
  - `= max(…)` y no `LIMIT 1`, porque el enunciado dice "el **o los**".
- **Reportes 3 y 4:**
  - Mora = préstamo **abierto** cuya fecha de vencimiento ya pasó, con `<` estricto. Un préstamo que **vence hoy todavía no está en mora**; con `<=`, Isabella aparecería como morosa en el reporte 3 y su Rayuela saldría en el reporte 4 con "0 días de mora".
  - Devolver tarde no deja moroso a nadie.
  - La mora se **calcula** con las fechas; no se guarda en una columna de estado.
- **Ventaja del esquema:** como `ejemplar` es una entidad débil cuya clave incluye el ISBN, el préstamo ya trae el ISBN. Por eso los reportes 1 y 4 unen `prestamo` con `libro` directamente, sin pasar por `ejemplar`.

### 8.4 Taller de consultas de S16 (cierre del Hito 2)

El taller tiene dos partes. La **parte A** son 11 ejercicios sobre un esquema de práctica del profesor, una tienda en línea de café, que vive en su propio esquema (`tienda`) y **no toca** `biblioteca`. La **parte B** son los 4 reportes del proyecto sobre nuestro esquema, con datos de prueba que demuestran que son correctos.

#### 8.4.1 Entregable de la guía y dónde quedó

| # | La guía pide | Dónde quedó |
|---|---|---|
| 1 | `parte-a.sql`: las 11 consultas, cada una con su número y, en la 9, la explicación | [`postgres/scripts/parte-a.sql`](postgres/scripts/parte-a.sql) |
| 2 | `datos-prueba.sql` y `reportes.sql`, en `postgres/scripts/` | [`datos-prueba.sql`](postgres/scripts/datos-prueba.sql) y [`reportes.sql`](postgres/scripts/reportes.sql) |
| 3 | Tabla de verificación de la parte B: caso, esperado, obtenido y qué se corrigió | [Sección 8.4.6](#846-tabla-de-verificación-de-la-parte-b), generada por [`verificacion-parte-b.sql`](postgres/scripts/verificacion-parte-b.sql) |
| 4 | Salida de `psql` de los 4 reportes con los datos de prueba | [`docs/evidencias.md`](docs/evidencias.md), secciones 9 a 11 (copiadas de la terminal del grupo), y las capturas `paso8-*.png` de la [sección 9](#9-evidencias) |

#### 8.4.2 Parte A: ejercicios sobre `tienda`

| Archivo | Qué es |
|---|---|
| [`postgres/scripts/S16-tienda.sql`](postgres/scripts/S16-tienda.sql) | Script del profesor: crea el esquema `tienda` con sus datos. Es re-ejecutable. |
| [`postgres/scripts/parte-a.sql`](postgres/scripts/parte-a.sql) | Los 11 ejercicios resueltos por el grupo. Cada uno explica su técnica y cuántas filas debe devolver. |

Los ejercicios practican: joins de varias tablas, self-join con `LEFT JOIN` (quién refirió a quién), anti-join (productos nunca vendidos), contar ceros con `count(columna)`, `GROUP BY` con `HAVING`, subconsulta correlacionada, `EXISTS`, la trampa de `NOT IN` con `NULL` (y su corrección con `NOT EXISTS`), el máximo con empates y la división con `NOT EXISTS` doble.

**Resultado:** los 11 ejercicios devuelven exactamente las filas esperadas que anota cada uno (2, 8, 1, 8, 3, 2, 4, 2, 5, 2 y 2). Evidencia: [`docs/evidencias.md`, sección 12](docs/evidencias.md#12-taller-s16-parte-a) y la captura [`assets/paso8-parte-a.png`](assets/paso8-parte-a.png). Si se reinicia la base desde cero, el esquema `tienda` se borra: basta con volver a correr `S16-tienda.sql` (comandos en la sección 2, paso 4).

#### 8.4.3 Parte A: las preguntas de la sesión

- **Ejercicio 5. ¿Qué pasa si se olvida el filtro de cancelados?** Los totales suben y **Accesorio** pasa al primer lugar: 621 000 frente a 562 000 de Grano, porque los pedidos cancelados traían el molino (150 000) y la prensa (95 000). Con el filtro, el orden es Grano 480 000, Accesorio 376 000 y Molido 184 000. Por capas: el `FROM` con los dos `JOIN` da 23 filas (una por línea de detalle), el `WHERE` deja 19 y el `GROUP BY`, 3.
- **Ejercicio 9. ¿Por qué el `NOT IN` devuelve 0 filas?** La subconsulta trae los `referido_por`, y los clientes que llegaron solos tienen `NULL`. `x NOT IN (1, 3, 4, NULL)` equivale a `x <> 1 AND x <> 3 AND x <> 4 AND x <> NULL`, y comparar con `NULL` da *desconocido*. El `AND` completo nunca llega a ser verdadero, y el `WHERE` solo deja pasar lo verdadero: descarta todas las filas sin dar error. **Corrección:** `NOT EXISTS` (una fila con `referido_por` `NULL` simplemente no coincide), o filtrar `WHERE referido_por IS NOT NULL` dentro de la subconsulta. Da 5 filas.
- **Ejercicio 11. ¿Por qué da exactamente los que compraron todos? ¿Qué pasa con Andrés?** "Compró todos los productos de Grano" se reescribe como "no existe un producto de Grano que no haya comprado" (`NOT EXISTS` doble). Salen Felipe y Laura. Andrés compró el Huila en un pedido enviado, pero el Nariño y el Cauca solo en el pedido **cancelado** 1013. Como el filtro de cancelados está en la subconsulta interna, esa compra no cuenta y Andrés no sale. **Si se olvida el filtro, la consulta da 3 filas y Andrés aparece** (comprobado en PostgreSQL).
- **Retos R1 a R3:** son opcionales y no suman a la rúbrica. No se hicieron (quedan en [`docs/pendientes.md`](docs/pendientes.md)).

#### 8.4.4 Parte B: qué cambia en nuestro esquema respecto a `reportes_demo`

Las 4 preguntas de la sección 3 de la guía, respondidas antes de escribir los reportes:

| Pregunta | En nuestro esquema |
|---|---|
| ¿El préstamo apunta al libro o a un ejemplar? | A un **ejemplar** (`isbn`, `numero_copia`). Como la clave del ejemplar incluye el ISBN, `prestamo` ya trae el `isbn`: se une con `libro` directamente, sin pasar por `ejemplar`, y se agrupa por libro. |
| ¿El nombre y el correo del lector están en `lector` o en `usuario`? | En **`usuario`**. El teléfono está en `lector`. El reporte 4 une `prestamo` → `lector` → `usuario`. |
| ¿Hay una columna de estado, o todo se calcula con fechas? | **Con fechas.** Abierto = `fecha_devolucion IS NULL`; en mora = abierto y `fecha_vencimiento < CURRENT_DATE`. |
| ¿Dónde está la fecha esperada de devolución? | En **`prestamo.fecha_vencimiento`**. Los datos de prueba la llenan con `fecha_prestamo + 14`. |

#### 8.4.5 Parte B: archivos

| Archivo | Qué hace |
|---|---|
| [`datos-prueba.sql`](postgres/scripts/datos-prueba.sql) | Una bibliotecaria y 30 préstamos con fechas relativas a `CURRENT_DATE`. El encabezado tiene el **resultado esperado** de cada reporte y de cada caso, escrito antes de correr nada. |
| [`reportes.sql`](postgres/scripts/reportes.sql) | Los 4 reportes. Encima de cada uno: qué devuelve, sus decisiones y el resultado esperado. Cada uno queda guardado como vista. |
| [`verificacion-parte-b.sql`](postgres/scripts/verificacion-parte-b.sql) | Lee las 4 vistas y compara, caso por caso, lo esperado con lo obtenido. No repite la lógica de los reportes: prueba exactamente esas consultas. |

#### 8.4.6 Tabla de verificación de la parte B

Una fila por cada caso de la sección 4 de la guía. "Esperado" se escribió antes de correr los reportes; "obtenido" es la salida de `verificacion-parte-b.sql` ([evidencia](docs/evidencias.md#11-verificación-de-la-parte-b)).

| # | Caso | Reporte | Dato de prueba | Esperado | Obtenido | ¿Coincidió? / qué se corrigió |
|---|---|---|---|---|---|---|
| 1 | Libro que nadie ha prestado | R1 | 16 libros sin préstamos, entre ellos *El olvido que seremos* | Cuenta 0, pero queda fuera del top: hay 21 libros con al menos un préstamo | Cuenta 0; fuera del top | Sí. La decisión quedó escrita en el encabezado del reporte 1. |
| 2 | Dos libros empatados en el último puesto | R1 | 16 libros con 1 préstamo, en los puestos 6 a 21 | 21 filas: sale también el empatado del puesto 21 | 21 filas; 16 empatados con 1 | Sí |
| 3 | Dos lectores empatados en el primer lugar | R2 | Mariana y Santiago, 5 préstamos devueltos cada uno | Salen los dos | Mariana y Santiago, 5 | Sí |
| 4 | Lector con varios préstamos abiertos y ninguno devuelto | R2 | Juan David (2 abiertos, 0 devueltos) y Camila (6 préstamos, 3 devueltos) | No sale ninguno | No sale ninguno | Sí. La regla de máximo 3 préstamos abiertos impide que un lector sin devoluciones tenga más préstamos que los ganadores (5). Por eso Camila cubre la parte de "más préstamos que los ganadores". |
| 5 | Préstamo devuelto después de la fecha esperada | R3, R4 | Santiago devolvió el Quijote 6 días tarde | No es mora: 0 veces en R3 y 0 en R4 | R3: 0 · R4: 0 | Sí |
| 6 | Préstamo abierto que vence hoy | R3, R4 | Isabella: la Rayuela, su único préstamo abierto | Regla `<`: no es mora; 0 veces en R3 y 0 en R4 | R3: 0 · R4: 0 | Sí, **después de corregir los datos.** El préstamo era de Juan David, que ya sale en R3 por otros dos préstamos, así que en R3 el caso no se notaba. Se pasó a Isabella. Prueba de control: con `<=`, la verificación da `R3: 1 · R4: 1` y marca `NO`. |
| 7 | Lector con dos préstamos en mora | R3, R4 | Juan David: *Cien años de soledad* (13 días) y *1984* (6 días) | 1 vez en R3 y 2 veces en R4 | R3: 1 · R4: 2 | Sí |
| 8 | Lector sin ningún préstamo | Todos | 12 lectores (documentos 1000000009 a 1000000020) | No aparecen en R2, R3 ni R4 | 12 lectores; R2: 0 · R3: 0 · R4: 0 | Sí |
| — | Total de filas | R1 a R4 | — | 21 · 2 · 4 · 5 | 21 · 2 · 4 · 5 | Sí |

#### 8.4.7 Checkpoint del Hito 2

| Pieza | Dónde quedó | Sesión | Estado |
|---|---|---|---|
| Esquema que corre limpio desde `postgres/init/` con la base vacía | `postgres/init/01_esquema.sql` (y `02_carga.sql`) | S14 | Hecho |
| Carga de libros y lectores desde CSV, con el semilla y con un CSV propio | `postgres/scripts/carga-*.sql` y `postgres/scripts/datos/` | S14 | Hecho |
| Validación de filas mal formadas y duplicados, con bitácora | Los scripts de carga, `carga.rechazo_carga` y [`docs/mapeo-y-criterios.md`](docs/mapeo-y-criterios.md) | S14 | Hecho |
| Las consultas de los 4 reportes, documentadas | `postgres/scripts/reportes.sql` y `datos-prueba.sql` | S16 | Hecho |

No quedó nada pendiente de S14.

## 9. Evidencias

**Salidas en texto:** [`docs/evidencias.md`](docs/evidencias.md) tiene la salida de `psql`, copiada tal cual de la terminal, de cada ejecución:

| Entregable | Sección de `docs/evidencias.md` |
|---|---|
| Arranque desde cero (`init/` crea los dos esquemas) | [1](docs/evidencias.md#1-arranque-desde-cero-init) |
| **Carga 1: libros limpio** | [2](docs/evidencias.md#2-carga-1-libros-limpio) |
| **Carga 2: libros con errores** | [3](docs/evidencias.md#3-carga-2-libros-con-errores) |
| Carga 3: lectores limpio | [4](docs/evidencias.md#4-carga-3-lectores-limpio) |
| **Carga 4: lectores con errores** | [5](docs/evidencias.md#5-carga-4-lectores-con-errores) |
| Totales: los 14 rechazos | [6](docs/evidencias.md#6-totales-después-de-las-4-cargas) |
| **CSV propio** (y su repetición sin duplicar) | [7](docs/evidencias.md#7-csv-propio) |
| **Prueba de la última línea de defensa** (y la regla restaurada) | [8](docs/evidencias.md#8-prueba-de-la-última-línea-de-defensa) |
| Préstamos de prueba (corrida final de S16 y las dos corridas de S15) | [9](docs/evidencias.md#9-préstamos-de-prueba) |
| **Los 4 reportes con los datos de prueba** (S16, parte B) | [10](docs/evidencias.md#10-los-4-reportes) |
| **Tabla de verificación de la parte B** (S16) | [11](docs/evidencias.md#11-verificación-de-la-parte-b) |
| **Taller S16, Parte A** (los 11 ejercicios) | [12](docs/evidencias.md#12-taller-s16-parte-a) |

**Capturas de pantalla** (en [`assets/`](assets/)). Para las cargas 3 y 4, el CSV propio y la prueba de la última línea de defensa, la evidencia es la salida en texto de la tabla anterior.

Pruebas de restricciones en pgAdmin (las 3 pruebas de S11 y la extra):
![Pruebas de restricciones en pgAdmin](assets/paso1-pruebas-pgadmin.png)

Carga 1, libros limpio (32 cargadas):
![Carga 1: libros limpio](assets/carga1-libros-limpio.png)

Carga 2, libros con errores (los 8 errores, cada uno con su motivo):
![Carga 2: libros con errores](assets/carga2-libros-errores.png)

Carga 1 repetida: las 32 filas salen rechazadas por `isbn ya existe en el catálogo` y los totales no cambian. **Repetir la carga no duplica.**
![Carga 1 repetida](assets/carga1-libros-limpio-repetida.png)

**Taller S16 (cierre del Hito 2): corrida final en el Docker del grupo**, en el orden de la guía.

Préstamos de prueba con `datos-prueba.sql` (`30 | 20 | 10 | 5`):
![Préstamos de prueba (S16)](assets/paso8-datos-prueba.png)

Reporte 1: los 20 libros más prestados (21 filas, por el empate en el puesto 20):
![Reporte 1](assets/paso8-reporte-1.png)

Reportes 2, 3 y 4 (cada `CREATE VIEW` es la vista de un reporte):
![Reportes 2, 3 y 4](assets/paso8-reportes-2-3-4.png)

**Tabla de verificación de la parte B: los 8 casos, 9 de 9 coinciden:**
![Verificación de la parte B](assets/paso8-verificacion.png)

Parte A: los 11 ejercicios sobre el esquema `tienda`, cada uno con las filas esperadas:
![Parte A](assets/paso8-parte-a.png)

**Capturas anteriores (S15).** Mismos resultados, con el script cuando se llamaba `datos-prestamos.sql` y los reportes antes de guardarse como vistas: [préstamos de prueba, dos corridas](assets/paso6-datos-prestamos.png) (muestra que el script se puede repetir), [reportes 1 y 2](assets/paso7-reportes-1-2.png) y [reportes 3 y 4](assets/paso7-reportes-3-4.png).

## 10. Lecciones aprendidas

- **PowerShell no es bash.** `rm -rf` no existe: se usa `Remove-Item -Recurse -Force`. Un comando pegado varias veces en la misma línea falla, así que se copia y ejecuta **uno a la vez**.
- **`docker compose` se ejecuta desde la carpeta del `docker-compose.yml`.** De lo contrario aparece `no configuration file provided`.
- **Docker Desktop debe estar abierto.** Si no, aparece el error `dockerDesktopLinuxEngine`.
- **`init/` solo corre con la base vacía.** Primero se copia el esquema a `init/` y **después** se levanta PostgreSQL. Para repetir el arranque, se borra `postgres/data/pgdata`.
- **Codificación:** PowerShell 5.1 muestra mal las tildes de un archivo UTF-8. Se ven bien con `Get-Content -Encoding UTF8`.
- **Los CSV no se editan con Excel**, porque los guarda con `;`, ni con comandos de PowerShell, porque mezclar finales de línea LF y CRLF hace fallar el `COPY` completo. Se usa VS Code o el Bloc de notas.
- **Datos de prueba con fechas relativas:** `datos-prueba.sql` calcula las fechas a partir del día en que se corre. Para que los días de mora de los reportes sean los esperados, se corre **el mismo día** que `reportes.sql`. Ojo: el contenedor usa la hora UTC, así que desde las 7 p. m. de Colombia PostgreSQL ya está en el día siguiente.
- **Un caso de prueba solo prueba algo si puede fallar.** El préstamo que "vence hoy" no se notaba en el reporte 3 porque su lector ya era moroso por otros préstamos: con `<` o con `<=` el reporte salía igual. Se aisló en una lectora sin otros préstamos abiertos, y se comprobó cambiando `<` por `<=` a propósito: la verificación lo detectó.
- **Paginador de psql:** si aparece `(END)`, se sale con `q`. En consultas sueltas se evita con `-P pager=off`.
- **pgAdmin no actualiza el árbol solo:** hay que recargar la página. El ícono `>_` abre el *PSQL Tool* (una terminal psql), no hace Refresh.

## 11. Taller S18: formas normales

Taller sobre un esquema de práctica del profesor: la planilla de servicios del Taller Automotriz El Pistón. Vive en su propio esquema, `automotriz`, así que **no toca** `biblioteca`. El desarrollo completo, con cada paso justificado, está en [`docs/S18-taller-normalizacion.md`](docs/S18-taller-normalizacion.md).

| Parte | Dónde | Qué se hizo |
|---|---|---|
| A1. Diagnóstico | [`docs/S18-taller-normalizacion.md`](docs/S18-taller-normalizacion.md#parte-a1-diagnóstico) | Claves, forma normal y lo que impide subir, para cada relación de la guía; la pregunta de `telefonos` y los grupos repetidos |
| A2. El Pistón hasta 3FN | [`docs/S18-taller-normalizacion.md`](docs/S18-taller-normalizacion.md#parte-a2-el-pistón-hasta-3fn) | 7 dependencias funcionales con su regla del negocio; `(num_orden, cod_servicio)` como única clave (por cierre); 2FN, 3FN y comprobación de FNBC; el dueño del día de la orden |
| B. En PostgreSQL | [`postgres/scripts/normalizacion.sql`](postgres/scripts/normalizacion.sql) | Limpieza de una contradicción, 7 tablas con PK, FK y `NOT NULL`, carga con `SELECT DISTINCT`, reconstrucción exacta con `EXCEPT` y las 3 anomalías de S17 eliminadas |
| C. 3FN frente a FNBC | [`docs/S18-taller-normalizacion.md`](docs/S18-taller-normalizacion.md#parte-c-3fn-frente-a-fnbc) | `responsable` está en 3FN pero no en FNBC; la FNBC pierde una regla; se recomienda 3FN con una FK compuesta (probado en PostgreSQL) |

**Esquema final (3FN y FNBC):**
```
dueno (cedula_dueno PK, …)      modelo (modelo PK, marca)      mecanico (cod_mecanico PK, …)
vehiculo (placa PK, modelo FK, cedula_dueno FK)
orden (num_orden PK, fecha_ingreso, kilometraje, placa FK)
servicio (cod_servicio PK, nombre_servicio, precio_lista)
orden_servicio (num_orden FK, cod_servicio FK, precio_cobrado, cod_mecanico FK)   PK (num_orden, cod_servicio)
```

**Cómo ejecutarlo:**
```powershell
docker compose exec postgres psql -U curso -d curso -f /scripts/S18-automotriz.sql
docker compose exec postgres psql -U curso -d curso -f /scripts/normalizacion.sql
```
Resultado esperado: en (a), una sola contradicción (la cédula 16700002) y `UPDATE 1`; en (c), 3, 4, 4, 6, 5, 3 y 11 filas; en (d), 11 y 11 filas y **0 filas** en los dos `EXCEPT`; en (e), las tres pruebas con `ROLLBACK` y, al final, 11 líneas de orden y 6 órdenes.
