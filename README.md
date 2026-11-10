# Sistema de gestión de biblioteca: proyecto integrador

**750006C Bases de Datos · Universidad del Valle**

| | |
|---|---|
| **Grupo** | ✏️ *(nombre o número del grupo)* |
| **Integrantes** | ✏️ *Nombre 1* · *Nombre 2* · *Nombre 3* · *Nombre 4* |
| **Entrega actual** | Hito 2, avance de S14: esquema en PostgreSQL y carga masiva desde CSV |
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
8. [Evidencias](#8-evidencias)
9. [Lecciones aprendidas](#9-lecciones-aprendidas)
10. [Pendientes](#10-pendientes)

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
│   │   └── datos/                   ← 4 CSV semilla del curso + CSV propio del grupo
│   └── data/                        ← datos internos de PostgreSQL (no se suben a GitHub)
├── pgadmin/servers.json             ← conexión a PostgreSQL precargada en pgAdmin
├── node/                            ← API REST (Hito 5)
├── docs/
│   ├── mapeo-y-criterios.md         ← mapeo CSV → esquema y criterios por tipo de error
│   └── README-entorno-docker.md     ← README original del entorno del profesor
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

**3. Revisar en pgAdmin:** abrir `http://localhost:5050`, entrar al servidor "Curso - PostgreSQL" (contraseña `curso`) e ir a *Databases → curso → Schemas*.

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
| 09/11/2026 | Prueba completa desde una base vacía (`init/` crea los dos esquemas solo), carga del CSV propio (5 cargadas, 4 rechazadas), prueba de la última línea de defensa y publicación del repositorio en GitHub. |

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
| 2 | *La vorágine* | ✅ Cargada | Fila normal; primera aparición del ISBN que se repite en la línea 7 |
| 3 | *María* | ✅ Cargada | Corrección: el ISBN `978-0-00-000004-0` se guarda como `9780000000040`, y `novela` como `Novela` |
| 4 | *El coronel no tiene quien le escriba* | ✅ Cargada | Corrección: espacios sobrantes; el autor ya existía y no se duplica |
| 5 | *Delirio* | ✅ Cargada | Fila normal |
| 6 | *El olvido que seremos* | ✅ Cargada | Categoría nueva (`Biografía`), creada automáticamente |
| 7 | ISBN de la línea 2, repetido | ❌ **Error nuevo** | `isbn repetido en el archivo (primera aparición: línea 2)` |
| 8 | Año 2031 | ❌ **Error nuevo** | `año en el futuro (posterior a 2026)` |
| 9 | 1000 ejemplares | ❌ **Error nuevo** | `ejemplares supera el máximo por carga (100)` |
| 10 | Ejemplares `tres` | ❌ Extra | `ejemplares no numérico`: prueba la regla que no activaron los datos del curso |

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

## 8. Evidencias

**Entregables de S14**

Carga 1, libros limpio:
![Carga 1: libros limpio](assets/carga1-libros-limpio.png)

Carga 2, libros con errores:
![Carga 2: libros con errores](assets/carga2-libros-errores.png)

Carga 4, lectores con errores:
![Carga 4: lectores con errores](assets/carga4-lectores-errores.png)

CSV propio:
![CSV propio](assets/paso6-csv-propio.png)

Última línea de defensa, el error del `CHECK`:
![Última línea de defensa](assets/paso7-error-check.png)

**Otras evidencias**

Pruebas de restricciones en pgAdmin:
![Pruebas de restricciones](assets/paso1-pruebas-pgadmin.png)

Log de `init/` con la base vacía:
![Log de init](assets/paso5-init-log.png)

Carga 3, lectores limpio:
![Carga 3: lectores limpio](assets/carga3-lectores-limpio.png)

Conteos antes y después de la prueba de la última línea de defensa:
![Antes](assets/paso7-antes.png)
![Después](assets/paso7-despues.png)

Regla restaurada:
![Restaurado](assets/paso7-restaurado.png)

## 9. Lecciones aprendidas

- **PowerShell no es bash.** `rm -rf` no existe: se usa `Remove-Item -Recurse -Force`. Un comando pegado varias veces en la misma línea falla, así que se copia y ejecuta **uno a la vez**.
- **`docker compose` se ejecuta desde la carpeta del `docker-compose.yml`.** De lo contrario aparece `no configuration file provided`.
- **Docker Desktop debe estar abierto.** Si no, aparece el error `dockerDesktopLinuxEngine`.
- **`init/` solo corre con la base vacía.** Primero se copia el esquema a `init/` y **después** se levanta PostgreSQL. Para repetir el arranque, se borra `postgres/data/pgdata`.
- **Codificación:** PowerShell 5.1 muestra mal las tildes de un archivo UTF-8. Se ven bien con `Get-Content -Encoding UTF8`.
- **Los CSV no se editan con Excel**, porque los guarda con `;`, ni con comandos de PowerShell, porque mezclar finales de línea LF y CRLF hace fallar el `COPY` completo. Se usa VS Code o el Bloc de notas.
- **Paginador de psql:** si aparece `(END)`, se sale con `q`. En consultas sueltas se evita con `-P pager=off`.
- **pgAdmin no actualiza el árbol solo:** hay que recargar la página. El ícono `>_` abre el *PSQL Tool* (una terminal psql), no hace Refresh.

## 10. Pendientes

- **S15 y S16:** las consultas de los 4 reportes (20 libros más prestados, usuarios que más leen, morosos y notificación de mora) y datos propios de préstamos para que devuelvan resultados.
- **Hito 3:** análisis de normalización del esquema.
- **Hito 4:** procedimiento almacenado y trigger, a partir de las reglas que el esquema no garantiza (sección 4).
- **Hito 5:** roles de PostgreSQL con privilegios mínimos, API REST en Node.js y login con contraseñas bcrypt.
