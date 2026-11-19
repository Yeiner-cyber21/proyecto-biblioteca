-- =====================================================================
-- a2-indices.sql  ·  S20, Parte A2: la misma consulta, con índices
-- 750006C Bases de Datos · Universidad del Valle · Grupo 9
-- Integrantes: Eisin Yeiner Tobar Bravo · Giovanny Mora Segura
--
-- Requisito: haber corrido S20-rendimiento.sql y a1-catalogo.sql antes.
--
-- Uso (PowerShell, desde la carpeta del proyecto):
--   docker compose exec postgres psql -U curso -d curso -f /scripts/hito3/taller-S20/a2-indices.sql
--
-- Antes de desnormalizar, se prueba un índice (pre-lectura, sección 4).
-- PostgreSQL crea índice para cada PRIMARY KEY y UNIQUE, pero NO para las
-- columnas de una FOREIGN KEY. Los dos joins de la consulta van por FK
-- (ejemplar.isbn y prestamo.id_ejemplar): son los candidatos.
--
--   ejemplar_isbn_idx     índice normal sobre la FK ejemplar.isbn
--   prestamo_abierto_idx  índice PARCIAL: solo indexa las filas que cumplen
--                         la condición (los 3 750 préstamos abiertos), no
--                         los 303 750. Es pequeño y es justo lo que pide la
--                         consulta (fecha_devolucion IS NULL).
--
-- Un índice NO es redundancia del modelo: no se consulta ni se actualiza a
-- mano, el DBMS lo mantiene solo en cada INSERT, UPDATE y DELETE, así que
-- no puede desincronizarse. Las tablas no cambian (mismas columnas, mismos
-- datos); solo cambia CÓMO se buscan las filas.
--
-- Se puede correr varias veces: IF NOT EXISTS no falla si ya existen.
-- =====================================================================

\set ON_ERROR_STOP on
\pset pager off
SET search_path TO rendimiento;

\echo
\echo '== A2. Crear los dos índices =='
CREATE INDEX IF NOT EXISTS ejemplar_isbn_idx    ON ejemplar (isbn);
CREATE INDEX IF NOT EXISTS prestamo_abierto_idx ON prestamo (id_ejemplar) WHERE fecha_devolucion IS NULL;

\echo
\echo '== A2. Tamaño de cada índice frente a la tabla prestamo (el parcial es mucho más pequeño) =='
SELECT c.relname AS objeto,
       CASE c.relkind WHEN 'r' THEN 'tabla' WHEN 'i' THEN 'índice' END AS tipo,
       pg_size_pretty(pg_relation_size(c.oid)) AS tamano
FROM   pg_class c
JOIN   pg_namespace n ON n.oid = c.relnamespace
WHERE  n.nspname = 'rendimiento'
  AND  c.relname IN ('prestamo', 'prestamo_pkey', 'prestamo_abierto_idx', 'ejemplar', 'ejemplar_isbn_idx')
ORDER BY pg_relation_size(c.oid) DESC;

\echo
\echo '== A2. Sin redundancia: las tablas tienen las mismas columnas que antes (esperado: libro 4, ejemplar 2, prestamo 6) =='
SELECT table_name AS tabla, count(*) AS columnas
FROM   information_schema.columns
WHERE  table_schema = 'rendimiento' AND table_name IN ('libro', 'ejemplar', 'prestamo')
GROUP BY table_name
ORDER BY table_name;

\echo
\echo '== A2. El resultado no cambia (esperado: igual que en A1, 83 con 2 y 28 con 3) =='
SELECT disponibles, count(*) AS titulos
FROM (
    SELECT l.isbn, l.titulo, count(e.id_ejemplar) - count(p.id) AS disponibles
    FROM   libro l
    JOIN   ejemplar e      ON e.isbn = l.isbn
    LEFT JOIN prestamo p   ON p.id_ejemplar = e.id_ejemplar
                          AND p.fecha_devolucion IS NULL
    WHERE  l.titulo LIKE 'Libro 12%'
    GROUP BY l.isbn, l.titulo
) AS catalogo
GROUP BY disponibles
ORDER BY disponibles;

\echo
\echo '== A2. EXPLAIN ANALYZE con índices, corrida 1 de 3 =='
EXPLAIN ANALYZE
SELECT l.isbn, l.titulo, count(e.id_ejemplar) - count(p.id) AS disponibles
FROM   libro l
JOIN   ejemplar e      ON e.isbn = l.isbn
LEFT JOIN prestamo p   ON p.id_ejemplar = e.id_ejemplar
                      AND p.fecha_devolucion IS NULL
WHERE  l.titulo LIKE 'Libro 12%'
GROUP BY l.isbn, l.titulo;

\echo
\echo '== A2. EXPLAIN ANALYZE con índices, corrida 2 de 3 =='
EXPLAIN ANALYZE
SELECT l.isbn, l.titulo, count(e.id_ejemplar) - count(p.id) AS disponibles
FROM   libro l
JOIN   ejemplar e      ON e.isbn = l.isbn
LEFT JOIN prestamo p   ON p.id_ejemplar = e.id_ejemplar
                      AND p.fecha_devolucion IS NULL
WHERE  l.titulo LIKE 'Libro 12%'
GROUP BY l.isbn, l.titulo;

\echo
\echo '== A2. EXPLAIN ANALYZE con índices, corrida 3 de 3 =='
EXPLAIN ANALYZE
SELECT l.isbn, l.titulo, count(e.id_ejemplar) - count(p.id) AS disponibles
FROM   libro l
JOIN   ejemplar e      ON e.isbn = l.isbn
LEFT JOIN prestamo p   ON p.id_ejemplar = e.id_ejemplar
                      AND p.fecha_devolucion IS NULL
WHERE  l.titulo LIKE 'Libro 12%'
GROUP BY l.isbn, l.titulo;

-- Qué buscar en el plan:
--   el  Seq Scan on prestamo p  de A1 desapareció. En su lugar hay un
--   Index Scan using prestamo_abierto_idx on prestamo p  (loops=333), dentro
--   de un  Nested Loop Left Join : por cada uno de los 333 ejemplares de los
--   111 títulos, busca en el índice si tiene préstamo abierto, en vez de
--   recorrer los 303 750 préstamos.
--   Puede seguir apareciendo  Seq Scan on ejemplar e : la tabla es pequeña
--   (15 000 filas) y al planificador le sale más barato recorrerla. Está bien.
