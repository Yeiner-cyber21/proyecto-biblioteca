# Evidencias de ejecución

Salidas **copiadas tal cual** de la terminal (PowerShell 5.1) del grupo, al ejecutar los scripts en el entorno Docker del curso. La única salida que no viene de esa terminal es la prueba de control de la sección 11, y lo dice ahí. La rúbrica de S14 acepta "la salida de `psql` (texto o captura)". Las capturas de pantalla que existen están en [`capturas/`](capturas/).

> **Rutas.** Desde el 17/11/2026 el repositorio está organizado por hitos: los scripts del Hito 2 están en `postgres/scripts/hito2/` (dentro de Docker, `/scripts/hito2/…`). Las salidas de este documento se copiaron **tal cual** de la terminal, así que muestran las rutas que tenían los scripts el día en que se corrieron (por ejemplo, `/scripts/carga-libros.sql`). Los comandos actuales están en el [README, sección 2](../../README.md#2-cómo-levantar-el-proyecto-desde-cero).

## Contenido

1. [Arranque desde cero (`init/`)](#1-arranque-desde-cero-init)
2. [Carga 1: libros limpio](#2-carga-1-libros-limpio)
3. [Carga 2: libros con errores](#3-carga-2-libros-con-errores)
4. [Carga 3: lectores limpio](#4-carga-3-lectores-limpio)
5. [Carga 4: lectores con errores](#5-carga-4-lectores-con-errores)
6. [Totales después de las 4 cargas](#6-totales-después-de-las-4-cargas)
7. [CSV propio](#7-csv-propio)
8. [Prueba de la última línea de defensa](#8-prueba-de-la-última-línea-de-defensa)
9. [Préstamos de prueba](#9-préstamos-de-prueba)
10. [Los 4 reportes](#10-los-4-reportes)
11. [Verificación de la parte B](#11-verificación-de-la-parte-b)
12. [Taller S16, Parte A](#12-taller-s16-parte-a)

---

## 1. Arranque desde cero (`init/`)

```text
PS C:\Users\yeine\proyecto-biblioteca> Get-ChildItem .\postgres\init

    Directorio: C:\Users\yeine\proyecto-biblioteca\postgres\init

Mode                 LastWriteTime         Length Name
----                 -------------         ------ ----
-a----      31/10/2026  4:21 p. m.           7901 01_esquema.sql
-a----       2/11/2026  6:46 p. m.           2797 02_carga.sql
-a----       8/09/2026  9:47 a. m.            963 README.md

PS C:\Users\yeine\proyecto-biblioteca> docker compose down
[+] down 3/3
 ✔ Container curso_pgadmin             Removed                          2.5s
 ✔ Container curso_postgres            Removed                          0.8s
 ✔ Network proyecto-biblioteca_default Removed                          0.5s
PS C:\Users\yeine\proyecto-biblioteca> Remove-Item -Recurse -Force .\postgres\data\pgdata
PS C:\Users\yeine\proyecto-biblioteca> docker compose run --rm postgres sh -c "rm -rf /var/lib/postgresql/data/pgdata"
[+] run 1/1
 ✔ Network proyecto-biblioteca_default Created                          0.2s
Container proyecto-biblioteca-postgres-run-897cd3ad499e Creating
Container proyecto-biblioteca-postgres-run-897cd3ad499e Created
PS C:\Users\yeine\proyecto-biblioteca> Test-Path .\postgres\data\pgdata
False
PS C:\Users\yeine\proyecto-biblioteca> docker compose up -d postgres pgadmin

[+] up 2/2
 ✔ Container curso_postgres Healthy                                    37.6s
 ✔ Container curso_pgadmin  Started                                    38.0s
PS C:\Users\yeine\proyecto-biblioteca> docker compose logs postgres | Select-String "running|ignoring|COMMIT|ERROR|init process complete"

curso_postgres  | running bootstrap script ... ok
curso_postgres  | /usr/local/bin/docker-entrypoint.sh: running
/docker-entrypoint-initdb.d/01_esquema.sql
curso_postgres  | COMMIT
curso_postgres  | /usr/local/bin/docker-entrypoint.sh: running
/docker-entrypoint-initdb.d/02_carga.sql
curso_postgres  | COMMIT
curso_postgres  | /usr/local/bin/docker-entrypoint.sh: ignoring
/docker-entrypoint-initdb.d/README.md
curso_postgres  | PostgreSQL init process complete; ready for start up.

PS C:\Users\yeine\proyecto-biblioteca> docker compose exec postgres psql -U curso -d curso -c '\dn'
        List of schemas
    Name    |       Owner
------------+-------------------
 biblioteca | curso
 carga      | curso
 public     | pg_database_owner
(3 rows)
```

## 2. Carga 1: libros limpio

```text
PS C:\Users\yeine\proyecto-biblioteca> docker compose exec postgres psql -U curso -d curso -f /scripts/carga-libros.sql
Pager usage is off.
BEGIN
TRUNCATE TABLE
COPY 33
INSERT 0 32
UPDATE 32
UPDATE 0
INSERT 0 9
INSERT 0 29
INSERT 0 32
INSERT 0 32
INSERT 0 94
INSERT 0 0
COMMIT

=== Resumen de la carga: /scripts/datos/libros_semilla.csv
 cargadas | rechazadas
----------+------------
       32 |          0
(1 row)

=== Filas rechazadas (también quedan en carga.rechazo_carga)
 linea | motivo | contenido
-------+--------+-----------
(0 rows)

=== Totales en el catálogo después de la carga
 libros | ejemplares | autores | categorias
--------+------------+---------+------------
     32 |         94 |      29 |          9
(1 row)
```

## 3. Carga 2: libros con errores

```text
PS C:\Users\yeine\proyecto-biblioteca> docker compose exec postgres psql -U curso -d curso -v archivo=/scripts/datos/libros_semilla_con_errores.csv -f /scripts/carga-libros.sql
Pager usage is off.
BEGIN
TRUNCATE TABLE
COPY 9
INSERT 0 8
UPDATE 8
UPDATE 0
INSERT 0 0
INSERT 0 0
INSERT 0 0
INSERT 0 0
INSERT 0 0
INSERT 0 8
COMMIT

=== Resumen de la carga: /scripts/datos/libros_semilla_con_errores.csv
 cargadas | rechazadas
----------+------------
        0 |          8
(1 row)

=== Filas rechazadas (también quedan en carga.rechazo_carga)
 linea |              motivo              |                                          contenido
-------+----------------------------------+---------------------------------------------------------------------------------------------
     2 | isbn ya existe en el catálogo    | 9780000000001,Cien años de soledad (edición duplicada),Gabriel García Márquez,Novela,1967,2
     3 | título vacío                     | 9780000000033,,Julio Cortázar,Novela,1963,3
     4 | año no numérico                  | 9780000000034,Relato sin ejemplares numéricos,Autor de Prueba,Novela,dos,3
     5 | año no numérico                  | 9780000000035,Relato con año inválido,Autor de Prueba,Novela,MCMXLIX,2
     6 | tiene 7 columnas, se esperaban 6 | 9780000000036,Relato con columna de más,Autor de Prueba,Novela,1999,2,columna_sobrante
     7 | autor vacío                      | 9780000000037,Relato sin autor,,Novela,2005,1
     8 | isbn vacío                       | ,Relato sin ISBN,Autor de Prueba,Novela,2010,1
     9 | ejemplares negativo              | 9780000000038,Relato con ejemplares negativos,Autor de Prueba,Novela,2015,-3
(8 rows)

=== Totales en el catálogo después de la carga
 libros | ejemplares | autores | categorias
--------+------------+---------+------------
     32 |         94 |      29 |          9
(1 row)
```

## 4. Carga 3: lectores limpio

```text
PS C:\Users\yeine\proyecto-biblioteca> docker compose exec postgres psql -U curso -d curso -f /scripts/carga-lectores.sql
Pager usage is off.
BEGIN
TRUNCATE TABLE
COPY 21
INSERT 0 20
UPDATE 20
UPDATE 0
UPDATE 0
INSERT 0 20
INSERT 0 20
INSERT 0 0
COMMIT

=== Resumen de la carga: /scripts/datos/lectores_semilla.csv
 cargadas | rechazadas
----------+------------
       20 |          0
(1 row)

=== Filas rechazadas (también quedan en carga.rechazo_carga)
 linea | motivo | contenido
-------+--------+-----------
(0 rows)

=== Totales después de la carga (deben ser iguales: cada usuario lector tiene su fila en lector)
 usuarios_lector | lectores
-----------------+----------
              20 |       20
(1 row)
```

## 5. Carga 4: lectores con errores

```text
PS C:\Users\yeine\proyecto-biblioteca> docker compose exec postgres psql -U curso -d curso -v archivo=/scripts/datos/lectores_semilla_con_errores.csv -f /scripts/carga-lectores.sql
Pager usage is off.
BEGIN
TRUNCATE TABLE
COPY 7
INSERT 0 6
UPDATE 6
UPDATE 0
UPDATE 0
INSERT 0 0
INSERT 0 0
INSERT 0 6
COMMIT

=== Resumen de la carga: /scripts/datos/lectores_semilla_con_errores.csv
 cargadas | rechazadas
----------+------------
        0 |          6
(1 row)

=== Filas rechazadas (también quedan en carga.rechazo_carga)
 linea |                           motivo                           |                                         contenido
-------+------------------------------------------------------------+-------------------------------------------------------------------------------------------
     2 | documento ya registrado (perfil lector)                    | 1000000001,Mariana,Gómez Rojas (duplicado),mariana.gomez@correo-ejemplo.edu.co,3001000001
     3 | correo vacío                                               | 1000000021,Carlos,Peña Londoño,,3001000021
     4 | correo mal formado                                         | 1000000022,Diana,Salgado Cuervo,diana.salgado-arroba-correo-ejemplo.edu.co,3001000022
     5 | teléfono no numérico o de longitud inválida (7-15 dígitos) | 1000000023,Jorge,Restrepo Vélez,jorge.restrepo@correo-ejemplo.edu.co,tres-cero-cero
     6 | documento vacío                                            | ,Sin Documento,Prueba Prueba,sin.documento@correo-ejemplo.edu.co,3001000024
     7 | nombres vacíos                                             | 1000000025,,Sin Nombre,sin.nombre@correo-ejemplo.edu.co,3001000025
(6 rows)

=== Totales después de la carga (deben ser iguales: cada usuario lector tiene su fila en lector)
 usuarios_lector | lectores
-----------------+----------
              20 |       20
(1 row)
```

## 6. Totales después de las 4 cargas

Los **14 rechazos** son exactamente los 14 errores de los archivos del curso.

```text
libros | ejemplares | autores | categorias | usuarios | lectores | rechazos
--------+------------+---------+------------+----------+----------+----------
     32 |         94 |      29 |          9 |       20 |       20 |       14
(1 row)
```

## 7. CSV propio

Primera carga: 5 filas válidas y 4 rechazadas (los 3 errores nuevos más la fila extra).

```text
PS C:\Users\yeine\proyecto-biblioteca> Copy-Item "$HOME\Downloads\libros_propios.csv" .\postgres\scripts\datos\
PS C:\Users\yeine\proyecto-biblioteca> docker compose exec postgres psql -U curso -d curso -v archivo=/scripts/datos/libros_propios.csv -f /scripts/carga-libros.sql
Pager usage is off.
BEGIN
TRUNCATE TABLE
COPY 10
INSERT 0 9
UPDATE 9
UPDATE 1
INSERT 0 1
INSERT 0 4
INSERT 0 5
INSERT 0 5
INSERT 0 10
INSERT 0 4
COMMIT

=== Resumen de la carga: /scripts/datos/libros_propios.csv
 cargadas | rechazadas
----------+------------
        5 |          4
(1 row)

=== Filas rechazadas (también quedan en carga.rechazo_carga)
 linea |                          motivo                          |                                   contenido
-------+----------------------------------------------------------+--------------------------------------------------------------------------------
     7 | isbn repetido en el archivo (primera aparición: línea 2) | 9780000000039,La vorágine (copia repetida),José Eustasio Rivera,Novela,1924,1
     8 | año en el futuro (posterior a 2026)                      | 9780000000044,Libro que aún no se publica,Autor de Prueba,Novela,2031,1
     9 | ejemplares supera el máximo por carga (100)              | 9780000000045,Cien mil copias,Autor de Prueba,Novela,2010,1000
    10 | ejemplares no numérico                                   | 9780000000046,Ejemplares escritos en palabras,Autor de Prueba,Novela,2012,tres
(4 rows)

=== Totales en el catálogo después de la carga
 libros | ejemplares | autores | categorias
--------+------------+---------+------------
     37 |        104 |      33 |         10
(1 row)
```

Segunda carga del mismo archivo: **no duplica nada** (0 cargadas, totales iguales).

```text
PS C:\Users\yeine\proyecto-biblioteca> docker compose exec postgres psql -U curso -d curso -v archivo=/scripts/datos/libros_propios.csv -f /scripts/carga-libros.sql
Pager usage is off.
BEGIN
TRUNCATE TABLE
COPY 10
INSERT 0 9
UPDATE 9
UPDATE 0
INSERT 0 0
INSERT 0 0
INSERT 0 0
INSERT 0 0
INSERT 0 0
INSERT 0 9
COMMIT

=== Resumen de la carga: /scripts/datos/libros_propios.csv
 cargadas | rechazadas
----------+------------
        0 |          9
(1 row)

=== Filas rechazadas (también quedan en carga.rechazo_carga)
 linea |                   motivo                    |                                           contenido
-------+---------------------------------------------+------------------------------------------------------------------------------------------------
     2 | isbn ya existe en el catálogo               | 9780000000039,La vorágine,José Eustasio Rivera,Novela,1924,3
     3 | isbn ya existe en el catálogo               | 978-0-00-000004-0,María,Jorge Isaacs,novela,1867,2
     4 | isbn ya existe en el catálogo               | 9780000000041,   El coronel no tiene   quien le escriba  ,Gabriel García Márquez,Novela,1961,2
     5 | isbn ya existe en el catálogo               | 9780000000042,Delirio,Laura Restrepo,Novela,2004,1
     6 | isbn ya existe en el catálogo               | 9780000000043,El olvido que seremos,Héctor Abad Faciolince,Biografía,2006,2
     7 | isbn ya existe en el catálogo               | 9780000000039,La vorágine (copia repetida),José Eustasio Rivera,Novela,1924,1
     8 | año en el futuro (posterior a 2026)         | 9780000000044,Libro que aún no se publica,Autor de Prueba,Novela,2031,1
     9 | ejemplares supera el máximo por carga (100) | 9780000000045,Cien mil copias,Autor de Prueba,Novela,2010,1000
    10 | ejemplares no numérico                      | 9780000000046,Ejemplares escritos en palabras,Autor de Prueba,Novela,2012,tres
(9 rows)

=== Totales en el catálogo después de la carga
 libros | ejemplares | autores | categorias
--------+------------+---------+------------
     37 |        104 |      33 |         10
(1 row)
```

## 8. Prueba de la última línea de defensa

**A. Regla `título vacío` comentada a propósito y carga del archivo con errores:**

```text
PS C:\Users\yeine\proyecto-biblioteca> Select-String -Path .\postgres\scripts\carga-libros.sql -SimpleMatch -Pattern "s.titulo = ''"

postgres\scripts\carga-libros.sql:79:    -- WHEN s.titulo = ''
                  THEN 'título vacío'

PS C:\Users\yeine\proyecto-biblioteca> docker compose exec postgres psql -U curso -d curso -v archivo=/scripts/datos/libros_semilla_con_errores.csv -f /scripts/carga-libros.sql
Pager usage is off.
BEGIN
TRUNCATE TABLE
COPY 9
INSERT 0 8
UPDATE 8
UPDATE 0
INSERT 0 0
INSERT 0 0
psql:/scripts/carga-libros.sql:142: ERROR:  new row for relation "libro" violates check constraint "ck_libro_titulo"
DETAIL:  Failing row contains (9780000000033, , 1963, 7, t).
PS C:\Users\yeine\proyecto-biblioteca> docker compose exec postgres psql -U curso -d curso -P pager=off -c 'SELECT (SELECT count(*) FROM biblioteca.libro) AS libros, (SELECT count(*) FROM carga.rechazo_carga) AS rechazos'
 libros | rechazos
--------+----------
     37 |       27
(1 row)
```

Antes de la prueba, los conteos también eran **37 libros y 27 rechazos**: la carga fallida no guardó nada.

**B. Regla restaurada y carga otra vez:**

```text
PS C:\Users\yeine\proyecto-biblioteca> docker compose exec postgres psql -U curso -d curso -v archivo=/scripts/datos/libros_semilla_con_errores.csv -f /scripts/carga-libros.sql
Pager usage is off.
BEGIN
TRUNCATE TABLE
COPY 9
INSERT 0 8
UPDATE 8
UPDATE 0
INSERT 0 0
INSERT 0 0
INSERT 0 0
INSERT 0 0
INSERT 0 0
INSERT 0 8
COMMIT

=== Resumen de la carga: /scripts/datos/libros_semilla_con_errores.csv
 cargadas | rechazadas
----------+------------
        0 |          8
(1 row)

=== Filas rechazadas (también quedan en carga.rechazo_carga)
 linea |              motivo              |                                          contenido
-------+----------------------------------+---------------------------------------------------------------------------------------------
     2 | isbn ya existe en el catálogo    | 9780000000001,Cien años de soledad (edición duplicada),Gabriel García Márquez,Novela,1967,2
     3 | título vacío                     | 9780000000033,,Julio Cortázar,Novela,1963,3
     4 | año no numérico                  | 9780000000034,Relato sin ejemplares numéricos,Autor de Prueba,Novela,dos,3
     5 | año no numérico                  | 9780000000035,Relato con año inválido,Autor de Prueba,Novela,MCMXLIX,2
     6 | tiene 7 columnas, se esperaban 6 | 9780000000036,Relato con columna de más,Autor de Prueba,Novela,1999,2,columna_sobrante
     7 | autor vacío                      | 9780000000037,Relato sin autor,,Novela,2005,1
     8 | isbn vacío                       | ,Relato sin ISBN,Autor de Prueba,Novela,2010,1
     9 | ejemplares negativo              | 9780000000038,Relato con ejemplares negativos,Autor de Prueba,Novela,2015,-3
(8 rows)

=== Totales en el catálogo después de la carga
 libros | ejemplares | autores | categorias
--------+------------+---------+------------
     37 |        104 |      33 |         10
(1 row)
```

## 9. Préstamos de prueba

**Corrida final de S16** con `datos-prueba.sql`, el 10/11/2026 en la noche (hora de Colombia), en el orden de la guía: `datos-prueba.sql`, `reportes.sql` y `verificacion-parte-b.sql`, seguidos. Captura: [`capturas/paso8-datos-prueba.png`](capturas/paso8-datos-prueba.png).

```text
PS C:\Users\yeine\proyecto-biblioteca> docker compose exec postgres psql -U curso -d curso -f /scripts/datos-prueba.sql
Pager usage is off.
BEGIN
DELETE 30
DELETE 1
INSERT 0 1
INSERT 0 1
INSERT 0 30
COMMIT

=== Préstamos de prueba (esperado: 30 | 20 | 10 | 5)
 prestamos | devueltos | abiertos | en_mora
-----------+-----------+----------+---------
        30 |        20 |       10 |       5
(1 row)
```

**Antes (S15).** Dos corridas seguidas del mismo script, cuando todavía se llamaba `datos-prestamos.sql`: dan lo mismo, así que **se puede repetir**. Los `DELETE` del inicio son los datos de la corrida anterior, que el script borra antes de volver a crearlos. En S16, además del nombre, el préstamo que vence hoy pasó de Juan David a Isabella; el resumen sigue siendo `30 | 20 | 10 | 5`.

```text
PS C:\Users\yeine\proyecto-biblioteca> docker compose exec postgres psql -U curso -d curso -f /scripts/datos-prestamos.sql
Pager usage is off.
BEGIN
DELETE 30
DELETE 1
INSERT 0 1
INSERT 0 1
INSERT 0 30
COMMIT

=== Préstamos de prueba (esperado: 30 | 20 | 10 | 5)
 prestamos | devueltos | abiertos | en_mora
-----------+-----------+----------+---------
        30 |        20 |       10 |       5
(1 row)

PS C:\Users\yeine\proyecto-biblioteca> docker compose exec postgres psql -U curso -d curso -f /scripts/datos-prestamos.sql
Pager usage is off.
BEGIN
DELETE 30
DELETE 1
INSERT 0 1
INSERT 0 1
INSERT 0 30
COMMIT

=== Préstamos de prueba (esperado: 30 | 20 | 10 | 5)
 prestamos | devueltos | abiertos | en_mora
-----------+-----------+----------+---------
        30 |        20 |       10 |       5
(1 row)
```

## 10. Los 4 reportes

Salida de `reportes.sql` justo después de la corrida final de `datos-prueba.sql`. Capturas: [`capturas/paso8-reporte-1.png`](capturas/paso8-reporte-1.png) y [`capturas/paso8-reportes-2-3-4.png`](capturas/paso8-reportes-2-3-4.png). Cada `CREATE VIEW` es la vista de un reporte. Los 4 coinciden con el resultado esperado escrito en el encabezado de `datos-prueba.sql`: **21, 2, 4 y 5 filas**.

El contenedor usa la hora UTC, que a esa hora ya iba en el 11/11. Por eso las fechas de vencimiento del reporte 4 van un día después que en las capturas de S15 (`paso7-*.png`); los **días de mora** son los mismos (31, 13, 7, 6 y 2), porque todo es relativo a `CURRENT_DATE`.

```text
PS C:\Users\yeine\proyecto-biblioteca> docker compose exec postgres psql -U curso -d curso -f /scripts/reportes.sql
Pager usage is off.
CREATE VIEW

== Reporte 1. Los 20 libros más prestados (con empates en el puesto 20) ==
     isbn      |               titulo               | prestamos
---------------+------------------------------------+-----------
 9780000000001 | Cien años de soledad               |         4
 9780000000014 | 1984                               |         3
 9780000000032 | Harry Potter y la piedra filosofal |         3
 9780000000017 | El principito                      |         2
 9780000000004 | Rayuela                            |         2
 9780000000011 | Como agua para chocolate           |         1
 9780000000026 | Crimen y castigo                   |         1
 9780000000003 | Crónica de una muerte anunciada    |         1
 9780000000009 | Don Quijote de la Mancha           |         1
 9780000000002 | El amor en los tiempos del cólera  |         1
 9780000000031 | El nombre del viento               |         1
 9780000000016 | Fahrenheit 451                     |         1
 9780000000007 | Ficciones                          |         1
 9780000000010 | La sombra del viento               |         1
 9780000000039 | La vorágine                        |         1
 9780000000040 | María                              |         1
 9780000000018 | Matilda                            |         1
 9780000000028 | Orgullo y prejuicio                |         1
 9780000000005 | Pedro Páramo                       |         1
 9780000000022 | Sapiens: de animales a dioses      |         1
 9780000000015 | Un mundo feliz                     |         1
(21 rows)

CREATE VIEW

== Reporte 2. El o los lectores que más libros han leído (préstamos devueltos) ==
 documento  | nombres  |    apellidos    | devueltos
------------+----------+-----------------+-----------
 1000000001 | Mariana  | Gómez Rojas     |         5
 1000000002 | Santiago | Rodríguez Pérez |         5
(2 rows)

CREATE VIEW

== Reporte 3. Lectores morosos ==
 documento  |    nombres    |    apellidos
------------+---------------+------------------
 1000000006 | Sebastián     | González Morales
 1000000003 | Valentina     | López Díaz
 1000000004 | Juan David    | Martínez Ruiz
 1000000008 | Andrés Felipe | Vargas Ortiz
(4 rows)

CREATE VIEW

== Reporte 4. Préstamos en mora (lista de notificación) ==
           lector           |                  correo                  |  telefono  |        titulo        | copia | fecha_vencimiento | dias_mora
----------------------------+------------------------------------------+------------+----------------------+-------+-------------------+-----------
 Sebastián González Morales | sebastian.gonzalez@correo-ejemplo.edu.co | 3001000006 | Crimen y castigo     |     1 | 2026-10-11        |        31
 Juan David Martínez Ruiz   | juan.martinez@correo-ejemplo.edu.co      | 3001000004 | Cien años de soledad |     4 | 2026-10-29        |        13
 Valentina López Díaz       | valentina.lopez@correo-ejemplo.edu.co    | 3001000003 | La sombra del viento |     1 | 2026-11-04        |         7
 Juan David Martínez Ruiz   | juan.martinez@correo-ejemplo.edu.co      | 3001000004 | 1984                 |     3 | 2026-11-05        |         6
 Andrés Felipe Vargas Ortiz | andres.vargas@correo-ejemplo.edu.co      | 3001000008 | El nombre del viento |     1 | 2026-11-09        |         2
(5 rows)
```

## 11. Verificación de la parte B

Salida de `verificacion-parte-b.sql`, justo después de los reportes. Las 9 filas coinciden con lo esperado. Captura: [`capturas/paso8-verificacion.png`](capturas/paso8-verificacion.png). Es la "tabla de verificación" que pide la guía de S16; la versión comentada está en el [README, sección 8.4.6](../../README.md#846-tabla-de-verificación-de-la-parte-b).

```text
PS C:\Users\yeine\proyecto-biblioteca> docker compose exec postgres psql -U curso -d curso -f /scripts/verificacion-parte-b.sql
Pager usage is off.

== Verificación de la parte B: los 8 casos de prueba de la guía S16 ==
 caso  |  reporte   |                      prueba                       |              esperado              |              obtenido              | coincide
-------+------------+---------------------------------------------------+------------------------------------+------------------------------------+----------
 1     | R1         | Libro sin préstamos (El olvido que seremos)       | cuenta 0; fuera del top            | cuenta 0; fuera del top            | sí
 2     | R1         | Empate en el último puesto del top                | 21 filas; 16 empatados con 1       | 21 filas; 16 empatados con 1       | sí
 3     | R2         | Empate en el primer lugar                         | Mariana y Santiago, 5              | Mariana y Santiago, 5              | sí
 4     | R2         | Juan David (sin devueltos) y Camila (6 préstamos) | no sale ninguno                    | no sale ninguno                    | sí
 5     | R3, R4     | Santiago devolvió el Quijote 6 días tarde         | R3: 0 · R4: 0                      | R3: 0 · R4: 0                      | sí
 6     | R3, R4     | Isabella: su préstamo vence hoy (regla <)         | R3: 0 · R4: 0                      | R3: 0 · R4: 0                      | sí
 7     | R3, R4     | Juan David: dos préstamos en mora                 | R3: 1 · R4: 2                      | R3: 1 · R4: 2                      | sí
 8     | R2, R3, R4 | Lectores sin ningún préstamo                      | 12 lectores; R2: 0 · R3: 0 · R4: 0 | 12 lectores; R2: 0 · R3: 0 · R4: 0 | sí
 total | R1 a R4    | Filas de cada reporte                             | 21 · 2 · 4 · 5                     | 21 · 2 · 4 · 5                     | sí
(9 rows)
```

**Prueba de control** (hecha al preparar la entrega, en una copia de PostgreSQL 16 fuera del Docker del grupo). Se cambió a propósito `<` por `<=` en los reportes 3 y 4 y se volvió a correr la verificación. El caso 6 dejó de coincidir, como debía: la verificación sí detecta un error en la regla de mora.

```text
 6     | R3, R4     | Isabella: su préstamo vence hoy (regla <)         | R3: 0 · R4: 0                      | R3: 1 · R4: 1                      | NO
 7     | R3, R4     | Juan David: dos préstamos en mora                 | R3: 1 · R4: 2                      | R3: 1 · R4: 2                      | sí
 total | R1 a R4    | Filas de cada reporte                             | 21 · 2 · 4 · 5                     | 21 · 2 · 5 · 6                     | NO
```

Después se restauró `<` y las 9 filas volvieron a coincidir.

## 12. Taller S16, Parte A

Primero `S16-tienda.sql` (crea el esquema `tienda`) y después `parte-a.sql`. Los 11 ejercicios devuelven las filas esperadas que anota cada uno: **2, 8, 1, 8, 3, 2, 4, 2, 5, 2 y 2**. Captura: [`capturas/paso8-parte-a.png`](capturas/paso8-parte-a.png).

```text
PS C:\Users\yeine\proyecto-biblioteca> docker compose exec postgres psql -U curso -d curso -f /scripts/S16-tienda.sql
psql:/scripts/S16-tienda.sql:14: NOTICE:  schema "tienda" does not exist, skipping
DROP SCHEMA
CREATE SCHEMA
SET
CREATE TABLE
CREATE TABLE
CREATE TABLE
CREATE TABLE
INSERT 0 8
INSERT 0 10
INSERT 0 14
INSERT 0 23
PS C:\Users\yeine\proyecto-biblioteca> docker compose exec postgres psql -U curso -d curso -f /scripts/parte-a.sql
Pager usage is off.
SET
== Ejercicio 1 (esperadas: 2) ==
   cliente   |          producto          | cantidad | subtotal
-------------+----------------------------+----------+----------
 Laura Ortiz | Café de origen Cauca 500 g |        1 |    40000
 Laura Ortiz | Prensa francesa            |        1 |    95000
(2 rows)

== Ejercicio 2 (esperadas: 8) ==
     cliente      |  referido_por
------------------+-----------------
 Andrés Mejía     | Laura Ortiz
 Daniela Rincón   | Felipe Cárdenas
 Felipe Cárdenas  |
 Jorge Salazar    |
 Laura Ortiz      |
 Natalia Quintero | Paula Restrepo
 Óscar Vélez      |
 Paula Restrepo   | Laura Ortiz
(8 rows)

== Ejercicio 3 (esperadas: 1) ==
      nombre
------------------
 Taza de cerámica
(1 row)

== Ejercicio 4 (esperadas: 8) ==
      nombre      | pedidos
------------------+---------
 Andrés Mejía     |       3
 Felipe Cárdenas  |       3
 Laura Ortiz      |       3
 Paula Restrepo   |       2
 Daniela Rincón   |       1
 Natalia Quintero |       1
 Óscar Vélez      |       1
 Jorge Salazar    |       0
(8 rows)

== Ejercicio 5 (esperadas: 3) ==
 categoria | total
-----------+--------
 Grano     | 480000
 Accesorio | 376000
 Molido    | 184000
(3 rows)

== Ejercicio 6 (esperadas: 2) ==
 mes | total
-----+--------
   2 | 255000
   4 | 393000
(2 rows)

== Ejercicio 7 (esperadas: 4) ==
           nombre            | categoria | precio
-----------------------------+-----------+--------
 Molino manual               | Accesorio | 150000
 Prensa francesa             | Accesorio |  95000
 Café de origen Nariño 500 g | Grano     |  42000
 Café molido premium 500 g   | Molido    |  30000
(4 rows)

== Ejercicio 8 (esperadas: 2) ==
     nombre
----------------
 Daniela Rincón
 Laura Ortiz
(2 rows)

== Ejercicio 9 (esperadas: 5) ==
      nombre
------------------
 Andrés Mejía
 Daniela Rincón
 Jorge Salazar
 Natalia Quintero
 Óscar Vélez
(5 rows)

== Ejercicio 10 (esperadas: 2) ==
      nombre      | total
------------------+--------
 Laura Ortiz      | 287000
 Natalia Quintero | 287000
(2 rows)

== Ejercicio 11 (esperadas: 2) ==
     nombre
-----------------
 Felipe Cárdenas
 Laura Ortiz
(2 rows)
```
