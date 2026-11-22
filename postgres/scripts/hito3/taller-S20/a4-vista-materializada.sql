-- =====================================================================
-- a4-vista-materializada.sql  ·  S20, Parte A4: el top 20 de libros más prestados
-- 750006C Bases de Datos · Universidad del Valle · Grupo 9
-- Integrantes: Eisin Yeiner Tobar Bravo · Giovanny Mora Segura
--
-- Requisito: haber corrido S20-rendimiento.sql y los pasos A1 a A3.
-- Uso (PowerShell, desde la carpeta del proyecto):
--   docker compose exec postgres psql -U curso -d curso -f /scripts/hito3/taller-S20/a4-vista-materializada.sql
--
-- Es el reporte 1 de S15/S16 sobre este esquema: préstamos -> ejemplar ->
-- libro, agrupado por libro, los 20 primeros con empates.
--
-- Por qué un índice NO lo arregla: para contar los préstamos de cada libro
-- hay que leer TODOS los préstamos (303 750). Un índice sirve para encontrar
-- POCAS filas sin leer las demás; aquí se necesitan todas. Lo que sí sirve
-- es no recalcular: guardar el resultado en una VISTA MATERIALIZADA.
--
-- Vista normal frente a vista materializada:
--   CREATE VIEW               guarda la CONSULTA; cada SELECT la vuelve a calcular.
--   CREATE MATERIALIZED VIEW  guarda el RESULTADO; un SELECT lo lee ya hecho.
--                             Se queda congelado hasta el próximo
--                             REFRESH MATERIALIZED VIEW, que lo recalcula.
--
-- Re-ejecutable: al empezar quita la vista y los 4000 préstamos simulados
-- de una corrida anterior.
-- =====================================================================

\set ON_ERROR_STOP on
\pset pager off
SET search_path TO rendimiento;

DROP MATERIALIZED VIEW IF EXISTS top_prestados;
DELETE FROM prestamo WHERE id BETWEEN 500001 AND 504000;

-- ---------------------------------------------------------------------
-- (a) El reporte calculado en cada consulta
-- ---------------------------------------------------------------------
\echo
\echo '== A4 (a). El top 20 (esperado: 20 filas; Libro 1 con 3881, Libro 2 con 1881, Libro 3 con 1401...) =='
SELECT   l.isbn, l.titulo, count(*) AS prestamos
FROM     prestamo p
JOIN     ejemplar e ON e.id_ejemplar = p.id_ejemplar
JOIN     libro    l ON l.isbn        = e.isbn
GROUP BY l.isbn, l.titulo
ORDER BY prestamos DESC
FETCH FIRST 20 ROWS WITH TIES;

\echo
\echo '== A4 (a). EXPLAIN ANALYZE del reporte calculado, corrida 1 de 3 =='
EXPLAIN ANALYZE
SELECT   l.isbn, l.titulo, count(*) AS prestamos
FROM     prestamo p
JOIN     ejemplar e ON e.id_ejemplar = p.id_ejemplar
JOIN     libro    l ON l.isbn        = e.isbn
GROUP BY l.isbn, l.titulo
ORDER BY prestamos DESC
FETCH FIRST 20 ROWS WITH TIES;

\echo '== A4 (a). Corrida 2 de 3 =='
EXPLAIN ANALYZE
SELECT   l.isbn, l.titulo, count(*) AS prestamos
FROM     prestamo p
JOIN     ejemplar e ON e.id_ejemplar = p.id_ejemplar
JOIN     libro    l ON l.isbn        = e.isbn
GROUP BY l.isbn, l.titulo
ORDER BY prestamos DESC
FETCH FIRST 20 ROWS WITH TIES;

\echo '== A4 (a). Corrida 3 de 3 =='
EXPLAIN ANALYZE
SELECT   l.isbn, l.titulo, count(*) AS prestamos
FROM     prestamo p
JOIN     ejemplar e ON e.id_ejemplar = p.id_ejemplar
JOIN     libro    l ON l.isbn        = e.isbn
GROUP BY l.isbn, l.titulo
ORDER BY prestamos DESC
FETCH FIRST 20 ROWS WITH TIES;

-- ---------------------------------------------------------------------
-- (b) El mismo reporte, guardado como vista materializada
-- ---------------------------------------------------------------------
\echo
\echo '== A4 (b). Crear la vista materializada (esperado: SELECT 20) =='
CREATE MATERIALIZED VIEW top_prestados AS
SELECT   l.isbn, l.titulo, count(*) AS prestamos
FROM     prestamo p
JOIN     ejemplar e ON e.id_ejemplar = p.id_ejemplar
JOIN     libro    l ON l.isbn        = e.isbn
GROUP BY l.isbn, l.titulo
ORDER BY prestamos DESC
FETCH FIRST 20 ROWS WITH TIES;

\echo '== A4 (b). EXPLAIN ANALYZE de leer la vista materializada, corrida 1 de 3 =='
EXPLAIN ANALYZE SELECT * FROM top_prestados;
\echo '== A4 (b). Corrida 2 de 3 =='
EXPLAIN ANALYZE SELECT * FROM top_prestados;
\echo '== A4 (b). Corrida 3 de 3 =='
EXPLAIN ANALYZE SELECT * FROM top_prestados;

-- ---------------------------------------------------------------------
-- (c) Un mes de mucho movimiento de un libro que no estaba en el top:
-- 4000 préstamos del ejemplar 15000 (Libro 5000, que tenía 21).
-- ---------------------------------------------------------------------
\echo
\echo '== A4 (c). 4000 préstamos nuevos de Libro 5000 (esperado: INSERT 0 4000) =='
INSERT INTO prestamo
SELECT 500000 + g, 15000, (1000000001 + g % 2000)::text,
       DATE '2025-06-01', DATE '2025-06-15', DATE '2025-06-10'
FROM   generate_series(1, 4000) AS g;

\echo '-- La vista materializada NO se enteró (esperado: sigue Libro 1 de primero)'
SELECT * FROM top_prestados ORDER BY prestamos DESC LIMIT 3;

\echo '-- La consulta calculada sí (esperado: Libro 5000 de primero, con 4021)'
SELECT   l.isbn, l.titulo, count(*) AS prestamos
FROM     prestamo p
JOIN     ejemplar e ON e.id_ejemplar = p.id_ejemplar
JOIN     libro    l ON l.isbn        = e.isbn
GROUP BY l.isbn, l.titulo
ORDER BY prestamos DESC
LIMIT 3;

\echo '-- REFRESH: recalcula la vista con los datos de hoy'
REFRESH MATERIALIZED VIEW top_prestados;

\echo '-- Después del REFRESH (esperado: Libro 5000 de primero, con 4021)'
SELECT * FROM top_prestados ORDER BY prestamos DESC LIMIT 3;

-- ---------------------------------------------------------------------
-- (d) En la biblioteca del proyecto, ¿cada cuánto refrescarla y quién?
--
--   Una vez al día, de noche (o al abrir el reporte, si casi nadie lo usa).
--   "Los 20 más prestados" es un reporte para decidir compras o exhibir
--   libros: nadie decide distinto por los préstamos de las últimas horas,
--   así que sí es aceptable que esté atrasado hasta un día. Lo haría un
--   trabajo programado, la API antes de servir el reporte, o el
--   bibliotecario con un botón "Actualizar".
--   Lo que NO tiene sentido: refrescarla después de cada préstamo. Cada
--   REFRESH cuesta lo mismo que la consulta original, y no se ganaría nada.
--   La diferencia con A3: el catálogo (disponibles) tiene que estar al día
--   al instante; el top 20 puede esperar. Por eso allá trigger y aquí vista
--   materializada.
-- ---------------------------------------------------------------------
