-- =====================================================================
-- a1-catalogo.sql  ·  S20, Parte A1: la consulta del catálogo, en 3FN y sin índices
-- 750006C Bases de Datos · Universidad del Valle · Grupo 9
-- Integrantes: Eisin Yeiner Tobar Bravo · Giovanny Mora Segura
--
-- Requisito: haber corrido S20-rendimiento.sql justo antes. Ese script
-- borra y recrea el esquema "rendimiento" SIN índices extra (solo los de
-- las PK), que es el punto de partida de esta medición.
--
-- Uso (PowerShell, desde la carpeta del proyecto):
--   docker compose exec postgres psql -U curso -d curso -f /scripts/hito3/taller-S20/S20-rendimiento.sql
--   docker compose exec postgres psql -U curso -d curso -f /scripts/hito3/taller-S20/a1-catalogo.sql
--
-- La consulta del catálogo: para cada título que coincide con la búsqueda,
-- cuántos ejemplares hay disponibles (ejemplares menos préstamos abiertos).
--
-- (a) ¿Por qué LEFT JOIN y count(p.id)?
--   - LEFT JOIN: un ejemplar SIN préstamo abierto no tiene pareja en
--     prestamo. Con JOIN se perdería esa fila, y justo esos son los
--     ejemplares disponibles. LEFT JOIN la conserva, con p.id en NULL.
--   - count(p.id): cuenta solo los préstamos abiertos (los NULL no cuentan).
--     Con count(*) la fila del ejemplar sin préstamo contaría 1, y todo
--     libro saldría con 0 disponibles. (Es la trampa de S15, sección 4.5.)
--   - La condición fecha_devolucion IS NULL va en el ON, no en el WHERE: si
--     fuera en el WHERE, descartaría las filas con p en NULL y el LEFT JOIN
--     volvería a comportarse como un JOIN.
-- =====================================================================

\set ON_ERROR_STOP on
\pset pager off
SET search_path TO rendimiento;

\echo
\echo '== Punto de partida: índices que existen (esperado: solo los 4 de las PK) =='
SELECT indexname FROM pg_indexes WHERE schemaname = 'rendimiento' ORDER BY indexname;

\echo
\echo '== A1. El resultado: títulos que coinciden y cuántos ejemplares disponibles tienen (esperado: 83 con 2 y 28 con 3; total 111) =='
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

-- (b) Medir: EXPLAIN ANALYZE ejecuta la consulta y dice cuánto tardó cada
-- parte del plan. Se corre tres veces porque la primera suele ser más lenta
-- (los datos todavía no están en memoria); se anota el tiempo típico.
\echo
\echo '== A1 (b) y (c). EXPLAIN ANALYZE, corrida 1 de 3 =='
EXPLAIN ANALYZE
SELECT l.isbn, l.titulo, count(e.id_ejemplar) - count(p.id) AS disponibles
FROM   libro l
JOIN   ejemplar e      ON e.isbn = l.isbn
LEFT JOIN prestamo p   ON p.id_ejemplar = e.id_ejemplar
                      AND p.fecha_devolucion IS NULL
WHERE  l.titulo LIKE 'Libro 12%'
GROUP BY l.isbn, l.titulo;

\echo
\echo '== A1 (b). EXPLAIN ANALYZE, corrida 2 de 3 =='
EXPLAIN ANALYZE
SELECT l.isbn, l.titulo, count(e.id_ejemplar) - count(p.id) AS disponibles
FROM   libro l
JOIN   ejemplar e      ON e.isbn = l.isbn
LEFT JOIN prestamo p   ON p.id_ejemplar = e.id_ejemplar
                      AND p.fecha_devolucion IS NULL
WHERE  l.titulo LIKE 'Libro 12%'
GROUP BY l.isbn, l.titulo;

\echo
\echo '== A1 (b). EXPLAIN ANALYZE, corrida 3 de 3 =='
EXPLAIN ANALYZE
SELECT l.isbn, l.titulo, count(e.id_ejemplar) - count(p.id) AS disponibles
FROM   libro l
JOIN   ejemplar e      ON e.isbn = l.isbn
LEFT JOIN prestamo p   ON p.id_ejemplar = e.id_ejemplar
                      AND p.fecha_devolucion IS NULL
WHERE  l.titulo LIKE 'Libro 12%'
GROUP BY l.isbn, l.titulo;

-- (c) Qué buscar en el plan (se lee de adentro hacia afuera):
--   el nodo  Seq Scan on prestamo p  con  Filter: (fecha_devolucion IS NULL)
--   y  Rows Removed by Filter: 300000. Recorre los 303 750 préstamos para
--   quedarse con los 3 750 abiertos, y se lleva la mayor parte del tiempo.
