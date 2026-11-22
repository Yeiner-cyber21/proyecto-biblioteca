# Hito 3. Evidencias (salidas de `psql`)

**750006C Bases de Datos · Universidad del Valle · Grupo 9**

Integrantes: Eisin Yeiner Tobar Bravo · Giovanny Mora Segura

Salidas **copiadas tal cual** de la terminal del grupo (PowerShell + Docker del curso), en el orden en que se corrieron. Respaldan las secciones 4 y 5 del [documento de normalización](hito3-documento-normalizacion.md).

## Contenido

1. [Migración de la base del grupo (`normalizacion.sql`)](#1-migración-de-la-base-del-grupo-normalizacionsql)
2. [El `init/` nuevo en una base vacía (`prueba_init`)](#2-el-init-nuevo-en-una-base-vacía-prueba_init)
3. [Los reportes del S16 sobre el esquema nuevo](#3-los-reportes-del-s16-sobre-el-esquema-nuevo)

---

## 1. Migración de la base del grupo (`normalizacion.sql`)

Base `curso`, con los datos de S14 y S16 y el esquema del Hito 2. Los `NOTICE … does not exist, skipping` del paso 2 son normales: el script quita primero lo que habría dejado una corrida anterior, y en la primera corrida no hay nada que quitar.

```text
PS C:\Users\yeine\proyecto-biblioteca> docker compose exec postgres psql -U curso -d curso -f /scripts/hito3/normalizacion.sql
Pager usage is off.
SET

== 1. Evidencia: perfil frente a lector y bibliotecario (esperado: 0 en las cuatro) ==
                 contradiccion                  | filas
------------------------------------------------+-------
 perfil lector sin fila en lector               |     0
 fila en lector con otro perfil                 |     0
 perfil bibliotecario sin fila en bibliotecario |     0
 fila en bibliotecario con otro perfil          |     0
(4 rows)

== 1. Evidencia: categorías que solo cambian en mayúsculas (esperado: 0 filas) ==
 nombre | count
--------+-------
(0 rows)

== 1. Evidencia: autores que solo cambian en mayúsculas o espacios (esperado: 0 filas) ==
 nombre | count
--------+-------
(0 rows)


== 2. Migración ==
BEGIN
SELECT 5
SELECT 20
SELECT 1
psql:/scripts/hito3/normalizacion.sql:81: NOTICE:  constraint "lector_usuario_perfil_fkey" of relation "lector" does not exist, skipping
ALTER TABLE
psql:/scripts/hito3/normalizacion.sql:82: NOTICE:  constraint "bibliotecario_usuario_perfil_fkey" of relation "bibliotecario" does not exist, skipping
ALTER TABLE
psql:/scripts/hito3/normalizacion.sql:83: NOTICE:  constraint "usuario_id_perfil_key" of relation "usuario" does not exist, skipping
ALTER TABLE
psql:/scripts/hito3/normalizacion.sql:84: NOTICE:  index "categoria_nombre_lower_key" does not exist, skipping
DROP INDEX
psql:/scripts/hito3/normalizacion.sql:85: NOTICE:  index "autor_nombre_lower_key" does not exist, skipping
DROP INDEX
ALTER TABLE
ALTER TABLE
ALTER TABLE
ALTER TABLE
ALTER TABLE
CREATE INDEX
CREATE INDEX
== 3. Conteos antes y después (esperado: iguales en las 5 tablas; no se crea ni se borra ninguna fila) ==
     tabla     | antes | despues | coincide
---------------+-------+---------+----------
 usuario       |    21 |      21 | sí
 lector        |    20 |      20 | sí
 bibliotecario |     1 |       1 | sí
 categoria     |    10 |      10 | sí
 autor         |    33 |      33 | sí
(5 rows)

== 3. lector: filas de antes que no están después, y al revés (esperado: 0 filas) ==
 id_usuario | telefono
------------+----------
(0 rows)

== 3. bibliotecario: lo mismo (esperado: 0 filas) ==
 id_usuario
------------
(0 rows)

== 3. La columna nueva quedó llena (esperado: lector -> lector, bibliotecario -> bibliotecario) ==
     tabla     |    perfil     | filas
---------------+---------------+-------
 lector        | lector        |    20
 bibliotecario | bibliotecario |     1
(2 rows)

ALTER TABLE
ALTER TABLE
COMMIT

== 5. Cambiar a "administrador" el perfil de un usuario que está en lector (esperado: rechazado) ==
psql:/scripts/hito3/normalizacion.sql:157: NOTICE:  Rechazado, como debe ser: update or delete on table "usuario" violates foreign key constraint "lector_usuario_perfil_fkey" on table "lector"
DO
== 5. Registrar como lector a un usuario que no tiene perfil de lector (esperado: rechazado) ==
psql:/scripts/hito3/normalizacion.sql:173: NOTICE:  Rechazado, como debe ser: insert or update on table "lector" violates foreign key constraint "lector_usuario_perfil_fkey"
DO
== 5. Crear la categoría "novela" cuando ya existe "Novela" (esperado: rechazado) ==
psql:/scripts/hito3/normalizacion.sql:182: NOTICE:  Rechazado, como debe ser: duplicate key value violates unique constraint "categoria_nombre_lower_key"
DO
== 5. Crear el autor " gabriel garcía márquez " (esperado: rechazado) ==
psql:/scripts/hito3/normalizacion.sql:191: NOTICE:  Rechazado, como debe ser: duplicate key value violates unique constraint "autor_nombre_lower_key"
DO
== 5. Lo que hace ahora la carga de libros con ese mismo autor: lo reconoce y no lo duplica (esperado: INSERT 0 0) ==
INSERT 0 0

== Fin: el esquema quedó igual al de postgres/init/01_esquema.sql (Hito 3) ==
```

## 2. El `init/` nuevo en una base vacía (`prueba_init`)

Como pide la guía del S20, el esquema nuevo se prueba en una base aparte, sin tocar la del grupo. `01_esquema.sql` se corrió dos veces: la segunda muestra que se puede repetir (borra y recrea el esquema).

```text
PS C:\Users\yeine\proyecto-biblioteca> docker compose exec postgres psql -U curso -d curso -c "CREATE DATABASE prueba_init;"
CREATE DATABASE
PS C:\Users\yeine\proyecto-biblioteca> docker compose exec postgres psql -U curso -d prueba_init -f /docker-entrypoint-initdb.d/01_esquema.sql
BEGIN
CREATE EXTENSION
psql:/docker-entrypoint-initdb.d/01_esquema.sql:31: NOTICE:  schema "biblioteca" does not exist, skipping
DROP SCHEMA
CREATE SCHEMA
SET
CREATE TABLE
CREATE TABLE
CREATE TABLE
CREATE TABLE
CREATE INDEX
CREATE TABLE
CREATE INDEX
CREATE TABLE
CREATE TABLE
CREATE TABLE
CREATE TABLE
CREATE INDEX
COMMIT
PS C:\Users\yeine\proyecto-biblioteca> docker compose exec postgres psql -U curso -d prueba_init -f /docker-entrypoint-initdb.d/02_carga.sql
BEGIN
psql:/docker-entrypoint-initdb.d/02_carga.sql:17: NOTICE:  schema "carga" does not exist, skipping
DROP SCHEMA
CREATE SCHEMA
CREATE TABLE
CREATE TABLE
CREATE TABLE
CREATE TABLE
COMMIT
PS C:\Users\yeine\proyecto-biblioteca> docker compose exec postgres psql -U curso -d prueba_init -f /docker-entrypoint-initdb.d/01_esquema.sql
BEGIN
psql:/docker-entrypoint-initdb.d/01_esquema.sql:29: NOTICE:  extension "pgcrypto" already exists, skipping
CREATE EXTENSION
psql:/docker-entrypoint-initdb.d/01_esquema.sql:31: NOTICE:  drop cascades to 9 other objects
DETAIL:  drop cascades to table biblioteca.usuario
drop cascades to table biblioteca.lector
drop cascades to table biblioteca.bibliotecario
drop cascades to table biblioteca.categoria
drop cascades to table biblioteca.autor
drop cascades to table biblioteca.libro
drop cascades to table biblioteca.libro_autor
drop cascades to table biblioteca.ejemplar
drop cascades to table biblioteca.prestamo
DROP SCHEMA
CREATE SCHEMA
SET
CREATE TABLE
CREATE TABLE
CREATE TABLE
CREATE TABLE
CREATE INDEX
CREATE TABLE
CREATE INDEX
CREATE TABLE
CREATE TABLE
CREATE TABLE
CREATE TABLE
CREATE INDEX
COMMIT
PS C:\Users\yeine\proyecto-biblioteca> docker compose exec postgres psql -U curso -d curso -c "DROP DATABASE prueba_init;"
DROP DATABASE
```

## 3. Los reportes del S16 sobre el esquema nuevo

Sobre la base del grupo, ya migrada: `datos-prueba.sql`, `reportes.sql` y `verificacion-parte-b.sql`, seguidos. Dan los mismos resultados que en el Hito 2 (21, 2, 4 y 5 filas, y 9 de 9). Las fechas de vencimiento cambian porque `datos-prueba.sql` las calcula con la fecha del día; los días de mora (31, 13, 7, 6 y 2) son los de siempre.

```text
PS C:\Users\yeine\proyecto-biblioteca> docker compose exec postgres psql -U curso -d curso -f /scripts/hito2/datos-prueba.sql
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

PS C:\Users\yeine\proyecto-biblioteca> docker compose exec postgres psql -U curso -d curso -f /scripts/hito2/reportes.sql
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
 Sebastián González Morales | sebastian.gonzalez@correo-ejemplo.edu.co | 3001000006 | Crimen y castigo     |     1 | 2026-10-22        |        31
 Juan David Martínez Ruiz   | juan.martinez@correo-ejemplo.edu.co      | 3001000004 | Cien años de soledad |     4 | 2026-11-09        |        13
 Valentina López Díaz       | valentina.lopez@correo-ejemplo.edu.co    | 3001000003 | La sombra del viento |     1 | 2026-11-15        |         7
 Juan David Martínez Ruiz   | juan.martinez@correo-ejemplo.edu.co      | 3001000004 | 1984                 |     3 | 2026-11-16        |         6
 Andrés Felipe Vargas Ortiz | andres.vargas@correo-ejemplo.edu.co      | 3001000008 | El nombre del viento |     1 | 2026-11-20        |         2
(5 rows)

PS C:\Users\yeine\proyecto-biblioteca> docker compose exec postgres psql -U curso -d curso -f /scripts/hito2/verificacion-parte-b.sql
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
