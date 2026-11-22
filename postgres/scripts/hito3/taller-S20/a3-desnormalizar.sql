-- =====================================================================
-- a3-desnormalizar.sql  ·  S20, Parte A3: guardar "disponibles" en libro
-- 750006C Bases de Datos · Universidad del Valle · Grupo 9
-- Integrantes: Eisin Yeiner Tobar Bravo · Giovanny Mora Segura
--
-- Requisito: haber corrido S20-rendimiento.sql, a1-catalogo.sql y a2-indices.sql.
-- Uso (PowerShell, desde la carpeta del proyecto):
--   docker compose exec postgres psql -U curso -d curso -f /scripts/hito3/taller-S20/a3-desnormalizar.sql
--
-- Desnormalizar = aceptar redundancia A PROPÓSITO para que una consulta
-- frecuente sea más barata. Aquí se copia en libro un dato DERIVADO:
--   disponibles = ejemplares del libro − préstamos abiertos de esos ejemplares
-- Así el catálogo ya no tiene que recorrer los préstamos. El precio: cada
-- préstamo y cada devolución tiene que actualizar la copia, o la copia miente.
--
-- Re-ejecutable: al empezar quita lo que dejó una corrida anterior (la
-- columna, la vista y el préstamo simulado 400001).
-- =====================================================================

\set ON_ERROR_STOP on
\pset pager off
SET search_path TO rendimiento;

DROP VIEW IF EXISTS descuadre;
DELETE FROM prestamo WHERE id = 400001;
ALTER TABLE libro DROP COLUMN IF EXISTS disponibles;

-- ---------------------------------------------------------------------
-- (a) Predicción, ANTES de calcular nada
--   Cada libro i tiene 3 ejemplares: 3i-2, 3i-1 y 3i (tres números seguidos).
--   Los préstamos abiertos son uno por cada ejemplar múltiplo de 4:
--   15000 / 4 = 3750 préstamos abiertos.
--   Entre tres números seguidos hay A LO SUMO un múltiplo de 4 (los
--   múltiplos de 4 están separados por 4). Entonces ningún libro tiene dos
--   préstamos abiertos, y los 3750 caen en 3750 libros distintos:
--     3750 libros con 1 prestado  -> 3 - 1 = 2 disponibles
--     5000 - 3750 = 1250 libros sin prestar -> 3 disponibles
--   Predicción: 3750 libros con 2 y 1250 con 3.
-- ---------------------------------------------------------------------

\echo
\echo '== A3 (a). Agregar la columna como NOT NULL de una vez FALLA: la tabla ya tiene 5000 filas, y la columna nueva nace en NULL =='
DO $$
BEGIN
    ALTER TABLE rendimiento.libro ADD COLUMN disponibles smallint NOT NULL;
    RAISE NOTICE 'Se agregó (no debía pasar)';
EXCEPTION WHEN not_null_violation THEN
    RAISE NOTICE 'Falla, como se esperaba: %', SQLERRM;
END $$;

\echo
\echo '== A3 (a). Por eso el orden es: 1) agregar la columna, 2) llenarla, 3) ponerle NOT NULL y el CHECK =='
ALTER TABLE libro ADD COLUMN disponibles smallint;

\echo '-- Llenarla con un solo UPDATE que la calcula (esperado: UPDATE 5000)'
UPDATE libro l
SET    disponibles =
         (SELECT count(*) FROM ejemplar e WHERE e.isbn = l.isbn)
       - (SELECT count(*)
          FROM   prestamo p
          JOIN   ejemplar e ON e.id_ejemplar = p.id_ejemplar
          WHERE  e.isbn = l.isbn
            AND  p.fecha_devolucion IS NULL);

ALTER TABLE libro
    ALTER COLUMN disponibles SET NOT NULL,
    ADD CONSTRAINT libro_disponibles_check CHECK (disponibles >= 0);

\echo '-- Comprobar la predicción (esperado: 2 -> 3750 libros, 3 -> 1250 libros)'
SELECT disponibles, count(*) AS libros FROM libro GROUP BY disponibles ORDER BY disponibles;

\echo '-- El catálogo con la columna da lo mismo que en A1 (esperado: 83 con 2 y 28 con 3)'
SELECT disponibles, count(*) AS titulos
FROM   libro WHERE titulo LIKE 'Libro 12%'
GROUP BY disponibles ORDER BY disponibles;

-- ---------------------------------------------------------------------
-- (b) La consulta del catálogo usando la columna: ya no hay joins.
-- Se lee solo libro (5000 filas), sin tocar ejemplar ni prestamo.
-- ---------------------------------------------------------------------
\echo
\echo '== A3 (b). EXPLAIN ANALYZE del catálogo con la columna, corrida 1 de 3 =='
EXPLAIN ANALYZE
SELECT isbn, titulo, disponibles FROM libro WHERE titulo LIKE 'Libro 12%';

\echo '== A3 (b). Corrida 2 de 3 =='
EXPLAIN ANALYZE
SELECT isbn, titulo, disponibles FROM libro WHERE titulo LIKE 'Libro 12%';

\echo '== A3 (b). Corrida 3 de 3 =='
EXPLAIN ANALYZE
SELECT isbn, titulo, disponibles FROM libro WHERE titulo LIKE 'Libro 12%';

-- ---------------------------------------------------------------------
-- (c) La copia puede mentir. La vista descuadre compara lo GUARDADO con lo
-- CALCULADO y devuelve solo los libros donde no coinciden. Es la consulta
-- de verificación que toda desnormalización debe tener (pre-lectura, sec. 5).
-- ---------------------------------------------------------------------
\echo
\echo '== A3 (c). La vista descuadre (guardado frente a calculado) =='
CREATE VIEW descuadre AS
SELECT   l.isbn,
         l.titulo,
         l.disponibles                         AS guardado,
         count(e.id_ejemplar) - count(p.id)    AS calculado
FROM     libro l
JOIN     ejemplar e    ON e.isbn = l.isbn
LEFT JOIN prestamo p   ON p.id_ejemplar = e.id_ejemplar
                      AND p.fecha_devolucion IS NULL
GROUP BY l.isbn, l.titulo, l.disponibles
HAVING   l.disponibles <> count(e.id_ejemplar) - count(p.id);

\echo '-- Recién calculada, la copia está bien (esperado: 0 filas)'
SELECT * FROM descuadre;

\echo '-- Alguien registra un préstamo del ejemplar 1 (Libro 1) y OLVIDA actualizar libro.disponibles'
INSERT INTO prestamo VALUES (400001, 1, '1000000001', CURRENT_DATE, CURRENT_DATE + 14, NULL);

\echo '-- La vista encuentra el problema (esperado: 1 fila, Libro 1: guardado 3, calculado 2)'
SELECT * FROM descuadre;

\echo '-- Arreglo: se recalcula la copia de los libros descuadrados (esperado: UPDATE 1)'
UPDATE libro l
SET    disponibles = d.calculado
FROM   descuadre d
WHERE  d.isbn = l.isbn;

\echo '-- Después del arreglo (esperado: 0 filas)'
SELECT * FROM descuadre;

-- ---------------------------------------------------------------------
-- (d) ¿Qué mecanismo mantendría disponibles al día en el proyecto?
--
--   Un TRIGGER sobre prestamo: al insertar un préstamo abierto, resta 1 en
--   el libro del ejemplar; al registrar la devolución (UPDATE que llena
--   fecha_devolucion), suma 1. Lo ejecuta el propio DBMS en cada INSERT o
--   UPDATE, venga de la API, de psql o de una carga masiva: nadie se lo
--   puede saltar. Es trabajo del Hito 4 (M6); mientras tanto, la vista
--   descuadre queda como verificación.
--
--   - "La aplicación lo actualiza en la misma transacción" funciona solo si
--     hay UN programa que escribe: un INSERT hecho a mano en psql (como el
--     de arriba) o una carga masiva se lo salta, y la copia miente.
--   - Una vista materializada NO sirve aquí: se atrasa hasta el próximo
--     REFRESH, y el catálogo tiene que estar al día en el momento de prestar
--     (si dice "1 disponible" y no hay, el lector va al estante en vano).
--   - Una columna generada tampoco: solo puede usar columnas de la MISMA
--     fila, y disponibles depende de filas de otras tablas.
-- ---------------------------------------------------------------------
